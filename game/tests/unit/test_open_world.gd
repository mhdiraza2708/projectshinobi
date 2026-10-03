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


func _stand_at(at: Vector3) -> void:
	player.global_position = at + Vector3.UP * 0.3
	player.velocity = Vector3.ZERO
	await physics_frames(3)


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
	scene.return_to_world()
	assert_eq(scene.mode, Game.Mode.WORLD)
	assert_false(is_instance_valid(scene._arena))


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
	assert_eq(world._duelist.title_override, "Kurogane")
	assert_false(world._givers.has("kurogane"), "he isn't standing there as well")
	await seconds(EnemyShinobi.SPAWN_TIME + 0.2)
	var xp := Game.xp()
	world._duelist.take_hit(99999.0, Element.NONE, player)
	await _skip_dialogue()
	assert_eq(Quests.status("ash_duelist"), Quests.DONE)
	assert_true(Game.xp() - xp >= int(Quests.quest("ash_duelist")["xp"]))


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
