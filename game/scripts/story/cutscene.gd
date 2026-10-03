class_name Cutscene
extends Node
## Plays a story "scene" beat: a short film made of steps (camera shots,
## characters walking, leaping and weaving, effects, lines, fades and
## captions) under letterbox bars. Steps run one after another; a step with
## "async": true runs alongside the ones after it. Holding Pause skips to the
## end, leaving everyone where the scene would have. docs/STORY.md lists the
## steps.

signal finished

## Seconds Pause must be held to skip.
const SKIP_HOLD := 0.9
const WALK_SPEED := 1.8
const RUN_SPEED := 6.5
const SHOT_FOV := 50.0
## Where a character's eyes are, as a share of their height.
const EYES := 0.93

## The scene playing now, if any (the pause menu and the dialogue camera
## leave it alone).
static var active: Cutscene

var director: StoryDirector
var skipping := false
var camera: Camera3D
var overlay: CutsceneOverlay

var _jobs := 0
var _shot := 0
var _cam_base := Transform3D.IDENTITY
var _shake := 0.0
var _shake_left := 0.0
var _skip_held := 0.0
var _prev_camera: Camera3D
var _player_was_visible := true


func _init(d: StoryDirector) -> void:
	name = "Cutscene"
	director = d


## Plays the steps (as parsed by Story) and emits `finished`.
func play(steps: Array) -> void:
	if UltimateSequence.active != null:
		await UltimateSequence.active.finished
	active = self
	var player := director.player
	_player_was_visible = player.visible
	player.input_enabled = false
	player._set_lock(null)
	director.hud.set_objective("")
	director.hud.visible = false
	for npc: StoryNpc in director.npcs.values():
		npc.show_tag(false)
	_prev_camera = get_viewport().get_camera_3d()
	camera = Camera3D.new()
	camera.name = "CutsceneCamera"
	camera.fov = SHOT_FOV
	camera.far = 3000.0
	director.stage.add_child(camera)
	if _prev_camera:
		camera.global_transform = _prev_camera.global_transform
		camera.fov = _prev_camera.fov
	_cam_base = camera.global_transform
	camera.current = true
	overlay = CutsceneOverlay.new()
	add_child(overlay)
	overlay.show_bars()

	for step: Dictionary in steps:
		if step["async"] and not skipping:
			_job(step)
		else:
			await _run(step)
	while _jobs > 0:
		await get_tree().process_frame
	_finish()


## Jumps to the end: every remaining step lands at once.
func skip() -> void:
	if skipping:
		return
	skipping = true
	Voice.stop()
	director.dialogue.abort()


func _process(delta: float) -> void:
	if not skipping and Input.is_action_pressed(&"pause"):
		_skip_held += delta
		if _skip_held >= SKIP_HOLD:
			skip()
	else:
		_skip_held = maxf(0.0, _skip_held - delta * 2.0)
	if overlay:
		overlay.set_skip_progress(_skip_held / SKIP_HOLD)
	if is_instance_valid(camera):
		var t := _cam_base
		if _shake_left > 0.0:
			_shake_left -= delta
			var k := _shake * clampf(_shake_left / 0.3, 0.0, 1.0)
			t.origin += t.basis * Vector3(randf_range(-k, k), randf_range(-k, k), 0.0)
		camera.global_transform = t


func _finish() -> void:
	var player := director.player
	player.scripted_velocity = Vector3.ZERO
	player.scripted_pose = -1
	player.visible = _player_was_visible or player.visible
	for npc: StoryNpc in director.npcs.values():
		if is_instance_valid(npc):
			npc.settle(player)
			npc.show_tag(true)
	director.dialogue.auto = false
	_shot += 1
	if is_instance_valid(_prev_camera):
		_prev_camera.current = true
	if is_instance_valid(camera):
		camera.queue_free()
	overlay.hide_bars()
	overlay.fade_to(0.0, 0.3)
	# Let the bars slide away before the overlay goes.
	get_tree().create_timer(CutsceneOverlay.SLIDE + 0.1).timeout.connect(overlay.queue_free)
	remove_child(overlay)
	director.add_child(overlay)
	active = null
	finished.emit()


func _job(step: Dictionary) -> void:
	_jobs += 1
	await _run(step)
	_jobs -= 1


