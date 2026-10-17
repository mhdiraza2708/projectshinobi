class_name SwingClip
extends RefCounted
## Finds the swing in a Mixamo sword clip and trims the clip to it.
##
## A sword clip is mostly wind-up and recovery: the cut itself is a few frames
## in the middle. The swing is where the sword arm and the spine turn fastest,
## read from the clip's rotation tracks: the window runs from the moment of
## peak speed out to both sides until the speed stays below a fraction of the
## peak. `trim` keeps just that, a short lead-in before it and a settle after
## it, sped up to fit the game's cut timing.
##
## Clips are in humanoid bone names (`%GeneralSkeleton:RightUpperArm`), as
## retargeted at import by tools/setup_mixamo.gd.

## The sword arm, and the spine that twists with it: their summed turning speed
## is the clip's swing.
const BONES: Array[StringName] = [&"RightUpperArm", &"RightLowerArm", &"RightHand", &"Spine", &"Chest", &"UpperChest"]
const SKELETON := "%GeneralSkeleton:"
## Seconds between speed samples.
const STEP := 1.0 / 60.0
## The swing lasts while the speed stays above this share of its peak...
const EDGE := 0.3
## ...and a dip below that, shorter than this (seconds), does not end it.
const DIP := 0.07
## A clip that never turns faster than this (radians a second) has no swing.
const MIN_PEAK := 1.0
## Seconds of the wind-up kept before the swing, and of the recovery after it
## (at the game's playback speed).
const LEAD := 0.05
const SETTLE := 0.1
## The most a clip is sped up. Faster than this a cut stops being readable,
## and it simply takes longer than the game's cut.
const MAX_SPEED := 2.4
## Metadata a trimmed clip carries (seconds on its own timeline): the span of
## the swing (Vector2), the moment of peak speed, and the speed it plays at
## against the source.
const META_SWING := &"swing"
const META_PEAK := &"peak"
const META_SPEED := &"speed"


## The summed turning speed of the sword arm and spine, radians a second,
## sampled every STEP from the start of the clip (smoothed over three samples).
static func turning_speed(anim: Animation) -> PackedFloat32Array:
	var tracks: Array[int] = []
	for bone in BONES:
		var t := anim.find_track(NodePath(SKELETON + bone), Animation.TYPE_ROTATION_3D)
		if t >= 0:
			tracks.append(t)
	var count := int(anim.length / STEP) + 1
	var raw := PackedFloat32Array()
	raw.resize(count)
	var last: Array[Quaternion] = []
	for i in count:
		var at := minf(i * STEP, anim.length)
		var now: Array[Quaternion] = []
		var sum := 0.0
		for k in tracks.size():
			var q := anim.rotation_track_interpolate(tracks[k], at)
			now.append(q)
			if i > 0:
				sum += 2.0 * acos(clampf(absf(last[k].dot(q)), 0.0, 1.0)) / STEP
		raw[i] = sum
		last = now
	if count > 1:
		raw[0] = raw[1]
	var smooth := PackedFloat32Array()
	smooth.resize(count)
	for i in count:
		smooth[i] = (raw[maxi(i - 1, 0)] + raw[i] + raw[mini(i + 1, count - 1)]) / 3.0
	return smooth


## The swing in seconds of the clip, as Vector2(start, end), and the moment of
## its peak speed as `peak` (-1 when there is no swing, with a zero window).
static func window(anim: Animation) -> Dictionary:
	var speed := turning_speed(anim)
	var top := 0
	for i in speed.size():
		if speed[i] > speed[top]:
			top = i
	var peak := speed[top] if speed.size() > 0 else 0.0
	if peak < MIN_PEAK:
		return {"span": Vector2.ZERO, "peak": -1.0}
	var edge := peak * EDGE
	var gap := ceili(DIP / STEP)
	var start := top
	var quiet := 0
	var i := top - 1
	while i >= 0 and quiet <= gap:
		if speed[i] >= edge:
			start = i
			quiet = 0
		else:
			quiet += 1
		i -= 1
	var end := top
	quiet = 0
	i = top + 1
	while i < speed.size() and quiet <= gap:
		if speed[i] >= edge:
			end = i
			quiet = 0
		else:
			quiet += 1
		i += 1
	return {"span": Vector2(start * STEP, minf(end * STEP, anim.length)), "peak": top * STEP}


