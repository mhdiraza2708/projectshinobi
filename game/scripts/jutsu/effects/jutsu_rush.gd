class_name JutsuRush
extends Node3D
## A rush jutsu: the technique gathers in the caster's right hand, then they
## drive it into whoever is ahead. Wind spins a tight sphere of wind in the
## palm that bursts on contact and throws the foe back (Cyclone Core);
## lightning gathers crackling in the hand for a lunge that pierces through
## everyone in its path (Stormpiercer).
##
## The body moves itself, reading `body_velocity()` each physics frame (see
## Player.begin_rush); this node keeps the time, finds what the hand meets
## and draws the technique in the hand.

## The rush is over: `landed` if it hit anyone.
signal finished(landed: bool)

enum Phase { GATHER, RUSH, DONE }

## How far the burst of a bursting rush (wind) reaches past the hand.
const BURST_RADIUS := 2.4
## How much further than a stagger a bursting rush throws its foes.
const BURST_PUSH := 2.2
## Turn rate (rad/s) toward the target while rushing.
const STEER := 2.5
## Where the hand is held, in the body's frame, when the rig has no hand bone.
const HAND_FALLBACK := Vector3(0.28, 1.05, -0.45)

var caster: Node3D
var target: Node3D
var element := Element.WIND
var power := 30.0
var speed := 22.0
var distance := 10.0
## How close to the hand counts as contact.
var radius := 0.9
var gather_time := 0.5
var phase := Phase.GATHER
var landed := false

var _t := 0.0
var _travelled := 0.0
var _last := Vector3.ZERO
var _dir := Vector3.FORWARD
var _hit: Array[Node] = []
## Those a piercing rush passes through (no collision with the caster until
## it ends).
var _passed: Array[PhysicsBody3D] = []
var _orb: Node3D
var _arcs: ArcCluster
var _loop_key := &""


## Whether this element's rush bursts at the first foe (wind) or pierces on
## through (lightning).
static func pierces(nature: int) -> bool:
	return nature == Element.LIGHTNING


## The technique held in the hand: a sphere of wind wound with spinning
## bands, or a bright point wrapped in lightning. Also drawn by VfxWarmup.
static func hand_visual(nature: int) -> Node3D:
	var root := Node3D.new()
	var color := Element.color(nature)
	if pierces(nature):
		var core := Vfx.sphere(0.1, Vfx.glow_material(color.lightened(0.4), 3.0))
		root.add_child(core)
		var arcs := ArcCluster.new(0.4)
		arcs.name = "Arcs"
		arcs.count = 9
		arcs.width = 0.075
		arcs.color = color
		root.add_child(arcs)
	else:
		var core := Vfx.sphere(0.16, Vfx.energy_material(color, 1.2, 0.3, 2.4))
		root.add_child(core)
		for i in 3:
			var band := Vfx.spiral(Color(color.lightened(0.45), 0.9), 0.46, 0.22, 0.22, 1.2)
			band.spin = 14.0 if i % 2 == 0 else -11.0
			band.width = 0.06
			band.rotation = Vector3(i * 1.05, i * 0.9, 0.4 * i)
			band.position = band.basis * Vector3(0.0, -0.21, 0.0)
			root.add_child(band)
	root.add_child(Vfx.light(color, 3.0, 1.6))
	return root


func _ready() -> void:
	_orb = hand_visual(element)
	_orb.top_level = true
	_orb.scale = Vector3.ONE * 0.05
	add_child(_orb)
	_arcs = _orb.get_node_or_null(^"Arcs") as ArcCluster
	_place_orb()
	_dir = aim()
	_loop_key = StringName("rush_%d" % get_instance_id())
	Sfx.play_at(&"charge_start", global_position, -2.0)
	Sfx.start_loop(_loop_key, &"charge_loop" if pierces(element) else &"wind_loop", -4.0)


func _exit_tree() -> void:
	Sfx.stop_loop(_loop_key)


## Which way the rush will go: at the target if there is one, else ahead.
func aim() -> Vector3:
	if not is_instance_valid(caster):
		return _dir
	var to := Vector3.ZERO
	if is_instance_valid(target):
		to = target.global_position - caster.global_position
	to.y = 0.0
	if to.length() < 0.3:
		to = -caster.global_basis.z
		to.y = 0.0
	return to.normalized() if to.length() > 0.01 else _dir


## The body's horizontal velocity: planted while it gathers, then driven on.
func body_velocity() -> Vector3:
	return _dir * speed if phase == Phase.RUSH else Vector3.ZERO


## Called off before it lands (the caster was knocked out of it).
func cancel() -> void:
	if phase == Phase.DONE:
		return
	_finish(false)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(caster):
		queue_free()
		return
	_t += delta
	match phase:
		Phase.GATHER:
			_dir = aim()
			_orb.scale = Vector3.ONE * lerpf(0.05, 1.0, smoothstep(0.0, gather_time, _t))
			if _t >= gather_time:
				_go()
		Phase.RUSH:
			_steer(delta)
			var now := caster.global_position
			_travelled += Vector2(now.x - _last.x, now.z - _last.z).length()
			_last = now
			_contact()
			if phase == Phase.RUSH and (_travelled >= distance or _t >= distance / speed + 0.3):
				if not pierces(element):
					_burst(_hand())
				_finish(landed)
	_place_orb()


func _go() -> void:
	phase = Phase.RUSH
	_t = 0.0
	_last = caster.global_position
	Sfx.play_at(&"dash", global_position)
	Sfx.play_at(StringName("cast_" + Element.NAMES[element]), global_position, -2.0)
	Vfx.dust(_world(), caster.global_position, 0.9)
	if _arcs:
		_arcs.tail = 2.4


