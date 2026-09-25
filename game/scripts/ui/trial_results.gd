class_name TrialResults
extends CanvasLayer
## Shown when a trial ends: time, record, waves cleared, and what next.

signal retry_chosen
signal title_chosen

var _root: Control
var _stamp: Control
var _stamp_slot: Control
var _heading: Label
var _sub: Label
var _lines: Label
var _record: Label
var _retry: Button


func _init() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build()
	visible = false


func is_open() -> bool:
	return visible


func show_result(won: bool, seconds: float, new_record: bool, cleared: int, total: int) -> void:
	if _stamp:
		_stamp.queue_free()
	_stamp = Hanko.make("勝" if won else "敗", 110.0, UiKit.CRIMSON if won else UiKit.INK_SOFT)
	_stamp_slot.add_child(_stamp)
	_heading.text = "TRIAL COMPLETE" if won else "DEFEATED"
	_sub.text = "The five natures yield to you." if won else "Rest, then try again. Watch for the seals above their heads: interrupt them."
	var best := Game.best_time(TrialDirector.TRIAL_ID)
	var lines := PackedStringArray()
	lines.append("Waves cleared   %d / %d" % [cleared, total])
	lines.append("Time   %s" % Game.format_time(seconds))
	if best > 0.0:
		lines.append("Best   %s" % Game.format_time(best))
	_lines.text = "\n".join(lines)
	_record.visible = new_record
	_retry.text = "Run it again" if won else "Try again"
	visible = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_retry.grab_focus()


func close() -> void:
	visible = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(UiKit.INK, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var paper := PaperPanel.new()
	paper.seed = 71.0
	paper.opacity = 0.98
	paper.tear = 3.0
	paper.margin = Vector4(56, 40, 56, 40)
	paper.custom_minimum_size = Vector2(900, 0)
	paper.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	paper.grow_horizontal = Control.GROW_DIRECTION_BOTH
	paper.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(paper)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 16)
	paper.add_child(vbox)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 24)
	vbox.add_child(header)
	_stamp_slot = CenterContainer.new()
	_stamp_slot.custom_minimum_size = Vector2(120, 120)
	header.add_child(_stamp_slot)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override(&"separation", -6)
	titles.add_child(UiKit.label("五行の試練", 24, UiKit.INK_SOFT, &"brush"))
	_heading = UiKit.label("", 56, UiKit.CRIMSON, &"display")
	titles.add_child(_heading)
	header.add_child(titles)

	_sub = UiKit.label("", 21, UiKit.INK, &"body")
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.custom_minimum_size.x = 780
	vbox.add_child(_sub)
	_lines = UiKit.label("", 28, UiKit.INK, &"bold")
	vbox.add_child(_lines)
	_record = UiKit.label("New record!", 30, UiKit.CRIMSON, &"display")
	vbox.add_child(_record)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 16)
	vbox.add_child(buttons)
	_retry = Button.new()
	_retry.add_theme_font_size_override(&"font_size", 28)
	_retry.pressed.connect(retry_chosen.emit)
	buttons.add_child(_retry)
	var title := Button.new()
	title.text = "Title screen"
	title.add_theme_font_size_override(&"font_size", 28)
	title.pressed.connect(title_chosen.emit)
	buttons.add_child(title)
