extends Node
## Sound effects. Autoloaded as `Sfx`.
##
## Sounds are the WAVs in res://assets/audio/sfx, made by
## art/audio/make_sfx.py, and are played by file name without the extension:
##   Sfx.play(&"ui_select")                 # flat, for UI
##   Sfx.play_at(&"impact", hit_position)   # positional, for the world
##   Sfx.footstep(&"grass", foot_position)  # a step on a kind of ground
##   Sfx.start_loop(&"charge", &"charge_loop") / Sfx.stop_loop(&"charge")
## A sound with several takes (strike_hit_v1.wav, strike_hit_v2.wav...) is
## played by its plain name (&"strike_hit"); a different take is picked each
## time, so frequent sounds don't repeat themselves.
##
## The files are mastered to a mix (see LEVELS in make_sfx.py): at 0 dB they
## sit where they belong, so game code only ever turns a sound down.
## Volumes come from Settings (master/sfx/ui/music/voice). Sfx also makes the
## Music and Voice buses that the Music and Voice autoloads play on, and puts
## a limiter on the master bus so a pile-up of blasts can't clip.

## Emitted for every sound that actually starts (tests, debugging).
signal played(sound: StringName)

const DIR := "res://assets/audio/sfx/"
const BUS_SFX := &"SFX"
const BUS_UI := &"UI"
const BUS_MUSIC := &"Music"
const BUS_VOICE := &"Voice"
const POOL_2D := 12
const POOL_3D := 24
## The same sound retriggered faster than this is dropped, so a volley of
## hits landing together doesn't stack into one loud spike.
const MIN_REPEAT_MSEC := 35
## Focus moves this soon after another UI sound stay silent (a menu opening
## grabs focus, which shouldn't also tick).
const UI_MOVE_QUIET_MSEC := 120
## How many sounds `history` remembers.
const HISTORY_LIMIT := 160
## The ground a footstep can be on (a sound step_<surface> exists for each).
const SURFACES: Array[StringName] = [&"dirt", &"grass", &"stone", &"sand", &"snow", &"water"]
## A file name ending in this is one take of a sound (name_v1.wav, name_v2.wav).
const TAKE_PATTERN := r"^(.+)_v\d+$"
## Nothing louder than this leaves the master bus.
const LIMITER_CEILING_DB := -0.5
const VOLUME_KEYS := {&"master_volume": &"Master", &"sfx_volume": BUS_SFX, &"ui_volume": BUS_UI,
	&"music_volume": BUS_MUSIC, &"voice_volume": BUS_VOICE}

## The last sounds played, newest last (for tests).
var history: Array[StringName] = []

var _streams: Dictionary = {}
## Sounds with several takes: name -> Array of AudioStream.
var _takes: Dictionary = {}
var _last_take: Dictionary = {}
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _loops: Dictionary = {}
var _last_msec: Dictionary = {}
var _last_ui_msec := -100000
## Sounds in the world stay silent while this is on (VfxWarmup setting off
## effects out of sight).
var world_muted := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var take_name := RegEx.create_from_string(TAKE_PATTERN)
	for file in ResourceLoader.list_directory(DIR):
		if file.get_extension() != "wav":
			continue
		var found := take_name.search(file.get_basename())
		if found:
			var base := StringName(found.get_string(1))
			if not _takes.has(base):
				_takes[base] = []
			(_takes[base] as Array).append(load(DIR + file))
		else:
			_streams[StringName(file.get_basename())] = load(DIR + file)
	_add_limiter()
	for bus: StringName in [BUS_SFX, BUS_UI, BUS_MUSIC, BUS_VOICE]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, &"Master")

	# UI sounds keep playing while paused; world sounds pause with the game.
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool_2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.process_mode = Node.PROCESS_MODE_PAUSABLE
		p.bus = BUS_SFX
		p.unit_size = 9.0
		p.max_distance = 70.0
		p.attenuation_filter_cutoff_hz = 9000.0
		add_child(p)
		_pool_3d.append(p)

	for key: StringName in VOLUME_KEYS:
		_apply_volume(key)
	Settings.value_changed.connect(func(key: StringName, _v: Variant) -> void:
		if VOLUME_KEYS.has(key):
			_apply_volume(key))
	get_tree().node_added.connect(_on_node_added)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


func has_sound(sound: StringName) -> bool:
	return _streams.has(sound) or _takes.has(sound)


## Every sound name (a sound with several takes counts once).
func sounds() -> Array:
	return _streams.keys() + _takes.keys()


## How many takes `sound` has (1 for a plain file, 0 if there is none).
func take_count(sound: StringName) -> int:
	if _takes.has(sound):
		return (_takes[sound] as Array).size()
	return 1 if _streams.has(sound) else 0


## Plays a non-positional sound on `bus` (UI sounds, the player's own feedback).
func play(sound: StringName, volume_db := 0.0, pitch_var := 0.04, bus := BUS_SFX) -> void:
	if not _accept(sound):
		return
	var p := _free_player(_pool_2d) as AudioStreamPlayer
	p.stream = _stream_for(sound)
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()
	_record(sound)


