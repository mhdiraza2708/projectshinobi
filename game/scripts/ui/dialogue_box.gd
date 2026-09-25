class_name DialogueBox
extends CanvasLayer
## Story dialogue: a paper strip along the bottom with the speaker's seal,
## name and a typewriter line. Confirm (A / Enter / Space / click) finishes
## the line, then moves on; holding it fast-forwards.

## A new line started (the director uses it for expressions and gestures).
signal line_started(index: int, line: Dictionary)
signal finished

const CHARS_PER_SECOND := 48.0
## While confirm is held, lines advance this often.
const HOLD_ADVANCE := 0.22

var story: Story
var lines: Array = []
var index := -1

var _root: Control
var _seal_slot: CenterContainer
var _seal: Control
var _name: Label
var _text: Label
var _next: Label
var _typing := 0.0
var _hold := 0.0


func _init() -> void:
	layer = 12


func _ready() -> void:
	_build()
	visible = false
	set_process(false)


func is_open() -> bool:
	return visible


## Plays `new_lines` ([{who, text, mood}]) and emits `finished` after the last.
func play(new_lines: Array, with_story: Story) -> void:
	story = with_story
	lines = new_lines
	index = -1
	visible = true
	set_process(true)
	_advance()


## Finishes the current line, or moves to the next one.
func advance() -> void:
	if not visible:
		return
	if _text.visible_ratio < 1.0:
		_text.visible_ratio = 1.0
		return
	_advance()


func _advance() -> void:
	index += 1
	if index >= lines.size():
		visible = false
		set_process(false)
		finished.emit()
		return
	var line: Dictionary = lines[index]
	var who: String = line["who"]
	if _seal:
		_seal.queue_free()
	var is_player := who == Story.PLAYER
	_seal = Hanko.make(story.speaker_kanji(who), 84.0, UiKit.INK if is_player else UiKit.CRIMSON)
	_seal_slot.add_child(_seal)
	var title: String = story.characters[who]["title"] if story.characters.has(who) else ""
	_name.text = story.speaker_name(who) + ("   " + title if title != "" else "")
	_text.text = Story.format(line["text"])
	_text.visible_ratio = 0.0
	_typing = 0.0
	Sfx.ui(&"ui_move", -6.0)
	line_started.emit(index, line)


func _process(delta: float) -> void:
	var count := maxi(1, _text.get_total_character_count())
	if _text.visible_ratio < 1.0:
		_typing += delta * CHARS_PER_SECOND
		_text.visible_ratio = minf(1.0, _typing / count)
	_next.modulate.a = 1.0 if _text.visible_ratio >= 1.0 else 0.0
	if Input.is_action_pressed(&"ui_accept"):
		_hold += delta
		if _hold >= HOLD_ADVANCE * 2.0:
			_hold = HOLD_ADVANCE
			_text.visible_ratio = 1.0
			_advance()
	else:
		_hold = 0.0


func _input(event: InputEvent) -> void:
	if not visible or get_tree().paused:
		return
	var confirm := event.is_action_pressed(&"ui_accept") and not event.is_echo()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		confirm = true
	if confirm:
		advance()
		get_viewport().set_input_as_handled()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.theme()
	add_child(_root)

	var paper := PaperPanel.new()
	paper.seed = 91.0
	paper.opacity = 0.97
	paper.tear = 4.0
	paper.margin = Vector4(40, 26, 44, 26)
	paper.anchor_left = 0.5
	paper.anchor_right = 0.5
	paper.anchor_top = 1.0
	paper.anchor_bottom = 1.0
	paper.offset_left = -760
	paper.offset_right = 760
	paper.offset_top = -236
	paper.offset_bottom = -40
	_root.add_child(paper)

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 26)
	paper.add_child(row)
	_seal_slot = CenterContainer.new()
	_seal_slot.custom_minimum_size = Vector2(100, 100)
	_seal_slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_seal_slot)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	_name = UiKit.label("", 30, UiKit.CRIMSON, &"display")
	col.add_child(_name)
	_text = UiKit.label("", 30, UiKit.INK, &"body")
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(1200, 80)
	col.add_child(_text)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(foot)
	_next = UiKit.label("»", 30, UiKit.CRIMSON, &"bold")
	foot.add_child(_next)
