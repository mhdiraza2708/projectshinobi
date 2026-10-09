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
const ROSTER_DIR := "res://assets/characters/roster"
## Used when nothing else is chosen: a CC0 VRoid Studio sample character.
const DEFAULT_MODEL := "res://assets/characters/roster/hairsample_male.vrm"
## The low-poly Godette (CC-BY), kept as a light fallback.
const PLACEHOLDER_MODEL := "res://assets/characters/default/godette.vrm"

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
## Whether this model's hair and outfit can be swapped (VRoid-style parts).
var swappable := false
## The story character this model voices: its mouth moves while Voice plays
## their lines. Empty for a model that never speaks.
var voice_id := "":
	set(value):
		voice_id = value
		set_process(value != "")

var _base_scale := Vector3.ONE
## [mesh, blend shape index, weight] per mouth shape used for talking.
var _mouth: Array = []
var _mouth_open := 0.0
var _mouth_time := 0.0


func _ready() -> void:
	set_process(voice_id != "")
	load_model(resolve_path())
	if use_profile:
		Profile.changed.connect(_on_profile_changed)




## Hair and cloth physics (VRM spring bones) jump with the body: after a
## teleport `from` -> `to` each strand's swing state (which the addon keeps
## in world space) moves with it, so the hair hangs exactly as it did instead
## of whipping across the gap. Called from inside the skeleton's modifier
## pass, before the hair simulates (HumanoidPoser.teleported).
func settle_physics(from: Transform3D, to: Transform3D) -> void:
	if instance == null:
		return
	var jump := to * from.affine_inverse()
	for node in instance.find_children("*", "", true, false):
		var springs: Variant = node.get(&"spring_bones_internal")
		if not springs is Array or node.get(&"default_springbone_center") != null:
			continue
		var centers: PackedInt32Array = node.get(&"springs_centers")
		var center_bones: Array = node.get(&"center_bones")
		var center_nodes: Array = node.get(&"center_nodes")
		for i in (springs as Array).size():
			if i >= centers.size():
				continue
			var c := centers[i]
			# Only chains simulated in world space (no centre of their own).
			if c >= center_bones.size() or center_bones[c] != -1 or center_nodes[c] != null:
				continue
			for verlet in springs[i].verlets:
				verlet.current_tail = jump * verlet.current_tail
				verlet.prev_tail = jump * verlet.prev_tail


func _process(delta: float) -> void:
	var target := Voice.level() if Voice.speaker == voice_id else 0.0
	_mouth_open = lerpf(_mouth_open, target, 1.0 - exp(-(30.0 if target > _mouth_open else 14.0) * delta))
	_mouth_time += delta
	set_mouth_open(_mouth_open)
	if animator:
		# Gesture through the line while it's being spoken.
		animator.talking = Voice.speaker == voice_id and Voice.is_speaking()


## Opens the mouth 0-1: mostly "A", shading into "O" so it doesn't just
## hinge. VRoid models only; others keep a still mouth.
func set_mouth_open(amount: float) -> void:
	var o_mix := 0.5 + 0.5 * sin(_mouth_time * 9.0)
	for entry: Array in _mouth:
		var mi: MeshInstance3D = entry[0]
		if is_instance_valid(mi):
			mi.set_blend_shape_value(entry[1], amount * (1.0 - 0.45 * o_mix if entry[2] == &"A" else 0.45 * o_mix))


func has_talking_mouth() -> bool:
	return not _mouth.is_empty()


func _find_mouth() -> void:
	_mouth.clear()
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		for i in mi.mesh.get_blend_shape_count():
			var shape := String(mi.mesh.get_blend_shape_name(i))
			if shape.ends_with("Fcl_MTH_A"):
				_mouth.append([mi, i, &"A"])
			elif shape.ends_with("Fcl_MTH_O"):
				_mouth.append([mi, i, &"O"])


func resolve_path() -> String:
	if model_path != "":
		return model_path
	if use_profile:
		var chosen: String = Profile.get_value(&"model")
		if chosen != "" and ResourceLoader.exists(chosen):
			return chosen
	return resolve_path_default()


## The character used when the profile names none.
static func resolve_path_default() -> String:
	if ResourceLoader.exists(USER_MODEL):
		return USER_MODEL
	return DEFAULT_MODEL if ResourceLoader.exists(DEFAULT_MODEL) else PLACEHOLDER_MODEL


## A roster entry by file name ("vivi") or path, or "" if there's none.
static func resolve_roster(value: String) -> String:
	if value == "":
		return ""
	if value.begins_with("res://"):
		return value if ResourceLoader.exists(value) else ""
	var path := ROSTER_DIR.path_join(value + ".vrm")
	return path if ResourceLoader.exists(path) else ""