## Plays a sound from a point in the world.
func play_at(sound: StringName, position: Vector3, volume_db := 0.0, pitch_var := 0.06) -> void:
	if world_muted or not _accept(sound):
		return
	var p := _free_player(_pool_3d) as AudioStreamPlayer3D
	p.stream = _stream_for(sound)
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.global_position = position
	p.play()
	_record(sound)


## A footstep on `surface` (one of SURFACES; anything else is dirt).
func footstep(surface: StringName, position: Vector3, volume_db := 0.0) -> void:
	var sound := StringName("step_" + surface)
	play_at(sound if has_sound(sound) else &"step_dirt", position, volume_db, 0.08)


## UI sound on the UI bus. Plays while the game is paused.
func ui(sound: StringName, volume_db := 0.0) -> void:
	_last_ui_msec = Time.get_ticks_msec()
	play(sound, volume_db, 0.02, BUS_UI)


## Starts a looping sound under `key` (fades in). Restarting a running key is
## a no-op.
func start_loop(key: StringName, sound: StringName, volume_db := 0.0) -> void:
	# Loops skip the instant-retrigger guard: switching loops quickly is fine.
	if _loops.has(key):
		return
	if not has_sound(sound):
		push_warning("Sfx: no sound named '%s' in %s" % [sound, DIR])
		return
	var p := AudioStreamPlayer.new()
	p.process_mode = Node.PROCESS_MODE_PAUSABLE
	p.stream = _stream_for(sound)
	p.bus = BUS_SFX
	p.volume_db = -30.0
	add_child(p)
	p.play()
	p.create_tween().tween_property(p, "volume_db", volume_db, 0.2)
	_loops[key] = p
	_record(sound)


func stop_loop(key: StringName) -> void:
	var p: AudioStreamPlayer = _loops.get(key)
	if p == null:
		return
	_loops.erase(key)
	var tw := p.create_tween()
	tw.tween_property(p, "volume_db", -40.0, 0.15)
	tw.tween_callback(p.queue_free)


func is_looping(key: StringName) -> bool:
	return _loops.has(key)


func stop_all_loops() -> void:
	for key: StringName in _loops.keys():
		stop_loop(key)


func _accept(sound: StringName) -> bool:
	if not has_sound(sound):
		push_warning("Sfx: no sound named '%s' in %s" % [sound, DIR])
		return false
	var now := Time.get_ticks_msec()
	if now - int(_last_msec.get(sound, -100000)) < MIN_REPEAT_MSEC:
		return false
	_last_msec[sound] = now
	return true


## The stream to play for `sound`: its file, or a random take other than the
## one played last.
func _stream_for(sound: StringName) -> AudioStream:
	if not _takes.has(sound):
		return _streams[sound]
	var takes: Array = _takes[sound]
	var pick := randi() % takes.size()
	if takes.size() > 1 and pick == int(_last_take.get(sound, -1)):
		pick = (pick + 1 + randi() % (takes.size() - 1)) % takes.size()
	_last_take[sound] = pick
	return takes[pick]


## A limiter on the master bus (once), so overlapping blasts can't clip.
func _add_limiter() -> void:
	var master := AudioServer.get_bus_index(&"Master")
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			return
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = LIMITER_CEILING_DB
	limiter.release = 0.1
	AudioServer.add_bus_effect(master, limiter)


## A free player from `pool`, or the one that has played longest.
func _free_player(pool: Array) -> Node:
	var oldest: Node = pool[0]
	var oldest_pos := -1.0
	for p: Node in pool:
		if not p.playing:
			return p
		var pos: float = p.get_playback_position()
		if pos > oldest_pos:
			oldest_pos = pos
			oldest = p
	return oldest


func _record(sound: StringName) -> void:
	history.append(sound)
	if history.size() > HISTORY_LIMIT:
		history.remove_at(0)
	played.emit(sound)


func _apply_volume(key: StringName) -> void:
	var idx := AudioServer.get_bus_index(VOLUME_KEYS[key])
	if idx < 0:
		return
	var v := clampf(float(Settings.get_value(key)), 0.0, 1.0)
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))


# --- Automatic UI sounds -------------------------------------------------------

func _on_node_added(node: Node) -> void:
	var b := node as BaseButton
	if b and not b.has_meta(&"sfx_hooked"):
		b.set_meta(&"sfx_hooked", true)
		b.pressed.connect(_on_button_pressed.bind(b))


## A button clicks (ui_select) unless its "sfx" meta names another sound
## (tabs set &"ui_tab"), or is &"" for none.
func _on_button_pressed(button: BaseButton) -> void:
	var sound: StringName = &"ui_select"
	if is_instance_valid(button):
		sound = button.get_meta(&"sfx", &"ui_select")
	if sound != &"":
		ui(sound)


func _on_focus_changed(control: Control) -> void:
	if control == null or not control.is_visible_in_tree():
		return
	if Time.get_ticks_msec() - _last_ui_msec < UI_MOVE_QUIET_MSEC:
		return
	ui(&"ui_move", -2.0)
