extends TestCase
## What there is to do at the continent's places of interest: raiders at a
## camp, a shrine to attune, a relic among ruins, a board with contracts.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player
var world: OpenWorld
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
	await physics_frames(3)


## Stands the player at a world position and lets the world notice.
func _stand_at(at: Vector3) -> void:
	await world._put_player_at(at)
	world.sites.update()
	await physics_frames(3)


func _skip_dialogue() -> void:
	for i in 40:
		if not world.dialogue.is_open():
			return
		world.dialogue.advance()
		world.dialogue.advance()
		await physics_frames(1)


func _first(kind: String) -> Dictionary:
	return world.sites.plan.of_kind(kind)[0]


func test_camp_waves_follow_danger_and_the_story_tier() -> void:
	var site := {"seed": 7, "region": "ashen_pass", "danger": 0}
	var calm := SiteActivities.camp_waves(site, 1)
	assert_eq(calm.size(), 2)
	assert_eq((calm[0] as Array).size(), 3)
	for pair: Array in calm[0]:
		assert_eq(pair[0], "genin")
		assert_true(["fire", "lightning"].has(pair[1]), "an Ashen Pass nature")
	site["danger"] = 2
	assert_true(SiteActivities.camp_waves(site, 1)[0].all(func(p: Array) -> bool: return p[0] == "chunin"), "danger 2 starts with chunin")
	assert_eq(SiteActivities.camp_waves(site, 1), SiteActivities.camp_waves(site, 1), "the same every time")
	assert_true(SiteActivities.camp_waves(site, 3).size() > SiteActivities.camp_waves(site, 1).size(), "a late-story camp has more waves")
	assert_true(SiteActivities.camp_waves(site, 5).size() > SiteActivities.camp_waves(site, 3).size())
	assert_true(SiteActivities.camp_xp(site, 4) > SiteActivities.camp_xp({"danger": 0}, 1), "harder camps pay more")


func test_a_camp_fights_you_when_you_come_to_its_fire_and_is_cleared_for_good() -> void:
	await _load()
	var camp := _first("camp")
	var node := world.sites.build_site(camp["id"])
	var xp_before := Game.xp()
	await _stand_at(node.spot("fire") + Vector3(8, 0, 0))
	assert_true(is_instance_valid(world._fight), "the fire draws the raiders out")
	assert_eq(world._fight_quest, SiteActivities.PREFIX + camp["id"])
	assert_true(world.busy)
	assert_eq(Quests.progress(world._fight_quest), 0, "a camp is no quest of the log")
	# Winning clears it.
	world._end_fight(true)
	assert_eq(world.sites.state(camp["id"]), WorldSites.DONE)
	assert_true(Game.xp() > xp_before, "and pays")
	# A cleared camp does not fight again.
	world.busy = false
	await _stand_at(node.spot("fire") + Vector3(6, 0, 0))
	assert_false(is_instance_valid(world._fight), "no second ambush")


func test_losing_a_camp_fight_leaves_it_to_try_again() -> void:
	await _load()
	var camp := _first("camp")
	var node := world.sites.build_site(camp["id"])
	await _stand_at(node.spot("fire") + Vector3(8, 0, 0))
	assert_true(is_instance_valid(world._fight))
	world._end_fight(false)
	assert_false(world.sites.is_done(camp["id"]), "not cleared")


func test_a_shrine_is_attuned_once_rests_you_and_is_travelled_to_from_the_map() -> void:
	await _load()
	var shrine := _first("shrine")
	var node := world.sites.build_site(shrine["id"])
	await _stand_at(node.spot("interact"))
	var offer := world.activities.interact_for(player.global_position)
	assert_eq(offer["kind"], "shrine")
	assert_true(str(offer["prompt"]).begins_with("Attune"), "first visit")
	player.stats.health = 1.0
	var xp := Game.xp()
	world.activities.use("shrine", shrine["id"])
	assert_true(world.sites.is_done(shrine["id"]), "attuned")
	assert_eq(player.stats.health, player.stats.max_health, "it heals")
	assert_true(Game.xp() > xp, "once for XP")
	var after := Game.xp()
	world.activities.use("shrine", shrine["id"])
	assert_eq(Game.xp(), after, "praying again pays nothing")
	assert_true(str(world.activities.interact_for(player.global_position)["prompt"]).begins_with("Pray"))
	# Travel there from far away.
	var far := {}
	for s: Dictionary in world.sites.plan.sites:
		if (s["at"] as Vector2).distance_to(shrine["at"]) > 1000.0:
			far = s
			break
	await _stand_at(world.sites.position_of(far["id"]))
	assert_true(await world.fast_travel(shrine["id"]), "a shrine you attuned to is a destination")
	# (The far shrine was freed while you were away; travelling built it again.)
	assert_true(player.global_position.distance_to(world.sites.build_site(shrine["id"]).spot("interact")) < 3.0, "you stand at its foot")
	assert_false(await world.fast_travel(world.sites.plan.of_kind("shrine")[1]["id"]), "an unattuned shrine is not")


func test_a_relic_is_taken_by_walking_over_it() -> void:
	await _load()
	var ruin := _first("ruin")
	var node := world.sites.build_site(ruin["id"])
	var xp := Game.xp()
	await _stand_at(node.spot("relic"))
	assert_true(world.sites.is_done(ruin["id"]), "taken")
	assert_true(Game.xp() > xp)
	assert_eq(int(Game.record("world", "relics", 0)), 1)


