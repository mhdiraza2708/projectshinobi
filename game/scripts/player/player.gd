class_name Player
extends CharacterBody3D
## Third-person shinobi controller.
##
## While weaving, the character plants their feet, and the movement keys and
## face buttons become seal inputs (see docs/CONTROLS.md). That's why the
## FREE-state actions (jump, strike, dash...) are only read in FREE.

signal state_changed(state: State)
signal lock_target_changed(target: Node3D)
signal quick_slots_changed
## Short player-facing message: "Not enough chakra", jutsu names, etc.
## kind: &"cast", &"fail" or &"info".
signal feedback(text: String, kind: StringName)

enum State { FREE, WEAVING, AUTO_WEAVING, CHARGING, GUARDING, DASHING }

@export_group("Movement")
@export var run_speed := 7.0
@export var sprint_speed := 12.0
@export var guard_speed := 2.2
@export var acceleration := 45.0
@export var air_control := 0.45
@export var turn_speed := 14.0
@export var jump_velocity := 8.0
@export var gravity := 24.0
@export_group("Chakra jump")
@export var air_jumps := 1
@export var air_jump_cost := 6.0
@export_group("Dash")
@export var dash_speed := 20.0
@export var dash_time := 0.2
@export var dash_cooldown := 0.35
## Seconds of invulnerability at the start of a dash.
@export var dash_iframes := 0.15
@export_group("Combat")
@export var strike_damage := 7.0
@export var strike_reach := 1.1
@export var strike_interval := 0.28
@export var guard_damage_multiplier := 0.3
@export var lock_range := 30.0
## A hit at least this big knocks you out of a weave.
@export var interrupt_damage := 10.0

var state := State.FREE
var weaver := SealWeaver.new()
var lock_target: Node3D
var quick_slots: Array[StringName] = [&"chakra_bolt", &"ember_volley", &"stone_bulwark", &"mending_palm"]
## Disable to freeze player control (cutscenes, menus, tests).
var input_enabled := true

var _state_time := 0.0
var _weave_started_frame := -1
var _air_jumps_left := 0
var _dash_dir := Vector3.FORWARD
var _dash_cooldown_left := 0.0
var _sprinting := false
var _strike_cooldown := 0.0
var _strike_combo := 0
var _auto_jutsu: JutsuDefinition
var _auto_queue: Array[int] = []
var _auto_timer := 0.0
var _kunai: JutsuDefinition

@onready var stats: Stats = $Stats
@onready var caster: JutsuCaster = $Caster
@onready var camera_rig: CameraRig = $CameraRig
@onready var model: CharacterModel = $Model
## Clips + procedural body language for the character.
var animator: CharacterAnimator


func _ready() -> void:
	add_to_group(&"player")
	collision_layer = Combat.LAYER_PLAYER
	collision_mask = Combat.BODY_MASK
	caster.stats = stats
	caster.body = self
	animator = model.animator

	_kunai = JutsuDefinition.new()
	_kunai.id = &"kunai"
	_kunai.display_name = "Kunai"
	_kunai.power = 4.0
	_kunai.speed = 38.0
	_kunai.max_range = 35.0
	_kunai.radius = 0.1
	_kunai.chakra_cost = 0.0
	_kunai.cooldown = 0.3

	_sync_settings()
	Settings.value_changed.connect(func(_k: StringName, _v: Variant) -> void: _sync_settings())
	weaver.seal_added.connect(_on_seal_added)
	weaver.broken.connect(func() -> void: feedback.emit("Sequence broken: too slow", &"fail"))
	caster.cast_succeeded.connect(_on_cast_succeeded)
	caster.cast_failed.connect(_on_cast_failed)
	stats.damaged.connect(_on_damaged)


func _sync_settings() -> void:
	weaver.timeout_scale = float(Settings.get_value(&"seal_timeout_scale"))


