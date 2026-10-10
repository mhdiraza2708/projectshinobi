class_name TrailerDirector
extends Node
## The 60-second trailer, played with the game's own systems: a fixed cut
## list timed to the trailer's music (art/trailer/make_trailer_audio.py, 120
## BPM, so every cut lands on a two-second bar line). Recorded with Godot's
## movie writer, then scored by art/trailer/mix_trailer.py:
##
##   godot --path game --write-movie OUT.avi --fixed-fps 30 --resolution 1280x720 \
##       -- --screenshot=LAST.png --demo=trailer
##
## Everything on screen is the real game: islands, skies, the main
## character and the masked rivals, the katana, jutsu, Shade Clones, the
## dojutsu cut-in and awakening, an ultimate and the Nue. The director only moves a camera,
## stages who stands where and presses the buttons.

const LENGTH := 60.0
## 2.39:1 letterbox on a 16:9 frame.
const BAR_FRACTION := 0.128

var stage: Node3D
var player: Player
var cam: Camera3D
var t := 0.0

## When the eye opens: its lids part (EyeSequence.CUT_AT + the middle of
## LIDS_OPEN) on the music's awakening hit at 36 s.
const EYE_OPEN_AT := 35.05

var _overlay: CanvasLayer
var _fade: ColorRect
var _text: Label
var _title: Control
var _cast: Array[Node] = []


static func run(on_stage: Node3D) -> TrailerDirector:
	var d := TrailerDirector.new()
	d.stage = on_stage
	on_stage.add_child(d)
	return d


func play() -> void:
	player = stage.player
	_prepare()
	await _opening()
	await _island_dawn()
	await _shore()
	await _blade()
	await _weave()
	await _five_natures()
	await _rival()
	await _jonin()
	await _kagerou()
	await _awakening()
	await _ultimate()
	await _montage()
	await _title_card()


# --- Setup -------------------------------------------------------------------

func _prepare() -> void:
	# A Hearth-clan shinobi: fire nature, Hawk Eye (awakened), Hearthfall.
	Profile.set_value(&"clan", "hearth")
	Profile.set_value(&"affinity", Element.FIRE)
	Profile.set_value(&"eye_art", "hawk_eye")
	Profile.set_value(&"ultimate", "hearthfall")
	Game.mark_chapter_done(Perks.awaken_after())
	player.caster.affinity = Element.FIRE
	EyeArtMode.reset_seen()
	if stage.title_screen:
		stage.title_screen.close()
	stage.hud.visible = false
	# The score is laid on afterwards; the game's own music would clash.
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Music"), true)
	cam = Camera3D.new()
	cam.name = "TrailerCamera"
	cam.fov = 40.0
	cam.far = 4000.0
	stage.add_child(cam)
	cam.current = true
	_overlay = CanvasLayer.new()
	_overlay.layer = 60
	add_child(_overlay)
	# Anchored, not sized: the UI's base size isn't the window's.
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0 - BAR_FRACTION
		bar.anchor_bottom = BAR_FRACTION if top else 1.0
		_overlay.add_child(bar)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(_fade)
	_text = UiKit.label("", 40, UiKit.PAPER, &"display", 10)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_text.anchor_right = 1.0
	_text.anchor_top = 1.0 - BAR_FRACTION - 0.12
	_text.anchor_bottom = 1.0 - BAR_FRACTION - 0.03
	_text.modulate.a = 0.0
	_overlay.add_child(_text)
	# The frame the trailer starts on, so the mix can cut what came before.
	print("TRAILER_START_FRAME %d" % Engine.get_frames_drawn())


# --- Timing helpers --------------------------------------------------------------

## Runs `each(local_seconds)` every frame until the trailer clock reaches `end`.
func _until(end: float, each := Callable()) -> void:
	var start := t
	while t < end:
		if each.is_valid():
			each.call(t - start)
		_tidy()
		await get_tree().process_frame
		t += get_process_delta_time()


func _look(from: Vector3, at: Vector3) -> void:
	cam.global_transform = Transform3D(Basis.IDENTITY, from).looking_at(at, Vector3.UP)


func _fade_to(alpha: float, seconds: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, seconds)


## A line of text that fades in, holds and fades out by `end`.
func _caption(text: String, end: float) -> void:
	_text.text = text
	var hold := maxf(0.1, end - t - 0.8)
	var tw := create_tween()
	tw.tween_property(_text, "modulate:a", 1.0, 0.35)
	tw.tween_interval(hold)
	tw.tween_property(_text, "modulate:a", 0.0, 0.4)


