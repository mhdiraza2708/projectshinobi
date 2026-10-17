class_name JumpClip
extends RefCounted
## Splits one Mixamo jump, a standing leap in a single clip, into the phases
## the game plays from the character's state: the push-off as a jump leaves the
## ground (jump_takeoff), the air (jump) and the crouch on landing (land).
##
## The phases are found in the clip itself, not from frame numbers, so any
## similar jump works. Forward kinematics over the legs gives the height of the
## ankles and toes on every frame; each stays "on the ground" at the lowest it
## ever gets, and the clip is in the air while both feet are above that.
## - The push-off runs from partway up out of the crouch to just after the
##   toes leave the ground.
## - The air runs from there to the toes coming back down. Its tuck is
##   greatest at the feet's highest, which is what the game poses at the top of
##   a jump (air_time).
## - The landing runs from touchdown through the deepest crouch, until the hips
##   have come back up part of the way.
##
## The clip's hips carry the whole jump's height. In the air and in the
## push-off (which only runs as the body is already leaving the ground) the hips
## are held still instead, at the height they have as the feet touch down, so the
## body's own movement is the only rise and the feet meet the ground where the
## legs reach it. Their rotation is kept. The landing crouch keeps its hips: it
## happens on the ground, and nothing else lowers the body.

## Meta on each clip made here: which phase it is (&"takeoff", &"air" or
## &"land"). The air clip also marks the pose at the top of the jump and at
## touchdown, in seconds into it.
const PHASE := &"jump_phase"
const PEAK := &"jump_peak"
const TOUCHDOWN := &"jump_touchdown"

const HIPS := &"Hips"
const LEG_BONES: Array[StringName] = [&"UpperLeg", &"LowerLeg", &"Foot", &"Toes"]
const TRACK_PREFIX := "%GeneralSkeleton:"

## Seconds between samples of a clip without a key on every frame (and how
## many keys the hips need to be sampled by them).
const STEP := 1.0 / 30.0
const MIN_KEYS := 12
## A foot's ground is this share of the way up its heights, lowest first.
const GROUND_SHARE := 0.05
## A foot is off the ground above this height, in leg lengths.
const CLEARANCE := 0.03
## The shortest time in the air that counts as a jump, in seconds, and the
## least the feet must rise in it, in leg lengths (a run's flight is neither).
const MIN_AIR := 0.12
const MIN_RISE := 0.25
## The push-off starts this share of the way back from the toes leaving the
## ground to the deepest part of the crouch, but no earlier than MAX_PUSH
## seconds before and no later than MIN_PUSH.
const PUSH_SHARE := 0.5
const MIN_PUSH := 0.1
const MAX_PUSH := 0.3
## Seconds the push-off runs on past the toes leaving the ground.
const PUSH_TAIL := 0.07
## The landing runs on until the hips have risen this share of the way back
## from the deepest crouch to standing.
const LAND_RISE := 0.3
## The shallowest crouch that makes a landing, in leg lengths.
const MIN_CROUCH := 0.1
## Seconds the air clip holds its last pose past the touchdown, so it can
## never run off its end (and loop) while it fades out.
const HOLD := 0.4
## The air pose at the top of the jump is the clip's peak. Rising at this
## speed (m/s) it is the pose at the toes leaving the ground; falling at this
## speed, the one at touchdown.
const RISE_SPEED := 8.0
const FALL_SPEED := 6.0


## Splits the "jump" in `lib` (a whole jump, loaded from `dir`) into the clips
## "jump_takeoff", "jump" (its air phase) and "land". A clip of those names
## that has a file of its own in `dir` wins, and a jump where no phases can be
## found is left as it is.
static func split_library(lib: AnimationLibrary, dir: String) -> void:
	var file := _file_of(dir, &"jump")
	if file == "" or not lib.has_animation(&"jump"):
		return
	var found := phases_of(file)
	if found.is_empty():
		push_warning("%s has no jump in it that the game can split into phases" % file)
		return
	var clips := build(found)
	for clip: StringName in clips:
		if clip == &"jump" or _file_of(dir, clip) == "":
			if lib.has_animation(clip):
				lib.remove_animation(clip)
			lib.add_animation(clip, clips[clip])


