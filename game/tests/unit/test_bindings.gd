extends TestCase
## Guards the "fully playable on keyboard/mouse AND controller" requirement.


func test_every_action_has_keyboard_mouse_and_gamepad_bindings() -> void:
	for action: StringName in DefaultBindings.table():
		assert_false(Settings.get_bindings_for_device(action, Binding.Device.KEYBOARD_MOUSE).is_empty(),
			"%s has a keyboard/mouse binding" % action)
		assert_false(Settings.get_bindings_for_device(action, Binding.Device.GAMEPAD).is_empty(),
			"%s has a gamepad binding" % action)


func test_every_action_is_registered_in_input_map() -> void:
	for action: StringName in DefaultBindings.table():
		assert_true(InputMap.has_action(action), "%s in InputMap" % action)
		assert_eq(InputMap.action_get_events(action).size(), Settings.get_bindings(action).size(),
			"%s events" % action)


func test_no_default_conflicts_within_a_context() -> void:
	for action: StringName in DefaultBindings.table():
		for b in Settings.get_bindings(action):
			assert_eq(Settings.find_conflict(action, b), &"",
				"%s's %s clashes" % [action, Binding.label(b)])


func test_menus_are_navigable_by_gamepad() -> void:
	for action in [&"ui_accept", &"ui_cancel", &"ui_up", &"ui_down", &"ui_left", &"ui_right"]:
		var has_pad := InputMap.action_get_events(action).any(
			func(e: InputEvent) -> bool: return e is InputEventJoypadButton or e is InputEventJoypadMotion)
		assert_true(has_pad, "%s has a gamepad event" % action)


func test_binding_serialization_round_trips() -> void:
	var samples := [
		Binding.key(KEY_F), Binding.mouse(MOUSE_BUTTON_RIGHT),
		Binding.joy_button(JOY_BUTTON_Y), Binding.joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0),
		Binding.joy_axis(JOY_AXIS_LEFT_Y, -1.0),
	]
	for b: Dictionary in samples:
		assert_true(Binding.equals(Binding.from_event(Binding.to_event(b)), b), Binding.label(b))


func test_small_stick_wobble_is_not_capturable() -> void:
	var m := InputEventJoypadMotion.new()
	m.axis = JOY_AXIS_LEFT_X
	m.axis_value = 0.2
	assert_true(Binding.from_event(m).is_empty())


func test_rebinding_swaps_on_conflict() -> void:
	# Put Jump on the key Guard uses: Guard should inherit Jump's old key.
	var guard_key: Dictionary = Settings.get_bindings_for_device(&"guard", Binding.Device.KEYBOARD_MOUSE)[0]
	var jump_key: Dictionary = Settings.get_bindings_for_device(&"jump", Binding.Device.KEYBOARD_MOUSE)[0]
	var swapped := Settings.set_binding(&"jump", Binding.Device.KEYBOARD_MOUSE, guard_key)
	assert_eq(swapped, &"guard")
	assert_true(Binding.equals(Settings.get_bindings_for_device(&"jump", Binding.Device.KEYBOARD_MOUSE)[0], guard_key))
	assert_true(Binding.equals(Settings.get_bindings_for_device(&"guard", Binding.Device.KEYBOARD_MOUSE)[0], jump_key))
	# Gamepad bindings are untouched.
	assert_false(Settings.get_bindings_for_device(&"jump", Binding.Device.GAMEPAD).is_empty())
	test_no_default_conflicts_within_a_context()


func test_weaving_inputs_may_overlap_field_inputs() -> void:
	# S is both Move Back and the bottom seal; that's intended (different contexts).
	assert_eq(Settings.find_conflict(&"seal_down", Binding.key(KEY_S)), &"")
	# But two seal inputs can't share a key.
	assert_eq(Settings.find_conflict(&"seal_down", Binding.key(KEY_W)), &"seal_up")


func test_reset_restores_defaults() -> void:
	Settings.set_binding(&"attack", Binding.Device.GAMEPAD, Binding.joy_button(JOY_BUTTON_LEFT_SHOULDER))
	Settings.reset_bindings()
	var pad: Array = Settings.get_bindings_for_device(&"attack", Binding.Device.GAMEPAD)
	assert_true(Binding.equals(pad[0], Binding.joy_button(JOY_BUTTON_X)))


func test_deadzone_setting_applies_to_sticks() -> void:
	Settings.set_value(&"stick_deadzone", 0.33)
	assert_near(InputMap.action_get_deadzone(&"move_forward"), 0.33)
	assert_near(InputMap.action_get_deadzone(&"look_left"), 0.33)


func test_gamepad_family_detection() -> void:
	assert_eq(InputDevice.family_for("PS5 Controller"), "playstation")
	assert_eq(InputDevice.family_for("Sony Interactive Entertainment DualSense Wireless Controller"), "playstation")
	assert_eq(InputDevice.family_for("Nintendo Switch Pro Controller"), "nintendo")
	assert_eq(InputDevice.family_for("Xbox Series Controller"), "xbox")
	assert_eq(InputDevice.family_for("Generic USB Joystick"), "xbox")


func test_glyph_labels_follow_family() -> void:
	var bottom := Binding.joy_button(JOY_BUTTON_A)
	assert_eq(Binding.label(bottom, "xbox"), "A")
	assert_eq(Binding.label(bottom, "playstation"), "Cross")
	assert_eq(Binding.label(bottom, "nintendo"), "B")
	assert_eq(Binding.label(Binding.joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0), "playstation"), "L2")
	assert_eq(Binding.label(Binding.mouse(MOUSE_BUTTON_RIGHT)), "RMB")
