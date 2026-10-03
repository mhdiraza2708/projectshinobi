class_name PauseMenu
extends CanvasLayer
## Pause menu, styled as a hanging scroll: rebinding for both devices,
## accessibility options, graphics, the jutsu scroll (every technique, its
## seals for your device, and the loadout editor: presets and the eight
## quick-cast slots) and the skill trees. Fully navigable with a
## controller: D-pad/stick to move, A to select, B to back out, LB/RB to
## switch tabs.

const TABS := [["操作", "Controls"], ["設定", "Accessibility"], ["画", "Graphics"], ["巻", "Jutsu Scroll"], ["技", "Skills"]]
const TAB_ACCESSIBILITY := 1
const TAB_GRAPHICS := 2
const TAB_JUTSU := 3
const TAB_SKILLS := 4

signal customize_requested
signal title_requested

var player: Player

var _root: Control
## HUDs hidden while the menu is open (to show again on close).
var _hidden_huds: Array[CanvasLayer] = []
var _tabs: TabContainer
var _tab_buttons: Array[Button] = []
var _tab_hint: HBoxContainer
var _controls_list: VBoxContainer
var _jutsu_list: VBoxContainer
var _jutsu_panel: LoadoutPanel
var _skills: SkillTreePanel
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
	InputDevice.device_changed.connect(func(_d: Binding.Device) -> void:
		_refresh_jutsu()
		_tab_hint.visible = InputDevice.current == Binding.Device.GAMEPAD)


func is_open() -> bool:
	return _root != null and _root.visible


func open() -> void:
	Sfx.ui(&"ui_open")
	_root.visible = true
	get_tree().paused = true
	# The HUD would show around the edges of the scroll.
	_hidden_huds.clear()
	for hud in get_tree().root.find_children("*", "Hud", true, false):
		if (hud as CanvasLayer).visible:
			(hud as CanvasLayer).visible = false
			_hidden_huds.append(hud)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_tab_hint.visible = InputDevice.current == Binding.Device.GAMEPAD
	_refresh_controls()
	_refresh_jutsu()
	_skills.refresh()
	_resume.grab_focus()


func close() -> void:
	_cancel_capture()
	if _root.visible:
		Sfx.ui(&"ui_close")
	_root.visible = false
	get_tree().paused = false
	for hud in _hidden_huds:
		if is_instance_valid(hud):
			hud.visible = true
	_hidden_huds.clear()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not _capture.is_empty():
		return
	# During a cutscene or an ultimate, Pause is held to skip instead.
	if (Cutscene.active != null or UltimateSequence.active != null or EyeSequence.active != null) and not is_open():
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
			_select_tab(wrapi(_tabs.current_tab + step, 0, _tabs.get_tab_count()))
			_focus_first(_tabs.get_current_tab_control())
			get_viewport().set_input_as_handled()


