class_name UiKit
extends RefCounted
## The ninja-scroll look shared by HUD and menus: washi paper, sumi ink,
## vermilion seals. Text on paper is dark ink (high contrast); text over
## the 3D scene gets an ink outline.

const PAPER := Color("efe6d2")
const PAPER_DARK := Color("d8c8a6")
const INK := Color("1b1a1f")
const INK_SOFT := Color("55505a")
const CRIMSON := Color("b8321f")
const CRIMSON_DARK := Color("7a1e12")
const GOLD := Color("c9a45c")
const HEALTH := Color("b3261e")
const CHAKRA := Color("2f5fb3")
const WOOD := Color("4a2d1b")

const FONT_BODY := "res://assets/fonts/ZenKakuGothicNew-Medium-Subset.ttf"
const FONT_BOLD := "res://assets/fonts/ZenKakuGothicNew-Bold-Subset.ttf"
const FONT_DISPLAY := "res://assets/fonts/Shojumaru-Regular.ttf"
const FONT_BRUSH := "res://assets/fonts/YujiSyuku-Subset.ttf"

static var _fonts: Dictionary = {}
static var _theme: Theme


## kind: &"body", &"bold", &"display" (Japanese-styled Latin titles) or
## &"brush" (calligraphy, used for kanji).
static func font(kind: StringName = &"body") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var path: String = {&"bold": FONT_BOLD, &"display": FONT_DISPLAY, &"brush": FONT_BRUSH}.get(kind, FONT_BODY)
	var f := (load(path) as FontFile).duplicate() as FontFile
	# Kanji fall back to the brush font; anything else to the body font.
	var fallbacks: Array[Font] = []
	if kind != &"brush":
		fallbacks.append(load(FONT_BRUSH))
	if kind != &"body":
		fallbacks.append(load(FONT_BODY))
	f.fallbacks = fallbacks
	_fonts[kind] = f
	return f


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font(&"body")
	t.default_font_size = 24
	t.set_color(&"font_color", &"Label", INK)

	# Buttons: ink text on paper; the focused/hovered one gets a slanted
	# vermilion brush-block so controller users always see where they are.
	var normal := _box(Color(0, 0, 0, 0))
	normal.border_width_bottom = 2
	normal.border_color = Color(INK, 0.35)
	var hover := _box(Color(CRIMSON, 0.16))
	var focus := _box(CRIMSON)
	focus.skew = Vector2(0.18, 0)
	focus.border_width_bottom = 3
	focus.border_color = CRIMSON_DARK
	var pressed := _box(CRIMSON_DARK)
	pressed.skew = Vector2(0.18, 0)
	for cls in [&"Button", &"OptionButton", &"CheckButton", &"CheckBox"]:
		t.set_stylebox(&"normal", cls, normal)
		t.set_stylebox(&"hover", cls, hover)
		t.set_stylebox(&"pressed", cls, pressed)
		t.set_stylebox(&"hover_pressed", cls, pressed)
		t.set_stylebox(&"focus", cls, focus)
		t.set_color(&"font_color", cls, INK)
		t.set_color(&"font_hover_color", cls, INK)
		t.set_color(&"font_pressed_color", cls, PAPER)
		t.set_color(&"font_hover_pressed_color", cls, PAPER)
		t.set_color(&"font_focus_color", cls, PAPER)
		t.set_font(&"font", cls, font(&"bold"))
	# Focus draws *over* the normal box, so the text under it must switch
	# colour: Button handles that via font_focus_color above.

	var off := _dot_icon(30, false)
	var on := _dot_icon(30, true)
	for cls in [&"CheckButton", &"CheckBox"]:
		t.set_icon(&"unchecked", cls, off)
		t.set_icon(&"checked", cls, on)
		t.set_icon(&"unchecked_disabled", cls, off)
		t.set_icon(&"checked_disabled", cls, on)
	t.set_icon(&"arrow", &"OptionButton", _diamond_icon(16, INK))

	var track := _box(Color(INK, 0.55))
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox(&"slider", &"HSlider", track)
	var filled := _box(CRIMSON)
	filled.content_margin_top = 3
	filled.content_margin_bottom = 3
	t.set_stylebox(&"grabber_area", &"HSlider", filled)
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", filled)
	t.set_icon(&"grabber", &"HSlider", _diamond_icon(26, INK))
	t.set_icon(&"grabber_highlight", &"HSlider", _diamond_icon(30, CRIMSON))
	var slider_focus := _box(Color(0, 0, 0, 0))
	slider_focus.border_color = CRIMSON
	slider_focus.set_border_width_all(2)
	t.set_stylebox(&"focus", &"HSlider", slider_focus)

	var popup := _box(PAPER)
	popup.set_border_width_all(2)
	popup.border_color = INK
	t.set_stylebox(&"panel", &"PopupMenu", popup)
	t.set_color(&"font_color", &"PopupMenu", INK)
	t.set_color(&"font_hover_color", &"PopupMenu", PAPER)
	t.set_stylebox(&"hover", &"PopupMenu", _box(CRIMSON))
	t.set_stylebox(&"panel", &"TooltipPanel", popup)
	t.set_color(&"font_color", &"TooltipLabel", INK)

	var grab := _box(Color(INK, 0.55))
	grab.set_corner_radius_all(4)
	var grab_hi := _box(CRIMSON)
	grab_hi.set_corner_radius_all(4)
	t.set_stylebox(&"grabber", &"VScrollBar", grab)
	t.set_stylebox(&"grabber_highlight", &"VScrollBar", grab_hi)
	t.set_stylebox(&"grabber_pressed", &"VScrollBar", grab_hi)
	t.set_stylebox(&"scroll", &"VScrollBar", _box(Color(INK, 0.08)))
	t.set_stylebox(&"panel", &"PanelContainer", StyleBoxEmpty.new())
	_theme = t
	return t


