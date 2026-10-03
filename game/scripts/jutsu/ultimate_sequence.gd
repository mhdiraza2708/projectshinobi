class_name UltimateSequence
extends Node
## An ultimate, start to finish: the world freezes, a close-up shows the
## shinobi weaving under a brush title card, then a wide shot shows the
## technique land (a falling sun, a cyclone, chain lightning, a stone fist, a
## breaking wave or a storm of shade clones) and its damage is dealt. Holding
## Pause skips straight to the blow, as in story cutscenes.

signal finished

## Seconds of the close-up (seals and title card).
const CLOSE_TIME := 1.45
## Field of view of both shots.
const FOV := 48.0
## Grace after the sequence before the player can be hurt again.
const AFTER_IFRAMES := 0.8
## Seconds Pause must be held to skip (the same as a story cutscene).
const SKIP_HOLD := Cutscene.SKIP_HOLD

## The sequence playing now (the pause menu, cutscenes and the meter leave
## things alone while it runs).
static var active: UltimateSequence

var player: Player
var ult: Dictionary
var element := Element.NONE
var color := Color.WHITE
## Where the technique lands.
var target_point := Vector3.ZERO

var _world: Node
var _camera: Camera3D
var _prev_camera: Camera3D
var _overlay: CutsceneOverlay
var _card: CanvasLayer
var _frozen: Dictionary = {}
var _cam_base := Transform3D.IDENTITY
var _shake := 0.0
var _shake_left := 0.0
var _skipping := false
var _struck := false
var _skip_held := 0.0
var _aura: Node3D
var _shades: Array[CharacterModel] = []
var _hidden_tags: Array = []


## Starts `u` for `p`. Returns the running sequence.
static func begin(p: Player, u: Dictionary) -> UltimateSequence:
	var s := UltimateSequence.new()
	s.player = p
	s.ult = u
	p.get_parent().add_child(s)
	s.play()
	return s


func _init() -> void:
	name = "UltimateSequence"


func play() -> void:
	active = self
	_world = player.get_parent()
	element = int(ult["element_id"])
	color = Element.color(element) if element != Element.NONE else Color(0.62, 0.68, 0.95)
	target_point = _pick_target()
	_freeze_world()
	player.input_enabled = false
	player.stats.is_invulnerable = true
	player.scripted_velocity = Vector3.ZERO
	player.velocity = Vector3.ZERO
	var to := target_point - player.global_position
	to.y = 0.0
	if to.length() > 0.3:
		player.rotation.y = atan2(-to.x, -to.z)

	_prev_camera = get_viewport().get_camera_3d()
	_camera = Camera3D.new()
	_camera.name = "UltimateCamera"
	_camera.fov = FOV
	_camera.far = 3000.0
	_world.add_child(_camera)
	_camera.current = true
	_overlay = CutsceneOverlay.new()
	add_child(_overlay)
	_overlay.show_bars()
	_overlay.flash(Color(color, 0.8), 0.3)
	Sfx.play(&"weave_start", 2.0)
	Sfx.play(&"buff", 0.0)
	Music.duck(true)

	await _close_up()
	await _release()
	_finish()


func _process(delta: float) -> void:
	if not _skipping and Input.is_action_pressed(&"pause"):
		_skip_held += delta
		if _skip_held >= SKIP_HOLD:
			_skipping = true
	else:
		_skip_held = maxf(0.0, _skip_held - delta * 2.0)
	if is_instance_valid(_overlay):
		_overlay.set_skip_progress(_skip_held / SKIP_HOLD)
	if is_instance_valid(_camera):
		var t := _cam_base
		if _shake_left > 0.0:
			_shake_left -= delta
			var k := _shake * clampf(_shake_left / 0.35, 0.0, 1.0)
			t.origin += t.basis * Vector3(randf_range(-k, k), randf_range(-k, k), 0.0)
		_camera.global_transform = t


func is_skipping() -> bool:
	return _skipping


