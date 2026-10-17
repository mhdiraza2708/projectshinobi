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
##   clip ("run.fbx"); they replace the library's clip of the same name. A
##   Mixamo jump is split into a push-off, the air and a landing (JumpClip).
##
## The procedural layer stays on top: hand seals, guard, charge, the dash
## lean, the kunai throw, the sprinting arms swept back, and a strike or cast
## made on the move (a full-body punch clip would freeze the running legs).
##
## The katana's cuts are procedural too, unless you add a clip for one: a
## Mixamo sword clip named cut_1 ... cut_4 (the combo's four cuts) replaces
## that cut when the character stands (the same conditions as any one-shot).
## The clip is trimmed to its swing on load (SwingClip), because Mixamo sword
## clips carry seconds of wind-up and recovery around a half-second cut.

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
## A Mixamo jump's push-off (JumpClip) plays this much faster than it was
## captured: it only covers the last of the crouch, as the body already leaves
## the ground.
const TAKEOFF_SPEED := 1.8
## Rising faster than this (m/s) as the feet leave the ground, or after a fall
## or the top of a jump, is a jump.
const LAUNCH_RISE := 4.0
## A height change bigger than this in one update (m) is the body being put
## somewhere, not moving.
const TELEPORT_RISE := 2.0
## Seconds a cut clip blends in over (a cut is quick, and so is the lean
## into it).
const CUT_BLEND := 0.08

## Same API the player controller used with the poser directly.
var pose := HumanoidPoser.Pose.LOCOMOTION:
	set(v):
		if v != pose and v != HumanoidPoser.Pose.LOCOMOTION and _action != &"" and _action != &"death":
			# Weaving, guarding, dashing... cut an action short.
			_action = &""
			if poser:
				poser.release_clip_cut()
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
## How fast the body is rising (m/s), worked out from how far it moves. The
## pose in the air follows it (JumpClip.air_time).
var vertical_speed := 0.0
## Whether vertical_speed is worked out from the body's movement (turn it off
## to set it by hand).
var follows_body := true
var _skeleton: Skeleton3D

var _action := &""
var _action_left := 0.0
var _strike_flip := false
var _since_cut := INF
var _combo := -1
## Seconds until the sword changes hands mid-draw or mid-sheathe (-1: none),
## and which way (true: into the hand).
var _swap_left := -1.0
var _swap_to := false
## The air phase of a Mixamo jump (null without one).
var _air_clip: Animation
var _last_height := 0.0
var _height_known := false

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
	_skeleton = model_root.get_node_or_null(^"%GeneralSkeleton") as Skeleton3D
	clips = AnimationPlayer.new()
	clips.name = "ClipPlayer"
	model_root.add_child(clips)
	# Tracks target %GeneralSkeleton, which is unique within the model root.
	clips.root_node = clips.get_path_to(model_root)
	clips.add_animation_library(&"", library)
	poser.clip_states = covered_states()
	_air_clip = library.get_animation(&"jump") if has_clip(&"jump") else null
	poser.clip_air = JumpClip.is_air(_air_clip)


func has_clip(clip: StringName) -> bool:
	return library != null and library.has_animation(clip)


## A Mixamo jump was split into phases (JumpClip), and flies the body in the
## air in place of the poser.
func has_jump_phases() -> bool:
	return JumpClip.is_air(_air_clip)


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
		_combo = cut if cut >= 0 else (_combo + 1) % HumanoidPoser.CUTS.size()
		var clip := cut_clip(_combo)
		if clip == &"":
			poser.cut(_combo)
			return
		# A Mixamo clip makes this cut: it plays on the whole body, and the
		# poser leaves the sword arm and the spine to it.
		_play_action(clip, 1.0, CUT_BLEND)
		var anim := library.get_animation(clip)
		var swing: Vector2 = anim.get_meta(SwingClip.META_SWING, Vector2(0.0, anim.length))
		poser.clip_cut(_combo, anim.length, swing.y)
		return
	if _can_act(&"strike_1"):
		_strike_flip = not _strike_flip
		_play_action(&"strike_2" if _strike_flip else &"strike_1", STRIKE_SPEED, 0.06)
	elif poser:
		poser.strike()


## The Mixamo clip that makes cut `index` of the combo (cut_1 ... cut_4), or
## &"" when the cut stays procedural: there is no clip for it, or the body
## isn't free for one (moving, in the air, in another pose).
func cut_clip(index: int) -> StringName:
	var clip := cut_clip_name(index)
	return clip if _can_act(clip) else &""


