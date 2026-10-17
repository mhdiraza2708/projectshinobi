extends TestCase
## Life on the roads: ambushes, travellers to save, wandering duelists,
## pilgrims and supply caches, met in the wilds between the continent's places.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player
var world: OpenWorld
var enc: WorldEncounters
var _saved_layout: Variant


func before_each() -> void:
	Profile.persist = false
	Profile.reset()
	Game.reset_records()
	Quests.reload()
	Settings.persist = false
	_saved_layout = Settings.get_value(&"world_layout")
	Settings.set_value(&"world_layout", "continent")


func after_each() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
	Settings.set_value(&"world_layout", _saved_layout)
	Game.reset_records()
	Profile.reset()


func _load() -> void:
	Game.start_mode = Game.Mode.TITLE
	scene = Scene.instantiate()
	root.add_child(scene)
	await physics_frames(2)
	scene.instant_world = true
	await scene.start_world()
	world = scene.world
	player = scene.player
	enc = world.encounters
	await physics_frames(3)


func _stand_at(at: Vector3) -> void:
	await world._put_player_at(at)
	await physics_frames(3)


func _skip_dialogue() -> void:
	for i in 40:
		if not world.dialogue.is_open():
			return
		world.dialogue.advance()
		world.dialogue.advance()
		await physics_frames(1)


## A good place for an encounter, with a heading along which another lies.
func _wild() -> Dictionary:
	var cw := world.archipelago as ContinentWorld
	for gx in range(-12, 13):
		for gz in range(-12, 13):
			var at := cw.to_global(Vector3(gx * 150.0 + 40.0, 0.0, gz * 150.0 + 40.0))
			if not enc.good_spot(at):
				continue
			for a in 8:
				var heading := Vector3.FORWARD.rotated(Vector3.UP, TAU * a / 8.0)
				if enc.spot_ahead(at, heading) is Vector3:
					return {"at": enc.ground(at), "heading": heading}
	return {}


func _found_count() -> int:
	return world.sites.found_sites().size()


func test_encounters_keep_to_the_wilds() -> void:
	await _load()
	assert_true(enc != null, "the continent has life on its roads")
	var cw := world.archipelago as ContinentWorld
	assert_false(enc.good_spot(cw.to_global(cw.offset("autumn_wood"))), "not in a region")
	var camp: Dictionary = world.sites.plan.of_kind("camp")[0]
	assert_false(enc.good_spot(world.sites.position_of(camp["id"])), "not at a place")
	var w := _wild()
	assert_false(w.is_empty(), "there are wilds between")
	var ahead: Vector3 = enc.spot_ahead(w["at"], w["heading"])
	var d := Vector2(ahead.x - w["at"].x, ahead.z - w["at"].z).length()
	assert_true(d > WorldEncounters.AHEAD * 0.7 and d < WorldEncounters.AHEAD * 1.4, "a little way ahead (%.0f m)" % d)


func test_walking_the_wilds_puts_something_on_the_road_ahead_and_leaving_it_takes_it_away() -> void:
	await _load()
	var w := _wild()
	await _stand_at(w["at"])
	enc._next = 60.0
	enc._travelled = 0.0
	var heading: Vector3 = w["heading"]
	var pos: Vector3 = w["at"]
	for i in 30:
		if not enc.current.is_empty():
			break
		pos = enc.ground(pos + heading * 3.0)
		player.global_position = pos + Vector3.UP * 0.2
		await physics_frames(1)
	assert_false(enc.current.is_empty(), "something waits on the road")
	var at: Vector3 = enc.current["at"]
	assert_true((at - pos).dot(heading) > 20.0, "ahead of you, not behind")
	# Turn round and go: it does not follow.
	player.global_position = enc.ground(pos - heading * (WorldEncounters.GIVE_UP + 30.0)) + Vector3.UP * 0.2
	await physics_frames(2)
	assert_true(enc.current.is_empty(), "walk away and it goes")


