class_name TitleScreen
extends CanvasLayer
## The first screen: a hanging scroll with the game's modes, while your
## character stands beside it. Fully usable with a controller.

signal trial_chosen
signal training_chosen
signal customize_chosen
signal chapter_chosen(chapter_id: String)

## The story, for the chapter list (loaded on first use if not given).
var story: Story

var _root: Control
var _menu: VBoxContainer
var _first: Button
var _on_chapters := false


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
	show_main()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func showing_chapters() -> bool:
	return _on_chapters


func show_main() -> void:
	_on_chapters = false
	_clear_menu()
	if story == null:
		story = Story.load_all()
	var cleared := story.chapters.filter(func(c: Dictionary) -> bool: return Game.chapter_done(c["id"])).size()
	_first = _entry("物", "Story", "Two parts, %d chapters, %d cleared." % [story.chapters.size(), cleared], show_chapters)
	var best := Game.best_time(TrialDirector.TRIAL_ID)
	_entry("試", "Trial of the Five Natures", "Five waves of shinobi clones. %s" % (
		"Best time %s." % Game.format_time(best) if best > 0.0 else "Beat each nature with the one that overcomes it."), trial_chosen.emit)
	_entry("修", "Training Ground", "Practise seals and jutsu on dummies. Nothing hits back.", training_chosen.emit)
	_entry("装", "Customize", "Look, colours, gear, name and chakra nature.", customize_chosen.emit)
	if OS.get_name() != "Web":
		_entry("退", "Quit", "", func() -> void: get_tree().quit())
	_first.grab_focus.call_deferred()


func show_chapters() -> void:
	_on_chapters = true
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
			var title: String = Story.PART_TITLES.get(part, "")
			_menu.add_child(UiKit.label("第%s部  PART %s%s" % [Story.numeral(part), ["", "ONE", "TWO", "THREE"][mini(part, 3)],
				(": " + title.to_upper()) if title != "" else ""], 22, UiKit.CRIMSON_DARK, &"bold"))
		var unlocked := story.is_unlocked(id)
		var done := Game.chapter_done(id)
		var status := "Cleared" if done else ("New" if unlocked else "Sealed: clear the chapter before it")
		var b := _entry(Story.numeral(c["number"]) if unlocked else "封", c["title"] if unlocked else "? ? ?",
			"%s  ·  %s" % [c["location"], status] if unlocked else status, chapter_chosen.emit.bind(id))
		b.disabled = not unlocked
		if unlocked and (focus == null or not done):
			focus = b
	_menu = outer
	_entry("戻", "Back", "", show_main)
	if focus:
		focus.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if visible and _on_chapters and event.is_action_pressed(&"ui_cancel"):
		Sfx.ui(&"ui_back")
		show_main()
		get_viewport().set_input_as_handled()


func _clear_menu() -> void:
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
	column.offset_top = 60
	column.offset_right = 90 + 700
	column.offset_bottom = -60
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
	b.add_theme_font_size_override(&"font_size", 30)
	b.custom_minimum_size.y = 54
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
