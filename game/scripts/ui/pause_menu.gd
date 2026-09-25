class_name PauseMenu
extends CanvasLayer
## Pause menu: rebinding for both devices, accessibility options, and the
## jutsu scroll (every technique, its seals for your device, quick-cast slot
## assignment). Fully navigable with a controller: D-pad/stick to move,
## A to select, B to back out, LB/RB to switch tabs.

var player: Player

var _root: Control
var _tabs: TabContainer
var _controls_list: VBoxContainer
var _jutsu_list: VBoxContainer
var _notice: Label
var _resume: Button
## {action, device, button} while waiting for a new input.
var _capture: Dictionary = {}
var _capture_started := 0


func _init() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS


func bind(p: Player) -> void:
	player = p
	_build()
	_root.visible = false
	Settings.bindings_changed.connect(_refresh_controls)
	InputDevice.device_changed.connect(func(_d: Binding.Device) -> void: _refresh_jutsu())
	player.quick_slots_changed.connect(_refresh_jutsu)


func is_open() -> bool:
	return _root != null and _root.visible


func open() -> void:
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_controls()
	_refresh_jutsu()
	_resume.grab_focus()


func close() -> void:
	_cancel_capture()
	_root.visible = false
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not _capture.is_empty():
		return
	if event.is_action_pressed(&"pause"):
		if is_open():
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif is_open() and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if not _capture.is_empty():
		_handle_capture(event)
		return
	# Shoulder buttons flip tabs.
	if event is InputEventJoypadButton and event.pressed:
		var step := 0
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			step = -1
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			step = 1
		if step != 0:
			_tabs.current_tab = wrapi(_tabs.current_tab + step, 0, _tabs.get_tab_count())
			_focus_first(_tabs.get_current_tab_control())
			get_viewport().set_input_as_handled()


# --- Layout ------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1240, 860)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 12)
	panel.add_child(vbox)
	var header := HBoxContainer.new()
	header.add_child(UiKit.label("PAUSED", 40, UiKit.ACCENT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(UiKit.label("LB / RB: switch tabs", 20, UiKit.MUTED))
	vbox.add_child(header)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_tabs)
	_tabs.add_child(_scroll("Controls", _build_controls()))
	_tabs.add_child(_scroll("Accessibility", _build_accessibility()))
	_tabs.add_child(_scroll("Jutsu Scroll", _build_jutsu()))

	_notice = UiKit.label("", 20, UiKit.MUTED)
	vbox.add_child(_notice)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 12)
	vbox.add_child(buttons)
	_resume = _button("Resume", close)
	buttons.add_child(_resume)
	buttons.add_child(_button("Reset controls", func() -> void:
		Settings.reset_bindings()
		_notice.text = "Controls reset to defaults."))
	buttons.add_child(_button("Reset options", func() -> void:
		Settings.reset_values()
		_tabs.get_child(1).queue_free()
		var fresh := _scroll("Accessibility", _build_accessibility())
		_tabs.add_child(fresh)
		_tabs.move_child(fresh, 1)
		_notice.text = "Options reset to defaults."))
	buttons.add_child(_button("Quit", func() -> void: get_tree().quit()))