func test_an_ambush_springs_as_you_pass_and_pays() -> void:
	await _load()
	var w := _wild()
	enc.begin("ambush", w["at"])
	var before := Game.xp()
	await _stand_at(enc.ground(w["at"] + Vector3(8, 0, 0)))
	assert_true(is_instance_valid(world._fight), "raiders spring out")
	assert_eq(world._fight_quest, WorldEncounters.PREFIX + "ambush")
	assert_eq(Music.current, &"camp")
	assert_eq(Quests.progress(world._fight_quest), 0, "no quest of the log")
	world._end_fight(true)
	assert_eq(Game.xp() - before, WorldEncounters.xp_for("ambush", world.story_tier()))
	assert_eq(enc.done_count("ambush"), 1)
	assert_true(enc.current.is_empty())


func test_an_ambushs_raiders_come_where_you_are_even_if_you_ran_on() -> void:
	await _load()
	var w := _wild()
	enc.begin("ambush", w["at"])
	await _stand_at(enc.ground(w["at"] + Vector3(8, 0, 0)))
	assert_true(is_instance_valid(world._fight), "it sprang")
	# Sprinting on before the raiders show (the film and the announce take a while).
	await _stand_at(enc.ground(w["at"] + Vector3(48, 0, 0)))
	await seconds(TrialDirector.ANNOUNCE_TIME + 0.3)
	var alive: Array = world._fight.alive
	assert_eq(alive.size(), 3, "three raiders")
	for e: EnemyShinobi in alive:
		var d := Vector2(e.global_position.x - player.global_position.x, e.global_position.z - player.global_position.z).length()
		assert_true(d < TrialDirector.SPAWN_DISTANCE + 4.0, "near you, not back where it began (%.0f m)" % d)
		assert_true(e.global_position.y > enc.ground(e.global_position).y - 0.3, "on the ground, not under it")
	world._end_fight(true)


func test_ambush_waves_grow_with_the_story() -> void:
	await _load()
	enc.current = {"region": "ashen_pass"}
	var early := enc.ambush_waves(1)
	assert_eq(early.size(), 1)
	for pair: Array in early[0]:
		assert_true(["fire", "lightning"].has(pair[1]), "an Ashen Pass nature")
	assert_eq(enc.ambush_waves(3).size(), 2, "a second wave later on")
	enc.current = {}


func test_a_rescued_traveller_tells_you_of_a_place() -> void:
	await _load()
	var w := _wild()
	enc.begin("rescue", w["at"])
	var t: EnemyShinobi = enc.current["traveller"]
	assert_true(t.is_ally(), "the traveller is on your side")
	for e: EnemyShinobi in enc.current["raiders"]:
		assert_true(e.hold, "the raiders wait for you")
		assert_eq(e.target, t, "and are after the traveller")
	var found := _found_count()
	var before := Game.xp()
	await _stand_at(enc.ground(w["at"] + Vector3(20, 0, 0)))
	assert_true(world.busy, "the fight is on")
	for e: EnemyShinobi in enc.current["raiders"]:
		assert_false(e.hold)
		e.dismiss()
	await physics_frames(3)
	assert_eq(_found_count(), found + 1, "the traveller marks a place on your map")
	assert_eq(Game.xp() - before, WorldEncounters.xp_for("rescue", world.story_tier()))
	assert_false(world.busy)
	assert_true(enc.current.is_empty())


func test_a_traveller_who_falls_pays_nothing() -> void:
	await _load()
	var w := _wild()
	enc.begin("rescue", w["at"])
	var found := _found_count()
	var before := Game.xp()
	await _stand_at(enc.ground(w["at"] + Vector3(20, 0, 0)))
	(enc.current["traveller"] as EnemyShinobi).dismiss()
	await physics_frames(2)
	for e: EnemyShinobi in enc.current["raiders"]:
		e.dismiss()
	await physics_frames(3)
	assert_eq(_found_count(), found)
	assert_eq(Game.xp(), before)
	assert_eq(enc.done_count("rescue"), 0)
	assert_false(world.busy, "the road is yours again")