## The phases found in the jump in the file at `path`: see find_phases, plus
## the clip itself (as "anim") and the hips' rest height ("rig").
static func phases_of(path: String) -> Dictionary:
	var scene := load(path) as PackedScene
	if scene == null:
		return {}
	var root := scene.instantiate()
	var rig := _rig_of(root)
	var anim: Animation = null
	for node in root.find_children("*", "AnimationPlayer", true, false):
		for anim_name in (node as AnimationPlayer).get_animation_list():
			if anim_name != &"RESET" and anim == null:
				anim = (node as AnimationPlayer).get_animation(anim_name)
	var found := {}
	if anim != null and not rig.is_empty():
		found = find_phases(anim, rig)
		if not found.is_empty():
			found["anim"] = anim
			found["rig"] = rig
	root.free()
	return found


## When each phase of the jump `anim` happens, in seconds into it, or an empty
## dictionary without a jump in it: "toes_off" and "touchdown" (the feet
## leaving and meeting the ground), "peak" (the feet's highest), "crouch" and
## "bottom" (the deepest part of the crouch before and after the air) and the
## windows "takeoff", "air" and "land" as Vector2(start, end), the push-off and
## the landing empty when the clip has none. `rig` is the legs' rest pose (_rig_of).
static func find_phases(anim: Animation, rig: Dictionary) -> Dictionary:
	var tracks := _tracks_of(anim)
	if tracks[HIPS]["pos"] < 0:
		return {}
	var times := _sample_times(anim, tracks)
	var n := times.size()
	if n < 8:
		return {}
	var up: Vector3 = rig["up"]
	var hips := PackedFloat32Array()
	var feet: Array[PackedFloat32Array] = []
	for i in 4:
		feet.append(PackedFloat32Array())
	for k in n:
		var at := _hips_at(anim, tracks, rig, times[k])
		hips.append(at.origin.dot(up))
		var points := _feet_at(anim, tracks, rig, at, times[k])
		for i in 4:
			feet[i].append(points[i].dot(up))
	# Each foot is on the ground at (nearly) the lowest it ever gets.
	var clear := PackedFloat32Array()
	clear.resize(n)
	for k in n:
		clear[k] = INF
	for i in 4:
		var ground := _ground(feet[i])
		for k in n:
			clear[k] = minf(clear[k], feet[i][k] - ground)
	var limit: float = CLEARANCE * float(rig["leg"])
	# The longest time in the air, as samples from..to-1.
	var best := Vector2i(-1, -1)
	var k := 0
	while k < n:
		if clear[k] > limit:
			var from := k
			while k < n and clear[k] > limit:
				k += 1
			if best.x < 0 or times[k - 1] - times[from] > times[best.y - 1] - times[best.x]:
				best = Vector2i(from, k)
		else:
			k += 1
	if best.x < 0 or times[best.y - 1] - times[best.x] < MIN_AIR:
		return {}
	var rise := 0.0
	for j in range(best.x, best.y):
		rise = maxf(rise, clear[j])
	if rise < MIN_RISE * float(rig["leg"]):
		return {}
	var first_time := times[0]
	var last_time := times[n - 1]
	var spacing := (last_time - first_time) / (n - 1)
	var toes_off := first_time if best.x == 0 else _cross(times, clear, best.x - 1, best.x, limit)
	var touchdown := last_time if best.y >= n else _cross(times, clear, best.y - 1, best.y, limit)
	# The peak is the middle of the feet's highest stretch, smoothed over a
	# few samples.
	var peak_k := best.x
	var peak_height := -INF
	for j in range(best.x, best.y):
		var sum := 0.0
		var count := 0
		for d in range(-2, 3):
			if j + d >= best.x and j + d < best.y:
				sum += clear[j + d]
				count += 1
		if sum / count > peak_height:
			peak_height = sum / count
			peak_k = j
	var peak := times[peak_k]
	var found := {
		"toes_off": toes_off, "touchdown": touchdown, "peak": peak,
		"crouch": -1.0, "bottom": -1.0,
		"takeoff": Vector2.ZERO, "air": Vector2(toes_off, touchdown), "land": Vector2.ZERO,
	}
	if toes_off > first_time + spacing * 2.0:
		# The crouch before: its deepest point sets how long the push-off is.
		var crouch_k := 0
		for j in best.x:
			if hips[j] < hips[crouch_k]:
				crouch_k = j
		var crouch := times[crouch_k]
		found["crouch"] = crouch
		var lead := clampf((toes_off - crouch) * PUSH_SHARE, MIN_PUSH, MAX_PUSH)
		var air_from := minf(toes_off + PUSH_TAIL, toes_off + (peak - toes_off) * 0.5)
		found["takeoff"] = Vector2(maxf(first_time, toes_off - lead), air_from)
		found["air"] = Vector2(air_from, touchdown)
	if touchdown < last_time - spacing * 2.0:
		# The crouch after: down to its deepest, and some of the way back up.
		var after := best.y
		var bottom_k := after
		for j in range(after, n):
			if hips[j] < hips[bottom_k]:
				bottom_k = j
		var standing := 0.0
		var tail := 0
		for j in range(maxi(after, n - 6), n):
			standing += hips[j]
			tail += 1
		standing /= maxi(tail, 1)
		if standing - hips[bottom_k] > MIN_CROUCH * float(rig["leg"]):
			var goal: float = hips[bottom_k] + LAND_RISE * (standing - hips[bottom_k])
			var end_k := n - 1
			for j in range(bottom_k, n):
				if hips[j] >= goal:
					end_k = j
					break
			found["bottom"] = times[bottom_k]
			found["land"] = Vector2(touchdown, times[end_k])
	return found


