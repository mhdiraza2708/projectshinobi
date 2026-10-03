class_name CustomizeMenu
extends CanvasLayer
## Character customization: roster, colours, ninja gear, body and identity,
## plus the clan, eye art and jutsu loadouts that shape how you fight.
## Changes apply live to the character (standing on the right, orbit with the
## right stick or a mouse drag) and are saved to the Profile immediately.
## Fully navigable with a controller: D-pad/stick to move, A to pick, LB/RB
## to switch tabs, B or Start to finish.
##
## `open_creation()` runs it as the start of a new game: the tabs come in the
## order you'd choose them (clan first), and Begin / Back replace Done.

signal opened
signal closed
## Creation only: the character is chosen, start the story.
signal begun
## Creation only: backed out; the new game should be abandoned.
signal cancelled

const TABS := [["姿", "Look"], ["色", "Colours"], ["装", "Gear"], ["名", "Identity"],
	["族", "Clan"], ["眼", "Eyes"], ["術", "Jutsu"]]
const T_LOOK := 0
const T_COLOURS := 1
const T_GEAR := 2
const T_IDENTITY := 3
const T_CLAN := 4
const T_EYES := 5
const T_JUTSU := 6
## The order the tabs sit in during creation (what you decide first, first).
const CREATION_ORDER := [T_CLAN, T_EYES, T_IDENTITY, T_LOOK, T_COLOURS, T_GEAR, T_JUTSU]
## What "Reset look" leaves alone: who you are, not how you look.
const KEPT_ON_RESET: Array[StringName] = [&"created", &"clan", &"eye_art", &"loadouts", &"loadout", &"affinity", &"name"]
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
var _tab_row: HFlowContainer
var _dragging := false
var creating := false
var _title: Label
var _subtitle: Label
var _done: Button
var _reset: Button
var _begin: Button
var _back: Button


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
	_open(false)


## The first screen of a new game: choose clan, eye art, name, look and jutsu.
func open_creation() -> void:
	_open(true)


func _open(for_creation: bool) -> void:
	creating = for_creation
	Sfx.ui(&"ui_open")
	_apply_mode()
	_rebuild_tabs()
	_root.visible = true
	player.input_enabled = false
	player.camera_rig.begin_showcase()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var first: int = CREATION_ORDER[0] if creating else T_LOOK
	_select_tab(first)
	_tab_buttons[first].grab_focus()
	opened.emit()


## Tab order, title and footer for the current mode.
func _apply_mode() -> void:
	var order: Array = CREATION_ORDER if creating else range(TABS.size())
	for pos in order.size():
		_tab_row.move_child(_tab_buttons[order[pos]], pos)
	_subtitle.text = "旅立ち" if creating else "身支度"
	_title.text = "NEW SHINOBI" if creating else "CUSTOMIZE"
	_done.visible = not creating
	_reset.visible = true
	_begin.visible = creating
	_back.visible = creating
	_update_footer()


func _update_footer() -> void:
	if _begin == null:
		return
	var chosen: bool = Profile.get_value(&"clan") != ""
	_begin.disabled = not chosen
	_begin.tooltip_text = "" if chosen else "Choose a clan first (Clan tab)"


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
	if not is_open() or creating:
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
			var order: Array = CREATION_ORDER if creating else range(TABS.size())
			var next: int = order[wrapi(order.find(_tabs.current_tab) + step, 0, order.size())]
			_select_tab(next)
			_tab_buttons[next].grab_focus()
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
	_panel.offset_right = 40 + 860
	_root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 12)
	_panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 16)
	header.add_child(Hanko.make("装", 70.0))
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override(&"separation", -8)
	_subtitle = UiKit.label("身支度", 22, UiKit.INK_SOFT, &"brush")
	titles.add_child(_subtitle)
	_title = UiKit.label("CUSTOMIZE", 44, UiKit.CRIMSON, &"display")
	titles.add_child(_title)
	header.add_child(titles)
	vbox.add_child(header)

	# A flow, so a long tab list wraps instead of running off the paper.
	_tab_row = HFlowContainer.new()
	_tab_row.add_theme_constant_override(&"h_separation", 2)
	_tab_row.add_theme_constant_override(&"v_separation", 0)
	vbox.add_child(_tab_row)
	for i in TABS.size():
		var b := Button.new()
		b.text = "%s %s" % [TABS[i][0], TABS[i][1]]
		b.add_theme_font_size_override(&"font_size", 21)
		b.pressed.connect(_select_tab.bind(i))
		_tab_row.add_child(b)
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
	_begin = _button("Begin", func() -> void:
		close()
		begun.emit())
	_begin.add_theme_font_size_override(&"font_size", 28)
	_begin.add_theme_color_override(&"font_color", UiKit.CRIMSON)
	footer.add_child(_begin)
	_back = _button("Back", func() -> void:
		close()
		cancelled.emit())
	_back.tooltip_text = "Abandon this new game"
	footer.add_child(_back)
	_done = _button("Done", close)
	footer.add_child(_done)
	_reset = _button("Reset look", _reset_look)
	_reset.tooltip_text = "Back to the default look. Your clan, eye art, name and jutsu stay."
	footer.add_child(_reset)
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
	_tabs.add_child(_scroll("Clan", _build_clan()))
	_tabs.add_child(_scroll("Eyes", _build_eyes()))
	_tabs.add_child(_scroll("Jutsu", _build_jutsu()))
	_select_tab(clampi(current, 0, TABS.size() - 1))
	_update_footer()
	if is_open():
		# The control that had focus was rebuilt; keep controller users anchored.
		_refocus.call_deferred()


