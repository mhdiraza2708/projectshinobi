"""Modelling toolkit for build_assets.py: textured materials, a mesh builder
with bevelled primitives and world-scale UVs, displacement, and soft
(rounded) normals for foliage.

Conventions: 1 unit = 1 metre, Z up, props face -Y (the front of a house,
the side you walk up to); origins on the ground.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
import bmesh
from mathutils import Euler, Matrix, Vector, noise

REPO_ROOT = Path(__file__).resolve().parents[2]
TEX_DIR = REPO_ROOT / "game" / "assets" / "textures"

# Game roughness per material (matches textures.MATERIALS).
ROUGHNESS = {
	"grass": 0.95, "dirt": 0.95, "rock": 0.9, "sand": 0.95, "snow": 0.8, "bark": 0.95, "wood": 0.85,
	"wood_dark": 0.8, "stone_blocks": 0.9, "roof_tiles": 0.7, "plaster": 0.95, "shoji": 0.95,
	"red_lacquer": 0.45, "black_lacquer": 0.45, "leaves": 0.9, "maple": 0.9, "pine_needles": 0.9,
	"straw": 0.95, "bamboo": 0.6, "steel": 0.3, "leather": 0.8, "grip_wrap": 0.8,
}
METALLIC = {"steel": 0.85}

_materials: dict = {}


def reset() -> None:
	bpy.ops.wm.read_factory_settings(use_empty=True)
	_materials.clear()


def _srgb(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def material(tex: str, tint: tuple | None = None, emission: tuple | None = None, name: str | None = None) -> bpy.types.Material:
	"""A PBR material using the baked textures `tex`_albedo/_normal.
	`tint` (sRGB) multiplies the colour (exported as the base colour factor);
	`emission` (sRGB) makes it glow (lantern paper)."""
	key = (tex, tint, emission, name)
	if key in _materials:
		return _materials[key]
	mat = bpy.data.materials.new(name or (tex if tint is None else f"{tex}_{'%02x%02x%02x' % tuple(int(c * 255) for c in tint)}"))
	mat.use_nodes = True
	nt = mat.node_tree
	bsdf = nt.nodes["Principled BSDF"]
	albedo = nt.nodes.new("ShaderNodeTexImage")
	albedo.image = bpy.data.images.load(str(TEX_DIR / f"{tex}_albedo.png"), check_existing=True)
	color_out = albedo.outputs["Color"]
	if tint is not None:
		mix = nt.nodes.new("ShaderNodeMix")
		mix.data_type = "RGBA"
		mix.blend_type = "MULTIPLY"
		mix.inputs[0].default_value = 1.0
		nt.links.new(color_out, mix.inputs[6])
		mix.inputs[7].default_value = (*[_srgb(c) for c in tint], 1.0)
		color_out = mix.outputs[2]
	nt.links.new(color_out, bsdf.inputs["Base Color"])
	nimg = bpy.data.images.load(str(TEX_DIR / f"{tex}_normal.png"), check_existing=True)
	nimg.colorspace_settings.name = "Non-Color"
	ntex = nt.nodes.new("ShaderNodeTexImage")
	ntex.image = nimg
	nmap = nt.nodes.new("ShaderNodeNormalMap")
	nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"])
	nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
	bsdf.inputs["Roughness"].default_value = ROUGHNESS.get(tex, 0.9)
	bsdf.inputs["Metallic"].default_value = METALLIC.get(tex, 0.0)
	if emission is not None:
		bsdf.inputs["Emission Color"].default_value = (*[_srgb(c) for c in emission], 1.0)
		bsdf.inputs["Emission Strength"].default_value = 1.0
	_materials[key] = mat
	return mat


def xform(loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)) -> Matrix:
	return Matrix.Translation(Vector(loc)) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Diagonal((*scale, 1.0))


class MeshBuilder:
	"""Accumulates primitives into one mesh. Each primitive is built in its
	own scratch mesh at the origin, bevelled and UV-mapped there (so textures
	keep their real-world size, `texel` metres per texture repeat), then
	moved into place and merged in."""

	def __init__(self, name: str):
		self.name = name
		self.bm = bmesh.new()
		self.uv = self.bm.loops.layers.uv.new("UVMap")
		self.soft = self.bm.faces.layers.int.new("soft")
		self.mats: list[bpy.types.Material] = []
		self.soft_centers: list[Vector] = []

	def _mat(self, mat: bpy.types.Material) -> int:
		if mat not in self.mats:
			self.mats.append(mat)
		return self.mats.index(mat)

	@staticmethod
	def _scratch():
		bm = bmesh.new()
		return bm, bm.loops.layers.uv.new("UVMap")

	def _commit(self, bm, uvl, mat, matrix: Matrix, proj: str, texel: float, smooth: bool,
			radius: float = 1.0, soft_center: Vector | None = None) -> None:
		bm.normal_update()
		_project(bm.faces, uvl, proj, texel, radius)
		bmesh.ops.transform(bm, matrix=matrix, verts=list(bm.verts))
		idx = self._mat(mat)
		soft_id = 0
		if soft_center is not None:
			self.soft_centers.append(matrix @ soft_center)
			soft_id = len(self.soft_centers)
		vmap = {v: self.bm.verts.new(v.co) for v in bm.verts}
		for f in bm.faces:
			try:
				nf = self.bm.faces.new([vmap[v] for v in f.verts])
			except ValueError:
				continue
			nf.material_index = idx
			nf.smooth = smooth
			nf[self.soft] = soft_id
			for src, dst in zip(f.loops, nf.loops):
				dst[self.uv].uv = src[uvl].uv
		bm.free()

	# --- primitives --------------------------------------------------------------------

	def box(self, mat, loc, size, rot=(0, 0, 0), bevel=0.0, texel=1.0, smooth=False):
		bm, uvl = self._scratch()
		bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Diagonal((*size, 1.0)))
		if bevel > 0:
			bmesh.ops.bevel(bm, geom=list(bm.verts) + list(bm.edges), offset=bevel, segments=2,
				affect="EDGES", profile=0.5)
		self._commit(bm, uvl, mat, xform(loc, rot), "box", texel, smooth)

	def cyl(self, mat, loc, r1, r2, depth, rot=(0, 0, 0), segments=16, texel=1.0, smooth=True, caps=True, bevel=0.0):
		bm, uvl = self._scratch()
		bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segments, radius1=r1, radius2=r2, depth=depth)
		if bevel > 0 and caps:
			rim = [e for e in bm.edges if all(abs(abs(v.co.z) - depth / 2) < 1e-4 for v in e.verts)
				and len(e.link_faces) == 2]
			bmesh.ops.bevel(bm, geom=rim, offset=bevel, segments=2, affect="EDGES", profile=0.5)
		self._commit(bm, uvl, mat, xform(loc, rot), "cyl", texel, smooth, radius=(r1 + r2) * 0.5)

	def prism(self, mat, loc, radius, depth, sides=6, rot=(0, 0, 0), texel=1.0, top_radius=None, bevel=0.0):
		"""A flat-sided prism (hexagonal lantern parts)."""
		bm, uvl = self._scratch()
		bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=radius,
			radius2=top_radius if top_radius is not None else radius, depth=depth)
		if bevel > 0:
			bmesh.ops.bevel(bm, geom=list(bm.verts) + list(bm.edges), offset=bevel, segments=1, affect="EDGES")
		self._commit(bm, uvl, mat, xform(loc, rot), "box", texel, False)

	def sphere(self, mat, loc, radius, scale=(1, 1, 1), rot=(0, 0, 0), subdiv=3, texel=1.0,
			displace=0.0, freq=1.5, seed=0, flatten_below=None, soft=False, smooth=True, soft_origin=None):
		"""An icosphere, optionally lumpy (`displace`). `soft` bends its normals
		outward from its centre, or from `soft_origin` (a point in the model)
		so several lumps shade as one mass."""
		bm, uvl = self._scratch()
		bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
		off = Vector((seed * 13.1, seed * 7.7, seed * 3.3))
		for v in bm.verts:
			d = v.co.normalized()
			if displace:
				v.co += d * noise.fractal(d * freq + off, 0.6, 2.0, 4) * displace * radius
			v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
			if flatten_below is not None and v.co.z < flatten_below:
				v.co.z = flatten_below + (v.co.z - flatten_below) * 0.15
		bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
		matrix = xform(loc, rot)
		center = None
		if soft:
			center = matrix.inverted() @ Vector(soft_origin) if soft_origin is not None else Vector((0, 0, 0))
		self._commit(bm, uvl, mat, matrix, "box", texel, smooth, soft_center=center)

	def raw(self, mat, verts: list, faces: list, texel=1.0, proj="box", smooth=True, soft_center=None, radius=1.0):
		"""Arbitrary geometry: verts (in place), faces as index tuples."""
		bm, uvl = self._scratch()
		vs = [bm.verts.new(Vector(v)) for v in verts]
		for f in faces:
			try:
				bm.faces.new([vs[i] for i in f])
			except ValueError:
				pass
		bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
		self._commit(bm, uvl, mat, Matrix.Identity(4), proj, texel, smooth, radius=radius,
			soft_center=Vector(soft_center) if soft_center is not None else None)

	def tube_path(self, mat, points: list, radius: float, segments=8, texel=0.3, radius_fn=None, smooth=True):
		"""A tube along a list of points (ropes, cords, curved branches).
		U runs round the tube, V along it."""
		bm, uvl = self._scratch()
		pts = [Vector(p) for p in points]
		rings = []
		for i, p in enumerate(pts):
			t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
			side = t.cross(Vector((0, 0, 1)))
			if side.length < 1e-4:
				side = t.cross(Vector((1, 0, 0)))
			side.normalize()
			up = side.cross(t).normalized()
			r = radius_fn(i / (len(pts) - 1)) if radius_fn else radius
			rings.append([bm.verts.new(p + (side * math.cos(2 * math.pi * k / segments) + up * math.sin(2 * math.pi * k / segments)) * r)
				for k in range(segments)])
		along = [0.0]
		for i in range(1, len(pts)):
			along.append(along[-1] + (pts[i] - pts[i - 1]).length)
		for i in range(len(rings) - 1):
			for k in range(segments):
				k2 = (k + 1) % segments
				f = bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
				us = (k, k + 1, k + 1, k)
				vs = (along[i], along[i], along[i + 1], along[i + 1])
				for l, u, v in zip(f.loops, us, vs):
					l[uvl].uv = (u / segments * 2 * math.pi * radius / texel, v / texel)
		bm.normal_update()
		self._commit(bm, uvl, mat, Matrix.Identity(4), "keep", texel, smooth)

	def build(self, parent=None, sharp_angle=40.0) -> bpy.types.Object:
		mesh = bpy.data.meshes.new(self.name)
		self.bm.faces.index_update()
		soft_faces = {f.index: f[self.soft] for f in self.bm.faces if f[self.soft] > 0}
		self.bm.normal_update()
		self.bm.to_mesh(mesh)
		self.bm.free()
		for m in self.mats:
			mesh.materials.append(m)
		mesh.set_sharp_from_angle(angle=math.radians(sharp_angle))
		if soft_faces:
			# No hard edges inside foliage: one smooth normal per vertex.
			sharp = mesh.attributes.get("sharp_edge")
			if sharp is not None:
				soft_keys = {k for p in mesh.polygons if p.index in soft_faces for k in p.edge_keys}
				for e in mesh.edges:
					if tuple(sorted(e.vertices)) in soft_keys:
						sharp.data[e.index].value = False
			# Foliage: bend normals outward from each clump's centre, so
			# canopies shade like soft round masses, not faceted rocks.
			corner = mesh.corner_normals
			normals = []
			for li, loop in enumerate(mesh.loops):
				normals.append(Vector(corner[li].vector))
			for poly in mesh.polygons:
				c = soft_faces.get(poly.index, 0)
				if not c:
					continue
				for li in poly.loop_indices:
					vert = mesh.vertices[mesh.loops[li].vertex_index]
					out = (vert.co - self.soft_centers[c - 1]).normalized()
					# Per vertex (not per face), so the surface shades smoothly.
					normals[li] = Vector(vert.normal).lerp(out, 0.75).normalized()
			mesh.normals_split_custom_set(normals)
		obj = bpy.data.objects.new(self.name, mesh)
		bpy.context.scene.collection.objects.link(obj)
		if parent is not None:
			obj.parent = parent
		return obj


def _project(faces, uvl, proj: str, texel: float, radius: float) -> None:
	"""World-scale UVs: box (dominant axis) or cylindrical round Z."""
	if proj == "keep":
		return
	for f in faces:
		if proj == "cyl" and abs(f.normal.z) < 0.9:
			angs = [math.atan2(l.vert.co.y, l.vert.co.x) for l in f.loops]
			if max(angs) - min(angs) > math.pi:
				angs = [a + 2 * math.pi if a < 0 else a for a in angs]
			for l, a in zip(f.loops, angs):
				l[uvl].uv = (a * radius / texel, l.vert.co.z / texel)
			continue
		n = f.normal
		ax = max(range(3), key=lambda i: abs(n[i]))
		for l in f.loops:
			p = l.vert.co
			if ax == 0:
				uv = (p.y * (1 if n.x > 0 else -1), p.z)
			elif ax == 1:
				uv = (p.x * (-1 if n.y > 0 else 1), p.z)
			else:
				uv = (p.x, p.y * (1 if n.z > 0 else -1))
			l[uvl].uv = (uv[0] / texel, uv[1] / texel)


def empty(name: str) -> bpy.types.Object:
	obj = bpy.data.objects.new(name, None)
	bpy.context.scene.collection.objects.link(obj)
	return obj


def rng(seed: int) -> random.Random:
	return random.Random(seed)