## The clips for the phases `found` (phases_of) holds: "jump_takeoff", "jump"
## and "land", the first and last only when the clip has them.
static func build(found: Dictionary) -> Dictionary:
	var anim: Animation = found["anim"]
	var rig: Dictionary = found["rig"]
	var up: Vector3 = rig["up"]
	var tracks := _tracks_of(anim)
	var hips_track: int = tracks[HIPS]["pos"]
	# Held still: where the hips start (level with the feet's ground) and as
	# high as they are when the feet touch down.
	var start := anim.position_track_interpolate(hips_track, 0.0)
	var down := anim.position_track_interpolate(hips_track, found["touchdown"])
	var held := _flat(start, up) + up * down.dot(up)
	var keep_still := func(_pos: Vector3, _time: float) -> Vector3: return held
	var clips := {}
	var air: Vector2 = found["air"]
	var out := _slice(anim, air, keep_still, true, HOLD)
	out.loop_mode = Animation.LOOP_LINEAR
	out.set_meta(PHASE, &"air")
	out.set_meta(PEAK, float(found["peak"]) - air.x)
	out.set_meta(TOUCHDOWN, float(found["touchdown"]) - air.x)
	clips[&"jump"] = out
	if (found["takeoff"] as Vector2) != Vector2.ZERO:
		out = _slice(anim, found["takeoff"], keep_still, true)
		out.loop_mode = Animation.LOOP_NONE
		out.set_meta(PHASE, &"takeoff")
		clips[&"jump_takeoff"] = out
	if (found["land"] as Vector2) != Vector2.ZERO:
		# The crouch keeps the hips' height; they meet the held ones where the feet land.
		var flat_down := _flat(down, up)
		var crouch := func(pos: Vector3, _time: float) -> Vector3:
			return _flat(held, up) + _flat(pos, up) - flat_down + up * pos.dot(up)
		out = _slice(anim, found["land"], crouch)
		out.loop_mode = Animation.LOOP_NONE
		out.set_meta(PHASE, &"land")
		clips[&"land"] = out
	return clips


