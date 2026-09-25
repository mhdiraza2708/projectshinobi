class_name HumanoidPoser
extends SkeletonModifier3D
## Procedural body language for any humanoid skeleton (VRoid/VRM, Mixamo,
## or anything retargeted to Godot's SkeletonProfileHumanoid bone names).
##
## Poses are authored in a *canonical* character frame: facing -Z, right = +X,
## up = +Y, with distances in units of the character's own arm/leg length.
## Limbs are placed with two-bone IK, so the same pose data works for T-pose
## and A-pose rigs, any facing, and any proportions.
##
## Runs as a SkeletonModifier3D, i.e. *after* animation clips. With Mixamo
## clips driving locomotion, set `procedural_locomotion = false` and this only
## layers the poses clips can't provide (hand seals, charge, guard).

enum Pose { LOCOMOTION, WEAVE, CHARGE, GUARD, DASH }

const BLEND_RATE := 14.0

# Humanoid bone names (Godot SkeletonProfileHumanoid, which godot-vrm and
# Godot's retargeting both produce).
const HIPS := &"Hips"
const SPINE_CHAIN: Array[StringName] = [&"Spine", &"Chest", &"UpperChest"]
const NECK := &"Neck"
const HEAD := &"Head"
const FINGERS: Array[String] = ["Index", "Middle", "Ring", "Little"]
const FINGER_SEGMENTS: Array[String] = ["Proximal", "Intermediate", "Distal"]

var pose := Pose.LOCOMOTION
## 0 = idle, 1 = run, above 1 = sprint.
var speed_ratio := 0.0
var airborne := false
## False when animation clips handle idle/run/jump; the poser then only
## drives the special poses.
var procedural_locomotion := true

var _skel: Skeleton3D
var _b: Dictionary = {}                 # bone name -> index (only bones that exist)
var _frame := Basis.IDENTITY            # canonical -> skeleton space
var _arm_len := 0.5
var _leg_len := 0.8
var _rest_foot := {}                    # "L"/"R" -> skeleton-space rest position
var _time := 0.0
var _phase := 0.0
var _strike_t := 0.0
var _strike_side := 1.0
var _flick_t := 0.0
var _cur: Dictionary = {}               # smoothed pose parameters
var _ready_for_pose := false


## Call once after the skeleton is in the tree. Returns false if the rig
## lacks the bones this needs (in which case the modifier stays inactive).
func setup(skeleton: Skeleton3D) -> bool:
	_skel = skeleton
	_b.clear()
	for i in skeleton.get_bone_count():
		_b[StringName(skeleton.get_bone_name(i))] = i
	for required in [HIPS, &"Spine", HEAD, &"LeftUpperArm", &"LeftLowerArm", &"LeftHand",
			&"RightUpperArm", &"RightLowerArm", &"RightHand", &"LeftUpperLeg", &"LeftLowerLeg",
			&"LeftFoot", &"RightUpperLeg", &"RightLowerLeg", &"RightFoot"]:
		if not _b.has(required):
			push_warning("HumanoidPoser: rig has no '%s' bone; procedural posing disabled" % required)
			active = false
			return false

	var up := (_rest(HEAD).origin - _rest(HIPS).origin).normalized()
	var right := (_rest(&"RightUpperArm").origin - _rest(&"LeftUpperArm").origin)
	right = (right - up * right.dot(up)).normalized()
	var back := right.cross(up).normalized()
	_frame = Basis(right, up, back)

	_arm_len = _dist(&"LeftUpperArm", &"LeftLowerArm") + _dist(&"LeftLowerArm", &"LeftHand")
	_leg_len = _dist(&"LeftUpperLeg", &"LeftLowerLeg") + _dist(&"LeftLowerLeg", &"LeftFoot")
	_rest_foot = {"L": _rest(&"LeftFoot").origin, "R": _rest(&"RightFoot").origin}
	_ready_for_pose = true
	active = true
	return true


