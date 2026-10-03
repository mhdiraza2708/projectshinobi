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
## The ultimate meter moved (0 to Ultimates.MAX_CHARGE).
signal ultimate_changed(charge: float, maximum: float)
## An ultimate was unleashed (its UltimateSequence is starting).
signal ultimate_used(ult: Dictionary)
## Short player-facing message: "Not enough chakra", jutsu names, etc.
## kind: &"cast", &"fail" or &"info".
signal feedback(text: String, kind: StringName)
## Health reached zero.
signal defeated
## One of the player's attacks damaged `victim`. kind: &"strike", &"kunai"
## or &"jutsu".
signal hit_landed(victim: Node, kind: StringName)

enum State { FREE, WEAVING, AUTO_WEAVING, CHARGING, GUARDING, DASHING, DOWN }

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
@export_group("Recovery")
## Health per second once out of combat for `regen_delay` seconds.
@export var health_regen := 3.0
@export var regen_delay := 4.0
@export_group("Combat")
@export var strike_damage := 7.0
@export var strike_reach := 1.1
@export var strike_interval := 0.28
@export var guard_damage_multiplier := 0.3
@export var lock_range := 30.0
## A hit at least this big knocks you out of a weave.
@export var interrupt_damage := 10.0

## Soft aim: how far off the camera's line a target can be and still be aimed at.
const SOFT_AIM_ANGLE := deg_to_rad(22.0)
## Lock-on prefers enemies that fight back over things that don't (training
## dummies) by this much score. Soft aim takes any enemy in its cone first.
const PASSIVE_LOCK_PENALTY := 8.0
const SOFT_AIM_RANGE := 28.0
## Landing faster than this (m/s) makes a sound.
const LAND_SOUND_SPEED := 5.0

## Combat team (see Combat.same_team); also this node's group.
var team := &"player"
var state := State.FREE
var weaver := SealWeaver.new()
var lock_target: Node3D
## The equipped loadout's jutsu and cast styles, one entry per quick-cast slot
## (see Loadouts); `quick_page` is which half of them a gamepad's D-pad works.
var quick_slots: Array[StringName] = []
var quick_styles: Array[String] = []
var quick_page := 0
## The ultimate meter: fills as you fight, empties when unleashed, and keeps
## its charge between fights (Game saves it with the slot).
## Ground speed multiplier from what you stand on (the open world's sea
## makes the sprint faster).
var surface_speed := 1.0
## Someone to talk to is in reach (the open world sets it).
var can_interact := false
## Second Wind (skill tree) can save the player from the next lethal blow.
var second_wind_ready := true
var ult_charge := 0.0:
	set(value):
		ult_charge = value
		Game.set_ult_charge(value)
## The eye art, opened in battle (EyeArtMode).
var eye_mode: EyeArtMode
## Disable to freeze player control (cutscenes, menus, tests).
var input_enabled := true
## While input is off, a cutscene can walk you (horizontal velocity) and pose
## you (a HumanoidPoser.Pose, or -1 for none).
var scripted_velocity := Vector3.ZERO
var scripted_pose := -1

