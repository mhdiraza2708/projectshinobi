extends TestCase
## The menus read as finished: with the game's one main character the
## customize screen and new-game flow talk only about who the shinobi is
## (name, clan, dojutsu, jutsu), controller tab cycling skips the tabs that
## are gone, and focus stays put when a pick rebuilds a tab.

const Scene := preload("res://scenes/training_ground.tscn")
const TMP := "user://test_menu_polish"

var scene: Node3D
var _was_persist: Array = []


func before_each() -> void:
	_was_persist = [Profile.persist, Game.persist]
	SaveSlots.root = TMP
	SaveSlots.active = 0
	Profile.persist = false
	Game.persist = false
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
	Profile.reset()
	Game.reset_records()
	InputDevice.current = Binding.Device.KEYBOARD_MOUSE


func _creation() -> CustomizeMenu:
	var menu: CustomizeMenu = scene.customize_menu
	menu.open_creation()
	return menu


func _shoulder(menu: CustomizeMenu, button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	menu._input(e)


func _visible_tabs(menu: CustomizeMenu) -> Array[String]:
	var out: Array[String] = []
	for b: Button in menu._tab_row.get_children():
		if b.visible:
			out.append(b.text.get_slice(" ", 1))
	return out


func test_creation_runs_clan_dojutsu_identity_jutsu() -> void:
	await physics_frames(2)
	var menu := _creation()
	assert_true(CharacterModel.has_main(), "the main character ships with the game")
	assert_eq(_visible_tabs(menu), ["Clan", "Dojutsu", "Identity", "Jutsu"] as Array[String],
		"tabs sit in the order you choose them, with no look, colours or gear")
	assert_eq(menu._tabs.current_tab, CustomizeMenu.T_CLAN)
	menu.close()


func test_tabs_for_a_look_that_is_gone_are_not_built() -> void:
	await physics_frames(2)
	var menu := _creation()
	for tab in [CustomizeMenu.T_LOOK, CustomizeMenu.T_COLOURS, CustomizeMenu.T_GEAR]:
		var page := menu._tabs.get_child(tab) as ScrollContainer
		assert_eq(page.find_children("*", "Button", true, false).size(), 0, "nothing to pick on %s" % CustomizeMenu.TABS[tab][1])
		assert_eq(page.find_children("*", "Label", true, false).size(), 0, "no wardrobe text on %s" % CustomizeMenu.TABS[tab][1])
	menu.close()


func test_shoulder_buttons_cycle_only_the_tabs_on_offer() -> void:
	await physics_frames(2)
	var menu := _creation()
	var seen: Array[int] = []
	for i in 5:
		_shoulder(menu, JOY_BUTTON_RIGHT_SHOULDER)
		seen.append(menu._tabs.current_tab)
	assert_eq(seen, [CustomizeMenu.T_EYES, CustomizeMenu.T_IDENTITY, CustomizeMenu.T_JUTSU, CustomizeMenu.T_CLAN,
		CustomizeMenu.T_EYES] as Array[int], "RB walks Clan, Dojutsu, Identity, Jutsu and round")
	_shoulder(menu, JOY_BUTTON_LEFT_SHOULDER)
	_shoulder(menu, JOY_BUTTON_LEFT_SHOULDER)
	assert_eq(menu._tabs.current_tab, CustomizeMenu.T_JUTSU, "LB wraps back past the first tab")
	menu.close()


func test_controller_tab_hint_shows_only_on_a_controller() -> void:
	await physics_frames(2)
	var menu := _creation()
	assert_false(menu._tab_hint.visible, "no LB / RB hint on keyboard and mouse")
	InputDevice.current = Binding.Device.GAMEPAD
	InputDevice.device_changed.emit(InputDevice.current)
	assert_true(menu._tab_hint.visible, "LB / RB switch tabs, said on a pad")
	menu.close()


func test_header_seal_and_title_are_about_the_shinobi_not_gear() -> void:
	await physics_frames(2)
	var menu := _creation()
	assert_eq(menu._title.text, "NEW SHINOBI")
	assert_eq(menu._seal.text, "忍")
	menu.close()
	menu.open()
	assert_eq(menu._title.text, "CUSTOMIZE")
	assert_eq(menu._seal.text, "身", "not the gear seal while there is no gear to change")
	menu.close()


func test_begin_says_why_it_waits() -> void:
	await physics_frames(2)
	var menu := _creation()
	assert_true(menu._begin.disabled)
	assert_true(menu._begin_note.visible, "the reason is on screen, not only in a tooltip")
	assert_true("clan" in menu._begin_note.text)
	menu._pick_clan("gale")
	assert_false(menu._begin.disabled)
	assert_false(menu._begin_note.visible, "and gone once a clan is chosen")
	menu.close()


func test_identity_recaps_the_shinobi_you_have_built() -> void:
	await physics_frames(2)
	var menu := _creation()
	menu._pick_clan("gale")
	menu._pick_eye("seal_eye")
	menu._select_tab(CustomizeMenu.T_IDENTITY)
	var text := ""
	for l: Label in menu._tabs.get_current_tab_control().find_children("*", "Label", true, false):
		text += l.text + "\n"
	assert_true("Gale Clan" in text, "the clan")
	assert_true("Wind nature" in text, "the nature")
	assert_true("Dojutsu: Seal Eye" in text, "the dojutsu")
	assert_true("quick-cast slots filled" in text, "the loadout")
	menu.close()


func test_creation_text_no_longer_offers_a_look() -> void:
	await physics_frames(2)
	var menu := _creation()
	var all := ""
	for tab in [CustomizeMenu.T_CLAN, CustomizeMenu.T_EYES, CustomizeMenu.T_IDENTITY, CustomizeMenu.T_JUTSU]:
		menu._select_tab(tab)
		for l: Label in menu._tabs.get_current_tab_control().find_children("*", "Label", true, false):
			all += l.text + "\n"
	for word in ["colour of your", "gear", "outfit", "Colours tab", "Look tab"]:
		assert_false(word in all, "no leftover talk of '%s'" % word)
	menu.close()
	scene.show_title()
	scene.title_screen.show_main()
	var blurbs := ""
	for l: Label in scene.title_screen.find_children("*", "Label", true, false):
		blurbs += l.text + "\n"
	assert_true("name" in blurbs and not "look" in blurbs, "the title's New Game blurb names what you choose now")


func test_focus_stays_on_the_card_you_picked() -> void:
	await physics_frames(2)
	var menu := _creation()
	await physics_frames(2)
	var cards := menu._focusables(menu._tabs.get_current_tab_control())
	assert_true(cards.size() >= 3, "clan cards to pick from")
	cards[2].grab_focus()
	cards[2].pressed.emit()
	await physics_frames(3)
	var after := menu._focusables(menu._tabs.get_current_tab_control())
	assert_eq(menu.get_viewport().gui_get_focus_owner(), after[2],
		"the same place in the rebuilt list, not back at the first card")
	menu.close()
