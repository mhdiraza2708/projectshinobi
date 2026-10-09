class_name EyeSequence
extends Node
## An eye art opening, in close-up: the world stops, the camera moves in on
## the face, then a hard cut to black and a drawn cut-in of the eyes
## (EyeInsert): the bangs whip aside, the lids snap open with a flash and
## the pattern spins into the irises under a brush title card. Drawn, so it
## works for any character, even one whose eyes the hair hides. The
## awakened form goes further: the pattern breaks into the awakened one,
## then a cut back to the shinobi wreathed in its colour as a shockwave
## goes out. Holding Pause skips, as in every other cinematic.

signal finished

## Seconds of the opening shot, and of the awakening after it.
const OPEN_TIME := 1.8
const AWAKEN_TIME := 1.6
## When the opening shot cuts from the face to the drawn eyes.
const CUT_AT := 0.5
## Beats of the cut-in, in seconds after the cut: the bangs sweeping aside,
## the lids opening (the flash comes as they part), and the pattern
## finishing its spin.
const HAIR_SWEEP := Vector2(0.15, 0.45)
const LIDS_OPEN := Vector2(0.35, 0.55)
const SPIN_DONE := 1.0
## How long the awakened pattern takes to break through before the cut back.
const AWAKEN_BREAK := 0.55
const FOV := 32.0
## Grace after the sequence before the player can be hurt again.
const AFTER_IFRAMES := 0.5
const SKIP_HOLD := Cutscene.SKIP_HOLD

static var active: EyeSequence

var player: Player
var mode: EyeArtMode
var art: Dictionary
var form: Dictionary
var color := Color.WHITE

var _world: Node
var _camera: Camera3D
var _prev_camera: Camera3D
var _overlay: CutsceneOverlay
var _card: CanvasLayer
var _frozen: Dictionary = {}
var _cam_base := Transform3D.IDENTITY
var _skipping := false
var _skip_held := 0.0
var _aura: Node3D
var _insert: EyeInsert


static func begin(p: Player, m: EyeArtMode) -> EyeSequence:
	var s := EyeSequence.new()
	s.player = p
	s.mode = m
	p.get_parent().add_child(s)
	s.play()
	return s


func _init() -> void:
	name = "EyeSequence"


func play() -> void:
	active = self
	_world = player.get_parent()
	art = EyeArtMode.art()
	form = EyeArtMode.form()
	color = Color(str(art.get("color", "#ffffff")))
	_frozen = CinematicKit.freeze(_world)
	player.input_enabled = false
	player.stats.is_invulnerable = true
	player.scripted_velocity = Vector3.ZERO
	player.velocity = Vector3.ZERO

	_prev_camera = get_viewport().get_camera_3d()
	_camera = Camera3D.new()
	_camera.name = "EyeCamera"
	_camera.fov = FOV
	_camera.near = 0.02
	_camera.far = 3000.0
	_camera.attributes = Graphics.shot_attributes(0.4)
	_world.add_child(_camera)
	_camera.current = true
	_overlay = CutsceneOverlay.new()
	add_child(_overlay)
	_overlay.show_bars()
	Music.duck(true)
	Sfx.play(&"weave_start", 0.0)

	await _open()
	if mode.awakened:
		await _awaken()
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
		_camera.global_transform = _cam_base


func is_skipping() -> bool:
	return _skipping


func skip() -> void:
	_skipping = true


## The card's text, for tests.
func card_text() -> String:
	return CinematicKit.card_text(_card)


## The drawn cut-in, while it's on screen (null before the cut and after).
func insert() -> EyeInsert:
	return _insert if is_instance_valid(_insert) else null


# --- The shots ---------------------------------------------------------------

