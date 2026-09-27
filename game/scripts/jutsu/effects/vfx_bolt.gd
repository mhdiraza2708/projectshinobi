class_name VfxBolt
extends MeshInstance3D
## A jagged bolt of lightning between two points, re-forked many times a
## second so it crackles. Drawn as a wide soft glow with a white-hot core,
## facing the camera. `a` and `b` are world positions (update them to make
## the bolt follow something). Frees itself after `lifetime` (0 = never).

var a := Vector3.ZERO
var b := Vector3.UP
var color := Color(0.75, 0.85, 1.0)
var width := 0.08
var lifetime := 0.25
## Sideways wander, as a share of the bolt's length.
var chaos := 0.22
## Small side branches.
var branches := 2
var rng := RandomNumberGenerator.new()

var _age := 0.0
var _regen := 0.0
var _paths: Array = []   # Array of PackedVector3Array
var _imesh := ImmediateMesh.new()
var _glow_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _imesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A coloured glow that holds up in daylight, and an additive hot core.
	_glow_mat = Vfx.surface_material(Vfx.tex(&"trail"), false)
	_core_mat = Vfx.surface_material(Vfx.tex(&"trail"), true)
	custom_aabb = AABB(Vector3(-5000, -5000, -5000), Vector3(10000, 10000, 10000))
	rng.randomize()
	_fork()


func _process(delta: float) -> void:
	_age += delta
	if lifetime > 0.0 and _age >= lifetime:
		queue_free()
		return
	_regen -= delta
	if _regen <= 0.0:
		_regen = 0.045
		_fork()
	_draw()


## A new random path (and branches) between a and b.
func _fork() -> void:
	_paths = [_jagged(a, b, chaos)]
	var main: PackedVector3Array = _paths[0]
	for i in branches:
		var from := main[rng.randi_range(1, main.size() - 2)]
		var dir := (b - a)
		var off := _perpendicular(dir) * dir.length() * rng.randf_range(0.15, 0.35)
		_paths.append(_jagged(from, from + dir * rng.randf_range(0.15, 0.3) + off, chaos * 1.3))


func _jagged(from: Vector3, to: Vector3, amount: float) -> PackedVector3Array:
	var pts := PackedVector3Array([from, to])
	var spread := from.distance_to(to) * amount
	for level in 4:
		var next := PackedVector3Array()
		for i in pts.size() - 1:
			next.append(pts[i])
			var mid := (pts[i] + pts[i + 1]) * 0.5
			next.append(mid + _perpendicular(to - from) * rng.randf_range(-spread, spread))
		next.append(pts[-1])
		pts = next
		spread *= 0.5
	return pts


func _perpendicular(dir: Vector3) -> Vector3:
	var p := dir.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
	return p.normalized() if p.length() > 1e-5 else Vector3.RIGHT


func _draw() -> void:
	_imesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var fade := 1.0 - (_age / lifetime if lifetime > 0.0 else 0.0)
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _glow_mat)
	for k in _paths.size():
		_strip(_paths[k], width * (3.0 if k == 0 else 1.8), Color(color, 0.55 * fade), cam)
	_imesh.surface_end()
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _core_mat)
	for k in _paths.size():
		_strip(_paths[k], width * (1.0 if k == 0 else 0.55), Color(Color(1, 1, 1).lerp(color, 0.2), fade), cam)
	_imesh.surface_end()


func _strip(path: PackedVector3Array, w: float, c: Color, cam: Camera3D) -> void:
	for i in path.size() - 1:
		var p0 := path[i]
		var p1 := path[i + 1]
		var to_cam := (cam.global_position - p0) if cam else Vector3.UP
		var side := (p1 - p0).cross(to_cam).normalized() * w * 0.5
		if side.length() < 1e-6:
			side = Vector3.RIGHT * w * 0.5
		var verts := [[p0 - side, Vector2(0, 0)], [p0 + side, Vector2(1, 0)], [p1 - side, Vector2(0, 1)],
			[p0 + side, Vector2(1, 0)], [p1 + side, Vector2(1, 1)], [p1 - side, Vector2(0, 1)]]
		for v: Array in verts:
			_imesh.surface_set_color(c)
			_imesh.surface_set_uv(v[1])
			_imesh.surface_add_vertex(v[0])
