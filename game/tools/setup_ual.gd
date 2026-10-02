extends SceneTree
## Configures the Universal Animation Library (Quaternius, CC0) in
## res://assets/animations/ual/ for Godot's humanoid retargeting, so its
## motion-captured clips play on every VRM/humanoid character. The same
## settings setup_mixamo.gd writes for Mixamo clips, with a bone map for the
## library's Rigify-style "DEF-" skeleton.
##
## Run via `make animations` (import, this, import again):
##   godot --headless --path game --script res://tools/setup_ual.gd

const LIBRARY_DIR := "res://assets/animations/ual"
const BONE_MAP_PATH := "res://assets/animations/ual_bone_map.tres"

## Godot humanoid profile bone -> library bone. The root stays unmapped: the
## game moves characters itself, so root motion is dropped.
const CENTER := {
	&"Hips": "DEF-hips", &"Spine": "DEF-spine.001", &"Chest": "DEF-spine.002",
	&"UpperChest": "DEF-spine.003", &"Neck": "DEF-neck", &"Head": "DEF-head",
}
## Per side (".L" / ".R" in the library).
const SIDE := {
	"Shoulder": "shoulder", "UpperArm": "upper_arm", "LowerArm": "forearm", "Hand": "hand",
	"ThumbMetacarpal": "thumb.01", "ThumbProximal": "thumb.02", "ThumbDistal": "thumb.03",
	"IndexProximal": "f_index.01", "IndexIntermediate": "f_index.02", "IndexDistal": "f_index.03",
	"MiddleProximal": "f_middle.01", "MiddleIntermediate": "f_middle.02", "MiddleDistal": "f_middle.03",
	"RingProximal": "f_ring.01", "RingIntermediate": "f_ring.02", "RingDistal": "f_ring.03",
	"LittleProximal": "f_pinky.01", "LittleIntermediate": "f_pinky.02", "LittleDistal": "f_pinky.03",
	"UpperLeg": "thigh", "LowerLeg": "shin", "Foot": "foot", "Toes": "toe",
}


func _initialize() -> void:
	var configured := 0
	for file in DirAccess.get_files_at(LIBRARY_DIR):
		if file.get_extension().to_lower() in ["gltf", "glb"]:
			var path := LIBRARY_DIR.path_join(file)
			var bones := skeleton_bones(path)
			if bones.is_empty():
				continue
			var bone_map := build_bone_map(bones)
			if ResourceSaver.save(bone_map, BONE_MAP_PATH) != OK:
				push_error("Could not save %s" % BONE_MAP_PATH)
				quit(1)
				return
			if configure(path):
				configured += 1
	print("Configured %d animation librar%s. Re-import to apply." % [configured, "y" if configured == 1 else "ies"])
	quit(0)


## Bone names as Godot imported them (it may tidy characters like ".").
static func skeleton_bones(path: String) -> PackedStringArray:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Import %s once before configuring it" % path)
		return PackedStringArray()
	var root := scene.instantiate()
	var names := PackedStringArray()
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var skel := skeletons[0] as Skeleton3D
		for i in skel.get_bone_count():
			names.append(skel.get_bone_name(i))
	root.free()
	return names


## Matches names loosely ("DEF-upper_arm.L" == "DEF-upper_arm_L"), so the map
## survives the importer's renaming.
static func _find(bones: PackedStringArray, wanted: String) -> String:
	var key := _loose(wanted)
	for b in bones:
		if _loose(b) == key:
			return b
	return ""


static func _loose(s: String) -> String:
	var out := ""
	for c in s.to_lower():
		if c >= "a" and c <= "z" or c >= "0" and c <= "9":
			out += c
	return out


static func build_bone_map(bones: PackedStringArray) -> BoneMap:
	var map := BoneMap.new()
	map.profile = SkeletonProfileHumanoid.new()
	var missing := []
	for profile_bone: StringName in CENTER:
		var found := _find(bones, CENTER[profile_bone])
		if found == "":
			missing.append(CENTER[profile_bone])
		map.set_skeleton_bone_name(profile_bone, found)
	for side in ["Left", "Right"]:
		var suffix := ".L" if side == "Left" else ".R"
		for part: String in SIDE:
			var wanted: String = "DEF-" + SIDE[part] + suffix
			var found := _find(bones, wanted)
			if found == "":
				missing.append(wanted)
			map.set_skeleton_bone_name(StringName(side + part), found)
	if not missing.is_empty():
		push_warning("Library bones not found: %s" % ", ".join(missing))
	return map


## Writes retarget settings into `<library>.import`.
static func configure(path: String) -> bool:
	var scene := load(path) as PackedScene
	var root := scene.instantiate()
	var skel_path := String(root.get_path_to(root.find_children("*", "Skeleton3D", true, false)[0]))
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
		# 1 = "Overwrite Axis", matching godot-vrm's skeleton normalisation.
		"retarget/rest_fixer/retarget_method": 1,
		"retarget/rest_fixer/fix_silhouette/enable": true,
		"retarget/remove_tracks/unmapped_bones": true,
	}
	subresources["nodes"] = nodes
	cfg.set_value("params", "_subresources", subresources)
	return cfg.save(path + ".import") == OK