func _physics_process(delta: float) -> void:
	_state_time += delta
	_dash_cooldown_left = maxf(0.0, _dash_cooldown_left - delta)
	_strike_cooldown = maxf(0.0, _strike_cooldown - delta)
	weaver.tick(delta)
	_validate_lock()

	if not input_enabled:
		_decelerate(delta)
	else:
		match state:
			State.FREE: _state_free(delta)
			State.WEAVING: _state_weaving(delta)
			State.AUTO_WEAVING: _state_auto_weaving(delta)
			State.CHARGING: _state_charging(delta)
			State.GUARDING: _state_guarding(delta)
			State.DASHING: _state_dashing(delta)

	if state != State.DASHING and not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	if is_on_floor():
		_air_jumps_left = air_jumps
	_update_animator()


# --- States ------------------------------------------------------------------

func _state_free(delta: float) -> void:
	if Input.is_action_just_pressed(&"weave"):
		_begin_weave()
		return
	for i in quick_slots.size():
		if Input.is_action_just_pressed(StringName("quick_cast_%d" % (i + 1))):
			start_quick_cast(i)
			if state != State.FREE:
				return
	if Input.is_action_just_pressed(&"lock_on"):
		toggle_lock()
	if Input.is_action_just_pressed(&"evade") and _dash_cooldown_left <= 0.0:
		_start_dash()
		return
	if not Input.is_action_pressed(&"evade"):
		_sprinting = false
	if Input.is_action_pressed(&"charge_chakra") and is_on_floor():
		_enter(State.CHARGING)
		return
	if Input.is_action_pressed(&"guard"):
		_enter(State.GUARDING)
		return
	if Input.is_action_just_pressed(&"jump"):
		_jump()
	if Input.is_action_just_pressed(&"attack"):
		_strike()
	if Input.is_action_just_pressed(&"throw_tool"):
		_face_now(_aim_flat())
		caster.cast(_kunai, lock_target)

	var speed := sprint_speed if _sprinting else run_speed
	_move(delta, speed * (1.0 + stats.modifier(&"move_speed")))


func _state_weaving(delta: float) -> void:
	_decelerate(delta)
	_face_towards(_aim_flat(), delta)
	for direction in Seal.DIRECTION_ACTIONS.size():
		if Input.is_action_just_pressed(Seal.DIRECTION_ACTIONS[direction]):
			weaver.add_seal(Seal.from_input(_held_bank(), direction))

	var hold_mode: bool = Settings.get_value(&"weave_mode") == "hold"
	var released := not Input.is_action_pressed(&"weave") if hold_mode \
		else (Input.is_action_just_pressed(&"weave") and Engine.get_physics_frames() != _weave_started_frame)
	if released:
		_release_weave()


func _state_auto_weaving(delta: float) -> void:
	_decelerate(delta)
	_face_towards(_aim_flat(), delta)
	_auto_timer -= delta
	if _auto_timer > 0.0:
		return
	if not _auto_queue.is_empty():
		weaver.add_seal(_auto_queue.pop_front())
		_auto_timer = float(Settings.get_value(&"auto_weave_seal_time"))
		return
	weaver.finish()
	_enter(State.FREE)
	_face_now(_aim_flat())
	caster.cast(_auto_jutsu, lock_target)


func _state_charging(delta: float) -> void:
	_decelerate(delta)
	stats.is_charging = true
	if not Input.is_action_pressed(&"charge_chakra"):
		_enter(State.FREE)


func _state_guarding(delta: float) -> void:
	stats.guard_multiplier = guard_damage_multiplier
	if Input.is_action_just_pressed(&"evade") and _dash_cooldown_left <= 0.0:
		_start_dash()
		return
	_move(delta, guard_speed)
	if not Input.is_action_pressed(&"guard"):
		_enter(State.FREE)


func _state_dashing(_delta: float) -> void:
	velocity = _dash_dir * dash_speed
	stats.is_invulnerable = _state_time < dash_iframes
	if _state_time >= dash_time:
		_sprinting = Input.is_action_pressed(&"evade")
		velocity = _dash_dir * (sprint_speed if _sprinting else run_speed)
		_enter(State.FREE)