static func _box(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func label(text: String, size := 24, color := INK, kind: StringName = &"body", outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override(&"font", font(kind))
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	if outline > 0:
		l.add_theme_color_override(&"font_outline_color", INK)
		l.add_theme_constant_override(&"outline_size", outline)
	return l


## Label for text drawn straight over the 3D scene.
static func scene_label(text: String, size := 22, color := PAPER, kind: StringName = &"bold") -> Label:
	return label(text, size, color, kind, 8)


static func seal_glyph(seal: int) -> String:
	var dir := InputDevice.glyph(Seal.DIRECTION_ACTIONS[Seal.direction_of(seal)])
	var bank := Seal.bank_of(seal)
	if bank == 0:
		return dir
	return "%s + %s" % [InputDevice.glyph(Seal.BANK_ACTIONS[bank]), dir]


## Input icons for one seal on the active device, e.g. [LB] + [Y].
static func seal_glyphs(seal: int, height := 30.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var bank := Seal.bank_of(seal)
	if bank > 0:
		row.add_child(InputGlyph.for_action(Seal.BANK_ACTIONS[bank], height))
		row.add_child(label("+", int(height * 0.6), INK_SOFT, &"bold"))
	row.add_child(InputGlyph.for_action(Seal.DIRECTION_ACTIONS[Seal.direction_of(seal)], height))
	return row


static func jutsu_tag(j: JutsuDefinition) -> String:
	return "%s · %s-rank · %d chakra" % [Element.display_name(j.element), j.rank, roundi(j.chakra_cost)]


# --- Procedural icons ------------------------------------------------------------

static func _dot_icon(size: int, filled: bool) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var r := size * 0.42
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var ring := clampf(1.0 - absf(d - r) / 1.6, 0.0, 1.0)
			var col := Color(INK, ring)
			if filled:
				var fill := clampf(r - 3.0 - d, 0.0, 1.0)
				col = col.blend(Color(CRIMSON, fill))
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func _diamond_icon(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size * 0.5
	for y in size:
		for x in size:
			var d := (absf(x + 0.5 - c) + absf(y + 0.5 - c)) / c
			img.set_pixel(x, y, Color(color, clampf((1.0 - d) * c * 0.9, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
