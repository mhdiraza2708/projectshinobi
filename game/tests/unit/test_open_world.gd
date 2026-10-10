extends TestCase
## The open world (Archipelago, OpenWorld, Quests): every island in one sea
## you can run across, a pillar where the next chapter starts, side quests
## that open with the story and pay XP, people who say the right thing, and
## chapters played in place by moving the world under them.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player
var world: OpenWorld


func before_each() -> void:
	Profile.persist = false
	Profile.reset()
	Game.reset_records()
	Quests.reload()


# Not a coroutine: the runner starts the next test without waiting.
func after_each() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
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


## Plays out whatever the dialogue box is showing.
func _skip_dialogue() -> void:
	for i in 40:
		if not world.dialogue.is_open():
			return
		world.dialogue.advance()
		world.dialogue.advance()
		await physics_frames(1)


## How brightly the lanterns' paper glows.
func _lantern_glow() -> float:
	for node in scene.lanterns():
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			var mi := mesh as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var m := mi.get_active_material(i) as BaseMaterial3D
				if m and m.emission_enabled:
					return m.emission_energy_multiplier
	return -1.0


func _stand_at(at: Vector3) -> void:
	player.global_position = at + Vector3.UP * 0.3
	player.velocity = Vector3.ZERO
	await physics_frames(3)


func test_every_gather_quest_finds_room_for_all_its_items() -> void:
	await _load()
	for q in Quests.all():
		if q["type"] != "gather":
			continue
		var spots := world.gather_spots(q)
		assert_eq(spots.size(), int(q["count"]), "%s: room for %d %s" % [q["id"], int(q["count"]), q["item"]])


func test_a_new_game_starts_on_the_ground_at_emberwood() -> void:
	await _load()
	var pad := world.archipelago.to_global(world.archipelago.offset("emberwood"))
	assert_near(player.global_position.y, pad.y, 1.0, "standing on the home clearing, not below it or in the sea")
	assert_eq(world.archipelago.island_near(player.global_position), "emberwood")


func test_the_quest_data_is_valid_and_its_places_are_dry_land() -> void:
	assert_eq(Quests.errors, [] as Array[String])
	assert_true(Quests.all().size() >= 8, "a handful of side quests")
	await _load()
	for q in Quests.all():
		var island: Island = world.archipelago.islands[q["island"]]
		for key: String in ["giver_at", "at"]:
			if not q.has(key):
				continue
			var at: Array = q[key]
			var h := island.height_at(float(at[0]), float(at[1]))
			assert_true(h > island.water_level + 0.5, "%s's %s is above the sea (%.1f)" % [q["id"], key, h])
		if q["type"] == "gather":
			assert_eq(world.gather_spots(q).size(), int(q["count"]), "%s has room for every item" % q["id"])
	for kanji: String in OpenWorld.ISLAND_KANJI.values():
		assert_true(UiKit.font(&"brush").has_char(kanji.unicode_at(0)), "%s is in the font" % kanji)


func test_every_island_stands_in_one_sea() -> void:
	await _load()
	assert_eq(world.archipelago.islands.size(), Archipelago.LAYOUT.size())
	assert_eq(world.archipelago.island_near(player.global_position), "emberwood", "a new game starts at Emberwood")
	# Far from any island you stand on the sea, and sprint faster there.
	var sea := world.archipelago.to_global(Vector3(220.0, Archipelago.SEA_LEVEL + 1.0, -90.0))
	await _stand_at(sea)
	await physics_frames(20)
	assert_true(world.archipelago.on_water(player), "the sea holds you up")
	assert_near(player.global_position.y, world.archipelago.global_position.y + Archipelago.SEA_LEVEL, 0.6)
	Input.action_press(&"evade")
	Input.action_press(&"move_forward")
	await seconds(0.6)
	assert_near(player.surface_speed, Archipelago.WATER_SPRINT, 0.001, "chakra-running on the water")
	Input.action_release(&"evade")
	Input.action_release(&"move_forward")


