class_name ShoreFoam
extends RefCounted
## The white surf along a coast: a strip of mesh that follows the waterline
## and carries the foam shader (assets/shaders/foam.gdshader). An island
## traces its own coast from its height map; an islet knows its outline.
## One shared material serves them all.

const SHADER := preload("res://assets/shaders/foam.gdshader")
## How many points trace an island's coast.
const COAST_STEPS := 144
## The strip starts this far on the land side (the ground hides it) and
## reaches this far out to sea, in metres.
const LAND_SIDE := 2.6
const REACH := 7.0
## Where (from the middle) a trace begins looking for the waterline.
const SEARCH_START := 79.0

static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material


## How far from the middle the waterline lies at each of `steps` bearings,
## given the ground's height at (x, z): the outermost place that stands
## above `level`, found by walking in from the sea.
static func trace_coast(height_at: Callable, level: float, steps := COAST_STEPS) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(steps)
	for i in steps:
		var dir := Vector2.from_angle(TAU * i / steps)
		var r := SEARCH_START
		while r > 0.0 and float(height_at.call(dir.x * r, dir.y * r)) < level:
			r -= 1.0
		# The crossing lies in this last metre: bisect it.
		var lo := r
		var hi := r + 1.0
		for k in 6:
			var mid := (lo + hi) * 0.5
			if float(height_at.call(dir.x * mid, dir.y * mid)) < level:
				hi = mid
			else:
				lo = mid
		out[i] = (lo + hi) * 0.5
	return out


## A closed strip around `centre` (x, z) along a shoreline given as the
## distance from the middle at evenly spaced bearings, at height `y`. Add
## several to one SurfaceTool to make a single mesh of them. A `lift` raises
## the strip's inner edge into a skirt that climbs the shore (for a cliff,
## which would hide a flat strip from a low angle).
static func add_ring(st: SurfaceTool, centre: Vector2, radii: PackedFloat32Array, y: float,
		reach := REACH, land_side := LAND_SIDE, lift := 0.0) -> void:
	var n := radii.size()
	st.set_normal(Vector3.UP)
	# A skirt starts at full strength where it meets the shore.
	var inner_d := -land_side if lift <= 0.0 else 0.0
	for i in n:
		var j := (i + 1) % n
		var d0 := Vector2.from_angle(TAU * i / n)
		var d1 := Vector2.from_angle(TAU * (i + 1) / n)
		# Corners: land side and sea side of this bearing and the next.
		var in0 := centre + d0 * (radii[i] - land_side)
		var out0 := centre + d0 * (radii[i] + reach)
		var in1 := centre + d1 * (radii[j] - land_side)
		var out1 := centre + d1 * (radii[j] + reach)
		for c: Array in [[in0, y + lift, inner_d], [out0, y, reach], [in1, y + lift, inner_d],
				[in1, y + lift, inner_d], [out0, y, reach], [out1, y, reach]]:
			st.set_uv(Vector2(reach, c[2]))
			st.add_vertex(Vector3(c[0].x, c[1], c[0].y))


## One island's (or islet's) foam as a node: `radii` as for add_ring, at
## height `y` in the parent's space. A `lift` (a cliff coast) gives it the
## skirt that climbs the rock.
static func make(radii: PackedFloat32Array, y: float, centre := Vector2.ZERO, reach := REACH, lift := 0.0) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	add_ring(st, centre, radii, y, reach, 0.3 if lift > 0.0 else LAND_SIDE, lift)
	st.set_material(material())
	var mi := MeshInstance3D.new()
	mi.name = "Foam"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