## Direction the character faces, in skeleton space.
func forward_in_skeleton() -> Vector3:
	return -_frame.z


func strike() -> void:
	_strike_t = 0.24
	_strike_side = -_strike_side


func seal_flick() -> void:
	_flick_t = 0.14


# --- Pose authoring ------------------------------------------------------------
# Arm targets: offset from the shoulder, in arm lengths. Leg targets: offset of
# the foot from its rest position, in leg lengths. Values are for the LEFT side
# (canonical -X); the right side mirrors x unless given explicitly.

func _target_params() -> Dictionary:
	var p := {
		"lean": 0.0, "twist": 0.0, "head_pitch": 0.0, "hips_drop": 0.02,
		"arm_L": Vector3(-0.2, -0.93, 0.06), "arm_R": Vector3(0.2, -0.93, 0.06),
		"pole_L": Vector3(-0.3, 0.0, 1.0), "pole_R": Vector3(0.3, 0.0, 1.0),
		"hand_L": Vector3(0, -1, 0), "hand_R": Vector3(0, -1, 0),
		"thumb_L": Vector3(0, 0, -1), "thumb_R": Vector3(0, 0, -1),
		"foot_L": Vector3.ZERO, "foot_R": Vector3.ZERO,
		"curl": 0.35, "use_legs": procedural_locomotion,
		"use_arms": procedural_locomotion, "use_spine": procedural_locomotion,
	}
	var breath := sin(_time * 2.2)
	p["arm_L"].y += breath * 0.01
	p["arm_R"].y += breath * 0.01

	match pose:
		Pose.LOCOMOTION:
			if airborne:
				p["foot_L"] = Vector3(0, 0.32, -0.12)
				p["foot_R"] = Vector3(0, 0.14, 0.1)
				p["arm_L"] = Vector3(-0.62, -0.5, 0.05)
				p["arm_R"] = Vector3(0.62, -0.5, 0.05)
				p["hips_drop"] = 0.0
			elif speed_ratio > 1.05:
				# Sprint: forward lean, arms trailing behind.
				var s := sin(_phase)
				p["lean"] = 0.5
				p["head_pitch"] = -0.35
				p["arm_L"] = Vector3(-0.2, -0.45, 0.82)
				p["arm_R"] = Vector3(0.2, -0.45, 0.82)
				p["hand_L"] = Vector3(0, -0.3, 1)
				p["hand_R"] = Vector3(0, -0.3, 1)
				p["foot_L"] = Vector3(0, 0.26 * maxf(0.0, cos(_phase)), -0.42 * s)
				p["foot_R"] = Vector3(0, 0.26 * maxf(0.0, -cos(_phase)), 0.42 * s)
				p["hips_drop"] = 0.06 + 0.04 * absf(cos(_phase))
				p["curl"] = 0.2
			elif speed_ratio > 0.05:
				var k := clampf(speed_ratio, 0.0, 1.0)
				var s := sin(_phase)
				p["lean"] = 0.14 * k
				p["twist"] = -0.12 * k * s
				p["arm_L"] = Vector3(-0.2, -0.78, 0.38 * k * s)
				p["arm_R"] = Vector3(0.2, -0.78, -0.38 * k * s)
				p["pole_L"] = Vector3(-0.2, -0.3, 1.0)
				p["pole_R"] = Vector3(0.2, -0.3, 1.0)
				p["foot_L"] = Vector3(0, 0.2 * k * maxf(0.0, cos(_phase)), -0.34 * k * s)
				p["foot_R"] = Vector3(0, 0.2 * k * maxf(0.0, -cos(_phase)), 0.34 * k * s)
				p["hips_drop"] = 0.03 + 0.035 * k * absf(cos(_phase))
				p["curl"] = 0.9
		Pose.WEAVE:
			# Palms pressed together in front of the chest, fingers up.
			var flick := sin(clampf(_flick_t / 0.14, 0.0, 1.0) * PI) * 0.06
			p["seal"] = Vector3(0, -0.32 + flick, -0.5)
			p["pole_L"] = Vector3(-1.0, -0.7, 0.4)
			p["pole_R"] = Vector3(1.0, -0.7, 0.4)
			p["hand_L"] = Vector3(0, 0.85, -0.35)
			p["hand_R"] = Vector3(0, 0.85, -0.35)
			p["thumb_L"] = Vector3(0, 0, 1)
			p["thumb_R"] = Vector3(0, 0, 1)
			p["curl"] = 0.0
			p["lean"] = 0.06
			p["foot_L"] = Vector3(-0.07, 0, 0)
			p["foot_R"] = Vector3(0.07, 0, 0)
			p["hips_drop"] = 0.05
			p["use_arms"] = true
			p["use_legs"] = true
			p["use_spine"] = true
		Pose.CHARGE:
			var tremble := sin(_time * 38.0) * 0.012
			p["arm_L"] = Vector3(-0.42, -0.78 + tremble, 0.12)
			p["arm_R"] = Vector3(0.42, -0.78 - tremble, 0.12)
			p["pole_L"] = Vector3(-1, 0, 0.6)
			p["pole_R"] = Vector3(1, 0, 0.6)
			p["curl"] = 1.2
			p["lean"] = -0.1
			p["head_pitch"] = 0.18
			p["foot_L"] = Vector3(-0.16, 0, 0)
			p["foot_R"] = Vector3(0.16, 0, 0)
			p["hips_drop"] = 0.13
			p["use_arms"] = true
			p["use_legs"] = true
			p["use_spine"] = true
		Pose.GUARD:
			# Forearms crossed in front of the face.
			p["arm_L"] = Vector3(0.42, 0.22, -0.5)
			p["arm_R"] = Vector3(-0.42, 0.16, -0.56)
			p["pole_L"] = Vector3(-1, -1, 0)
			p["pole_R"] = Vector3(1, -1, 0)
			p["hand_L"] = Vector3(0.4, 1, 0)
			p["hand_R"] = Vector3(-0.4, 1, 0)
			p["curl"] = 1.1
			p["lean"] = 0.18
			p["foot_L"] = Vector3(-0.05, 0, -0.14)
			p["foot_R"] = Vector3(0.05, 0, 0.12)
			p["hips_drop"] = 0.08
			p["use_arms"] = true
			p["use_spine"] = true
		Pose.DASH:
			p["lean"] = 0.62
			p["head_pitch"] = -0.45
			p["arm_L"] = Vector3(-0.22, -0.35, 0.88)
			p["arm_R"] = Vector3(0.22, -0.35, 0.88)
			p["hand_L"] = Vector3(0, -0.2, 1)
			p["hand_R"] = Vector3(0, -0.2, 1)
			p["foot_L"] = Vector3(0, 0.12, -0.32)
			p["foot_R"] = Vector3(0, 0.22, 0.36)
			p["hips_drop"] = 0.1
			p["curl"] = 0.2
			p["use_arms"] = true
			p["use_legs"] = true
			p["use_spine"] = true

	if _strike_t > 0.0:
		var punch := sin(clampf(_strike_t / 0.24, 0.0, 1.0) * PI)
		var side := "R" if _strike_side > 0.0 else "L"
		var sx := 1.0 if side == "R" else -1.0
		p["arm_" + side] = (p["arm_" + side] as Vector3).lerp(Vector3(-0.08 * sx, -0.05, -0.98), punch)
		p["pole_" + side] = Vector3(sx, -1, 0.3)
		p["hand_" + side] = (p["hand_" + side] as Vector3).lerp(Vector3(0, 0, -1), punch)
		p["twist"] += 0.4 * sx * punch
		p["curl"] = maxf(p["curl"], 1.3 * punch)
		p["use_arms"] = true
		p["use_spine"] = true
	return p