func test_music_follows_the_island_the_sea_and_the_night() -> void:
	# The choice itself: a place's own music, else the region's night or theme.
	for id: String in Island.PRESETS:
		assert_eq(OpenWorld.track_for(id, "day"), Music.island_theme(id), "%s has its theme by day" % id)
		assert_eq(OpenWorld.track_for(id, "night"), Music.island_night(id), "and its own piece after dark")
		assert_true(Music.island_night(id) != &"night" and Music.has_track(Music.island_night(id)), "%s has a night of its own" % id)
	assert_eq(OpenWorld.track_for("emberwood", "dawn"), &"calm", "Emberwood keeps calm")
	assert_eq(OpenWorld.track_for("ashen_pass", "dusk"), &"ashen_pass")
	assert_eq(OpenWorld.track_for("", "day"), &"sea")
	assert_eq(OpenWorld.track_for("", "night"), &"night", "night over the water too")
	assert_eq(OpenWorld.track_for("", "day", true), &"road", "the continent's wilds have the road, not the sea")
	assert_eq(OpenWorld.track_for("", "night", true), &"road_night")
	assert_eq(OpenWorld.track_for("old_dam", "night", true), Music.island_night("old_dam"), "a region keeps its night")
	for kind: String in OpenWorld.PLACE_TRACKS:
		for when in ["day", "night"]:
			assert_eq(OpenWorld.track_for("", when, true, kind), OpenWorld.PLACE_TRACKS[kind], "a %s by %s" % [kind, when])
	assert_eq(OpenWorld.track_for("ashen_pass", "day", true, "camp"), &"ashen_pass", "a place without music of its own changes nothing")
	# In the world (the wilds are the sea on the islands and the road on the continent).
	var wilds := &"road" if OpenWorld.uses_continent() else &"sea"
	var wilds_night := &"road_night" if OpenWorld.uses_continent() else &"night"
	await _load()
	assert_eq(Music.current, &"calm", "a new game starts on Emberwood in the morning")
	for id: String in ["autumn_wood", "ashen_pass", "old_dam", "frozen_road", "five_winds", "emberwood"]:
		await _stand_at(world.archipelago.on_island(id, OpenWorld.TRAVEL_POINT))
		assert_eq(Music.current, Music.island_theme(id), "%s plays its own music" % id)
	var sea := world.archipelago.to_global(Vector3(220.0, Archipelago.SEA_LEVEL + 1.0, -90.0))
	await _stand_at(sea)
	assert_eq(Music.current, wilds, "out in the open")
	world.clock = 0.8 * OpenWorld.DAY_LENGTH
	await physics_frames(2)
	assert_eq(world.phase(), "night")
	assert_eq(Music.current, wilds_night, "night falls over the open")
	await _stand_at(world.archipelago.on_island("old_dam", OpenWorld.TRAVEL_POINT))
	assert_eq(Music.current, Music.island_night("old_dam"), "and each region has its own night")
	world.clock = 0.3 * OpenWorld.DAY_LENGTH
	await physics_frames(2)
	assert_eq(Music.current, &"old_dam", "morning brings the island's theme back")


func test_island_music_holds_a_little_way_past_the_shore() -> void:
	await _load()
	# Distances from the coast: the name card shows within 18 m; the music keeps
	# going until SHORE_HOLD further out, and only returns inside the 18.
	# (On the continent a region's edge is its radius, and the home pad's own height is the ground.)
	var coast := ContinentLand.REGION_RADIUS if OpenWorld.uses_continent() else float(Island.PRESETS["emberwood"]["coast"])
	var home := world.archipelago.offset("emberwood")
	var out_to := func(metres: float) -> Vector3:
		return world.archipelago.to_global(home + Vector3(coast + metres, 1.0, 0.0))
	await _stand_at(out_to.call(18.0 + OpenWorld.SHORE_HOLD * 0.5))
	assert_eq(Music.current, &"calm", "past the name card's reach the island's music holds")
	await _stand_at(out_to.call(18.0 + OpenWorld.SHORE_HOLD + 6.0))
	var wilds := &"road" if OpenWorld.uses_continent() else &"sea"
	assert_eq(Music.current, wilds, "further out it gives way to the open")
	await _stand_at(out_to.call(18.0 + OpenWorld.SHORE_HOLD * 0.5))
	assert_eq(Music.current, wilds, "and does not flicker back at the same spot")
	await _stand_at(out_to.call(18.0 - 4.0))
	assert_eq(Music.current, &"calm", "it returns once you are properly inside")
	world.busy = true
	await _stand_at(out_to.call(18.0 + OpenWorld.SHORE_HOLD + 6.0))
	assert_eq(Music.current, &"calm", "a fight or chapter keeps its own music")