func _reset_look() -> void:
	var kept := {}
	for key in KEPT_ON_RESET:
		kept[key] = Profile.get_value(key)
	Profile.reset()
	for key in kept:
		Profile.set_value(key, kept[key])
	_rebuild_tabs()


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
	list.add_child(_section("Face & body"))
	var current := player.model.loaded_path
	var roster := CharacterModel.roster()
	list.add_child(_pick_grid(roster.map(func(e: Dictionary) -> Array: return [e["name"], e["path"]]), current,
		func(path: String) -> void:
			Profile.set_value(&"model", path)
			_rebuild_tabs()))

	# Hair and outfit from any other VRoid-built character.
	var parts := roster.filter(func(e: Dictionary) -> bool: return e["path"] != CharacterModel.PLACEHOLDER_MODEL)
	var options: Array = [["Own", ""]]
	options.append_array(parts.map(func(e: Dictionary) -> Array: return [e["name"], e["path"]]))
	if player.model.swappable:
		list.add_child(_section("Hair"))
		list.add_child(_pick_grid(options, Profile.get_value(&"hair_from"), func(path: String) -> void:
			Profile.set_value(&"hair_from", path)
			_rebuild_tabs()))
		list.add_child(_section("Outfit"))
		list.add_child(_pick_grid(options, Profile.get_value(&"outfit_from"), func(path: String) -> void:
			Profile.set_value(&"outfit_from", path)
			_rebuild_tabs()))
		list.add_child(_hint("Hair and outfits are the real VRoid parts of each character, fitted to yours. Recolour them on the Colours tab."))
	else:
		list.add_child(_hint("This character's hair and clothes are one piece, so they can't be swapped. Pick a VRoid character to mix and match."))
	list.add_child(_hint("Add your own characters by exporting them from VRoid Studio into assets/characters/roster/."))

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
	var fixed := Perks.clan_element(Profile.get_value(&"clan"))
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
		# A clan fixes your nature; only Wayfarers (and old saves) choose.
		b.disabled = fixed != Element.NONE and e != fixed
		b.pressed.connect(func() -> void:
			Profile.set_value(&"affinity", e)
			_rebuild_tabs())
		natures.add_child(b)
	list.add_child(natures)
	list.add_child(_hint(("Your clan fixes your nature. Wayfarers choose their own. " if fixed != Element.NONE else "")
		+ "Jutsu of your nature cost %d%% less chakra. Fire > Wind > Lightning > Earth > Water > Fire." \
		% roundi(JutsuCaster.AFFINITY_DISCOUNT * 100.0)))
	return list


func _build_clan() -> Control:
	var list := _list()
	list.add_child(_section("Clan"))
	var current: String = Profile.get_value(&"clan")
	for clan in Perks.clans():
		var element := Perks.clan_element(clan["id"])
		var tag := "%s nature" % Element.display_name(element) if element != Element.NONE else "Any nature"
		list.add_child(_card(clan["kanji"], Color(clan["color"]), clan["name"], tag, clan["blurb"],
			Perks.describe(clan["perks"]), clan["id"] == current, _pick_clan.bind(clan["id"])))
	list.add_child(_hint("Your clan sets your chakra nature and which eye arts you may take. Every clan here is original to this game. You can change it later from Customize."))
	return list