# --- Solve ---------------------------------------------------------------------

func _process_modification_with_delta(delta: float) -> void:
	if not _ready_for_pose:
		return
	_time += delta
	_strike_t = maxf(0.0, _strike_t - delta)
	_flick_t = maxf(0.0, _flick_t - delta)
	if speed_ratio > 0.05 and not airborne:
		_phase += delta * lerpf(6.0, 12.5, clampf(speed_ratio, 0.0, 1.6) / 1.6)

	var target := _target_params()
	var w := 1.0 - exp(-BLEND_RATE * delta)
	for key: String in target:
		var v: Variant = target[key]
		if v is Vector3:
			_cur[key] = (_cur[key] as Vector3).lerp(v, w) if _cur.get(key) is Vector3 else v
		elif v is float:
			_cur[key] = lerpf(_cur[key], v, w) if _cur.get(key) is float else v
		else:
			_cur[key] = v
	if not target.has("seal"):
		_cur.erase("seal")
	var p := _cur

	if p["use_legs"]:
		var hips := _skel.get_bone_global_pose(_b[HIPS])
		hips.origin += _frame * Vector3(0, -p["hips_drop"] * _leg_len, 0)
		_skel.set_bone_global_pose(_b[HIPS], hips)

	if p["use_spine"]:
		var spine_bones := SPINE_CHAIN.filter(func(n: StringName) -> bool: return _b.has(n))
		var share := 1.0 / spine_bones.size()
		var bend := Basis(_frame.x, -p["lean"] * share) * Basis(_frame.y, p["twist"] * share)
		for n in spine_bones:
			_rotate_global(_b[n], bend)
		if _b.has(HEAD):
			_rotate_global(_b[HEAD], Basis(_frame.x, -p["head_pitch"]))

	if p["use_legs"]:
		for side in ["L", "R"]:
			var pre := "Left" if side == "L" else "Right"
			var foot: Vector3 = _rest_foot[side] + _frame * (p["foot_" + side] * _leg_len)
			_two_bone(StringName(pre + "UpperLeg"), StringName(pre + "LowerLeg"), StringName(pre + "Foot"),
				foot, _frame * Vector3(0, 0, -1))

	if p["use_arms"]:
		var shoulder_mid := (_pos(&"LeftUpperArm") + _pos(&"RightUpperArm")) * 0.5
		for side in ["L", "R"]:
			var pre := "Left" if side == "L" else "Right"
			var goal: Vector3
			if p.has("seal"):
				var sx := -0.035 if side == "L" else 0.035
				goal = shoulder_mid + _frame * ((p["seal"] + Vector3(sx, 0, 0)) * _arm_len)
			else:
				goal = _pos(StringName(pre + "UpperArm")) + _frame * (p["arm_" + side] * _arm_len)
			_two_bone(StringName(pre + "UpperArm"), StringName(pre + "LowerArm"), StringName(pre + "Hand"),
				goal, _frame * p["pole_" + side])
			_aim_hand(pre, _frame * p["hand_" + side], _frame * p["thumb_" + side])
			_curl_fingers(pre, p["curl"])


