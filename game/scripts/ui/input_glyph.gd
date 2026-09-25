class_name InputGlyph
extends Control
## Draws the button/key for an action on the active device: keycaps, mouse
## buttons, and controller buttons in each pad family's style (Xbox colours,
## PlayStation shapes, Nintendo letters). Updates live when the player
## switches device or rebinds.

const XBOX_COLORS := {
	JOY_BUTTON_A: Color("3f9b41"), JOY_BUTTON_B: Color("c8372d"),
	JOY_BUTTON_X: Color("2f63b8"), JOY_BUTTON_Y: Color("d9a21b"),
}
const PS_SYMBOL_COLORS := {
	JOY_BUTTON_A: Color("7aa7e8"), JOY_BUTTON_B: Color("e0605a"),
	JOY_BUTTON_X: Color("e68ab8"), JOY_BUTTON_Y: Color("5fc4a0"),
}
const PAD_BODY := Color("26252b")
const PAD_TEXT := Color("f4f1ea")

## Action to show (follows device changes and rebinding).
var action: StringName
## Force a device (-1 follows the active device).
var device := -1
## Show this binding instead of looking one up.
var binding: Dictionary = {}
var glyph_height := 32.0


static func for_action(action_name: StringName, height := 32.0, force_device := -1) -> InputGlyph:
	var g := InputGlyph.new()
	g.action = action_name
	g.glyph_height = height
	g.device = force_device
	return g


static func for_binding(b: Dictionary, height := 32.0) -> InputGlyph:
	var g := InputGlyph.new()
	g.binding = b
	g.glyph_height = height
	return g


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _ready() -> void:
	InputDevice.device_changed.connect(func(_d: Binding.Device) -> void: _refresh())
	Settings.bindings_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	update_minimum_size()
	queue_redraw()


func current_binding() -> Dictionary:
	if not binding.is_empty():
		return binding
	var dev: Binding.Device = InputDevice.current if device < 0 else device as Binding.Device
	var list := Settings.get_bindings_for_device(action, dev)
	return list[0] if not list.is_empty() else {}


func _get_minimum_size() -> Vector2:
	var b := current_binding()
	var h := glyph_height
	match b.get("type", ""):
		Binding.TYPE_KEY:
			var w := _text_width(_key_text(b), int(h * 0.48)) + h * 0.55
			return Vector2(maxf(h, w), h)
		Binding.TYPE_MOUSE:
			return Vector2(h * 0.72, h)
		Binding.TYPE_JOY_BUTTON:
			var code := int(b["code"])
			if code in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
				return Vector2(h * 1.45, h)
			if code in [JOY_BUTTON_BACK, JOY_BUTTON_START, JOY_BUTTON_GUIDE]:
				return Vector2(maxf(h * 1.3, _text_width(_label(b), int(h * 0.36)) + h * 0.5), h)
			return Vector2(h, h)
		Binding.TYPE_JOY_AXIS:
			var axis := int(b["code"])
			if axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
				return Vector2(h * 1.2, h)
			return Vector2(h, h)
	return Vector2(_text_width("—", int(h * 0.5)) + 8.0, h)


func _draw() -> void:
	var b := current_binding()
	var h := glyph_height
	var r := Rect2(Vector2.ZERO, size)
	match b.get("type", ""):
		Binding.TYPE_KEY:
			_draw_key(r, _key_text(b))
		Binding.TYPE_MOUSE:
			_draw_mouse(r, int(b["code"]))
		Binding.TYPE_JOY_BUTTON:
			var code := int(b["code"])
			if code >= JOY_BUTTON_A and code <= JOY_BUTTON_Y:
				_draw_face(r, code)
			elif code >= JOY_BUTTON_DPAD_UP and code <= JOY_BUTTON_DPAD_RIGHT:
				_draw_dpad(r, code)
			elif code in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
				_draw_tab(r, _label(b), false)
			elif code in [JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK]:
				_draw_stick(r, "L" if code == JOY_BUTTON_LEFT_STICK else "R", Vector2.ZERO, true)
			else:
				_draw_pill(r, _label(b))
		Binding.TYPE_JOY_AXIS:
			var axis := int(b["code"])
			var dir := float(b.get("dir", 1))
			match axis:
				JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT:
					_draw_tab(r, _label(b), true)
				JOY_AXIS_LEFT_X, JOY_AXIS_RIGHT_X:
					_draw_stick(r, "L" if axis == JOY_AXIS_LEFT_X else "R", Vector2(dir, 0), false)
				_:
					_draw_stick(r, "L" if axis == JOY_AXIS_LEFT_Y else "R", Vector2(0, dir), false)
		_:
			_text(r, "—", int(h * 0.5), UiKit.INK_SOFT)