func test_the_story_waits_at_a_pillar_and_plays_in_place() -> void:
	await _load()
	var o := world.objective()
	assert_true(str(o["title"]).contains("Graduation"), "the main quest is chapter one")
	assert_true(o["at"] is Vector3)
	var chapter: Dictionary = world.story.chapters[3]
	for i in 3:
		Game.mark_chapter_done(world.story.chapters[i]["id"])
	world.refresh()
	assert_eq(world._beacon.chapter_id, chapter["id"], "the pillar moves to the next chapter")
	assert_eq(world.archipelago.island_near(world._beacon.global_position), chapter["island"])
	scene.start_story_in_world(chapter["id"])
	await physics_frames(3)
	var island: Island = world.archipelago.islands[chapter["island"]]
	assert_true(island.global_position.length() < 0.01, "the chapter's island is moved to the origin")
	assert_true(is_instance_valid(scene._arena), "a wall rings the clearing")
	assert_eq(scene.mode, Game.Mode.STORY)
	var npc: StoryNpc = scene.story_director.add_npc("hisame", Vector2(2, 2), true)
	scene.return_to_world()
	assert_eq(scene.mode, Game.Mode.WORLD)
	assert_false(is_instance_valid(scene._arena))
	await physics_frames(1)
	assert_false(is_instance_valid(npc), "the chapter's cast leaves with it")


func test_a_gather_quest_from_offer_to_reward() -> void:
	await _load()
	assert_eq(Quests.status("practice_kunai"), Quests.LOCKED, "it waits for the story")
	Game.mark_chapter_done("ch1_graduation")
	world.refresh()
	assert_eq(Quests.status("practice_kunai"), Quests.AVAILABLE)
	var tobi: StoryNpc = world._givers["tobi"]
	assert_eq((tobi.get_node("QuestMark") as Label3D).text, "!", "Tobi has something for you")
	world.talk_to("tobi")
	await _skip_dialogue()
	assert_eq(Quests.status("practice_kunai"), Quests.ACTIVE)
	assert_eq(Quests.tracked(), "practice_kunai", "a new quest is tracked")
	var pickups: Array = world._pickups["practice_kunai"]
	assert_eq(pickups.size(), 6)
	var xp := Game.xp()
	for p in pickups.duplicate():
		await _stand_at((p as Node3D).global_position - Vector3.UP * 0.6)
		await physics_frames(2)
	await _skip_dialogue()
	assert_eq(Quests.status("practice_kunai"), Quests.DONE)
	assert_eq(Game.xp() - xp, int(Quests.quest("practice_kunai")["xp"]), "it pays its XP")


func test_a_delivery_crosses_the_sea() -> void:
	await _load()
	Game.mark_chapter_done("ch8_dam")
	world.refresh()
	world.talk_to("renji")
	await _skip_dialogue()
	assert_eq(Quests.status("lost_letter"), Quests.ACTIVE)
	world.refresh()
	assert_true(world._givers.has("suzu"), "the letter's reader is waiting")
	assert_eq(world.archipelago.island_near(world._givers["suzu"].global_position), "autumn_wood")
	assert_true(world.objective()["at"] is Vector3)
	world.talk_to("suzu")
	await _skip_dialogue()
	assert_eq(Quests.status("lost_letter"), Quests.DONE)


func test_a_defeat_quest_starts_at_its_spot_with_mixed_natures() -> void:
	await _load()
	Game.mark_chapter_done("ch2_rival")
	world.refresh()
	world.talk_to("mago")
	await _skip_dialogue()
	assert_eq(Quests.status("pier_bandits"), Quests.ACTIVE)
	var q := Quests.quest("pier_bandits")
	await _stand_at(world.archipelago.on_island("emberwood", Vector2(q["at"][0], q["at"][1])))
	assert_true(is_instance_valid(world._fight), "reaching the spot starts the fight")
	assert_eq(Music.current, &"battle", "the first quest fight plays the first battle theme")
	await seconds(TrialDirector.ANNOUNCE_TIME + 0.3)
	var natures := world._fight.alive.map(func(e: EnemyShinobi) -> int: return e.element)
	assert_eq(natures, [Element.FIRE, Element.WATER], "each bandit keeps its own nature")
	for e in world._fight.alive:
		assert_true(e.global_position.distance_to(player.global_position) < 30.0, "they appear near you, on the ground")


