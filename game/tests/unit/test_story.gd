extends TestCase
## Story mode: chapter data, dialogue, a full playthrough of chapter 1,
## bosses, retrying a lost fight, chapter unlocking and time of day.

const Scene := preload("res://scenes/training_ground.tscn")
const TMP := "user://test_story"

var scene: Node3D
var player: Player


func before_each() -> void:
	seed(99)


func after_each() -> void:
	for action: StringName in DefaultBindings.table():
		Input.action_release(action)
	if DirAccess.dir_exists_absolute(TMP):
		for f in DirAccess.get_files_at(TMP):
			DirAccess.remove_absolute(TMP.path_join(f))
		DirAccess.remove_absolute(TMP)


func _load() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	await physics_frames(5)


## Advances any open dialogue until a non-dialogue beat is reached.
func _talk_through() -> void:
	for i in 400:
		if not scene.dialogue.is_open():
			return
		scene.dialogue.advance()
		scene.dialogue.advance()
		await physics_frames(1)


func _beat() -> String:
	return scene.story_director.current_beat().get("do", "")


## Waits for the next beat of `kind` after the current one.
func _await_beat(kind: String, limit := 400) -> void:
	var from: int = scene.story_director.beat_index
	for i in limit:
		await _talk_through()
		if scene.story_director.beat_index != from and _beat() == kind:
			return
		await physics_frames(1)
	fail("never reached a '%s' beat (at '%s')" % [kind, _beat()])


func _kill_all_enemies(limit := 300) -> void:
	for i in limit:
		var enemies := scene.find_children("*", "EnemyShinobi", true, false).filter(
			func(e: EnemyShinobi) -> bool: return not e.is_defeated())
		if enemies.is_empty() and i > 0 and (scene.story_director.fight == null or scene.story_director.fight.alive.is_empty()):
			if _beat() != "fight" and _beat() != "boss":
				return
		for e: EnemyShinobi in enemies:
			e.take_hit(99999.0, Element.NONE, player)
		await physics_frames(1)


func _jump_to(kind: String) -> void:
	var beats: Array = scene.story_director.chapter["beats"]
	scene.dialogue.visible = false
	scene.story_director.beat_index = beats.find_custom(func(b: Dictionary) -> bool: return b["do"] == kind) - 1
	scene.story_director._next()


func test_story_files_load_cleanly() -> void:
	var story := Story.load_all()
	assert_eq(story.errors, [] as Array[String], "story data errors")
	assert_eq(story.chapters.size(), 5)
	for c: Dictionary in story.chapters:
		var kinds: Array = c["beats"].map(func(b: Dictionary) -> String: return b["do"])
		assert_true(kinds.has("say"), "%s has dialogue" % c["id"])
		assert_true(kinds.has("fight") or kinds.has("boss"), "%s has a fight" % c["id"])
	for id: String in story.characters:
		assert_true(UiKit.font(&"brush").has_char(story.characters[id]["kanji"].unicode_at(0)), "%s's seal kanji is in the font" % id)


func test_loader_catches_mistakes() -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	var cast := FileAccess.open(TMP.path_join("characters.json"), FileAccess.WRITE)
	cast.store_string(JSON.stringify({"mei": {"name": "Mei", "kanji": "雨", "element": "water", "style": {"hat": true}}}))
	cast.close()
	var ch := FileAccess.open(TMP.path_join("ch1.json"), FileAccess.WRITE)
	ch.store_string(JSON.stringify({
		"id": "ch1", "number": 1, "title": "T", "location": "L", "time": "noon", "colour": "red",
		"beats": [
			{"do": "say", "lines": [["mei", "I'm not on stage yet."]]},
			{"do": "enter", "who": "ghost", "at": [0, 0]},
			{"do": "task", "text": "x", "goal": "dance"},
			{"do": "fight", "waves": [{"element": "metal", "enemies": ["genin", "kage"]}]},
			{"do": "exit", "who": "mei"},
			{"do": "teleport"},
		]}))
	ch.close()
	var story := Story.load_all(TMP)
	var all := "\n".join(story.errors)
	for expected in ["unknown style key 'hat'", "unknown key 'colour'", "time must be one of", "isn't on stage",
			"unknown character 'ghost'", "unknown goal 'dance'", "unknown element 'metal'", "unknown rank 'kage'",
			"exits without having entered", "unknown beat 'teleport'"]:
		assert_true(all.contains(expected), "reports: %s" % expected)
	assert_eq(story.chapters.size(), 0, "a broken chapter isn't playable")