## `anim` cut down to its swing, with a lead-in before and a settle after, and
## sped up so the swing takes `swing_time` seconds (never slowed, and by at
## most MAX_SPEED). A clip without a swing is only sped up to fit. The result
## has no loop and carries META_SWING, META_PEAK and META_SPEED.
static func trim(anim: Animation, swing_time: float, lead := LEAD, settle := SETTLE) -> Animation:
	var found := window(anim)
	var span: Vector2 = found["span"]
	var from := 0.0
	var to := anim.length
	var speed := 1.0
	var peak := -1.0
	if span != Vector2.ZERO:
		speed = clampf((span.y - span.x) / maxf(swing_time, 0.05), 1.0, MAX_SPEED)
		from = maxf(0.0, span.x - lead * speed)
		to = minf(anim.length, span.y + settle * speed)
		peak = (float(found["peak"]) - from) / speed
	else:
		speed = clampf(anim.length / maxf(lead + swing_time + settle, 0.05), 1.0, MAX_SPEED)
	var out := Animation.new()
	out.length = (to - from) / speed
	out.step = anim.step
	out.loop_mode = Animation.LOOP_NONE
	for t in anim.get_track_count():
		var type := anim.track_get_type(t)
		if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_SCALE_3D:
			continue
		var o := out.add_track(type)
		out.track_set_path(o, anim.track_get_path(t))
		out.track_set_interpolation_type(o, anim.track_get_interpolation_type(t))
		# The source's own keys inside the window, and the window's two ends.
		var times: Array[float] = [from]
		for k in anim.track_get_key_count(t):
			var kt := anim.track_get_key_time(t, k)
			if kt > from + 1e-4 and kt < to - 1e-4:
				times.append(kt)
		times.append(to)
		for kt in times:
			var at := (kt - from) / speed
			match type:
				Animation.TYPE_POSITION_3D:
					out.position_track_insert_key(o, at, anim.position_track_interpolate(t, kt))
				Animation.TYPE_ROTATION_3D:
					out.rotation_track_insert_key(o, at, anim.rotation_track_interpolate(t, kt))
				_:
					out.scale_track_insert_key(o, at, anim.scale_track_interpolate(t, kt))
	var swing := Vector2(0.0, out.length)
	if span != Vector2.ZERO:
		swing = Vector2((span.x - from) / speed, (span.y - from) / speed)
	out.set_meta(META_SWING, swing)
	out.set_meta(META_PEAK, peak)
	out.set_meta(META_SPEED, speed)
	return out


## Where the right hand is, in the skeleton's space, `at` seconds into `anim`
## (forward kinematics from the clip's tracks over `skeleton`'s rest pose).
static func hand_at(anim: Animation, skeleton: Skeleton3D, at: float) -> Vector3:
	var chain: Array[int] = []
	var bone := skeleton.find_bone(&"RightHand")
	while bone >= 0:
		chain.push_front(bone)
		bone = skeleton.get_bone_parent(bone)
	var xf := Transform3D.IDENTITY
	for b in chain:
		var rest := skeleton.get_bone_rest(b)
		var path := NodePath(SKELETON + skeleton.get_bone_name(b))
		var rot := rest.basis.get_rotation_quaternion()
		var pos := rest.origin
		var rt := anim.find_track(path, Animation.TYPE_ROTATION_3D)
		if rt >= 0:
			rot = anim.rotation_track_interpolate(rt, at)
		var pt := anim.find_track(path, Animation.TYPE_POSITION_3D)
		if pt >= 0:
			pos = anim.position_track_interpolate(pt, at)
		xf = xf * Transform3D(Basis(rot), pos)
	return xf.origin


## The way the hand travels across the body at the swing's peak, in skeleton
## space (`span` seconds either side of it): not normalised, ZERO for a clip
## that has no swing.
static func travel(anim: Animation, skeleton: Skeleton3D, span := 0.05) -> Vector3:
	var peak: float = anim.get_meta(META_PEAK, -1.0)
	if peak < 0.0:
		return Vector3.ZERO
	return hand_at(anim, skeleton, minf(peak + span, anim.length)) - hand_at(anim, skeleton, maxf(peak - span, 0.0))
