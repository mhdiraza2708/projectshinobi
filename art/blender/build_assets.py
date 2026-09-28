"""Models Project Shinobi's environment props and gear in Blender and
exports them as glTF with textures.

Run with either:
    blender --background --python art/blender/build_assets.py -- [options]
    python art/blender/build_assets.py [options]        # needs `pip install -r art/blender/requirements.txt`

Options:
    --out DIR        output directory (default: game/assets/models)
    --only NAME      build a single asset (e.g. gate); repeatable
    --preview DIR    also render a preview image of each asset
    --save-blend     also write a .blend next to each model for hand editing

Everything is modelled in code: bevelled parts, world-scale UVs on the
baked, tileable materials from textures.py (run that first), soft normals on
foliage. Models are written as .gltf + .bin and share the textures in
game/assets/textures/ rather than embedding copies.

Characters are not modelled here: they come from VRoid Studio as .vrm files
(see docs/CHARACTERS.md).

Conventions: 1 unit = 1 metre, Z up, the front of a prop faces -Y (which
becomes Godot's +Z after export... see Island.gd for placement), origins sit
on the ground.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy  # noqa: E402  (must come before bmesh/mathutils when bpy is a pip module)
from mathutils import Vector  # noqa: E402

import kit  # noqa: E402
from kit import MeshBuilder, empty, material as M, rng  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO_ROOT / "game" / "assets" / "models"


# --------------------------------------------------------------------------
# Shared parts
# --------------------------------------------------------------------------

def bent_box(mb: MeshBuilder, mat, center, length: float, height: float, depth: float, lift: float,
		segments=24, texel=1.0, power=2.6):
	"""A beam along X whose ends sweep upward by `lift` (torii lintels)."""
	cx, cy, cz = center
	verts, faces = [], []
	for i in range(segments + 1):
		t = i / segments * 2 - 1
		x = cx + t * length / 2
		z0 = cz + lift * abs(t) ** power
		for dy, dz in ((-depth / 2, -height / 2), (depth / 2, -height / 2), (depth / 2, height / 2), (-depth / 2, height / 2)):
			verts.append((x, cy + dy, z0 + dz))
	for i in range(segments):
		a, b = i * 4, (i + 1) * 4
		for k in range(4):
			k2 = (k + 1) % 4
			faces.append((a + k, a + k2, b + k2, b + k))
	faces.append((0, 3, 2, 1))
	e = segments * 4
	faces.append((e, e + 1, e + 2, e + 3))
	mb.raw(mat, verts, faces, texel=texel, smooth=False)


def gable_roof(mb: MeshBuilder, mat, trim, width: float, depth: float, eave_z: float, pitch_deg: float,
		overhang: float, sori: float = 0.15, thickness: float = 0.14, texel=1.4) -> float:
	"""Two roof slopes along X meeting at a ridge. The eaves and corners
	sweep upward (sori) like a Japanese roof. Returns the ridge height."""
	pitch = math.radians(pitch_deg)
	half = depth / 2 + overhang
	rise = half * math.tan(pitch)
	nx, ny = 20, 8
	w = width / 2 + overhang
	for side in (-1, 1):
		top, bot = [], []
		for j in range(ny + 1):
			s = j / ny            # 0 at ridge, 1 at eave
			for i in range(nx + 1):
				t = i / nx * 2 - 1
				x = t * w
				y = side * s * half
				z = eave_z + rise * (1 - s) - sori * math.sin(s * math.pi) * 0.6 + sori * (abs(t) ** 3) * s * 1.6
				top.append((x, y, z))
				bot.append((x, y, z - thickness))
		verts = top + bot
		n = (nx + 1) * (ny + 1)
		faces = []
		for j in range(ny):
			for i in range(nx):
				a = j * (nx + 1) + i
				q = (a, a + 1, a + nx + 2, a + nx + 1)
				faces.append(q if side > 0 else q[::-1])
				faces.append(tuple(v + n for v in (q[::-1] if side > 0 else q)))
		for i in range(nx):
			a = ny * (nx + 1) + i
			faces.append((a, a + n, a + n + 1, a + 1) if side > 0 else (a + 1, a + n + 1, a + n, a))
		for j in range(ny):
			for i in (0, nx):
				a = j * (nx + 1) + i
				b = a + nx + 1
				f = (a, b, b + n, a + n)
				faces.append(f if (i == 0) == (side > 0) else f[::-1])
		_roof_slope(mb, mat, verts, faces, texel)
	ridge_z = eave_z + rise + 0.05
	mb.cyl(mat, (0, 0, ridge_z), 0.16, 0.16, width + overhang * 2 + 0.2, rot=(0, math.pi / 2, 0), segments=12, texel=texel)
	for sx in (-1, 1):
		mb.box(trim, (sx * (w + 0.12), 0, ridge_z + 0.12), (0.22, 0.42, 0.5), bevel=0.04, texel=0.6)
	return ridge_z


def _roof_slope(mb: MeshBuilder, mat, verts, faces, texel):
	"""Roof slopes get UVs with the tile rows running along the ridge."""
	bm, uvl = mb._scratch()
	vs = [bm.verts.new(Vector(v)) for v in verts]
	for f in faces:
		try:
			bm.faces.new([vs[i] for i in f])
		except ValueError:
			pass
	for f in bm.faces:
		for l in f.loops:
			p = l.vert.co
			l[uvl].uv = (p.x / texel, abs(p.y) / texel * 1.1)
	mb._commit(bm, uvl, mat, kit.xform(), "keep", texel, True)


def rope(mb: MeshBuilder, mat, a, b, sag: float, radius: float, n=24, texel=0.12) -> list:
	pts = []
	for i in range(n + 1):
		t = i / n
		p = Vector(a).lerp(Vector(b), t)
		p.z -= sag * 4 * t * (1 - t)
		pts.append(p)
	mb.tube_path(mat, pts, radius, segments=10, texel=texel,
		radius_fn=lambda t: radius * (0.55 + 0.45 * math.sin(t * math.pi) ** 0.5))
	return pts


def shide(mb: MeshBuilder, mat, top, height=0.45, width=0.12, steps=4):
	"""A zigzag paper streamer hanging from a shrine rope."""
	x, y, z = top
	verts, faces = [], []
	h = height / steps
	for i in range(steps + 1):
		off = (width * 0.5) * (1 if i % 2 == 0 else -1)
		verts += [(x + off - width * 0.5, y - 0.004 * i, z - h * i), (x + off + width * 0.5, y - 0.004 * i, z - h * i)]
	for i in range(steps):
		a = i * 2
		faces.append((a, a + 1, a + 3, a + 2))
	mb.raw(mat, verts, faces, texel=0.5, smooth=False)


def helix(radius: float, z0: float, z1: float, turns: float, n=80) -> list:
	return [Vector((radius * math.cos(2 * math.pi * turns * i / n), radius * math.sin(2 * math.pi * turns * i / n),
		z0 + (z1 - z0) * i / n)) for i in range(n + 1)]


def paint_tops(mb: MeshBuilder, from_mat, to_mat, min_z: float) -> None:
	"""Gives upward-facing faces another material (moss, snow)."""
	src = mb._mat(from_mat)
	dst = mb._mat(to_mat)
	mb.bm.normal_update()
	for f in mb.bm.faces:
		if f.material_index == src and f.normal.z > min_z:
			f.material_index = dst


# --------------------------------------------------------------------------
# Props
# --------------------------------------------------------------------------

def build_training_dummy() -> None:
	"""A wooden training post: cross-footed stand, rope-bound post, dowel
	arms and a straw-wrapped head."""
	root = empty("TrainingDummy")
	mb = MeshBuilder("TrainingDummyMesh")
	wood, dark, straw = M("wood"), M("wood_dark"), M("straw")
	for rot in (0.0, math.pi / 2):
		mb.box(dark, (0, 0, 0.07), (0.95, 0.17, 0.14), rot=(0, 0, rot), bevel=0.02, texel=0.8)
	mb.cyl(wood, (0, 0, 0.95), 0.19, 0.17, 1.75, segments=16, texel=0.9)
	for z0, z1 in ((0.52, 0.76), (1.2, 1.42)):
		mb.tube_path(straw, helix(0.2, z0, z1, 3.5), 0.022, segments=6, texel=0.1)
	mb.sphere(straw, (0, 0, 1.94), 0.29, scale=(1, 1, 1.15), subdiv=3, texel=0.35, displace=0.06, freq=3.0, seed=4)
	mb.tube_path(straw, helix(0.24, 1.72, 1.78, 2.0), 0.025, segments=6, texel=0.1)
	for x, z, yaw in ((-0.1, 1.44, -0.35), (0.1, 1.44, 0.35), (0.0, 1.05, 0.0)):
		mb.cyl(dark, (x + math.sin(yaw) * 0.28, -math.cos(yaw) * 0.28, z), 0.042, 0.036, 0.56,
			rot=(math.pi / 2, 0, yaw), segments=8, texel=0.5)
	mb.build(root)


def build_rock() -> None:
	root = empty("Rock")
	mb = MeshBuilder("RockMesh")
	rock, moss = M("rock"), M("grass", tint=(0.75, 0.85, 0.65))
	mb.sphere(rock, (0, 0, 0.3), 0.66, scale=(1.3, 1.0, 0.72), subdiv=4, texel=1.6, displace=0.32, freq=1.3, seed=3,
		flatten_below=-0.28)
	mb.sphere(rock, (0.72, 0.32, 0.12), 0.34, scale=(1.1, 1.0, 0.8), subdiv=3, texel=1.6, displace=0.3, freq=1.6, seed=9,
		flatten_below=-0.12)
	paint_tops(mb, rock, moss, 0.82)
	mb.build(root, sharp_angle=55)


def _pine(name: str, snowy: bool) -> None:
	"""A pine of drooping, ragged tiers: each tier's rim alternates long
	drooping tips and short notches, tiers are turned and sized unevenly."""
	root = empty(name)
	mb = MeshBuilder(name + "Mesh")
	bark, needles = M("bark"), M("pine_needles")
	cap = M("snow") if snowy else needles
	r = rng(17 if not snowy else 23)
	mb.cyl(bark, (0, 0, 1.6), 0.25, 0.09, 3.2, segments=12, texel=1.0)
	for i in range(5):
		a = 2 * math.pi * i / 5 + r.uniform(-0.3, 0.3)
		mb.cyl(bark, (math.cos(a) * 0.22, math.sin(a) * 0.22, 0.12), 0.12, 0.03, 0.55,
			rot=(0, math.radians(55), a), segments=6, texel=0.8)
	tiers = [(1.35, 1.8, 1.25), (2.0, 1.55, 1.15), (2.6, 1.3, 1.05), (3.15, 1.05, 0.95), (3.65, 0.82, 0.85),
		(4.1, 0.6, 0.8), (4.5, 0.4, 0.75)]
	for k, (z0, rad, h) in enumerate(tiers):
		n = 22
		rad *= r.uniform(0.92, 1.08)
		spin = r.uniform(0, 2 * math.pi)
		ox, oy = r.uniform(-0.06, 0.06), r.uniform(-0.06, 0.06)
		apex = (ox, oy, z0 + h)
		inner, rim = [], []
		for i in range(n):
			a = 2 * math.pi * i / n + spin
			inner.append((ox + math.cos(a) * rad * 0.45, oy + math.sin(a) * rad * 0.45, z0 + h * 0.42 + r.uniform(-0.04, 0.04)))
			tip = i % 2 == 0
			rr = rad * (r.uniform(1.0, 1.18) if tip else r.uniform(0.72, 0.84))
			droop = 0.32 * rad if tip else 0.12 * rad
			rim.append((ox + math.cos(a) * rr, oy + math.sin(a) * rr, z0 - droop + r.uniform(-0.05, 0.05)))
		# Upper cone (snow sits here on a snowy pine), then the ragged skirt,
		# then a shallow underside.
		mb.raw(cap, [apex] + inner, [(0, 1 + i, 1 + (i + 1) % n) for i in range(n)], texel=1.3,
			soft_center=(ox, oy, z0 + h * 0.1))
		verts = inner + rim + [(ox, oy, z0 + 0.1)]
		faces = []
		for i in range(n):
			i2 = (i + 1) % n
			faces.append((i, n + i, i2))
			faces.append((i2, n + i, n + i2))
			faces.append((2 * n, n + i2, n + i))
		mb.raw(needles, verts, faces, texel=1.3, soft_center=(ox, oy, z0 + h * 0.1))
	mb.cyl(cap, (0, 0, 5.35), 0.18, 0.0, 0.6, segments=8, texel=1.0)
	if snowy:
		# Snow settles on the flatter parts of each skirt too.
		paint_tops(mb, needles, cap, 0.64)
	mb.build(root)


def build_pine() -> None:
	_pine("Pine", False)


def build_snow_pine() -> None:
	_pine("SnowPine", True)


def _broadleaf(name: str, foliage: str, seed: int, spread=1.0) -> None:
	root = empty(name)
	mb = MeshBuilder(name + "Mesh")
	bark, leaves = M("bark"), M(foliage)
	r = rng(seed)
	mb.cyl(bark, (0, 0, 1.3), 0.27, 0.15, 2.6, segments=12, texel=1.0)
	for i in range(4):
		a = 2 * math.pi * i / 4 + r.uniform(-0.3, 0.3)
		mb.cyl(bark, (math.cos(a) * 0.24, math.sin(a) * 0.24, 0.12), 0.12, 0.03, 0.5,
			rot=(0, math.radians(55), a), segments=6, texel=0.8)
	arms = []
	for i in range(3):
		a = 2 * math.pi * i / 3 + r.uniform(-0.3, 0.3)
		start = Vector((0, 0, 2.2 + i * 0.15))
		mid = start + Vector((math.cos(a) * 0.6, math.sin(a) * 0.6, 0.55))
		end = start + Vector((math.cos(a) * 1.15 * spread, math.sin(a) * 1.15 * spread, 0.95))
		pts = [start.lerp(mid, t * 2) if t < 0.5 else mid.lerp(end, (t - 0.5) * 2) for t in (0, 0.25, 0.5, 0.75, 1.0)]
		mb.tube_path(bark, pts, 0.1, segments=7, texel=0.8, radius_fn=lambda t: 0.11 * (1 - t * 0.6))
		arms.append(end)
	lumps = [(Vector((0, 0, 3.75)), 1.25)] + [(e + Vector((0, 0, 0.2)), r.uniform(0.95, 1.15)) for e in arms]
	for i in range(4):
		a = 2 * math.pi * (i + 0.5) / 4
		lumps.append((Vector((math.cos(a) * 0.9 * spread, math.sin(a) * 0.9 * spread, 3.3 + r.uniform(-0.2, 0.3))), r.uniform(0.8, 1.0)))
	# A few lumps hanging lower round the sides break the mushroom outline.
	for i in range(5):
		a = 2 * math.pi * (i + 0.3) / 5 + r.uniform(-0.2, 0.2)
		lumps.append((Vector((math.cos(a) * 1.25 * spread, math.sin(a) * 1.25 * spread, 2.85 + r.uniform(-0.15, 0.2))),
			r.uniform(0.55, 0.75)))
	heart = (0.0, 0.0, 3.25)
	for k, (c, rad) in enumerate(lumps):
		mb.sphere(leaves, tuple(c), rad, scale=(1.0 * spread, 1.0 * spread, 0.85), subdiv=3, texel=1.5,
			displace=0.3, freq=2.2, seed=seed + k, soft=True, soft_origin=heart)
	mb.build(root)


def build_broadleaf() -> None:
	_broadleaf("Broadleaf", "leaves", 21)


def build_maple() -> None:
	_broadleaf("Maple", "maple", 33, spread=1.12)


def build_dead_tree() -> None:
	root = empty("DeadTree")
	mb = MeshBuilder("DeadTreeMesh")
	bark = M("bark", tint=(0.62, 0.6, 0.58))
	r = rng(5)
	mb.cyl(bark, (0, 0, 1.6), 0.28, 0.08, 3.2, segments=10, texel=1.0)

	def branch(start: Vector, direction: Vector, length: float, radius: float, depth: int):
		pts = [start]
		d = direction.normalized()
		for i in range(4):
			d = (d + Vector((r.uniform(-0.3, 0.3), r.uniform(-0.3, 0.3), r.uniform(-0.1, 0.25)))).normalized()
			pts.append(pts[-1] + d * length / 4)
		mb.tube_path(bark, pts, radius, segments=6, texel=0.8, radius_fn=lambda t: radius * (1 - t * 0.8))
		if depth > 0:
			for _ in range(2):
				branch(pts[r.randint(2, 3)], d + Vector((r.uniform(-1, 1), r.uniform(-1, 1), 0.4)), length * 0.55, radius * 0.5, depth - 1)

	for i in range(5):
		a = 2 * math.pi * i / 5 + r.uniform(-0.4, 0.4)
		branch(Vector((0, 0, r.uniform(1.8, 3.0))), Vector((math.cos(a), math.sin(a), r.uniform(0.4, 1.0))), r.uniform(1.2, 1.8), 0.08, 1)
	mb.build(root)


def build_bamboo() -> None:
	root = empty("Bamboo")
	mb = MeshBuilder("BambooMesh")
	stalk_mat, node_mat, leaves = M("bamboo"), M("bamboo", tint=(0.8, 0.85, 0.7)), M("leaves", tint=(0.95, 1.1, 0.85))
	r = rng(9)
	for s in range(7):
		a = r.uniform(0, 2 * math.pi)
		d = r.uniform(0.0, 0.55)
		base = Vector((math.cos(a) * d, math.sin(a) * d, 0))
		lean = Vector((r.uniform(-0.05, 0.05), r.uniform(-0.05, 0.05), 1)).normalized()
		tilt = (math.atan2(-lean.y, lean.z), math.atan2(lean.x, lean.z), 0)
		h = r.uniform(5.0, 7.0)
		seg = 0.85
		radius = r.uniform(0.045, 0.06)
		k = 0
		while k * seg < h:
			mb.cyl(stalk_mat, tuple(base + lean * (k * seg + seg / 2)), radius, radius * 0.97, seg - 0.03, rot=tilt,
				segments=8, texel=0.6)
			mb.cyl(node_mat, tuple(base + lean * ((k + 1) * seg)), radius * 1.18, radius * 1.18, 0.045, rot=tilt,
				segments=8, texel=0.3)
			k += 1
		for j in range(5):
			z = h * (0.55 + 0.09 * j)
			ang = r.uniform(0, 2 * math.pi)
			c = base + lean * z + Vector((math.cos(ang), math.sin(ang), 0)) * 0.35
			mb.sphere(leaves, tuple(c), 0.45, scale=(1.3, 0.55, 0.35), rot=(0, r.uniform(-0.4, 0.4), ang),
				subdiv=2, texel=0.8, displace=0.25, freq=2.5, seed=s * 10 + j, soft=True)
	mb.build(root)


def _torii(mb: MeshBuilder, broken=False) -> None:
	red, black = M("red_lacquer"), M("black_lacquer")
	r = rng(8)
	for x in (-2.0, 2.0):
		mb.cyl(black, (x, 0, 0.2), 0.27, 0.27, 0.4, segments=20, texel=0.8, bevel=0.02)
		if broken and x > 0:
			mb.cyl(red, (x, 0, 1.15), 0.21, 0.2, 1.5, segments=20, texel=1.0)
			verts = [(x, 0, 1.9 + r.uniform(0.0, 0.25))]
			verts += [(x + math.cos(a) * 0.2, math.sin(a) * 0.2, 1.9 + r.uniform(-0.25, 0.05))
				for a in [2 * math.pi * i / 12 for i in range(12)]]
			faces = [(0, 1 + i, 1 + (i + 1) % 12) for i in range(12)]
			mb.raw(M("wood"), verts, faces, texel=0.5, smooth=False)
			continue
		mb.cyl(red, (x, 0, 2.2), 0.21, 0.18, 3.8, segments=20, texel=1.0)
		mb.cyl(black, (x, 0, 4.06), 0.23, 0.23, 0.12, segments=20, texel=0.8)
	if not broken:
		mb.box(red, (0, 0, 3.35), (5.1, 0.2, 0.3), bevel=0.02, texel=1.0)
		for x in (-2.33, 2.33):
			mb.box(black, (x, 0, 3.35), (0.1, 0.28, 0.16), bevel=0.01, texel=0.3)
		mb.box(red, (0, 0, 3.75), (0.26, 0.22, 0.55), bevel=0.015, texel=0.6)
		mb.box(black, (0, -0.13, 3.78), (0.46, 0.05, 0.62), bevel=0.01, texel=0.6)
		mb.box(M("plaster", tint=(0.95, 0.85, 0.55)), (0, -0.16, 3.78), (0.36, 0.02, 0.5), texel=0.5)
		bent_box(mb, red, (0, 0, 4.14), 5.7, 0.3, 0.34, 0.2, texel=1.0)
		bent_box(mb, black, (0, 0, 4.38), 6.3, 0.2, 0.44, 0.34, texel=1.0)
	else:
		mb.box(red, (-0.4, 0, 2.6), (4.8, 0.2, 0.3), rot=(0, math.radians(-24), 0), bevel=0.02, texel=1.0)
		bent_box(mb, red, (1.1, -1.7, 0.16), 5.7, 0.3, 0.34, 0.2, texel=1.0)
		bent_box(mb, black, (1.1, -1.7, 0.4), 6.3, 0.2, 0.44, 0.34, texel=1.0)
		mb.sphere(M("rock"), (2.6, 0.7, 0.12), 0.3, scale=(1.2, 1, 0.7), subdiv=2, displace=0.3, seed=2, texel=1.2)


def build_gate() -> None:
	"""A myōjin-style torii: lacquered pillars on black bases, a wedged tie
	beam, a centre strut with a plaque, and the upswept double lintel."""
	root = empty("Gate")
	mb = MeshBuilder("GateMesh")
	_torii(mb)
	mb.build(root)


def build_gate_broken() -> None:
	root = empty("GateBroken")
	mb = MeshBuilder("GateBrokenMesh")
	_torii(mb, broken=True)
	mb.build(root)


def build_lantern() -> None:
	"""A kasuga-style stone lantern (tōrō): hexagonal base, pole, platform,
	a light box with glowing paper windows, a curled roof and a jewel."""
	root = empty("Lantern")
	mb = MeshBuilder("LanternMesh")
	stone = M("rock", tint=(1.05, 1.05, 1.02))
	paper = M("shoji", emission=(1.0, 0.72, 0.38), name="lantern_paper")
	mb.prism(stone, (0, 0, 0.08), 0.36, 0.16, texel=0.8, bevel=0.012)
	mb.prism(stone, (0, 0, 0.22), 0.28, 0.12, top_radius=0.2, texel=0.8)
	mb.cyl(stone, (0, 0, 0.6), 0.1, 0.09, 0.66, segments=12, texel=0.6)
	mb.cyl(stone, (0, 0, 0.62), 0.115, 0.115, 0.05, segments=12, texel=0.6)
	mb.prism(stone, (0, 0, 0.99), 0.22, 0.12, top_radius=0.3, texel=0.8, bevel=0.01)
	mb.prism(stone, (0, 0, 1.2), 0.23, 0.3, texel=0.8)
	apothem = 0.23 * math.cos(math.pi / 6)
	for k in (0, 2, 4):
		a = math.pi / 6 + k * math.pi / 3
		mb.box(paper, (math.cos(a) * (apothem + 0.004), math.sin(a) * (apothem + 0.004), 1.2), (0.02, 0.15, 0.19),
			rot=(0, 0, a), texel=0.25)
	# Roof: six corners curling up, the edges sagging between them.
	rim = []
	for i in range(12):
		a = 2 * math.pi * i / 12
		corner = i % 2 == 0
		rr = 0.44 if corner else 0.38
		rim.append((math.cos(a) * rr, math.sin(a) * rr, 1.4 + (0.07 if corner else 0.0)))
	verts = [(0, 0, 1.62)] + rim + [(0, 0, 1.34)] + [(x * 0.9, y * 0.9, z - 0.06) for x, y, z in rim]
	faces = []
	for i in range(12):
		i2 = (i + 1) % 12
		faces.append((0, 1 + i, 1 + i2))
		faces.append((13, 14 + i2, 14 + i))
		faces.append((1 + i, 14 + i, 14 + i2, 1 + i2))
	mb.raw(stone, verts, faces, texel=0.8, smooth=False)
	mb.cyl(stone, (0, 0, 1.65), 0.06, 0.05, 0.05, segments=10, texel=0.4)
	mb.sphere(stone, (0, 0, 1.72), 0.07, scale=(1, 1, 1.25), subdiv=2, texel=0.4)
	mb.cyl(stone, (0, 0, 1.8), 0.025, 0.0, 0.06, segments=8, texel=0.4)
	mb.build(root, sharp_angle=35)


def build_house() -> None:
	"""A timber house: stone footing, plank floor and porch, shoji front,
	plaster and plank walls, and a curved tiled roof."""
	root = empty("House")
	mb = MeshBuilder("HouseMesh")
	stone, wood, dark, plaster, shoji = M("stone_blocks"), M("wood"), M("wood_dark"), M("plaster"), M("shoji")
	roof = M("roof_tiles")
	w, d = 6.0, 4.4
	mb.box(stone, (0, 0, 0.25), (w + 0.4, d + 0.4, 0.5), bevel=0.03, texel=1.5)
	mb.box(wood, (0, 0, 0.54), (w + 0.2, d + 0.2, 0.08), texel=2.0)
	for x in (-w / 2, -w / 4, 0, w / 4, w / 2):
		for y in (-d / 2, d / 2):
			mb.box(dark, (x, y, 1.9), (0.18, 0.18, 2.8), bevel=0.01, texel=1.0)
	for y in (-d / 4, d / 4):
		for x in (-w / 2, w / 2):
			mb.box(dark, (x, y, 1.9), (0.18, 0.18, 2.8), bevel=0.01, texel=1.0)
	for i in range(4):
		mb.box(shoji, (-w / 2 + w / 8 + i * w / 4, -d / 2, 1.55), (w / 4 - 0.18, 0.05, 1.9), texel=1.9)
	mb.box(plaster, (0, -d / 2 + 0.02, 2.85), (w, 0.08, 0.55), texel=1.5)
	mb.box(wood, (0, d / 2, 1.05), (w, 0.08, 0.9), texel=1.5)
	mb.box(plaster, (0, d / 2, 2.35), (w, 0.08, 1.7), texel=1.5)
	for x in (-w / 2, w / 2):
		mb.box(wood, (x, 0, 1.05), (0.08, d, 0.9), texel=1.5)
		mb.box(plaster, (x, 0, 2.35), (0.08, d, 1.7), texel=1.5)
	for z, h in ((0.64, 0.12), (2.55, 0.14), (3.18, 0.16)):
		mb.box(dark, (0, -d / 2, z), (w + 0.2, 0.2, h), texel=1.2)
		mb.box(dark, (0, d / 2, z), (w + 0.2, 0.2, h), texel=1.2)
		mb.box(dark, (-w / 2, 0, z), (0.2, d, h), texel=1.2)
		mb.box(dark, (w / 2, 0, z), (0.2, d, h), texel=1.2)
	for x in (-w / 2, w / 2):
		mb.raw(plaster, [(x, -d / 2, 3.26), (x, d / 2, 3.26), (x, 0, 4.55)], [(0, 1, 2)], texel=1.5, smooth=False)
	mb.box(wood, (0, -d / 2 - 0.6, 0.5), (w + 0.4, 1.1, 0.08), texel=2.0)
	for x in (-w / 2 - 0.1, 0.0, w / 2 + 0.1):
		mb.box(dark, (x, -d / 2 - 1.05, 1.85), (0.14, 0.14, 2.7), bevel=0.01, texel=1.0)
	mb.box(stone, (0, -d / 2 - 1.4, 0.15), (1.2, 0.5, 0.3), bevel=0.03, texel=1.0)
	gable_roof(mb, roof, dark, w, d + 1.2, 3.28, 30, 0.55, sori=0.18)
	mb.build(root)


def build_shrine() -> None:
	"""A shrine hall on a raised floor: red pillars, lattice doors, a curved
	copper-green roof with crossed chigi and ridge logs, a sacred rope with
	paper streamers, and an offering box."""
	root = empty("Shrine")
	mb = MeshBuilder("ShrineMesh")
	dark, wood, red = M("wood_dark"), M("wood"), M("red_lacquer")
	stone = M("stone_blocks")
	lattice = M("shoji", tint=(0.72, 0.6, 0.48))
	roof = M("roof_tiles", tint=(0.62, 0.95, 0.8))
	rope_mat = M("straw")
	paper = M("plaster", tint=(1.05, 1.05, 1.05))
	w, d = 5.0, 4.0
	mb.box(stone, (0, 0, 0.2), (w + 1.2, d + 1.2, 0.4), bevel=0.03, texel=1.5)
	mb.box(dark, (0, 0, 0.7), (w + 0.8, d + 0.8, 0.6), bevel=0.02, texel=1.5)
	for i in range(3):
		mb.box(wood, (0, -d / 2 - 0.6 - i * 0.32, (3 - i) * 0.15), (2.0, 0.34, (3 - i) * 0.3), bevel=0.015, texel=1.2)
	for x in (-w / 2, -w / 6, w / 6, w / 2):
		for y in (-d / 2, d / 2):
			mb.cyl(red, (x, y, 2.3), 0.16, 0.16, 2.6, segments=16, texel=1.0)
	mb.box(lattice, (0, -d / 2 + 0.05, 2.1), (w - 0.4, 0.06, 2.0), texel=1.6)
	mb.box(wood, (0, d / 2 - 0.05, 2.1), (w - 0.3, 0.06, 2.4), texel=1.5)
	for x in (-w / 2 + 0.05, w / 2 - 0.05):
		mb.box(wood, (x, 0, 2.1), (0.06, d - 0.3, 2.4), texel=1.5)
	for z in (3.45, 1.05):
		mb.box(red, (0, -d / 2, z), (w + 0.4, 0.24, 0.24), bevel=0.01, texel=1.2)
		mb.box(red, (0, d / 2, z), (w + 0.4, 0.24, 0.24), bevel=0.01, texel=1.2)
	for x in (-w / 2, w / 2):
		mb.raw(wood, [(x, -d / 2, 3.57), (x, d / 2, 3.57), (x, 0, 4.9)], [(0, 1, 2)], texel=1.5, smooth=False)
	ridge = gable_roof(mb, roof, dark, w, d + 1.2, 3.62, 34, 0.9, sori=0.3)
	for x in (-w / 2 - 0.85, w / 2 + 0.85):
		for side in (-1, 1):
			mb.box(dark, (x, side * 0.3, ridge + 0.35), (0.08, 0.14, 1.2), rot=(side * math.radians(38), 0, 0), bevel=0.01, texel=0.6)
	for x in (-1.5, -0.5, 0.5, 1.5):
		mb.cyl(dark, (x, 0, ridge + 0.22), 0.1, 0.1, 0.8, rot=(math.pi / 2, 0, 0), segments=10, texel=0.6)
	pts = rope(mb, rope_mat, (-w / 2 - 0.1, -d / 2 - 0.25, 3.25), (w / 2 + 0.1, -d / 2 - 0.25, 3.25), 0.35, 0.09)
	for t in (0.25, 0.5, 0.75):
		p = pts[int(t * (len(pts) - 1))]
		shide(mb, paper, (p.x, p.y - 0.02, p.z - 0.08))
	mb.box(wood, (0, -d / 2 - 1.75, 0.3), (1.1, 0.6, 0.6), bevel=0.02, texel=0.8)
	for i in range(5):
		mb.box(dark, (-0.4 + i * 0.2, -d / 2 - 1.75, 0.62), (0.06, 0.55, 0.05), texel=0.5)
	mb.build(root)


def build_pillar() -> None:
	"""A tall standing stone with carved bands and a dish on top (the game
	adds a glowing orb)."""
	root = empty("Pillar")
	mb = MeshBuilder("PillarMesh")
	blocks, rock = M("stone_blocks"), M("rock")
	mb.box(blocks, (0, 0, 0.3), (1.7, 1.7, 0.6), bevel=0.04, texel=1.2)
	mb.box(rock, (0, 0, 0.75), (1.35, 1.35, 0.3), bevel=0.03, texel=1.2)
	mb.cyl(rock, (0, 0, 3.2), 0.46, 0.38, 4.6, segments=8, texel=1.5, smooth=False)
	for z in (1.4, 5.0):
		mb.cyl(blocks, (0, 0, z), 0.52, 0.52, 0.22, segments=8, texel=1.0, smooth=False, bevel=0.02)
	mb.box(blocks, (0, 0, 5.75), (1.2, 1.2, 0.5), bevel=0.04, texel=1.0)
	mb.cyl(rock, (0, 0, 6.15), 0.45, 0.72, 0.3, segments=12, texel=1.0)
	mb.build(root)


def build_dam() -> None:
	"""An old stone dam: buttressed block wall, a lower spillway, a plank
	walkway with a rail, boulders at its foot."""
	root = empty("Dam")
	mb = MeshBuilder("DamMesh")
	blocks, dark, wood, rock = M("stone_blocks"), M("stone_blocks", tint=(0.8, 0.8, 0.8)), M("wood"), M("rock")
	rail = M("wood_dark")
	mb.box(blocks, (-12.5, 0, 5.0), (17.0, 4.0, 10.0), texel=3.0)
	mb.box(blocks, (12.5, 0, 5.0), (17.0, 4.0, 10.0), texel=3.0)
	mb.box(dark, (0, 0.3, 3.8), (8.0, 3.4, 7.6), texel=3.0)
	for x in (-19, -12, -5, 5, 12, 19):
		mb.box(dark, (x, -2.4, 4.6), (1.4, 1.2, 9.2), bevel=0.05, texel=3.0)
	for sign in (-1, 1):
		mb.box(wood, (sign * 12.5, 0, 10.1), (17.4, 4.4, 0.2), texel=2.0)
		for k in range(9):
			mb.box(rail, (sign * (4.6 + k * 2.0), -2.0, 10.65), (0.14, 0.14, 0.9), texel=0.8)
		mb.box(rail, (sign * 12.5, -2.0, 11.05), (16.6, 0.12, 0.12), texel=1.5)
	for x, y, s, seed in ((-6, -4.5, 1.2, 12), (7, -5.2, 1.0, 13), (-14, -4.8, 0.8, 14), (15, -4.3, 0.9, 15)):
		mb.sphere(rock, (x, y, 0.4), s * 1.3, scale=(1.4, 1.1, 0.8), subdiv=3, displace=0.3, seed=seed, texel=2.0,
			flatten_below=-0.3)
	mb.build(root)


def build_fence() -> None:
	"""A 4 m run of post-and-rail fence, lashed with rope."""
	root = empty("Fence")
	mb = MeshBuilder("FenceMesh")
	dark, wood, straw = M("wood_dark"), M("wood"), M("straw")
	for x in (-2.0, 0.0, 2.0):
		mb.box(dark, (x, 0, 0.62), (0.14, 0.14, 1.25), bevel=0.012, texel=0.8)
		for z in (0.45, 0.95):
			mb.tube_path(straw, [p + Vector((x, 0, 0)) for p in helix(0.09, z - 0.05, z + 0.05, 2.5, n=24)], 0.012,
				segments=5, texel=0.08)
	for z in (0.45, 0.95):
		mb.box(wood, (0, -0.1, z), (4.1, 0.07, 0.11), bevel=0.01, texel=1.5)
	mb.build(root)


# --------------------------------------------------------------------------
# Gear
# --------------------------------------------------------------------------

def build_ninjato() -> None:
	"""A straight ninja sword in its scabbard, hilt up (+Z): wrapped grip,
	pommel cap, square guard, lacquered scabbard and a cord."""
	root = empty("Ninjato")
	mb = MeshBuilder("NinjatoMesh")
	black, steel, grip = M("black_lacquer"), M("steel", tint=(0.55, 0.55, 0.58)), M("grip_wrap")
	cord = M("leather", tint=(1.6, 0.55, 0.45))
	mb.box(black, (0, 0, -0.16), (0.048, 0.03, 0.62), bevel=0.008, texel=0.4)
	mb.box(black, (0, 0, -0.485), (0.054, 0.036, 0.04), bevel=0.01, texel=0.2)
	mb.box(black, (0, 0, 0.13), (0.056, 0.038, 0.04), bevel=0.008, texel=0.2)
	mb.box(steel, (0, 0, 0.165), (0.09, 0.075, 0.012), bevel=0.004, texel=0.2)
	mb.box(grip, (0, 0, 0.29), (0.034, 0.027, 0.23), bevel=0.006, texel=0.1)
	mb.box(black, (0, 0, 0.415), (0.038, 0.031, 0.022), bevel=0.006, texel=0.2)
	mb.tube_path(cord, [(0.026, -0.02, 0.1), (0.05, -0.03, 0.04), (0.04, -0.03, -0.05), (0.028, -0.02, -0.08)],
		0.006, segments=6, texel=0.05)
	mb.build(root)


def build_kunai() -> None:
	"""A kunai pointing along +Y: a leaf-shaped blade with a centre ridge, a
	cord-wrapped grip and a ring."""
	root = empty("Kunai")
	mb = MeshBuilder("KunaiMesh")
	steel, grip = M("steel"), M("grip_wrap", tint=(0.35, 0.35, 0.4))
	profile = [(0.0, 0.017), (0.03, 0.03), (0.06, 0.036), (0.1, 0.028), (0.14, 0.014), (0.175, 0.0)]
	verts = []
	for y, hw in profile:
		ridge = 0.006 * (hw / 0.036 + 0.2)
		verts += [(-hw, y, 0.0), (0.0, y, ridge), (hw, y, 0.0), (0.0, y, -ridge)]
	faces = []
	for i in range(len(profile) - 1):
		a, b = i * 4, (i + 1) * 4
		for k in range(4):
			faces.append((a + k, a + (k + 1) % 4, b + (k + 1) % 4, b + k))
	faces.append((3, 2, 1, 0))
	mb.raw(steel, verts, faces, texel=0.1, smooth=False)
	mb.cyl(grip, (0, -0.05, 0), 0.011, 0.011, 0.1, rot=(math.pi / 2, 0, 0), segments=8, texel=0.04)
	ring = [(0.022 * math.cos(2 * math.pi * i / 16), -0.12 + 0.022 * math.sin(2 * math.pi * i / 16), 0) for i in range(17)]
	mb.tube_path(steel, ring, 0.004, segments=6, texel=0.05)
	mb.build(root)


def build_pouch() -> None:
	"""A leather kunai pouch with a flap, a steel stud and belt loops."""
	root = empty("Pouch")
	mb = MeshBuilder("PouchMesh")
	leather, dark, steel = M("leather"), M("leather", tint=(0.6, 0.55, 0.5)), M("steel")
	mb.box(leather, (0, 0, 0), (0.1, 0.055, 0.12), bevel=0.012, texel=0.15)
	mb.box(dark, (0, -0.004, 0.058), (0.106, 0.064, 0.012), bevel=0.004, texel=0.15)
	mb.box(dark, (0, -0.03, 0.03), (0.1, 0.006, 0.06), bevel=0.003, texel=0.15)
	mb.cyl(steel, (0, -0.035, 0.012), 0.008, 0.008, 0.006, rot=(math.pi / 2, 0, 0), segments=10, texel=0.05)
	for x in (-0.03, 0.03):
		mb.box(dark, (x, 0.03, 0.02), (0.02, 0.008, 0.1), texel=0.1)
	mb.build(root)


ASSETS = {
	"training_dummy": build_training_dummy,
	"rock": build_rock,
	"pine": build_pine,
	"gate": build_gate,
	"lantern": build_lantern,
	"broadleaf": build_broadleaf,
	"maple": build_maple,
	"dead_tree": build_dead_tree,
	"snow_pine": build_snow_pine,
	"bamboo": build_bamboo,
	"house": build_house,
	"shrine": build_shrine,
	"gate_broken": build_gate_broken,
	"pillar": build_pillar,
	"dam": build_dam,
	"fence": build_fence,
	"ninjato": build_ninjato,
	"kunai": build_kunai,
	"pouch": build_pouch,
}


def export(name: str, out_dir: Path, save_blend: bool) -> Path:
	kit.reset()
	ASSETS[name]()
	out_dir.mkdir(parents=True, exist_ok=True)
	path = out_dir / f"{name}.gltf"
	bpy.ops.export_scene.gltf(
		filepath=str(path),
		export_format="GLTF_SEPARATE",
		export_keep_originals=True,
		export_yup=True,
		export_apply=True,
		export_cameras=False,
		export_lights=False,
	)
	if save_blend:
		bpy.ops.wm.save_as_mainfile(filepath=str(out_dir / f"{name}.blend"))
	return path


def preview(name: str, out_dir: Path) -> None:
	"""A quick textured render of the asset (Workbench) for reviewing."""
	scene = bpy.context.scene
	scene.render.engine = "BLENDER_WORKBENCH"
	scene.display.shading.light = "STUDIO"
	scene.display.shading.color_type = "TEXTURE"
	scene.display.shading.show_cavity = True
	scene.render.resolution_x = 512
	scene.render.resolution_y = 512
	objs = [o for o in scene.objects if o.type == "MESH"]
	corners = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
	lo = Vector((min(c[i] for c in corners) for i in range(3)))
	hi = Vector((max(c[i] for c in corners) for i in range(3)))
	center = (lo + hi) / 2
	size = (hi - lo).length
	cam_data = bpy.data.cameras.new("cam")
	cam = bpy.data.objects.new("cam", cam_data)
	scene.collection.objects.link(cam)
	cam.location = center + Vector((0.55, -1.0, 0.45)).normalized() * size * 1.35
	cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
	scene.camera = cam
	scene.render.filepath = str(out_dir / f"{name}.png")
	bpy.ops.render.render(write_still=True)


def parse_args(argv: list[str]) -> argparse.Namespace:
	if "--" in argv:
		argv = argv[argv.index("--") + 1:]
	elif Path(argv[0]).name.startswith("blender"):
		argv = []
	else:
		argv = argv[1:]
	p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	p.add_argument("--out", type=Path, default=DEFAULT_OUT)
	p.add_argument("--only", action="append", choices=sorted(ASSETS))
	p.add_argument("--preview", type=Path)
	p.add_argument("--save-blend", action="store_true")
	return p.parse_args(argv)


def main() -> int:
	args = parse_args(sys.argv)
	for name in args.only or list(ASSETS):
		path = export(name, args.out, args.save_blend)
		print(f"exported {path.relative_to(REPO_ROOT) if path.is_relative_to(REPO_ROOT) else path}")
		if args.preview:
			args.preview.mkdir(parents=True, exist_ok=True)
			preview(name, args.preview)
	return 0


if __name__ == "__main__":
	sys.exit(main())