func _pick_clan(id: String) -> void:
	Profile.set_value(&"clan", id)
	var element := Perks.clan_element(id)
	if element != Element.NONE:
		Profile.set_value(&"affinity", element)
	# An eye art the new clan can't take is dropped.
	if Perks.active_eye_art().is_empty():
		Profile.set_value(&"eye_art", "")
	_rebuild_tabs()


func _build_eyes() -> Control:
	var list := _list()
	list.add_child(_section("Eye art"))
	var clan_id: String = Profile.get_value(&"clan")
	if clan_id == "":
		list.add_child(_hint("Choose a clan first: each clan can awaken only some eye arts."))
		return list
	var current: String = Profile.get_value(&"eye_art")
	list.add_child(_card("無", UiKit.INK_SOFT, "No eye art", "Plain eyes", "Nothing awakened: you rely on your clan and your hands.",
		PackedStringArray(), current == "", _pick_eye.bind("")))
	for art in Perks.arts_for(clan_id):
		var lines := Perks.describe(art["perks"])
		# Opened in battle, and the form it awakens into.
		lines.append("Open in battle (%s + %s): %s" % [InputDevice.glyph(&"quick_shift"),
			InputDevice.glyph(&"charge_chakra"), art["active"]["name"]])
		lines.append(("Awakened: %s" if EyeArtMode.awakening_unlocked() else "Awakens after Part One: %s")
			% art["awakened"]["name"])
		list.add_child(_card(art["kanji"], Color(art["color"]), art["name"], "Eye art", art["blurb"],
			lines, art["id"] == current, _pick_eye.bind(art["id"])))
	list.add_child(_hint("Your eyes change colour with your eye art. Eye arts are original to this game: they sharpen how you aim, dodge, guard or read seals."))
	return list


func _pick_eye(id: String) -> void:
	Profile.set_value(&"eye_art", id)
	_rebuild_tabs()


func _build_jutsu() -> Control:
	var list := _list()
	list.add_child(_hint("Loadouts fill your eight quick-cast slots (%s – %s). Make as many as %d and swap between them in battle with %s / %s."
		% [InputDevice.glyph(&"quick_cast_1"), InputDevice.glyph(&"quick_cast_8"), Loadouts.MAX_PRESETS,
		InputDevice.glyph(&"preset_prev"), InputDevice.glyph(&"preset_next")]))
	list.add_child(LoadoutPanel.new(false))
	return list


# --- Widgets -------------------------------------------------------------------

## A tall selectable card: stamp, name, tag, blurb and what it grants.
func _card(kanji: String, color: Color, title: String, tag: String, blurb: String, perks: PackedStringArray,
		is_selected: bool, on_pick: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 138)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_pick)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(UiKit.CRIMSON, 0.1)
	focus.border_color = UiKit.CRIMSON
	focus.set_border_width_all(3)
	b.add_theme_stylebox_override(&"focus", focus)
	if is_selected:
		b.add_theme_stylebox_override(&"normal", _selected_box())
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -16
	row.offset_top = 8
	row.offset_bottom = -8
	row.add_theme_constant_override(&"separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var stamp := Hanko.make(kanji, 68.0, color.darkened(0.25))
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stamp)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override(&"separation", 2)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 12)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(UiKit.label(title, 24, UiKit.INK, &"display"))
	var tag_label := UiKit.label(tag, 16, UiKit.INK_SOFT, &"bold")
	tag_label.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(tag_label)
	text.add_child(head)
	var blurb_label := UiKit.label(blurb, 16, UiKit.INK_SOFT, &"body")
	blurb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(blurb_label)
	if not perks.is_empty():
		var perk_label := UiKit.label("  ·  ".join(perks), 16, UiKit.CRIMSON_DARK, &"bold")
		perk_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(perk_label)
	for child in text.find_children("*", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


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
	l.custom_minimum_size.x = 400
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


## A grid of mutually exclusive choices [[label, value]]; `on_pick(value)`.
func _pick_grid(options: Array, current: Variant, on_pick: Callable) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 6)
	for opt: Array in options:
		var value: Variant = opt[1]
		var b := _choice(opt[0], value == current, func() -> void: on_pick.call(value))
		b.custom_minimum_size.x = 220
		b.clip_text = true
		grid.add_child(b)
	return grid


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