func _rest(bone: StringName) -> Transform3D:
	return _skel.get_bone_global_rest(_b[bone])


func _dist(a: StringName, b: StringName) -> float:
	return _rest(a).origin.distance_to(_rest(b).origin)


func _pos(bone: StringName) -> Vector3:
	return _skel.get_bone_global_pose(_b[bone]).origin


## Rotates a bone in skeleton space about its own origin.
func _rotate_global(bone: int, rot: Basis) -> void:
	var t := _skel.get_bone_global_pose(bone)
	t.basis = rot * t.basis
	_skel.set_bone_global_pose(bone, t)


## Rotates `bone` so the direction to its child `child` becomes `dir`.
func _aim(bone: int, child_pos: Vector3, dir: Vector3) -> void:
	var t := _skel.get_bone_global_pose(bone)
	var cur := (child_pos - t.origin).normalized()
	var want := dir.normalized()
	if cur.dot(want) > 0.9999:
		return
	var axis := cur.cross(want)
	if axis.length_squared() < 1e-10:
		return
	t.basis = Basis(axis.normalized(), cur.angle_to(want)) * t.basis
	_skel.set_bone_global_pose(bone, t)


func _two_bone(upper: StringName, lower: StringName, end: StringName, target: Vector3, pole: Vector3) -> void:
	var a := _pos(upper)
	var b := _pos(lower)
	var c := _pos(end)
	var la := a.distance_to(b)
	var lb := b.distance_to(c)
	var to_t := target - a
	var d := clampf(to_t.length(), absf(la - lb) + 0.001, la + lb - 0.001)
	var dir := to_t.normalized() if to_t.length() > 0.0001 else (c - a).normalized()
	var bend := pole - dir * pole.dot(dir)
	if bend.length_squared() < 1e-8:
		bend = (b - a) - dir * (b - a).dot(dir)
	bend = bend.normalized()
	var cos_a := clampf((la * la + d * d - lb * lb) / (2.0 * la * d), -1.0, 1.0)
	var elbow := a + dir * (la * cos_a) + bend * (la * sqrt(1.0 - cos_a * cos_a))
	_aim(_b[upper], b, elbow - a)
	_aim(_b[lower], _pos(end), (a + dir * d) - elbow)


