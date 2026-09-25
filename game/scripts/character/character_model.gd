class_name CharacterModel
extends Node3D
## Loads the playable character and adapts it to the game.
##
## Which model, its colours, gear, height and expression come from the
## player's Profile (edited in the Customize screen). Drop your VRoid Studio
## export at res://assets/characters/player.vrm, or more characters into
## res://assets/characters/roster/, and they appear in the roster
## (see docs/CHARACTERS.md). Any humanoid .vrm/.glb/.fbx whose skeleton uses
## Godot's humanoid bone names works.

signal model_loaded

const USER_MODEL := "res://assets/characters/player.vrm"
const DEFAULT_MODEL := "res://assets/characters/default/godette.vrm"
const ROSTER_DIR := "res://assets/characters/roster"

## Force a specific model (used by tests); empty = follow the profile.
@export_file("*.vrm", "*.glb", "*.gltf", "*.fbx", "*.tscn") var model_path := ""
## Apply the saved Profile (colours, gear, height, expression) and follow
## its changes live.
@export var use_profile := true
## Models outside [min_height, max_height] metres are rescaled to target_height
## (placeholder assets are often authored at odd scales). Real VRoid exports
## are left at their designed height.
@export var target_height := 1.65
@export var min_height := 1.3
@export var max_height := 2.1
## Where retargeted Mixamo clips live (overridable for tests).
@export_dir var clip_dir := CharacterAnimator.CLIP_DIR

var instance: Node3D
var skeleton: Skeleton3D
var poser: HumanoidPoser
## Gameplay-facing animation driver (clips + procedural poser).
var animator: CharacterAnimator
## The VRM's expression player (blink, happy, angry...), if any.
var expressions: AnimationPlayer
var styler := CharacterStyler.new()
var gear := CharacterGear.new()
var loaded_path := ""

var _base_scale := Vector3.ONE


func _ready() -> void:
	load_model(resolve_path())
	if use_profile:
		Profile.changed.connect(_on_profile_changed)


func resolve_path() -> String:
	if model_path != "":
		return model_path
	if use_profile:
		var chosen: String = Profile.get_value(&"model")
		if chosen != "" and ResourceLoader.exists(chosen):
			return chosen
	if ResourceLoader.exists(USER_MODEL):
		return USER_MODEL
	return DEFAULT_MODEL


## Every selectable character: [{path, name}].
static func roster() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if ResourceLoader.exists(USER_MODEL):
		out.append({"path": USER_MODEL, "name": "Your character"})
	if DirAccess.dir_exists_absolute(ROSTER_DIR):
		var files := Array(ResourceLoader.list_directory(ROSTER_DIR))
		files.sort()
		for file: String in files:
			if file.get_extension().to_lower() in ["vrm", "glb"]:
				out.append({"path": ROSTER_DIR.path_join(file), "name": file.get_basename().capitalize()})
	out.append({"path": DEFAULT_MODEL, "name": "Godette (placeholder)"})
	return out


func load_model(path: String) -> void:
	if instance:
		instance.queue_free()
		instance = null
	if animator:
		animator.queue_free()
		animator = null
	gear.clear()
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
	var humanoid := poser.setup(skeleton)
	if humanoid:
		_face_forward()
	_normalize_height()
	_base_scale = instance.scale

	animator = CharacterAnimator.new()
	animator.name = "CharacterAnimator"
	add_child(animator)
	animator.setup(instance, poser, clip_dir)

	styler.bind(instance)
	if humanoid:
		gear.bind(skeleton, poser.canonical_frame())
	apply_profile()
	model_loaded.emit()


## Applies colours, gear, height and expression from the Profile.
func apply_profile() -> void:
	if not use_profile or instance == null:
		return
	for slot in styler.available_slots():
		styler.apply_tint(slot, Profile.tint(slot))
	if skeleton and poser and poser.active:
		var settings := {}
		for key in ["headband", "headband_color", "mask", "mask_color", "scarf", "scarf_color",
				"back", "pouch", "gear_scale", "gear_lift"]:
			settings[key] = Profile.get_value(StringName(key))
		gear.rebuild(settings)
	instance.scale = _base_scale * float(Profile.get_value(&"height"))
	play_expression(StringName(Profile.get_value(&"expression")))


func _on_profile_changed(key: StringName) -> void:
	if key == &"model" or key == &"":
		var path := resolve_path()
		if path != loaded_path:
			load_model(path)
			return
	apply_profile()


## Turns the model so it faces -Z (Godot's forward). VRM models face +Z.
func _face_forward() -> void:
	var to_local := global_basis.inverse() * skeleton.global_basis
	var fwd := to_local * poser.forward_in_skeleton()
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return
	instance.rotate_y(-atan2(-fwd.x, -fwd.z))


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
		if mi.has_meta(&"gear"):
			continue
		var to_local := global_transform.affine_inverse() * mi.global_transform
		var box := to_local * mi.get_aabb()
		lo = minf(lo, box.position.y)
		hi = maxf(hi, box.end.y)
	return hi - lo if hi > lo else 0.0


func play_expression(expression: StringName) -> void:
	if expressions and expressions.has_animation(expression):
		expressions.play(expression)
