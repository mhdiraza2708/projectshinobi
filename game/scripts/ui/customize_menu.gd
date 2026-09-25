class_name CustomizeMenu
extends CanvasLayer
## Character customization: roster, colours, ninja gear, body and identity.
## Changes apply live to the character (standing on the right, orbit with the
## right stick or a mouse drag) and are saved to the Profile immediately.
## Fully navigable with a controller: D-pad/stick to move, A to pick, LB/RB
## to switch tabs, B or Start to finish.

signal opened
signal closed

const TABS := [["姿", "Look"], ["色", "Colours"], ["装", "Gear"], ["名", "Identity"]]
## Multiplied onto the model's own colours, so each reads as a tint.
const PALETTE := [
	["Original", Color.WHITE], ["Ink", Color("2a2730")], ["Charcoal", Color("55545c")],
	["Snow", Color("f2f2f2")], ["Indigo", Color("4b5fb0")], ["Navy", Color("2c3a6e")],
	["Vermilion", Color("d9452e")], ["Crimson", Color("9e2430")], ["Rust", Color("b86a3c")],
	["Gold", Color("e3c05e")], ["Forest", Color("3f7d4e")], ["Moss", Color("8a9a4c")],
	["Teal", Color("3b9a9a")], ["Violet", Color("7a5bb0")], ["Plum", Color("7a3a64")],
	["Rose", Color("e39aac")], ["Sand", Color("d8c29a")], ["Ash", Color("a9a9b3")],
]
const EXPRESSION_LABELS := {
	"neutral": "Neutral", "angry": "Determined", "happy": "Cheerful", "relaxed": "Calm", "sad": "Somber",
}

var player: Player

var _root: Control
var _panel: PaperPanel
var _tabs: TabContainer
var _tab_buttons: Array[Button] = []
var _dragging := false


func _init() -> void:
	layer = 18


func bind(p: Player) -> void:
	player = p
	_build()
	_root.visible = false
	player.model.model_loaded.connect(func() -> void:
		if is_open():
			_rebuild_tabs())


func is_open() -> bool:
	return _root != null and _root.visible


func open() -> void:
	Sfx.ui(&"ui_open")
	_rebuild_tabs()
	_root.visible = true
	player.input_enabled = false
	player.camera_rig.begin_showcase()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_select_tab(0)
	_tab_buttons[0].grab_focus()
	opened.emit()


func close() -> void:
	if not is_open():
		return
	Sfx.ui(&"ui_close")
	_root.visible = false
	player.input_enabled = true
	player.camera_rig.end_showcase()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventJoypadButton and event.pressed:
		var step := 0
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			step = -1
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			step = 1
		if step != 0:
			_select_tab(wrapi(_tabs.current_tab + step, 0, _tabs.get_tab_count()))
			_tab_buttons[_tabs.current_tab].grab_focus()
			get_viewport().set_input_as_handled()
	# Drag anywhere off the panel to spin the character.
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_dragging = event.pressed and not _panel.get_global_rect().has_point(event.position)
	elif event is InputEventMouseMotion and _dragging:
		player.camera_rig.yaw -= event.relative.x * 0.01
		get_viewport().set_input_as_handled()


# --- Layout ------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.theme()
	add_child(_root)

	_panel = PaperPanel.new()
	_panel.seed = 33.0
	_panel.opacity = 0.97
	_panel.tear = 4.0
	_panel.margin = Vector4(40, 28, 40, 28)
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 40
	_panel.offset_top = 40
	_panel.offset_bottom = -40
	_panel.offset_right = 40 + 760
	_root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 12)
	_panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 16)
	header.add_child(Hanko.make("装", 70.0))
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override(&"separation", -8)
	titles.add_child(UiKit.label("身支度", 22, UiKit.INK_SOFT, &"brush"))
	titles.add_child(UiKit.label("CUSTOMIZE", 44, UiKit.CRIMSON, &"display"))
	header.add_child(titles)
	vbox.add_child(header)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override(&"separation", 4)
	vbox.add_child(tab_row)
	for i in TABS.size():
		var b := Button.new()
		b.text = "%s %s" % [TABS[i][0], TABS[i][1]]
		b.add_theme_font_size_override(&"font_size", 22)
		b.pressed.connect(_select_tab.bind(i))
		tab_row.add_child(b)
		_tab_buttons.append(b)
	vbox.add_child(_rule())

	_tabs = TabContainer.new()
	_tabs.tabs_visible = false
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	vbox.add_child(_tabs)

	vbox.add_child(_rule())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 12)
	vbox.add_child(footer)
	footer.add_child(_button("Done", close))
	footer.add_child(_button("Reset all", func() -> void:
		Profile.reset()
		_rebuild_tabs()))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	footer.add_child(InputGlyph.for_binding(Binding.joy_axis(JOY_AXIS_RIGHT_X, 1.0), 28.0))
	footer.add_child(UiKit.label("/ drag to rotate", 17, UiKit.INK_SOFT, &"bold"))


