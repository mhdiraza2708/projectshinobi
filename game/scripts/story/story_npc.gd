class_name StoryNpc
extends Node3D
## A story character standing in the scene: their look, a name tag, and
## body language while talking. They arrive and leave in a puff of smoke
## (the body flicker every shinobi learns), so no walking is needed.

var who := ""
## Roster character (file name) to use; empty picks one from the roster.
var model_name := ""
var display_name := ""
var element := Element.NONE
var style: Dictionary = {}
## Turn to face this node (usually the player).
var look_at_node: Node3D
var model: CharacterModel

var _tag: Label3D


func _ready() -> void:
	model = CharacterModel.new()
	model.name = "Model"
	model.use_profile = false
	var chosen := CharacterModel.resolve_roster(model_name)
	model.model_path = chosen if chosen != "" else EnemyShinobi.pick_model(who)
	model.style = style
	add_child(model)
	_tag = Label3D.new()
	_tag.text = display_name
	_tag.font = UiKit.font(&"bold")
	_tag.font_size = 26
	_tag.outline_size = 8
	_tag.outline_modulate = Color(UiKit.INK, 0.85)
	_tag.modulate = Element.color(element).lightened(0.45)
	_tag.pixel_size = 0.01
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.position.y = 2.2
	add_child(_tag)
	_puff()


func _process(delta: float) -> void:
	if is_instance_valid(look_at_node):
		var to := look_at_node.global_position - global_position
		if Vector2(to.x, to.z).length() > 0.05:
			rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-6.0 * delta))
	if model.animator:
		model.animator.speed_ratio = 0.0


## A small gesture and the line's expression, when this character speaks.
func speak(mood: String) -> void:
	if model.animator:
		model.animator.seal_flick()
	model.play_expression(StringName(mood if mood != "" else str(style.get("expression", "neutral"))))


## Leaves in a puff of smoke.
func vanish() -> void:
	_puff()
	queue_free()


func _puff() -> void:
	var parent := get_parent()
	if parent:
		Vfx.burst(parent, global_position + Vector3.UP, Color(0.9, 0.9, 0.92), 1.4, 0.45)
	Sfx.play_at(&"smoke", global_position + Vector3.UP, -3.0)
