class_name EyeInsert
extends CanvasLayer
## The cut-in of a dojutsu opening (eye_insert.gdshader): the screen goes
## black on two eyes under the bangs; EyeSequence drives the bangs, the lids
## and the pattern through set_state(). Above the 3D and below the
## letterbox bars, flashes and title card.

const SHADER := preload("res://assets/shaders/eye_insert.gdshader")

var material: ShaderMaterial
var _rect: ColorRect


## For `art` (an eye art: its pattern and colour).
func _init(art: Dictionary = {}) -> void:
	name = "EyeInsert"
	layer = 10
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"pattern", maxi(0, EyePattern.PATTERNS.find(str(art.get("pattern", "")))))
	material.set_shader_parameter(&"color", Color(str(art.get("color", "#ffffff"))))
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = material
	add_child(_rect)


func _process(_delta: float) -> void:
	var size := _rect.size
	if size.y > 0.0:
		material.set_shader_parameter(&"aspect", size.x / size.y)


## Where the opening has got to: each value 0..1 (spin in radians).
func set_state(lids: float, hair: float, intensity: float, spin: float, awakened := 0.0, burst := 0.0,
		fade := 1.0) -> void:
	material.set_shader_parameter(&"lids", lids)
	material.set_shader_parameter(&"hair", hair)
	material.set_shader_parameter(&"intensity", intensity)
	material.set_shader_parameter(&"spin", spin)
	material.set_shader_parameter(&"awakened", awakened)
	material.set_shader_parameter(&"burst", burst)
	material.set_shader_parameter(&"fade", fade)


func lids() -> float:
	return float(material.get_shader_parameter(&"lids"))