var _state_time := 0.0
var _weave_started_frame := -1
var _air_jumps_left := 0
var _dash_dir := Vector3.FORWARD
var _charge_fx: Node3D
var _dash_trail: VfxTrail
var _dash_cooldown_left := 0.0
var _sprinting := false
var _strike_cooldown := 0.0
## Seconds since the guard last took a blow (Counter Edge).
var _since_blocked := INF
var _strike_combo := 0
var _auto_jutsu: JutsuDefinition
var _auto_queue: Array[int] = []
var _auto_timer := 0.0
var _kunai: JutsuDefinition
# What the exported numbers were before clan and eye art perks.
var _base: Dictionary = {}
var _focus_active := false

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
	stats.health_regen = health_regen
	stats.regen_delay = regen_delay
	animator = model.animator
	model.model_loaded.connect(func() -> void: animator = model.animator)
	caster.affinity = Profile.get_value(&"affinity")
	caster.use_perks = true
	_base = {"run": run_speed, "sprint": sprint_speed, "dash_cooldown": dash_cooldown, "lock": lock_range,
		"guard": guard_damage_multiplier, "health": stats.max_health, "chakra_regen": stats.chakra_regen,
		"chakra": stats.max_chakra, "charge": stats.charge_regen}
	_apply_perks()
	Game.skills_changed.connect(_apply_perks)
	_load_loadout()
	eye_mode = EyeArtMode.new()
	add_child(eye_mode)
	# Whatever the meter held at the end of the last fight.
	ult_charge = clampf(Game.ult_charge(), 0.0, Ultimates.MAX_CHARGE)
	Profile.changed.connect(func(key: StringName) -> void:
		caster.affinity = Profile.get_value(&"affinity")
		if key in [&"clan", &"eye_art", &""]:
			_apply_perks()
		if key in [&"loadouts", &"loadout", &""]:
			_load_loadout())
	stats.dodged.connect(_on_dodged)

	_kunai = JutsuDefinition.new()
	_kunai.id = &"kunai"
	_kunai.display_name = "Kunai"
	_kunai.power = 5.0
	_kunai.speed = 34.0
	_kunai.max_range = 32.0
	_kunai.radius = 0.12
	_kunai.chakra_cost = 0.0
	_kunai.cooldown = 0.3
	_kunai.visual = &"kunai"
	_kunai.homing = 7.0

	_sync_settings()
	Settings.value_changed.connect(func(_k: StringName, _v: Variant) -> void: _sync_settings())
	weaver.seal_added.connect(_on_seal_added)
	weaver.broken.connect(func() -> void:
		Sfx.play(&"seal_break")
		feedback.emit("Sequence broken: too slow", &"fail"))
	caster.cast_succeeded.connect(_on_cast_succeeded)
	caster.cast_failed.connect(_on_cast_failed)
	stats.damaged.connect(_on_damaged)
	stats.died.connect(_on_died)
	stats.cheat_death_health = SkillTrees.SECOND_WIND_HEALTH
	stats.death_cheated.connect(_on_second_wind)


func _exit_tree() -> void:
	Sfx.stop_loop(&"charge")
	if _focus_active:
		Engine.time_scale = 1.0


func _sync_settings() -> void:
	weaver.timeout_scale = float(Settings.get_value(&"seal_timeout_scale"))


func _physics_process(delta: float) -> void:
	_state_time += delta
	if not second_wind_ready and stats.since_hit >= SkillTrees.SECOND_WIND_RECHARGE and not is_down():
		second_wind_ready = true
		if Perks.has(&"second_wind"):
			feedback.emit("Second Wind ready", &"info")
	_dash_cooldown_left = maxf(0.0, _dash_cooldown_left - delta)
	_strike_cooldown = maxf(0.0, _strike_cooldown - delta)
	_since_blocked += delta
	weaver.tick(delta)
	_validate_lock()

	if state == State.DOWN:
		_decelerate(delta)
	elif input_enabled and Input.is_action_just_pressed(&"ultimate") and try_ultimate():
		pass
	elif not input_enabled:
		if state == State.CHARGING or state == State.GUARDING:
			_enter(State.FREE)
		if scripted_velocity != Vector3.ZERO:
			velocity.x = scripted_velocity.x
			velocity.z = scripted_velocity.z
			_face_towards(scripted_velocity, delta)
		else:
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
	var was_airborne := not is_on_floor()
	var fall_speed := -velocity.y
	move_and_slide()
	if is_on_floor():
		_air_jumps_left = air_jumps
		if was_airborne and fall_speed > LAND_SOUND_SPEED:
			Sfx.play_at(&"land", global_position, linear_to_db(clampf(fall_speed / 16.0, 0.35, 1.0)))
	_update_animator()


# --- States ------------------------------------------------------------------