## Ends at once (the blow still lands).
func skip() -> void:
	_skipping = true


# --- The two shots -----------------------------------------------------------

func _close_up() -> void:
	player.scripted_pose = HumanoidPoser.Pose.WEAVE
	_aura = Vfx.boss_aura(color, 1.0)
	_aura.name = "UltimateAura"
	player.add_child(_aura)
	var fwd := _forward()
	var right := fwd.cross(Vector3.UP).normalized()
	var eye := player.global_position + Vector3.UP * 1.38
	var start := eye + fwd * 1.6 + right * 0.4 - Vector3.UP * 0.32
	var end := eye + fwd * 1.15 + right * 0.28 - Vector3.UP * 0.22
	_show_card()
	if ult["style"] == "shades":
		_summon_shades()
	var t := 0.0
	var next_seal := 0.0
	var seal := 0
	while t < CLOSE_TIME and not _skipping:
		var k := smoothstep(0.0, 1.0, t / CLOSE_TIME)
		_cam_base = Transform3D(Basis.IDENTITY, start.lerp(end, k)).looking_at(eye - Vector3.UP * 0.05, Vector3.UP)
		if t >= next_seal:
			next_seal = t + 0.17
			if player.animator:
				player.animator.seal_flick()
			Sfx.play(StringName("seal_%d" % (seal % 3 + 1)), -2.0, 0.05)
			seal += 1
			Vfx.sparks(_world, player.global_position + Vector3.UP * 1.1 + fwd * 0.35, color, 6, 3.0)
		await get_tree().process_frame
		t += get_process_delta_time()


func _release() -> void:
	_overlay.flash(Color(1, 1, 1, 0.9), 0.22)
	player.scripted_pose = -1
	if player.animator:
		player.animator.pose = HumanoidPoser.Pose.LOCOMOTION
		player.animator.cast()
	Sfx.play(StringName("cast_" + Element.NAMES[element]), 2.0)
	_wide_shot()
	if not _skipping:
		match str(ult["style"]):
			"meteor": await _meteor()
			"cyclone": await _cyclone()
			"chain": await _chain()
			"fist": await _fist()
			"wave": await _wave()
			"shades": await _shades_strike()
	if not _struck:
		_strike_area(target_point, float(ult["radius"]))
	if not _skipping:
		await _wait(0.45)


func _wide_shot() -> void:
	var from := player.global_position
	var mid := (from + target_point) * 0.5
	var span := maxf(from.distance_to(target_point), 4.0)
	var fwd := _forward()
	var side := fwd.cross(Vector3.UP).normalized()
	# From the side and behind, high enough to see the ground around the
	# target (and, for blows from the sky, what's coming down).
	var high: bool = ult["style"] in ["meteor", "chain"]
	var pos := mid + side * (span * 0.5 + 6.5) - fwd * (span * 0.5 + 4.0) + Vector3.UP * (6.5 + span * 0.2)
	var look := mid + Vector3.UP * (2.6 if high else 1.1)
	_cam_base = Transform3D(Basis.IDENTITY, pos).looking_at(look, Vector3.UP)


func _finish() -> void:
	if is_instance_valid(_aura):
		_aura.queue_free()
	for m: Variant in _shades:
		if is_instance_valid(m):
			Vfx.smoke_puff(_world, m.global_position + Vector3.UP, 0.9)
			m.queue_free()
	_unfreeze_world()
	player.scripted_pose = -1
	player.input_enabled = true
	if is_instance_valid(_prev_camera):
		_prev_camera.current = true
	if is_instance_valid(_camera):
		_camera.queue_free()
	if is_instance_valid(_card):
		_card.queue_free()
	_overlay.hide_bars()
	Music.duck(false)
	active = null
	finished.emit()
	# A short grace, then the overlay goes.
	await get_tree().create_timer(AFTER_IFRAMES).timeout
	if is_instance_valid(player):
		player.stats.is_invulnerable = false
	queue_free()