func _scroll(title: String, content: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.name = title
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.follow_focus = true
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(content)
	return s


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	return b


func _focus_first(node: Node) -> void:
	for c in node.find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl.focus_mode == Control.FOCUS_ALL and ctl.is_visible_in_tree():
			ctl.grab_focus()
			return


# --- Controls tab --------------------------------------------------------------

func _build_controls() -> Control:
	_controls_list = VBoxContainer.new()
	_controls_list.add_theme_constant_override(&"separation", 6)
	_refresh_controls()
	return _controls_list


func _refresh_controls() -> void:
	if _controls_list == null:
		return
	var focused := get_viewport().gui_get_focus_owner()
	var refocus := ""
	if focused and focused.has_meta(&"bind_key"):
		refocus = focused.get_meta(&"bind_key")
	for c in _controls_list.get_children():
		c.queue_free()

	var header := HBoxContainer.new()
	header.add_child(_cell(UiKit.label("Action", 20, UiKit.MUTED), 460))
	header.add_child(_cell(UiKit.label("Keyboard / Mouse", 20, UiKit.MUTED), 300))
	header.add_child(_cell(UiKit.label("Controller", 20, UiKit.MUTED), 300))
	_controls_list.add_child(header)

	var table := DefaultBindings.table()
	var group := ""
	for action: StringName in table:
		var entry: Dictionary = table[action]
		if entry["group"] != group:
			group = entry["group"]
			var g := UiKit.label(group.to_upper(), 20, UiKit.ACCENT)
			_controls_list.add_child(g)
		var row := HBoxContainer.new()
		row.add_child(_cell(UiKit.label(entry["label"], 22), 460))
		for device in [Binding.Device.KEYBOARD_MOUSE, Binding.Device.GAMEPAD]:
			var b := Button.new()
			b.custom_minimum_size = Vector2(290, 44)
			b.text = InputDevice.glyph_for_device(action, device)
			b.set_meta(&"bind_key", "%s/%d" % [action, device])
			b.pressed.connect(_start_capture.bind(action, device, b))
			row.add_child(_cell(b, 300))
			if refocus == b.get_meta(&"bind_key"):
				b.call_deferred(&"grab_focus")
		_controls_list.add_child(row)


func _cell(control: Control, width: float) -> Control:
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, width - 10)
	return control


func _start_capture(action: StringName, device: Binding.Device, button: Button) -> void:
	_capture = {"action": action, "device": device, "button": button}
	_capture_started = Time.get_ticks_msec()
	button.text = "Press a key… (Esc cancels)" if device == Binding.Device.KEYBOARD_MOUSE \
		else "Press a button… (View/Back cancels)"


func _handle_capture(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if not event.is_pressed() or event.is_echo():
		return
	# Ignore the tail of the press that opened the capture.
	if Time.get_ticks_msec() - _capture_started < 150:
		return
	var device: Binding.Device = _capture["device"]
	var is_pad := event is InputEventJoypadButton or event is InputEventJoypadMotion
	var is_kbm := event is InputEventKey or event is InputEventMouseButton
	if (event is InputEventKey and event.physical_keycode == KEY_ESCAPE) \
			or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_BACK):
		_cancel_capture()
		return
	if (device == Binding.Device.GAMEPAD and not is_pad) or (device == Binding.Device.KEYBOARD_MOUSE and not is_kbm):
		return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return
	var binding := Binding.from_event(event)
	if binding.is_empty():
		return
	var action: StringName = _capture["action"]
	_capture = {}
	var swapped := Settings.set_binding(action, device, binding)
	var table := DefaultBindings.table()
	_notice.text = "%s → %s" % [table[action]["label"], Binding.label(binding, InputDevice.gamepad_family)]
	if swapped != &"":
		_notice.text += "   (swapped with %s)" % table[swapped]["label"]


func _cancel_capture() -> void:
	if _capture.is_empty():
		return
	_capture = {}
	_refresh_controls()


# --- Accessibility tab -----------------------------------------------------------

