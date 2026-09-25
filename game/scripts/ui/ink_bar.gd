class_name InkBar
extends Control
## Health/chakra bar painted as a brush stroke. After a drop, a pale trail
## shows how much was lost, then catches up.

const SHADER := preload("res://assets/ui/shaders/ink_bar.gdshader")
const TRAIL_DELAY := 0.35
const TRAIL_SPEED := 0.9

@export var ink_color := UiKit.HEALTH
@export var seed := 1.0

var ratio := 1.0
var _trail := 1.0
var _trail_wait := 0.0
var _rect: ColorRect
var _mat: ShaderMaterial


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(360, 26)


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"ink_color", ink_color)
	_mat.set_shader_parameter(&"seed", seed)
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)
	resized.connect(_fit)
	_fit()
	_push()


func set_ratio(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if value < ratio:
		_trail = maxf(_trail, ratio)
		_trail_wait = TRAIL_DELAY
	else:
		_trail = value
	ratio = value
	_push()


func _process(delta: float) -> void:
	if _trail <= ratio:
		return
	_trail_wait -= delta
	if _trail_wait <= 0.0:
		_trail = maxf(ratio, _trail - TRAIL_SPEED * delta)
	_push()


func _fit() -> void:
	if _rect:
		_rect.size = size
		_mat.set_shader_parameter(&"rect_size", size)


func _push() -> void:
	if _mat:
		_mat.set_shader_parameter(&"value", ratio)
		_mat.set_shader_parameter(&"trail", maxf(_trail, ratio))