# --- Title card --------------------------------------------------------------

func _show_card() -> void:
	_card = CanvasLayer.new()
	_card.layer = 31
	add_child(_card)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(root)
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 1.0
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_top = -190
	box.offset_bottom = 190
	box.offset_right = -70
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", -14)
	root.add_child(box)
	var tag := UiKit.label("奥義  ULTIMATE", 30, UiKit.GOLD, &"display", 10)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(tag)
	var kanji := UiKit.label(str(ult["kanji"]), 190, color.lightened(0.25), &"brush", 26)
	kanji.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(kanji)
	var title := UiKit.label(str(ult["name"]).to_upper(), 54, UiKit.PAPER, &"display", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(title)
	# Slams in from the right, holds, then fades as the blow lands.
	box.modulate.a = 0.0
	box.pivot_offset = Vector2(600, 190)
	box.scale = Vector2(1.35, 1.35)
	var tw := box.create_tween().set_parallel()
	tw.tween_property(box, "modulate:a", 1.0, 0.18)
	tw.tween_property(box, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(CLOSE_TIME - 0.55)
	tw.chain().tween_property(box, "modulate:a", 0.0, 0.25)


## The title card's text, for tests.
func card_text() -> String:
	if not is_instance_valid(_card):
		return ""
	var parts := PackedStringArray()
	for l in _card.find_children("*", "Label", true, false):
		parts.append((l as Label).text)
	return " ".join(parts)


# --- The techniques ------------------------------------------------------------

## A falling sun: grows as it drops onto the target, then bursts.
func _meteor() -> void:
	var radius := float(ult["radius"])
	var sun := Vfx.sphere(2.4, Vfx.fire_material(1.8))
	var glow := Vfx.light(Color(1.0, 0.55, 0.2), 30.0, 6.0)
	sun.add_child(glow)
	_world.add_child(sun)
	var from := target_point + Vector3(-6.0, 26.0, -4.0)
	var land := target_point + Vector3.UP * 1.0
	sun.global_position = from
	sun.scale = Vector3.ONE * 0.4
	var t := 0.0
	var fall := 0.95
	while t < fall and not _skipping:
		var k := t / fall
		sun.global_position = from.lerp(land, k * k)
		sun.scale = Vector3.ONE * lerpf(0.4, 1.35, k)
		Vfx.flash(_world, sun.global_position + Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1)),
			Color(1.0, 0.5, 0.15), 2.4, 0.3)
		_look_follow(sun.global_position, 0.25)
		await get_tree().process_frame
		t += get_process_delta_time()
	sun.queue_free()
	_overlay.flash(Color(1.0, 0.75, 0.4, 0.85), 0.3)
	Vfx.area_blast(_world, _ground(target_point), Element.FIRE, radius)
	Vfx.shockwave(_world, _ground(target_point) + Vector3.UP * 0.2, Color(1.0, 0.55, 0.2), radius * 1.3, 0.6)
	for i in 6:
		var a := TAU * i / 6.0
		Vfx._pillar(_world, _ground(target_point + Vector3(cos(a), 0, sin(a)) * radius * 0.6), Color(1.0, 0.45, 0.12), 7.0, 0.9)
	Vfx.debris(_world, target_point, Color(0.3, 0.22, 0.18), 18, 9.0, 1.4)
	Sfx.play_at(&"explosion", target_point, 4.0)
	_shake_now(0.6, 0.8)
	_strike_area(target_point, radius)
	await _wait(0.6)