## Name tags and health bars stay out of the shots.
func _tidy() -> void:
	for tag in stage.find_children("*", "Label3D", true, false):
		(tag as Label3D).visible = false
	for e in stage.find_children("*", "EnemyShinobi", true, false):
		for s in e.find_children("*", "Sprite3D", true, false):
			(s as Sprite3D).visible = false
	if stage.hud.visible:
		stage.hud.visible = false


func _ground(x: float, z: float) -> Vector3:
	var h: float = stage.island.height_at(x, z) if stage.island else 0.0
	return Vector3(x, h, z)


func _place_player(at: Vector3, facing: Vector3) -> void:
	player.global_position = at + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	var f := facing - at
	player.rotation.y = atan2(-f.x, -f.z)


## A story character as a fighter (their look, voice, nature).
func _character(who: String, element: int, at: Vector3, rank := &"jonin", hunt := false, size := 1.0) -> EnemyShinobi:
	var story := Story.load_all()
	var info: Dictionary = story.characters[who]
	var e := EnemyShinobi.new()
	e.name = "Trailer_" + who
	e.rank = rank
	e.element = element
	e.title_override = info["name"]
	e.style_override = info["style"]
	var chosen := CharacterModel.resolve_roster(info["model"])
	e.model_path = chosen if chosen != "" else EnemyShinobi.pick_model(who)
	e.hunt = hunt
	e.target = player
	e.size = size
	e.position = at + Vector3.UP * 0.2
	stage.add_child(e)
	_cast.append(e)
	return e


## A rank-and-file fighter: genin and chunin wear their nature's masked
## rival, jonin the rogue elite.
func _foe(at: Vector3, element: int, hunt := false, rank := &"genin") -> EnemyShinobi:
	var e := EnemyShinobi.new()
	e.rank = rank
	e.element = element
	e.hunt = hunt
	e.target = player
	e.position = at + Vector3.UP * 0.2
	stage.add_child(e)
	_cast.append(e)
	return e


func _clear_cast() -> void:
	for n: Variant in _cast:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_cast.clear()
	# Earth and water walls outlast whoever raised them.
	for wall in stage.find_children("*", "JutsuWall", true, false):
		wall.queue_free()


func _cast_now(id: StringName, target: Node3D) -> void:
	player.stats.chakra = player.stats.max_chakra
	var j := JutsuRegistry.get_jutsu(id)
	if j:
		if target:
			_place_player(player.global_position, target.global_position)
		player.caster.cast(j, target, true)
		if player.animator:
			player.animator.cast()


# --- The shots ---------------------------------------------------------------------

## 0-2 s: black, the game's motto in brush ink.
func _opening() -> void:
	var motto := UiKit.label("忍の道", 108, UiKit.PAPER, &"brush")
	motto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	motto.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	motto.set_anchors_preset(Control.PRESET_FULL_RECT)
	motto.modulate.a = 0.0
	_overlay.add_child(motto)
	var tw := create_tween()
	tw.tween_property(motto, "modulate:a", 1.0, 0.7).set_delay(0.2)
	tw.tween_interval(0.6)
	tw.tween_property(motto, "modulate:a", 0.0, 0.4)
	stage.use_island("emberwood")
	stage.set_time_of_day("day")
	# The training ground's dummies would follow onto the island.
	for dummy in stage.find_children("*", "TrainingDummy", true, false):
		dummy.free()
	_place_player(_ground(0, 0), _ground(0, -10))
	await _until(2.0)
	motto.queue_free()


## 2-8 s: over the sea at dawn, closing on the island.
func _island_dawn() -> void:
	_fade_to(0.0, 0.6)
	_caption("AN ORIGINAL SHINOBI ACTION GAME", 7.6)
	var coast := float(stage.island.preset.get("coast", 60.0))
	await _until(8.0, func(k: float) -> void:
		var a := deg_to_rad(200.0 + k * 7.0)
		var r := lerpf(coast * 1.9, coast * 1.45, k / 6.0)
		var h := lerpf(46.0, 30.0, k / 6.0)
		_look(Vector3(cos(a) * r, h, sin(a) * r), Vector3(0, 6, 0)))


## 8-10 s: low across the water.
func _shore() -> void:
	var coast := float(stage.island.preset.get("coast", 60.0))
	var water := float(stage.island.water_level)
	await _until(10.0, func(k: float) -> void:
		var x := lerpf(-14.0, -6.0, k / 2.0)
		_look(Vector3(x, water + 1.6, coast + 20.0), Vector3(0, water + 5.0, 0)))