func _run(s: Dictionary) -> void:
	match s["action"]:
		"wait": await _sleep(s["seconds"])
		"cam": await _cam(s)
		"say": await _say(s)
		"enter": _enter(s)
		"exit": _exit(s)
		"move": await _move(s)
		"leap": await _leap(s)
		"face": _face(s)
		"pose": await _pose(s)
		"weave": await _weave(s)
		"cast": await _cast(s)
		"fx": await _fx(s)
		"grow": await _grow(s)
		"music":
			if s["track"] == "none":
				Music.stop()
			else:
				Music.play(StringName(s["track"]))
		"sfx":
			if not skipping:
				Sfx.play(StringName(s["sound"]))
		"time":
			if director.stage.has_method(&"set_time_of_day"):
				director.stage.set_time_of_day(s["time"])
		"weather":
			if director.stage.has_method(&"set_weather"):
				director.stage.set_weather(s["weather"])
		"fade":
			if not skipping:
				overlay.fade_to(1.0 if s["fade"] == "out" else 0.0, s["seconds"], s["color"])
				await _sleep(s["seconds"])
		"title":
			if not skipping:
				overlay.caption(s["title"], s["sub"], s["seconds"])
				await _sleep(s["seconds"])


func _sleep(seconds: float) -> void:
	var t := 0.0
	while t < seconds and not skipping:
		await get_tree().process_frame
		t += get_process_delta_time()


# --- Who and where -------------------------------------------------------------------

func _actor(who: String) -> Node3D:
	if who == Story.PLAYER:
		return director.player
	var npc: Variant = director.npcs.get(who)
	return npc if is_instance_valid(npc) else null


## A step's target (a character, [x, z] on the ground or [x, y, z]) as a
## point: a character's `share` of their height, the ground plus `lift`.
func _point(target: Variant, share := 0.55, lift := 0.0) -> Vector3:
	if target is String:
		var a := _actor(target)
		if a == null:
			return Vector3.ZERO
		return a.global_position + Vector3.UP * _height(a) * share
	if target is Vector2:
		return Vector3(target.x, lift, target.y)
	return target


## A character's height in metres.
func _height(a: Node3D) -> float:
	var m: Variant = a.get(&"model")
	var h: float = (m as CharacterModel).measure_height() if m is CharacterModel and (m as CharacterModel).instance else 0.0
	return (h if h > 0.5 else 1.62) * a.scale.y


func _facing(a: Node3D) -> Vector3:
	var f := -a.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


# --- Camera ------------------------------------------------------------------------

func _cam(s: Dictionary) -> void:
	if skipping or not _shot_ready(s):
		return
	_shot += 1
	_cam_loop(s, _shot)
	await _sleep(s["seconds"])