## A cyclone: lifts everyone near the target, shreds them, drops them.
func _cyclone() -> void:
	var radius := float(ult["radius"])
	Vfx._tornado(_world, _ground(target_point), radius * 0.55)
	Sfx.play_at(&"cast_wind", target_point, 3.0)
	var caught := _foes_near(target_point, radius)
	var starts := {}
	for f in caught:
		starts[f] = f.global_position
	var t := 0.0
	var spin := 1.5
	var next_slash := 0.0
	while t < spin and not _skipping:
		var k := t / spin
		var lift := sin(clampf(k, 0.0, 1.0) * PI) * 3.2
		for f: Node3D in caught:
			if is_instance_valid(f):
				var a: Vector3 = starts[f]
				var around := (a - target_point).rotated(Vector3.UP, k * TAU * 1.2)
				f.global_position = target_point + around * lerpf(1.0, 0.45, sin(k * PI)) + Vector3.UP * lift
		if t >= next_slash:
			next_slash = t + 0.09
			var at := target_point + Vector3(randf_range(-2, 2), randf_range(1.0, 4.0), randf_range(-2, 2))
			Vfx.slash(_world, Transform3D(Basis(Vector3.UP, randf() * TAU), at), Color(0.75, 1.0, 0.9), 2.4, randf_range(-1.2, 1.2))
			Sfx.play_at(&"strike_whoosh", at, -4.0, 0.2)
		if not _struck and k > 0.55:
			_strike_area(target_point, radius)
			_shake_now(0.35, 0.6)
		await get_tree().process_frame
		t += get_process_delta_time()
	for f: Node3D in caught:
		if is_instance_valid(f):
			var a: Vector3 = starts[f]
			f.global_position = Vector3(f.global_position.x, a.y, f.global_position.z)
			Vfx.dust(_world, f.global_position, 1.0)


## Bolts fall on every foe in range one after another, then chain between them.
func _chain() -> void:
	var radius := float(ult["radius"])
	var foes := _foes_near(player.global_position, radius)
	foes.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(target_point) < b.global_position.distance_to(target_point))
	var points: Array[Vector3] = []
	for f in foes:
		points.append(f.global_position + Vector3.UP)
	if points.is_empty():
		for i in 3:
			points.append(target_point + Vector3(randf_range(-2, 2), 1.0, randf_range(-2, 2)))
	var power := _power()
	for i in points.size():
		if _skipping:
			break
		var p := points[i]
		Vfx.bolt(_world, p + Vector3(randf_range(-3, 3), 30.0, randf_range(-3, 3)), p, Color(0.95, 0.9, 0.5), 0.28, 0.35)
		Vfx.flash(_world, p, Color(1.0, 0.95, 0.6), 3.4, 0.25)
		Vfx.impact(_world, p, Element.LIGHTNING, 1.6)
		_overlay.flash(Color(1, 1, 0.85, 0.45), 0.12)
		Sfx.play_at(&"thunder", p, 2.0, 0.15)
		_shake_now(0.3, 0.3)
		if i < foes.size() and is_instance_valid(foes[i]):
			if Combat.apply_hit(foes[i], power, element, player) > 0.0:
				player.notify_hit(foes[i], &"ultimate")
		_look_follow(p, 0.5)
		await _wait(0.16)
	_struck = true
	# Then the bolts leap from foe to foe.
	for i in range(1, points.size()):
		Vfx.bolt(_world, points[i - 1], points[i], Color(0.95, 0.9, 0.5), 0.12, 0.4)
	if points.size() > 1:
		Sfx.play(&"cast_lightning", 0.0)
	await _wait(0.5)