func _state_free(delta: float) -> void:
	if Input.is_action_just_pressed(&"weave"):
		_begin_weave()
		return
	for i in quick_slots.size():
		if Input.is_action_just_pressed(StringName("quick_cast_%d" % (i + 1))):
			var slot := i
			# The D-pad (or 1-4) works the current page's four slots: the
			# first page unless flipped, or the other one while Shift is held.
			if i < Loadouts.PAGE:
				slot += dpad_page() * Loadouts.PAGE
			start_quick_cast(slot)
			if state != State.FREE:
				return
	if Input.is_action_just_pressed(&"quick_page"):
		quick_page = 1 - quick_page
		feedback.emit("Quick-cast slots %d–%d" % [quick_page * Loadouts.PAGE + 1, (quick_page + 1) * Loadouts.PAGE], &"info")
		quick_slots_changed.emit()
	if Input.is_action_just_pressed(&"preset_next"):
		cycle_loadout(1)
	elif Input.is_action_just_pressed(&"preset_prev"):
		cycle_loadout(-1)
	if Input.is_action_just_pressed(&"lock_on"):
		toggle_lock()
	if Input.is_action_just_pressed(&"evade") and _dash_cooldown_left <= 0.0:
		_start_dash()
		return
	if not Input.is_action_pressed(&"evade"):
		_sprinting = false
	# Page shift + Charge opens the eye art instead of charging.
	if Input.is_action_pressed(&"quick_shift"):
		if Input.is_action_just_pressed(&"charge_chakra") and not eye_mode.release():
			# A sustained eye (Unclosing Eye) closes on the same chord.
			if eye_mode.sustaining():
				eye_mode.close()
			else:
				eye_mode.try_open()
	elif Input.is_action_pressed(&"charge_chakra") and is_on_floor():
		_enter(State.CHARGING)
		return
	if Input.is_action_pressed(&"guard"):
		_enter(State.GUARDING)
		return
	if Input.is_action_just_pressed(&"jump"):
		_jump()
	# Beside someone to talk to, the strike button talks instead (OpenWorld).
	if Input.is_action_just_pressed(&"attack") and not can_interact:
		_strike()
	if Input.is_action_just_pressed(&"throw_tool"):
		throw_kunai()

	var speed := (sprint_speed if _sprinting else run_speed) * surface_speed
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
		_auto_timer = _seal_time()
		return
	weaver.finish()
	_enter(State.FREE)
	_face_now(_aim_flat())
	caster.cast(_auto_jutsu, aim_target())


func _state_charging(delta: float) -> void:
	_decelerate(delta)
	stats.is_charging = true
	if not Input.is_action_pressed(&"charge_chakra"):
		_enter(State.FREE)


func _state_guarding(delta: float) -> void:
	# Mirror Eye: release what the guard absorbed without letting go of it.
	if Input.is_action_pressed(&"quick_shift") and Input.is_action_just_pressed(&"charge_chakra"):
		eye_mode.release()
	stats.guard_multiplier = guard_damage_multiplier
	# Still Eye: a guard raised just before a blow takes none of it.
	if Perks.has(&"perfect_guard") and _state_time < Perks.PERFECT_GUARD_WINDOW:
		stats.guard_multiplier = 0.0
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
		State.CHARGING:
			stats.is_charging = false
			Sfx.stop_loop(&"charge")
			_stop_charge_fx()
		State.GUARDING: stats.guard_multiplier = 1.0
		State.DASHING:
			stats.is_invulnerable = false
			if is_instance_valid(_dash_trail):
				_dash_trail.emitting = false
				_dash_trail.reparent(get_parent())
			_dash_trail = null
	if new_state == State.CHARGING:
		Sfx.start_loop(&"charge", &"charge_loop", -3.0)
		_start_charge_fx()
	state = new_state
	_state_time = 0.0
	state_changed.emit(state)


# --- Actions -----------------------------------------------------------------

func _begin_weave() -> void:
	Sfx.play(&"weave_start")
	weaver.begin()
	_weave_started_frame = Engine.get_physics_frames()
	_enter(State.WEAVING)


func _release_weave() -> void:
	var sequence := weaver.finish()
	_enter(State.FREE)
	if sequence.is_empty():
		return
	_face_now(_aim_flat())
	caster.cast_sequence(sequence, aim_target())


## Casts the jutsu in `slot` by weaving its seals automatically.
## The page of quick-cast slots the D-pad (and keys 1-4) cast right now: the
## gamepad's flipped page, swapped while the page shift is held.
func dpad_page() -> int:
	var page := quick_page if InputDevice.current == Binding.Device.GAMEPAD else 0
	return 1 - page if input_enabled and Input.is_action_pressed(&"quick_shift") else page


