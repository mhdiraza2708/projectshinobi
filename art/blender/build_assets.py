"""Procedurally models Project Shinobi's blockout assets and exports glTF.

Run with either:
    blender --background --python art/blender/build_assets.py -- [options]
    python art/blender/build_assets.py [options]        # needs `pip install -r art/blender/requirements.txt`

Options:
    --out DIR        output directory (default: game/assets/models)
    --only NAME      build a single asset (e.g. gate)
    --save-blend     also write a .blend next to each .glb for hand editing

These are environment *blockouts*: clean, stylised, readable shapes that let
the game be built and play-tested now. Characters are not modelled here: they
come from VRoid Studio as .vrm files (see docs/CHARACTERS.md).

Conventions: 1 unit = 1 metre, props face +Y in Blender (which becomes -Z,
Godot's forward, after glTF export), origins sit on the ground.
"""

from __future__ import annotations

import argparse
import math
import random
import sys
from pathlib import Path

import bpy  # must be imported before bmesh/mathutils when running as a pip module
import bmesh
from mathutils import Euler, Matrix, Vector

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO_ROOT / "game" / "assets" / "models"

# --------------------------------------------------------------------------
# Palette (sRGB, converted to linear on export).
# --------------------------------------------------------------------------
PALETTE = {
    "wood": (0.55, 0.36, 0.20),
    "wood_dark": (0.36, 0.22, 0.12),
    "rope": (0.85, 0.74, 0.48),
    "stone": (0.52, 0.53, 0.55),
    "stone_dark": (0.38, 0.39, 0.42),
    "bark": (0.33, 0.22, 0.14),
    "leaf": (0.20, 0.45, 0.22),
    "leaf_light": (0.30, 0.58, 0.26),
    "gate_red": (0.78, 0.18, 0.10),
    "gate_black": (0.08, 0.08, 0.09),
    "paper": (0.98, 0.93, 0.78),
    "maple_red": (0.80, 0.20, 0.10),
    "maple_orange": (0.92, 0.46, 0.12),
    "maple_gold": (0.94, 0.70, 0.22),
    "bark_ash": (0.24, 0.22, 0.21),
    "snow": (0.93, 0.95, 0.98),
    "leaf_dark": (0.13, 0.32, 0.20),
    "bamboo": (0.46, 0.63, 0.30),
    "bamboo_dark": (0.32, 0.48, 0.22),
    "roof_tile": (0.22, 0.24, 0.28),
    "plaster": (0.90, 0.86, 0.78),
}


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def material(name: str) -> bpy.types.Material:
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    # PALETTE is authored in sRGB (what colour pickers show); Blender and
    # glTF store base colour in linear space.
    r, g, b = (srgb_to_linear(c) for c in PALETTE[name])
    bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.85
    if name == "paper":
        # Lantern paper glows at night.
        bsdf.inputs["Emission Color"].default_value = (1.0, 0.8, 0.45, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.5
    return mat


class Part:
    """Accumulates primitives into one mesh object whose origin is a joint.

    Primitive positions are given in *world* space (character standing at the
    origin), which keeps proportions easy to read; they are converted to the
    part's local space on build.
    """

    def __init__(self, name: str, origin=(0.0, 0.0, 0.0), parent: "Part | None" = None):
        self.name = name
        self.origin = Vector(origin)
        self.parent = parent
        self.bm = bmesh.new()
        self.materials: list[bpy.types.Material] = []
        self.obj: bpy.types.Object | None = None

    def _mat_index(self, mat_name: str) -> int:
        mat = material(mat_name)
        if mat not in self.materials:
            self.materials.append(mat)
        return self.materials.index(mat)

    def _matrix(self, loc, scale, rot) -> Matrix:
        return (
            Matrix.Translation(Vector(loc) - self.origin)
            @ Euler(rot).to_matrix().to_4x4()
            @ Matrix.Diagonal((*scale, 1.0))
        )

    def _finish(self, verts, mat_name: str, smooth: bool) -> None:
        idx = self._mat_index(mat_name)
        for face in {f for v in verts for f in v.link_faces}:
            face.material_index = idx
            face.smooth = smooth

    def box(self, mat, loc, size, rot=(0, 0, 0)):
        ret = bmesh.ops.create_cube(self.bm, size=1.0, matrix=self._matrix(loc, size, rot))
        self._finish(ret["verts"], mat, smooth=False)
        return self

    def ball(self, mat, loc, size, rot=(0, 0, 0), segments=18, rings=10):
        ret = bmesh.ops.create_uvsphere(
            self.bm, u_segments=segments, v_segments=rings, radius=0.5,
            matrix=self._matrix(loc, size, rot))
        self._finish(ret["verts"], mat, smooth=True)
        return self

    def tube(self, mat, loc, r1, r2, depth, rot=(0, 0, 0), segments=14, smooth=True):
        ret = bmesh.ops.create_cone(
            self.bm, cap_ends=True, cap_tris=False, segments=segments,
            radius1=r1, radius2=r2, depth=depth,
            matrix=self._matrix(loc, (1, 1, 1), rot))
        self._finish(ret["verts"], mat, smooth=smooth)
        return self

    def rock(self, mat, loc, size, seed: int, roughness=0.18):
        rng = random.Random(seed)
        ret = bmesh.ops.create_icosphere(
            self.bm, subdivisions=2, radius=0.5, matrix=self._matrix(loc, size, (0, 0, 0)))
        for v in ret["verts"]:
            v.co += v.co.normalized() * rng.uniform(-roughness, roughness) * min(size)
        self._finish(ret["verts"], mat, smooth=False)
        return self

    def build(self) -> bpy.types.Object:
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for mat in self.materials:
            mesh.materials.append(mat)
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        if self.parent is not None:
            obj.parent = self.parent.obj
            obj.location = self.origin - self.parent.origin
        else:
            obj.location = self.origin
        self.obj = obj
        return obj


def empty(name: str, location=(0, 0, 0), parent=None) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    obj.parent = parent
    return obj


# --------------------------------------------------------------------------
# Assets
# --------------------------------------------------------------------------

def build_training_dummy() -> None:
    """Classic wooden training post with arms and a straw-wrapped head."""
    empty("TrainingDummy")
    post = Part("Post")
    post.tube("wood_dark", (0, 0, 0.08), 0.42, 0.42, 0.16, segments=8, smooth=False)
    post.tube("wood", (0, 0, 0.95), 0.2, 0.18, 1.7)
    post.tube("rope", (0, 0, 1.30), 0.205, 0.205, 0.1)
    post.tube("rope", (0, 0, 0.62), 0.205, 0.205, 0.1)
    post.ball("rope", (0, 0, 1.88), (0.36, 0.36, 0.36))
    for x, z, yaw in ((-0.12, 1.42, -20), (0.12, 1.42, 20), (0.0, 1.05, 0)):
        post.tube("wood_dark", (x, 0.28, z), 0.04, 0.035, 0.5,
                  rot=(math.radians(90), 0, math.radians(yaw)))
    post.build().parent = bpy.data.objects["TrainingDummy"]


def build_rock() -> None:
    empty("Rock")
    r = Part("RockMesh")
    r.rock("stone", (0, 0, 0.35), (1.3, 1.1, 0.9), seed=7)
    r.rock("stone_dark", (0.6, 0.3, 0.2), (0.6, 0.55, 0.45), seed=11)
    r.build().parent = bpy.data.objects["Rock"]


def build_pine() -> None:
    empty("Pine")
    t = Part("PineMesh")
    t.tube("bark", (0, 0, 1.2), 0.22, 0.14, 2.4, segments=8, smooth=False)
    for i, (z, r) in enumerate(((2.0, 1.6), (3.0, 1.25), (3.9, 0.9), (4.7, 0.55))):
        t.tube("leaf" if i % 2 == 0 else "leaf_light", (0, 0, z), r, 0.0, 1.6, segments=9, smooth=False)
    t.build().parent = bpy.data.objects["Pine"]


def build_gate() -> None:
    """A shrine-style gate framing the training ground."""
    empty("Gate")
    g = Part("GateMesh")
    for x in (-2.0, 2.0):
        g.tube("gate_red", (x, 0, 2.0), 0.2, 0.17, 4.0)
        g.tube("gate_black", (x, 0, 0.15), 0.26, 0.26, 0.3)
    g.box("gate_red", (0, 0, 3.35), (4.6, 0.22, 0.22))
    g.box("gate_red", (0, 0, 4.05), (5.4, 0.36, 0.26))
    g.box("gate_black", (0, 0, 4.26), (5.9, 0.42, 0.16))
    g.box("gate_red", (0, 0, 3.7), (0.22, 0.2, 0.5))
    g.build().parent = bpy.data.objects["Gate"]


def build_lantern() -> None:
    empty("Lantern")
    lamp = Part("LanternMesh")
    lamp.box("stone_dark", (0, 0, 0.1), (0.7, 0.7, 0.2))
    lamp.tube("stone", (0, 0, 0.55), 0.12, 0.12, 0.7, segments=8, smooth=False)
    lamp.box("stone", (0, 0, 0.95), (0.55, 0.55, 0.12))
    lamp.box("paper", (0, 0, 1.18), (0.36, 0.36, 0.34))
    lamp.tube("stone_dark", (0, 0, 1.47), 0.5, 0.05, 0.26, segments=4, smooth=False,
              rot=(0, 0, math.radians(45)))
    lamp.build().parent = bpy.data.objects["Lantern"]


# --- Island props ------------------------------------------------------------

def _canopy(t: Part, mats: list[str], center, radius: float, seed: int, blobs: int = 7) -> None:
    """A broadleaf crown: a core and lumpy clusters around it."""
    rng = random.Random(seed)
    cx, cy, cz = center
    t.rock(mats[0], (cx, cy, cz + 0.2 * radius), (radius * 1.5,) * 3, seed=seed + 99, roughness=0.1)
    for i in range(blobs):
        a = 2 * math.pi * i / blobs + rng.uniform(-0.3, 0.3)
        d = rng.uniform(0.5, 0.8) * radius
        s = rng.uniform(0.75, 1.0) * radius
        z = cz + rng.uniform(-0.35, 0.4) * radius
        t.rock(mats[i % len(mats)], (cx + math.cos(a) * d, cy + math.sin(a) * d, z), (s, s, s * 0.8),
               seed=seed + i, roughness=0.12)


def _broadleaf(name: str, mats: list[str], seed: int) -> None:
    empty(name)
    t = Part(name + "Mesh")
    t.tube("bark", (0, 0, 1.3), 0.26, 0.16, 2.6, segments=8, smooth=False)
    for yaw, tilt, length in ((20, 40, 1.4), (150, 45, 1.2), (260, 35, 1.3)):
        a, b = math.radians(yaw), math.radians(tilt)
        mid = (math.cos(a) * math.sin(b) * length * 0.5, math.sin(a) * math.sin(b) * length * 0.5,
               2.3 + math.cos(b) * length * 0.5)
        t.tube("bark", mid, 0.1, 0.05, length, rot=(0, b, a), segments=6, smooth=False)
    _canopy(t, mats, (0, 0, 3.5), 1.7, seed)
    t.build().parent = bpy.data.objects[name]


def build_broadleaf() -> None:
    _broadleaf("Broadleaf", ["leaf", "leaf_light", "leaf_dark"], seed=21)


def build_maple() -> None:
    """Autumn maple: red, orange and gold."""
    _broadleaf("Maple", ["maple_red", "maple_orange", "maple_gold", "maple_red"], seed=33)


def build_dead_tree() -> None:
    """Bare, ash-grey tree for burnt ground."""
    empty("DeadTree")
    t = Part("DeadTreeMesh")
    t.tube("bark_ash", (0, 0, 1.6), 0.28, 0.1, 3.2, segments=7, smooth=False)
    rng = random.Random(5)
    for i in range(6):
        a = 2 * math.pi * i / 6 + rng.uniform(-0.4, 0.4)
        b = math.radians(rng.uniform(30, 65))
        z0 = rng.uniform(1.6, 2.9)
        length = rng.uniform(0.9, 1.6)
        mid = (math.cos(a) * math.sin(b) * length * 0.5, math.sin(a) * math.sin(b) * length * 0.5,
               z0 + math.cos(b) * length * 0.5)
        t.tube("bark_ash", mid, 0.08, 0.02, length, rot=(0, b, a), segments=5, smooth=False)
    t.build().parent = bpy.data.objects["DeadTree"]


def build_snow_pine() -> None:
    empty("SnowPine")
    t = Part("SnowPineMesh")
    t.tube("bark", (0, 0, 1.2), 0.22, 0.14, 2.4, segments=8, smooth=False)
    for z, r in ((2.0, 1.6), (3.0, 1.25), (3.9, 0.9), (4.7, 0.55)):
        t.tube("leaf_dark", (0, 0, z), r, 0.0, 1.6, segments=9, smooth=False)
        t.tube("snow", (0, 0, z + 0.45), r * 0.62, 0.0, 0.8, segments=9, smooth=False)
    t.build().parent = bpy.data.objects["SnowPine"]


def build_bamboo() -> None:
    """A clump of bamboo with jointed stalks and leafy tops."""
    empty("Bamboo")
    t = Part("BambooMesh")
    rng = random.Random(9)
    for i in range(7):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(0.0, 0.55)
        x, y = math.cos(a) * d, math.sin(a) * d
        h = rng.uniform(5.0, 7.0)
        lean = (rng.uniform(-0.06, 0.06), rng.uniform(-0.06, 0.06), 0)
        t.tube("bamboo", (x, y, h * 0.5), 0.055, 0.045, h, rot=lean, segments=7)
        for k in range(1, int(h / 0.9)):
            t.tube("bamboo_dark", (x + lean[1] * k * 0.9, y - lean[0] * k * 0.9, k * 0.9), 0.065, 0.065, 0.05, segments=7)
        # Feathery leaves along the top third, not a ball on a stick.
        for k in range(4):
            z = h * (0.62 + 0.11 * k)
            a2 = rng.uniform(0, 2 * math.pi)
            ox, oy = math.cos(a2) * 0.35, math.sin(a2) * 0.35
            t.ball("leaf_light" if (i + k) % 2 else "leaf", (x + lean[1] * z + ox, y - lean[0] * z + oy, z),
                   (0.9 - 0.12 * k, 0.55, 0.35), rot=(0, 0, a2), segments=8, rings=5)
    t.build().parent = bpy.data.objects["Bamboo"]


def _gable_roof(t: Part, mat: str, width: float, depth: float, eave_z: float, pitch_deg: float, overhang: float) -> float:
    """Two roof planes along X meeting at a ridge. Returns the ridge height."""
    pitch = math.radians(pitch_deg)
    half = depth * 0.5 + overhang
    slope_len = half / math.cos(pitch)
    rise = half * math.tan(pitch)
    for side in (-1, 1):
        t.box(mat, (0, side * half * 0.5, eave_z + rise * 0.5), (width + 2 * overhang, slope_len, 0.18),
              rot=(-side * pitch, 0, 0))
    t.box(mat, (0, 0, eave_z + rise + 0.05), (width + 2 * overhang + 0.2, 0.34, 0.26))
    return eave_z + rise


def build_house() -> None:
    """A small timber house: stone footing, paper walls, tiled gable roof, veranda."""
    empty("House")
    t = Part("HouseMesh")
    w, d = 6.0, 4.4
    t.box("stone_dark", (0, 0, 0.25), (w + 0.4, d + 0.4, 0.5))
    t.box("paper", (0, 0, 1.85), (w - 0.1, d - 0.1, 2.7))
    for x in (-w / 2, -w / 6, w / 6, w / 2):
        for y in (-d / 2, d / 2):
            t.box("wood_dark", (x, y, 1.85), (0.18, 0.18, 2.8))
    for z in (0.55, 1.35, 3.15):
        t.box("wood_dark", (0, -d / 2, z), (w + 0.1, 0.2, 0.12))
        t.box("wood_dark", (0, d / 2, z), (w + 0.1, 0.2, 0.12))
    t.box("wood_dark", (0, -d / 2 - 0.02, 1.35), (1.3, 0.1, 1.9))
    # Gable ends filled in plaster under the roof.
    t.box("plaster", (0, 0, 3.55), (w - 0.1, d * 0.55, 0.7))
    t.box("wood", (0, -d / 2 - 0.65, 0.48), (w + 0.6, 1.2, 0.12))
    for x in (-w / 2, 0, w / 2):
        t.tube("wood_dark", (x, -d / 2 - 1.2, 1.9), 0.08, 0.08, 2.8, segments=6, smooth=False)
    _gable_roof(t, "roof_tile", w, d + 1.2, 3.25, 32, 0.5)
    t.build().parent = bpy.data.objects["House"]


def build_shrine() -> None:
    """A red shrine hall on a raised platform with steps."""
    empty("Shrine")
    t = Part("ShrineMesh")
    w, d = 5.0, 4.0
    t.box("wood_dark", (0, 0, 0.45), (w + 0.8, d + 0.8, 0.9))
    for i in range(3):
        t.box("wood", (0, -d / 2 - 0.55 - i * 0.35, 0.15 + i * 0.0), (1.8, 0.35, 0.3 + (2 - i) * 0.3))
    t.box("wood", (0, 0, 2.2), (w - 0.3, d - 0.3, 2.6))
    for x in (-w / 2, w / 2):
        for y in (-d / 2, d / 2):
            t.tube("gate_red", (x, y, 2.3), 0.16, 0.16, 2.8, segments=10)
    t.box("gate_red", (0, -d / 2, 3.55), (w + 0.4, 0.24, 0.26))
    t.box("gate_red", (0, d / 2, 3.55), (w + 0.4, 0.24, 0.26))
    t.box("gate_black", (0, -d / 2 - 0.02, 2.0), (1.6, 0.08, 1.8))
    t.box("rope", (0, -d / 2 - 0.25, 3.2), (2.6, 0.12, 0.14))
    t.box("wood_dark", (0, -d / 2 - 1.0, 1.25), (1.0, 0.6, 0.5))
    _gable_roof(t, "gate_black", w, d + 0.8, 3.7, 34, 0.8)
    t.build().parent = bpy.data.objects["Shrine"]


def build_gate_broken() -> None:
    """The gate after a fight: one pillar snapped, the lintel on the ground."""
    empty("GateBroken")
    g = Part("GateBrokenMesh")
    g.tube("gate_red", (-2.0, 0, 2.0), 0.2, 0.17, 4.0)
    g.tube("gate_black", (-2.0, 0, 0.15), 0.26, 0.26, 0.3)
    g.tube("gate_red", (2.0, 0, 0.8), 0.2, 0.19, 1.6)
    g.rock("gate_red", (2.0, 0, 1.62), (0.4, 0.4, 0.25), seed=4, roughness=0.3)
    g.tube("gate_black", (2.0, 0, 0.15), 0.26, 0.26, 0.3)
    g.box("gate_red", (-0.4, 0, 3.35), (4.6, 0.22, 0.22), rot=(0, math.radians(-24), 0))
    g.box("gate_red", (1.2, -1.6, 0.2), (5.4, 0.36, 0.26), rot=(0, 0, math.radians(18)))
    g.box("gate_black", (1.2, -1.6, 0.38), (5.9, 0.42, 0.16), rot=(0, 0, math.radians(18)))
    g.rock("stone_dark", (2.6, 0.6, 0.15), (0.5, 0.4, 0.3), seed=8)
    g.build().parent = bpy.data.objects["GateBroken"]


def build_pillar() -> None:
    """A tall standing stone with a dish on top (an orb is added in game)."""
    empty("Pillar")
    t = Part("PillarMesh")
    t.box("stone_dark", (0, 0, 0.3), (1.7, 1.7, 0.6))
    t.box("stone", (0, 0, 0.75), (1.35, 1.35, 0.3))
    t.tube("stone", (0, 0, 3.2), 0.46, 0.38, 4.6, segments=8, smooth=False)
    for z in (1.4, 5.0):
        t.tube("stone_dark", (0, 0, z), 0.5, 0.5, 0.2, segments=8, smooth=False)
    t.box("stone_dark", (0, 0, 5.75), (1.2, 1.2, 0.5))
    t.tube("stone_dark", (0, 0, 6.15), 0.45, 0.7, 0.3, segments=8, smooth=False)
    t.build().parent = bpy.data.objects["Pillar"]


def build_dam() -> None:
    """An old stone dam: buttressed wall, a lower spillway in the middle, a walkway on top."""
    empty("Dam")
    t = Part("DamMesh")
    t.box("stone", (-12.5, 0, 5.0), (17.0, 4.0, 10.0))
    t.box("stone", (12.5, 0, 5.0), (17.0, 4.0, 10.0))
    t.box("stone_dark", (0, 0.3, 3.8), (8.0, 3.4, 7.6))
    for x in (-19, -12, -5, 5, 12, 19):
        t.box("stone_dark", (x, -2.4, 4.6), (1.4, 1.2, 9.2))
    for sign in (-1, 1):
        t.box("stone_dark", (sign * 12.5, 0, 10.2), (17.4, 4.4, 0.4))
        for k in range(9):
            t.box("wood_dark", (sign * (4.6 + k * 2.0), -2.0, 10.8), (0.14, 0.14, 0.9))
        t.box("wood_dark", (sign * 12.5, -2.0, 11.15), (16.6, 0.12, 0.12))
    t.rock("stone_dark", (-6, -4.5, 0.4), (2.4, 1.8, 1.2), seed=12)
    t.rock("stone", (7, -5.2, 0.4), (2.0, 1.6, 1.0), seed=13)
    t.build().parent = bpy.data.objects["Dam"]


def build_fence() -> None:
    """A 4 m run of post-and-rail fence."""
    empty("Fence")
    t = Part("FenceMesh")
    for x in (-2.0, 0.0, 2.0):
        t.box("wood_dark", (x, 0, 0.6), (0.14, 0.14, 1.2))
    for z in (0.45, 0.95):
        t.box("wood", (0, 0, z), (4.1, 0.08, 0.12))
    t.build().parent = bpy.data.objects["Fence"]


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
}


def export(name: str, out_dir: Path, save_blend: bool) -> Path:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ASSETS[name]()
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{name}.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
    )
    if save_blend:
        bpy.ops.wm.save_as_mainfile(filepath=str(out_dir / f"{name}.blend"))
    return path


def parse_args(argv: list[str]) -> argparse.Namespace:
    # Under `blender --python`, our args follow a literal `--`.
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    elif Path(argv[0]).name.startswith("blender"):
        argv = []
    else:
        argv = argv[1:]
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out", type=Path, default=DEFAULT_OUT)
    p.add_argument("--only", choices=sorted(ASSETS))
    p.add_argument("--save-blend", action="store_true")
    return p.parse_args(argv)


def main() -> int:
    args = parse_args(sys.argv)
    names = [args.only] if args.only else list(ASSETS)
    for name in names:
        path = export(name, args.out, args.save_blend)
        print(f"exported {path.relative_to(REPO_ROOT) if path.is_relative_to(REPO_ROOT) else path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
