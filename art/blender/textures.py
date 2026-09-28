"""Bakes Project Shinobi's tileable material textures with Blender.

    python art/blender/textures.py [--only NAME] [--size-scale 0.5]

Each material is a procedural shader (noise, Voronoi, waves) whose
coordinates wrap round a 4D torus, so the result tiles seamlessly. Cycles
bakes its colour (with crevices darkened, for a painted look) and a normal
map from its height. Output: game/assets/textures/<name>_albedo.png and
<name>_normal.png. Models (build_assets.py) and the terrain use them.

Needs the `bpy` module (pip install -r art/blender/requirements.txt).
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT = REPO_ROOT / "game" / "assets" / "textures"


class Graph:
	"""Small helper for building shader node graphs in code."""

	def __init__(self, mat: bpy.types.Material):
		mat.use_nodes = True
		self.nt = mat.node_tree
		self.nt.nodes.clear()
		self.x = 0
		uv = self.nt.nodes.new("ShaderNodeTexCoord")
		sep = self.node("ShaderNodeSeparateXYZ", Vector=uv.outputs["UV"])
		self.u = sep.outputs["X"]
		self.v = sep.outputs["Y"]

	def node(self, kind: str, **inputs):
		n = self.nt.nodes.new(kind)
		n.location = (self.x, 0)
		self.x += 200
		for name, value in inputs.items():
			if name.startswith("_"):
				setattr(n, name[1:], value)
				continue
			sock = n.inputs[name]
			if isinstance(value, bpy.types.NodeSocket):
				self.nt.links.new(value, sock)
			else:
				sock.default_value = value
		return n

	def math(self, op: str, a, b=0.0, c=0.0):
		n = self.node("ShaderNodeMath", _operation=op)
		for i, v in enumerate((a, b, c)):
			if isinstance(v, bpy.types.NodeSocket):
				self.nt.links.new(v, n.inputs[i])
			else:
				n.inputs[i].default_value = v
		return n.outputs[0]

	def torus(self, ru: float, rv: float):
		"""(x, y, z, w) on a torus: tiles in u and v. Radii set frequency."""
		au = self.math("MULTIPLY", self.u, 2 * math.pi)
		av = self.math("MULTIPLY", self.v, 2 * math.pi)
		x = self.math("MULTIPLY", self.math("COSINE", au), ru)
		y = self.math("MULTIPLY", self.math("SINE", au), ru)
		z = self.math("MULTIPLY", self.math("COSINE", av), rv)
		w = self.math("MULTIPLY", self.math("SINE", av), rv)
		vec = self.node("ShaderNodeCombineXYZ", X=x, Y=y, Z=z)
		return vec.outputs[0], w

	def noise(self, ru: float, rv: float | None = None, scale=1.0, detail=4.0, rough=0.55, distort=0.0):
		vec, w = self.torus(ru, rv if rv is not None else ru)
		n = self.node("ShaderNodeTexNoise", _noise_dimensions="4D", Vector=vec, W=w, Scale=scale,
			Detail=detail, Roughness=rough, Distortion=distort)
		return n.outputs["Fac"]

	def voronoi(self, ru: float, rv: float | None = None, scale=1.0, feature="F1", out="Distance", randomness=1.0):
		vec, w = self.torus(ru, rv if rv is not None else ru)
		n = self.node("ShaderNodeTexVoronoi", _voronoi_dimensions="4D", _feature=feature,
			Vector=vec, W=w, Scale=scale, Randomness=randomness)
		return n.outputs[out]

	def ramp(self, fac, stops: list[tuple[float, tuple]]):
		n = self.node("ShaderNodeValToRGB", Fac=fac)
		cr = n.color_ramp
		while len(cr.elements) > 1:
			cr.elements.remove(cr.elements[-1])
		cr.elements[0].position = stops[0][0]
		cr.elements[0].color = (*stops[0][1], 1.0)
		for pos, col in stops[1:]:
			e = cr.elements.new(pos)
			e.color = (*col, 1.0)
		return n.outputs["Color"]

	def mix(self, fac, a, b, blend="MIX"):
		n = self.nt.nodes.new("ShaderNodeMix")
		n.data_type = "RGBA"
		n.blend_type = blend
		n.location = (self.x, 0)
		self.x += 200
		for sock, val in ((n.inputs[0], fac), (n.inputs[6], a), (n.inputs[7], b)):
			if isinstance(val, bpy.types.NodeSocket):
				self.nt.links.new(val, sock)
			else:
				sock.default_value = val if not isinstance(val, tuple) else (*val, 1.0)
		return n.outputs[2]

	def clamp01(self, a):
		return self.math("MINIMUM", self.math("MAXIMUM", a, 0.0), 1.0)

	def smooth(self, a, lo: float, hi: float):
		"""Smoothstep of a from lo to hi (0..1)."""
		t = self.clamp01(self.math("DIVIDE", self.math("SUBTRACT", a, lo), hi - lo))
		return self.math("MULTIPLY", self.math("MULTIPLY", t, t), self.math("SUBTRACT", 3.0, self.math("MULTIPLY", t, 2.0)))


def _srgb(c):
	"""sRGB colour tuple to linear (Blender colours are linear)."""
	def f(x):
		return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
	return tuple(f(x) for x in c)


# --------------------------------------------------------------------------
# Materials: each returns (color socket, height socket, bump strength).
# Colours are authored in sRGB.
# --------------------------------------------------------------------------

def grass(g: Graph):
	# Clumps of blades: bright tips, dark roots between clumps, drier patches.
	patches = g.noise(1.2, scale=1.4, detail=3)
	clump_d = g.voronoi(5.0, scale=2.0, feature="F1", out="Distance", randomness=0.9)
	clump = g.math("SUBTRACT", 1.0, g.smooth(clump_d, 0.1, 0.55))
	blades = g.noise(10.0, 24.0, scale=2.0, detail=4, rough=0.6)
	blade_hi = g.smooth(blades, 0.4, 0.7)
	tone = g.clamp01(g.math("ADD", g.math("MULTIPLY", clump, 0.5), g.math("MULTIPLY", blade_hi, 0.5)))
	green = g.ramp(tone, [(0.0, _srgb((0.2, 0.34, 0.12))), (0.35, _srgb((0.32, 0.52, 0.18))),
		(0.7, _srgb((0.45, 0.65, 0.23))), (1.0, _srgb((0.64, 0.78, 0.34)))])
	dry = g.ramp(tone, [(0.05, _srgb((0.25, 0.22, 0.1))), (0.6, _srgb((0.55, 0.52, 0.26))), (1.0, _srgb((0.78, 0.74, 0.44)))])
	col = g.mix(g.smooth(patches, 0.58, 0.75), green, dry)
	flowers = g.voronoi(9.0, scale=2.0, feature="F1", out="Distance")
	dots = g.math("LESS_THAN", flowers, 0.05)
	col = g.mix(g.math("MULTIPLY", dots, 0.85), col, _srgb((0.97, 0.93, 0.72)))
	height = g.math("ADD", g.math("MULTIPLY", blades, 0.6), g.math("MULTIPLY", clump, 0.5))
	return col, height, 0.9


def dirt(g: Graph):
	# Packed, trodden earth: soft mottling, scattered small stones and only
	# faint, fine cracks (big ones read as desert).
	base_n = g.noise(1.5, scale=1.5, detail=5)
	base = g.ramp(base_n, [(0.3, _srgb((0.42, 0.31, 0.2))), (0.7, _srgb((0.55, 0.43, 0.29)))])
	mottle = g.noise(5.0, scale=2.0, detail=3)
	base = g.mix(0.35, base, g.ramp(mottle, [(0.35, _srgb((0.36, 0.27, 0.18))), (0.65, _srgb((0.6, 0.48, 0.33)))]), "OVERLAY")
	pebble_d = g.voronoi(2.6, scale=2.0, feature="F1", out="Distance", randomness=0.95)
	pebble_mask = g.smooth(g.noise(4.0, scale=2.5), 0.4, 0.55)
	pebble = g.math("MULTIPLY", g.smooth(g.math("SUBTRACT", 0.3, pebble_d), 0.0, 0.08), pebble_mask)
	pebble_col = g.ramp(g.noise(11.0, scale=3.0), [(0.3, _srgb((0.36, 0.31, 0.25))), (0.7, _srgb((0.52, 0.46, 0.38)))])
	col = g.mix(g.math("MULTIPLY", pebble, 0.75), base, pebble_col)
	cracks = g.voronoi(1.5, scale=2.0, feature="DISTANCE_TO_EDGE", out="Distance")
	crack = g.math("SUBTRACT", 1.0, g.smooth(cracks, 0.0, 0.03))
	crack = g.math("MULTIPLY", crack, g.smooth(g.noise(2.5, scale=2.0), 0.45, 0.6))
	col = g.mix(g.math("MULTIPLY", crack, 0.45), col, _srgb((0.25, 0.18, 0.12)))
	fine = g.noise(14.0, scale=2.0, detail=4)
	height = g.math("ADD", g.math("MULTIPLY", pebble, 0.6), g.math("MULTIPLY", fine, 0.3))
	height = g.math("ADD", height, g.math("MULTIPLY", mottle, 0.2))
	height = g.math("SUBTRACT", height, g.math("MULTIPLY", crack, 0.15))
	return col, height, 0.8


def rock(g: Graph):
	n = g.noise(2.0, scale=1.6, detail=7, rough=0.6)
	col = g.ramp(n, [(0.25, _srgb((0.34, 0.33, 0.32))), (0.5, _srgb((0.48, 0.47, 0.45))), (0.75, _srgb((0.6, 0.59, 0.56)))])
	cracks = g.voronoi(2.5, scale=1.5, feature="DISTANCE_TO_EDGE", out="Distance")
	crack = g.math("SUBTRACT", 1.0, g.smooth(cracks, 0.0, 0.05))
	col = g.mix(g.math("MULTIPLY", crack, 0.6), col, _srgb((0.18, 0.17, 0.17)))
	lichen = g.smooth(g.noise(3.0, scale=2.0, detail=3), 0.62, 0.72)
	col = g.mix(g.math("MULTIPLY", lichen, 0.5), col, _srgb((0.45, 0.5, 0.3)))
	height = g.math("SUBTRACT", n, g.math("MULTIPLY", crack, 0.5))
	return col, height, 1.2


def sand(g: Graph):
	n = g.noise(2.0, scale=1.5, detail=3)
	ripple = g.math("SINE", g.math("ADD", g.math("MULTIPLY", g.v, 2 * math.pi * 10), g.math("MULTIPLY", n, 3.0)))
	grains = g.noise(30.0, scale=2.0, detail=2)
	col = g.ramp(n, [(0.3, _srgb((0.76, 0.67, 0.5))), (0.7, _srgb((0.86, 0.78, 0.6)))])
	col = g.mix(0.25, col, g.ramp(grains, [(0.4, _srgb((0.6, 0.52, 0.4))), (0.6, _srgb((0.95, 0.9, 0.78)))]), "OVERLAY")
	height = g.math("ADD", g.math("MULTIPLY", ripple, 0.3), g.math("MULTIPLY", grains, 0.3))
	return col, height, 0.5


def snow(g: Graph):
	n = g.noise(1.8, scale=1.5, detail=5)
	col = g.ramp(n, [(0.3, _srgb((0.8, 0.85, 0.93))), (0.65, _srgb((0.95, 0.96, 0.99)))])
	sparkle = g.voronoi(20.0, scale=2.0, feature="F1", out="Distance")
	col = g.mix(g.math("MULTIPLY", g.math("LESS_THAN", sparkle, 0.05), 0.6), col, (1.0, 1.0, 1.0))
	return col, n, 0.4


def bark(g: Graph):
	# Ridges run up the trunk (v): stretched cells, deep grooves between.
	cells = g.voronoi(6.0, 1.2, scale=1.5, feature="DISTANCE_TO_EDGE", out="Distance")
	groove = g.smooth(cells, 0.0, 0.12)
	n = g.noise(8.0, 3.0, scale=2.0, detail=5)
	col = g.ramp(n, [(0.3, _srgb((0.24, 0.16, 0.1))), (0.7, _srgb((0.42, 0.3, 0.2)))])
	col = g.mix(g.math("SUBTRACT", 1.0, groove), col, _srgb((0.12, 0.08, 0.05)))
	height = g.math("ADD", groove, g.math("MULTIPLY", n, 0.3))
	return col, height, 1.4


def _grain(g: Graph, lines: int, colors):
	"""Wood grain running along u, with lines across v."""
	wob = g.noise(1.5, 6.0, scale=1.2, detail=3)
	phase = g.math("ADD", g.math("MULTIPLY", g.v, 2 * math.pi * lines), g.math("MULTIPLY", wob, 6.0))
	grain = g.math("MULTIPLY", g.math("ADD", g.math("SINE", phase), 1.0), 0.5)
	fine = g.noise(3.0, 40.0, scale=1.5, detail=4)
	col = g.ramp(g.math("ADD", g.math("MULTIPLY", grain, 0.6), g.math("MULTIPLY", fine, 0.4)),
		[(0.25, _srgb(colors[0])), (0.75, _srgb(colors[1]))])
	return col, grain, fine


def wood(g: Graph):
	col, grain, fine = _grain(g, 18, ((0.45, 0.3, 0.18), (0.66, 0.48, 0.3)))
	# Plank seams every quarter.
	seam = g.math("SUBTRACT", 1.0, g.smooth(g.math("ABSOLUTE", g.math("SUBTRACT",
		g.math("FRACT", g.math("MULTIPLY", g.v, 4.0)), 0.5)), 0.46, 0.5))
	col = g.mix(g.math("SUBTRACT", 1.0, seam), col, _srgb((0.15, 0.1, 0.06)))
	height = g.math("SUBTRACT", g.math("MULTIPLY", fine, 0.4), g.math("MULTIPLY", g.math("SUBTRACT", 1.0, seam), 0.8))
	return col, height, 0.6


def wood_dark(g: Graph):
	col, grain, fine = _grain(g, 14, ((0.2, 0.12, 0.07), (0.36, 0.23, 0.14)))
	return col, fine, 0.5


def stone_blocks(g: Graph):
	# Cut blocks: 4 across, 8 rows, alternate rows offset (tiles cleanly).
	bu = g.math("MULTIPLY", g.u, 4.0)
	bv = g.math("MULTIPLY", g.v, 8.0)
	row = g.math("FLOOR", bv)
	odd = g.math("MODULO", row, 2.0)
	bu = g.math("ADD", bu, g.math("MULTIPLY", odd, 0.5))
	fu = g.math("FRACT", bu)
	fv = g.math("FRACT", bv)
	edge = g.math("MINIMUM", g.math("MINIMUM", fu, g.math("SUBTRACT", 1.0, fu)),
		g.math("MULTIPLY", g.math("MINIMUM", fv, g.math("SUBTRACT", 1.0, fv)), 0.5))
	mortar = g.math("SUBTRACT", 1.0, g.smooth(edge, 0.0, 0.035))
	n = g.noise(3.0, scale=2.0, detail=6)
	col = g.ramp(n, [(0.3, _srgb((0.42, 0.41, 0.39))), (0.7, _srgb((0.6, 0.58, 0.55)))])
	col = g.mix(g.math("MULTIPLY", mortar, 0.85), col, _srgb((0.2, 0.19, 0.18)))
	height = g.math("SUBTRACT", g.math("MULTIPLY", n, 0.4), g.math("MULTIPLY", mortar, 0.8))
	return col, height, 1.0


def roof_tiles(g: Graph):
	# Kawara: rows of overlapping tiles (v), round channels (u).
	rows = 8
	cols = 6
	fv = g.math("FRACT", g.math("MULTIPLY", g.v, rows))
	chan = g.math("ABSOLUTE", g.math("SINE", g.math("MULTIPLY", g.u, math.pi * cols)))
	lap = g.math("POWER", fv, 1.5)
	height = g.math("ADD", g.math("MULTIPLY", chan, 0.6), g.math("MULTIPLY", lap, 0.5))
	n = g.noise(4.0, scale=1.5, detail=4)
	col = g.ramp(n, [(0.3, _srgb((0.18, 0.2, 0.24))), (0.7, _srgb((0.32, 0.34, 0.38)))])
	shade = g.ramp(height, [(0.0, (0.35, 0.35, 0.35)), (1.0, (1.0, 1.0, 1.0))])
	col = g.mix(1.0, col, shade, "MULTIPLY")
	return col, height, 1.5


def plaster(g: Graph):
	n = g.noise(2.0, scale=1.5, detail=6)
	col = g.ramp(n, [(0.3, _srgb((0.84, 0.8, 0.72))), (0.7, _srgb((0.94, 0.91, 0.85)))])
	stain = g.smooth(g.noise(1.2, scale=1.3, detail=3), 0.6, 0.75)
	col = g.mix(g.math("MULTIPLY", stain, 0.25), col, _srgb((0.6, 0.55, 0.45)))
	return col, n, 0.2


def shoji(g: Graph):
	# Paper panes in a wooden lattice: 3 across, 4 down.
	fu = g.math("FRACT", g.math("MULTIPLY", g.u, 3.0))
	fv = g.math("FRACT", g.math("MULTIPLY", g.v, 4.0))
	du = g.math("MINIMUM", fu, g.math("SUBTRACT", 1.0, fu))
	dv = g.math("MINIMUM", fv, g.math("SUBTRACT", 1.0, fv))
	frame = g.math("SUBTRACT", 1.0, g.smooth(g.math("MINIMUM", du, dv), 0.03, 0.05))
	paper_n = g.noise(6.0, scale=2.0, detail=5)
	paper = g.ramp(paper_n, [(0.3, _srgb((0.9, 0.86, 0.76))), (0.7, _srgb((0.98, 0.95, 0.87)))])
	col = g.mix(frame, paper, _srgb((0.3, 0.2, 0.12)))
	return col, frame, 0.8


def _lacquer(g: Graph, color, wear_color):
	n = g.noise(3.0, scale=1.5, detail=5)
	col = g.ramp(n, [(0.3, _srgb(tuple(c * 0.85 for c in color))), (0.7, _srgb(color))])
	wear = g.smooth(g.noise(2.0, scale=2.0, detail=6, rough=0.7), 0.64, 0.7)
	col = g.mix(wear, col, _srgb(wear_color))
	return col, g.math("SUBTRACT", 0.0, wear), 0.3


def red_lacquer(g: Graph):
	return _lacquer(g, (0.8, 0.17, 0.08), (0.36, 0.22, 0.14))


def black_lacquer(g: Graph):
	return _lacquer(g, (0.09, 0.09, 0.1), (0.3, 0.22, 0.15))


def _foliage(g: Graph, dark, mid, light):
	# Clusters of leaf shapes, each lit on one side, darker in between.
	cells = g.voronoi(7.0, scale=1.5, feature="F1", out="Distance")
	leaf = g.math("SUBTRACT", 1.0, g.smooth(cells, 0.15, 0.5))
	clump = g.noise(1.6, scale=1.4, detail=3)
	tone = g.math("ADD", g.math("MULTIPLY", leaf, 0.6), g.math("MULTIPLY", clump, 0.5))
	col = g.ramp(tone, [(0.2, _srgb(dark)), (0.55, _srgb(mid)), (0.9, _srgb(light))])
	return col, leaf, 0.8


def leaves(g: Graph):
	return _foliage(g, (0.1, 0.24, 0.1), (0.26, 0.48, 0.18), (0.52, 0.7, 0.28))


def maple(g: Graph):
	return _foliage(g, (0.45, 0.07, 0.04), (0.82, 0.3, 0.08), (0.98, 0.7, 0.22))


def pine_needles(g: Graph):
	streak = g.noise(18.0, 3.0, scale=2.0, detail=4)
	clump = g.noise(1.5, scale=1.4, detail=3)
	tone = g.math("ADD", g.math("MULTIPLY", streak, 0.6), g.math("MULTIPLY", clump, 0.45))
	col = g.ramp(tone, [(0.25, _srgb((0.06, 0.18, 0.12))), (0.55, _srgb((0.14, 0.34, 0.2))), (0.85, _srgb((0.3, 0.5, 0.26)))])
	return col, streak, 0.9


def straw(g: Graph):
	streak = g.noise(24.0, 2.0, scale=2.0, detail=5)
	col = g.ramp(streak, [(0.3, _srgb((0.56, 0.44, 0.22))), (0.7, _srgb((0.86, 0.74, 0.44)))])
	return col, streak, 0.7


def bamboo(g: Graph):
	fiber = g.noise(20.0, 2.0, scale=2.0, detail=4)
	n = g.noise(2.0, scale=1.5, detail=3)
	col = g.ramp(g.math("ADD", g.math("MULTIPLY", fiber, 0.4), g.math("MULTIPLY", n, 0.6)),
		[(0.3, _srgb((0.38, 0.52, 0.24))), (0.7, _srgb((0.58, 0.7, 0.34)))])
	return col, fiber, 0.4


def steel(g: Graph):
	brushed = g.noise(40.0, 1.5, scale=2.0, detail=3)
	col = g.ramp(brushed, [(0.3, _srgb((0.52, 0.54, 0.58))), (0.7, _srgb((0.72, 0.74, 0.78)))])
	return col, brushed, 0.15


def leather(g: Graph):
	pores = g.voronoi(14.0, scale=2.0, feature="F1", out="Distance")
	n = g.noise(2.5, scale=1.5, detail=4)
	col = g.ramp(n, [(0.3, _srgb((0.26, 0.16, 0.1))), (0.7, _srgb((0.42, 0.27, 0.16)))])
	return col, pores, 0.5


def grip_wrap(g: Graph):
	# Tsuka-ito: dark cord crossing in diamonds over pale rayskin.
	a = g.math("FRACT", g.math("MULTIPLY", g.math("ADD", g.u, g.v), 4.0))
	b = g.math("FRACT", g.math("MULTIPLY", g.math("SUBTRACT", g.u, g.v), 4.0))
	cord = g.math("MAXIMUM", g.smooth(g.math("ABSOLUTE", g.math("SUBTRACT", a, 0.5)), 0.22, 0.3),
		g.smooth(g.math("ABSOLUTE", g.math("SUBTRACT", b, 0.5)), 0.22, 0.3))
	skin = g.ramp(g.noise(30.0, scale=2.0, detail=2), [(0.3, _srgb((0.75, 0.72, 0.65))), (0.7, _srgb((0.92, 0.9, 0.84)))])
	# `cord` is 1 along the crossing lines: dark cord there, rayskin in the diamonds.
	col = g.mix(cord, skin, _srgb((0.08, 0.07, 0.09)))
	return col, cord, 0.8


# name: (builder, size in px, roughness for the game material)
MATERIALS = {
	"grass": (grass, 1024, 0.95),
	"dirt": (dirt, 1024, 0.95),
	"rock": (rock, 1024, 0.9),
	"sand": (sand, 512, 0.95),
	"snow": (snow, 512, 0.8),
	"bark": (bark, 512, 0.95),
	"wood": (wood, 512, 0.85),
	"wood_dark": (wood_dark, 512, 0.8),
	"stone_blocks": (stone_blocks, 512, 0.9),
	"roof_tiles": (roof_tiles, 512, 0.7),
	"plaster": (plaster, 512, 0.95),
	"shoji": (shoji, 512, 0.95),
	"red_lacquer": (red_lacquer, 512, 0.45),
	"black_lacquer": (black_lacquer, 512, 0.45),
	"leaves": (leaves, 512, 0.9),
	"maple": (maple, 512, 0.9),
	"pine_needles": (pine_needles, 512, 0.9),
	"straw": (straw, 512, 0.95),
	"bamboo": (bamboo, 512, 0.6),
	"steel": (steel, 256, 0.3),
	"leather": (leather, 256, 0.8),
	"grip_wrap": (grip_wrap, 256, 0.8),
}


def bake(name: str, size: int) -> None:
	bpy.ops.wm.read_factory_settings(use_empty=True)
	scene = bpy.context.scene
	scene.render.engine = "CYCLES"
	scene.cycles.device = "CPU"
	scene.cycles.samples = 1
	scene.cycles.bake_type = "EMIT"
	bpy.ops.mesh.primitive_plane_add(size=1.0)
	obj = bpy.context.active_object
	mat = bpy.data.materials.new(name)
	obj.data.materials.append(mat)
	g = Graph(mat)
	color, height, strength = MATERIALS[name][0](g)

	# Crevices darker: a painted, lit-from-above look that survives flat lighting.
	cavity = g.ramp(height, [(0.0, (0.7, 0.7, 0.7)), (1.0, (1.0, 1.0, 1.0))])
	shaded = g.mix(0.5, color, cavity, "MULTIPLY")
	emit = g.node("ShaderNodeEmission", Color=shaded)
	out = g.node("ShaderNodeOutputMaterial", Surface=emit.outputs[0])

	img = bpy.data.images.new(f"{name}_albedo", size, size)
	tex = g.nt.nodes.new("ShaderNodeTexImage")
	tex.image = img
	g.nt.nodes.active = tex
	bpy.ops.object.bake(type="EMIT", margin=0)
	_save(img, OUT / f"{name}_albedo.png")

	# Normal map from the height: bake the bumped shading normal.
	bump = g.node("ShaderNodeBump", Height=height, Strength=strength, Distance=0.02)
	bsdf = g.node("ShaderNodeBsdfPrincipled", Normal=bump.outputs[0])
	g.nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
	nimg = bpy.data.images.new(f"{name}_normal", size // 2, size // 2)
	nimg.colorspace_settings.name = "Non-Color"
	tex.image = nimg
	g.nt.nodes.active = tex
	scene.cycles.bake_type = "NORMAL"
	bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", margin=0)
	_save(nimg, OUT / f"{name}_normal.png")


def _save(img: bpy.types.Image, path: Path) -> None:
	img.filepath_raw = str(path)
	img.file_format = "PNG"
	img.save()
	print(f"  {path}")


def main() -> int:
	global OUT
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
	p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	p.add_argument("--only", action="append", choices=sorted(MATERIALS))
	p.add_argument("--size-scale", type=float, default=1.0)
	p.add_argument("--out", type=Path, default=OUT)
	args = p.parse_args(argv)
	OUT = args.out
	OUT.mkdir(parents=True, exist_ok=True)
	for name in args.only or MATERIALS:
		print(name)
		bake(name, max(64, int(MATERIALS[name][1] * args.size_scale)))
	return 0


if __name__ == "__main__":
	sys.exit(main())
