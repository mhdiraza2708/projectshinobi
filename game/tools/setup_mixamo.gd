extends SceneTree
## Configures every Mixamo FBX in res://assets/animations/mixamo/ for Godot's
## humanoid retargeting, so the clips play on any VRM/humanoid character.
##
## Run via `make animations`, which imports, runs this, and re-imports:
##   godot --headless --path game --import
##   godot --headless --path game --script res://tools/setup_mixamo.gd
##   godot --headless --path game --import
##
## What it sets (the same as doing it by hand in the Import dock):
##   Skeleton3D > Retarget > Bone Map = mixamo_bone_map.tres (humanoid profile)
##   rename bones, unique skeleton name "GeneralSkeleton", rest fixer set to
##   "Overwrite Axis" (matching godot-vrm's skeleton normalisation).

const CLIP_DIR := "res://assets/animations/mixamo"
const BONE_MAP_PATH := "res://assets/animations/mixamo_bone_map.tres"

## Godot humanoid profile bone -> Mixamo bone (after Godot turns ':' into '_').
const MIXAMO := {
	&"Hips": "Hips", &"Spine": "Spine", &"Chest": "Spine1", &"UpperChest": "Spine2",
	&"Neck": "Neck", &"Head": "Head",
}
const SIDE_MAP := {
	"Shoulder": "Shoulder", "UpperArm": "Arm", "LowerArm": "ForeArm", "Hand": "Hand",
	"ThumbMetacarpal": "HandThumb1", "ThumbProximal": "HandThumb2", "ThumbDistal": "HandThumb3",
	"IndexProximal": "HandIndex1", "IndexIntermediate": "HandIndex2", "IndexDistal": "HandIndex3",
	"MiddleProximal": "HandMiddle1", "MiddleIntermediate": "HandMiddle2", "MiddleDistal": "HandMiddle3",
	"RingProximal": "HandRing1", "RingIntermediate": "HandRing2", "RingDistal": "HandRing3",
	"LittleProximal": "HandPinky1", "LittleIntermediate": "HandPinky2", "LittleDistal": "HandPinky3",
	"UpperLeg": "UpLeg", "LowerLeg": "Leg", "Foot": "Foot", "Toes": "ToeBase",
}


func _initialize() -> void:
	var clip_dir := CLIP_DIR
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			clip_dir = arg.trim_prefix("--dir=")
	var bone_map := build_bone_map()
	var err := ResourceSaver.save(bone_map, BONE_MAP_PATH)
	if err != OK:
		push_error("Could not save %s" % BONE_MAP_PATH)
		quit(1)
		return
	var configured := 0
	for file in DirAccess.get_files_at(clip_dir):
		if file.get_extension().to_lower() == "fbx":
			if configure(clip_dir.path_join(file)):
				configured += 1
	print("Configured %d Mixamo clip(s). Re-import to apply." % configured)
	quit(0)


static func build_bone_map() -> BoneMap:
	var map := BoneMap.new()
	map.profile = SkeletonProfileHumanoid.new()
	for profile_bone: StringName in MIXAMO:
		map.set_skeleton_bone_name(profile_bone, "mixamorig_" + MIXAMO[profile_bone])
	for side in ["Left", "Right"]:
		for part: String in SIDE_MAP:
			map.set_skeleton_bone_name(StringName(side + part), "mixamorig_%s%s" % [side, SIDE_MAP[part]])
	return map


## Writes retarget settings into `<clip>.import`. The clip must already have
## been imported once so its skeleton's node path is known.
static func configure(path: String) -> bool:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Import %s once before configuring it" % path)
		return false
	var root := scene.instantiate()
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_error("%s has no skeleton" % path)
		root.free()
		return false
	var skel_path := String(root.get_path_to(skeletons[0]))
	root.free()

	var cfg := ConfigFile.new()
	if cfg.load(path + ".import") != OK:
		push_error("Missing %s.import" % path)
		return false
	var subresources: Dictionary = cfg.get_value("params", "_subresources", {})
	var nodes: Dictionary = subresources.get("nodes", {})
	nodes["PATH:" + skel_path] = {
		"retarget/bone_map": load(BONE_MAP_PATH),
		"retarget/bone_renamer/rename_bones": true,
		"retarget/bone_renamer/unique_node/make_unique": true,
		"retarget/bone_renamer/unique_node/skeleton_name": "GeneralSkeleton",
		"retarget/rest_fixer/apply_node_transforms": true,
		"retarget/rest_fixer/normalize_position_tracks": true,
		# 1 = "Overwrite Axis": the same bone-axis normalisation godot-vrm
		# applies to VRM skeletons, so rotations transfer 1:1.
		"retarget/rest_fixer/retarget_method": 1,
		"retarget/rest_fixer/fix_silhouette/enable": true,
		"retarget/remove_tracks/unmapped_bones": true,
	}
	subresources["nodes"] = nodes
	cfg.set_value("params", "_subresources", subresources)
	return cfg.save(path + ".import") == OK
