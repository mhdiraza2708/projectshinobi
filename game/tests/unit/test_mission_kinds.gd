extends TestCase
## The newer mission kinds: escort, search, duels to the old rules (blades
## only) and crowds that yield instead of falling.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player
var director: StoryDirector


func before_each() -> void:
	seed(21)


func _load() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	await physics_frames(3)
	scene.start_story("ch7_wood", true)
	await physics_frames(2)
	director = scene.story_director
	# Stop the chapter that started on its own; the test plays its own beats.
	director.running = false
	scene.dialogue.visible = false


## Runs `beats` (raw JSON dictionaries) as a chapter of their own, followed by
## a long wait so the chapter never finishes under the test.
func _play(beats: Array) -> void:
	var parser := Story.new()
	parser.characters = director.story.characters
	var present := {}
	var parsed: Array = []
	for i in beats.size():
		var b := parser._parse_beat("test beat %d" % i, beats[i], present)
		assert_true(parser.errors.is_empty(), "\n".join(parser.errors))
		parsed.append(b)
	parsed.append(parser._parse_beat("test wait", {"do": "wait", "seconds": 600}, present))
	director.chapter = {"id": "test_kinds", "number": 1, "part": 1, "island": "",
		"player_at": Vector2(0, 6), "beats": parsed}
	director._films_seen[0] = true
	director.running = true
	director.beat_index = -1
	player.global_position = Vector3(0, 0.1, 6)
	director._next()
	await physics_frames(2)


## Physics and idle frames both (the director ticks in _process).
func _frames(n: int) -> void:
	for i in n:
		await root.get_tree().physics_frame
		await root.get_tree().process_frame


func _errors_of(raw: Dictionary) -> Array[String]:
	var parser := Story.new()
	parser.characters = Story.load_all().characters
	parser._parse_beat("t", raw, {})
	return parser.errors


# --- The format --------------------------------------------------------------------

func test_the_new_beats_parse_and_mistakes_are_caught() -> void:
	assert_eq(_errors_of({"do": "escort", "who": "hisame", "to": [0, -2]}).size(), 0)
	assert_eq(_errors_of({"do": "search", "text": "Find them", "spots": [[10, 4], [-8, 12]]}).size(), 0)
	assert_eq(_errors_of({"do": "boss", "who": "kagerou", "rank": "jonin", "health": 100, "rules": "blades"}).size(), 0)
	assert_eq(_errors_of({"do": "fight", "waves": [{"element": "fire", "enemies": ["genin"]}], "nonlethal": true}).size(), 0)
	assert_eq(_errors_of({"do": "survive", "seconds": 10, "enemies": [["genin", "fire"]], "nonlethal": true}).size(), 0)
	assert_true(_errors_of({"do": "escort", "who": "hisame"}).size() > 0, "an escort needs somewhere to go")
	assert_true(_errors_of({"do": "escort", "who": "hisame", "to": [0, 0], "health": 0}).size() > 0, "and health")
	assert_true(_errors_of({"do": "search", "text": "x", "spots": []}).size() > 0, "a search needs places")
	assert_true(_errors_of({"do": "search", "text": "x", "spots": [[1, 2]], "radius": 0}).size() > 0)
	assert_true(_errors_of({"do": "boss", "who": "kagerou", "rank": "jonin", "health": 100, "rules": "fists"}).size() > 0,
		"unknown duel rules are an error")


# --- Non-lethal crowds ---------------------------------------------------------------

func test_health_can_have_a_floor() -> void:
	var stats := Stats.new()
	stats.max_health = 50.0
	stats.min_health = 1.0
	root.add_child(stats)
	await physics_frames(1)
	stats.take_damage(500.0, Element.NONE)
	assert_false(stats.is_dead(), "with a floor, nothing is lethal")
	assert_eq(stats.health, 1.0)
	stats.queue_free()


func test_a_nonlethal_fighter_yields_instead_of_falling() -> void:
	await _load()
	var crowd := EnemyShinobi.new()
	crowd.nonlethal = true
	crowd.target = player
	crowd.position = player.global_position + Vector3(0, 0, -6)
	scene.add_child(crowd)
	await physics_frames(ceili(EnemyShinobi.SPAWN_TIME * 60.0) + 5)
	var beaten := [0]
	crowd.defeated.connect(func(_x: EnemyShinobi) -> void: beaten[0] += 1)
	crowd.stats.take_damage(100000.0, Element.NONE)
	await physics_frames(2)
	assert_false(crowd.stats.is_dead(), "no blow can kill a crowd that yields")
	await seconds(1.5)
	assert_eq(beaten[0], 1, "it gave up, and counts as beaten")
	assert_false(is_instance_valid(crowd) and not crowd.is_queued_for_deletion(), "and went")


func test_a_story_fight_can_be_nonlethal() -> void:
	await _load()
	director._films_seen[0] = true
	await _play([{"do": "fight", "text": "Hold the stairs", "nonlethal": true,
		"waves": [{"element": "fire", "enemies": ["genin", "genin"]}]}])
	await seconds(TrialDirector.ANNOUNCE_TIME + 1.0)
	assert_true(director.fight != null and director.fight.nonlethal, "the trial director was told")
	var foes := director.fight.alive
	assert_eq(foes.size(), 2)
	for e in foes:
		assert_true(e.nonlethal, "every one of the crowd yields")


# --- Duels to the old rules -----------------------------------------------------------