## A ring of stone spears, then a giant fist bursting up from beneath the foe.
func _fist() -> void:
	var radius := float(ult["radius"])
	var ground := _ground(target_point)
	for i in 8:
		var a := TAU * i / 8.0
		Vfx._spike(_world, ground + Vector3(cos(a), 0, sin(a)) * radius * 0.75, Color(0.55, 0.42, 0.3), 2.6)
	Vfx.dust(_world, ground, 2.0)
	Sfx.play_at(&"wall_rise", ground, 3.0)
	_shake_now(0.25, 0.5)
	await _wait(0.35)
	var fist := _stone_fist()
	_world.add_child(fist)
	# Leaning a little toward the player, knuckles first.
	var lean := Basis(_forward().cross(Vector3.UP).normalized(), 0.22)
	fist.global_transform = Transform3D(lean * Basis.looking_at(-_forward(), Vector3.UP), ground - Vector3.UP * 4.0)
	var tw := create_tween()
	tw.tween_property(fist, "global_position", ground + Vector3.UP * 3.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Vfx.debris(_world, ground, Color(0.45, 0.36, 0.28), 24, 11.0, 1.6)
	Vfx.area_blast(_world, ground, Element.EARTH, radius)
	Sfx.play_at(&"explosion", ground, 3.0)
	_shake_now(0.7, 0.7)
	var foes := _foes_near(target_point, radius)
	_strike_area(target_point, radius)
	# Thrown into the air by the blow (the tween is the sequence's: the foes
	# themselves are frozen).
	for f in foes:
		if is_instance_valid(f):
			var up := create_tween()
			up.tween_property(f, "global_position:y", f.global_position.y + 3.5, 0.3).set_ease(Tween.EASE_OUT)
			up.tween_property(f, "global_position:y", f.global_position.y, 0.35).set_ease(Tween.EASE_IN)
	await _wait(0.75)
	var sink := create_tween()
	sink.tween_property(fist, "global_position", ground - Vector3.UP * 5.0, 0.4).set_ease(Tween.EASE_IN)
	sink.tween_callback(fist.queue_free)


## A wall of water rises behind the player and breaks over the target: a
## leaning body of water, a curling foam crest, spray along its foot.
func _wave() -> void:
	var radius := float(ult["radius"])
	var fwd := _forward()
	var width := radius * 2.2
	var wave := Node3D.new()
	wave.name = "Leviathan"
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(width, 6.0, 2.2)
	body.mesh = body_mesh
	body.material_override = Vfx.energy_material(Color(0.12, 0.38, 0.85), 1.1, 0.45)
	body.position = Vector3(0, 3.0, 0)
	body.rotation.x = -0.22
	wave.add_child(body)
	# The crest curls over the front.
	var crest := MeshInstance3D.new()
	var crest_mesh := CylinderMesh.new()
	crest_mesh.top_radius = 1.25
	crest_mesh.bottom_radius = 1.25
	crest_mesh.height = width
	crest.mesh = crest_mesh
	crest.material_override = Vfx.energy_material(Color(0.55, 0.82, 1.0), 1.6, 0.2)
	crest.rotation.z = PI * 0.5
	crest.position = Vector3(0, 6.1, -1.0)
	wave.add_child(crest)
	_world.add_child(wave)
	var start := _ground(player.global_position - fwd * 3.0)
	var end := _ground(target_point + fwd * 1.5)
	wave.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), start)
	wave.scale = Vector3(1.0, 0.15, 1.0)
	Sfx.play(&"cast_water", 3.0)
	Sfx.play(&"wind_loop", -6.0)
	var t := 0.0
	var run := 1.1
	var next := 0.0
	while t < run and not _skipping:
		var k := t / run
		wave.global_position = start.lerp(end, smoothstep(0.0, 1.0, k))
		# Rises fast, leans further as it runs, and collapses at the end.
		var rise := minf(k * 3.5, 1.0) * lerpf(1.0, 0.35, maxf(0.0, k - 0.75) / 0.25)
		wave.scale = Vector3(1.0, maxf(0.15, rise), 1.0)
		crest.rotation.x = -k * 2.5
		if t >= next:
			next = t + 0.04
			var along := wave.global_basis.x * randf_range(-width * 0.5, width * 0.5)
			Vfx.sparks(_world, wave.global_position + along + Vector3.UP * 6.0 * rise, Color(0.9, 0.97, 1.0), 10, 7.0, -fwd, 70.0)
			Vfx.dust(_world, wave.global_position + along - fwd * 1.2, 1.4, Color(0.7, 0.85, 1.0))
		_look_follow(wave.global_position + Vector3.UP * 2.0, 0.25)
		await get_tree().process_frame
		t += get_process_delta_time()
	wave.queue_free()
	Vfx.area_blast(_world, _ground(target_point), Element.WATER, radius)
	Vfx.shockwave(_world, _ground(target_point) + Vector3.UP * 0.2, Color(0.4, 0.7, 1.0), radius * 1.3, 0.6)
	for i in 10:
		var a := TAU * i / 10.0
		Vfx.sparks(_world, _ground(target_point + Vector3(cos(a), 0, sin(a)) * radius * 0.5) + Vector3.UP,
			Color(0.85, 0.95, 1.0), 12, 9.0)
	Sfx.play_at(&"explosion", target_point, 0.0)
	_shake_now(0.5, 0.6)
	_strike_area(target_point, radius)
	await _wait(0.4)