## Friendlier names for the bundled CC0 VRoid Studio samples.
const DISPLAY_NAMES := {
	"hairsample_male": "Kai", "hairsample_female": "Nene",
	"sendagaya_shino": "Shino", "sendagaya_shibu": "Shibu", "darkness_shibu": "Darkness Shibu",
	"sakurada_fumiriya": "Fumiriya", "victoria_rubin": "Victoria", "vita": "Vita", "vivi": "Vivi",
}


static func display_name(path: String) -> String:
	var stem := path.get_file().get_basename()
	return DISPLAY_NAMES.get(stem, stem.capitalize())


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
				out.append({"path": ROSTER_DIR.path_join(file), "name": display_name(file)})
	out.append({"path": PLACEHOLDER_MODEL, "name": "Godette"})
	return out


## Character scenes read lately, newest last. A model's file isn't kept in
## memory by the characters made from it, so without this every Shade Clone
## or rival wearing a model already on screen read it from disk again: a
## tenth of a second each, a visible freeze mid-fight.
static var _scenes := {}
const SCENE_CACHE := 4


static func load_scene(path: String) -> PackedScene:
	var scene: PackedScene = _scenes.get(path)
	if scene == null:
		scene = load(path) as PackedScene
		if scene == null:
			return null
	_scenes.erase(path)
	_scenes[path] = scene
	while _scenes.size() > SCENE_CACHE:
		_scenes.erase(_scenes.keys()[0])
	return scene


func load_model(path: String) -> void:
	if instance:
		instance.queue_free()
		instance = null
	if animator:
		animator.queue_free()
		animator = null
	gear.clear()
	var scene := load_scene(path)
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
	var look := current_look()
	swappable = CharacterWardrobe.is_swappable(instance)
	CharacterWardrobe.apply(instance, skeleton, resolve_roster(look[&"hair_from"]), resolve_roster(look[&"outfit_from"]))

	poser = HumanoidPoser.new()
	poser.name = "HumanoidPoser"
	skeleton.add_child(poser)
	poser.teleported.connect(settle_physics)
	var humanoid := poser.setup(skeleton)
	if humanoid:
		_face_forward()
	_normalize_height()
	_base_scale = instance.scale

	animator = CharacterAnimator.new()
	animator.name = "CharacterAnimator"
	add_child(animator)
	animator.setup(instance, poser, clip_dir)
	animator.gear = gear

	styler.bind(instance)
	_find_mouth()
	if humanoid:
		gear.bind(skeleton, poser.canonical_frame())
	apply_profile()
	model_loaded.emit()


const GEAR_KEYS: PackedStringArray = ["headband", "headband_color", "mask", "mask_color", "scarf",
	"scarf_color", "back", "pouch", "gear_scale", "gear_lift"]

## The look applied when the model isn't following the Profile (enemies).
## Same keys as Profile: "tints" {slot: Color}, gear keys, "height",
## "expression". Missing keys keep Profile defaults.
var style: Dictionary = {}


## The look to wear: the Profile's, or `style` (over Profile defaults) when
## use_profile is off.
func current_look() -> Dictionary:
	var look := {}
	for key: StringName in Profile.DEFAULTS:
		look[key] = Profile.get_value(key) if use_profile else style.get(String(key), Profile.DEFAULTS[key])
	if use_profile:
		# An eye art colours the eyes.
		var art := Perks.active_eye_art()
		if not art.is_empty():
			var tints: Dictionary = (look[&"tints"] as Dictionary).duplicate()
			tints["eyes"] = Color(str(art["color"]))
			look[&"tints"] = tints
	return look


## Applies colours, gear, height and expression from the Profile, or from
## `style` when use_profile is off.
func apply_profile() -> void:
	if instance == null:
		return
	var look := current_look()
	for slot in styler.available_slots():
		var tints: Dictionary = look[&"tints"]
		styler.apply_tint(slot, tints.get(slot, Color.WHITE))
	if skeleton and poser and poser.active:
		var settings := {}
		for key in GEAR_KEYS:
			settings[key] = look[StringName(key)]
		gear.rebuild(settings)
	instance.scale = _base_scale * float(look[&"height"])
	play_expression(StringName(look[&"expression"]))


## Replaces the look (for models that don't follow the Profile).
func apply_style(new_style: Dictionary) -> void:
	style = new_style
	apply_profile()


func _on_profile_changed(key: StringName) -> void:
	if key in [&"hair_from", &"outfit_from"]:
		load_model(resolve_path())
		return
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
