class_name CameraRig
extends Node3D
## Third-person orbit camera. Mouse, right stick or arrow keys orbit it; with a
## lock-on target it swings to keep both fighters in view. Top-level so the
## player body can rotate freely underneath it.
##
## Two styles (Settings "camera_style"): over the shoulder, close behind with
## the character off to one side so whoever they face is in plain view, or
## classic, further back and centred.

## The height of shinobi the customize and title framing was made for.
const SHOWCASE_FOR := 1.65

## Per style: how far behind, how high it aims, and how far to the side (of
## the shoulder named by Settings "camera_side").
const STYLES := {
	"shoulder": {"distance": 2.6, "height": 1.62, "side": 0.62},
	"classic": {"distance": 4.3, "height": 1.55, "side": 0.0},
}
## Kept this far from a wall beside the shoulder.
const SIDE_MARGIN := 0.3

@export var follow_height := 1.55
@export var distance := 4.3
@export var mouse_scale := 0.0025
## Radians per second at full stick deflection (before sensitivity).
@export var stick_speed := 3.0
@export var min_pitch := deg_to_rad(-65.0)
@export var max_pitch := deg_to_rad(30.0)

var yaw := 0.0
var pitch := deg_to_rad(-14.0)
var lock_target: Node3D
var target: Node3D
## Horizontal framing offset (the customize screen shifts the character right).
var frame_offset := 0.0
## How far right of the character the camera sits (negative: left), from the
## style; `_side_now` eases toward it and stops short of walls.
var side := 0.0
var _side_now := 0.0

var _shake := 0.0
var _saved: Dictionary = {}
## Story conversations: who the camera looks toward over the player's shoulder.
var _focus: Node3D
var _conversation_saved: Dictionary = {}

@onready var pivot: Node3D = $Pivot
@onready var spring: SpringArm3D = $Pivot/SpringArm3D
@onready var camera: Camera3D = $Pivot/SpringArm3D/Camera3D


func _ready() -> void:
	top_level = true
	target = get_parent() as Node3D
	apply_style()
	spring.collision_mask = Combat.LAYER_WORLD | Combat.LAYER_WALLS
	spring.margin = 0.25
	var probe := SphereShape3D.new()
	probe.radius = 0.2
	spring.shape = probe
	# Field of view from Graphics settings.
	camera.fov = float(Settings.get_value(&"fov"))
	Settings.value_changed.connect(func(key: StringName, v: Variant) -> void:
		if key == &"fov":
			camera.fov = float(v)
		elif key == &"camera_style" or key == &"camera_side":
			apply_style())
	if target:
		yaw = target.global_rotation.y
		snap()


## Distance, aim height and shoulder from Settings "camera_style" and
## "camera_side". A showcase or conversation keeps its own framing and gets
## the new one when it ends.
func apply_style() -> void:
	var style: Dictionary = STYLES.get(str(Settings.get_value(&"camera_style")), STYLES["shoulder"])
	distance = style["distance"]
	side = style["side"] * (-1.0 if str(Settings.get_value(&"camera_side")) == "left" else 1.0)
	if in_showcase():
		_saved["length"] = distance
		_saved["height"] = style["height"]
	elif in_conversation():
		_conversation_saved["length"] = distance
		follow_height = style["height"]
	else:
		spring.spring_length = distance
		follow_height = style["height"]


func snap() -> void:
	if target:
		global_position = target.global_position + Vector3.UP * follow_height
	rotation = Vector3(0.0, yaw, 0.0)
	pivot.rotation.x = pitch
	_side_now = _side_goal()
	pivot.position.x = _clear_side(_side_now)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not lock_target:
		var s := mouse_scale * float(Settings.get_value(&"mouse_sensitivity"))
		var inv := -1.0 if Settings.get_value(&"invert_y") else 1.0
		yaw -= event.relative.x * s
		pitch -= event.relative.y * s * inv


