class_name QuestTracker
extends CanvasLayer
## The open world's quest display: the tracked quest top right (what it
## wants and how far), a marker on screen where it is (pinned to the edge
## when it's behind you or off screen), the Interact prompt when someone is
## close, and an island's name as you arrive.

const EDGE := 70.0

var world: OpenWorld

var _root: Control
var _kanji: Label
var _title: Label
var _text: Label
var _dist: Label
var _marker: Control
var _marker_dist: Label
var _prompt: Label
var _place: VBoxContainer
var _place_kanji: Label
var _place_name: Label
var _place_tween: Tween


func _init() -> void:
	layer = 4


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.theme()
	add_child(_root)

	var box := HBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -560
	box.offset_right = -40
	box.offset_top = 200
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override(&"separation", 0)
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(lines)
	_title = UiKit.label("", 24, UiKit.GOLD, &"bold", 5)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lines.add_child(_title)
	_text = UiKit.label("", 19, UiKit.PAPER, &"bold", 5)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 440
	lines.add_child(_text)
	_dist = UiKit.label("", 18, Color(UiKit.PAPER, 0.75), &"bold", 4)
	_dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lines.add_child(_dist)
	_kanji = UiKit.label("", 54, UiKit.GOLD, &"brush", 6)
	_kanji.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.add_child(_kanji)

	_marker = Control.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	_marker.custom_minimum_size = Vector2(40, 40)
	_marker.size = Vector2(40, 40)
	_root.add_child(_marker)
	_marker_dist = UiKit.label("", 17, UiKit.PAPER, &"bold", 4)
	_marker_dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marker_dist.position = Vector2(-40, 34)
	_marker_dist.size = Vector2(120, 24)
	_marker.add_child(_marker_dist)

	_prompt = UiKit.label("", 26, UiKit.PAPER, &"bold", 6)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_left = -500
	_prompt.offset_right = 500
	_prompt.offset_top = -330
	_prompt.offset_bottom = -290
	_root.add_child(_prompt)

	_place = VBoxContainer.new()
	_place.alignment = BoxContainer.ALIGNMENT_CENTER
	_place.add_theme_constant_override(&"separation", -10)
	_place.anchor_left = 0.5
	_place.anchor_right = 0.5
	_place.offset_left = -500
	_place.offset_right = 500
	_place.offset_top = 150
	_place.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place.modulate.a = 0.0
	_root.add_child(_place)
	_place_kanji = UiKit.label("", 110, UiKit.PAPER, &"brush", 8)
	_place_kanji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place.add_child(_place_kanji)
	_place_name = UiKit.label("", 46, UiKit.PAPER, &"display", 6)
	_place_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place.add_child(_place_name)


## Re-reads the tracked quest.
func refresh() -> void:
	if world == null or _title == null:
		return
	var o := world.objective()
	_title.text = str(o["title"])
	_text.text = str(o["text"])
	_kanji.text = str(o["kanji"])


func set_prompt(text: String) -> void:
	if _prompt == null:
		return
	_prompt.text = "%s  %s" % [InputDevice.glyph(&"interact"), text] if text != "" else ""


## An island's name as you arrive on it.
func show_location(place: String, kanji: String) -> void:
	if _place == null:
		return
	_place_kanji.text = kanji
	_place_name.text = place.to_upper()
	if _place_tween and _place_tween.is_valid():
		_place_tween.kill()
	_place_tween = create_tween()
	_place_tween.tween_property(_place, "modulate:a", 1.0, 0.8)
	_place_tween.tween_interval(2.4)
	_place_tween.tween_property(_place, "modulate:a", 0.0, 1.2)


func _process(_delta: float) -> void:
	if world == null or world.player == null:
		return
	var roaming: bool = world.hud.visible and world.get_parent().get(&"mode") == Game.Mode.WORLD
	_root.visible = roaming
	if not roaming:
		return
	var o := world.objective()
	_title.text = str(o["title"])
	_text.text = str(o["text"])
	_kanji.text = str(o["kanji"])
	var at: Variant = o["at"]
	if at == null:
		_dist.text = ""
		_marker.visible = false
		return
	var d := (at as Vector3).distance_to(world.player.global_position)
	_dist.text = "%d m" % roundi(d)
	_place_marker(at, d)


## The marker sits over the objective, or on the screen's edge pointing at it.
func _place_marker(at: Vector3, d: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_marker.visible = false
		return
	_marker.visible = true
	var screen := get_viewport().get_visible_rect().size
	var target := at + Vector3.UP * 2.0
	var behind := cam.is_position_behind(target)
	var p := cam.unproject_position(target)
	if behind:
		p = screen - p
	var inside := Rect2(Vector2(EDGE, EDGE), screen - Vector2(EDGE, EDGE) * 2.0)
	var pinned := behind or not inside.has_point(p)
	if pinned:
		var c := screen * 0.5
		var dir := (p - c).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN
		var scale := minf((c.x - EDGE) / maxf(absf(dir.x), 0.001), (c.y - EDGE) / maxf(absf(dir.y), 0.001))
		p = c + dir * scale
	# The UI is laid out at 1920x1080 and scaled to the window.
	var ui_scale := _root.get_global_rect().size / screen if screen.x > 0 else Vector2.ONE
	_marker.position = p * ui_scale - _marker.size * 0.5
	_marker.set_meta(&"pinned", pinned)
	_marker_dist.text = "%d m" % roundi(d)
	_marker.queue_redraw()


func _draw_marker() -> void:
	var c := _marker.size * 0.5
	var r := 14.0
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	_marker.draw_colored_polygon(pts, Color(UiKit.GOLD, 0.95))
	pts.append(pts[0])
	_marker.draw_polyline(pts, UiKit.INK, 3.0, true)
	_marker.draw_circle(c, 4.0, UiKit.INK)