func _build_accessibility() -> Control:
	var list := VBoxContainer.new()
	list.add_theme_constant_override(&"separation", 10)

	var weave := OptionButton.new()
	weave.add_item("Hold (release to cast)")
	weave.add_item("Toggle (press again to cast)")
	weave.selected = 0 if Settings.get_value(&"weave_mode") == "hold" else 1
	weave.item_selected.connect(func(i: int) -> void: Settings.set_value(&"weave_mode", "hold" if i == 0 else "toggle"))
	list.add_child(_option_row("Weave mode", weave))

	var no_limit := CheckButton.new()
	no_limit.text = "No time limit between seals"
	no_limit.button_pressed = float(Settings.get_value(&"seal_timeout_scale")) == 0.0
	var window := _slider(&"seal_timeout_scale", 0.5, 3.0, 0.25, "%.2f×")
	window.editable = not no_limit.button_pressed
	no_limit.toggled.connect(func(on: bool) -> void:
		window.editable = not on
		Settings.set_value(&"seal_timeout_scale", 0.0 if on else maxf(window.value, 0.5)))
	list.add_child(_option_row("Seal timing window", window))
	list.add_child(_option_row("", no_limit))

	list.add_child(_option_row("Seal hints while weaving", _toggle(&"seal_hints")))
	list.add_child(_option_row("Quick-cast weave speed (s/seal)", _slider(&"auto_weave_seal_time", 0.08, 0.4, 0.02, "%.2fs")))
	list.add_child(_option_row("Mouse sensitivity", _slider(&"mouse_sensitivity", 0.2, 3.0, 0.1, "%.1f")))
	list.add_child(_option_row("Stick sensitivity", _slider(&"stick_sensitivity", 0.2, 3.0, 0.1, "%.1f")))
	list.add_child(_option_row("Invert camera Y", _toggle(&"invert_y")))
	list.add_child(_option_row("Stick deadzone", _slider(&"stick_deadzone", 0.05, 0.5, 0.05, "%.2f")))
	list.add_child(_option_row("Controller vibration", _toggle(&"vibration")))
	list.add_child(_option_row("Screen shake", _slider(&"screen_shake", 0.0, 1.0, 0.1, "%.0f%%", 100.0)))
	list.add_child(_option_row("UI scale", _slider(&"ui_scale", 0.75, 1.5, 0.05, "%.2f×")))
	return list


func _option_row(title: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_cell(UiKit.label(title, 22), 520))
	row.add_child(control)
	if control.has_meta(&"readout"):
		row.add_child(control.get_meta(&"readout"))
	return row


func _toggle(key: StringName) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = bool(Settings.get_value(key))
	c.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	return c


## Slider with a live value readout. `display_scale` multiplies the value in
## the readout only (e.g. 100 to show a percentage).
func _slider(key: StringName, lo: float, hi: float, step: float, fmt: String, display_scale := 1.0) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(380, 36)
	s.value = clampf(float(Settings.get_value(key)), lo, hi)
	s.focus_mode = Control.FOCUS_ALL
	var readout := UiKit.label(fmt % (s.value * display_scale), 22, UiKit.MUTED)
	readout.custom_minimum_size.x = 110
	s.value_changed.connect(func(v: float) -> void:
		readout.text = fmt % (v * display_scale)
		if s.editable:
			Settings.set_value(key, v))
	s.set_meta(&"readout", readout)
	return s


# --- Jutsu tab -----------------------------------------------------------------

func _build_jutsu() -> Control:
	_jutsu_list = VBoxContainer.new()
	_jutsu_list.add_theme_constant_override(&"separation", 8)
	_refresh_jutsu()
	return _jutsu_list


func _refresh_jutsu() -> void:
	if _jutsu_list == null or player == null:
		return
	for c in _jutsu_list.get_children():
		c.queue_free()
	_jutsu_list.add_child(UiKit.label(
		"Seals shown for your current device. Use the 1-4 buttons to put a jutsu on a quick-cast slot.",
		20, UiKit.MUTED))
	for j in JutsuRegistry.all():
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UiKit.label("%s   %s" % [j.display_name, UiKit.jutsu_tag(j)], 22,
			Element.color(j.element).lightened(0.35)))
		info.add_child(UiKit.label("%s      %s" % [" › ".join(j.seal_names()), UiKit.sequence_glyphs(j.seals)], 20))
		if j.description != "":
			info.add_child(UiKit.label(j.description, 18, UiKit.MUTED))
		row.add_child(info)
		for slot in 4:
			var b := Button.new()
			b.text = str(slot + 1)
			b.custom_minimum_size = Vector2(52, 44)
			b.tooltip_text = "Put on quick-cast slot %d" % (slot + 1)
			if player.quick_slots[slot] == j.id:
				b.add_theme_color_override(&"font_color", UiKit.ACCENT)
				b.text = "[%d]" % (slot + 1)
			b.pressed.connect(func() -> void:
				player.assign_quick_slot(slot, j.id)
				_notice.text = "%s is now on quick-cast slot %d." % [j.display_name, slot + 1])
			row.add_child(b)
		_jutsu_list.add_child(row)
