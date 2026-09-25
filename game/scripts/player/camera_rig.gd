class_name CameraRig
extends Node3D
## Third-person orbit camera. Mouse, right stick or arrow keys orbit it; with a
## lock-on target it swings to keep both fighters in view. Top-level so the
## player body can rotate freely underneath it.

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
	spring.spring_length = distance
	spring.collision_mask = Combat.LAYER_WORLD | Combat.LAYER_WALLS
	spring.margin = 0.25
	var probe := SphereShape3D.new()
	probe.radius = 0.2
	spring.shape = probe
	if target:
		yaw = target.global_rotation.y
		snap()


func snap() -> void:
	if target:
		global_position = target.global_position + Vector3.UP * follow_height
	rotation = Vector3(0.0, yaw, 0.0)
	pivot.rotation.x = pitch


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

	if _shake > 0.0:
		camera.h_offset = frame_offset + randf_range(-1.0, 1.0) * _shake * 0.12
		camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.12
		_shake = move_toward(_shake, 0.0, delta * 3.0)
	else:
		camera.h_offset = frame_offset
		camera.v_offset = 0.0


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
	spring.spring_length = 2.7
	follow_height = 1.05
	pitch = deg_to_rad(-4.0)
	frame_offset = offset
	if target:
		yaw = target.global_rotation.y + PI
	snap()


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