func test_a_duel_turns_the_giver_into_the_foe() -> void:
	await _load()
	Game.mark_chapter_done("ch5_kagerou")
	world.refresh()
	world.talk_to("kurogane")
	await _skip_dialogue()
	await physics_frames(2)
	assert_true(is_instance_valid(world._duelist), "Kurogane draws")
	assert_eq(Music.current, &"duel", "a duel has its own music")
	assert_eq(world._fights, 1)
	assert_eq(world._duelist.title_override, "Kurogane")
	assert_false(world._givers.has("kurogane"), "he isn't standing there as well")
	await seconds(EnemyShinobi.SPAWN_TIME + 0.2)
	var xp := Game.xp()
	world._duelist.take_hit(99999.0, Element.NONE, player)
	await _skip_dialogue()
	assert_eq(Quests.status("ash_duelist"), Quests.DONE)
	assert_true(Game.xp() - xp >= int(Quests.quest("ash_duelist")["xp"]))
	assert_eq(Music.current, Music.island_theme(world.archipelago.island_near(player.global_position)), "back to exploring")


func test_the_quest_log_lists_and_tracks() -> void:
	await _load()
	Game.mark_chapter_done("ch1_graduation")
	Game.mark_chapter_done("ch2_rival")
	world.refresh()
	world.talk_to("tobi")
	await _skip_dialogue()
	var menu: PauseMenu = scene.pause_menu
	menu.open()
	menu._select_tab(PauseMenu.TAB_QUESTS)
	await physics_frames(2)
	var text := ""
	for l in menu._quest_list.find_children("*", "Label", true, false):
		text += (l as Label).text + "\n"
	assert_true(text.contains("Thrown and Forgotten"), "the quest taken on")
	assert_true(text.contains("Trouble at the Old Pier"), "one on offer")
	var track: Button
	for b in menu._quest_list.find_children("*", "Button", true, false):
		if (b as Button).text == "Track":
			track = b
	track.pressed.emit()
	assert_eq(Quests.tracked(), Quests.MAIN, "the story can be tracked again")
	menu.close()


