class_name Hanko
extends Control
## A round vermilion seal stamp with a kanji, like a signature seal on a scroll.

@export var text := "忍":
	set(v):
		text = v
		queue_redraw()
@export var color := UiKit.CRIMSON:
	set(v):
		color = v
		queue_redraw()
@export var ink := UiKit.PAPER


static func make(kanji: String, diameter := 64.0, stamp_color := UiKit.CRIMSON) -> Hanko:
	var h := Hanko.new()
	h.text = kanji
	h.color = stamp_color
	h.custom_minimum_size = Vector2.ONE * diameter
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	# Slightly uneven stamp: solid disc, a paler inner ring, the kanji.
	draw_circle(c, r, color)
	draw_arc(c, r * 0.84, 0.0, TAU, 48, Color(ink, 0.55), maxf(1.5, r * 0.05), true)
	var f := UiKit.font(&"brush")
	var fs := int(r * 1.15)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc := f.get_ascent(fs)
	var desc := f.get_descent(fs)
	draw_string(f, Vector2(c.x - w * 0.5, c.y + (asc - desc) * 0.5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
