extends TestCase
## The start of a game: the title's Continue / New Game / Load Game and slot
## cards, and character creation (clan, eye art, nature, Begin / Back).

const Scene := preload("res://scenes/training_ground.tscn")
const TMP := "user://test_new_game"

var scene: Node3D
var _was_persist: Array = []


func before_each() -> void:
	_was_persist = [Profile.persist, Game.persist]
	_wipe(TMP)
	SaveSlots.root = TMP
	SaveSlots.active = 0
	Profile.persist = true
	Game.persist = true
	Profile.reset()
	Game.reset_records()
	scene = Scene.instantiate()
	root.add_child(scene)


func after_each() -> void:
	if scene:
		scene.queue_free()
		scene = null
	SaveSlots.root = "user://saves"
	SaveSlots.active = 0
	Profile.persist = _was_persist[0]
	Game.persist = _was_persist[1]
	_wipe(TMP)
	Profile.reset()
	Game.reset_records()
	Game.tracking = false


static func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _titles() -> PackedStringArray:
	var out := PackedStringArray()
	for b: Button in scene.title_screen.find_children("*", "Button", true, false):
		out.append(b.text.get_slice("   ", 1) if "   " in b.text else b.text)
	return out


func _saved_game(slot: int, character := "Kaze") -> void:
	SaveSlots.create(slot)
	Profile.set_value(&"name", character)
	Profile.set_value(&"created", true)
	Profile.set_value(&"clan", "gale")


func test_title_without_saves_offers_a_new_game_only() -> void:
	await physics_frames(2)
	scene.show_title()
	await physics_frames(2)
	var titles := _titles()
	assert_true(titles.has("New Game"), "a new game")
	assert_true(titles.has("Training Ground") and titles.has("Trial of the Five Natures"), "the open modes")
	for hidden in ["Continue", "Load Game", "Chapters", "Customize"]:
		assert_false(titles.has(hidden), "no %s without a save" % hidden)


func test_title_with_a_save_offers_continue_load_and_chapters() -> void:
	_saved_game(1)
	await physics_frames(2)
	scene.show_title()
	await physics_frames(2)
	var titles := _titles()
	for shown in ["Continue", "New Game", "Load Game", "Chapters", "Customize"]:
		assert_true(titles.has(shown), shown)


func test_slot_cards_list_three_slots_and_confirm_an_overwrite() -> void:
	_saved_game(1, "Kaze")
	_saved_game(3, "Rin")
	await physics_frames(2)
	scene.show_title()
	var title: TitleScreen = scene.title_screen
	title.show_slots(true)
	assert_true(title.showing_slots())
	var started: Array[int] = []
	title.new_game_chosen.connect(func(slot: int) -> void: started.append(slot))
	var cards := title.find_children("*", "Button", true, false).filter(
		func(b: Button) -> bool: return b.custom_minimum_size.y >= 100.0)
	assert_eq(cards.size(), SaveSlots.COUNT, "one card per slot")
	title._slot_pressed(1, true)
	assert_true(started.is_empty(), "an occupied slot asks before it is overwritten")
	assert_false(title.showing_slots(), "the question is showing")
	title.show_slots(true)
	title._slot_pressed(2, true)
	assert_eq(started, [2] as Array[int], "an empty slot starts at once")


func test_loading_an_occupied_slot_resumes_it() -> void:
	_saved_game(2, "Rin")
	await physics_frames(2)
	scene.show_title()
	var title: TitleScreen = scene.title_screen
	var loaded: Array[int] = []
	title.continue_chosen.connect(func(slot: int) -> void: loaded.append(slot))
	title.show_slots(false)
	title._slot_pressed(2, false)
	assert_eq(loaded, [2] as Array[int])


func test_deleting_a_save_asks_first_then_removes_it() -> void:
	_saved_game(1)
	_saved_game(2, "Rin")
	await physics_frames(2)
	scene.show_title()
	var title: TitleScreen = scene.title_screen
	title.show_slots(false)
	title._ask_delete(1, false)
	assert_true(SaveSlots.exists(1), "still there until confirmed")
	title._delete_slot(1, false)
	assert_false(SaveSlots.exists(1), "gone")
	assert_true(SaveSlots.exists(2), "the other save is untouched")
	assert_true(title.showing_slots(), "back on the list while saves remain")
	title._delete_slot(2, false)
	assert_false(title.showing_slots(), "no saves left: back on the main page")


func test_new_game_opens_creation_in_a_fresh_slot() -> void:
	_saved_game(1)
	await physics_frames(2)
	scene.show_title()
	scene.title_screen.new_game_chosen.emit(2)
	var menu: CustomizeMenu = scene.customize_menu
	assert_eq(SaveSlots.active, 2, "playing in the new slot")
	assert_true(menu.is_open() and menu.creating, "character creation")
	assert_false(scene.title_screen.is_open())
	assert_eq(Profile.get_value(&"clan"), "", "no clan yet")
	assert_true(menu._begin.disabled, "Begin waits for a clan")
	assert_eq(menu._tabs.current_tab, CustomizeMenu.T_CLAN, "the clan is chosen first")
	assert_true(Profile.get_value(&"name") != "Nameless", "a starting name is suggested")


func test_choosing_a_clan_sets_your_nature_and_unlocks_begin() -> void:
	await physics_frames(2)
	scene.show_title()
	scene.title_screen.new_game_chosen.emit(1)
	var menu: CustomizeMenu = scene.customize_menu
	menu._pick_clan("stonewright")
	assert_eq(int(Profile.get_value(&"affinity")), Element.EARTH, "the clan fixes the nature")
	assert_false(menu._begin.disabled, "Begin unlocked")
	menu._pick_eye("still_eye")
	assert_eq(Profile.get_value(&"eye_art"), "still_eye")
	menu._pick_clan("gale")
	assert_eq(Profile.get_value(&"eye_art"), "", "Gale can't take Still Eye: it is dropped")
	assert_eq(int(Profile.get_value(&"affinity")), Element.WIND)
	menu._pick_clan("wayfarer")
	assert_eq(int(Profile.get_value(&"affinity")), Element.WIND, "a Wayfarer keeps whatever nature they had")


