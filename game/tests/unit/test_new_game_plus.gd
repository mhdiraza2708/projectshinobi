extends TestCase
## New Game+ and the difficulty setting: the saga again, tougher, with what
## you learned.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D


func before_each() -> void:
	Profile.persist = false
	Settings.persist = false
	Profile.reset()
	Game.reset_records()
	Quests.reload()


func after_each() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
	Game.reset_records()
	Profile.reset()


func test_it_wipes_the_saga_but_keeps_what_you_learned() -> void:
	Game.persist = false
	Game.mark_chapter_done("ch1_graduation")
	Game.set_record("quests", "practice_kunai", Quests.DONE)
	Game.set_record("world", "position", Vector3(5, 0, 5))
	Game.set_record("world", "discovered", ["autumn_wood"])
	Game.set_record("sites", "site_01", "done")
	Game.add_xp(500, "test")
	var ranks := {"some_node": 2}
	Game.set_skill_ranks(ranks)
	var xp := Game.xp()
	assert_eq(Game.ng_plus(), 0)
	Game.begin_new_game_plus()
	assert_eq(Game.ng_plus(), 1)
	assert_false(Game.chapter_done("ch1_graduation"), "the story starts over")
	assert_eq(Quests.status("practice_kunai"), Quests.LOCKED, "and its quests")
	assert_eq(Game.record("world", "discovered", []), [], "and what you discovered")
	assert_eq(Game.record("sites", "site_01", ""), "", "and the continent's places")
	assert_eq(Game.xp(), xp, "your experience stays")
	assert_eq(Game.skill_ranks(), ranks, "and your skills")
	Game.begin_new_game_plus()
	assert_eq(Game.ng_plus(), 2, "it can go round again")
	Game.persist = true


func test_the_tougher_world_shows_in_the_fighters_it_makes() -> void:
	Game.set_record("meta", "ng_plus", 1)
	var e := EnemyShinobi.new()
	e.rank = &"chunin"
	e.tier = EnemyTier.of_part(1)
	var table: Dictionary = (EnemyShinobi.RANKS[&"chunin"] as Dictionary).duplicate(true)
	EnemyTier.apply(table, e.tier)
	assert_true(float(table["health"]) > float(EnemyShinobi.RANKS[&"chunin"]["health"]), "round two's first fighters are already tougher")
	e.free()


func test_the_quests_tab_offers_it_only_when_the_story_is_told() -> void:
	Game.start_mode = Game.Mode.TITLE
	scene = Scene.instantiate()
	root.add_child(scene)
	await physics_frames(2)
	scene.instant_world = true
	await scene.start_world()
	await physics_frames(3)
	var menu: PauseMenu = scene.pause_menu
	menu.open()
	menu._select_tab(PauseMenu.TAB_QUESTS)
	await physics_frames(2)
	assert_true(_buttons(menu).filter(func(b: Button) -> bool: return b.text.begins_with("Begin New Game+")).is_empty(), "not while the story goes on")
	for c: Dictionary in scene.story.chapters:
		Game.mark_chapter_done(c["id"])
	menu._refresh_quests()
	await physics_frames(2)
	var found := _buttons(menu).filter(func(b: Button) -> bool: return b.text.begins_with("Begin New Game+"))
	assert_eq(found.size(), 1, "once the last chapter is done")
	assert_true(_labels(menu).any(func(t: String) -> bool: return t.begins_with("Side quests done")), "with a tally of deeds")
	menu.close()


func _buttons(menu: PauseMenu) -> Array[Button]:
	var out: Array[Button] = []
	for n in menu._quest_list.find_children("*", "Button", true, false):
		out.append(n as Button)
	return out


func _labels(menu: PauseMenu) -> Array[String]:
	var out: Array[String] = []
	for n in menu._quest_list.find_children("*", "Label", true, false):
		out.append((n as Label).text)
	return out