# --- Layout ------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(UiKit.INK, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var scroll := VBoxContainer.new()
	scroll.add_theme_constant_override(&"separation", -6)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	scroll.grow_horizontal = Control.GROW_DIRECTION_BOTH
	scroll.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(scroll)
	scroll.add_child(_roller())
	var paper := PaperPanel.new()
	paper.seed = 21.0
	paper.opacity = 0.99
	paper.tear = 3.0
	paper.margin = Vector4(48, 26, 48, 26)
	paper.custom_minimum_size = Vector2(1240, 820)
	scroll.add_child(paper)
	scroll.add_child(_roller())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 12)
	paper.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 16)
	header.add_child(Hanko.make("忍", 70.0))
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override(&"separation", -8)
	titles.add_child(UiKit.label("一時停止", 22, UiKit.INK_SOFT, &"brush"))
	titles.add_child(UiKit.label("PAUSED", 46, UiKit.CRIMSON, &"display"))
	header.add_child(titles)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_tab_hint = HBoxContainer.new()
	_tab_hint.add_theme_constant_override(&"separation", 6)
	_tab_hint.add_child(InputGlyph.for_binding(Binding.joy_button(JOY_BUTTON_LEFT_SHOULDER), 30.0))
	_tab_hint.add_child(InputGlyph.for_binding(Binding.joy_button(JOY_BUTTON_RIGHT_SHOULDER), 30.0))
	_tab_hint.add_child(UiKit.label("switch tabs", 18, UiKit.INK_SOFT, &"bold"))
	header.add_child(_tab_hint)
	vbox.add_child(header)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override(&"separation", 8)
	vbox.add_child(tab_row)
	for i in TABS.size():
		var b := Button.new()
		b.text = "%s  %s" % [TABS[i][0], TABS[i][1]]
		b.add_theme_font_size_override(&"font_size", 24)
		b.pressed.connect(_select_tab.bind(i))
		tab_row.add_child(b)
		_tab_buttons.append(b)
	vbox.add_child(_rule())

	_tabs = TabContainer.new()
	_tabs.tabs_visible = false
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	vbox.add_child(_tabs)
	_tabs.add_child(_scroll("Controls", _build_controls()))
	_tabs.add_child(_scroll("Accessibility", _build_accessibility()))
	_tabs.add_child(_scroll("Graphics", _build_graphics()))
	_tabs.add_child(_scroll("Jutsu Scroll", _build_jutsu()))
	_skills = SkillTreePanel.new()
	_tabs.add_child(_scroll("Skills", _skills))
	_select_tab(0)

	vbox.add_child(_rule())
	_notice = UiKit.label("", 19, UiKit.CRIMSON_DARK, &"bold")
	vbox.add_child(_notice)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 14)
	vbox.add_child(buttons)
	_resume = _button("Resume", close)
	buttons.add_child(_resume)
	buttons.add_child(_button("Customize", func() -> void:
		close()
		customize_requested.emit()))
	buttons.add_child(_button("Reset controls", func() -> void:
		Settings.reset_bindings()
		_notice.text = "Controls reset to defaults."))
	buttons.add_child(_button("Reset options", func() -> void:
		Settings.reset_values()
		_rebuild_tab(TAB_ACCESSIBILITY)
		_rebuild_tab(TAB_GRAPHICS)
		_notice.text = "Options reset to defaults."))
	buttons.add_child(_button("Title screen", func() -> void:
		close()
		title_requested.emit()))
	buttons.add_child(_button("Quit", func() -> void: get_tree().quit()))


func _roller() -> Control:
	var bar := Panel.new()
	bar.custom_minimum_size = Vector2(1300, 28)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var wood := StyleBoxFlat.new()
	wood.bg_color = UiKit.WOOD
	wood.set_corner_radius_all(14)
	wood.border_width_bottom = 4
	wood.border_color = Color(UiKit.WOOD).darkened(0.45)
	bar.add_theme_stylebox_override(&"panel", wood)
	for side in [0.0, 1.0]:
		var knob := Panel.new()
		knob.size = Vector2(34, 34)
		knob.position = Vector2(side * (1300 - 34), -3)
		var k := StyleBoxFlat.new()
		k.bg_color = UiKit.GOLD
		k.set_corner_radius_all(17)
		k.set_border_width_all(3)
		k.border_color = Color(UiKit.WOOD).darkened(0.3)
		knob.add_theme_stylebox_override(&"panel", k)
		bar.add_child(knob)
	return bar


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(UiKit.INK, 0.25)
	r.custom_minimum_size = Vector2(0, 2)
	return r


func _select_tab(i: int) -> void:
	_tabs.current_tab = i
	for j in _tab_buttons.size():
		var active := j == i
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0)
		box.border_width_bottom = 4 if active else 0
		box.border_color = UiKit.CRIMSON
		box.content_margin_left = 14
		box.content_margin_right = 14
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		_tab_buttons[j].add_theme_stylebox_override(&"normal", box)
		_tab_buttons[j].add_theme_color_override(&"font_color", UiKit.INK if active else UiKit.INK_SOFT)


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