## Shade clones (made during the close-up) burst out of smoke around the foe
## and strike together.
func _shades_strike() -> void:
	var radius := float(ult["radius"])
	for i in _shades.size():
		var m := _shades[i]
		if not is_instance_valid(m):
			continue
		var a := TAU * i / _shades.size() + 0.4
		var at := _ground(target_point + Vector3(cos(a), 0, sin(a)) * 2.1)
		m.global_position = at
		m.look_at(Vector3(target_point.x, at.y, target_point.z), Vector3.UP)
		m.visible = true
		Vfx.smoke_puff(_world, at + Vector3.UP, 1.0)
		Sfx.play_at(&"smoke", at, -4.0, 0.2)
		await _wait(0.07)
	await _wait(0.2)
	for beat in 3:
		if _skipping:
			break
		for m in _shades:
			if is_instance_valid(m) and m.animator:
				m.animator.strike()
				Vfx.slash(_world, Transform3D(m.global_basis, m.global_position + Vector3.UP * 1.1),
					Color(0.6, 0.65, 1.0), 2.0, randf_range(-1.2, 1.2))
		Vfx.hit_spark(_world, target_point + Vector3.UP * 1.1, Color(0.8, 0.85, 1.0), 2.0)
		Sfx.play_at(&"strike_hit", target_point, 2.0, 0.15)
		_shake_now(0.25, 0.25)
		await _wait(0.24)
	Vfx.area_blast(_world, _ground(target_point), Element.NONE, radius * 0.7)
	_strike_area(target_point, radius)
	await _wait(0.35)


## A forearm and fist of rough stone, knuckles forward (-Z).
func _stone_fist() -> Node3D:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.36, 0.31, 0.27)
	stone.roughness = 1.0
	var dark := stone.duplicate() as StandardMaterial3D
	dark.albedo_color = Color(0.27, 0.23, 0.2)
	var root := Node3D.new()
	root.name = "StoneFist"
	var parts := [
		# [size, position, material]: the forearm, the fist, four knuckles, the thumb.
		[Vector3(2.4, 6.0, 2.2), Vector3(0, -1.0, 0), dark],
		[Vector3(3.4, 2.6, 2.8), Vector3(0, 3.1, 0), stone],
		[Vector3(0.8, 0.8, 0.9), Vector3(-1.2, 4.35, -1.1), stone],
		[Vector3(0.8, 0.85, 0.9), Vector3(-0.4, 4.4, -1.15), stone],
		[Vector3(0.8, 0.85, 0.9), Vector3(0.4, 4.4, -1.15), stone],
		[Vector3(0.8, 0.8, 0.9), Vector3(1.2, 4.35, -1.1), stone],
		[Vector3(0.9, 1.6, 0.9), Vector3(1.9, 2.9, -0.6), dark],
	]
	for p: Array in parts:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = p[0]
		mi.mesh = box
		mi.position = p[1]
		mi.rotation = Vector3(randf_range(-0.06, 0.06), randf_range(-0.06, 0.06), randf_range(-0.06, 0.06))
		mi.material_override = p[2]
		root.add_child(mi)
	return root


