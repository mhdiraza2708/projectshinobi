class_name VfxSpiral
extends MeshInstance3D
## Ribbons winding round an axis, camera-facing like VfxTrail: the bands of
## a whirlwind, wind curling off a blade, the twist of a water lance. The
## axis is the node's own +Y (turn the node to aim it). Each ribbon runs
## from the base (y = 0) up to `length`, its radius easing from `radius_base`
## to `radius_tip`, and the whole bundle spins. With a `lifetime` it fades
## in, thins away and frees itself (0 = lasts until you free it).

var color := Color(0.55, 1.0, 0.7, 0.8)
var ribbons := 3
var length := 3.0
var radius_base := 0.3
var radius_tip := 0.3
## Full turns each ribbon makes along its length.
var turns := 1.5
var width := 0.14
## Radians per second round the axis (negative turns the other way).
var spin := 8.0
var additive := false
var lifetime := 0.0

## Points per ribbon.
const SEGMENTS := 18

var _age := 0.0
var _imesh := ImmediateMesh.new()


func _ready() -> void:
	mesh = _imesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = Vfx.surface_material(Vfx.tex(&"trail"), additive)
	# The ribbons are drawn in code, so say how big the thing is.
	var reach := maxf(radius_base, radius_tip) + width
	custom_aabb = AABB(Vector3(-reach, -width, -reach), Vector3(reach * 2.0, length + width * 2.0, reach * 2.0))


func _process(delta: float) -> void:
	_age += delta
	if lifetime > 0.0 and _age >= lifetime:
		queue_free()
		return
	_draw()


## How much of the ribbons shows right now: in over a moment, out over the
## last third of the lifetime.
func visibility() -> float:
	if lifetime <= 0.0:
		return 1.0
	return smoothstep(0.0, 0.12, _age) * (1.0 - smoothstep(0.65, 1.0, _age / lifetime))


func _draw() -> void:
	_imesh.clear_surfaces()
	var shown := visibility()
	if shown <= 0.01:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var cam_local := global_transform.affine_inverse() * cam.global_position if cam else Vector3.UP * 100.0
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in ribbons:
		var points := PackedVector3Array()
		for s in SEGMENTS + 1:
			var k := float(s) / SEGMENTS
			var angle := TAU * i / ribbons + spin * _age + TAU * turns * k
			var rad := lerpf(radius_base, radius_tip, k)
			points.append(Vector3(cos(angle) * rad, k * length, sin(angle) * rad))
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var prev_c := Color()
		for s in points.size():
			var k := float(s) / SEGMENTS
			var dir := (points[mini(s + 1, points.size() - 1)] - points[maxi(s - 1, 0)]).normalized()
			var side := dir.cross(cam_local - points[s])
			side = side.normalized() if side.length() > 1e-5 else Vector3.RIGHT
			# Thin at both ends, full in the middle.
			var body := sin(PI * k)
			var half := width * 0.5 * (0.2 + 0.8 * body)
			var l := points[s] - side * half
			var r := points[s] + side * half
			var c := Color(color, color.a * pow(body, 0.7) * shown)
			if s > 0:
				var v0 := float(s - 1) / SEGMENTS
				_vert(prev_l, prev_c, Vector2(0, v0))
				_vert(prev_r, prev_c, Vector2(1, v0))
				_vert(l, c, Vector2(0, k))
				_vert(prev_r, prev_c, Vector2(1, v0))
				_vert(r, c, Vector2(1, k))
				_vert(l, c, Vector2(0, k))
			prev_l = l
			prev_r = r
			prev_c = c
	_imesh.surface_end()


func _vert(p: Vector3, c: Color, uv: Vector2) -> void:
	_imesh.surface_set_color(c)
	_imesh.surface_set_uv(uv)
	_imesh.surface_add_vertex(p)