## The slot of cut `index`: cut_1 for the first cut of the combo.
static func cut_clip_name(index: int) -> StringName:
	return StringName("cut_%d" % (posmod(index, HumanoidPoser.CUTS.size()) + 1))


## The way the blade travels across the front in cut `index` (`first`: its
## first stroke; the X is two): a unit vector in the canonical frame, for
## sparks to fly along. A clip's cut is read from the clip (where the hand
## goes at the swing's peak), a procedural one from its keys.
func cut_direction(index: int, first := true) -> Vector3:
	var clip := cut_clip_name(index)
	if _action == clip and has_clip(clip) and _skeleton != null and poser != null:
		var travel := poser.canonical_frame().inverse() * SwingClip.travel(library.get_animation(clip), _skeleton)
		var line := Vector3(travel.x, travel.y, 0.0)
		if line.length() > 0.02:
			return line.normalized()
	var keyed := HumanoidPoser.cut_direction(index)
	# The X's first stroke is its last, mirrored.
	if first and posmod(index, HumanoidPoser.CUTS.size()) == HumanoidPoser.CUTS.size() - 1:
		keyed.x = -keyed.x
	return keyed


## Screenshots: cut `index` made by its clip, frozen `t` (0-1) of the way
## through (called every frame, with the poser's timers held). False when the
## cut has no clip to play.
func hold_clip_cut(index: int, t: float) -> bool:
	var clip := cut_clip(index)
	if clip == &"":
		return false
	var anim := library.get_animation(clip)
	var swing: Vector2 = anim.get_meta(SwingClip.META_SWING, Vector2(0.0, anim.length))
	if clips.current_animation != clip:
		clips.play(clip)
	clips.speed_scale = 0.0
	clips.seek(anim.length * t, true)
	poser.clip_cut(index, anim.length * (1.0 - t), maxf(swing.y - anim.length * t, 0.001))
	return true


func throw() -> void:
	if poser:
		poser.throw()


## A rush jutsu's right arm: 0 free, 1 holding the technique out at the
## side, 2 driving it forward.
func rush_arm(stage: int) -> void:
	if poser:
		poser.rush_arm = stage


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


## The hands form hand seal `seal` (0-11) and hold it until the next one.
func seal(seal_index: int) -> void:
	if poser:
		poser.set_seal(seal_index)


func _can_act(clip: StringName, poses: Array = [HumanoidPoser.Pose.LOCOMOTION]) -> bool:
	return clips != null and has_clip(clip) and speed_ratio < MOVING and not airborne \
		and pose in poses and _action != &"death"


func _play_action(clip: StringName, speed: float, blend: float) -> void:
	if poser and not String(clip).begins_with("cut_"):
		# Any other action takes the body from a cut clip.
		poser.release_clip_cut()
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


## Works out the body's vertical speed from how far it moved, and starts the
## push-off of a Mixamo jump the frame the body leaves the ground (or kicks off
## again in mid-air) rising fast.
func _follow_height(delta: float) -> void:
	var body := get_parent() as Node3D
	if body == null or delta <= 0.0 or not follows_body:
		_height_known = false
		return
	var height := body.global_position.y
	if _height_known and absf(height - _last_height) > TELEPORT_RISE:
		# Placed somewhere new (a spawn, fast travel), not a jump.
		_height_known = false
		vertical_speed = 0.0
	if _height_known:
		var rise := clampf((height - _last_height) / delta, -40.0, 40.0)
		if airborne and rise > LAUNCH_RISE and vertical_speed < 1.0 and (_action == &"" or _action == &"land") \
				and pose == HumanoidPoser.Pose.LOCOMOTION and has_clip(&"jump_takeoff"):
			_play_action(&"jump_takeoff", TAKEOFF_SPEED, 0.05)
		vertical_speed = lerpf(vertical_speed, rise, 1.0 - exp(-delta / 0.05))
	_last_height = height
	_height_known = true