func start_quick_cast(slot: int) -> void:
	if slot < 0 or slot >= quick_slots.size():
		return
	var jutsu := JutsuRegistry.get_jutsu(quick_slots[slot])
	if jutsu == null:
		feedback.emit("Quick-cast slot %d is empty" % (slot + 1), &"fail")
		return
	var instant := quick_styles[slot] == Loadouts.INSTANT
	var reason := caster.block_reason(jutsu, instant)
	if reason != &"":
		_on_cast_failed(jutsu, reason)
		return
	if instant:
		# No seals: a flick of the hands and it's done.
		_face_now(_aim_flat())
		if animator:
			animator.seal_flick()
		caster.cast(jutsu, aim_target(), true)
		return
	_auto_jutsu = jutsu
	_auto_queue = jutsu.seals.duplicate()
	_auto_timer = 0.0
	Sfx.play(&"weave_start")
	weaver.begin()
	_enter(State.AUTO_WEAVING)


func assign_quick_slot(slot: int, jutsu_id: StringName) -> void:
	if slot < 0 or slot >= quick_slots.size():
		return
	# Saved in the equipped loadout; the Profile's change reloads the slots.
	Loadouts.assign(slot, jutsu_id)


## Equips the next (1) or previous (-1) jutsu loadout.
func cycle_loadout(step: int) -> void:
	if Loadouts.all().size() < 2:
		feedback.emit("Only one loadout (make more in the pause menu)", &"info")
		return
	Loadouts.equip(Loadouts.cycle(step))
	feedback.emit("Loadout: %s" % Loadouts.active()["name"], &"info")


func _load_loadout() -> void:
	var preset := Loadouts.active()
	quick_slots.clear()
	quick_styles.clear()
	for i in Loadouts.SLOTS:
		quick_slots.append(Loadouts.jutsu_in(preset, i))
		quick_styles.append(Loadouts.style_in(preset, i))
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
		Sfx.play(&"jump", -4.0)
	elif _air_jumps_left > 0 and stats.spend_chakra(air_jump_cost):
		_air_jumps_left -= 1
		velocity.y = jump_velocity * 0.9
		Sfx.play(&"chakra_jump")
		var chakra := Element.color(Element.NONE)
		Vfx.shockwave(get_parent(), global_position, chakra, 1.6, 0.35)
		Vfx.flash(get_parent(), global_position, chakra.lightened(0.4), 1.2, 0.15, &"glow")


func _start_charge_fx() -> void:
	_stop_charge_fx()
	_charge_fx = Vfx.charge_aura(Element.color(int(Profile.get_value(&"affinity"))).lerp(Element.color(Element.NONE), 0.5))
	add_child(_charge_fx)


func _stop_charge_fx() -> void:
	if not is_instance_valid(_charge_fx):
		return
	var fx := _charge_fx
	_charge_fx = null
	for p in fx.find_children("*", "CPUParticles3D", true, false):
		(p as CPUParticles3D).emitting = false
	var tw := fx.create_tween()
	tw.tween_property(fx, "scale", Vector3(0.6, 0.2, 0.6), 0.25).set_ease(Tween.EASE_IN)
	tw.tween_callback(fx.queue_free)


func _start_dash() -> void:
	var dir := _input_direction()
	if dir.length() < 0.1:
		dir = -global_basis.z
	dir.y = 0.0
	_dash_dir = dir.normalized()
	_face_now(_dash_dir)
	_dash_cooldown_left = dash_cooldown
	Sfx.play(&"dash")
	_enter(State.DASHING)
	# Dust where you pushed off, and a streak where you went.
	Vfx.dust(get_parent(), global_position, 0.7)
	_dash_trail = Vfx.trail(Color(0.85, 0.92, 1.0, 0.35), 1.1, 0.18, true)
	var chest := Node3D.new()
	chest.position.y = 1.0
	add_child(chest)
	chest.add_child(_dash_trail)
	get_tree().create_timer(dash_time + 0.4, false).timeout.connect(chest.queue_free)


