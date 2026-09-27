class_name VfxTrail
extends MeshInstance3D
## A ribbon streaming behind whatever it's attached to: it records where its
## parent has been, faces the camera, and tapers and fades with age. When
## the parent goes, call Vfx.linger() so the ribbon fades out in place.

var color := Color.WHITE
var width := 0.3
## How long a point of the ribbon lasts, in seconds.
var lifetime := 0.25
var additive := true
var emitting := true

var _points: Array = []   # [position, age]
var _imesh := ImmediateMesh.new()
var _source: Node3D


func _ready() -> void:
	_source = get_parent() as Node3D
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _imesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = Vfx.surface_material(Vfx.tex(&"trail"), additive)
	# Wide enough to cover wherever the ribbon goes.
	custom_aabb = AABB(Vector3(-5000, -5000, -5000), Vector3(10000, 10000, 10000))


func _process(delta: float) -> void:
	for p: Array in _points:
		p[1] += delta
	while not _points.is_empty() and _points[0][1] > lifetime:
		_points.pop_front()
	if emitting and is_instance_valid(_source) and _source.is_inside_tree():
		var pos := _source.global_position
		if _points.is_empty() or (_points[-1][0] as Vector3).distance_to(pos) > 0.04:
			_points.append([pos, 0.0])
		else:
			_points[-1][0] = pos
	if not emitting and _points.is_empty():
		queue_free()
		return
	_draw()


func _draw() -> void:
	_imesh.clear_surfaces()
	var n := _points.size()
	if n < 2:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_c := Color()
	var prev_v := 0.0
	for i in n:
		var p: Vector3 = _points[i][0]
		var age: float = _points[i][1]
		var ahead: Vector3 = _points[mini(i + 1, n - 1)][0]
		var behind: Vector3 = _points[maxi(i - 1, 0)][0]
		var dir := (ahead - behind).normalized()
		var to_cam := (cam.global_position - p) if cam else Vector3.UP
		var side := dir.cross(to_cam).normalized()
		if side.length() < 0.5:
			side = Vector3.RIGHT
		var life := clampf(1.0 - age / lifetime, 0.0, 1.0)
		var w := width * 0.5 * (0.25 + 0.75 * life)
		var l := p - side * w
		var r := p + side * w
		var c := Color(color, color.a * pow(life, 1.4))
		var v := float(i) / (n - 1)
		if i > 0:
			_vert(prev_l, prev_c, Vector2(0, prev_v))
			_vert(prev_r, prev_c, Vector2(1, prev_v))
			_vert(l, c, Vector2(0, v))
			_vert(prev_r, prev_c, Vector2(1, prev_v))
			_vert(r, c, Vector2(1, v))
			_vert(l, c, Vector2(0, v))
		prev_l = l
		prev_r = r
		prev_c = c
		prev_v = v
	_imesh.surface_end()


func _vert(p: Vector3, c: Color, uv: Vector2) -> void:
	_imesh.surface_set_color(c)
	_imesh.surface_set_uv(uv)
	_imesh.surface_add_vertex(p)