func _enter(new_state: State) -> void:
	if state == new_state:
		return
	# Clean up whatever the old state switched on.
	match state:
		State.CHARGING: stats.is_charging = false
		State.GUARDING: stats.guard_multiplier = 1.0
		State.DASHING: stats.is_invulnerable = false
	state = new_state
	_state_time = 0.0
	state_changed.emit(state)


# --- Actions -----------------------------------------------------------------

func _begin_weave() -> void:
	weaver.begin()
	_weave_started_frame = Engine.get_physics_frames()
	_enter(State.WEAVING)


func _release_weave() -> void:
	var sequence := weaver.finish()
	_enter(State.FREE)
	if sequence.is_empty():
		return
	_face_now(_aim_flat())
	caster.cast_sequence(sequence, lock_target)


## Casts the jutsu in `slot` by weaving its seals automatically.
func start_quick_cast(slot: int) -> void:
	if slot < 0 or slot >= quick_slots.size():
		return
	var jutsu := JutsuRegistry.get_jutsu(quick_slots[slot])
	if jutsu == null:
		feedback.emit("Quick-cast slot %d is empty" % (slot + 1), &"fail")
		return
	var reason := caster.block_reason(jutsu)
	if reason != &"":
		_on_cast_failed(jutsu, reason)
		return
	_auto_jutsu = jutsu
	_auto_queue = jutsu.seals.duplicate()
	_auto_timer = 0.0
	weaver.begin()
	_enter(State.AUTO_WEAVING)


func assign_quick_slot(slot: int, jutsu_id: StringName) -> void:
	if slot < 0 or slot >= quick_slots.size():
		return
	quick_slots[slot] = jutsu_id
	quick_slots_changed.emit()


func _held_bank() -> int:
	if Input.is_action_pressed(&"seal_layer_2"):
		return 2
	if Input.is_action_pressed(&"seal_layer_1"):
		return 1
	return 0


func _jump() -> void:
	if is_on_floor():
		velocity.y = jump_velocity
	elif _air_jumps_left > 0 and stats.spend_chakra(air_jump_cost):
		_air_jumps_left -= 1
		velocity.y = jump_velocity * 0.9
		Vfx.burst(get_parent(), global_position, Element.color(Element.NONE), 1.0, 0.3)


func _start_dash() -> void:
	var dir := _input_direction()
	if dir.length() < 0.1:
		dir = -global_basis.z
	dir.y = 0.0
	_dash_dir = dir.normalized()
	_face_now(_dash_dir)
	_dash_cooldown_left = dash_cooldown
	_enter(State.DASHING)


func _strike() -> void:
	if _strike_cooldown > 0.0:
		return
	_strike_cooldown = strike_interval
	_strike_combo = (_strike_combo + 1) % 3
	if is_instance_valid(lock_target):
		_face_now(lock_target.global_position - global_position)
	if animator:
		animator.strike()
	var forward := -global_basis.z
	velocity += forward * 3.0
	var center := global_position + forward * strike_reach + Vector3.UP * 1.1
	var damage := strike_damage * (1.0 + 0.25 * _strike_combo) * (1.0 + stats.modifier(&"attack_power"))
	var landed := false
	for victim in Combat.hittables_in_sphere(get_world_3d(), center, 0.9, [get_rid()]):
		if Combat.apply_hit(victim, damage, Element.NONE, self) > 0.0:
			landed = true
	if landed:
		camera_rig.add_shake(0.25)
		InputDevice.rumble(0.3, 0.2, 0.08)


# --- Lock-on -----------------------------------------------------------------

func toggle_lock() -> void:
	_set_lock(null if lock_target else find_lock_target())


func find_lock_target() -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var look := camera_rig.flat_forward()
	for node in get_tree().get_nodes_in_group(&"lockable"):
		var n := node as Node3D
		if n == null or n == self:
			continue
		var to := n.global_position - global_position
		var dist := to.length()
		if dist > lock_range or dist < 0.01:
			continue
		# Prefer what the camera is pointing at, then what is close.
		var score := look.angle_to(to.normalized()) * 8.0 + dist * 0.1
		if score < best_score:
			best_score = score
			best = n
	return best


