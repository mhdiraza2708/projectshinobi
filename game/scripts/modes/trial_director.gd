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
## Nobody appears closer than this to the player: with their back to the
## arena's edge, the fan would be squeezed onto the player's lap, so it opens
## toward the middle instead.
const MIN_SPAWN_DISTANCE := 7.0
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
## Where the fight is (the open world fights anywhere): spawns stay within
## ARENA_RADIUS of it, standing on the ground there.
var center := Vector3.ZERO
var arena_radius := ARENA_RADIUS


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
	# A wave may mix natures (quest fights): one per enemy.
	var natures: Array = w.get("elements", [])
	for i in ranks.size():
		_spawn(ranks[i], natures[i] if i < natures.size() else w["element"], i, ranks.size())
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
	var flat := _inside_arena(p)
	var mine := Vector2(player.global_position.x, player.global_position.z)
	if flat.distance_to(mine) < MIN_SPAWN_DISTANCE:
		# Turn the fan around: from the player toward the arena's middle.
		var inward := Vector3(center.x - player.global_position.x, 0.0, center.z - player.global_position.z)
		inward = inward.normalized() if inward.length() > 0.5 else -look
		var turned := inward.rotated(Vector3.UP, angle)
		flat = _inside_arena(player.global_position + turned * SPAWN_DISTANCE)
	var at := Vector3(flat.x, center.y, flat.y)
	if is_inside_tree() and player.is_inside_tree():
		at.y = Combat.ground_height(player.get_world_3d(), at + Vector3.UP * 10.0, center.y)
	return at + Vector3.UP * 0.2


## `p` as a flat point, pulled back inside the arena.
func _inside_arena(p: Vector3) -> Vector2:
	var flat := Vector2(p.x - center.x, p.z - center.z)
	if flat.length() > arena_radius:
		flat = flat.normalized() * arena_radius
	return Vector2(center.x + flat.x, center.z + flat.y)


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
			e.stand_down()
	var record := Game.record_time(record_id, elapsed) if won and record_id != "" else false
	if won:
		SkillTrees.award("trial")
	if record:
		SkillTrees.award("trial_record")
	Sfx.play(&"victory" if won else &"defeat")
	finished.emit(won, elapsed, record)


