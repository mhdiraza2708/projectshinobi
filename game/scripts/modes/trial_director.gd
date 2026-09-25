class_name TrialDirector
extends Node
## Trial of the Five Natures: five waves of chakra clones, one nature per
## wave. Clear them all to finish; your time is recorded. Each wave's
## weakness is the nature that beats it (see Element.BEATS).

signal wave_started(index: int, total: int, element: int)
signal enemies_left_changed(count: int)
signal finished(won: bool, seconds: float, new_record: bool)

const TRIAL_ID := "five_natures"
const WAVES := [
	{"element": Element.FIRE, "enemies": [&"genin"]},
	{"element": Element.WIND, "enemies": [&"genin", &"genin"]},
	{"element": Element.LIGHTNING, "enemies": [&"chunin", &"genin"]},
	{"element": Element.EARTH, "enemies": [&"chunin", &"chunin"]},
	{"element": Element.WATER, "enemies": [&"jonin", &"genin"]},
]
## Seconds between a wave's announcement and its enemies appearing.
const ANNOUNCE_TIME := 1.4
## Seconds of rest after a wave is cleared.
const BREATHER := 2.5
## Share of max health restored between waves.
const BREATHER_HEAL := 0.35
const SPAWN_DISTANCE := 11.0
const ARENA_RADIUS := 19.0

var player: Player
## The waves to run (tests and story fights use their own lists).
var waves: Array = WAVES
## Where the completion time is recorded ("" = not recorded).
var record_id := TRIAL_ID
## Announce each wave with its sound (story fights do their own intro).
var announce := true
var wave := -1
var elapsed := 0.0
var running := false
var alive: Array[EnemyShinobi] = []
## Waves fully cleared so far.
var waves_cleared := 0


func start(p: Player) -> void:
	player = p
	wave = -1
	waves_cleared = 0
	elapsed = 0.0
	running = true
	if not player.defeated.is_connected(_on_player_defeated):
		player.defeated.connect(_on_player_defeated)
	_next_wave()


func _process(delta: float) -> void:
	if running:
		elapsed += delta


func current_element() -> int:
	return waves[wave]["element"] if wave >= 0 and wave < waves.size() else Element.NONE


func _next_wave() -> void:
	wave += 1
	if wave >= waves.size():
		_finish(true)
		return
	var w: Dictionary = waves[wave]
	wave_started.emit(wave, waves.size(), w["element"])
	if announce:
		Sfx.play(&"wave_start")
	await get_tree().create_timer(ANNOUNCE_TIME, false).timeout
	if not running or not is_inside_tree():
		return
	var ranks: Array = w["enemies"]
	for i in ranks.size():
		_spawn(ranks[i], w["element"], i, ranks.size())
	enemies_left_changed.emit(alive.size())


func _spawn(rank: StringName, element: int, index: int, count: int) -> EnemyShinobi:
	var e := EnemyShinobi.new()
	e.rank = rank
	e.element = element
	e.target = player
	e.position = spawn_point(index, count)
	e.rotation.y = atan2(-(player.global_position.x - e.position.x), -(player.global_position.z - e.position.z))
	e.defeated.connect(_on_enemy_defeated)
	alive.append(e)
	get_parent().add_child(e)
	return e


## Where the index-th of `count` enemies appears: in front of the camera, in
## a fan around the player, kept inside the arena.
func spawn_point(index: int, count: int) -> Vector3:
	var look := player.camera_rig.flat_forward() if player.camera_rig else Vector3.FORWARD
	var spread := deg_to_rad(40.0)
	var angle := (index - (count - 1) * 0.5) * spread
	var p := player.global_position + look.rotated(Vector3.UP, angle) * SPAWN_DISTANCE
	p.y = 0.0
	var flat := Vector2(p.x, p.z)
	if flat.length() > ARENA_RADIUS:
		flat = flat.normalized() * ARENA_RADIUS
	return Vector3(flat.x, 0.2, flat.y)


func _on_enemy_defeated(e: EnemyShinobi) -> void:
	alive.erase(e)
	enemies_left_changed.emit(alive.size())
	if not alive.is_empty() or not running:
		return
	waves_cleared += 1
	if wave < waves.size() - 1:
		player.stats.heal(player.stats.max_health * BREATHER_HEAL)
		player.stats.chakra = maxf(player.stats.chakra, player.stats.max_chakra * 0.6)
		player.stats.chakra_changed.emit(player.stats.chakra, player.stats.max_chakra)
		await get_tree().create_timer(BREATHER, false).timeout
		if running and is_inside_tree():
			_next_wave()
	else:
		_next_wave()


func _on_player_defeated() -> void:
	if running:
		_finish(false)


func _finish(won: bool) -> void:
	running = false
	for e in alive:
		if is_instance_valid(e):
			e.target = null
	var record := Game.record_time(record_id, elapsed) if won and record_id != "" else false
	Sfx.play(&"victory" if won else &"defeat")
	finished.emit(won, elapsed, record)


