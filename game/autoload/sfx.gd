extends Node
## Sound effects. Autoloaded as `Sfx`.
##
## Sounds are the WAVs in res://assets/audio/sfx, made by
## art/audio/make_sfx.py, and are played by file name without the extension:
##   Sfx.play(&"ui_select")                 # flat, for UI
##   Sfx.play_at(&"impact", hit_position)   # positional, for the world
##   Sfx.start_loop(&"charge", &"charge_loop") / Sfx.stop_loop(&"charge")
## Volumes come from Settings (master/sfx/ui).

## Emitted for every sound that actually starts (tests, debugging).
signal played(sound: StringName)

const DIR := "res://assets/audio/sfx/"
const BUS_SFX := &"SFX"
const BUS_UI := &"UI"
const POOL_2D := 12
const POOL_3D := 24
## The same sound retriggered faster than this is dropped, so a volley of
## hits landing together doesn't stack into one loud spike.
const MIN_REPEAT_MSEC := 35
## Focus moves this soon after another UI sound stay silent (a menu opening
## grabs focus, which shouldn't also tick).
const UI_MOVE_QUIET_MSEC := 120
const VOLUME_KEYS := {&"master_volume": &"Master", &"sfx_volume": BUS_SFX, &"ui_volume": BUS_UI}

## The last sounds played, newest last (for tests).
var history: Array[StringName] = []

var _streams: Dictionary = {}
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _loops: Dictionary = {}
var _last_msec: Dictionary = {}
var _last_ui_msec := -100000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for file in ResourceLoader.list_directory(DIR):
		if file.get_extension() == "wav":
			_streams[StringName(file.get_basename())] = load(DIR + file)
	for bus: StringName in [BUS_SFX, BUS_UI]:
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
	return _streams.has(sound)


func sounds() -> Array:
	return _streams.keys()


## Plays a non-positional sound on `bus` (UI sounds, the player's own feedback).
func play(sound: StringName, volume_db := 0.0, pitch_var := 0.04, bus := BUS_SFX) -> void:
	if not _accept(sound):
		return
	var p := _free_player(_pool_2d) as AudioStreamPlayer
	p.stream = _streams[sound]
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()
	_record(sound)


## Plays a sound from a point in the world.
func play_at(sound: StringName, position: Vector3, volume_db := 0.0, pitch_var := 0.06) -> void:
	if not _accept(sound):
		return
	var p := _free_player(_pool_3d) as AudioStreamPlayer3D
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.global_position = position
	p.play()
	_record(sound)


## UI sound on the UI bus. Plays while the game is paused.
func ui(sound: StringName, volume_db := 0.0) -> void:
	_last_ui_msec = Time.get_ticks_msec()
	play(sound, volume_db, 0.02, BUS_UI)


## Starts a looping sound under `key` (fades in). Restarting a running key is
## a no-op.
func start_loop(key: StringName, sound: StringName, volume_db := 0.0) -> void:
	if _loops.has(key) or not _accept(sound):
		return
	var p := AudioStreamPlayer.new()
	p.process_mode = Node.PROCESS_MODE_PAUSABLE
	p.stream = _streams[sound]
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
	if not _streams.has(sound):
		push_warning("Sfx: no sound named '%s' in %s" % [sound, DIR])
		return false
	var now := Time.get_ticks_msec()
	if now - int(_last_msec.get(sound, -100000)) < MIN_REPEAT_MSEC:
		return false
	_last_msec[sound] = now
	return true


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
	if history.size() > 64:
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
	if b and not b.pressed.is_connected(_on_button_pressed):
		b.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	ui(&"ui_select")


func _on_focus_changed(control: Control) -> void:
	if control == null or not control.is_visible_in_tree():
		return
	if Time.get_ticks_msec() - _last_ui_msec < UI_MOVE_QUIET_MSEC:
		return
	ui(&"ui_move", -4.0)