## 10-14 s: the drop. The katana leaves the scabbard and two masked raiders
## fall to it.
func _blade() -> void:
	var raiders: Array[EnemyShinobi] = [_foe(_ground(-1.0, -3.4), Element.FIRE), _foe(_ground(1.6, -4.2), Element.FIRE)]
	_place_player(_ground(0, 0), raiders[0].global_position)
	_caption("DRAW THE BLADE", 13.7)
	# [when, who, what]
	var acts := [[0.1, 0, "dash"], [0.45, 0, "strike"], [0.8, 0, "strike"], [1.15, 0, "strike"],
		[1.75, 1, "dash"], [2.1, 1, "strike"], [2.45, 1, "strike"], [2.8, 1, "strike"]]
	var done := 0
	await _until(14.0, func(k: float) -> void:
		var p := player.global_position
		var who: EnemyShinobi = raiders[1 if k >= 1.6 else 0]
		var a := who.global_position if is_instance_valid(who) else p + Vector3(0, 0, -3)
		var dir := Vector3(a.x - p.x, 0.0, a.z - p.z).normalized()
		var side := dir.cross(Vector3.UP).normalized()
		_look(p - dir * 1.4 + side * 2.4 + Vector3.UP * 1.25, (p + a) * 0.5 + Vector3.UP * 1.0)
		if done < acts.size() and k >= float(acts[done][0]):
			var target: EnemyShinobi = raiders[int(acts[done][1])]
			if is_instance_valid(target):
				_place_player(p, target.global_position)
				player.lock_target = target
			match str(acts[done][2]):
				"dash": player._start_dash()
				"strike": player._strike()
			done += 1)
	player.lock_target = null


## 14-18 s: hands weaving, then a bolt of chakra leaves them.
func _weave() -> void:
	_clear_cast()
	var at := _ground(0, 0)
	var dummy := _foe(_ground(0, -11), Element.WIND)
	_place_player(at, dummy.global_position)
	player.scripted_pose = HumanoidPoser.Pose.WEAVE
	_caption("WEAVE THE SEALS", 17.7)
	var fwd := -player.global_basis.z
	var right := fwd.cross(Vector3.UP).normalized()
	var next_seal := 0.0
	var seal := 0
	var released := false
	await _until(18.0, func(k: float) -> void:
		var chest := player.global_position + Vector3.UP * 1.15
		_look(chest + fwd * lerpf(1.5, 1.1, k / 4.0) + right * 0.55 - Vector3.UP * 0.1, chest)
		if k < 2.2 and k >= next_seal:
			next_seal = k + 0.22
			if player.animator:
				player.animator.seal_flick()
			Sfx.play(StringName("seal_%d" % (seal % 3 + 1)), -2.0, 0.05)
			Vfx.sparks(stage, chest + fwd * 0.35, Color(0.62, 0.68, 0.95), 6, 3.0)
			seal += 1
		if k >= 2.3 and not released:
			released = true
			player.scripted_pose = -1
			_cast_now(&"chakra_bolt", dummy))


## 18-22 s: fire, water, wind and lightning in quick succession, at the
## storm caller, the stone warden and the tide-runner.
func _five_natures() -> void:
	_clear_cast()
	var targets: Array[EnemyShinobi] = []
	for i in 3:
		targets.append(_foe(_ground(-6.0 + i * 6.0, -14.0), [Element.LIGHTNING, Element.EARTH, Element.WATER][i]))
	_place_player(_ground(0, 0), _ground(0, -14))
	_caption("MASTER FIVE NATURES", 21.7)
	var casts := [[0.3, &"ember_volley", 0], [1.3, &"tide_lance", 1], [2.2, &"crescent_cutter", 2], [3.1, &"thunder_needle", 1]]
	var done := 0
	await _until(22.0, func(k: float) -> void:
		var p := player.global_position
		_look(p + Vector3(7.5 - k * 0.6, 2.4, 3.5), p + Vector3(0, 1.2, -6.0))
		if done < casts.size() and k >= float(casts[done][0]):
			var who: EnemyShinobi = targets[int(casts[done][2])]
			_cast_now(casts[done][1], who if is_instance_valid(who) else null)
			done += 1)


