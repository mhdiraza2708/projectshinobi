class_name CharacterAnimator
extends Node
## Drives a humanoid character from gameplay state with motion-captured clips
## where they exist and procedural IK (HumanoidPoser) for everything else.
##
## Clips come from two places, retargeted to Godot's humanoid skeleton so they
## play on every character rig:
## - The Universal Animation Library (Quaternius, CC0) in UAL_DIR: idle, walk,
##   jog, sprint, jumps, punches, a spell cast, hit reactions, a death and a
##   talking idle. CLIP_SOURCES maps the game's clip names to its animations.
## - Your own Mixamo downloads in CLIP_DIR, one clip per file named after the
##   clip ("run.fbx"); they replace the library's clip of the same name.
##
## The procedural layer stays on top: hand seals, guard, charge, the dash
## lean, the kunai throw, the sprinting arms swept back, and a strike or cast
## made on the move (a full-body punch clip would freeze the running legs).

const CLIP_DIR := "res://assets/animations/mixamo"
const UAL_DIR := "res://assets/animations/ual"
## Game clip -> library animation (Godot drops the "_Loop" suffixes on import).
const CLIP_SOURCES := {
	&"idle": "Idle", &"walk": "Walk", &"run": "Jog_Fwd", &"sprint": "Sprint",
	&"jump": "Jump", &"land": "Jump_Land", &"strike_1": "Punch_Jab", &"strike_2": "Punch_Cross",
	&"cast": "Spell_Simple_Shoot", &"hit": "Hit_Chest", &"hit_head": "Hit_Head", &"death": "Death01",
	&"talk": "Idle_Talking",
}
const LOOPING: PackedStringArray = ["idle", "walk", "run", "sprint", "jump", "talk", "guard", "charge", "fall"]
const BLEND_TIME := 0.18
## How fast each locomotion clip carries a character on its feet, in leg
## lengths per second at speed 1, measured on all nine roster rigs with
## tools/measure_strides.gd (the speed a planted foot slides back; the jog's
## reading is pulled down by its stride length against the sprint's).
## Playback speed follows the real speed so feet don't skate.
const STRIDE := {&"walk": 1.28, &"run": 5.5, &"sprint": 7.0}
## Above these ground speeds (leg lengths per second) the next gait takes over.
# A brisk walk (a cutscene's 1.8 m/s) still walks.
const GAIT_WALK_MAX := 2.9
const GAIT_RUN_MAX := 6.2
const GAIT_SPEED_RANGE := Vector2(0.6, 2.0)
## One-shot playback speeds: game strikes come every 0.28 s, much faster
## than a boxer's jab.
const STRIKE_SPEED := 1.9
const CAST_SPEED := 1.3
const HIT_SPEED := 1.2
## Above this speed ratio a strike or cast is done by the arms alone.
const MOVING := 0.25

## Same API the player controller used with the poser directly.
var pose := HumanoidPoser.Pose.LOCOMOTION:
	set(v):
		if v != pose and v != HumanoidPoser.Pose.LOCOMOTION and _action != &"" and _action != &"death":
			# Weaving, guarding, dashing... cut an action short.
			_action = &""
		pose = v
		if poser:
			poser.pose = v
## Ground speed over run speed: 0 = still, 1 = running, above 1 = sprinting.
var speed_ratio := 0.0:
	set(v):
		speed_ratio = v
		if poser:
			poser.speed_ratio = v
var airborne := false:
	set(v):
		if airborne and not v:
			_landed()
		airborne = v
		if poser:
			poser.airborne = v
## The run speed `speed_ratio` is measured against, in m/s.
var run_speed := 7.0
## Plays the talking idle while standing (story characters speaking).
var talking := false
## The character's gear: with a sword at the hip, strikes draw it and cut,
## and it goes home again after a quiet moment or to weave seals.
var gear: CharacterGear
## Seconds without a cut before the sword is sheathed.
const SHEATHE_AFTER := 4.0

var poser: HumanoidPoser
var clips: AnimationPlayer
var library: AnimationLibrary

var _action := &""
var _action_left := 0.0
var _strike_flip := false
var _since_cut := INF
var _combo := -1
## Seconds until the sword changes hands mid-draw or mid-sheathe (-1: none),
## and which way (true: into the hand).
var _swap_left := -1.0
var _swap_to := false

static var _library_cache: Dictionary = {}