func _strike() -> void:
	if _strike_cooldown > 0.0:
		return
	# Kenjutsu (skill tree) makes the cuts faster, longer and harder.
	_strike_cooldown = strike_interval * maxf(0.4, 1.0 - Perks.value(&"strike_speed"))
	_strike_combo = (_strike_combo + 1) % 3
	if is_instance_valid(lock_target):
		_face_now(lock_target.global_position - global_position)
	# With a sword at the hip the first blow draws it in a level cut.
	var drawing := animator != null and animator.has_sword() and not animator.sword_drawn()
	if animator:
		animator.strike(_strike_combo)
	Sfx.play(&"strike_whoosh", -2.0, 0.1)
	var forward := -global_basis.z
	velocity += forward * 3.0
	var reach := 1.0 + Perks.value(&"strike_reach")
	var center := global_position + forward * strike_reach * reach + Vector3.UP * 1.1
	# The blade's arc: each blow of the combo cuts at a different angle.
	var tilt: float = 0.05 if drawing else [0.7, -0.7, 1.35][_strike_combo]
	Vfx.slash(get_parent(), Transform3D(global_basis, global_position + Vector3.UP * 1.1), Color(0.3, 0.55, 1.0), 2.2, tilt)
	var damage := strike_damage * (1.0 + 0.25 * _strike_combo) * (1.0 + stats.modifier(&"attack_power")) \
		* (1.0 + Perks.value(&"strike_damage"))
	if _strike_combo == 2:
		damage *= 1.0 + Perks.value(&"finisher")
	# Counter Edge: answering a blocked blow.
	var counter := Perks.has(&"counter_strike") and _since_blocked < SkillTrees.COUNTER_WINDOW
	if counter:
		damage *= 2.0
		_since_blocked = INF
		feedback.emit("Counter!", &"info")
	var landed := false
	for victim in Combat.hittables_in_sphere(get_world_3d(), center, 0.9 * reach, [get_rid()]):
		# Guard Breaker (or a counter) knocks a raised guard aside first.
		if victim is EnemyShinobi and (counter or (Perks.has(&"guard_break") \
				and (victim as EnemyShinobi).state == EnemyShinobi.State.GUARDING)):
			(victim as EnemyShinobi).stagger()
		if Combat.apply_hit(victim, damage, Element.NONE, self) > 0.0:
			landed = true
			notify_hit(victim, &"strike")
			# On the struck body's near side, where the blow lands.
			var at := (victim as Node3D).global_position + Vector3.UP * 1.1 - forward * 0.4 if victim is Node3D else center
			Vfx.hit_spark(get_parent(), at, Color(1.0, 0.62, 0.15), 1.0, forward)
	if landed:
		Sfx.play_at(&"strike_hit", center, 0.0, 0.1)
		camera_rig.add_shake(0.25)
		InputDevice.rumble(0.3, 0.2, 0.08)
		# Drinking Steel: a landed cut feeds the chakra.
		var drink := Perks.value(&"strike_chakra")
		if drink > 0.0:
			stats.chakra = minf(stats.max_chakra, stats.chakra + stats.max_chakra * drink)
			stats.chakra_changed.emit(stats.chakra, stats.max_chakra)
	# Crescent Moon: the third cut flies on.
	if _strike_combo == 2 and Perks.has(&"blade_wave"):
		_blade_wave(forward, damage)


## A crescent of chakra cut loose from the blade (Crescent Moon).
func _blade_wave(forward: Vector3, cut: float) -> void:
	var p := JutsuProjectile.new()
	p.element = Element.NONE
	p.style = &"crescent"
	p.power = cut * SkillTrees.BLADE_WAVE_POWER
	p.speed = SkillTrees.BLADE_WAVE_SPEED
	p.max_range = SkillTrees.BLADE_WAVE_RANGE
	p.radius = 0.6
	p.caster = self
	var target := aim_target()
	p.target = target
	p.homing_rate = 2.0
	p.direction = caster.aim_direction(target) if target else forward
	get_parent().add_child(p)
	p.global_position = global_position + Vector3.UP * 1.1 + forward * 0.8
	Sfx.play(&"strike_whoosh", 1.0, 0.05)