## How far into the air clip `air` the pose is, at a vertical speed in m/s (up
## is positive): the clip's start rising at RISE_SPEED, the peak at rest,
## touchdown falling at FALL_SPEED or faster.
static func air_time(air: Animation, vertical_speed: float) -> float:
	var peak: float = air.get_meta(PEAK, 0.0)
	if vertical_speed >= 0.0:
		return lerpf(peak, 0.0, clampf(vertical_speed / RISE_SPEED, 0.0, 1.0))
	var down: float = air.get_meta(TOUCHDOWN, peak)
	return lerpf(peak, down, clampf(-vertical_speed / FALL_SPEED, 0.0, 1.0))


## Whether `anim` is an air clip made by build().
static func is_air(anim: Animation) -> bool:
	return anim != null and anim.has_meta(PEAK)


# --- Reading the clip ----------------------------------------------------------

## The file for the clip `clip` in `dir` ("" without one), by name like the
## clip library's own loading does.
static func _file_of(dir: String, clip: StringName) -> String:
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	for file in ResourceLoader.list_directory(dir):
		if file.get_extension().to_lower() in ["fbx", "glb"] and file.get_basename().to_lower() == String(clip):
			return dir.path_join(file)
	return ""


## The rest pose of the hips and legs in the model `root`, in metres: each
## bone's rest transform, which way is up, the leg's length and the scale the
## hips' track is stored in. Empty without the bones.
static func _rig_of(root: Node) -> Dictionary:
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return {}
	var skel := skeletons[0] as Skeleton3D
	var rig := {"scale": skel.motion_scale, "bones": {}, "up": Vector3.UP, "leg": 0.0}
	var bones: Dictionary = rig["bones"]
	for bone in _bones():
		var i := skel.find_bone(bone)
		if i < 0:
			return {}
		bones[bone] = skel.get_bone_rest(i)
	var head := skel.find_bone(&"Head")
	if head >= 0:
		var up := skel.get_bone_global_rest(head).origin - skel.get_bone_global_rest(skel.find_bone(HIPS)).origin
		if up.length_squared() > 1e-6:
			rig["up"] = up.normalized()
	rig["leg"] = (bones[&"LeftLowerLeg"] as Transform3D).origin.length() \
		+ (bones[&"LeftFoot"] as Transform3D).origin.length()
	return rig


## The hips and every leg bone.
static func _bones() -> Array[StringName]:
	var names: Array[StringName] = [HIPS]
	for side in ["Left", "Right"]:
		for part in LEG_BONES:
			names.append(StringName(side + String(part)))
	return names


static func _tracks_of(anim: Animation) -> Dictionary:
	var tracks := {}
	for bone in _bones():
		var path := NodePath(TRACK_PREFIX + bone)
		tracks[bone] = {
			"pos": anim.find_track(path, Animation.TYPE_POSITION_3D),
			"rot": anim.find_track(path, Animation.TYPE_ROTATION_3D),
		}
	return tracks


## A bone's pose at time `t` relative to its parent: the clip's rotation (the
## rest pose's without a track), and for the hips their position, in metres.
static func _local(anim: Animation, tracks: Dictionary, rig: Dictionary, bone: StringName, t: float) -> Transform3D:
	var rest: Transform3D = rig["bones"][bone]
	var rot := rest.basis.get_rotation_quaternion()
	var pos := rest.origin
	var track: Dictionary = tracks[bone]
	if track["rot"] >= 0:
		rot = anim.rotation_track_interpolate(track["rot"], t)
	if bone == HIPS and track["pos"] >= 0:
		pos = anim.position_track_interpolate(track["pos"], t) * float(rig["scale"])
	return Transform3D(Basis(rot), pos)


static func _hips_at(anim: Animation, tracks: Dictionary, rig: Dictionary, t: float) -> Transform3D:
	return _local(anim, tracks, rig, HIPS, t)