## Moves the camera for one shot, every frame until the next shot replaces it
## (so close-ups keep following someone who moves).
func _cam_loop(s: Dictionary, id: int) -> void:
	var start := camera.global_transform
	var start_fov := camera.fov
	var t := 0.0
	while id == _shot and not skipping and is_instance_valid(camera):
		var k := clampf(t / maxf(s["seconds"], 0.001), 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		var xf := _shot_transform(s, k)
		var fov: float = s["fov"]
		var blend: float = s["blend"]
		if blend > 0.0 and t < blend:
			var w := smoothstep(0.0, 1.0, t / blend)
			xf = start.interpolate_with(xf, w)
			fov = lerpf(start_fov, fov, w)
		_cam_base = xf
		camera.global_transform = xf
		camera.fov = fov
		await get_tree().process_frame
		t += get_process_delta_time()


## False when a shot is about someone who isn't on stage (an ally who is
## fighting rather than standing there, say).
func _shot_ready(s: Dictionary) -> bool:
	var who: Array = []
	for key in ["on", "from"]:
		if s.has(key):
			who.append_array(s[key] if s[key] is Array else [s[key]])
	for key in ["at", "to", "look", "look_to"]:
		if s.has(key) and s[key] is String:
			who.append(s[key])
	return who.all(func(w: String) -> bool: return _actor(w) != null)


func _shot_transform(s: Dictionary, k: float) -> Transform3D:
	var kind: String = s["cam"]
	var eye := Vector3.ZERO
	var look := Vector3.ZERO
	match kind:
		"free":
			eye = _point(s["at"]).lerp(_point(s.get("to", s["at"])), k)
			look = _point(s["look"], EYES, 1.0).lerp(_point(s.get("look_to", s["look"]), EYES, 1.0), k)
		"orbit":
			var a := _actor(s["on"])
			var centre := a.global_position + Vector3.UP * _height(a) * 0.6
			var f := _facing(a)
			var ang := atan2(f.x, f.z) + deg_to_rad(float(s["degrees"])) * k
			var r: float = s["radius"]
			eye = centre + Vector3(sin(ang) * r, s["height"], cos(ang) * r)
			look = centre
		"over":
			var a := _actor(s["from"])
			var b := _actor(s["on"])
			var dir := b.global_position - a.global_position
			dir.y = 0.0
			dir = dir.normalized() if dir.length() > 0.01 else _facing(a)
			var right := dir.cross(Vector3.UP).normalized()
			var head := a.global_position + Vector3.UP * _height(a) * EYES
			eye = head - dir * 1.3 + right * 0.55 * float(s["side"]) + Vector3.UP * 0.25
			look = b.global_position + Vector3.UP * _height(b) * 0.8
		"two":
			var a := _actor(s["on"][0])
			var b := _actor(s["on"][1])
			var mid := (a.global_position + b.global_position) * 0.5
			var across := b.global_position - a.global_position
			across.y = 0.0
			var side := Vector3.UP.cross(across).normalized() * float(s["side"])
			if side.length() < 0.01:
				side = _facing(a)
			var span := maxf(across.length(), 1.0)
			eye = mid + side * (span * 1.1 + 1.5) + Vector3.UP * 1.5
			look = mid + Vector3.UP * 1.2
		_:
			# Framings of one character: in front of them, pushing slowly in.
			var a := _actor(s["on"])
			var h := _height(a)
			var f := _facing(a)
			var right := f.cross(Vector3.UP).normalized()
			var dist: float = s["dist"]
			var lift: float = s["height"]
			var at := h * EYES
			match kind:
				"mid":
					at = h * 0.72
				"wide":
					at = h * 0.5
				"low":
					at = h * 0.75
			dist *= lerpf(1.12, 1.0, k)
			eye = a.global_position + f * dist + right * float(s["side"]) * dist * 0.25 + Vector3.UP * lift
			look = a.global_position + Vector3.UP * at
	var up := Vector3.UP if absf((look - eye).normalized().y) < 0.98 else Vector3.BACK
	return Transform3D(Basis.looking_at(look - eye, up), eye)


# --- Lines -------------------------------------------------------------------------

func _say(s: Dictionary) -> void:
	if skipping:
		return
	var box := director.dialogue
	box.auto = true
	box.play(s["lines"], director.story)
	while box.is_open() and not skipping:
		await get_tree().process_frame
	box.auto = false


# --- Characters --------------------------------------------------------------------

func _enter(s: Dictionary) -> void:
	var from: Variant = s["from"] if not skipping else null
	var npc := director.add_npc(s["who"], s["at"], skipping or not s["puff"], from)
	if s["facing"] != null:
		_face({"who": s["who"], "to": s["facing"]})


func _exit(s: Dictionary) -> void:
	director.remove_npc(s["who"], not skipping and s["puff"])


func _face(s: Dictionary) -> void:
	var a := _actor(s["who"])
	if a == null:
		return
	var to: Variant = s["to"]
	if a is StoryNpc:
		var target := _actor(to) if to is String else null
		(a as StoryNpc).look_at_node = target
		if target == null:
			(a as StoryNpc).turn_to(_point(to))
	elif a is Player:
		(a as Player)._face_now(_point(to) - a.global_position)


func _move(s: Dictionary) -> void:
	var a := _actor(s["who"])
	if a == null:
		return
	var dest: Vector3 = _point(s["to"])
	dest.y = a.global_position.y
	var speed: float = RUN_SPEED if s["run"] else WALK_SPEED
	var npc := a as StoryNpc
	var looked: Node3D = npc.look_at_node if npc else null
	if npc:
		npc.look_at_node = null
	while not skipping and is_instance_valid(a):
		var to := dest - a.global_position
		to.y = 0.0
		if to.length() < 0.12:
			break
		var dt := get_process_delta_time()
		var dir := to.normalized()
		if npc:
			npc.global_position += dir * minf(speed * dt, to.length())
			npc.turn_to(npc.global_position + dir, 10.0)
			npc.speed_ratio = speed / RUN_SPEED
		else:
			(a as Player).scripted_velocity = dir * speed
		await get_tree().process_frame
	if not is_instance_valid(a):
		return
	if npc:
		npc.speed_ratio = 0.0
		npc.global_position = Vector3(dest.x, npc.global_position.y, dest.z)
		npc.look_at_node = looked
	else:
		var p := a as Player
		p.scripted_velocity = Vector3.ZERO
		if skipping:
			p.global_position = Vector3(dest.x, p.global_position.y, dest.z)


func _leap(s: Dictionary) -> void:
	var npc := _actor(s["who"]) as StoryNpc
	if npc == null:
		return
	var from: Vector3 = s["from"] if s["from"] != null else npc.global_position
	var to: Vector3 = _point(s["to"])
	var looked := npc.look_at_node
	npc.look_at_node = null
	var seconds: float = s["seconds"] if s["seconds"] > 0.0 else clampf(from.distance_to(to) / 14.0, 0.5, 1.6)
	var height: float = s["height"]
	if not skipping:
		Sfx.play_at(&"jump", from, -4.0)
		npc.turn_to(to)
		npc.airborne = true
	var t := 0.0
	while t < seconds and not skipping and is_instance_valid(npc):
		var k := t / seconds
		npc.global_position = from.lerp(to, k) + Vector3.UP * height * 4.0 * k * (1.0 - k)
		await get_tree().process_frame
		t += get_process_delta_time()
	if not is_instance_valid(npc):
		return
	npc.global_position = to
	npc.airborne = false
	npc.look_at_node = looked
	if not skipping:
		Vfx.dust(director.stage, to, 1.2)
		Sfx.play_at(&"land", to, -2.0)


func _pose(s: Dictionary) -> void:
	var a := _actor(s["who"])
	if a == null or skipping:
		return
	var pose: int = s["as"]
	_set_pose(a, pose)
	if s["seconds"] > 0.0:
		await _sleep(s["seconds"])
		if is_instance_valid(a):
			_set_pose(a, HumanoidPoser.Pose.LOCOMOTION)


func _set_pose(a: Node3D, pose: int) -> void:
	if a is StoryNpc:
		(a as StoryNpc).pose = pose
	elif a is Player:
		(a as Player).scripted_pose = pose if pose != HumanoidPoser.Pose.LOCOMOTION else -1


## Seals one after another, each flashing above the weaver's head, then a
## burst of chakra.
func _weave(s: Dictionary) -> void:
	var a := _actor(s["who"])
	if a == null or skipping:
		return
	_set_pose(a, HumanoidPoser.Pose.WEAVE)
	Sfx.play_at(&"weave_start", a.global_position, -4.0)
	var tag := Label3D.new()
	tag.font = UiKit.font(&"bold")
	tag.font_size = 64
	tag.outline_size = 12
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.pixel_size = 0.006
	tag.modulate = UiKit.PAPER
	tag.outline_modulate = Color(UiKit.INK, 0.9)
	tag.position = Vector3.UP * (_height(a) / maxf(a.scale.y, 0.01) + 0.45)
	a.add_child(tag)
	for seal: int in s["seals"]:
		if skipping or not is_instance_valid(a):
			break
		tag.text = Seal.kanji(seal)
		Sfx.play_at(StringName("seal_%d" % (Seal.bank_of(seal) + 1)), a.global_position, -2.0)
		var model: CharacterModel = a.get(&"model")
		if model and model.animator:
			model.animator.seal_flick()
		await _sleep(0.32)
	if is_instance_valid(tag):
		tag.queue_free()
	if is_instance_valid(a):
		if not skipping:
			Vfx.flash(director.stage, a.global_position + Vector3.UP * _height(a) * 0.7, UiKit.GOLD, 1.4, 0.2)
		_set_pose(a, HumanoidPoser.Pose.LOCOMOTION)


## A technique for show: nobody is hurt.
func _cast(s: Dictionary) -> void:
	var a := _actor(s["who"])
	if a == null or skipping:
		return
	var element: int = s["element"]
	var color := Element.color(element)
	var target := _point(s["at"], 0.55)
	var stage := director.stage
	Sfx.play_at(StringName("cast_" + Element.NAMES[element]), a.global_position, -2.0)
	match s["kind"]:
		"blast":
			Vfx.area_blast(stage, Vector3(target.x, 0.0, target.z), element, 3.0)
			Sfx.play_at(&"explosion", target, -3.0)
			_shake_now(0.12, 0.5)
		"bolt":
			_lightning(target, color)
		_:
			var model: CharacterModel = a.get(&"model")
			if model and model.animator:
				model.animator.throw()
			var visual := Vfx.projectile_visual(element, 0.35)
			stage.add_child(visual)
			var from := a.global_position + Vector3.UP * _height(a) * 0.7 + _facing(a) * 0.6
			visual.global_position = from
			var dist := from.distance_to(target)
			var t := 0.0
			while t * 22.0 < dist and not skipping and is_instance_valid(visual):
				visual.global_position = from.lerp(target, t * 22.0 / dist)
				var dir := (target - from).normalized()
				if absf(dir.y) < 0.99:
					visual.global_basis = Basis.looking_at(dir, Vector3.UP)
				await get_tree().process_frame
				t += get_process_delta_time()
			if is_instance_valid(visual):
				visual.global_position = target
				Vfx.linger(visual, stage)
			if not skipping:
				Vfx.impact(stage, target, element, 1.3)
				Sfx.play_at(&"impact", target, -3.0)


func _lightning(at: Vector3, color: Color) -> void:
	var stage := director.stage
	Vfx.bolt(stage, at + Vector3(randf_range(-3, 3), 26.0, randf_range(-3, 3)), at, color.lightened(0.4), 0.14, 0.3)
	Vfx.flash(stage, at, color.lightened(0.5), 3.0, 0.25, &"glow")
	Vfx.sparks(stage, at, color, 18, 9.0)
	if stage.has_method(&"_flash_lightning"):
		stage._flash_lightning()
	else:
		Sfx.play(&"thunder", -2.0)
	_shake_now(0.18, 0.5)


func _fx(s: Dictionary) -> void:
	if skipping:
		return
	var stage := director.stage
	var color: Color = s["color"]
	var size: float = s["size"]
	match s["fx"]:
		"flash":
			overlay.flash(color, s["seconds"] if s["seconds"] > 0.0 else 0.5)
		"shake":
			_shake_now(0.15 * size, s["seconds"] if s["seconds"] > 0.0 else 0.6)
		"lightning":
			_lightning(_point(s["at"], 0.0), color)
		"blast":
			var at := _point(s["at"], 0.0)
			Vfx.area_blast(stage, Vector3(at.x, 0.0, at.z), s["element"], 3.0 * size)
			Sfx.play_at(&"explosion", at, -3.0)
			_shake_now(0.12 * size, 0.5)
		"smoke":
			Vfx.smoke_puff(stage, _point(s["at"], 0.5), size)
			Sfx.play_at(&"smoke", _point(s["at"], 0.5), -3.0)
		"dust":
			Vfx.dust(stage, _point(s["at"], 0.0), size)
		"aura":
			var a := _actor(s["on"])
			if a:
				var old := a.get_node_or_null(^"SceneAura")
				if old:
					old.queue_free()
				var aura := Vfx.boss_aura(color, size)
				aura.name = "SceneAura"
				a.add_child(aura)
				Sfx.play_at(&"buff", a.global_position, -2.0)
				if s["seconds"] > 0.0:
					get_tree().create_timer(s["seconds"]).timeout.connect(func() -> void:
						if is_instance_valid(aura):
							aura.queue_free())
		"beam":
			# A crackling stream of chakra from one point to another.
			var t := 0.0
			var seconds: float = s["seconds"] if s["seconds"] > 0.0 else 1.0
			var next := 0.0
			while t < seconds and not skipping:
				if t >= next:
					next = t + 0.06
					var a := _point(s["from"], 0.6)
					var b := _point(s["to"], 0.6)
					Vfx.bolt(stage, a, b, color, 0.07 * size, 0.12)
				await get_tree().process_frame
				t += get_process_delta_time()
	if s["seconds"] > 0.0 and s["fx"] in ["flash", "shake"]:
		await _sleep(s["seconds"])


func _grow(s: Dictionary) -> void:
	var a := _actor(s["who"])
	if a == null:
		return
	var from := a.scale.x
	var to: float = s["scale"]
	var seconds: float = s["seconds"]
	var t := 0.0
	while t < seconds and not skipping and is_instance_valid(a):
		var k := smoothstep(0.0, 1.0, t / seconds)
		a.scale = Vector3.ONE * lerpf(from, to, k)
		await get_tree().process_frame
		t += get_process_delta_time()
	if is_instance_valid(a):
		a.scale = Vector3.ONE * to


func _shake_now(amount: float, seconds: float) -> void:
	_shake = amount
	_shake_left = seconds
