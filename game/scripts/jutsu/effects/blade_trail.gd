class_name BladeTrail
extends MeshInstance3D
## A ribbon of light behind a drawn sword, and the glint that runs up its
## blade as it leaves the scabbard. It's a child of the sword node (the
## "Katana", whose local -Y runs from the guard down the blade), one per
## sword, so it goes when the sword does.
##
## While `emitting` it samples the blade's base and point in world space each
## frame and draws the surface they sweep through, fading with age, plus a
## thin camera-facing line along the point's path so a cut still shows when
## the sheet is edge-on to the camera. Switch `emitting` off and the last
## of it fades in `lifetime` seconds.

const TRAIL_TEXTURE := &"trail"
## Samples kept at most, and the closest two may be in time (a fast frame
## rate refreshes the newest sample instead of piling up more).
const CAPACITY := 24
const MIN_STEP := 1.0 / 120.0
## Each gap between samples is drawn as this many curve segments, so a
## quick swing is round and not a polygon.
const SUBDIVISIONS := 3
const POINTS := (CAPACITY - 1) * SUBDIVISIONS + 1
## A blade point that moves this far (metres) in one frame was carried off
## (a teleport), not swung: the ribbon starts afresh.
const MAX_JUMP := 3.0
## Where along the blade (0 at the guard, 1 at the point) the ribbon starts.
const FROM := 0.12
## Width in metres of the bright line the point draws.
const LINE_WIDTH := 0.12
const GLINT_TIME := 0.16

static var _materials: Dictionary = {}

## Pale steel with a faint cool tint.
var color := Color(0.72, 0.84, 1.0)
## How long a sample of the ribbon lasts, in seconds.
var lifetime := 0.15
var emitting := false:
	set(v):
		emitting = v
		if v and is_inside_tree():
			_wake()

var _imesh := ImmediateMesh.new()
# The samples, oldest first from `_first`: blade base and point, and age.
var _base := PackedVector3Array()
var _tip := PackedVector3Array()
var _age := PackedFloat32Array()
var _first := 0
var _count := 0
# The curve through them, rebuilt each frame (base, point, life left 0-1).
var _curve_base := PackedVector3Array()
var _curve_tip := PackedVector3Array()
var _curve_life := PackedFloat32Array()
var _flare: MeshInstance3D
var _glint_t := -1.0


func _init() -> void:
	name = "BladeTrail"
	_base.resize(CAPACITY)
	_tip.resize(CAPACITY)
	_age.resize(CAPACITY)
	_curve_base.resize(POINTS)
	_curve_tip.resize(POINTS)
	_curve_life.resize(POINTS)
	# Gear is left out of the body's measurements and restyling.
	set_meta(&"gear", true)


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _imesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = _material(TRAIL_TEXTURE, false)
	# Wide enough to cover wherever the ribbon goes.
	custom_aabb = AABB(Vector3(-5000, -5000, -5000), Vector3(10000, 10000, 10000))
	if emitting or _glint_t >= 0.0:
		_wake()
	else:
		set_process(false)


func _exit_tree() -> void:
	_sleep()


## Whether any of the ribbon is showing.
func is_showing() -> bool:
	return _count > 0


## A bright flare runs from the guard to the point of the blade (the sword
## has just been drawn).
func glint() -> void:
	if _flare == null:
		_flare = MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		_flare.mesh = quad
		_flare.material_override = _material(&"star", true)
		_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_flare)
	_glint_t = 0.0
	_flare.visible = true
	if is_inside_tree():
		_wake()


func _process(delta: float) -> void:
	var sword := get_parent() as Node3D
	if sword == null:
		_sleep()
		return
	# A sheathed sword shows nothing, and starts afresh when it's drawn again.
	if not sword.visible:
		_count = 0
	for i in _count:
		_age[_slot(i)] += delta
	while _count > 0 and _age[_slot(0)] > lifetime:
		_first = (_first + 1) % CAPACITY
		_count -= 1
	if emitting and sword.visible:
		_add_sample(sword)
	if _glint_t >= 0.0:
		_glint_t += delta
		if _glint_t >= GLINT_TIME or not sword.visible:
			_glint_t = -1.0
			_flare.visible = false
	if not emitting and _count == 0 and _glint_t < 0.0:
		_imesh.clear_surfaces()
		_sleep()


