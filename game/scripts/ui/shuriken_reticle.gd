class_name ShurikenReticle
extends Control
## Lock-on marker: a slowly spinning four-point shuriken.

const SIZE := 58.0

var _angle := 0.0


func _init() -> void:
	custom_minimum_size = Vector2.ONE * SIZE
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if visible:
		_angle += delta * 2.2
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var outer := SIZE * 0.5
	var inner := SIZE * 0.16
	var pts := PackedVector2Array()
	for i in 8:
		# Inner points are swept back so the blades read as a pinwheel.
		var a := _angle + i * TAU / 8.0 + (0.35 if i % 2 == 1 else 0.0)
		var radius := outer if i % 2 == 0 else inner
		pts.append(c + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(pts, Color(UiKit.CRIMSON, 0.85))
	pts.append(pts[0])
	draw_polyline(pts, UiKit.INK, 2.0, true)
	draw_circle(c, SIZE * 0.07, UiKit.PAPER)
	draw_arc(c, SIZE * 0.07, 0.0, TAU, 16, UiKit.INK, 1.5, true)
