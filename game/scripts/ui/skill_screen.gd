class_name SkillScreen
extends CanvasLayer
## The skills screen: your shinobi posed on a lit stage on the left
## (SkillStage), the tree on a sheet of paper on the right (SkillTreePanel),
## the four trees as tabs across the top. LB / RB (Q / E) switch trees,
## A learns, B backs out to the pause menu.

signal closed

var stage: SkillStage
var panel: SkillTreePanel

var _root: Control
var _tabs: Dictionary = {}
var _tree_name: Label
var _tree_kanji: Label
var _hints: HBoxContainer


func _init() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	add_child(_root)

	# The stage fills the screen; the paper sits over its right side.
	var view := SubViewportContainer.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.stretch = true
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(view)
	stage = SkillStage.new()
	view.add_child(stage)

	# A dark wash from the right edge so the paper reads against the stage.
	var wash := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.04, 0.06, 0.0))
	g.set_color(1, Color(0.05, 0.04, 0.06, 0.75))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.35, 0.0)
	gt.fill_to = Vector2(1.0, 0.0)
	wash.texture = gt
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(wash)

	# Top left: the screen's title and the tree's name over the stage.
	var title := VBoxContainer.new()
	title.add_theme_constant_override(&"separation", -6)
	title.position = Vector2(64, 40)
	_root.add_child(title)
	title.add_child(UiKit.label("技  SKILLS", 30, UiKit.PAPER, &"display", 4))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override(&"separation", 14)
	_tree_kanji = UiKit.label("", 92, UiKit.PAPER, &"brush", 6)
	name_row.add_child(_tree_kanji)
	_tree_name = UiKit.label("", 44, UiKit.PAPER, &"display", 5)
	_tree_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(_tree_name)
	title.add_child(name_row)

	# Right: the tabs, then the paper.
	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", 10)
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_top = 0.0
	right.anchor_bottom = 1.0
	right.offset_left = -1140
	right.offset_right = -48
	right.offset_top = 40
	right.offset_bottom = -96
	_root.add_child(right)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 6)
	right.add_child(tabs)
	tabs.add_child(_shoulder(JOY_BUTTON_LEFT_SHOULDER, KEY_Q))
	for t in SkillTrees.trees():
		var b := Button.new()
		b.text = "%s  %s" % [t["kanji"], str(t["name"]).trim_prefix("Way of ").trim_prefix("the ")]
		b.add_theme_font_size_override(&"font_size", 26)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_switch.bind(str(t["id"])))
		tabs.add_child(b)
		_tabs[t["id"]] = b
	tabs.add_child(_shoulder(JOY_BUTTON_RIGHT_SHOULDER, KEY_E))
	var paper := PaperPanel.new()
	paper.seed = 33.0
	paper.opacity = 0.97
	paper.tear = 4.0
	paper.margin = Vector4(40, 30, 40, 26)
	paper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(paper)
	panel = SkillTreePanel.new()
	panel.show_tabs = false
	panel.screen_mode = true
	paper.add_child(panel)
	panel.tree_changed.connect(_on_tree_changed)

	# A dark band along the bottom so the hints read over any stage.
	var band := TextureRect.new()
	var bg := Gradient.new()
	bg.set_color(0, Color(0.04, 0.03, 0.05, 0.0))
	bg.set_color(1, Color(0.04, 0.03, 0.05, 0.85))
	var bt := GradientTexture2D.new()
	bt.gradient = bg
	bt.fill_from = Vector2(0.0, 0.0)
	bt.fill_to = Vector2(0.0, 1.0)
	band.texture = bt
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.anchor_top = 1.0
	band.anchor_bottom = 1.0
	band.anchor_right = 1.0
	band.offset_top = -150
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(band)
	_hints = HBoxContainer.new()
	_hints.add_theme_constant_override(&"separation", 26)
	_hints.anchor_top = 1.0
	_hints.anchor_bottom = 1.0
	_hints.offset_left = 64
	_hints.offset_top = -78
	_hints.offset_bottom = -36
	_root.add_child(_hints)
	_refresh_hints()
	InputDevice.device_changed.connect(func(_d: Binding.Device) -> void: _refresh_hints())
	_on_tree_changed(panel.tree_id)


func _shoulder(button: JoyButton, key: Key) -> Control:
	var box := CenterContainer.new()
	box.custom_minimum_size = Vector2(44, 40)
	var glyph := InputGlyph.for_binding(Binding.joy_button(button) if InputDevice.current == Binding.Device.GAMEPAD
		else Binding.key(key), 30.0)
	box.add_child(glyph)
	return box


func _refresh_hints() -> void:
	for c in _hints.get_children():
		c.queue_free()
	var pad := InputDevice.current == Binding.Device.GAMEPAD
	for pair: Array in [["A" if pad else "Enter", "Learn"], ["LB / RB" if pad else "Q / E", "Switch tree"],
			["B" if pad else "Esc", "Back"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		row.add_child(UiKit.label(pair[0], 22, UiKit.GOLD, &"bold", 3))
		row.add_child(UiKit.label(pair[1], 22, UiKit.PAPER, &"bold", 3))
		_hints.add_child(row)


func open(tree := "") -> void:
	visible = true
	if tree != "":
		panel.show_tree(tree)
	else:
		panel.show_tree(panel.tree_id)
	panel.refresh()
	Sfx.ui(&"ui_open")


func close() -> void:
	visible = false
	Sfx.ui(&"ui_close")
	closed.emit()


func _switch(id: String) -> void:
	if id == panel.tree_id:
		return
	Sfx.ui(&"ui_move")
	panel.show_tree(id)


func _on_tree_changed(id: String) -> void:
	var t := SkillTrees.tree(id)
	var c := Color(str(t.get("color", "#c8553d")))
	_tree_kanji.text = str(t.get("kanji", ""))
	_tree_kanji.add_theme_color_override(&"font_color", c.lightened(0.25))
	_tree_name.text = str(t.get("name", "")).to_upper()
	for tid: String in _tabs:
		var b: Button = _tabs[tid]
		var tc := Color(str(SkillTrees.tree(tid)["color"]))
		var box := StyleBoxFlat.new()
		box.bg_color = Color(tc, 0.85) if tid == id else Color(0.08, 0.07, 0.09, 0.55)
		box.set_corner_radius_all(4)
		box.content_margin_left = 16
		box.content_margin_right = 16
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		for state: StringName in [&"normal", &"hover", &"pressed"]:
			b.add_theme_stylebox_override(state, box)
		b.add_theme_color_override(&"font_color", UiKit.PAPER if tid == id else Color(UiKit.PAPER, 0.7))
		b.add_theme_color_override(&"font_hover_color", UiKit.PAPER)
	if stage:
		stage.show_tree(id, stage.is_inside_tree())


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()
		return
	var step := 0
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			step = -1
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			step = 1
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q:
			step = -1
		elif event.physical_keycode == KEY_E:
			step = 1
	if step != 0:
		var ids: Array = SkillTrees.trees().map(func(t: Dictionary) -> String: return t["id"])
		_switch(ids[wrapi(ids.find(panel.tree_id) + step, 0, ids.size())])
		get_viewport().set_input_as_handled()
