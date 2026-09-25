class_name UiKit
extends RefCounted
## Shared look for HUD and menus, plus device-aware seal glyphs.

const TEXT := Color(0.95, 0.94, 0.9)
const MUTED := Color(0.7, 0.72, 0.78)
const ACCENT := Color(0.93, 0.35, 0.23)
const PANEL := Color(0.06, 0.07, 0.11, 0.82)
const HEALTH := Color(0.86, 0.24, 0.24)
const CHAKRA := Color(0.3, 0.6, 1.0)
const FAIL := Color(1.0, 0.55, 0.45)

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 24
	t.set_color(&"font_color", &"Label", TEXT)

	t.set_stylebox(&"panel", &"PanelContainer", panel_style())
	t.set_stylebox(&"panel", &"Panel", panel_style())

	var normal := _box(Color(0.14, 0.15, 0.21), 6)
	var hover := _box(Color(0.22, 0.23, 0.31), 6)
	var pressed := _box(ACCENT.darkened(0.3), 6)
	# A thick, high-contrast focus ring so controller/keyboard users always
	# know where they are.
	var focus := _box(Color(0, 0, 0, 0), 6)
	focus.border_color = ACCENT.lightened(0.2)
	focus.set_border_width_all(4)
	for cls in [&"Button", &"OptionButton", &"CheckButton", &"CheckBox"]:
		t.set_stylebox(&"normal", cls, normal)
		t.set_stylebox(&"hover", cls, hover)
		t.set_stylebox(&"pressed", cls, pressed)
		t.set_stylebox(&"focus", cls, focus)
		t.set_color(&"font_color", cls, TEXT)
		t.set_color(&"font_hover_color", cls, TEXT)
	t.set_stylebox(&"focus", &"HSlider", focus)
	t.set_stylebox(&"background", &"ProgressBar", _box(Color(0, 0, 0, 0.55), 4))
	_theme = t
	return t


static func panel_style() -> StyleBoxFlat:
	var s := _box(PANEL, 10)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


static func _box(color: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func label(text: String, size := 24, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", Color.BLACK)
	l.add_theme_constant_override(&"outline_size", 4)
	return l


static func bar(color: Color, width := 360.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(width, 22)
	b.show_percentage = false
	var fill := _box(color, 4)
	b.add_theme_stylebox_override(&"fill", fill)
	return b


## The input(s) for one seal on the active device, e.g. "LB + Y" or "Shift + W".
static func seal_glyph(seal: int) -> String:
	var dir := InputDevice.glyph(Seal.DIRECTION_ACTIONS[Seal.direction_of(seal)])
	var bank := Seal.bank_of(seal)
	if bank == 0:
		return dir
	return "%s + %s" % [InputDevice.glyph(Seal.BANK_ACTIONS[bank]), dir]


static func sequence_glyphs(seals: Array) -> String:
	return "  ›  ".join(seals.map(func(s: int) -> String: return seal_glyph(s)))


static func jutsu_tag(j: JutsuDefinition) -> String:
	return "%s · %s-rank · %d chakra" % [Element.display_name(j.element), j.rank, roundi(j.chakra_cost)]