func test_blades_only_stops_every_jutsu_but_the_kunai() -> void:
	await _load()
	var kunai: JutsuDefinition = player._kunai
	var other: JutsuDefinition = null
	for j in JutsuRegistry.all():
		if j.id != &"kunai":
			other = j
			break
	assert_true(kunai != null and other != null)
	player.stats.chakra = player.stats.max_chakra
	assert_true(player.caster.block_reason(other) != &"rules")
	player.caster.blades_only = true
	assert_eq(player.caster.block_reason(other), &"rules", "no jutsu in a blades-only duel")
	assert_true(player.caster.block_reason(kunai) != &"rules", "the kunai is a blade")
	player.ult_charge = Ultimates.MAX_CHARGE
	assert_false(player.try_ultimate(), "and no ultimate")
	player.caster.blades_only = false


func test_a_blades_duel_binds_both_fighters_and_ends_with_the_boss() -> void:
	await _load()
	await _play([{"do": "boss", "who": "kagerou", "rank": "chunin", "health": 80, "rules": "blades",
		"specials": []}])
	await physics_frames(2)
	assert_true(player.caster.blades_only, "you are bound")
	assert_true(director.boss != null and director.boss.blades_only, "so is the boss")
	assert_true(director.boss._pick_jutsu(8.0) == null, "who therefore reaches for no jutsu")
	director.boss.stats.take_damage(100000.0, Element.NONE)
	await physics_frames(3)
	assert_false(player.caster.blades_only, "when the boss falls you have your jutsu back")


# --- Escort -------------------------------------------------------------------------

func test_an_escorted_ally_walks_to_the_goal_and_waits_for_you() -> void:
	await _load()
	await _play([{"do": "escort", "who": "hisame", "from": [0, -6], "to": [0, -1], "text": "Walk her home"}])
	var e := director.escortee
	assert_true(e != null and e.is_ally(), "she is on your side")
	assert_true(e.escort_to is Vector3)
	# You stay put: she walks to the goal and the beat completes.
	var end := Time.get_ticks_msec() + 20000
	while director.beat_index == 0 and Time.get_ticks_msec() < end:
		await physics_frames(5)
	assert_eq(director.beat_index, 1, "arriving ends the beat")
	assert_true(director.npcs.has("hisame"), "and she stands there, ready to talk")
	assert_true(director.escortee == null)


func test_an_escort_waits_while_the_player_falls_behind() -> void:
	await _load()
	await _play([{"do": "escort", "who": "hisame", "from": [0, -6], "to": [0, -30], "text": "Walk her home"}])
	var e := director.escortee
	await physics_frames(ceili(EnemyShinobi.SPAWN_TIME * 60.0) + 5)
	# The player is far behind: she holds still.
	player.global_position = Vector3(0, 0.1, 40)
	await physics_frames(10)
	var held := e.global_position
	await physics_frames(60)
	assert_true(e.global_position.distance_to(held) < 0.6, "she waits for you")
	player.global_position = Vector3(0, 0.1, -6)
	await physics_frames(60)
	assert_true(e.global_position.distance_to(held) > 1.0, "and walks on once you are close")


func test_enemies_go_for_the_escorted_ally_first() -> void:
	await _load()
	await _play([{"do": "escort", "who": "hisame", "from": [0, -6], "to": [0, -30], "text": "Walk her home",
		"enemies": [["genin", "fire"]], "max_alive": 2}])
	director._escort_timer = 0.0
	await physics_frames(10)
	var attackers := scene.find_children("*", "EnemyShinobi", true, false).filter(
		func(n: EnemyShinobi) -> bool: return not n.is_ally())
	assert_true(attackers.size() > 0, "attackers came")
	assert_eq((attackers[0] as EnemyShinobi).target, director.escortee, "for her")


func test_losing_the_escorted_ally_loses_the_fight() -> void:
	await _load()
	var lost := [false]
	director.fight_lost.connect(func() -> void: lost[0] = true)
	await _play([{"do": "escort", "who": "hisame", "from": [0, -6], "to": [0, -30], "text": "Walk her home"}])
	await physics_frames(ceili(EnemyShinobi.SPAWN_TIME * 60.0) + 5)
	director.escortee.stats.take_damage(100000.0, Element.NONE)
	await physics_frames(5)
	assert_true(lost[0], "if she falls, you retry the beat")
	director.retry()
	await physics_frames(3)
	assert_true(director.escortee != null and not director.escortee.is_defeated(), "and she is back, whole")


# --- Search -------------------------------------------------------------------------

func test_a_search_is_won_by_walking_to_every_place() -> void:
	await _load()
	await _play([{"do": "search", "text": "Find the cairns", "spots": [[14, 0], [-14, 0]], "radius": 3.0}])
	await _frames(3)
	assert_eq(director._search_found.count(true), 0)
	player.global_position = Vector3(14, 0.1, 0)
	await _frames(3)
	assert_eq(director._search_found.count(true), 1, "standing on one finds it")
	assert_eq(director.beat_index, 0, "and the search goes on")
	player.global_position = Vector3(-14, 0.1, 0)
	await _frames(4)
	assert_eq(director.beat_index, 1, "finding the last one ends it")


func test_each_find_can_spring_an_ambush_that_must_be_beaten() -> void:
	await _load()
	await _play([{"do": "search", "text": "Find the cairns", "spots": [[14, 0]], "radius": 3.0,
		"enemies": [["genin", "fire"], ["genin", "wind"]]}])
	player.global_position = Vector3(14, 0.1, 0)
	await _frames(4)
	assert_eq(director._search_ambush.size(), 2, "the place was guarded")
	assert_eq(director.beat_index, 0, "so it isn't over yet")
	for e in director._search_ambush.duplicate():
		e.dismiss()
	await _frames(5)
	assert_eq(director.beat_index, 1, "until they are beaten")