## Draws the ribbon and the glint where the blade is now. Runs just before
## each frame is drawn (see _wake): the skeleton only settles after every
## node's _process, so the blade is read late, or the ribbon would trail a
## frame behind it.
func refresh() -> void:
	var sword := get_parent() as Node3D
	if sword == null:
		return
	if emitting and sword.visible and _count > 0:
		var last := _slot(_count - 1)
		var base := _blade_point(sword, FROM)
		if _count > 1 and _base[_slot(_count - 2)].distance_to(base) > MAX_JUMP:
			# Carried off, not swung: the ribbon starts afresh here.
			_first = last
			_count = 1
		_base[last] = base
		_tip[last] = _blade_point(sword, 1.0)
	_rebuild()
	if _glint_t >= 0.0:
		var guard := _blade_point(sword, 0.0)
		var point := _blade_point(sword, 1.0)
		var k := _glint_t / GLINT_TIME
		# Quick off the guard, easing into the point, swelling in the middle.
		_flare.global_position = guard.lerp(point, ease(k, 0.6))
		_flare.scale = Vector3.ONE * guard.distance_to(point) * 0.65 * sin(k * PI)


func _wake() -> void:
	set_process(true)
	if not RenderingServer.frame_pre_draw.is_connected(refresh):
		RenderingServer.frame_pre_draw.connect(refresh)


func _sleep() -> void:
	set_process(false)
	if RenderingServer.frame_pre_draw.is_connected(refresh):
		RenderingServer.frame_pre_draw.disconnect(refresh)


func _slot(i: int) -> int:
	return (_first + i) % CAPACITY


## A point on the blade, `t` of the way from the guard to the point.
func _blade_point(sword: Node3D, t: float) -> Vector3:
	return sword.to_global(Vector3(0.0, CharacterGear.GUARD_Y - t * CharacterGear.BLADE_LENGTH, 0.0))


## Starts a new sample when one is due. It begins where the last one was;
## refresh() puts it on the blade.
func _add_sample(sword: Node3D) -> void:
	if _count > 0 and _age[_slot(_count - 1)] < MIN_STEP:
		return
	var from := _slot(_count - 1)
	var base := _base[from] if _count > 0 else _blade_point(sword, FROM)
	var tip := _tip[from] if _count > 0 else _blade_point(sword, 1.0)
	if _count == CAPACITY:
		_first = (_first + 1) % CAPACITY
		_count -= 1
	var at := _slot(_count)
	_base[at] = base
	_tip[at] = tip
	_age[at] = 0.0
	_count += 1


## Smooths the samples into a curve (Catmull-Rom through base and point) and
## draws the sheet between the two and the line along the point.
func _rebuild() -> void:
	_imesh.clear_surfaces()
	if _count < 2:
		return
	var n := (_count - 1) * SUBDIVISIONS + 1
	for k in n:
		var i := mini(floori(float(k) / SUBDIVISIONS), _count - 2)
		var t := float(k - i * SUBDIVISIONS) / SUBDIVISIONS
		var s0 := _slot(maxi(i - 1, 0))
		var s1 := _slot(i)
		var s2 := _slot(i + 1)
		var s3 := _slot(mini(i + 2, _count - 1))
		_curve_base[k] = _base[s1].cubic_interpolate(_base[s2], _base[s0], _base[s3], t)
		_curve_tip[k] = _tip[s1].cubic_interpolate(_tip[s2], _tip[s0], _tip[s3], t)
		_curve_life[k] = clampf(1.0 - lerpf(_age[s1], _age[s2], t) / lifetime, 0.0, 1.0)
	var hot := color.lerp(Color.WHITE, 0.7)

	# The sheet the blade swept: faint at the guard, bright along the edge.
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for k in n:
		var v := float(k) / (n - 1)
		var fade := pow(_curve_life[k], 1.5)
		_vertex(_curve_base[k], Color(color, 0.0), Vector2(0.0, v))
		_vertex(_curve_tip[k], Color(hot, 0.8 * fade), Vector2(0.5, v))
	_imesh.surface_end()

	# The line the point draws, facing the camera.
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for k in n:
		var tip := _curve_tip[k]
		var along := _curve_tip[mini(k + 1, n - 1)] - _curve_tip[maxi(k - 1, 0)]
		var side := along.cross((cam.global_position - tip) if cam else Vector3.UP)
		side = side.normalized() if side.length_squared() > 1e-8 else Vector3.RIGHT
		var life := _curve_life[k]
		var half := LINE_WIDTH * 0.5 * (0.2 + 0.8 * life)
		var c := Color(hot, pow(life, 1.3))
		var v := float(k) / (n - 1)
		_vertex(tip - side * half, c, Vector2(0.0, v))
		_vertex(tip + side * half, c, Vector2(1.0, v))
	_imesh.surface_end()


func _vertex(p: Vector3, c: Color, uv: Vector2) -> void:
	_imesh.surface_set_color(c)
	_imesh.surface_set_uv(uv)
	_imesh.surface_add_vertex(p)


## One material per look, shared by every sword.
static func _material(texture: StringName, billboard: bool) -> StandardMaterial3D:
	var key := "%s|%s" % [texture, billboard]
	if not _materials.has(key):
		var m := Vfx.surface_material(Vfx.tex(texture), true)
		if billboard:
			m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			# The flare sits on the blade and shows over it.
			m.no_depth_test = true
		_materials[key] = m
	return _materials[key]
