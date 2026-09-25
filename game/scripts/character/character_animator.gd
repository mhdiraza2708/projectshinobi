class_name CharacterAnimator
extends Node
## Drives a humanoid character from gameplay state: Mixamo clips where they
## exist, procedural IK (HumanoidPoser) for everything else. The hand-seal
## pose is always procedural and layers on top of whatever clip is playing.
##
## Clips are looked up by file name in CLIP_DIR (see docs/CHARACTERS.md):
##   idle, run, sprint, jump, dash, guard, charge   (all optional)

const CLIP_DIR := "res://assets/animations/mixamo"
const LOOPING: PackedStringArray = ["idle", "run", "sprint", "walk", "guard", "charge", "jump", "fall"]
const BLEND_TIME := 0.18

## Same API the player controller used with the poser directly.
var pose := HumanoidPoser.Pose.LOCOMOTION:
	set(v):
		pose = v
		if poser:
			poser.pose = v
var speed_ratio := 0.0:
	set(v):
		speed_ratio = v
		if poser:
			poser.speed_ratio = v
var airborne := false:
	set(v):
		airborne = v
		if poser:
			poser.airborne = v

var poser: HumanoidPoser
var clips: AnimationPlayer
var library: AnimationLibrary

static var _library_cache: Dictionary = {}


func setup(model_root: Node, humanoid_poser: HumanoidPoser, clip_dir := CLIP_DIR) -> void:
	poser = humanoid_poser
	library = load_library(clip_dir)
	if library.get_animation_list().is_empty():
		return
	clips = AnimationPlayer.new()
	clips.name = "ClipPlayer"
	model_root.add_child(clips)
	# Tracks target %GeneralSkeleton, which is unique within the model root.
	clips.root_node = clips.get_path_to(model_root)
	clips.add_animation_library(&"", library)
	poser.clip_states = covered_states()


func has_clip(clip: StringName) -> bool:
	return library != null and library.has_animation(clip)


## Which HumanoidPoser states the clips take over.
func covered_states() -> Dictionary:
	var states := {}
	if has_clip(&"idle") and has_clip(&"run"):
		states[HumanoidPoser.Pose.LOCOMOTION] = true
	if has_clip(&"guard"):
		states[HumanoidPoser.Pose.GUARD] = true
	if has_clip(&"charge"):
		states[HumanoidPoser.Pose.CHARGE] = true
	if has_clip(&"dash"):
		states[HumanoidPoser.Pose.DASH] = true
	return states


func strike() -> void:
	if poser:
		poser.strike()


func throw() -> void:
	if poser:
		poser.throw()


func seal_flick() -> void:
	if poser:
		poser.seal_flick()


func _process(_delta: float) -> void:
	if clips == null:
		return
	var want := _clip_for_state()
	if want == &"":
		return
	var speed := 1.0
	if want == &"run" or want == &"sprint":
		speed = clampf(speed_ratio / (1.5 if want == &"sprint" else 1.0), 0.6, 1.4)
	clips.speed_scale = speed
	if clips.current_animation != want:
		clips.play(want, BLEND_TIME)


func _clip_for_state() -> StringName:
	match pose:
		HumanoidPoser.Pose.GUARD:
			if has_clip(&"guard"):
				return &"guard"
		HumanoidPoser.Pose.CHARGE:
			if has_clip(&"charge"):
				return &"charge"
		HumanoidPoser.Pose.DASH:
			if has_clip(&"dash"):
				return &"dash"
	if airborne and has_clip(&"jump"):
		return &"jump"
	if speed_ratio > 1.05 and has_clip(&"sprint"):
		return &"sprint"
	if speed_ratio > 0.05 and has_clip(&"run"):
		return &"run"
	return &"idle" if has_clip(&"idle") else &""


## Builds (and caches) an AnimationLibrary from every retargeted clip in
## `dir`, named after the file ("run.fbx" -> "run").
static func load_library(dir: String) -> AnimationLibrary:
	if _library_cache.has(dir):
		return _library_cache[dir]
	var lib := AnimationLibrary.new()
	if DirAccess.dir_exists_absolute(dir):
		for file in ResourceLoader.list_directory(dir):
			if file.get_extension().to_lower() != "fbx" and file.get_extension().to_lower() != "glb":
				continue
			var anim := _first_animation(dir.path_join(file))
			if anim == null:
				continue
			var clip := file.get_basename().to_lower()
			anim = anim.duplicate()
			anim.loop_mode = Animation.LOOP_LINEAR if LOOPING.has(clip) else Animation.LOOP_NONE
			lib.add_animation(StringName(clip), anim)
	_library_cache[dir] = lib
	return lib


static func _first_animation(path: String) -> Animation:
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var root := scene.instantiate()
	var result: Animation = null
	for node in root.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		for anim_name in player.get_animation_list():
			if anim_name != &"RESET":
				var anim := player.get_animation(anim_name)
				# Only clips retargeted to the humanoid skeleton are usable.
				if anim.get_track_count() > 0 and String(anim.track_get_path(0)).begins_with("%GeneralSkeleton"):
					result = anim
				else:
					push_warning("%s is not retargeted; run `make animations`" % path)
				break
		break
	root.free()
	return result