func throw_kunai() -> void:
	if caster.cooldown_left(_kunai.id) > 0.0:
		return
	var target := aim_target()
	_face_now(_aim_flat())
	if animator:
		animator.throw()
	caster.cast(_kunai, target)
	InputDevice.rumble(0.15, 0.0, 0.05)


# --- Lock-on -----------------------------------------------------------------

## Where attacks go: the lock-on target, else the soft-aim target, else null
## (straight ahead).
func aim_target() -> Node3D:
	if is_instance_valid(lock_target):
		return lock_target
	return soft_target()


## Without lock-on, the target nearest to where the camera points (within
## SOFT_AIM_ANGLE), so throws and jutsu land without precise aiming. An
## enemy in the cone always wins over a dummy.
func soft_target() -> Node3D:
	var best: Node3D = null
	var best_angle := SOFT_AIM_ANGLE
	var passive: Node3D = null
	var passive_angle := SOFT_AIM_ANGLE
	var look := camera_rig.flat_forward()
	for node in get_tree().get_nodes_in_group(&"lockable"):
		var n := node as Node3D
		if n == null or n == self:
			continue
		var to := n.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist > SOFT_AIM_RANGE or dist < 0.5:
			continue
		var angle := look.angle_to(to / dist)
		if not _is_hostile(n):
			if angle < passive_angle:
				passive_angle = angle
				passive = n
		elif angle < best_angle:
			best_angle = angle
			best = n
	return best if best else passive


func _is_hostile(n: Node) -> bool:
	var other: Variant = n.get(&"team")
	return other is StringName and other != &"" and other != team


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
		# Prefer enemies, then what the camera is pointing at, then what is close.
		var score := look.angle_to(to.normalized()) * 8.0 + dist * 0.1
		if not _is_hostile(n):
			score += PASSIVE_LOCK_PENALTY
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
	elif not lock_target.is_in_group(&"lockable"):
		# The target was defeated: move on to the next one, if any.
		_set_lock(find_lock_target())


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


## Where techniques should go: the aim target, else where the camera looks.
func _aim_flat() -> Vector3:
	var target := aim_target()
	if is_instance_valid(target):
		return target.global_position - global_position
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
	if scripted_pose >= 0 and not input_enabled:
		animator.pose = scripted_pose
	animator.airborne = not is_on_floor()
	animator.run_speed = run_speed
	animator.speed_ratio = Vector2(velocity.x, velocity.z).length() / run_speed


# --- Clan and eye art perks ----------------------------------------------------

## An enemy jutsu is about to hit: the eye art may absorb it.
func try_absorb(p: JutsuProjectile) -> bool:
	return eye_mode != null and eye_mode.try_absorb(p)


## Re-reads the perks (after the eye art opens or closes).
func refresh_perks() -> void:
	_apply_perks()


## Re-reads the player's clan and eye art into the numbers they change.
func _apply_perks() -> void:
	var move := 1.0 + Perks.value(&"move_speed")
	run_speed = _base["run"] * move
	sprint_speed = _base["sprint"] * move
	dash_cooldown = _base["dash_cooldown"] * maxf(0.2, 1.0 + Perks.value(&"dash_cooldown"))
	lock_range = _base["lock"] * (1.0 + Perks.value(&"lock_range"))
	guard_damage_multiplier = _base["guard"] * maxf(0.05, 1.0 - Perks.value(&"guard"))
	var ratio := stats.health / stats.max_health if stats.max_health > 0.0 else 1.0
	stats.max_health = _base["health"] * (1.0 + Perks.value(&"max_health"))
	stats.health = clampf(ratio * stats.max_health, 0.0, stats.max_health)
	stats.chakra_regen = _base["chakra_regen"] * (1.0 + Perks.value(&"chakra_regen"))
	stats.charge_regen = _base["charge"] * (1.0 + Perks.value(&"charge_speed"))
	var chakra_ratio := stats.chakra / stats.max_chakra if stats.max_chakra > 0.0 else 1.0
	stats.max_chakra = _base["chakra"] * (1.0 + Perks.value(&"max_chakra"))
	stats.chakra = clampf(chakra_ratio * stats.max_chakra, 0.0, stats.max_chakra)
	stats.health_changed.emit(stats.health, stats.max_health)
	stats.chakra_changed.emit(stats.chakra, stats.max_chakra)