func _set_lock(target: Node3D) -> void:
	lock_target = target
	camera_rig.lock_target = target
	lock_target_changed.emit(target)


func _validate_lock() -> void:
	if lock_target == null:
		return
	if not is_instance_valid(lock_target) or not lock_target.is_inside_tree() \
			or global_position.distance_to(lock_target.global_position) > lock_range * 1.3:
		_set_lock(null)


# --- Movement helpers ----------------------------------------------------------

func _input_direction() -> Vector3:
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var b := camera_rig.flat_basis()
	var dir := b.x * input.x + b.z * input.y
	dir.y = 0.0
	return dir.limit_length(1.0)


func _move(delta: float, speed: float) -> void:
	var dir := _input_direction()
	var goal := dir * speed
	var accel := acceleration * (1.0 if is_on_floor() else air_control)
	velocity.x = move_toward(velocity.x, goal.x, accel * delta)
	velocity.z = move_toward(velocity.z, goal.z, accel * delta)
	if is_instance_valid(lock_target):
		_face_towards(lock_target.global_position - global_position, delta)
	elif dir.length() > 0.1:
		_face_towards(dir, delta)


func _decelerate(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)


## Where techniques should go: the lock-on target, else where the camera looks.
func _aim_flat() -> Vector3:
	if is_instance_valid(lock_target):
		return lock_target.global_position - global_position
	return camera_rig.flat_forward()


func _face_towards(dir: Vector3, delta: float) -> void:
	if Vector2(dir.x, dir.z).length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-turn_speed * delta))


func _face_now(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() < 0.01:
		return
	rotation.y = atan2(-dir.x, -dir.z)


func _update_animator() -> void:
	if animator == null:
		return
	match state:
		State.WEAVING, State.AUTO_WEAVING: animator.pose = HumanoidPoser.Pose.WEAVE
		State.CHARGING: animator.pose = HumanoidPoser.Pose.CHARGE
		State.GUARDING: animator.pose = HumanoidPoser.Pose.GUARD
		State.DASHING: animator.pose = HumanoidPoser.Pose.DASH
		_: animator.pose = HumanoidPoser.Pose.LOCOMOTION
	animator.airborne = not is_on_floor()
	animator.speed_ratio = Vector2(velocity.x, velocity.z).length() / run_speed


# --- Reactions ---------------------------------------------------------------

func _on_seal_added(_seal: int, _sequence: Array[int]) -> void:
	if animator:
		animator.seal_flick()
	InputDevice.rumble(0.12, 0.0, 0.04)


func _on_cast_succeeded(jutsu: JutsuDefinition) -> void:
	if jutsu == _kunai:
		return
	feedback.emit(jutsu.display_name, &"cast")
	camera_rig.add_shake(0.15 if jutsu.form != JutsuDefinition.Form.AREA else 0.45)
	InputDevice.rumble(0.25, 0.35 if jutsu.form == JutsuDefinition.Form.AREA else 0.1, 0.15)


func _on_cast_failed(jutsu: JutsuDefinition, reason: StringName) -> void:
	if jutsu == _kunai:
		return
	match reason:
		&"misfire":
			feedback.emit("Misfire: no jutsu uses that sequence", &"fail")
		&"chakra":
			feedback.emit("Not enough chakra for %s" % jutsu.display_name, &"fail")
		&"cooldown":
			feedback.emit("%s is recharging (%.1fs)" % [jutsu.display_name, caster.cooldown_left(jutsu.id)], &"fail")
	InputDevice.rumble(0.0, 0.3, 0.12)


func _on_damaged(amount: float, _element: int, _multiplier: float) -> void:
	camera_rig.add_shake(clampf(amount / 30.0, 0.1, 0.6))
	InputDevice.rumble(0.4, 0.5, 0.15)
	if amount >= interrupt_damage and (state == State.WEAVING or state == State.AUTO_WEAVING):
		weaver.cancel()
		_enter(State.FREE)
		feedback.emit("Weave interrupted!", &"fail")


func take_hit(amount: float, element: int, _source: Node) -> float:
	return stats.take_damage(amount, element)
