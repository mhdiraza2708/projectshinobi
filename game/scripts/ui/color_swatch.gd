class_name ColorSwatch
extends Button
## A round colour chip. Picking colours from a fixed palette works on a
## D-pad as well as a mouse (a free colour picker doesn't). White means
## "original colours" and is drawn as a slashed circle.

const SIZE := 46.0

var swatch := Color.WHITE
var selected := false:
	set(v):
		selected = v
		queue_redraw()


static func make(color: Color, is_selected: bool, tooltip := "") -> ColorSwatch:
	var s := ColorSwatch.new()
	s.swatch = color
	s.selected = is_selected
	s.tooltip_text = tooltip
	return s


func _init() -> void:
	custom_minimum_size = Vector2.ONE * SIZE
	focus_mode = Control.FOCUS_ALL
	for style in [&"normal", &"hover", &"pressed", &"focus", &"hover_pressed"]:
		add_theme_stylebox_override(style, StyleBoxEmpty.new())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _draw() -> void:
	var c := size * 0.5
	var r := SIZE * 0.5 - 6.0
	if has_focus() or is_hovered():
		draw_circle(c, r + 5.0, UiKit.CRIMSON if has_focus() else Color(UiKit.CRIMSON, 0.35))
	if selected:
		draw_arc(c, r + 3.5, 0.0, TAU, 40, UiKit.INK, 3.0, true)
	draw_circle(c, r, swatch)
	draw_arc(c, r, 0.0, TAU, 40, Color(UiKit.INK, 0.6), 1.5, true)
	if swatch == Color.WHITE:
		var d := Vector2(r, -r) * 0.62
		draw_line(c - d, c + d, UiKit.CRIMSON, 2.5, true)
