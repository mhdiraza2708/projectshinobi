class_name PaperPanel
extends PanelContainer
## A container drawn as a torn sheet of washi paper (shader-based, so it stays
## crisp at any UI scale). Children are laid out on top of the paper.

const SHADER := preload("res://assets/ui/shaders/paper.gdshader")

@export var seed := 0.0
@export_range(0.0, 1.0) var opacity := 0.95
@export var tear := 7.0
@export var margin := Vector4(26, 18, 26, 18)

var _bg: ColorRect


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var box := StyleBoxEmpty.new()
	box.content_margin_left = margin.x
	box.content_margin_top = margin.y
	box.content_margin_right = margin.z
	box.content_margin_bottom = margin.w
	add_theme_stylebox_override(&"panel", box)
	_bg = ColorRect.new()
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.show_behind_parent = true
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter(&"seed", seed)
	mat.set_shader_parameter(&"opacity", opacity)
	mat.set_shader_parameter(&"tear", tear)
	_bg.material = mat
	add_child(_bg, false, Node.INTERNAL_MODE_FRONT)
	resized.connect(_fit)
	# The container lays out every child, the paper included, inside the
	# content margins; re-fit the paper to the full rect after each sort.
	sort_children.connect(_fit)
	_fit()


func _fit() -> void:
	if _bg == null:
		return
	# Extend under the content margins so the paper frames the content.
	_bg.position = Vector2.ZERO
	_bg.size = size
	(_bg.material as ShaderMaterial).set_shader_parameter(&"rect_size", size)