func test_format_fills_name_nature_and_buttons() -> void:
	Profile.set_value(&"name", "Kaze")
	Profile.set_value(&"affinity", Element.WIND)
	InputDevice.current = Binding.Device.KEYBOARD_MOUSE
	var text := Story.format("{name}, a {nature} user, presses {throw_tool}. {unknown} stays.")
	assert_eq(text, "Kaze, a wind user, presses %s. {unknown} stays." % InputDevice.glyph(&"throw_tool"))


func test_dialogue_types_advances_and_finishes() -> void:
	var box := DialogueBox.new()
	root.add_child(box)
	var story := Story.load_all()
	var done := [false]
	box.finished.connect(func() -> void: done[0] = true)
	box.play([{"who": "hisame", "text": "First line, typed out.", "mood": ""},
		{"who": Story.PLAYER, "text": "Second.", "mood": ""}], story)
	assert_true(box.is_open())
	assert_true(box._text.visible_ratio < 1.0, "types out")
	assert_true(box._name.text.begins_with("Hisame"))
	box.advance()
	assert_near(box._text.visible_ratio, 1.0, 0.001, "first press completes the line")
	box.advance()
	assert_eq(box.index, 1)
	assert_eq(box._name.text, str(Profile.get_value(&"name")))
	box.advance()
	box.advance()
	assert_true(done[0] and not box.is_open(), "finished after the last line")


func test_chapter_one_plays_through() -> void:
	await _load()
	scene.start_story("ch1_graduation", true)
	var finished := []
	scene.story_director.chapter_finished.connect(func(c: Dictionary) -> void: finished.append(c["id"]))
	assert_eq(scene.find_children("*", "TrainingDummy", true, false).size(), 3, "chapter 1 keeps the dummies")
	assert_true(scene.story_director.npcs.has("hisame"), "Hisame is on stage")

	if _beat() != "task":
		await _await_beat("task")
	assert_true(player.input_enabled, "control returns for tasks")
	assert_true(scene.hud.objective().contains("kunai"), scene.hud.objective())
	for i in 2:
		player.throw_kunai()
		await physics_frames(40)
	await _await_beat("task")
	assert_eq(scene.story_director.task["jutsu"], &"ember_volley")
	player.caster.cast(JutsuRegistry.get_jutsu(&"ember_volley"))
	await _await_beat("task")
	assert_eq(scene.story_director.task["goal"], "weak_hit")
	var wind: TrainingDummy = scene.get_node("DummyWind")
	player.caster._cooldowns.clear()
	player.caster.cast(JutsuRegistry.get_jutsu(&"ember_volley"), wind)
	await physics_frames(60)
	await _await_beat("task")
	assert_eq(scene.story_director.task["goal"], "guard")
	Input.action_press(&"guard")
	await physics_frames(3)
	Input.action_release(&"guard")
	await _await_beat("fight")
	await physics_frames(ceili((TrialDirector.ANNOUNCE_TIME + EnemyShinobi.SPAWN_TIME) * 60.0) + 10)
	await _kill_all_enemies()
	for i in 600:
		await _talk_through()
		if not finished.is_empty():
			break
		await physics_frames(1)
	assert_eq(finished, ["ch1_graduation"], "chapter finished")
	assert_true(Game.chapter_done("ch1_graduation"))
	assert_true(scene.story.is_unlocked("ch2_rival"), "next chapter unlocked")
	await physics_frames(70)
	assert_true(scene.results.is_open(), "chapter complete panel")


