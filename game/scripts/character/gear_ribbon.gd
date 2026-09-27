class_name GearRibbon
extends MeshInstance3D
## A cloth tail (a headband's knot ends): a short chain that hangs from its
## parent, swings when the head moves, stays outside the head and ends in a
## swallowtail notch. Simulated and drawn in world space.

## Where it hangs from and the head it must stay outside of, in the
## parent's space.
var anchor := Vector3.ZERO
var head_center := Vector3.ZERO
var head_radius := 0.1
var length := 0.18
var width := 0.03
## Which way it tends to flutter (-1 left, 1 right).
var side := 1.0
var color := Color(0.7, 0.2, 0.12)
var segments := 7

var _p := PackedVector3Array()
var _prev := PackedVector3Array()
var _imesh := ImmediateMesh.new()
var _time := 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _imesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mat := Toon.flat(color, 0.95)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	material_override = mat
	set_meta(&"gear", true)
	reset()


## Hangs the tail straight down from its anchor.
func reset() -> void:
	var xf := _parent_xf()
	var a := xf * anchor
	var seg := _seg_len(xf)
	_p.resize(segments + 1)
	_prev.resize(segments + 1)
	for i in segments + 1:
		_p[i] = a + (Vector3.DOWN + xf.basis.z.normalized() * 0.25).normalized() * seg * i
		_prev[i] = _p[i]
	_draw(xf)


func points() -> PackedVector3Array:
	return _p


func _parent_xf() -> Transform3D:
	var parent := get_parent() as Node3D
	return parent.global_transform if parent else Transform3D.IDENTITY


func _seg_len(xf: Transform3D) -> float:
	return length * xf.basis.get_scale().x / segments


func _process(delta: float) -> void:
	var xf := _parent_xf()
	var a := xf * anchor
	if _p.is_empty() or a.distance_to(_p[0]) > 1.0:
		reset()
		return
	_time += delta
	var dt := minf(delta, 1.0 / 30.0)
	var scale := xf.basis.get_scale().x
	var seg := _seg_len(xf)
	var center := xf * head_center
	var radius := head_radius * scale
	# Gravity, a light breeze across and behind, and damping.
	var right := xf.basis.x.normalized()
	var back := xf.basis.z.normalized()
	var breeze := right * side * (0.7 + 0.5 * sin(_time * 2.3 + side)) + back * (0.9 + 0.6 * sin(_time * 1.7))
	var force := Vector3(0, -9.8, 0) + breeze * 1.4
	for i in range(1, _p.size()):
		var v := (_p[i] - _prev[i]) * 0.9
		_prev[i] = _p[i]
		_p[i] += v + force * dt * dt
	for iteration in 4:
		_p[0] = a
		for i in range(1, _p.size()):
			var d := _p[i] - _p[i - 1]
			_p[i] = _p[i - 1] + (d.normalized() if d.length() > 1e-6 else Vector3.DOWN) * seg
			var off := _p[i] - center
			if off.length() < radius:
				_p[i] = center + off.normalized() * radius
	_draw(xf)


func _draw(xf: Transform3D) -> void:
	_imesh.clear_surfaces()
	if _p.size() < 2:
		return
	var scale := xf.basis.get_scale().x
	var center := xf * head_center
	var n := _p.size()
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for i in n:
		var dir := (_p[mini(i + 1, n - 1)] - _p[maxi(i - 1, 0)]).normalized()
		var out := _p[i] - center
		out.y = 0.0
		var s := dir.cross(out).normalized() if out.length() > 1e-5 else xf.basis.x.normalized()
		if s.length() < 0.5:
			s = xf.basis.x.normalized()
		# Slightly wider at the knot, and a gentle twist along the length.
		var t := float(i) / (n - 1)
		var w := width * scale * lerpf(1.1, 0.9, t) * 0.5
		s = s.rotated(dir, 0.35 * t * side)
		left.append(_p[i] - s * w)
		right.append(_p[i] + s * w)
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n - 2:
		var shade := lerpf(1.0, 0.82, float(i) / n)
		_quad(left[i], right[i], left[i + 1], right[i + 1], Color(shade, shade, shade))
	# Swallowtail end: two points with a notch between them.
	var last := n - 1
	var dir_end := (_p[last] - _p[last - 1]).normalized()
	var notch := _p[last] - dir_end * width * scale * 0.55
	var c := Color(0.8, 0.8, 0.8)
	_tri(left[last - 1], right[last - 1], notch, c)
	_tri(left[last - 1], notch, left[last], c)
	_tri(right[last - 1], right[last], notch, c)
	_imesh.surface_end()


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(a, b, c, col)
	_tri(b, d, c, col)


func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	for v in [a, b, c]:
		_imesh.surface_set_normal(nrm)
		_imesh.surface_set_color(col)
		_imesh.surface_add_vertex(v)