func _rebuild_tabs() -> void:
	var current := _tabs.current_tab if _tabs.get_tab_count() > 0 else 0
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_tabs.add_child(_scroll("Look", _build_look()))
	_tabs.add_child(_scroll("Colours", _build_colours()))
	_tabs.add_child(_scroll("Gear", _build_gear()))
	_tabs.add_child(_scroll("Identity", _build_identity()))
	_select_tab(clampi(current, 0, TABS.size() - 1))
	if is_open():
		# The control that had focus was rebuilt; keep controller users anchored.
		_refocus.call_deferred()


func _refocus() -> void:
	var owner := get_viewport().gui_get_focus_owner()
	if owner and owner.is_visible_in_tree():
		return
	for c in _tabs.get_current_tab_control().find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl.focus_mode == Control.FOCUS_ALL and ctl.is_visible_in_tree():
			ctl.grab_focus()
			return


func _select_tab(i: int) -> void:
	if _tabs.get_tab_count() > i:
		_tabs.current_tab = i
	for j in _tab_buttons.size():
		var active := j == i
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0)
		box.border_width_bottom = 4 if active else 0
		box.border_color = UiKit.CRIMSON
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		_tab_buttons[j].add_theme_stylebox_override(&"normal", box)
		_tab_buttons[j].add_theme_color_override(&"font_color", UiKit.INK if active else UiKit.INK_SOFT)


# --- Tabs ----------------------------------------------------------------------

func _build_look() -> Control:
	var list := _list()
	list.add_child(_section("Character"))
	var roster := VBoxContainer.new()
	var current := player.model.loaded_path
	for entry in CharacterModel.roster():
		var path: String = entry["path"]
		roster.add_child(_choice(entry["name"], path == current, func() -> void:
			Profile.set_value(&"model", path)
			_rebuild_tabs()))
	list.add_child(roster)
	list.add_child(_hint("Add more characters by exporting them from VRoid Studio into assets/characters/roster/."))

	list.add_child(_section("Height"))
	list.add_child(_slider(&"height", 0.9, 1.1, 0.01, "%.0f%%", 100.0))

	var available := Array(Profile.EXPRESSIONS)
	if player.model.expressions:
		available = available.filter(func(e: String) -> bool: return player.model.expressions.has_animation(e))
	if not available.is_empty():
		list.add_child(_section("Expression"))
		list.add_child(_choices(available.map(func(e: String) -> Array: return [EXPRESSION_LABELS.get(e, e.capitalize()), e]), &"expression"))
	return list


func _build_colours() -> Control:
	var list := _list()
	var slots := player.model.styler.available_slots()
	if slots.is_empty():
		list.add_child(_hint("This model has no recolourable materials."))
	for slot in slots:
		list.add_child(_section(CharacterStyler.SLOT_LABELS.get(slot, slot.capitalize())))
		list.add_child(_swatches(Profile.tint(slot), func(c: Color) -> void: Profile.set_tint(slot, c)))
	list.add_child(_hint("Colours tint the model's own textures: they can shift and darken, but not lighten."))
	return list


func _build_gear() -> Control:
	var list := _list()
	list.add_child(_section("Headband"))
	list.add_child(_choices([["None", "none"], ["Cloth", "cloth"], ["Hachigane", "hachigane"]], &"headband"))
	list.add_child(_swatches(Profile.get_value(&"headband_color"), func(c: Color) -> void: Profile.set_value(&"headband_color", c), false))

	list.add_child(_section("Face mask"))
	list.add_child(_choices([["Off", false], ["On", true]], &"mask"))
	list.add_child(_swatches(Profile.get_value(&"mask_color"), func(c: Color) -> void: Profile.set_value(&"mask_color", c), false))

	list.add_child(_section("Scarf"))
	list.add_child(_choices([["Off", false], ["On", true]], &"scarf"))
	list.add_child(_swatches(Profile.get_value(&"scarf_color"), func(c: Color) -> void: Profile.set_value(&"scarf_color", c), false))

	list.add_child(_section("Back"))
	list.add_child(_choices([["Nothing", "none"], ["Ninjato", "ninjato"]], &"back"))
	list.add_child(_section("Kunai pouch"))
	list.add_child(_choices([["Off", false], ["On", true]], &"pouch"))

	list.add_child(_section("Fit"))
	list.add_child(_labelled("Gear size", _slider(&"gear_scale", 0.85, 1.25, 0.01, "%.0f%%", 100.0, 300.0)))
	list.add_child(_labelled("Headband height", _slider(&"gear_lift", -0.15, 0.15, 0.01, "%+.0f", 100.0, 300.0)))
	list.add_child(_hint("Gear is fitted to each character's measured head and body; nudge it here if hair gets in the way."))
	return list