func _steer(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var want := aim()
	var angle := _dir.signed_angle_to(want, Vector3.UP)
	_dir = _dir.rotated(Vector3.UP, clampf(angle, -STEER * delta, STEER * delta)).normalized()


## Anyone the hand reaches: a bursting rush goes off at the first, a piercing
## one strikes each in turn and carries on.
func _contact() -> void:
	var hand := _hand()
	var exclude: Array[RID] = []
	if caster is CollisionObject3D:
		exclude.append((caster as CollisionObject3D).get_rid())
	for victim in Combat.hittables_in_sphere(get_world_3d(), hand, radius, exclude):
		if victim in _hit or Combat.same_team(victim, caster):
			continue
		if pierces(element):
			_pierce(victim, hand)
		else:
			_burst(hand)
			_finish(true)
			return


func _pierce(victim: Node, at: Vector3) -> void:
	_hit.append(victim)
	if caster is PhysicsBody3D and victim is PhysicsBody3D:
		(caster as PhysicsBody3D).add_collision_exception_with(victim)
		_passed.append(victim)
	if Combat.apply_hit(victim, power, element, caster) <= 0.0:
		return
	landed = true
	_notify(victim)
	if victim is EnemyShinobi:
		(victim as EnemyShinobi).stagger(caster)
	var color := Element.color(element)
	Vfx.impact(_world(), at, element, 1.3)
	Vfx.bolt(_world(), at - _dir * 1.5, at + _dir * 1.8, color.lightened(0.4), 0.1, 0.25, 3)
	Vfx.sparks(_world(), at, color, 18, 9.0, _dir, 70.0)
	Sfx.play_at(&"thunder", at, -6.0)
	Sfx.play_at(&"strike_hit", at)
	_jolt(0.08, 0.35)


## The sphere goes off: everyone round the hand is struck and thrown back.
func _burst(at: Vector3) -> void:
	var exclude: Array[RID] = []
	if caster is CollisionObject3D:
		exclude.append((caster as CollisionObject3D).get_rid())
	for victim in Combat.hittables_in_sphere(get_world_3d(), at, BURST_RADIUS, exclude):
		if victim in _hit:
			continue
		_hit.append(victim)
		if Combat.apply_hit(victim, power, element, caster) > 0.0:
			landed = true
			_notify(victim)
			if victim is EnemyShinobi:
				(victim as EnemyShinobi).stagger(caster, BURST_PUSH)
	# Thrown forward, away from the caster (and the camera behind them): a
	# ring and a twist of wind out along the rush, a ring on the ground.
	var color := Element.color(element)
	Vfx.impact(_world(), at, element, 1.3)
	Vfx.shockwave(_world(), at + _dir * 0.6, color.lightened(0.3), 1.6, 0.3, _dir)
	var twist := Vfx.spiral(Color(color.lightened(0.4), 0.8), 3.2, 0.3, 1.4, 1.4, 16.0, 3, 0.16, false, 0.4)
	_world().add_child(twist)
	twist.global_position = at
	twist.global_basis = Basis.looking_at(_dir, Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
	var ground := at
	ground.y = Combat.ground_height(get_world_3d(), at, caster.global_position.y)
	Vfx.shockwave(_world(), ground + Vector3.UP * 0.05, color, BURST_RADIUS, 0.4)
	Vfx.dust(_world(), ground + _dir, 1.2)
	Vfx.sparks(_world(), at, color.lightened(0.5), 16, 10.0, _dir, 50.0, -2.0)
	Sfx.play_at(&"explosion", at, -3.0)
	_jolt(0.1 if landed else 0.0, 0.5)


func _notify(victim: Node) -> void:
	if caster.has_method(&"notify_hit"):
		caster.notify_hit(victim, &"jutsu")


func _jolt(freeze: float, shake: float) -> void:
	if freeze > 0.0:
		HitStop.freeze(get_tree(), freeze)
	var rig: Variant = caster.get(&"camera_rig")
	if rig is CameraRig:
		(rig as CameraRig).add_shake(shake)
	if caster is Player:
		InputDevice.rumble(0.5, 0.6, 0.18)


func _finish(did_land: bool) -> void:
	phase = Phase.DONE
	landed = did_land
	for body in _passed:
		if is_instance_valid(body) and caster is PhysicsBody3D:
			(caster as PhysicsBody3D).remove_collision_exception_with(body)
	_passed.clear()
	Sfx.stop_loop(_loop_key)
	finished.emit(did_land)
	# The technique in the hand fades as the hand opens.
	if is_instance_valid(_orb):
		if _arcs:
			_arcs.tail = 0.0
		var tw := _orb.create_tween()
		tw.tween_property(_orb, "scale", Vector3.ONE * 0.01, 0.18)
	get_tree().create_timer(0.2, false).timeout.connect(queue_free)


## The right palm, a little out from it (or where a hand would be held).
func _hand() -> Vector3:
	var model: Variant = caster.get(&"model")
	if model is CharacterModel and is_instance_valid((model as CharacterModel).skeleton):
		var skel := (model as CharacterModel).skeleton
		var bone := skel.find_bone(&"RightHand")
		if bone >= 0:
			var at := skel.global_transform * skel.get_bone_global_pose(bone).origin
			return at + _dir * 0.14
	return caster.global_transform * HAND_FALLBACK


func _place_orb() -> void:
	if is_instance_valid(_orb) and is_instance_valid(caster):
		_orb.global_position = _hand()
		_orb.global_basis = Basis.looking_at(_dir, Vector3.UP).scaled(_orb.scale)


func _world() -> Node:
	var scene := get_tree().current_scene
	return scene if scene else get_tree().root
