class_name FuseBar
extends Control
## The seal timing window, drawn as a burning fuse: the lit end creeps left as
## time runs out. `ratio` 1 = full window, 0 = the sequence breaks.

var ratio := 1.0:
	set(v):
		ratio = clampf(v, 0.0, 1.0)
		queue_redraw()
## When false (no time limit), the fuse is drawn unlit.
var lit := true:
	set(v):
		lit = v
		queue_redraw()

var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(520, 18)


func _process(delta: float) -> void:
	if lit:
		_t += delta
		queue_redraw()


func _draw() -> void:
	var y := size.y * 0.5
	var end_x := size.x * ratio
	# Ash left behind the flame.
	if end_x < size.x:
		draw_dashed_line(Vector2(end_x, y), Vector2(size.x, y), Color(UiKit.INK, 0.25), 2.0, 5.0)
	if end_x > 1.0:
		draw_line(Vector2(0, y), Vector2(end_x, y), UiKit.WOOD, 5.0, true)
		# Twisted rope marks.
		var x := 4.0
		while x < end_x - 2.0:
			draw_line(Vector2(x, y - 2.5), Vector2(x + 3.0, y + 2.5), UiKit.GOLD, 1.5, true)
			x += 7.0
	if not lit:
		return
	var flicker := 0.8 + 0.2 * sin(_t * 31.0) * sin(_t * 17.0)
	var tip := Vector2(end_x, y)
	draw_circle(tip, 9.0 * flicker, Color(1.0, 0.45, 0.1, 0.35))
	draw_circle(tip, 5.5 * flicker, Color(1.0, 0.7, 0.2, 0.9))
	draw_circle(tip, 2.5, Color(1.0, 0.97, 0.85))