func _build_identity() -> Control:
	var list := _list()
	list.add_child(_section("Name"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var name_edit := LineEdit.new()
	name_edit.text = Profile.get_value(&"name")
	name_edit.max_length = 32
	name_edit.custom_minimum_size = Vector2(420, 46)
	name_edit.add_theme_font_override(&"font", UiKit.font(&"bold"))
	name_edit.add_theme_color_override(&"font_color", UiKit.INK)
	var edit_box := StyleBoxFlat.new()
	edit_box.bg_color = Color(UiKit.PAPER).darkened(0.05)
	edit_box.border_width_bottom = 2
	edit_box.border_color = UiKit.INK
	edit_box.content_margin_left = 10
	name_edit.add_theme_stylebox_override(&"normal", edit_box)
	name_edit.text_changed.connect(func(t: String) -> void:
		Profile.set_value(&"name", t.strip_edges() if not t.strip_edges().is_empty() else "Nameless"))
	row.add_child(name_edit)
	row.add_child(_button("Random", func() -> void:
		name_edit.text = Profile.random_name()
		Profile.set_value(&"name", name_edit.text)))
	list.add_child(row)

	list.add_child(_section("Chakra nature"))
	var natures := HBoxContainer.new()
	natures.add_theme_constant_override(&"separation", 8)
	for e in [Element.FIRE, Element.WIND, Element.LIGHTNING, Element.EARTH, Element.WATER]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(118, 110)
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		var stamp := Hanko.make(Element.kanji(e), 56.0, Element.color(e).darkened(0.35))
		stamp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(stamp)
		var l := UiKit.label(Element.display_name(e), 17, UiKit.INK, &"bold")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
		b.add_child(box)
		if int(Profile.get_value(&"affinity")) == e:
			b.add_theme_stylebox_override(&"normal", _selected_box())
		b.pressed.connect(func() -> void:
			Profile.set_value(&"affinity", e)
			_rebuild_tabs())
		natures.add_child(b)
	list.add_child(natures)
	list.add_child(_hint("Jutsu of your nature cost %d%% less chakra. Fire > Wind > Lightning > Earth > Water > Fire." \
		% roundi(JutsuCaster.AFFINITY_DISCOUNT * 100.0)))
	return list


# --- Widgets -------------------------------------------------------------------

func _list() -> VBoxContainer:
	var list := VBoxContainer.new()
	list.add_theme_constant_override(&"separation", 10)
	return list


func _scroll(title: String, content: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.name = title
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.follow_focus = true
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(content)
	return s


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(UiKit.INK, 0.25)
	r.custom_minimum_size = Vector2(0, 2)
	return r


func _section(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var mark := Hanko.make("", 12.0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	row.add_child(UiKit.label(title.to_upper(), 21, UiKit.CRIMSON, &"display"))
	return row


func _hint(text: String) -> Label:
	var l := UiKit.label(text, 16, UiKit.INK_SOFT, &"body")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 600
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	return b


func _selected_box() -> StyleBoxFlat:
	var on := StyleBoxFlat.new()
	on.bg_color = Color(UiKit.CRIMSON, 0.16)
	on.border_color = UiKit.CRIMSON
	on.set_border_width_all(2)
	on.content_margin_left = 14
	on.content_margin_right = 14
	on.content_margin_top = 6
	on.content_margin_bottom = 6
	return on


func _choice(text: String, is_selected: bool, on_pick: Callable) -> Button:
	var b := _button(text, on_pick)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if is_selected:
		b.add_theme_stylebox_override(&"normal", _selected_box())
	return b


## A row of mutually exclusive options bound to a Profile key.
func _choices(options: Array, key: StringName) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	for opt: Array in options:
		var value: Variant = opt[1]
		row.add_child(_choice(opt[0], Profile.get_value(key) == value, func() -> void:
			Profile.set_value(key, value)
			for c in row.get_children():
				(c as Button).remove_theme_stylebox_override(&"normal")
			(row.get_child(options.find(opt)) as Button).add_theme_stylebox_override(&"normal", _selected_box())))
	return row


func _swatches(current: Color, on_pick: Callable, allow_original := true) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override(&"h_separation", 4)
	grid.add_theme_constant_override(&"v_separation", 4)
	for entry in PALETTE:
		var color: Color = entry[1]
		if color == Color.WHITE and not allow_original:
			continue
		var sw := ColorSwatch.make(color, color.is_equal_approx(current), entry[0])
		sw.pressed.connect(func() -> void:
			on_pick.call(color)
			for c in grid.get_children():
				(c as ColorSwatch).selected = c == sw)
		grid.add_child(sw)
	return grid


func _slider(key: StringName, lo: float, hi: float, step: float, fmt: String, display_scale := 1.0, width := 420.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(width, 36)
	s.value = float(Profile.get_value(key))
	s.focus_mode = Control.FOCUS_ALL
	var readout := UiKit.label(fmt % (s.value * display_scale), 20, UiKit.CRIMSON_DARK, &"bold")
	readout.custom_minimum_size.x = 90
	s.value_changed.connect(func(v: float) -> void:
		readout.text = fmt % (v * display_scale)
		Profile.set_value(key, v))
	row.add_child(s)
	row.add_child(readout)
	return row


func _labelled(title: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := UiKit.label(title, 19, UiKit.INK, &"bold")
	l.custom_minimum_size.x = 210
	row.add_child(l)
	row.add_child(control)
	return row