## 22-26 s: Asahi's lightning against your strikes.
func _rival() -> void:
	_clear_cast()
	var asahi := _character("asahi", Element.LIGHTNING, _ground(0, -5.5), &"jonin", true)
	_place_player(_ground(0, 0), asahi.global_position)
	player.lock_target = asahi
	var acts := [[0.4, "dash"], [0.9, "strike"], [1.2, "strike"], [1.5, "strike"], [2.4, "kunai"], [3.0, "dash"], [3.4, "strike"]]
	var done := 0
	await _until(26.0, func(k: float) -> void:
		var p := player.global_position
		var a := asahi.global_position if is_instance_valid(asahi) else p + Vector3(0, 0, -5)
		var away := Vector3(p.x - a.x, 0.0, p.z - a.z).normalized()
		var side := away.cross(Vector3.UP).normalized()
		# Over the player's shoulder, so Asahi stays in frame wherever she goes.
		_look(p + away * (3.0 - k * 0.25) + side * 1.1 + Vector3.UP * 1.7, a + Vector3.UP * 1.1)
		if done < acts.size() and k >= float(acts[done][0]):
			_place_player(p, a)
			match str(acts[done][1]):
				"dash": player._start_dash()
				"strike": player._strike()
				"kunai": player.throw_kunai()
			done += 1)


## 26-30 s: two rogue elites, and the player splits into Shade Clones.
func _jonin() -> void:
	_clear_cast()
	player.lock_target = null
	var elites: Array[EnemyShinobi] = [_foe(_ground(-2.2, -7.0), Element.FIRE, true, &"jonin"),
		_foe(_ground(2.4, -7.6), Element.LIGHTNING, true, &"jonin")]
	_place_player(_ground(0, 0), _ground(0, -7))
	_caption("SPLIT YOUR SHADOW", 29.7)
	var summoned := false
	await _until(30.0, func(k: float) -> void:
		var p := player.global_position
		var a := deg_to_rad(-35.0 + k * 16.0)
		_look(p + Vector3(sin(a) * 7.8, 3.2, cos(a) * 7.8), p + Vector3(0, 1.0, -3.6))
		if k >= 0.35 and not summoned and is_instance_valid(elites[0]):
			summoned = true
			_cast_now(&"shade_clones", elites[0]))
	for c in player.caster.clones():
		c.leave()


## 30-34 s: night. Kagerou waits in the firelight.
func _kagerou() -> void:
	_clear_cast()
	stage.set_time_of_day("night")
	var kage := _character("kagerou", Element.FIRE, _ground(0, -6), &"jonin", false, 1.05)
	var aura := Vfx.boss_aura(Color(0.95, 0.35, 0.15), 1.0)
	kage.add_child(aura)
	_place_player(_ground(0, 3), kage.global_position)
	var bloomed := false
	await _until(34.0, func(k: float) -> void:
		if not is_instance_valid(kage):
			return
		var at := kage.global_position
		var dir := (player.global_position - at).normalized()
		kage.rotation.y = atan2(-dir.x, -dir.z)
		var dist := lerpf(3.6, 1.7, smoothstep(0.0, 1.0, k / 4.0))
		_look(at + dir * dist + Vector3.UP * lerpf(1.2, 1.55, k / 4.0), at + Vector3.UP * 1.5)
		if k >= 2.4 and not bloomed:
			bloomed = true
			kage.caster.cast(JutsuRegistry.get_jutsu(&"cinder_bloom"), kage, true))


## 34-40 s: darkness, "Open your eyes", the push-in, the cut to the drawn
## eyes snapping open on the music's hit (36 s), and the awakening.
func _awakening() -> void:
	_fade_to(1.0, 0.25)
	await _until(34.6)
	_clear_cast()
	stage.set_time_of_day("dusk")
	_place_player(_ground(0, 0), _ground(0, -10))
	player.stats.chakra = player.stats.max_chakra
	await _until(EYE_OPEN_AT)
	_fade.color.a = 0.0
	# The eye sequence takes the camera: the push-in, the cut to black and
	# the lids parting (EyeSequence.CUT_AT + LIDS_OPEN) land on the hit.
	player.eye_mode.try_open()
	await _until(39.0)
	cam.current = true
	_caption("AWAKEN YOUR EYES", 40.0)
	await _until(40.0, func(k: float) -> void:
		var eyes := player.eye_mode.eye_point()
		var fwd := -player.global_basis.z
		_look(eyes + fwd * lerpf(0.95, 0.75, k) + Vector3.UP * 0.02, eyes))


var _nue: EnemyShinobi