func _section(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var mark := Hanko.make("", 12.0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	row.add_child(UiKit.label(title.to_upper(), 22, UiKit.CRIMSON, &"display"))
	return row


# --- Controls tab --------------------------------------------------------------

func _build_controls() -> Control:
	_controls_list = VBoxContainer.new()
	_controls_list.add_theme_constant_override(&"separation", 6)
	_refresh_controls()
	return _controls_list


func _refresh_controls() -> void:
	if _controls_list == null:
		return
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var refocus := ""
	if focused and focused.has_meta(&"bind_key"):
		refocus = focused.get_meta(&"bind_key")
	for c in _controls_list.get_children():
		c.queue_free()

	var header := HBoxContainer.new()
	header.add_child(_cell(UiKit.label("Action", 18, UiKit.INK_SOFT, &"bold"), 470))
	header.add_child(_cell(UiKit.label("Keyboard / Mouse", 18, UiKit.INK_SOFT, &"bold"), 310))
	header.add_child(_cell(UiKit.label("Controller", 18, UiKit.INK_SOFT, &"bold"), 310))
	_controls_list.add_child(header)

	var table := DefaultBindings.table()
	var group := ""
	for action: StringName in table:
		var entry: Dictionary = table[action]
		if entry["group"] != group:
			group = entry["group"]
			_controls_list.add_child(_section(group))
		var row := HBoxContainer.new()
		row.add_child(_cell(UiKit.label(entry["label"], 21, UiKit.INK, &"bold"), 470))
		for device in [Binding.Device.KEYBOARD_MOUSE, Binding.Device.GAMEPAD]:
			var b := Button.new()
			b.custom_minimum_size = Vector2(300, 48)
			var glyph := InputGlyph.for_action(action, 32.0, device)
			b.add_child(glyph)
			glyph.set_anchors_preset(Control.PRESET_CENTER)
			glyph.grow_horizontal = Control.GROW_DIRECTION_BOTH
			glyph.grow_vertical = Control.GROW_DIRECTION_BOTH
			b.set_meta(&"glyph", glyph)
			b.set_meta(&"bind_key", "%s/%d" % [action, device])
			b.tooltip_text = InputDevice.glyph_for_device(action, device)
			b.pressed.connect(_start_capture.bind(action, device, b))
			row.add_child(_cell(b, 310))
			if refocus == b.get_meta(&"bind_key"):
				b.call_deferred(&"grab_focus")
		_controls_list.add_child(row)


func _cell(control: Control, width: float) -> Control:
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, width - 10)
	return control


func _start_capture(action: StringName, device: Binding.Device, button: Button) -> void:
	_capture = {"action": action, "device": device, "button": button}
	_capture_started = Time.get_ticks_msec()
	(button.get_meta(&"glyph") as Control).visible = false
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

	list.add_child(_section("Seal weaving"))
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

	list.add_child(_section("Camera and controller"))
	list.add_child(_option_row("Mouse sensitivity", _slider(&"mouse_sensitivity", 0.2, 3.0, 0.1, "%.1f")))
	list.add_child(_option_row("Stick sensitivity", _slider(&"stick_sensitivity", 0.2, 3.0, 0.1, "%.1f")))
	list.add_child(_option_row("Invert camera Y", _toggle(&"invert_y")))
	list.add_child(_option_row("Stick deadzone", _slider(&"stick_deadzone", 0.05, 0.5, 0.05, "%.2f")))
	list.add_child(_option_row("Controller vibration", _toggle(&"vibration")))

	list.add_child(_section("Display"))
	list.add_child(_option_row("Screen shake", _slider(&"screen_shake", 0.0, 1.0, 0.1, "%.0f%%", 100.0)))
	list.add_child(_option_row("UI scale", _slider(&"ui_scale", 0.75, 1.5, 0.05, "%.2f×")))
	list.add_child(_hint_row("Resolution, quality and the window are under Graphics."))

	list.add_child(_section("Audio"))
	list.add_child(_option_row("Master volume", _slider(&"master_volume", 0.0, 1.0, 0.05, "%.0f%%", 100.0)))
	list.add_child(_option_row("Effects volume", _slider(&"sfx_volume", 0.0, 1.0, 0.05, "%.0f%%", 100.0)))
	list.add_child(_option_row("Menu sounds volume", _slider(&"ui_volume", 0.0, 1.0, 0.05, "%.0f%%", 100.0)))
	list.add_child(_option_row("Music volume", _slider(&"music_volume", 0.0, 1.0, 0.05, "%.0f%%", 100.0)))
	list.add_child(_option_row("Voice volume", _slider(&"voice_volume", 0.0, 1.0, 0.05, "%.0f%%", 100.0)))
	return list


# --- Graphics tab ----------------------------------------------------------------

func _build_graphics() -> Control:
	var list := VBoxContainer.new()
	list.add_theme_constant_override(&"separation", 10)

	list.add_child(_section("Preset"))
	var preset := _choice(&"graphics_preset", Graphics.PRESET_ORDER,
		["Low (fastest)", "Medium", "High", "Ultra (cinematic)", "Custom"], func(v: Variant) -> void:
			if str(v) != "custom":
				Graphics.apply_preset(str(v))
				_rebuild_tab.call_deferred(TAB_GRAPHICS, true))
	preset.name = "Preset"
	list.add_child(_option_row("Quality preset", preset))
	list.add_child(_hint_row("A preset sets everything under Quality. Change any of those and it becomes Custom."))

	list.add_child(_section("Display"))
	list.add_child(_option_row("Window", _choice(&"window_mode", Graphics.WINDOW_MODES,
		["Windowed", "Borderless fullscreen", "Exclusive fullscreen"])))
	list.add_child(_option_row("VSync", _toggle(&"vsync")))
	var caps: Array = []
	for c in Graphics.FPS_CAPS:
		caps.append(c)
	list.add_child(_option_row("Frame rate cap", _choice(&"max_fps", caps,
		Graphics.FPS_CAPS.map(func(c: int) -> String: return "Unlimited" if c == 0 else "%d FPS" % c))))
	list.add_child(_option_row("Brightness", _slider(&"brightness", 0.6, 1.5, 0.05, "%.0f%%", 100.0)))
	list.add_child(_option_row("Field of view", _slider(&"fov", 55.0, 100.0, 1.0, "%.0f°")))

	list.add_child(_section("Quality"))
	var scale := _slider(&"render_scale", 0.5, 1.0, 0.05, "%.0f%%", 100.0)
	scale.value_changed.connect(func(_v: float) -> void: _mark_custom())
	list.add_child(_option_row("Render resolution (FSR)" if Graphics.supported() else "Render resolution", scale))
	list.add_child(_option_row("Anti-aliasing", _quality_choice(&"anti_aliasing", Graphics.AA_MODES,
		["Off", "FXAA (soft, fast)", "MSAA 2×", "MSAA 4×", "TAA (smoothest)"])))
	list.add_child(_option_row("Shadows", _quality_choice(&"shadow_quality", Graphics.SHADOW_LEVELS, ["Low", "Medium", "High"])))
	var lighting := _quality_choice(&"graphics_quality", Graphics.LEVELS,
		Array(Graphics.LEVELS).map(func(l: String) -> String: return Graphics.LABELS[l]))
	if not Graphics.supported():
		lighting.disabled = true
		lighting.tooltip_text = "Needs the Vulkan renderer (Forward+)"
	list.add_child(_option_row("Lighting", lighting))
	for pair in [[&"ambient_occlusion", "Ambient occlusion"], [&"bloom", "Bloom (glow)"]]:
		var t := _toggle(pair[0])
		t.toggled.connect(func(_on: bool) -> void: _mark_custom())
		list.add_child(_option_row(pair[1], t))
	var rt := _toggle(&"ray_tracing")
	if not RayTracing.available():
		# Shown off without saving it off: the same save may move to a PC that has one.
		rt.disabled = true
		rt.set_pressed_no_signal(false)
		rt.text = "Needs a ray tracing GPU"
	list.add_child(_option_row("Ray-traced shadows (RTAO)", rt))
	return list


## An OptionButton for `key` over `values` (shown as `labels`).
func _choice(key: StringName, values: Array, labels: Array, on_change := Callable()) -> OptionButton:
	var o := OptionButton.new()
	for l: String in labels:
		o.add_item(l)
	o.selected = maxi(0, values.find(Settings.get_value(key)))
	o.item_selected.connect(func(i: int) -> void:
		Settings.set_value(key, values[i])
		if on_change.is_valid():
			on_change.call(values[i]))
	return o


## A choice under Quality: changing it makes the preset Custom (unless it
## happens to match one).
func _quality_choice(key: StringName, values: Array, labels: Array) -> OptionButton:
	return _choice(key, values, labels, func(_v: Variant) -> void: _mark_custom())


func _mark_custom() -> void:
	Settings.set_value(&"graphics_preset", Graphics.matching_preset())
	var tab := _tabs.get_child(TAB_GRAPHICS) if _tabs and _tabs.get_child_count() > TAB_GRAPHICS else null
	var preset := tab.find_child("Preset", true, false) as OptionButton if tab else null
	if preset:
		preset.select(Graphics.PRESET_ORDER.find(str(Settings.get_value(&"graphics_preset"))))


## Rebuilds tab `i` in place (after a reset or a preset changes its values).
func _rebuild_tab(i: int, keep_focus := false) -> void:
	var was := _tabs.current_tab
	var old := _tabs.get_child(i)
	var title := old.name
	var fresh := _scroll(title, _build_graphics() if i == TAB_GRAPHICS else _build_accessibility())
	_tabs.remove_child(old)
	old.queue_free()
	_tabs.add_child(fresh)
	_tabs.move_child(fresh, i)
	# Removing the open tab switches tabs: put the player back where they were.
	_select_tab(was)
	if keep_focus:
		var preset := fresh.find_child("Preset", true, false) as Control
		if preset:
			preset.grab_focus.call_deferred()


func _hint_row(text: String) -> Label:
	var l := UiKit.label(text, 18, UiKit.INK_SOFT, &"body")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _option_row(title: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_cell(UiKit.label(title, 21, UiKit.INK, &"bold"), 520))
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
	var readout := UiKit.label(fmt % (s.value * display_scale), 21, UiKit.CRIMSON_DARK, &"bold")
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
	_jutsu_list.add_theme_constant_override(&"separation", 10)
	_jutsu_list.add_child(_hint_label())
	_jutsu_panel = LoadoutPanel.new(true)
	_jutsu_list.add_child(_jutsu_panel)
	return _jutsu_list


func _hint_label() -> Label:
	var l := UiKit.label("", 18, UiKit.INK_SOFT, &"bold")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 900
	l.set_meta(&"is_hint", true)
	return l


## Seals are shown for the device in use; the quick-cast keys follow the
## bindings.
func _refresh_jutsu() -> void:
	if _jutsu_list == null or player == null:
		return
	(_jutsu_list.get_child(0) as Label).text = \
		"Quick-cast with %s – %s. On a controller the D-pad casts slots 1–4; hold %s and it casts 5–8 (%s flips the pages for good). %s / %s switch loadout. Seals are shown for the device you're using." % [
			InputDevice.glyph(&"quick_cast_1"), InputDevice.glyph(&"quick_cast_8"),
			InputDevice.glyph_for_device(&"quick_shift", Binding.Device.GAMEPAD), InputDevice.glyph(&"quick_page"),
			InputDevice.glyph(&"preset_prev"), InputDevice.glyph(&"preset_next")]
	_jutsu_panel.refresh()