func test_boss_changes_nature_summons_and_speaks() -> void:
	await _load()
	scene.start_story("ch5_kagerou", true)
	await physics_frames(2)
	_jump_to("boss")
	var boss: EnemyShinobi = scene.story_director.boss
	assert_true(boss != null and boss.is_boss())
	assert_true(scene.hud.boss_shown(), "boss bar")
	assert_near(boss.stats.max_health, 340.0)
	assert_eq(boss.element, Element.FIRE)
	await physics_frames(ceili(EnemyShinobi.SPAWN_TIME * 60.0) + 5)
	boss.take_hit(boss.stats.max_health * 0.25, Element.NONE, player)
	await physics_frames(2)
	assert_eq(boss.element, Element.WIND, "first phase: wind")
	assert_true(scene.hud.subtitle().contains("Wind"), scene.hud.subtitle())
	boss.take_hit(boss.stats.max_health * 0.25, Element.NONE, player)
	await physics_frames(2)
	assert_eq(boss.element, Element.LIGHTNING)
	assert_eq(scene.story_director.adds.size(), 1, "summoned a clone")
	var add: EnemyShinobi = scene.story_director.adds[0]
	boss.take_hit(99999.0, Element.NONE, player)
	await physics_frames(3)
	assert_true(add.is_defeated(), "clones vanish with the boss")
	assert_false(scene.hud.boss_shown())
	await physics_frames(90)
	assert_true(scene.dialogue.is_open(), "the story continues")


func test_losing_a_fight_retries_it() -> void:
	await _load()
	scene.start_story("ch2_rival", true)
	await physics_frames(2)
	_jump_to("boss")
	var first: EnemyShinobi = scene.story_director.boss
	var lost := [false]
	scene.story_director.fight_lost.connect(func() -> void: lost[0] = true)
	player.take_hit(1000.0, Element.NONE, null)
	assert_true(lost[0], "fight lost")
	await physics_frames(100)
	assert_true(scene.results.is_open(), "defeat panel")
	scene._on_results_primary()
	await physics_frames(2)
	assert_eq(player.state, Player.State.FREE, "back on your feet")
	assert_near(player.stats.health, player.stats.max_health)
	assert_false(is_instance_valid(first) and first.is_inside_tree(), "old boss cleared")
	assert_true(scene.story_director.boss != null and scene.story_director.boss != first, "boss fight restarted")
	assert_eq(_beat(), "boss")


func test_chapters_unlock_in_order() -> void:
	await _load()
	scene.show_title()
	scene.title_screen.show_chapters()
	await physics_frames(1)
	var buttons: Array = scene.title_screen.find_children("*", "Button", true, false)
	var locked: int = buttons.filter(func(b: Button) -> bool: return b.disabled).size()
	assert_eq(locked, 4, "only chapter 1 is open at first")
	Game.mark_chapter_done("ch1_graduation")
	scene.title_screen.show_chapters()
	await physics_frames(1)
	buttons = scene.title_screen.find_children("*", "Button", true, false)
	assert_eq(buttons.filter(func(b: Button) -> bool: return b.disabled).size(), 3)
	var chosen := []
	scene.title_screen.chapter_chosen.connect(func(id: String) -> void: chosen.append(id))
	scene.title_screen.chapter_chosen.disconnect(scene.start_story)
	var ch2: Button = buttons.filter(func(b: Button) -> bool: return b.text.contains("Lightning at Noon"))[0]
	ch2.pressed.emit()
	await physics_frames(1)
	assert_eq(chosen, ["ch2_rival"])


func test_night_relights_without_touching_the_scene_file() -> void:
	await _load()
	scene.set_time_of_day("night")
	assert_eq(scene.lantern_lights.size(), 6, "every lantern lit")
	assert_near(scene.get_node("Sun").light_energy, 0.35)
	var fresh := Scene.instantiate()
	var sky := (fresh.get_node("WorldEnvironment").environment.sky.sky_material as ProceduralSkyMaterial)
	assert_true(sky.sky_top_color.b > 0.5, "the shared sky resource is unchanged")
	fresh.free()