func test_the_day_turns_and_the_sky_crossfades() -> void:
	await _load()
	assert_eq(world.phase(), "day", "a new game starts mid-morning")
	assert_eq(world.phase(0.62 * OpenWorld.DAY_LENGTH), "dusk")
	assert_eq(world.phase(0.9 * OpenWorld.DAY_LENGTH), "night")
	assert_eq(world.phase(0.02 * OpenWorld.DAY_LENGTH), "dawn")
	# Just before dusk, a moment later it's dusk, easing in.
	world.clock = 0.55 * OpenWorld.DAY_LENGTH - 0.05
	await seconds(0.3)
	assert_eq(scene.time_of_day(), "dusk", "the clock moves the world's time")
	var env := (scene.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sky := Skies.material(env)
	if sky:
		assert_true(float(sky.get_shader_parameter(&"blend")) < 1.0, "the old sky is still fading out")
	# Night lights the lanterns on every island; dawn puts them out.
	scene.transition_time("night", 0.0)
	assert_true(scene.lantern_lights.size() > 6, "lanterns across the archipelago")
	assert_near(_lantern_glow(), scene.LANTERN_GLOW, 0.01, "and their paper glows")
	scene.transition_time("dawn", 0.0)
	assert_eq(scene.lantern_lights.size(), 0)
	assert_near(_lantern_glow(), scene.LANTERN_GLOW_DAY, 0.01, "dim again by day")
	world.save_position()
	assert_near(float(Game.record("world", "clock", 0.0)), world.clock, 0.01, "the time is saved")


func test_the_map_charts_the_islands_and_travel_needs_a_visit() -> void:
	await _load()
	var tex := WorldMap.chart(world.archipelago)
	var img := tex.get_image()
	var continent := OpenWorld.uses_continent()
	var b := WorldMap.bounds(continent)
	var per_pixel := WorldMap.CONTINENT_METRES_PER_PIXEL if continent else WorldMap.METRES_PER_PIXEL
	var layout := world.archipelago.layout()
	for id: String in Archipelago.LAYOUT:
		var c: Vector2 = (layout[id] - b.position) / per_pixel
		assert_true(img.get_pixelv(Vector2i(c)).a > 0.5, "%s is drawn on the chart" % id)
	# Open sea is left as paper: the islands' gap, or the continent's far corner.
	var sea := Vector2(-1840, 1840) if continent else Vector2(220, -90)
	assert_true(img.get_pixelv(Vector2i((sea - b.position) / per_pixel)).a < 0.1, "open sea is left as paper")
	assert_true(world.discovered("emberwood"))
	assert_false(world.discovered("autumn_wood"))
	assert_false(await world.fast_travel("autumn_wood"), "not before you've been there")
	await _stand_at(world.archipelago.on_island("autumn_wood", Vector2(0, 10)))
	await physics_frames(2)
	assert_true(world.discovered("autumn_wood"), "setting foot there finds it")
	await _stand_at(world.archipelago.on_island("emberwood", Vector2(0, 14)))
	assert_true(await world.fast_travel("autumn_wood"))
	assert_eq(world.archipelago.island_near(player.global_position), "autumn_wood", "and travel takes you there")
	var menu: PauseMenu = scene.pause_menu
	menu.open()
	menu._select_tab(PauseMenu.TAB_MAP)
	await physics_frames(2)
	assert_true(menu._map != null and menu._map.is_visible_in_tree(), "the Map tab shows the chart")
	menu.close()


func test_continuing_at_sea_announces_no_island() -> void:
	# Until the world puts you back where you were you stand at the origin,
	# on Emberwood: nothing may be announced (or found) from there.
	if OpenWorld.uses_continent():
		# Dry land as far from every region as there is.
		var land := ContinentLand.new()
		var best := Vector2.ZERO
		var far := 0.0
		for z in range(-1600, 1700, 100):
			for x in range(-1600, 1700, 100):
				if land.height_at(x, z) < 6.0:
					continue
				var d := float(land.nearest_region(x, z)["distance"])
				if d > far:
					far = d
					best = Vector2(x, z)
		assert_true(far > ContinentLand.REGION_RADIUS + 60.0, "there are wilds (%.0f m from any region)" % far)
		Game.set_record("world", "position_continent", Vector3(best.x, land.height_at(best.x, best.y), best.y))
	else:
		Game.set_record("world", "position", Archipelago.offset_of("autumn_wood") + Vector3(-130, 0, 50))
	await _load()
	await physics_frames(3)
	assert_eq(world.archipelago.island_near(player.global_position), "", "you're back out at sea")
	assert_eq(world.tracker._place_name.text, "", "and no island's name comes up")


func test_a_save_made_at_dusk_continues_at_dusk() -> void:
	Game.set_record("world", "clock", 0.6 * OpenWorld.DAY_LENGTH)
	await _load()
	assert_eq(world.phase(), "dusk")
	assert_eq(scene.time_of_day(), "dusk", "the world is lit for the saved time")


func test_continuing_at_night_finds_the_lanterns_lit() -> void:
	# The time is set before the islands are built: the lanterns must still
	# be lit once they exist.
	Game.set_record("world", "clock", 0.85 * OpenWorld.DAY_LENGTH)
	await _load()
	assert_eq(scene.time_of_day(), "night")
	assert_true(scene.lantern_lights.size() > 6, "lanterns lit across the archipelago")
	assert_near(_lantern_glow(), scene.LANTERN_GLOW, 0.01, "their paper glowing")


## Plays out whatever the story shows: dialogue is clicked through, but
## cutscenes play in full (as a player sees them, without skipping).
func _story_through() -> void:
	if scene.dialogue.is_open():
		scene.dialogue.advance()
		scene.dialogue.advance()


func test_kagerou_mission_plays_to_the_end_in_the_world() -> void:
	# Kagerou's boss fight and everything after it, played where the story
	# happens (in the world), then back to free roam.
	await _load()
	for i in 6:
		Game.mark_chapter_done(world.story.chapters[i]["id"])
	world.refresh()
	scene.start_story_in_world("ch5_kagerou")
	await physics_frames(3)
	var finished := []
	scene.story_director.chapter_finished.connect(func(c: Dictionary) -> void: finished.append(c["id"]))
	var beats: Array = scene.story_director.chapter["beats"]
	scene.dialogue.visible = false
	scene.story_director.beat_index = beats.find_custom(func(b: Dictionary) -> bool: return b["do"] == "boss") - 1
	scene.story_director._next()
	await physics_frames(ceili(EnemyShinobi.SPAWN_TIME * 60.0) + 5)
	var boss: EnemyShinobi = scene.story_director.boss
	assert_true(boss != null, "the boss is on the field")
	boss.take_hit(99999.0, Element.NONE, player)
	for i in 2400:
		await _story_through()
		if not finished.is_empty():
			break
		await physics_frames(1)
	assert_eq(finished, ["ch5_kagerou"], "the mission finishes (stuck at beat %d)" % scene.story_director.beat_index)
	for i in 400:
		if scene.mode == Game.Mode.WORLD:
			break
		await physics_frames(1)
	assert_eq(scene.mode, Game.Mode.WORLD, "and you're back in the world")
	await physics_frames(30)
	assert_true(is_instance_valid(player) and player.is_inside_tree(), "still standing")
