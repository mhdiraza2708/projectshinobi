class_name VfxBolt
extends MeshInstance3D
## A jagged bolt of lightning between two points, re-forked many times a
## second so it crackles. Drawn as a wide soft halo, a coloured glow and a
## white-hot core, facing the camera. `a` and `b` are world positions (move
## them and the bolt stays attached, keeping its shape). It crackles for the
## first part of its life, then holds its last shape and fades away slowly:
## the afterglow. Frees itself after `lifetime` (0 = never; it crackles
## for as long as it lives).

var a := Vector3.ZERO
var b := Vector3.UP
var color := Color(0.75, 0.85, 1.0)
var width := 0.08
var lifetime := 0.25
## Sideways wander, as a share of the bolt's length.
var chaos := 0.22
## Small side branches.
var branches := 2
## The share of its life it spends crackling before it holds still and fades.
var crackle := 0.55
var rng := RandomNumberGenerator.new()

## The cool edge of the halo, so a bolt shows against pale sky and sand.
const HALO_TINT := Color(0.55, 0.5, 1.0)

var _age := 0.0
var _regen := 0.0
var _flicker := 1.0
## Array of PackedVector3Array, each in the bolt's own frame: z runs from a
## to b (0 to 1), x and y are sideways, all as shares of its length.
var _paths: Array = []
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
	if lifetime <= 0.0 or _age < lifetime * crackle:
		_regen -= delta
		if _regen <= 0.0:
			_regen = 0.045
			_fork()
	_draw()


## A new random path (and branches) between a and b.
func _fork() -> void:
	var along := Vector3(0, 0, 1)
	_paths = [_jagged(Vector3.ZERO, along, chaos)]
	var main: PackedVector3Array = _paths[0]
	for i in branches:
		var from := main[rng.randi_range(1, main.size() - 2)]
		var off := _perpendicular(along) * rng.randf_range(0.15, 0.35)
		_paths.append(_jagged(from, from + along * rng.randf_range(0.15, 0.3) + off, chaos * 1.3))
	# Each fork flares a little differently, which reads as crackle.
	_flicker = rng.randf_range(0.7, 1.0)


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


## A path from the bolt's own frame placed between a and b in the world.
func _to_world(path: PackedVector3Array) -> PackedVector3Array:
	var span := b - a
	var length := span.length()
	var z := span / length if length > 1e-5 else Vector3.UP
	var x := z.cross(Vector3.UP)
	x = x.normalized() if x.length() > 1e-4 else z.cross(Vector3.RIGHT).normalized()
	var y := z.cross(x)
	var out := PackedVector3Array()
	for p in path:
		out.append(a + (x * p.x + y * p.y + z * p.z) * length)
	return out


func _draw() -> void:
	_imesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var age_share := _age / lifetime if lifetime > 0.0 else 0.0
	# Bright at the strike, a long tail of glow after, the core thinning.
	var fade := pow(1.0 - age_share, 1.5) * _flicker
	var thin := lerpf(1.0, 0.45, age_share)
	var world: Array = _paths.map(_to_world)
	var halo := color.lerp(HALO_TINT, 0.4)
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _glow_mat)
	for k in world.size():
		_strip(world[k], width * (7.0 if k == 0 else 4.0), Color(halo, 0.22 * fade), cam)
		_strip(world[k], width * (3.0 if k == 0 else 1.8), Color(color, 0.6 * fade), cam)
	_imesh.surface_end()
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _core_mat)
	for k in world.size():
		_strip(world[k], width * thin * (1.0 if k == 0 else 0.55), Color(Color(1, 1, 1).lerp(color, 0.2), fade), cam)
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
