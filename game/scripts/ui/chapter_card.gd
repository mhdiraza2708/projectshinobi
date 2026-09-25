class_name ChapterCard
extends CanvasLayer
## Full-screen ink card that opens a chapter: numeral, title, place and
## time. Confirm skips it.

signal finished

const HOLD := 2.6
const FADE := 0.5

var _root: Control
var _numeral: Label
var _chapter: Label
var _title: Label
var _place: Label
var _tween: Tween


func _init() -> void:
	layer = 25


func _ready() -> void:
	_build()
	visible = false


func is_open() -> bool:
	return visible


func show_chapter(number: int, title: String, place: String) -> void:
	_numeral.text = Story.numeral(number)
	_chapter.text = "CHAPTER %d" % number
	_title.text = title
	_place.text = place
	visible = true
	_root.modulate.a = 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, FADE)
	_tween.tween_interval(HOLD)
	_tween.tween_callback(close)
	Sfx.play(&"wave_start", -4.0)


func close() -> void:
	if not visible:
		return
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 0.0, FADE)
	_tween.tween_callback(func() -> void:
		visible = false
		finished.emit())


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_accept") and _root.modulate.a > 0.5:
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	add_child(_root)
	var ink := ColorRect.new()
	ink.color = UiKit.INK
	ink.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(ink)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override(&"separation", 4)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(col)
	_numeral = UiKit.label("", 180, UiKit.CRIMSON, &"brush")
	_chapter = UiKit.label("", 26, UiKit.PAPER_DARK, &"bold")
	_title = UiKit.label("", 72, UiKit.PAPER, &"display")
	_place = UiKit.label("", 26, UiKit.GOLD, &"body")
	for l: Label in [_numeral, _chapter, _title, _place]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