## In on the face, then the cut to black: the drawn eyes open and the
## pattern spins into place.
func _open() -> void:
	var fwd := _forward()
	var eyes := mode.eye_point()
	var t := 0.0
	var flashed := false
	var carded := false
	while t < OPEN_TIME and not _skipping:
		if t < CUT_AT:
			eyes = mode.eye_point()
			var k := smoothstep(0.0, 1.0, t / CUT_AT)
			var from := eyes + fwd * 0.85 - Vector3.UP * 0.02
			var to := eyes + fwd * 0.45 - Vector3.UP * 0.015
			_cam_base = Transform3D(Basis.IDENTITY, from.lerp(to, k)).looking_at(eyes, Vector3.UP)
		else:
			if _insert == null:
				_insert = EyeInsert.new(art)
				add_child(_insert)
				Sfx.play(&"eye_open", 0.0)
			var u := t - CUT_AT
			var parting := smoothstep(LIDS_OPEN.x, LIDS_OPEN.y, u)
			# The lids snap a touch past open and settle.
			var lids := parting + sin(parting * PI) * 0.12
			var open := smoothstep(LIDS_OPEN.x + 0.05, SPIN_DONE, u)
			var spin := (1.0 - open) * TAU * 2.0
			var burst := clampf(1.0 - absf(u - LIDS_OPEN.y) / 0.35, 0.0, 1.0)
			var fade := 1.0 - smoothstep(OPEN_TIME - CUT_AT - 0.12, OPEN_TIME - CUT_AT, u) \
				if not mode.awakened else 1.0
			_insert.set_state(lids, smoothstep(HAIR_SWEEP.x, HAIR_SWEEP.y, u), open, spin, 0.0, burst, fade)
			# The model's own irises follow, for when the camera comes back.
			mode._set_pattern(open, 0.0, spin)
			if u >= LIDS_OPEN.x + 0.08 and not flashed:
				flashed = true
				_overlay.flash(Color(color, 0.6), 0.3)
			if u >= LIDS_OPEN.x + 0.1 and not carded and not mode.awakened:
				carded = true
				_card = CinematicKit.title_card(self, "開眼  DOJUTSU", str(art["kanji"]), str(form.get("name", art["name"])),
					color, OPEN_TIME - t)
		await get_tree().process_frame
		t += get_process_delta_time()
	mode._set_pattern(1.0, 0.0, 0.0)
	# Back from the cut-in on the face.
	_cam_base = Transform3D(Basis.IDENTITY, eyes + fwd * 0.45 - Vector3.UP * 0.015).looking_at(eyes, Vector3.UP)
	if not mode.awakened:
		_drop_insert()


## The first pattern breaks into the awakened one in the cut-in; then a cut
## back to the shinobi as the shockwave goes out, and the camera pulls back.
func _awaken() -> void:
	var eyes := mode.eye_point()
	var fwd := _forward()
	var from := _cam_base.origin
	var to := eyes + fwd * 1.5 + fwd.cross(Vector3.UP).normalized() * 0.35 - Vector3.UP * 0.25
	_overlay.flash(Color(1, 1, 1, 0.85), 0.3)
	Sfx.play(&"thunder", -6.0, 0.05)
	_card = CinematicKit.title_card(self, "覚醒  AWAKENED", str(form.get("kanji", art["kanji"])),
		str(form.get("name", art["name"])), color, AWAKEN_TIME)
	var t := 0.0
	var cut_back := false
	while t < AWAKEN_TIME and not _skipping:
		var change := smoothstep(0.0, AWAKEN_BREAK, t)
		var spin := (1.0 - change) * TAU * 3.0
		mode._set_pattern(1.0, change, spin)
		if t < AWAKEN_BREAK:
			if _insert:
				_insert.set_state(1.0, 1.0, 1.0, spin, change, 1.0 - change * 0.6)
		elif not cut_back:
			cut_back = true
			_drop_insert()
			_overlay.flash(Color(color, 0.7), 0.25)
			Vfx.shockwave(_world, player.global_position + Vector3.UP * 0.2, color, 7.0, 0.7)
			_aura = Vfx.boss_aura(color, 1.0)
			_aura.name = "AwakeningAura"
			player.add_child(_aura)
		var k := smoothstep(AWAKEN_BREAK, AWAKEN_TIME, t)
		_cam_base = Transform3D(Basis.IDENTITY, from.lerp(to, k)).looking_at(eyes - Vector3.UP * 0.12 * k, Vector3.UP)
		await get_tree().process_frame
		t += get_process_delta_time()


func _drop_insert() -> void:
	if is_instance_valid(_insert):
		_insert.queue_free()
	_insert = null


func _finish() -> void:
	mode._set_pattern(1.0, 1.0 if mode.awakened else 0.0, 0.0)
	if is_instance_valid(_aura):
		_aura.queue_free()
	CinematicKit.thaw(_frozen)
	player.input_enabled = true
	if is_instance_valid(_prev_camera):
		_prev_camera.current = true
	if is_instance_valid(_camera):
		_camera.queue_free()
	if is_instance_valid(_card):
		_card.queue_free()
	_drop_insert()
	_overlay.hide_bars()
	Music.duck(false)
	active = null
	finished.emit()
	await get_tree().create_timer(AFTER_IFRAMES).timeout
	if is_instance_valid(player):
		player.stats.is_invulnerable = false
	queue_free()


func _exit_tree() -> void:
	# Freed mid-shot (the area unloaded): don't leave the world waiting.
	if active == self:
		active = null
		CinematicKit.thaw(_frozen)
		Music.duck(false)
		if is_instance_valid(player):
			player.input_enabled = true
			player.stats.is_invulnerable = false


func frozen_count() -> int:
	return (_frozen.get("nodes", {}) as Dictionary).size()


func _forward() -> Vector3:
	var f := -player.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD
