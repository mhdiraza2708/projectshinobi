class_name TitleScreen
extends CanvasLayer
## The first screen: a hanging scroll with the game's modes and your saves,
## while your character stands beside it. Fully usable with a controller.
##
## Continue resumes the slot you played last; New Game and Load / Delete Save
## list the save slots (a new game over an old save, and deleting one, ask
## first; Delete or the controller's X deletes the selected save).

signal trial_chosen
signal training_chosen
signal customize_chosen
signal chapter_chosen(chapter_id: String)
## Resume a saved game: Continue, or a slot picked under Load Game.
signal continue_chosen(slot: int)
## A fresh game in this slot (anything saved there is confirmed gone).
signal new_game_chosen(slot: int)

## Deletes the save whose card is selected on the slot page.
const DELETE_KEY := KEY_DELETE
const DELETE_BUTTON := JOY_BUTTON_X

## The story, for the chapter list (loaded on first use if not given).
var story: Story

var _root: Control
var _warning: Label
var _menu: VBoxContainer
var _first: Button
## &"main", &"chapters", &"slots" or &"confirm".
var _page := &"main"
## Whether the slot page is choosing where a new game goes.
var _slots_for_new := false


func _init() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build()
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	# Without the character packs every character falls back to the low-poly
	# placeholder, and without the audio pack there's no music: say so
	# plainly instead of letting it look like the game.
	_warning.text = Packs.missing_warning(Packs.characters_installed(), Packs.audio_installed())
	_warning.visible = _warning.text != ""
	show_main()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func showing_chapters() -> bool:
	return _page == &"chapters"


func showing_slots() -> bool:
	return _page == &"slots"


func show_main() -> void:
	_page = &"main"
	_clear_menu()
	if story == null:
		story = Story.load_all()
	var slot := SaveSlots.active
	if slot > 0:
		_first = _entry("続", "Continue", _slot_summary(slot), continue_chosen.emit.bind(slot))
	_entry("新", "New Game", "" if slot > 0 else "Choose your clan, dojutsu, look and jutsu, then begin the story.",
		show_slots.bind(true))
	if _first == null or slot == 0:
		_first = _menu.get_child(0) as Button
	if SaveSlots.any():
		_entry("録", "Load / Delete Save", "", show_slots.bind(false))
	if slot > 0 and bool(Profile.get_value(&"created")):
		_entry("物", "Chapters", "", show_chapters)
	var best := Game.best_time(TrialDirector.TRIAL_ID)
	_entry("試", "Trial of the Five Natures", "Best time %s" % Game.format_time(best) if best > 0.0 else "", trial_chosen.emit)
	_entry("修", "Training Ground", "", training_chosen.emit)
	if slot > 0:
		_entry("装", "Customize", "", customize_chosen.emit)
	if OS.get_name() != "Web":
		_entry("退", "Quit", "", func() -> void: get_tree().quit())
	_focus_later(_first)


## One line about a save, for Continue and the slot cards.
func _slot_summary(slot: int) -> String:
	var m := SaveSlots.meta(slot)
	if not m["exists"]:
		return ""
	if not m["created"]:
		return "Slot %d · character not finished" % slot
	return "%s  ·  %s  ·  %d of %d chapters  ·  %s" % [m["name"], _clan_name(m["clan"]), m["cleared"],
		story.chapters.size(), SaveSlots.format_playtime(m["playtime"])]


static func _clan_name(clan_id: String) -> String:
	var clan := Perks.clan(clan_id)
	return clan["name"] if not clan.is_empty() else "No clan"


## The saves as cards, in a column that scrolls with controller focus.
## `for_new`: pick where a new game goes (an occupied slot asks before it is
## overwritten); otherwise pick one to load. Either way a save can be
## deleted: its Delete button, or DELETE_KEY / DELETE_BUTTON on its card.
func show_slots(for_new: bool) -> void:
	_page = &"slots"
	_slots_for_new = for_new
	_clear_menu()
	if story == null:
		story = Story.load_all()
	_menu.add_child(UiKit.label("Choose where the new game goes" if for_new else "Choose a save to load",
		22, UiKit.CRIMSON_DARK, &"bold"))
	if SaveSlots.any():
		_menu.add_child(_delete_hint())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size.y = 470
	_menu.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 6)
	scroll.add_child(column)
	var cards: Array[Button] = []
	for slot in range(1, SaveSlots.COUNT + 1):
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var card := _slot_card(slot, for_new)
		cards.append(card)
		row.add_child(card)
		if SaveSlots.exists(slot):
			row.add_child(_delete_button(slot, for_new))
		column.add_child(row)
	# A new game starts on the first empty slot; Load on the slot in play (or
	# else the first save).
	var pick := 0
	for slot in range(1, SaveSlots.COUNT + 1):
		if for_new and not SaveSlots.exists(slot):
			pick = slot
			break
		if not for_new and SaveSlots.exists(slot) and (pick == 0 or slot == SaveSlots.active):
			pick = slot
	_entry("戻", "Back", "", show_main)
	_focus_later(cards[maxi(pick, 1) - 1])


func _delete_button(slot: int, for_new: bool) -> Button:
	var del := Button.new()
	del.text = "Delete"
	del.tooltip_text = "Delete this save"
	del.custom_minimum_size = Vector2(104, 0)
	del.add_theme_color_override(&"font_color", UiKit.CRIMSON)
	del.add_theme_color_override(&"font_hover_color", UiKit.CRIMSON_DARK)
	del.add_theme_color_override(&"font_focus_color", UiKit.CRIMSON_DARK)
	del.pressed.connect(func() -> void: _ask_delete.call_deferred(slot, for_new))
	return del


## "[Del] / [X] Delete the selected save": the shortcut on both devices.
func _delete_hint() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	row.add_child(InputGlyph.for_binding(Binding.key(DELETE_KEY), 24.0))
	row.add_child(UiKit.label("/", 16, UiKit.INK_SOFT, &"body"))
	row.add_child(InputGlyph.for_binding(Binding.joy_button(DELETE_BUTTON), 24.0))
	row.add_child(UiKit.label("Delete the selected save", 16, UiKit.INK_SOFT, &"body"))
	return row


## The slot whose card (or Delete button) has focus, 0 for none.
func focused_slot() -> int:
	var f := get_viewport().gui_get_focus_owner()
	if f == null:
		return 0
	if f.has_meta(&"slot"):
		return int(f.get_meta(&"slot"))
	for sibling in f.get_parent().get_children():
		if sibling.has_meta(&"slot"):
			return int(sibling.get_meta(&"slot"))
	return 0


func _slot_card(slot: int, for_new: bool) -> Button:
	var m := SaveSlots.meta(slot)
	var b := Button.new()
	b.set_meta(&"slot", slot)
	b.custom_minimum_size = Vector2(0, 122)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var kanji := "空"
	var color := UiKit.INK_SOFT
	var heading := "Slot %d  ·  Empty" % slot
	var line1 := "A new shinobi begins here." if for_new else "Nothing saved."
	var line2 := ""
	var line3 := ""
	if m["exists"]:
		var clan := Perks.clan(m["clan"])
		kanji = clan["kanji"] if not clan.is_empty() else "忍"
		color = Color(clan["color"]) if not clan.is_empty() else UiKit.CRIMSON
		heading = m["name"]
		if m["created"]:
			line1 = "Slot %d  ·  %s  ·  %s" % [slot, _clan_name(m["clan"]), Element.display_name(m["nature"])]
			line2 = "Lv %d  ·  %d of %d chapters  ·  %s" % [m["level"], m["cleared"], story.chapters.size(),
				SaveSlots.format_playtime(m["playtime"])]
		else:
			line1 = "Slot %d  ·  character not finished" % slot
		line3 = _date(m["modified"])
	b.disabled = not for_new and not m["exists"]
	if slot == SaveSlots.active and m["exists"]:
		line3 += "  ·  last played" if line3 != "" else "last played"
	# Deferred: the pages rebuild the menu, freeing the card that was pressed.
	b.pressed.connect(func() -> void: _slot_pressed.call_deferred(slot, for_new))
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -16
	row.offset_top = 8
	row.offset_bottom = -8
	row.add_theme_constant_override(&"separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var stamp := Hanko.make(kanji, 72.0, color.darkened(0.2))
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stamp)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override(&"separation", 2)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var head := UiKit.label(heading, 24, UiKit.INK, &"bold")
	head.clip_text = true
	text.add_child(head)
	for line: String in [line1, line2, line3]:
		if line != "":
			var l := UiKit.label(line, 16, UiKit.INK_SOFT, &"body")
			l.clip_text = true
			text.add_child(l)
	var focus_box := StyleBoxFlat.new()
	focus_box.bg_color = Color(UiKit.CRIMSON, 0.1)
	focus_box.border_color = UiKit.CRIMSON
	focus_box.set_border_width_all(3)
	b.add_theme_stylebox_override(&"focus", focus_box)
	var dim_box := StyleBoxFlat.new()
	dim_box.bg_color = Color(UiKit.INK, 0.05)
	b.add_theme_stylebox_override(&"disabled", dim_box)
	return b


static func _date(unix: int) -> String:
	if unix <= 0:
		return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	return Time.get_datetime_string_from_unix_time(unix + bias * 60, true).left(16)


func _slot_pressed(slot: int, for_new: bool) -> void:
	if not for_new:
		continue_chosen.emit(slot)
	elif SaveSlots.exists(slot):
		_confirm("Overwrite slot %d?" % slot,
			"%s will be gone for good, and a new shinobi begins here." % SaveSlots.meta(slot)["name"],
			"Overwrite", new_game_chosen.emit.bind(slot), show_slots.bind(true))
	else:
		new_game_chosen.emit(slot)


func _ask_delete(slot: int, for_new: bool) -> void:
	_confirm("Delete slot %d?" % slot,
		"%s and all their progress will be gone for good." % SaveSlots.meta(slot).get("name", "This save"),
		"Delete", _delete_slot.bind(slot, for_new), show_slots.bind(for_new))


func _delete_slot(slot: int, for_new: bool) -> void:
	SaveSlots.erase(slot)
	if SaveSlots.any():
		show_slots(for_new)
	else:
		show_main()


## A yes/no page. Focus starts on the safe answer.
func _confirm(heading: String, body: String, yes_label: String, on_yes: Callable, on_no: Callable) -> void:
	_page = &"confirm"
	_clear_menu()
	_menu.add_child(UiKit.label(heading, 34, UiKit.CRIMSON, &"display"))
	var l := UiKit.label(body, 20, UiKit.INK, &"body")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 560
	_menu.add_child(l)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 14
	_menu.add_child(spacer)
	var no := _entry("戻", "No, go back", "", on_no)
	_entry("消", yes_label, "", on_yes)
	_focus_later(no)


func show_chapters() -> void:
	_page = &"chapters"
	_clear_menu()
	# Ten chapters don't fit the scroll: list them in a scrolling column that
	# follows controller focus.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size.y = 540
	_menu.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 6)
	scroll.add_child(column)
	var outer := _menu
	_menu = column
	var focus: Button = null
	var part := 0
	for c: Dictionary in story.chapters:
		var id: String = c["id"]
		if c["part"] != part:
			part = c["part"]
			var title: String = story.part(part).get("title", "")
			_menu.add_child(UiKit.label("第%s章  CHAPTER %d%s" % [Story.numeral(part), part,
				(": " + title.to_upper()) if title != "" else ""], 22, UiKit.CRIMSON_DARK, &"bold"))
		var unlocked := story.is_unlocked(id)
		var done := Game.chapter_done(id)
		var status := "Cleared" if done else ("New" if unlocked else "Sealed: clear the mission before it")
		var b := _entry(Story.numeral(c["number"]) if unlocked else "封", c["title"] if unlocked else "? ? ?",
			"%s  ·  %s" % [c["location"], status] if unlocked else status, chapter_chosen.emit.bind(id))
		b.disabled = not unlocked
		if unlocked and (focus == null or not done):
			focus = b
	_menu = outer
	_entry("戻", "Back", "", show_main)
	if focus:
		_focus_later(focus)