func _process(delta: float) -> void:
	if in_showcase():
		# Arrow keys are menu navigation here, so only the right stick orbits
		# (the customize screen also handles mouse drags).
		var rs := Input.get_joy_axis(InputDevice.active_joypad, JOY_AXIS_RIGHT_X)
		if absf(rs) > float(Settings.get_value(&"stick_deadzone")):
			yaw -= rs * stick_speed * delta
	elif is_instance_valid(_focus) and target:
		var to_focus := _focus.global_position - target.global_position
		yaw = lerp_angle(yaw, atan2(-to_focus.x, -to_focus.z), 1.0 - exp(-4.0 * delta))
		pitch = lerpf(pitch, deg_to_rad(-8.0), 1.0 - exp(-4.0 * delta))
	elif is_instance_valid(lock_target) and target:
		var to := lock_target.global_position - target.global_position
		yaw = lerp_angle(yaw, atan2(-to.x, -to.z), 1.0 - exp(-7.0 * delta))
		pitch = lerpf(pitch, deg_to_rad(-12.0), 1.0 - exp(-4.0 * delta))
	else:
		var look := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
		var s := stick_speed * float(Settings.get_value(&"stick_sensitivity")) * delta
		var inv := -1.0 if Settings.get_value(&"invert_y") else 1.0
		yaw -= look.x * s
		pitch -= look.y * s * 0.7 * inv
	pitch = clampf(pitch, min_pitch, max_pitch)

	if target:
		var goal := target.global_position + Vector3.UP * follow_height
		global_position = global_position.lerp(goal, 1.0 - exp(-18.0 * delta))
	rotation = Vector3(0.0, yaw, 0.0)
	pivot.rotation.x = pitch
	_side_now = lerpf(_side_now, _side_goal(), 1.0 - exp(-8.0 * delta))
	pivot.position.x = _clear_side(_side_now)

	if _shake > 0.0:
		camera.h_offset = frame_offset + randf_range(-1.0, 1.0) * _shake * 0.12
		camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.12
		_shake = move_toward(_shake, 0.0, delta * 3.0)
	else:
		camera.h_offset = frame_offset
		camera.v_offset = 0.0


## The shoulder offset wanted now: none while a showcase or conversation
## frames the shot itself.
func _side_goal() -> float:
	return 0.0 if in_showcase() or in_conversation() else side


## `offset` to the side, cut short where a wall beside the character is in
## the way (so the camera never starts its arm inside one).
func _clear_side(offset: float) -> float:
	if absf(offset) < 0.01 or not is_inside_tree():
		return offset
	var right := Basis(Vector3.UP, yaw).x * signf(offset)
	var from := global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + right * (absf(offset) + SIDE_MARGIN),
		spring.collision_mask)
	if target is CollisionObject3D:
		query.exclude = [(target as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return offset
	return signf(offset) * maxf(0.0, from.distance_to(hit["position"]) - SIDE_MARGIN)


## Yaw-only basis: movement input is relative to where the camera faces.
func flat_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func flat_forward() -> Vector3:
	return flat_basis() * Vector3.FORWARD


## Swings round to look at the character's front, close up, for the
## customize screen. The stick/arrow keys still orbit. `end_showcase` restores.
func begin_showcase(offset := -0.55) -> void:
	if _saved.is_empty():
		_saved = {"length": spring.spring_length, "height": follow_height, "pitch": pitch}
	lock_target = null
	var k := showcase_scale()
	spring.spring_length = 2.7 * k
	follow_height = 1.05 * k
	pitch = deg_to_rad(-4.0)
	frame_offset = offset
	if target:
		yaw = target.global_rotation.y + PI
	snap()


## The target's height over the height the showcase was framed for, so a
## shorter or taller shinobi is still framed head to foot.
func showcase_scale() -> float:
	var worn: Variant = target.get(&"model") if target else null
	if worn is CharacterModel and (worn as CharacterModel).instance:
		var height := (worn as CharacterModel).measure_height()
		if height > 0.5:
			return clampf(height / SHOWCASE_FOR, 0.6, 1.8)
	return 1.0


func end_showcase() -> void:
	if _saved.is_empty():
		return
	spring.spring_length = _saved["length"]
	follow_height = _saved["height"]
	pitch = _saved["pitch"]
	frame_offset = 0.0
	_saved.clear()
	if target:
		yaw = target.global_rotation.y
	snap()


## Frames a story conversation: over the player's shoulder toward `focus`.
func begin_conversation(focus: Node3D) -> void:
	if _conversation_saved.is_empty():
		_conversation_saved = {"length": spring.spring_length, "lock": lock_target}
	_focus = focus
	lock_target = null
	spring.spring_length = 3.3
	frame_offset = 0.75


func end_conversation() -> void:
	_focus = null
	if _conversation_saved.is_empty():
		return
	spring.spring_length = _conversation_saved["length"]
	frame_offset = 0.0
	_conversation_saved.clear()


func in_conversation() -> bool:
	return _focus != null


func in_showcase() -> bool:
	return not _saved.is_empty()


func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount * float(Settings.get_value(&"screen_shake")))
