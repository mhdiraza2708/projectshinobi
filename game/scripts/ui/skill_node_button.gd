class_name SkillNodeButton
extends Button
## One node of a skill tree: an ink seal with the node's kanji, its ranks as
## dots underneath. Locked nodes are faint, learnable ones are outlined in the
## tree's colour, learned ones are filled, maxed ones get a gold ring. The
## final skill of a tree is a larger diamond.

var node_id := ""
var kanji := ""
var color := UiKit.CRIMSON
var capstone := false
var rank := 0
var ranks := 1
## SkillTrees.can_learn's answer.
var state := SkillTrees.OK

var _pop := 0.0


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	text = ""
	var empty := StyleBoxEmpty.new()
	for s: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]:
		add_theme_stylebox_override(s, empty)


## A little swell when a rank is learned.
func pop() -> void:
	_pop = 1.0
	var tw := create_tween()
	tw.tween_property(self, "_pop", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_callback(queue_redraw).set_delay(0.0)
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()
	if _pop <= 0.0:
		set_process(false)


func _ready() -> void:
	set_process(false)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _shape(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	if capstone:
		for i in 4:
			points.append(center + Vector2.UP.rotated(TAU * i / 4.0) * radius)
	else:
		for i in 32:
			points.append(center + Vector2.RIGHT.rotated(TAU * i / 32.0) * radius)
	return points


func _draw() -> void:
	var learned := rank > 0
	var maxed := rank >= ranks
	var open := state == SkillTrees.OK
	var center := size * 0.5 - Vector2(0, 6)
	var radius := (minf(size.x, size.y) * 0.5 - 10.0) * (1.0 + 0.12 * _pop)
	if capstone:
		radius *= 1.18
	var hot := has_focus() or is_hovered()
	if hot:
		var ring := _shape(center, radius + 7.0)
		ring.append(ring[0])
		draw_polyline(ring, UiKit.CRIMSON, 4.0, true)
	var fill := UiKit.PAPER
	if learned:
		fill = color.lerp(UiKit.PAPER, 0.15 if maxed else 0.45)
	elif not open:
		fill = UiKit.PAPER_DARK
	draw_colored_polygon(_shape(center, radius), fill)
	var edge := _shape(center, radius)
	edge.append(edge[0])
	var edge_color := UiKit.GOLD if maxed else (color.darkened(0.2) if learned or open else Color(UiKit.INK, 0.3))
	draw_polyline(edge, edge_color, 4.0 if maxed or open else 2.5, true)
	var f := UiKit.font(&"brush")
	var font_size := int(radius * (1.0 if capstone else 1.05))
	var ink := UiKit.PAPER if learned and maxed else (UiKit.INK if learned or open else Color(UiKit.INK, 0.35))
	var w := f.get_string_size(kanji, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(f, center + Vector2(-w * 0.5, font_size * 0.36), kanji, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
	# Ranks as dots under the seal, on a paper pill so links don't run through.
	var dot_y := center.y + radius + (12.0 if capstone else 9.0)
	var half := (ranks - 1) * 6.5 + 8.0
	draw_rect(Rect2(center.x - half, dot_y - 7.0, half * 2.0, 14.0), UiKit.PAPER)
	for i in ranks:
		var x := center.x + (i - (ranks - 1) * 0.5) * 13.0
		if i < rank:
			draw_circle(Vector2(x, dot_y), 4.5, color.darkened(0.2))
		else:
			draw_arc(Vector2(x, dot_y), 4.0, 0.0, TAU, 12, Color(UiKit.INK, 0.45), 1.5, true)