## 40-46 s: Hearthfall.
func _ultimate() -> void:
	for i in 3:
		_foe(_ground(-3.0 + i * 3.0, -9.0 - absf(i - 1) * 1.5), [Element.WIND, Element.EARTH, Element.WATER][i])
	await _until(40.1)
	player.ult_charge = Ultimates.MAX_CHARGE
	player.try_ultimate()
	while UltimateSequence.active != null and t < 44.5:
		_tidy()
		await get_tree().process_frame
		t += get_process_delta_time()
	cam.current = true
	_caption("UNLEASH YOUR ULTIMATE", 46.0)
	# The Nue waits out of shot until its moment (a fresh spawn T-poses).
	_nue = _character("nue", Element.FIRE, _ground(24, 24), &"jonin", false, 1.5)
	var start := t
	await _until(46.0, func(k: float) -> void:
		var p := player.global_position
		var a := deg_to_rad(30.0 + (k + start - 43.0) * 18.0)
		_look(p + Vector3(cos(a) * 6.0, 2.2, sin(a) * 6.0), p + Vector3(0, 1.4, -2.0)))


## 46-54 s: the Nue, a kunai, a dash and a cut, then the night village.
func _montage() -> void:
	for n: Variant in _cast:
		if is_instance_valid(n) and n != _nue:
			(n as Node).queue_free()
	_cast = [_nue] as Array[Node]
	stage.set_time_of_day("night")
	var nue := _nue
	nue.global_position = _ground(0, -7) + Vector3.UP * 0.2
	nue.velocity = Vector3.ZERO
	nue.add_child(Vfx.boss_aura(Color(0.95, 0.4, 0.12), 1.5))
	_place_player(_ground(0, 2), nue.global_position)
	await _until(48.4, func(k: float) -> void:
		if not is_instance_valid(nue):
			return
		var at := nue.global_position
		var dir := (player.global_position - at).normalized()
		nue.rotation.y = atan2(-dir.x, -dir.z)
		_look(at + dir * lerpf(5.4, 4.2, k / 2.4) + Vector3.UP * 0.5, at + Vector3.UP * 2.4))
	# A kunai past the camera.
	_place_player(player.global_position, nue.global_position)
	player.lock_target = nue
	player.throw_kunai()
	await _until(49.4, func(k: float) -> void:
		var p := player.global_position
		var fwd := -player.global_basis.z
		_look(p - fwd * 1.6 + fwd.cross(Vector3.UP).normalized() * 0.6 + Vector3.UP * 1.6, p + fwd * 6.0 + Vector3.UP * 1.4))
	# A dash and the katana.
	player._start_dash()
	var cuts := 0
	await _until(51.0, func(k: float) -> void:
		var p := player.global_position
		if k > 0.3 + cuts * 0.35 and cuts < 3:
			cuts += 1
			player._strike()
		_look(p + Vector3(3.2, 1.0, 1.0), p + Vector3.UP * 1.1))
	# The village at night: lanterns, and the light where the next mission waits.
	_clear_cast()
	player.lock_target = null
	_place_player(_ground(0, 4), _ground(0, -10))
	_caption("A WORLD TO EXPLORE", 53.8)
	await _until(54.0, func(k: float) -> void:
		var a := deg_to_rad(150.0 + k * 9.0)
		_look(Vector3(cos(a) * 26.0, lerpf(6.0, 13.0, k / 3.0), sin(a) * 26.0), Vector3(0, 3.0, 0)))


## 54-60 s: the title.
func _title_card() -> void:
	_fade.color.a = 1.0
	_text.modulate.a = 0.0
	_title = VBoxContainer.new()
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	(_title as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	(_title as VBoxContainer).add_theme_constant_override(&"separation", -6)
	_overlay.add_child(_title)
	var parts: Array[Label] = [
		UiKit.label("忍の道", 52, UiKit.GOLD, &"brush"),
		UiKit.label("PROJECT", 96, UiKit.PAPER, &"display", 10),
		UiKit.label("SHINOBI", 190, UiKit.CRIMSON, &"display", 16),
		UiKit.label("AN ORIGINAL SHINOBI ACTION GAME", 32, UiKit.PAPER, &"bold"),
	]
	for l in parts:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title.add_child(l)
	_title.modulate.a = 0.0
	_title.scale = Vector2(1.08, 1.08)
	_title.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	var tw := create_tween().set_parallel()
	tw.tween_property(_title, "modulate:a", 1.0, 0.25)
	tw.tween_property(_title, "scale", Vector2.ONE, 4.6).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(_title, "modulate:a", 0.0, 0.7).set_delay(0.0)
	await _until(LENGTH)