func _label(b: Dictionary) -> String:
	return Binding.label(b, InputDevice.gamepad_family)


func _key_text(b: Dictionary) -> String:
	var t := Binding.label(b)
	var short := {"Escape": "Esc", "Space": "Space", "Shift": "Shift", "Tab": "Tab", "Up": "↑",
		"Down": "↓", "Left": "←", "Right": "→", "Enter": "Enter", "Backspace": "Bksp"}
	return short.get(t, t)


func _text_width(t: String, fs: int) -> float:
	return UiKit.font(&"bold").get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func _text(r: Rect2, t: String, fs: int, color: Color) -> void:
	var f := UiKit.font(&"bold")
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var y := r.position.y + (r.size.y + f.get_ascent(fs) - f.get_descent(fs)) * 0.5
	draw_string(f, Vector2(r.position.x + (r.size.x - w) * 0.5, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _draw_key(r: Rect2, t: String) -> void:
	var cap := StyleBoxFlat.new()
	cap.bg_color = UiKit.PAPER
	cap.set_corner_radius_all(int(r.size.y * 0.18))
	cap.set_border_width_all(2)
	cap.border_width_bottom = 4
	cap.border_color = UiKit.INK
	draw_style_box(cap, r)
	_text(Rect2(r.position, r.size - Vector2(0, 2)), t, int(r.size.y * 0.48), UiKit.INK)


func _draw_mouse(r: Rect2, button: int) -> void:
	var body := StyleBoxFlat.new()
	body.bg_color = UiKit.PAPER
	body.set_corner_radius_all(int(r.size.x * 0.5))
	body.set_border_width_all(2)
	body.border_color = UiKit.INK
	draw_style_box(body, r)
	var mid_y := r.position.y + r.size.y * 0.45
	var cx := r.position.x + r.size.x * 0.5
	var hl := Color(UiKit.CRIMSON)
	match button:
		MOUSE_BUTTON_LEFT:
			draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(r.size.x * 0.5 - 3, mid_y - r.position.y - 3)), hl)
		MOUSE_BUTTON_RIGHT:
			draw_rect(Rect2(Vector2(cx, r.position.y + 3), Vector2(r.size.x * 0.5 - 3, mid_y - r.position.y - 3)), hl)
		MOUSE_BUTTON_MIDDLE:
			draw_rect(Rect2(Vector2(cx - 3, r.position.y + r.size.y * 0.14), Vector2(6, r.size.y * 0.22)), hl)
	draw_line(Vector2(r.position.x + 2, mid_y), Vector2(r.end.x - 2, mid_y), UiKit.INK, 2.0)
	draw_line(Vector2(cx, r.position.y + 2), Vector2(cx, mid_y), UiKit.INK, 2.0)