func test_nature_is_locked_to_the_clan_except_for_wayfarers() -> void:
	await physics_frames(2)
	scene.show_title()
	scene.title_screen.new_game_chosen.emit(1)
	var menu: CustomizeMenu = scene.customize_menu
	menu._pick_clan("tidebound")
	menu._select_tab(CustomizeMenu.T_IDENTITY)
	var natures := menu._tabs.get_current_tab_control().find_children("*", "Button", true, false).filter(
		func(b: Button) -> bool: return b.custom_minimum_size == Vector2(118, 110))
	assert_eq(natures.size(), 5)
	var open := natures.filter(func(b: Button) -> bool: return not b.disabled)
	assert_eq(open.size(), 1, "only the clan's own nature")
	menu._pick_clan("wayfarer")
	menu._select_tab(CustomizeMenu.T_IDENTITY)
	natures = menu._tabs.get_current_tab_control().find_children("*", "Button", true, false).filter(
		func(b: Button) -> bool: return b.custom_minimum_size == Vector2(118, 110))
	assert_eq(natures.filter(func(b: Button) -> bool: return not b.disabled).size(), 5, "Wayfarers choose")


func test_eye_art_tab_only_offers_what_the_clan_allows() -> void:
	await physics_frames(2)
	scene.show_title()
	scene.title_screen.new_game_chosen.emit(1)
	var menu: CustomizeMenu = scene.customize_menu
	menu._select_tab(CustomizeMenu.T_EYES)
	assert_eq(menu._tabs.get_current_tab_control().find_children("*", "Button", true, false).size(), 0,
		"no clan, no eye arts")
	menu._pick_clan("hearth")
	menu._select_tab(CustomizeMenu.T_EYES)
	var cards := menu._tabs.get_current_tab_control().find_children("*", "Button", true, false)
	assert_eq(cards.size(), 1 + Perks.arts_for("hearth").size(), "none, plus the clan's own arts")


func test_begin_starts_chapter_one_and_marks_the_character_created() -> void:
	await physics_frames(2)
	scene.show_title()
	scene.title_screen.new_game_chosen.emit(1)
	var menu: CustomizeMenu = scene.customize_menu
	menu._pick_clan("hearth")
	menu._begin.pressed.emit()
	assert_true(bool(Profile.get_value(&"created")), "creation is finished")
	assert_false(menu.is_open())
	assert_eq(scene.mode, Game.Mode.STORY, "the story begins")
	assert_true(scene.hud.visible, "with the HUD back")
	assert_true(Game.tracking, "and play time counting")
	var meta := SaveSlots.meta(1)
	assert_true(meta["created"] and meta["clan"] == "hearth", "the slot card shows the new shinobi")


func test_backing_out_of_creation_abandons_the_new_game() -> void:
	_saved_game(1)
	await physics_frames(2)
	scene.show_title()
	scene.title_screen.new_game_chosen.emit(2)
	assert_true(SaveSlots.exists(2))
	scene.customize_menu._back.pressed.emit()
	assert_false(SaveSlots.exists(2), "the empty slot is cleared again")
	assert_true(SaveSlots.exists(1), "other saves are untouched")
	assert_true(scene.title_screen.is_open(), "back on the title")


func test_continue_picks_up_at_the_first_chapter_not_cleared() -> void:
	_saved_game(1)
	Game.mark_chapter_done("ch1_graduation")
	await physics_frames(2)
	scene.show_title()
	var story: Story = Story.load_all()
	assert_eq(story.resume_chapter()["id"], story.chapters[1]["id"], "chapter two is next")
	scene.title_screen.continue_chosen.emit(1)
	assert_eq(scene.mode, Game.Mode.STORY)
	for c in story.chapters:
		Game.mark_chapter_done(c["id"])
	assert_true(story.resume_chapter().is_empty(), "a finished story has nowhere to resume")


func test_an_unfinished_character_goes_back_to_creation() -> void:
	SaveSlots.create(1)
	await physics_frames(2)
	scene.show_title()
	scene.title_screen.continue_chosen.emit(1)
	assert_true(scene.customize_menu.is_open() and scene.customize_menu.creating)


func test_reset_look_keeps_who_you_are() -> void:
	await physics_frames(2)
	scene.show_title()
	scene.title_screen.new_game_chosen.emit(1)
	var menu: CustomizeMenu = scene.customize_menu
	menu._pick_clan("gale")
	menu._pick_eye("seal_eye")
	Profile.set_value(&"mask", true)
	Loadouts.rename(0, "Mine")
	menu._reset_look()
	assert_false(bool(Profile.get_value(&"mask")), "the look is back to default")
	assert_eq(Profile.get_value(&"clan"), "gale")
	assert_eq(Profile.get_value(&"eye_art"), "seal_eye")
	assert_eq(Loadouts.active()["name"], "Mine", "loadouts survive")


func test_the_pause_menu_still_customizes_without_creation_buttons() -> void:
	_saved_game(1)
	await physics_frames(2)
	scene.customize_menu.open()
	assert_false(scene.customize_menu.creating)
	assert_false(scene.customize_menu._begin.visible, "no Begin outside creation")
	assert_true(scene.customize_menu._done.visible)
	scene.customize_menu.close()