## Seconds per seal when a quick-cast weaves for you.
func _seal_time() -> float:
	return maxf(0.05, float(Settings.get_value(&"auto_weave_seal_time")) * (1.0 - Perks.value(&"cast_speed")))


func _eye_color() -> Color:
	var art := Perks.active_eye_art()
	return Color(str(art["color"])) if not art.is_empty() else Color.WHITE


## Mirror Eye: slipping through a blow slows the world for a heartbeat.
func _on_dodged(_amount: float, _element: int) -> void:
	if state != State.DASHING or _focus_active or not Perks.has(&"dodge_focus"):
		return
	_focus_active = true
	Engine.time_scale = Perks.FOCUS_TIME_SCALE
	stats.chakra = minf(stats.max_chakra, stats.chakra + Perks.FOCUS_CHAKRA)
	stats.chakra_changed.emit(stats.chakra, stats.max_chakra)
	feedback.emit("Mirror Eye", &"cast")
	Vfx.flash(get_parent(), global_position + Vector3.UP * 1.6, _eye_color().lightened(0.3), 2.4, 0.3, &"glow")
	Sfx.play(&"chakra_jump", -2.0)
	# Real time, not slowed time.
	await get_tree().create_timer(Perks.FOCUS_SECONDS, true, false, true).timeout
	Engine.time_scale = 1.0
	_focus_active = false


## Still Eye: a perfectly timed guard.
func _perfect_guard() -> void:
	gain_ultimate(Ultimates.PER_PERFECT_GUARD)
	Sfx.play(&"guard", 3.0)
	feedback.emit("Still Eye: blocked", &"cast")
	stats.chakra = minf(stats.max_chakra, stats.chakra + Perks.FOCUS_CHAKRA * 0.8)
	stats.chakra_changed.emit(stats.chakra, stats.max_chakra)
	Vfx.hit_spark(get_parent(), global_position + Vector3.UP * 1.2 - global_basis.z * 0.5,
		_eye_color(), 0.9, -global_basis.z)
	camera_rig.add_shake(0.15)


# --- Reactions ---------------------------------------------------------------

func _on_seal_added(seal: int, _sequence: Array[int]) -> void:
	Sfx.play(StringName("seal_%d" % (Seal.bank_of(seal) + 1)), 0.0, 0.03)
	if animator:
		animator.seal_flick()
	InputDevice.rumble(0.12, 0.0, 0.04)


func _on_cast_succeeded(jutsu: JutsuDefinition) -> void:
	if jutsu == _kunai:
		return
	if animator:
		animator.cast()
	feedback.emit(jutsu.display_name, &"cast")
	camera_rig.add_shake(0.15 if jutsu.form != JutsuDefinition.Form.AREA else 0.45)
	InputDevice.rumble(0.25, 0.35 if jutsu.form == JutsuDefinition.Form.AREA else 0.1, 0.15)


func _on_cast_failed(jutsu: JutsuDefinition, reason: StringName) -> void:
	if jutsu == _kunai:
		return
	Sfx.play(&"misfire", 0.0 if reason == &"misfire" else -7.0)
	match reason:
		&"misfire":
			feedback.emit("Misfire: no jutsu uses that sequence", &"fail")
		&"chakra":
			feedback.emit("Not enough chakra for %s" % jutsu.display_name, &"fail")
		&"cooldown":
			feedback.emit("%s is recharging (%.1fs)" % [jutsu.display_name, caster.cooldown_left(jutsu.id)], &"fail")
	InputDevice.rumble(0.0, 0.3, 0.12)


func _on_damaged(amount: float, _element: int, _multiplier: float) -> void:
	if amount <= 0.0 and state == State.GUARDING:
		_perfect_guard()
		return
	Sfx.play(&"guard" if state == State.GUARDING else &"hit_player")
	if animator and state != State.GUARDING and not stats.is_dead():
		animator.hit(amount >= interrupt_damage)
	camera_rig.add_shake(clampf(amount / 30.0, 0.1, 0.6))
	InputDevice.rumble(0.4, 0.5, 0.15)
	if amount >= interrupt_damage and (state == State.WEAVING or state == State.AUTO_WEAVING):
		weaver.cancel()
		_enter(State.FREE)
		feedback.emit("Weave interrupted!", &"fail")