func _draw_face(r: Rect2, code: int) -> void:
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) * 0.5 - 1.0
	match InputDevice.gamepad_family:
		"playstation":
			draw_circle(c, rad, PAD_BODY)
			var col: Color = PS_SYMBOL_COLORS[code]
			var s := rad * 0.45
			match code:
				JOY_BUTTON_A:
					draw_line(c - Vector2(s, s), c + Vector2(s, s), col, 2.5, true)
					draw_line(c + Vector2(-s, s), c + Vector2(s, -s), col, 2.5, true)
				JOY_BUTTON_B:
					draw_arc(c, s, 0.0, TAU, 32, col, 2.5, true)
				JOY_BUTTON_X:
					draw_rect(Rect2(c - Vector2(s, s) * 0.85, Vector2(s, s) * 1.7), col, false, 2.5)
				JOY_BUTTON_Y:
					var pts := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, s * 0.7), c + Vector2(-s, s * 0.7), c + Vector2(0, -s)])
					draw_polyline(pts, col, 2.5, true)
		"nintendo":
			draw_circle(c, rad, PAD_BODY)
			_text(r, _label({"type": Binding.TYPE_JOY_BUTTON, "code": code}), int(rad * 1.1), PAD_TEXT)
		_:
			draw_circle(c, rad, XBOX_COLORS[code])
			draw_arc(c, rad, 0.0, TAU, 32, Color(0, 0, 0, 0.35), 1.5, true)
			_text(r, _label({"type": Binding.TYPE_JOY_BUTTON, "code": code}), int(rad * 1.15), PAD_TEXT)


func _draw_dpad(r: Rect2, code: int) -> void:
	var c := r.get_center()
	var arm := minf(r.size.x, r.size.y) * 0.5 - 1.0
	var w := arm * 0.7
	var idle := Color(PAD_BODY, 0.4)
	draw_rect(Rect2(c - Vector2(w * 0.5, arm), Vector2(w, arm * 2.0)), idle)
	draw_rect(Rect2(c - Vector2(arm, w * 0.5), Vector2(arm * 2.0, w)), idle)
	var dir: Vector2 = {JOY_BUTTON_DPAD_UP: Vector2.UP, JOY_BUTTON_DPAD_DOWN: Vector2.DOWN,
		JOY_BUTTON_DPAD_LEFT: Vector2.LEFT, JOY_BUTTON_DPAD_RIGHT: Vector2.RIGHT}[code]
	# The pressed arm lights up in full.
	var along := dir * arm
	var across := Vector2(-dir.y, dir.x) * w * 0.5
	var arm_poly := PackedVector2Array([c + across, c + along + across, c + along - across, c - across])
	draw_colored_polygon(arm_poly, UiKit.CRIMSON)
	arm_poly.append(arm_poly[0])
	draw_polyline(arm_poly, PAD_BODY, 1.5, true)


func _draw_tab(r: Rect2, t: String, trigger: bool) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = PAD_BODY
	box.corner_radius_top_left = int(r.size.y * (0.45 if trigger else 0.35))
	box.corner_radius_top_right = box.corner_radius_top_left
	box.corner_radius_bottom_left = int(r.size.y * 0.12)
	box.corner_radius_bottom_right = box.corner_radius_bottom_left
	draw_style_box(box, r)
	_text(r, t, int(r.size.y * 0.4), PAD_TEXT)


func _draw_pill(r: Rect2, t: String) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = PAD_BODY
	box.set_corner_radius_all(int(r.size.y * 0.5))
	var inner := Rect2(r.position + Vector2(0, r.size.y * 0.18), Vector2(r.size.x, r.size.y * 0.64))
	draw_style_box(box, inner)
	_text(inner, t, int(r.size.y * 0.36), PAD_TEXT)


func _draw_stick(r: Rect2, side: String, dir: Vector2, click: bool) -> void:
	# The stick's thumb cap is drawn pushed in the bound direction, so Move
	# Up/Down/Left/Right are distinguishable at a glance.
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) * 0.5 - 1.0
	draw_circle(c, rad, Color(PAD_BODY, 0.55))
	draw_arc(c, rad, 0.0, TAU, 32, PAD_BODY, 1.5, true)
	var cap := c + dir * rad * 0.42
	var cap_r := rad * 0.62
	draw_circle(cap, cap_r, UiKit.CRIMSON if dir != Vector2.ZERO else PAD_BODY)
	draw_arc(cap, cap_r, 0.0, TAU, 32, PAD_BODY, 1.5, true)
	var label := side + ("3" if click and InputDevice.gamepad_family == "playstation" else "")
	_text(Rect2(cap - Vector2.ONE * cap_r, Vector2.ONE * cap_r * 2.0), label, int(cap_r * 1.2), PAD_TEXT)