func setup(model_root: Node, humanoid_poser: HumanoidPoser, clip_dir := CLIP_DIR) -> void:
	poser = humanoid_poser
	add_child(Footsteps.new())
	library = load_library(clip_dir)
	# Clips need the humanoid skeleton the retargeting targets.
	if library.get_animation_list().is_empty() or not poser.active \
			or model_root.get_node_or_null(^"%GeneralSkeleton") == null:
		library = AnimationLibrary.new()
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


## The clip playing right now (&"" without clips).
func current_clip() -> StringName:
	return StringName(clips.current_animation) if clips else &""


func has_sword() -> bool:
	return gear != null and gear.has_sword() and poser != null and poser.active


## The sword is in the hand (or on its way there).
func sword_drawn() -> bool:
	return has_sword() and (gear.is_drawn() or (_swap_left >= 0.0 and _swap_to))


## A blow: with a sword, the first draws it from the hip in a cut and the
## next are cuts (`cut`: which of the combo, or the next one); without, a
## jab or cross.
func strike(cut := -1) -> void:
	if has_sword():
		_since_cut = 0.0
		if not sword_drawn():
			_combo = -1
			poser.hilt = gear.hilt_grip
			poser.draw()
			_swap_left = HumanoidPoser.DRAW_TIME * HumanoidPoser.DRAW_REACH
			_swap_to = true
			return
		if poser.is_drawing():
			# The draw is this cut.
			return
		# Struck again while putting it away: it stays out.
		_swap_left = -1.0
		_combo = cut if cut >= 0 else (_combo + 1) % 3
		poser.cut(_combo)
		return
	if _can_act(&"strike_1"):
		_strike_flip = not _strike_flip
		_play_action(&"strike_2" if _strike_flip else &"strike_1", STRIKE_SPEED, 0.06)
	elif poser:
		poser.strike()


func throw() -> void:
	if poser:
		poser.throw()


## A jutsu leaves the hands.
func cast() -> void:
	# A jutsu is released straight out of the weave, before the pose changes.
	if _can_act(&"cast", [HumanoidPoser.Pose.LOCOMOTION, HumanoidPoser.Pose.WEAVE]):
		_play_action(&"cast", CAST_SPEED, 0.08)
	elif poser:
		poser.cast_push()


## Flinch from a blow (`heavy`: snapped back by the head).
func hit(heavy := false) -> void:
	var clip := &"hit_head" if heavy and has_clip(&"hit_head") else &"hit"
	if clips and has_clip(clip) and _action != &"death":
		_play_action(clip, HIT_SPEED, 0.05)
	elif poser:
		poser.flinch()


## Falls and stays down. Returns false when there is no clip for it (the
## caller topples the body instead).
func die() -> bool:
	if not (clips and has_clip(&"death")):
		return false
	_play_action(&"death", 1.0, 0.1)
	_action_left = INF
	return true


## Back up after die().
func revive() -> void:
	_action = &""


func seal_flick() -> void:
	if poser:
		poser.seal_flick()


func _can_act(clip: StringName, poses: Array = [HumanoidPoser.Pose.LOCOMOTION]) -> bool:
	return clips != null and has_clip(clip) and speed_ratio < MOVING and not airborne \
		and pose in poses and _action != &"death"


func _play_action(clip: StringName, speed: float, blend: float) -> void:
	_action = clip
	_action_left = library.get_animation(clip).length / speed
	clips.speed_scale = speed
	# Restart even if this clip is already playing (a combo of jabs).
	clips.play(clip, blend)
	clips.seek(0.0, true)


func _landed() -> void:
	if clips and has_clip(&"land") and speed_ratio < MOVING and _action == &"" \
			and pose == HumanoidPoser.Pose.LOCOMOTION:
		# Only the crouch into the landing; standing up again is the idle's job.
		_play_action(&"land", 1.6, 0.06)
		_action_left = 0.35


func _process(delta: float) -> void:
	if has_sword():
		_update_sword(delta)
	if clips == null:
		return
	if _action != &"":
		_action_left -= delta
		if _action_left > 0.0:
			return
		_action = &""
	var want := _clip_for_state()
	if want == &"":
		return
	clips.speed_scale = _speed_for(want)
	if clips.current_animation != want:
		clips.play(want, BLEND_TIME)


