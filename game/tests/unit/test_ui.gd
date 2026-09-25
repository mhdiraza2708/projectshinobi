extends TestCase
## The ink-and-scroll UI: fonts, input icons, HUD weave panel, vitals, menu.

const Scene := preload("res://scenes/training_ground.tscn")


func after_each() -> void:
	InputDevice.current = Binding.Device.KEYBOARD_MOUSE
	InputDevice.gamepad_family = "xbox"
	root.get_tree().paused = false


func test_fonts_cover_every_kanji_the_ui_draws() -> void:
	var brush := UiKit.font(&"brush")
	var body := UiKit.font(&"body")
	for k in Seal.KANJI + Element.KANJI + PackedStringArray(["忍", "体", "気", "印", "術", "操", "作", "設", "定", "巻", "一", "時", "停", "止"]):
		assert_true(brush.has_char(k.unicode_at(0)), "brush font has %s" % k)
	for c in "Weave Strike › · — ×":
		assert_true(body.has_char(c.unicode_at(0)), "body font has '%s'" % c)


func test_every_binding_type_has_a_drawable_glyph() -> void:
	var samples := [
		Binding.key(KEY_SHIFT), Binding.key(KEY_W), Binding.mouse(MOUSE_BUTTON_RIGHT),
		Binding.joy_button(JOY_BUTTON_A), Binding.joy_button(JOY_BUTTON_LEFT_SHOULDER),
		Binding.joy_button(JOY_BUTTON_DPAD_UP), Binding.joy_button(JOY_BUTTON_START),
		Binding.joy_button(JOY_BUTTON_RIGHT_STICK), Binding.joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0),
		Binding.joy_axis(JOY_AXIS_LEFT_Y, -1.0),
	]
	for family in ["xbox", "playstation", "nintendo"]:
		InputDevice.gamepad_family = family
		for b: Dictionary in samples:
			var g := InputGlyph.for_binding(b, 32.0)
			root.add_child(g)
			var min_size := g.get_combined_minimum_size()
			assert_true(min_size.x >= 16.0 and min_size.y >= 30.0, "%s %s sized %s" % [family, Binding.label(b), min_size])
	await root.get_tree().process_frame  # draws every glyph once


func test_glyph_follows_active_device() -> void:
	var g := InputGlyph.for_action(&"weave")
	root.add_child(g)
	assert_eq(g.current_binding()["type"], Binding.TYPE_MOUSE)
	InputDevice.current = Binding.Device.GAMEPAD
	assert_eq(g.current_binding()["type"], Binding.TYPE_JOY_AXIS)


func test_ink_bar_trail_catches_up_after_damage() -> void:
	var bar := InkBar.new()
	root.add_child(bar)
	bar.set_ratio(0.5)
	assert_near(bar._trail, 1.0, 0.001, "trail holds the lost amount")
	bar._process(InkBar.TRAIL_DELAY + 2.0)
	assert_near(bar._trail, 0.5, 0.001, "trail caught up")


func test_weave_panel_stamps_one_talisman_per_seal() -> void:
	var scene := Scene.instantiate()
	root.add_child(scene)
	await physics_frames(3)
	var hud: Hud = scene.hud
	var player: Player = scene.player
	assert_false(hud._weave_panel.visible, "hidden until weaving")
	player.weaver.begin()
	player.weaver.add_seal(Seal.TIGER)
	player.weaver.add_seal(Seal.OX)
	await root.get_tree().process_frame
	assert_true(hud._weave_panel.visible)
	var talismans := hud._talismans.get_children().filter(
		func(c: Node) -> bool: return c is Talisman and not c.is_queued_for_deletion())
	var others := hud._talismans.get_children().filter(
		func(c: Node) -> bool: return not c is Talisman and not c.is_queued_for_deletion())
	assert_eq(talismans.size(), 2)
	assert_eq(others.size(), 0, "no leftover placeholder")
	assert_true(hud._hints.get_child_count() > 0, "Ember Volley shown as an exact match")
	player.weaver.finish()
	assert_false(hud._weave_panel.visible)


func test_menu_offers_both_devices_for_every_action() -> void:
	var scene := Scene.instantiate()
	root.add_child(scene)
	await root.get_tree().process_frame
	var menu: PauseMenu = scene.pause_menu
	menu.open()
	await root.get_tree().process_frame
	var buttons := menu._controls_list.find_children("*", "Button", true, false).filter(
		func(b: Node) -> bool: return b.has_meta(&"bind_key") and not b.is_queued_for_deletion())
	assert_eq(buttons.size(), DefaultBindings.table().size() * 2)
	menu.close()