func take_hit(amount: float, element: int, _source: Node) -> float:
	if state == State.GUARDING:
		_since_blocked = 0.0
	stats.cheat_death = second_wind_ready and Perks.has(&"second_wind")
	var dealt := stats.take_damage(amount, element)
	stats.cheat_death = false
	gain_ultimate(dealt * Ultimates.PER_DAMAGE_TAKEN)
	return dealt


# --- Ultimate --------------------------------------------------------------------

func gain_ultimate(amount: float) -> void:
	if amount <= 0.0 or UltimateSequence.active != null or state == State.DOWN:
		return
	var before := ult_charge
	ult_charge = minf(Ultimates.MAX_CHARGE, ult_charge + amount * (1.0 + Perks.value(&"ult_gain")))
	if ult_charge == before:
		return
	ultimate_changed.emit(ult_charge, Ultimates.MAX_CHARGE)
	if before < Ultimates.MAX_CHARGE and ultimate_ready():
		feedback.emit("Ultimate ready: %s" % InputDevice.glyph(&"ultimate"), &"info")
		Sfx.play(&"buff", 2.0)
		InputDevice.rumble(0.3, 0.3, 0.2)


func is_sprinting() -> bool:
	return _sprinting


func ultimate_ready() -> bool:
	return ult_charge >= Ultimates.MAX_CHARGE


## Unleashes the equipped ultimate if the meter is full. Returns whether it
## began.
func try_ultimate() -> bool:
	if not ultimate_ready():
		feedback.emit("Ultimate charging: %d%%" % floori(ult_charge / Ultimates.MAX_CHARGE * 100.0), &"info")
		return false
	if not state in [State.FREE, State.GUARDING, State.CHARGING] or UltimateSequence.active != null \
			or Cutscene.active != null:
		return false
	var u := Ultimates.equipped()
	if u.is_empty():
		return false
	if state != State.FREE:
		_enter(State.FREE)
	ult_charge = 0.0
	ultimate_changed.emit(ult_charge, Ultimates.MAX_CHARGE)
	ultimate_used.emit(u)
	UltimateSequence.begin(self, u)
	return true


## Called by projectiles and blasts this player made when they deal damage.
func notify_hit(victim: Node, kind: StringName) -> void:
	hit_landed.emit(victim, kind)
	if eye_mode:
		eye_mode.on_hit_landed()


func is_down() -> bool:
	return state == State.DOWN


func _on_died() -> void:
	weaver.cancel()
	_set_lock(null)
	_enter(State.DOWN)
	Sfx.play(&"hit_player", 3.0)
	# Fall (the death clip), or topple forward onto the ground without one.
	if not (animator and animator.die()):
		var tw := model.create_tween()
		tw.tween_property(model, "rotation:x", -1.35, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	defeated.emit()


## Second Wind: a lethal blow was shrugged off. A burst of wind, a moment
## untouchable, and it rests until the player goes a while unhurt.
func _on_second_wind() -> void:
	second_wind_ready = false
	var world := get_parent()
	var at := global_position + Vector3.UP
	Vfx.shockwave(world, global_position + Vector3.UP * 0.2, Color("f4e7c5"), 4.0, 0.6)
	Vfx.flash(world, at, Color("fff3d6"), 2.6, 0.25)
	Vfx.sparks(world, at, Color("f4e7c5"), 20, 7.0)
	Sfx.play(&"buff", 2.0)
	InputDevice.rumble(0.8, 0.6, 0.35)
	feedback.emit("Second Wind!", &"info")
	stats.is_invulnerable = true
	get_tree().create_timer(SkillTrees.SECOND_WIND_SHIELD).timeout.connect(func() -> void:
		if is_instance_valid(self) and state != State.DASHING:
			stats.is_invulnerable = false)


## Back on your feet at full health (trial retry).
func revive() -> void:
	second_wind_ready = true
	stats.restore()
	model.rotation = Vector3.ZERO
	if animator:
		animator.revive()
	velocity = Vector3.ZERO
	_enter(State.FREE)
