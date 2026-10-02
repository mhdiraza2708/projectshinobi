class_name StoryNpc
extends Node3D
## A story character standing in the scene: their look, a name tag, and
## body language while talking. They usually arrive and leave in a puff of
## smoke (the body flicker every shinobi learns); cutscenes also walk, run,
## leap and pose them.

var who := ""
## Roster character (file name) to use; empty picks one from the roster.
var model_name := ""
var display_name := ""
var element := Element.NONE
var style: Dictionary = {}
## Turn to face this node (usually the player).
var look_at_node: Node3D
var model: CharacterModel
## Arrive without the puff of smoke (a cutscene brings them in some other way).
var quiet := false
## Body language a cutscene sets: 0 standing, 1 running; in the air; a pose.
var speed_ratio := 0.0
var airborne := false
var pose := HumanoidPoser.Pose.LOCOMOTION

var _tag: Label3D


func _ready() -> void:
	model = CharacterModel.new()
	model.name = "Model"
	model.use_profile = false
	var chosen := CharacterModel.resolve_roster(model_name)
	model.model_path = chosen if chosen != "" else EnemyShinobi.pick_model(who)
	model.style = style
	model.voice_id = who
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
	if not quiet:
		_puff()


func _process(delta: float) -> void:
	if is_instance_valid(look_at_node):
		turn_to(look_at_node.global_position, 6.0, delta)
	if model.animator:
		model.animator.run_speed = Cutscene.RUN_SPEED
		model.animator.speed_ratio = speed_ratio
		model.animator.airborne = airborne
		model.animator.pose = pose


## Turns towards a point (at once, or at `rate` per second).
func turn_to(point: Vector3, rate := 0.0, delta := 0.0) -> void:
	var to := point - global_position
	if Vector2(to.x, to.z).length() <= 0.05:
		return
	var yaw := atan2(-to.x, -to.z)
	rotation.y = yaw if rate <= 0.0 else lerp_angle(rotation.y, yaw, 1.0 - exp(-rate * (delta if delta > 0.0 else get_process_delta_time())))


func show_tag(on: bool) -> void:
	_tag.visible = on


## Back to standing and facing `node`, as after a cutscene.
func settle(node: Node3D) -> void:
	speed_ratio = 0.0
	airborne = false
	pose = HumanoidPoser.Pose.LOCOMOTION
	look_at_node = node


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
		Vfx.smoke_puff(parent, global_position + Vector3.UP, 1.0)
	Sfx.play_at(&"smoke", global_position + Vector3.UP, -3.0)
