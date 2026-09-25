class_name CharacterModel
extends Node3D
## Loads the playable character and adapts it to the game.
##
## Drop your VRoid Studio export at res://assets/characters/player.vrm and it
## replaces the placeholder automatically (see docs/CHARACTERS.md). Any
## humanoid .vrm/.glb/.fbx whose skeleton uses Godot's humanoid bone names works.

const USER_MODEL := "res://assets/characters/player.vrm"
const DEFAULT_MODEL := "res://assets/characters/default/godette.vrm"

## Force a specific model (used by tests); empty = auto.
@export_file("*.vrm", "*.glb", "*.gltf", "*.fbx", "*.tscn") var model_path := ""
## Models outside [min_height, max_height] metres are rescaled to target_height
## (placeholder assets are often authored at odd scales). Real VRoid exports
## are left at their designed height.
@export var target_height := 1.65
@export var min_height := 1.3
@export var max_height := 2.1

var instance: Node3D
var skeleton: Skeleton3D
var poser: HumanoidPoser
## The VRM's expression player (blink, happy, angry...), if any.
var expressions: AnimationPlayer
var loaded_path := ""


func _ready() -> void:
	load_model(resolve_path())


func resolve_path() -> String:
	if model_path != "":
		return model_path
	if ResourceLoader.exists(USER_MODEL):
		return USER_MODEL
	return DEFAULT_MODEL


func load_model(path: String) -> void:
	if instance:
		instance.queue_free()
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("CharacterModel: could not load %s" % path)
		return
	loaded_path = path
	instance = scene.instantiate() as Node3D
	add_child(instance)

	var skeletons := instance.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_error("CharacterModel: %s has no Skeleton3D" % path)
		return
	skeleton = skeletons[0]
	expressions = instance.get_node_or_null("AnimationPlayer") as AnimationPlayer

	poser = HumanoidPoser.new()
	poser.name = "HumanoidPoser"
	skeleton.add_child(poser)
	if poser.setup(skeleton):
		_face_forward()
	_normalize_height()


## Turns the model so it faces -Z (Godot's forward). VRM models face +Z.
func _face_forward() -> void:
	var to_local := global_basis.inverse() * skeleton.global_basis
	var fwd := to_local * poser.forward_in_skeleton()
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return
	instance.rotate_y(atan2(-fwd.x, -fwd.z) * -1.0)


func _normalize_height() -> void:
	var height := measure_height()
	if height <= 0.01 or (height >= min_height and height <= max_height):
		return
	instance.scale *= target_height / height


func measure_height() -> float:
	var lo := INF
	var hi := -INF
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var to_local := global_transform.affine_inverse() * mi.global_transform
		var box := to_local * mi.get_aabb()
		lo = minf(lo, box.position.y)
		hi = maxf(hi, box.end.y)
	return hi - lo if hi > lo else 0.0


func play_expression(expression: StringName) -> void:
	if expressions and expressions.has_animation(expression):
		expressions.play(expression)