## Points the hand's fingers along `fingers`, then twists it so the thumb
## side faces `thumb`.
func _aim_hand(pre: String, fingers: Vector3, thumb: Vector3) -> void:
	var hand: int = _b[StringName(pre + "Hand")]
	var mid := StringName(pre + "MiddleProximal")
	if not _b.has(mid):
		return
	_aim(hand, _pos(mid), fingers)
	var thumb_bone := StringName(pre + "ThumbProximal")
	if not _b.has(thumb_bone):
		return
	var t := _skel.get_bone_global_pose(hand)
	var axis := (_pos(mid) - t.origin).normalized()
	var cur := _pos(thumb_bone) - t.origin
	cur = (cur - axis * cur.dot(axis)).normalized()
	var want := (thumb - axis * thumb.dot(axis)).normalized()
	if cur.length_squared() < 0.5 or want.length_squared() < 0.5:
		return
	var angle := cur.signed_angle_to(want, axis)
	t.basis = Basis(axis, angle) * t.basis
	_skel.set_bone_global_pose(hand, t)


## Curls the four fingers toward the palm (0 = flat, ~1.3 = fist).
func _curl_fingers(pre: String, amount: float) -> void:
	if amount < 0.01:
		return
	var hand: int = _b[StringName(pre + "Hand")]
	var ht := _skel.get_bone_global_pose(hand)
	# VRM and Godot's humanoid profile rest with palms facing down.
	var palm := (ht.basis * _skel.get_bone_global_rest(hand).basis.inverse()) * (_frame * Vector3.DOWN)
	for finger in FINGERS:
		for seg in FINGER_SEGMENTS:
			var bone_name := StringName(pre + finger + seg)
			if not _b.has(bone_name):
				continue
			var i: int = _b[bone_name]
			var t := _skel.get_bone_global_pose(i)
			var children := _skel.get_bone_children(i)
			var along: Vector3
			if children.is_empty():
				along = t.origin - _skel.get_bone_global_pose(_skel.get_bone_parent(i)).origin
			else:
				along = _skel.get_bone_global_pose(children[0]).origin - t.origin
			var axis := along.normalized().cross(palm)
			if axis.length_squared() < 1e-8:
				continue
			t.basis = Basis(axis.normalized(), amount * 0.55) * t.basis
			_skel.set_bone_global_pose(i, t)