## Where the ankles and toes are (left foot, left toes, right foot, right toes)
## with the hips at `hips`.
static func _feet_at(anim: Animation, tracks: Dictionary, rig: Dictionary, hips: Transform3D, t: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for side in ["Left", "Right"]:
		var at := hips
		for part in LEG_BONES:
			at = at * _local(anim, tracks, rig, StringName(side + String(part)), t)
			if part == &"Foot" or part == &"Toes":
				points.append(at.origin)
	return points


## When, between samples `a` and `b`, `values` crosses `limit`.
static func _cross(times: PackedFloat32Array, values: PackedFloat32Array, a: int, b: int, limit: float) -> float:
	var span := values[b] - values[a]
	return lerpf(times[a], times[b], clampf((limit - values[a]) / span, 0.0, 1.0) if absf(span) > 1e-6 else 0.5)


## When the clip is sampled: at the hips' own keys, where the pose is exactly
## as it was captured (a Mixamo clip has a key on every frame), else every STEP.
static func _sample_times(anim: Animation, tracks: Dictionary) -> PackedFloat32Array:
	var times := PackedFloat32Array()
	var track: int = tracks[HIPS]["pos"]
	var keys := anim.track_get_key_count(track)
	if keys >= MIN_KEYS:
		for k in keys:
			times.append(anim.track_get_key_time(track, k))
		return times
	var t := 0.0
	while t < anim.length:
		times.append(t)
		t += STEP
	times.append(anim.length)
	return times


## Where the ground is for a foot: a low share of its heights, so one frame of
## a foot through the floor doesn't lower it.
static func _ground(heights: PackedFloat32Array) -> float:
	var sorted := heights.duplicate()
	sorted.sort()
	return sorted[int(sorted.size() * GROUND_SHARE)]


static func _flat(v: Vector3, up: Vector3) -> Vector3:
	return v - up * v.dot(up)


# --- Cutting the clip ----------------------------------------------------------

## The part of `anim` from window.x to window.y seconds as a clip of its own
## (`hold` seconds longer, holding its last pose). `hips` moves the hips'
## position (given it and the time into the clip) and `still` says it is the
## same all through, so only the ends are keyed.
static func _slice(anim: Animation, window: Vector2, hips: Callable, still := false, hold := 0.0) -> Animation:
	var out := Animation.new()
	var span := window.y - window.x
	out.length = span + hold
	out.step = anim.step
	for i in anim.get_track_count():
		var type := anim.track_get_type(i)
		if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_SCALE_3D:
			continue
		var is_hips := type == Animation.TYPE_POSITION_3D and anim.track_get_path(i) == NodePath(TRACK_PREFIX + HIPS)
		var track := out.add_track(type)
		out.track_set_path(track, anim.track_get_path(i))
		out.track_set_interpolation_type(track, anim.track_get_interpolation_type(i))
		var times := PackedFloat32Array([window.x])
		if not (is_hips and still):
			for k in anim.track_get_key_count(i):
				var at := anim.track_get_key_time(i, k)
				if at > window.x + 0.0001 and at < window.y - 0.0001:
					times.append(at)
		times.append(window.y)
		var last: Variant = null
		for at in times:
			last = _value(anim, i, type, at)
			if is_hips:
				last = hips.call(last, at - window.x)
			_key(out, track, type, at - window.x, last)
		if hold > 0.0:
			_key(out, track, type, span + hold, last)
	return out


static func _value(anim: Animation, track: int, type: int, at: float) -> Variant:
	match type:
		Animation.TYPE_POSITION_3D: return anim.position_track_interpolate(track, at)
		Animation.TYPE_ROTATION_3D: return anim.rotation_track_interpolate(track, at)
	return anim.scale_track_interpolate(track, at)


static func _key(anim: Animation, track: int, type: int, at: float, value: Variant) -> void:
	match type:
		Animation.TYPE_POSITION_3D: anim.position_track_insert_key(track, at, value)
		Animation.TYPE_ROTATION_3D: anim.rotation_track_insert_key(track, at, value)
		_: anim.scale_track_insert_key(track, at, value)