func test_a_board_gives_one_contract_for_a_camp_and_it_pays_double() -> void:
	await _load()
	var village := _first("village")
	var node := world.sites.build_site(village["id"])
	await _stand_at(node.spot("board") + Vector3(1.5, 0, 0))
	var offer := world.activities.interact_for(player.global_position)
	assert_eq(offer["kind"], "board")
	assert_true(str(offer["prompt"]).begins_with("Take"))
	world.activities.use("board", village["id"])
	var camp_id := world.activities.contract()
	assert_true(camp_id != "", "a contract was taken")
	assert_eq(world.sites.plan.site(camp_id)["kind"], "camp")
	assert_true(world.sites.is_found(camp_id), "and the camp is on the map")
	assert_true(str(world.activities.interact_for(player.global_position)["prompt"]).begins_with("Read"), "one at a time")
	var camp := world.sites.plan.site(camp_id)
	var normal := SiteActivities.camp_xp(camp, world.story_tier())
	var before := Game.xp()
	world.activities.finish_fight(SiteActivities.PREFIX + camp_id)
	assert_eq(Game.xp() - before, 2 * normal, "double pay")
	assert_eq(world.activities.contract(), "", "the contract is done")
	assert_eq(int(Game.record("world", "contracts_done", 0)), 1)


func test_the_lanterns_of_a_place_built_at_night_are_lit() -> void:
	await _load()
	scene.set_time_of_day("night")
	await physics_frames(2)
	var node := world.sites.build_site(_first("village")["id"])
	assert_true(node.lanterns.size() >= 3, "a village has lanterns")
	for lantern in node.lanterns:
		assert_true(lantern.get_children().any(func(c: Node) -> bool: return c is OmniLight3D), "%s is lit" % lantern.name)
	assert_true(world.sites.lanterns().size() >= node.lanterns.size())


func test_continuing_far_from_home_stands_on_the_ground_there() -> void:
	# A save in the far north: the ground must come up there (not at the origin
	# where the player waits) and stay while they are placed on it.
	var site := OpenWorld.demo_site("shrine", 0)
	Game.set_record("world", "position_continent", site + Vector3(0, 0, 24))
	await _load()
	var land := (world.archipelago as ContinentWorld).continent.land
	var p := player.global_position
	assert_near(p.y, land.height_at(p.x, p.z) + 0.2, 0.6, "on the ground, not under it")


func test_a_wanted_shinobi_speaks_then_duels_and_is_finished_for_good() -> void:
	await _load()
	var lair := _first("lair")
	var bounty := Bounties.get_bounty(lair["bounty"])
	var node := world.sites.build_site(lair["id"])
	var before := Game.xp()
	await _stand_at(node.spot("den") + Vector3(12, 0, 0))
	assert_true(world.busy, "the encounter has begun")
	assert_true(world.dialogue.is_open(), "they speak first")
	await _skip_dialogue()
	await physics_frames(3)
	assert_true(is_instance_valid(world._duelist), "then the duel")
	assert_eq(world._duelist.title_override, bounty["name"])
	assert_eq(world._duelist.rank, &"jonin")
	assert_eq(world._duelist.element, Element.from_name(bounty["element"]))
	assert_true(world._duelist.health_override >= 300.0)
	assert_eq(world._fight_quest, SiteActivities.PREFIX + lair["id"])
	world._duelist.defeated.emit(world._duelist)
	assert_true(world.sites.is_done(lair["id"]), "finished")
	assert_true(Game.xp() - before >= SiteActivities.bounty_xp(bounty, world.story_tier()), "a bounty pays well")
	assert_eq(int(Game.record("world", "bounties", 0)), 1)
	world.busy = false
	await _stand_at(node.spot("den") + Vector3(8, 0, 0))
	assert_false(world.busy, "they do not come back")


func test_every_third_contract_is_a_wanted_shinobi() -> void:
	await _load()
	var village := _first("village")
	var node := world.sites.build_site(village["id"])
	Game.set_record("world", "contracts_done", 2)
	await _stand_at(node.spot("board") + Vector3(1.5, 0, 0))
	world.activities.use("board", village["id"])
	var target := world.sites.plan.site(world.activities.contract())
	assert_eq(target["kind"], "lair", "the third contract names a lair")


func test_every_quarter_of_a_kind_pays_a_growing_bonus() -> void:
	await _load()
	var camps := world.sites.plan.of_kind("camp")
	var total := camps.size()
	var paid: Array[int] = []
	for i in total:
		world.sites.set_state(camps[i]["id"], WorldSites.DONE)
		var m := world.activities.milestone("camp")
		if not m.is_empty():
			paid.append(int(m["xp"]))
	assert_eq(paid.size(), 4, "four marks over %d camps" % total)
	assert_eq(paid, [150, 300, 450, 600] as Array[int], "each worth more than the last")
	assert_true(world.activities.milestone("village").is_empty(), "villages have none")
	var xp := Game.xp()
	world.activities.take_relic(_first("ruin"))
	assert_true(Game.xp() > xp)


func test_snow_settles_over_the_frozen_road_and_lifts_when_you_leave() -> void:
	await _load()
	assert_eq(scene.weather, "none", "clear at home")
	await world._put_player_at(world.archipelago.on_island("frozen_road", Vector2(0, 12)))
	await physics_frames(5)
	assert_eq(scene.weather, "snow", "snow on the Frozen Road")
	await world._put_player_at(world.archipelago.on_island("emberwood", Vector2(0, 12)))
	await physics_frames(5)
	assert_eq(scene.weather, "none", "and clear again elsewhere")
	await world._put_player_at(world.archipelago.on_island("autumn_wood", Vector2(0, 12)))
	await physics_frames(5)
	assert_eq(scene.weather, "leaves", "leaves fall in Autumn Wood")