func _process(delta: float) -> void:
	if has_sword():
		_update_sword(delta)
	if clips == null:
		return
	_follow_height(delta)
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
		# The first clip snaps in: blending from no clip is blending out of the
		# rest pose, a T-pose held for a fifth of a second as anyone appears.
		clips.play(want, BLEND_TIME if clips.current_animation != &"" else 0.0)
	if want == &"jump" and poser.clip_air:
		clips.seek(JumpClip.air_time(_air_clip, vertical_speed), true)


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
		JumpClip.split_library(lib, dir)
	# A sword clip is its swing, not the seconds of wind-up around it.
	for i in HumanoidPoser.CUTS.size():
		var slot := cut_clip_name(i)
		if lib.has_animation(slot):
			var trimmed := SwingClip.trim(lib.get_animation(slot), HumanoidPoser.cut_time(i) - SwingClip.LEAD)
			lib.remove_animation(slot)
			lib.add_animation(slot, trimmed)
	_hold_torso_at_rest(lib)
	_library_cache[dir] = lib
	return lib


## Torso and head bones every humanoid rig rests at no rotation (the
## retargeted and VRM-normalised skeletons all do).
const REST_TORSO: Array[StringName] = [&"Hips", &"Spine", &"Chest", &"UpperChest", &"Neck", &"Head"]


## A clip that leaves a torso bone alone would leave it wherever the last clip
## put it: the library's idle has no Spine track, so after a Mixamo jump or
## cut (which bend the Spine) a character stood hunched over for good. Each
## clip without a track for a torso bone another clip moves gets one holding
## it at rest, so the blend back brings it upright.
static func _hold_torso_at_rest(lib: AnimationLibrary) -> void:
	var moved := {}
	for clip in lib.get_animation_list():
		var anim := lib.get_animation(clip)
		for t in anim.get_track_count():
			if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				var bone := StringName(String(anim.track_get_path(t)).trim_prefix("%GeneralSkeleton:"))
				if REST_TORSO.has(bone):
					moved[bone] = true
	for clip in lib.get_animation_list():
		var anim := lib.get_animation(clip)
		for bone: StringName in moved:
			var path := NodePath("%GeneralSkeleton:" + String(bone))
			if anim.find_track(path, Animation.TYPE_ROTATION_3D) >= 0:
				continue
			var t := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(t, path)
			anim.rotation_track_insert_key(t, 0.0, Quaternion.IDENTITY)


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
	_straighten_ual(lib)


## Bones the library's clips come out of the retarget bent forward at rest:
## its rig's upper spine is curved, and that curve arrives as a 35° stoop
## in every clip (the idle stood looking at the ground).
const STOOPED: Array[StringName] = [&"UpperChest"]


## Takes the idle's own bend of each STOOPED bone out of every library clip,
## so the idle stands straight and the walk and run keep only their lean
## relative to it.
static func _straighten_ual(lib: AnimationLibrary) -> void:
	if not lib.has_animation(&"idle"):
		return
	var idle := lib.get_animation(&"idle")
	for bone in STOOPED:
		var path := NodePath("%GeneralSkeleton:" + String(bone))
		var it := idle.find_track(path, Animation.TYPE_ROTATION_3D)
		if it < 0:
			continue
		# The idle's average turn of the bone (it barely moves).
		var sum := Quaternion(0.0, 0.0, 0.0, 0.0)
		for i in 9:
			var q := idle.rotation_track_interpolate(it, idle.length * i / 8.0)
			if sum.dot(q) < 0.0:
				q = -q
			sum = Quaternion(sum.x + q.x, sum.y + q.y, sum.z + q.z, sum.w + q.w)
		var undo := sum.normalized().inverse()
		for clip in lib.get_animation_list():
			_turn_track(lib.get_animation(clip), path, undo)


## Turns every key of a rotation track by `by` (in the parent's frame),
## rebuilding the track from samples when the import compressed it.
static func _turn_track(anim: Animation, path: NodePath, by: Quaternion) -> void:
	var t := anim.find_track(path, Animation.TYPE_ROTATION_3D)
	if t < 0:
		return
	if not anim.track_is_compressed(t):
		for k in anim.track_get_key_count(t):
			anim.track_set_key_value(t, k, by * (anim.track_get_key_value(t, k) as Quaternion))
		return
	var samples := []
	var steps := maxi(ceili(anim.length * 30.0), 1)
	for i in steps + 1:
		var at := minf(i / 30.0, anim.length)
		samples.append([at, by * anim.rotation_track_interpolate(t, at)])
	anim.remove_track(t)
	var n := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(n, path)
	for s: Array in samples:
		anim.rotation_track_insert_key(n, s[0], s[1])


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