func _summon_shades() -> void:
	for i in 4:
		var m := CharacterModel.new()
		m.use_profile = true
		m.visible = false
		_world.add_child(m)
		_shades.append(m)
		# One a frame, so the close-up doesn't hitch.
		await get_tree().process_frame


# --- Helpers -------------------------------------------------------------------

func _pick_target() -> Vector3:
	var t: Node3D = player.lock_target if is_instance_valid(player.lock_target) else player.soft_target()
	if t == null:
		var best := INF
		for f in _foes_near(player.global_position, 22.0):
			var d := f.global_position.distance_to(player.global_position)
			if d < best:
				best = d
				t = f
	if t != null:
		return t.global_position
	return player.global_position + _forward() * 8.0


func _forward() -> Vector3:
	var f := -player.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func _ground(at: Vector3) -> Vector3:
	return Vector3(at.x, Combat.ground_height(player.get_world_3d(), at, at.y + 1.0), at.z)


## Everyone the player could hurt near `center`.
func _foes_near(center: Vector3, radius: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var exclude: Array[RID] = [player.get_rid()]
	for victim in Combat.hittables_in_sphere(player.get_world_3d(), center + Vector3.UP, radius, exclude):
		if victim is Node3D and not Combat.same_team(victim, player):
			out.append(victim)
	return out


func _power() -> float:
	return float(ult["power"]) * Perks.damage_multiplier(element) * (1.0 + player.stats.modifier(&"attack_power"))


func _strike_area(center: Vector3, radius: float) -> void:
	if _struck:
		return
	_struck = true
	var power := _power()
	for victim in _foes_near(center, radius):
		if Combat.apply_hit(victim, power, element, player) > 0.0:
			player.notify_hit(victim, &"ultimate")


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds and not _skipping:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shake_now(amount: float, seconds: float) -> void:
	_shake = maxf(_shake if _shake_left > 0.0 else 0.0, amount)
	_shake_left = maxf(_shake_left, seconds)


## Turns the wide shot toward `point` a little at a time.
func _look_follow(point: Vector3, weight: float) -> void:
	var want := Transform3D(Basis.IDENTITY, _cam_base.origin).looking_at(point, Vector3.UP)
	_cam_base.basis = _cam_base.basis.slerp(want.basis, weight * 0.06).orthonormalized()


## Stops every fighter and projectile where it is: time stands still for
## everyone but the player.
func _freeze_world() -> void:
	var stopped: Array[Node] = []
	stopped.append_array(_world.find_children("*", "EnemyShinobi", true, false))
	stopped.append_array(_world.find_children("*", "JutsuProjectile", true, false))
	stopped.append_array(_world.find_children("*", "TrainingDummy", true, false))
	for n in stopped:
		_frozen[n] = [n.process_mode, (n as CollisionObject3D).disable_mode if n is CollisionObject3D else 0]
		# Frozen, but still there to be hit (a disabled body otherwise leaves
		# the physics world).
		if n is CollisionObject3D:
			(n as CollisionObject3D).disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		n.process_mode = Node.PROCESS_MODE_DISABLED
	# Name tags and health numbers would clutter the shots.
	for tag in _world.find_children("*", "Label3D", true, false):
		if (tag as Label3D).visible:
			tag.visible = false
			_hidden_tags.append(tag)


func _unfreeze_world() -> void:
	# Untyped: the blow may have finished some of them off.
	for n: Variant in _frozen.keys():
		if is_instance_valid(n):
			(n as Node).process_mode = _frozen[n][0]
			if n is CollisionObject3D:
				(n as CollisionObject3D).disable_mode = _frozen[n][1]
	_frozen.clear()
	for tag: Variant in _hidden_tags:
		if not is_instance_valid(tag):
			continue
		# Not over someone the blow just defeated.
		var owner_node := (tag as Node).get_parent()
		if not (owner_node.has_method(&"is_defeated") and owner_node.is_defeated()):
			(tag as Label3D).visible = true
	_hidden_tags.clear()


func frozen_count() -> int:
	return _frozen.size()