func test_a_wandering_duelist_bars_the_road() -> void:
	await _load()
	var w := _wild()
	enc.begin("duelist", w["at"])
	var b: Dictionary = enc.current["bounty"]
	assert_true(WorldEncounters.DUELISTS.any(func(d: Array) -> bool: return d[1] == b["name"]))
	var before := Game.xp()
	await _stand_at(enc.ground(w["at"] + Vector3(12, 0, 0)))
	assert_true(world.dialogue.is_open(), "they speak first")
	await _skip_dialogue()
	await physics_frames(3)
	assert_true(is_instance_valid(world._duelist), "then the duel")
	assert_eq(world._duelist.title_override, b["name"])
	assert_eq(Music.current, &"duel")
	world._duelist.defeated.emit(world._duelist)
	assert_eq(enc.done_count("duelist"), 1)
	assert_eq(Game.xp() - before, WorldEncounters.xp_for("duelist", world.story_tier()))


func test_a_pilgrim_knows_of_a_place() -> void:
	await _load()
	var w := _wild()
	enc.begin("pilgrim", w["at"])
	var found := _found_count()
	await _stand_at(enc.ground(w["at"] + Vector3(1.5, 0, 0)))
	assert_eq(world._interact.get("kind", ""), "encounter", "you can speak to them")
	enc.use("pilgrim")
	assert_eq(_found_count(), found + 1, "and they mark a place on your map")
	assert_eq(enc.done_count("pilgrim"), 1)


func test_a_cache_binds_your_wounds() -> void:
	await _load()
	var w := _wild()
	enc.begin("cache", w["at"])
	player.stats.health = 10.0
	player.stats.chakra = 0.0
	await _stand_at(w["at"])
	assert_eq(player.stats.health, player.stats.max_health)
	assert_eq(player.stats.chakra, player.stats.max_chakra)
	assert_eq(enc.done_count("cache"), 1)


func test_nothing_waits_on_the_road_during_a_chapter() -> void:
	await _load()
	var w := _wild()
	enc.begin("pilgrim", w["at"])
	var mode: int = scene.mode
	scene.mode = Game.Mode.STORY
	await physics_frames(2)
	assert_true(enc.current.is_empty(), "a chapter clears the road")
	scene.mode = mode


func test_going_down_in_a_rescue_gives_the_road_back() -> void:
	await _load()
	var w := _wild()
	enc.begin("rescue", w["at"])
	var raiders: Array = enc.current["raiders"]
	await _stand_at(enc.ground(w["at"] + Vector3(20, 0, 0)))
	assert_true(world.busy)
	player.defeated.emit()
	await physics_frames(2)
	assert_true(enc.current.is_empty(), "the encounter ends")
	assert_false(world.busy, "and free roam is not stuck")
	for e: Variant in raiders:
		assert_true(not is_instance_valid(e) or (e as EnemyShinobi).is_defeated(), "its raiders go")


func test_losing_an_ambush_ends_it() -> void:
	await _load()
	var w := _wild()
	enc.begin("ambush", w["at"])
	await _stand_at(enc.ground(w["at"] + Vector3(8, 0, 0)))
	assert_true(is_instance_valid(world._fight))
	player.defeated.emit()
	await physics_frames(2)
	assert_true(enc.current.is_empty())
	assert_false(is_instance_valid(world._fight) and not world._fight.is_queued_for_deletion(), "the fight is gone")
	assert_eq(enc.done_count("ambush"), 0)


func test_travelling_away_leaves_a_waiting_encounter_behind() -> void:
	await _load()
	var w := _wild()
	await _stand_at(enc.ground(w["at"] + Vector3(40, 0, 0)))
	enc.begin("pilgrim", w["at"])
	assert_true(await world.fast_travel("emberwood"))
	await physics_frames(3)
	assert_true(enc.current.is_empty(), "it does not wait for you across the map")
