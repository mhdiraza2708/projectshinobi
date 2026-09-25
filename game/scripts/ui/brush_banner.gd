class_name BrushBanner
extends Control
## Announces a cast: an ink brush stroke sweeps in, the jutsu name appears in
## display type with an element seal, then everything fades. Failures use a
## dark vermilion stroke with smaller text.

const SHADER := preload("res://assets/ui/shaders/brush_band.gdshader")
const BAND_SIZE := Vector2(860, 116)

var _band: ColorRect
var _mat: ShaderMaterial
var _title: Label
var _hanko: Hanko
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = BAND_SIZE
	size = BAND_SIZE
	modulate.a = 0.0


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"rect_size", BAND_SIZE)
	_band = ColorRect.new()
	_band.material = _mat
	_band.size = BAND_SIZE
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_band)
	_hanko = Hanko.make("火", 78.0)
	_hanko.position = Vector2(110, (BAND_SIZE.y - 78.0) * 0.5)
	add_child(_hanko)
	_title = UiKit.label("", 54, UiKit.PAPER, &"display")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.position = Vector2(0, 0)
	_title.size = BAND_SIZE
	add_child(_title)


## kind: &"cast" (big, with element seal), &"fail" or &"info".
func show_text(text: String, kind: StringName = &"info", element := Element.NONE) -> void:
	if _tween:
		_tween.kill()
	_title.text = text
	var cast := kind == &"cast"
	_hanko.visible = cast
	_hanko.text = Element.kanji(element)
	_hanko.color = UiKit.CRIMSON if element == Element.NONE else Element.color(element).darkened(0.35)
	_title.add_theme_font_size_override(&"font_size", 54 if cast else 30)
	_title.add_theme_font_override(&"font", UiKit.font(&"display" if cast else &"bold"))
	_title.add_theme_color_override(&"font_color", UiKit.PAPER if kind != &"fail" else Color("ffb3a6"))
	_mat.set_shader_parameter(&"ink_color", Color(UiKit.INK, 0.9) if kind != &"fail" else Color(UiKit.CRIMSON_DARK, 0.92))
	modulate.a = 1.0
	_title.modulate.a = 0.0
	_mat.set_shader_parameter(&"progress", 0.0)
	_tween = create_tween()
	_tween.tween_method(func(p: float) -> void: _mat.set_shader_parameter(&"progress", p), 0.0, 1.0, 0.22)
	_tween.parallel().tween_property(_title, "modulate:a", 1.0, 0.18).set_delay(0.08)
	_tween.tween_interval(1.0 if cast else 1.4)
	_tween.tween_property(self, "modulate:a", 0.0, 0.45)