func _update_sword(delta: float) -> void:
	_since_cut += delta
	poser.hilt = gear.hilt_grip
	if _swap_left >= 0.0:
		_swap_left -= delta
		if _swap_left < 0.0:
			gear.set_drawn(_swap_to)
			if _swap_to:
				_glint()
			else:
				_sword_sound(&"sword_snap", gear.scabbard)
	elif gear.is_drawn():
		if pose == HumanoidPoser.Pose.WEAVE or pose == HumanoidPoser.Pose.CHARGE:
			# Seals and charging need both hands: home at once.
			gear.set_drawn(false)
			_sword_sound(&"sword_snap", gear.scabbard)
		elif _since_cut > SHEATHE_AFTER and pose == HumanoidPoser.Pose.LOCOMOTION and not airborne \
				and _action != &"death":
			poser.sheathe()
			_swap_left = HumanoidPoser.SHEATHE_TIME * HumanoidPoser.SHEATHE_HOME
			_swap_to = false
			_sword_sound(&"sword_sheathe", gear.scabbard)
	poser.sword_drawn = gear.is_drawn()
	if is_instance_valid(gear.blade_trail):
		gear.blade_trail.emitting = gear.is_drawn() and (poser.is_cutting() or poser.is_drawing())


## The blade is out: a glint runs up it, and it sings.
func _glint() -> void:
	if is_instance_valid(gear.blade_trail):
		gear.blade_trail.glint()
	_sword_sound(&"sword_draw", gear.sword)


## A sound from the sword (or its scabbard), where it is in the world.
func _sword_sound(sound: StringName, from: Node3D) -> void:
	if is_instance_valid(from) and from.is_inside_tree():
		Sfx.play_at(sound, from.global_position, 0.0, 0.04)


## Leg lengths per second the character is covering.
func _ground_speed() -> float:
	var leg := poser.leg_length() if poser else 0.8
	return speed_ratio * run_speed / maxf(leg, 0.1)


func _speed_for(clip: StringName) -> float:
	if STRIDE.has(clip):
		return clampf(_ground_speed() / STRIDE[clip], GAIT_SPEED_RANGE.x, GAIT_SPEED_RANGE.y)
	return 1.0


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
	var ground := _ground_speed()
	if speed_ratio > 0.05:
		if ground > GAIT_RUN_MAX and has_clip(&"sprint"):
			return &"sprint"
		if ground > GAIT_WALK_MAX or not has_clip(&"walk"):
			if has_clip(&"run"):
				return &"run"
		return &"walk"
	if talking and has_clip(&"talk") and pose == HumanoidPoser.Pose.LOCOMOTION:
		return &"talk"
	return &"idle" if has_clip(&"idle") else &""


## Builds (and caches) the clip library: the animation library in UAL_DIR,
## then any per-file clips in `dir` (Mixamo downloads) on top.
static func load_library(dir: String) -> AnimationLibrary:
	if _library_cache.has(dir):
		return _library_cache[dir]
	var lib := AnimationLibrary.new()
	_add_ual(lib)
	if DirAccess.dir_exists_absolute(dir):
		for file in ResourceLoader.list_directory(dir):
			if file.get_extension().to_lower() != "fbx" and file.get_extension().to_lower() != "glb":
				continue
			var anim := _first_animation(dir.path_join(file))
			if anim == null:
				continue
			var clip := StringName(file.get_basename().to_lower())
			anim = anim.duplicate()
			anim.loop_mode = Animation.LOOP_LINEAR if LOOPING.has(clip) else Animation.LOOP_NONE
			if lib.has_animation(clip):
				lib.remove_animation(clip)
			lib.add_animation(clip, anim)
	_library_cache[dir] = lib
	return lib


static func _add_ual(lib: AnimationLibrary) -> void:
	if not DirAccess.dir_exists_absolute(UAL_DIR):
		return
	for file in ResourceLoader.list_directory(UAL_DIR):
		if not file.get_extension().to_lower() in ["gltf", "glb"]:
			continue
		var scene := load(UAL_DIR.path_join(file)) as PackedScene
		if scene == null:
			continue
		var root := scene.instantiate()
		var players := root.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			var player := players[0] as AnimationPlayer
			for clip: StringName in CLIP_SOURCES:
				var source := StringName(CLIP_SOURCES[clip])
				if not player.has_animation(source):
					continue
				var anim := player.get_animation(source)
				if anim.get_track_count() == 0 or not String(anim.track_get_path(0)).begins_with("%GeneralSkeleton"):
					push_warning("%s is not retargeted; run `make animations`" % UAL_DIR)
					break
				anim = anim.duplicate()
				anim.loop_mode = Animation.LOOP_LINEAR if LOOPING.has(clip) else Animation.LOOP_NONE
				lib.add_animation(clip, anim)
		root.free()


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