func _unhandled_input(event: InputEvent) -> void:
	if visible and _page == &"slots" and _is_delete(event):
		var slot := focused_slot()
		if SaveSlots.exists(slot):
			Sfx.ui(&"ui_back")
			_ask_delete(slot, _slots_for_new)
			get_viewport().set_input_as_handled()
			return
	if visible and _page != &"main" and event.is_action_pressed(&"ui_cancel"):
		Sfx.ui(&"ui_back")
		show_main()
		get_viewport().set_input_as_handled()


static func _is_delete(event: InputEvent) -> bool:
	if event is InputEventKey:
		var k := event as InputEventKey
		return k.pressed and not k.echo and (k.keycode == DELETE_KEY or k.physical_keycode == DELETE_KEY)
	if event is InputEventJoypadButton:
		var j := event as InputEventJoypadButton
		return j.pressed and j.button_index == DELETE_BUTTON
	return false


## Focuses `control` once it's laid out, unless the page was rebuilt (and
## it thrown away) in the meantime.
func _focus_later(control: Control) -> void:
	(func() -> void:
		if is_instance_valid(control) and control.is_inside_tree():
			control.grab_focus()).call_deferred()


func _clear_menu() -> void:
	_first = null
	for child in _menu.get_children():
		_menu.remove_child(child)
		child.queue_free()


func close() -> void:
	visible = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.theme()
	add_child(_root)

	# Ink wash fading out from the left so the scroll reads over any scenery.
	var fade := Gradient.new()
	fade.set_color(0, Color(UiKit.INK, 0.6))
	fade.set_color(1, Color(UiKit.INK, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = fade
	tex.width = 256
	tex.height = 4
	var wash := TextureRect.new()
	wash.texture = tex
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.anchor_bottom = 1.0
	wash.offset_right = 1100
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(wash)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", -6)
	column.anchor_bottom = 1.0
	column.offset_left = 90
	column.offset_top = 36
	column.offset_right = 90 + 700
	column.offset_bottom = -36
	_root.add_child(column)
	column.add_child(_roller())
	var paper := PaperPanel.new()
	paper.seed = 57.0
	paper.opacity = 0.98
	paper.tear = 3.0
	paper.margin = Vector4(56, 40, 56, 36)
	paper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(paper)
	column.add_child(_roller())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 14)
	paper.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 20)
	header.add_child(Hanko.make("忍", 104.0))
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override(&"separation", -10)
	titles.add_child(UiKit.label("忍の道", 30, UiKit.INK_SOFT, &"brush"))
	titles.add_child(UiKit.label("PROJECT", 44, UiKit.INK, &"display"))
	titles.add_child(UiKit.label("SHINOBI", 72, UiKit.CRIMSON, &"display"))
	header.add_child(titles)
	vbox.add_child(header)
	vbox.add_child(_rule())

	_warning = UiKit.label("", 19, UiKit.CRIMSON, &"bold")
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.custom_minimum_size.x = 560
	_warning.visible = false
	vbox.add_child(_warning)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override(&"separation", 6)
	_menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_menu)

	vbox.add_child(_rule())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 8)
	vbox.add_child(footer)
	footer.add_child(InputGlyph.for_binding(Binding.joy_button(JOY_BUTTON_A), 28.0))
	footer.add_child(UiKit.label("/ Enter to choose", 18, UiKit.INK_SOFT, &"bold"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	footer.add_child(UiKit.label("An original shinobi game", 16, UiKit.INK_SOFT, &"body"))


func _entry(kanji: String, title: String, blurb: String, on_press: Callable) -> Button:
	var parent := _menu
	var b := Button.new()
	b.text = "%s   %s" % [kanji, title]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override(&"font_size", 28)
	b.custom_minimum_size.y = 46
	# Deferred: pages rebuild the menu, freeing the button that was pressed.
	b.pressed.connect(func() -> void: on_press.call_deferred())
	parent.add_child(b)
	if blurb != "":
		var l := UiKit.label(blurb, 18, UiKit.INK_SOFT, &"body")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 560
		parent.add_child(l)
	return b


func _roller() -> Control:
	var r := ColorRect.new()
	r.color = UiKit.WOOD
	r.custom_minimum_size = Vector2(0, 18)
	return r


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(UiKit.INK, 0.3)
	r.custom_minimum_size = Vector2(0, 2)
	return r
