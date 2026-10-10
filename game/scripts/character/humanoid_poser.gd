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
## Runs as a SkeletonModifier3D, i.e. *after* animation clips, so when Mixamo
## clips drive a state (see `clip_states`) it only layers what the clips can't
## provide, above all the hand-seal pose.

enum Pose { LOCOMOTION, WEAVE, CHARGE, GUARD, DASH }

## The body jumped further than any movement in one update (a teleport).
## Sent from inside the skeleton's modifier pass, before the hair and cloth
## physics (a later modifier) simulate it, so they can be settled first.
signal teleported(from: Transform3D, to: Transform3D)
## A jump further than this between updates is a teleport, not movement (no
## dash covers it, even at 10 frames a second).
const TELEPORT_DISTANCE := 3.0

const BLEND_RATE := 14.0
const THROW_TIME := 0.28

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
## Poses that animation clips already cover (set by CharacterAnimator). The
## poser leaves those alone, except the hand-seal arms, which it always owns.
var clip_states: Dictionary = {}

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
var _throw_t := 0.0
var _flick_t := 0.0
var _cast_t := 0.0
var _flinch_t := 0.0
var _cur: Dictionary = {}               # smoothed pose parameters
var _last_xform := Transform3D.IDENTITY
var _has_last := false
## A sword in the right hand: the arm holds it while moving and strikes are
## cuts (set by CharacterAnimator from the gear).
var sword_drawn := false
## The sheathed sword's grip (CharacterGear.hilt_grip), where the hand goes
## to draw and to sheathe.
var hilt: Node3D
var _cut_t := 0.0
var _cut := 0
var _draw_t := 0.0
var _sheathe_t := 0.0
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


## Basis mapping the canonical character frame (facing -Z, right +X, up +Y)
## into skeleton space.
func canonical_frame() -> Basis:
	return _frame


func strike() -> void:
	_strike_t = 0.24
	_strike_side = -_strike_side


const CUT_TIME := 0.26
## Drawing: the hand reaches the hilt (DRAW_REACH of the way), then the
## blade comes out in a cut across the front.
const DRAW_TIME := 0.36
const DRAW_REACH := 0.35
## Sheathing: the blade slides home (SHEATHE_HOME of the way), the hand lets go.
const SHEATHE_TIME := 0.34
const SHEATHE_HOME := 0.7


## A cut with the drawn sword: 0 down across from the right shoulder, 1
## rising back, 2 straight down from overhead.
func cut(index: int) -> void:
	_cut = posmod(index, 3)
	_cut_t = CUT_TIME
	_draw_t = 0.0
	_sheathe_t = 0.0


## The right hand goes to the hilt at the hip and draws in a cut.
func draw() -> void:
	_draw_t = DRAW_TIME
	_cut_t = 0.0
	_sheathe_t = 0.0


## The blade goes home into the scabbard.
func sheathe() -> void:
	_sheathe_t = SHEATHE_TIME
	_draw_t = 0.0
	_cut_t = 0.0


func is_drawing() -> bool:
	return _draw_t > 0.0


## A cut is under way.
func is_cutting() -> bool:
	return _cut_t > 0.0


func is_sheathing() -> bool:
	return _sheathe_t > 0.0


## Overhand right-handed throw (kunai).
func throw() -> void:
	_throw_t = THROW_TIME


func seal_flick() -> void:
	_flick_t = 0.14


const CAST_TIME := 0.32
const FLINCH_TIME := 0.26
## How much of a wrist's twist its forearm takes (see _share_wrist_twist).
const WRIST_TWIST_SHARE := 0.55

## A rush jutsu's right arm (see CharacterAnimator.rush_arm): 0 free, 1
## holding the technique out low at the side, palm up, 2 driving it forward.
var rush_arm := 0


## Both palms thrust forward as a jutsu leaves the hands (on the move, or on
## rigs without a cast clip).
func cast_push() -> void:
	_cast_t = CAST_TIME


## Rocked back by a blow (without a hit clip).
func flinch() -> void:
	_flinch_t = FLINCH_TIME


## Hip to ankle, in metres.
func leg_length() -> float:
	return _leg_len


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
		"curl": 0.35, "wrap_L": 0.0, "wrap_R": 0.0, "use_legs": true, "use_arms": true, "use_spine": true,
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

	if clip_states.has(pose):
		p["use_arms"] = false
		p["use_legs"] = false
		p["use_spine"] = false
		if pose == Pose.LOCOMOTION and speed_ratio > 1.05 and not airborne:
			# The shinobi sprint: the clip's legs, arms swept back behind,
			# and a deeper lean than any sprinter would dare.
			p["use_arms"] = true
			p["use_spine"] = true
			p["lean"] = 0.3
			p["twist"] = 0.0
	elif pose == Pose.WEAVE and clip_states.has(Pose.LOCOMOTION):
		# Seal arms over the idle clip's stance.
		p["use_legs"] = false
	if airborne and pose == Pose.LOCOMOTION:
		# In the air the body is posed, not clipped: legs tucked, arms out
		# for balance. A jump clip is a standing leap, and played over a
		# game's jump it reads as standing still in mid-air.
		p["use_arms"] = true
		p["use_legs"] = true
		p["use_spine"] = true

	if _throw_t > 0.0:
		# Wind up behind the head, then whip forward (with the left hand
		# while the right holds a sword).
		var t := 1.0 - _throw_t / THROW_TIME
		var sx := -1.0 if sword_drawn else 1.0
		var side := "L" if sword_drawn else "R"
		var arm := Vector3(0.18 * sx, 0.5, 0.35).lerp(Vector3(0.05 * sx, 0.02, -0.97), smoothstep(0.25, 0.75, t))
		p["arm_" + side] = arm
		p["pole_" + side] = Vector3(sx, -0.4, 0.6)
		p["hand_" + side] = Vector3(0, 0.3, -1)
		p["twist"] += lerpf(-0.3, 0.35, t) * sx
		p["curl"] = maxf(p["curl"], 1.1)
		p["use_arms"] = true
		p["use_spine"] = true

	if _cast_t > 0.0:
		# Draw in, then both palms out, fingers up, as the technique leaves.
		var t := 1.0 - _cast_t / CAST_TIME
		var push := smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(0.7, 1.0, t))
		for side in ["L", "R"]:
			var sx := -1.0 if side == "L" else 1.0
			p["arm_" + side] = (p["arm_" + side] as Vector3).lerp(Vector3(0.1 * sx, -0.08, -0.92), push)
			p["pole_" + side] = Vector3(sx, -1.0, 0.2)
			p["hand_" + side] = (p["hand_" + side] as Vector3).lerp(Vector3(0, 1, -0.25), push)
			p["thumb_" + side] = Vector3(-sx, 0, 0)
		p["curl"] = lerpf(p["curl"], 0.0, push)
		p["lean"] += 0.12 * push
		p["use_arms"] = true
		p["use_spine"] = true

	if rush_arm > 0:
		if rush_arm == 1:
			p["arm_R"] = Vector3(0.3, -0.5, -0.55)
			p["hand_R"] = Vector3(0.1, 0.15, -1)
			p["thumb_R"] = Vector3(1, 0, 0)
			p["twist"] += 0.25
		else:
			p["arm_R"] = Vector3(0.04, -0.1, -0.98)
			p["hand_R"] = Vector3(0, 1, -0.25)
			p["thumb_R"] = Vector3(-1, 0, 0)
			p["twist"] -= 0.3
		p["pole_R"] = Vector3(1, -1, 0.3)
		p["curl"] = 0.0
		p["use_arms"] = true
		p["use_spine"] = true

	if _flinch_t > 0.0:
		var k := sin(clampf(_flinch_t / FLINCH_TIME, 0.0, 1.0) * PI)
		p["lean"] -= 0.32 * k
		p["head_pitch"] += 0.3 * k
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
	if sword_drawn or _draw_t > 0.0 or _sheathe_t > 0.0:
		_sword(p)
	return p


# --- The sword -------------------------------------------------------------------
# Each key: the right arm's goal (arm lengths from the shoulder), the blade's
# direction (out of the thumb side of the fist) and the spine's twist, in
# the canonical frame (facing -Z, right +X). The edge (the knuckles) always
# leads the blade's motion, so it's worked out, never keyed.

## Down across from above the right shoulder to the left hip (kesa-giri).
const CUT_DOWN := [
	[Vector3(0.42, 0.38, -0.3), Vector3(0.35, 0.85, 0.4), -0.3],
	[Vector3(0.05, -0.08, -0.88), Vector3(-0.45, -0.1, -0.9), 0.1],
	[Vector3(-0.42, -0.58, -0.48), Vector3(-0.55, -0.7, 0.45), 0.45],
]
## Rising back from the left hip to above the right shoulder.
const CUT_UP := [
	[Vector3(-0.4, -0.58, -0.48), Vector3(-0.55, -0.7, 0.45), 0.45],
	[Vector3(0.1, -0.1, -0.9), Vector3(0.45, 0.1, -0.9), 0.0],
	[Vector3(0.5, 0.38, -0.3), Vector3(0.35, 0.85, 0.4), -0.35],
]
## Straight down from overhead (shomen), the finisher.
const CUT_OVERHEAD := [
	[Vector3(0.12, 0.78, -0.12), Vector3(0.0, 0.5, 0.85), 0.0],
	[Vector3(0.06, 0.05, -0.96), Vector3(0.0, 0.15, -1.0), 0.05],
	[Vector3(0.02, -0.55, -0.72), Vector3(0.0, -0.75, -0.65), 0.05],
]
## Along the worn scabbard, hilt end first (CharacterGear.SCABBARD_ALONG).
const SCABBARD := Vector3(0.2, 0.5, -1.0)
## The draw (nukitsuke): out of the scabbard with the blade still pointing
## back along it, the tip swinging out past the left, then level across the
## front to the right.
const DRAW_CUT := [
	[Vector3(-0.3, -0.62, -0.55), -SCABBARD, 0.45],
	[Vector3(-0.22, -0.42, -0.78), Vector3(-0.9, -0.1, -0.45), 0.35],
	[Vector3(0.18, -0.3, -0.92), Vector3(0.3, -0.05, -0.95), 0.0],
	[Vector3(0.62, -0.2, -0.55), Vector3(0.95, 0.0, 0.3), -0.35],
]
## Home again: across the front, the tip to the scabbard's mouth, and in.
const SHEATHE_KEYS := [
	[Vector3(0.25, -0.5, -0.6), Vector3(-0.2, -0.3, -0.95), 0.0],
	[Vector3(-0.22, -0.48, -0.72), Vector3(-0.95, -0.2, -0.25), 0.3],
	[Vector3(-0.3, -0.62, -0.55), -SCABBARD, 0.4],
]


## The way the blade travels across the front in cut `index`, or in the draw
## (-1): a unit vector in the canonical frame (facing -Z, right +X), without
## the depth. Where sparks and the like should fly.
static func cut_direction(index: int) -> Vector3:
	var keys: Array = DRAW_CUT.slice(1) if index < 0 else [CUT_DOWN, CUT_UP, CUT_OVERHEAD][posmod(index, 3)]
	var d: Vector3 = keys[-1][0] - keys[0][0]
	return Vector3(d.x, d.y, 0.0).normalized()


func _sword(p: Dictionary) -> void:
	_sword_hold(p)
	if _draw_t > 0.0:
		var t := 1.0 - _draw_t / DRAW_TIME
		if t < DRAW_REACH:
			# Across to the hilt at the left hip; the blade's edge is up, as
			# it's worn.
			var k := smoothstep(0.0, DRAW_REACH, t)
			_sword_key(p, DRAW_CUT[0][0], DRAW_CUT[0][1], Vector3.UP, DRAW_CUT[0][2] * k)
			p["hilt_w"] = k
			p["snap_R"] = true
		else:
			_sword_keys(p, DRAW_CUT, smoothstep(DRAW_REACH, 1.0, t))
			p["hilt_w"] = 1.0 - smoothstep(DRAW_REACH, DRAW_REACH + 0.2, t)
	elif _sheathe_t > 0.0:
		var t := 1.0 - _sheathe_t / SHEATHE_TIME
		if t < SHEATHE_HOME:
			var k := smoothstep(0.0, SHEATHE_HOME, t)
			_sword_keys(p, SHEATHE_KEYS, k)
			p["hilt_w"] = smoothstep(0.5, 1.0, k)
		else:
			# Let go: the hand falls back to the side.
			p["use_arm_R"] = true
			p["hilt_w"] = 1.0 - smoothstep(SHEATHE_HOME, 1.0, t)
			p["curl_R"] = lerpf(1.25, 0.35, smoothstep(SHEATHE_HOME, 1.0, t))
			p["wrap_R"] = lerpf(1.0, 0.0, smoothstep(SHEATHE_HOME, 1.0, t))
	elif _cut_t > 0.0:
		var keys: Array = [CUT_DOWN, CUT_UP, CUT_OVERHEAD][_cut]
		var t := 1.0 - _cut_t / CUT_TIME
		# A quick start, all the speed through the middle, a held finish.
		_sword_keys(p, keys, ease(t, 0.6))
		if _cut == 2:
			p["lean"] = float(p["lean"]) + lerpf(-0.1, 0.32, t)
			p["hips_drop"] = float(p["hips_drop"]) + 0.06 * sin(t * PI)


## Holding the drawn sword: the way a swordsman waits, the arm hanging easy at
## the side, the wrist cocked so the blade angles down and away from the leg,
## and the body loose (the shoulders level, the weight on one hip, the head a
## little low). Trailing back while running (the shinobi run), swept behind in
## a sprint.
func _sword_hold(p: Dictionary) -> void:
	if not sword_drawn and _draw_t <= 0.0:
		p["use_arm_R"] = p["use_arms"]
		return
	# The arm hangs all but straight (reach just short of full, so the elbow
	# only softens), a little out from the hip. The fingers run inward and down
	# along it (the palm faces forward, the knuckles back), so the wrist bends
	# only a little.
	var arm := Vector3(0.2, -0.97, -0.06)
	var blade := Vector3(0.5, -0.84, -0.18)
	var edge := Vector3(-0.8, -0.6, 0.15)
	if pose == Pose.GUARD:
		# A blade block: held level across in front of the head.
		arm = Vector3(0.12, 0.3, -0.58)
		blade = Vector3(-1.0, 0.18, -0.12)
		edge = Vector3(0.0, 0.6, -0.8)
	elif airborne:
		arm = Vector3(0.6, -0.45, 0.1)
		blade = Vector3(0.2, -0.4, 1.0)
		edge = Vector3(0.0, -1.0, -0.4)
	elif speed_ratio > 1.05:
		arm = Vector3(0.2, -0.45, 0.82)
		blade = Vector3(0.1, 0.1, 1.0)
		edge = Vector3(0.0, -1.0, 0.1)
	elif speed_ratio > 0.05:
		arm = Vector3(0.28, -0.75, 0.15)
		blade = Vector3(0.15, -0.45, 1.0)
		edge = Vector3(0.0, -1.0, -0.45)
	_sword_key(p, arm, blade, edge, 0.0)
	if arm.y < -0.9:
		# Hanging at the side: the elbow, if it bends at all, bends back.
		p["pole_R"] = Vector3(0.5, -0.3, 0.8)


func _sword_key(p: Dictionary, arm: Vector3, blade: Vector3, edge: Vector3, twist: float) -> void:
	var b := blade.normalized()
	var e := edge - b * edge.dot(b)
	p["arm_R"] = arm
	p["thumb_R"] = b
	p["hand_R"] = e.normalized() if e.length_squared() > 1e-6 else Vector3.DOWN
	p["pole_R"] = Vector3(1.0, -0.6, 0.4)
	p["curl_R"] = 1.5
	p["wrap_R"] = 1.0
	p["use_arm_R"] = true
	p["twist"] = float(p["twist"]) + twist
	p["use_spine"] = true
	# Only the sword arm: the other keeps what the clip or pose gives it.
	if not p.has("use_arm_L"):
		p["use_arm_L"] = p["use_arms"]


## Through evenly spaced keys at `t` (0-1), the edge leading the way the
## blade is turning.
func _sword_keys(p: Dictionary, keys: Array, t: float) -> void:
	var span := float(keys.size() - 1)
	var i := mini(int(t * span), keys.size() - 2)
	var u := clampf(t * span - i, 0.0, 1.0)
	var a: Array = keys[i]
	var b: Array = keys[i + 1]
	var from := (a[1] as Vector3).normalized()
	var to := (b[1] as Vector3).normalized()
	var blade := from.slerp(to, u)
	# Toward where the blade is going (or on from where it came, at the end).
	var edge := to - blade * to.dot(blade)
	if edge.length_squared() < 1e-4:
		edge = blade * blade.dot(from) - from
	_sword_key(p, (a[0] as Vector3).lerp(b[0], u), blade, edge, lerpf(a[2], b[2], u))
	p["snap_R"] = true


# --- Solve ---------------------------------------------------------------------

func _process_modification_with_delta(delta: float) -> void:
	if _skel:
		var now := _skel.global_transform
		if _has_last and now.origin.distance_to(_last_xform.origin) > TELEPORT_DISTANCE:
			teleported.emit(_last_xform, now)
		_last_xform = now
		_has_last = true
	if not _ready_for_pose:
		return
	_time += delta
	_strike_t = maxf(0.0, _strike_t - delta)
	_throw_t = maxf(0.0, _throw_t - delta)
	_flick_t = maxf(0.0, _flick_t - delta)
	_cast_t = maxf(0.0, _cast_t - delta)
	_flinch_t = maxf(0.0, _flinch_t - delta)
	_cut_t = maxf(0.0, _cut_t - delta)
	_draw_t = maxf(0.0, _draw_t - delta)
	_sheathe_t = maxf(0.0, _sheathe_t - delta)
	if speed_ratio > 0.05 and not airborne:
		_phase += delta * lerpf(6.0, 12.5, clampf(speed_ratio, 0.0, 1.6) / 1.6)

	var target := _target_params()
	var w := 1.0 - exp(-BLEND_RATE * delta)
	# A cut is too quick for the usual smoothing: the sword arm follows it
	# within a couple of frames.
	var snap: bool = target.get("snap_R", false)
	var fast := 1.0 - exp(-60.0 * delta)
	for key: String in target:
		var v: Variant = target[key]
		if snap and (key.ends_with("_R") or key in ["twist", "hilt_w"]) and (v is Vector3 or v is float) \
				and typeof(_cur.get(key)) == typeof(v):
			_cur[key] = (_cur[key] as Vector3).lerp(v, fast) if v is Vector3 else lerpf(_cur[key], v, fast)
		elif v is Vector3:
			_cur[key] = (_cur[key] as Vector3).lerp(v, w) if _cur.get(key) is Vector3 else v
		elif v is float:
			_cur[key] = lerpf(_cur[key], v, w) if _cur.get(key) is float else v
		else:
			_cur[key] = v
	# Optional keys (the seal, one arm only, the hilt) end when not asked for.
	for key: String in _cur.keys():
		if not target.has(key):
			_cur.erase(key)
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

	var shoulder_mid := (_pos(&"LeftUpperArm") + _pos(&"RightUpperArm")) * 0.5
	for side in ["L", "R"]:
		if not p.get("use_arm_" + side, p["use_arms"]):
			continue
		var pre := "Left" if side == "L" else "Right"
		var goal: Vector3
		if p.has("seal"):
			var sx := -0.035 if side == "L" else 0.035
			goal = shoulder_mid + _frame * ((p["seal"] + Vector3(sx, 0, 0)) * _arm_len)
		else:
			goal = _pos(StringName(pre + "UpperArm")) + _frame * (p["arm_" + side] * _arm_len)
		if side == "R" and float(p.get("hilt_w", 0.0)) > 0.001 and is_instance_valid(hilt):
			# The wrist sits a hand's breadth short of the grip it holds.
			var grip := _skel.global_transform.affine_inverse() * hilt.global_position
			grip -= (_frame * (p["hand_R"] as Vector3)).normalized() * _arm_len * 0.12
			goal = goal.lerp(grip, p["hilt_w"])
		_two_bone(StringName(pre + "UpperArm"), StringName(pre + "LowerArm"), StringName(pre + "Hand"),
			goal, _frame * p["pole_" + side])
		_aim_hand(pre, _frame * p["hand_" + side], _frame * p["thumb_" + side])
		_curl_fingers(pre, p.get("curl_" + side, p["curl"]))
		_curl_thumb(pre, float(p.get("wrap_" + side, 0.0)))

	# Clip or pose alike: share each wrist's twist with its forearm.
	for pre in ["Left", "Right"]:
		_share_wrist_twist(pre, WRIST_TWIST_SHARE)


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
	# The thumb side as the hand itself carries it (from the rest pose), not
	# where a clip has bent the thumb: steady, and the same side a drawn
	# sword is fitted to (CharacterGear._grip_in_hand).
	var rest := _skel.get_bone_global_rest(hand)
	var cur := t.basis * (rest.basis.inverse() * (_skel.get_bone_global_rest(_b[thumb_bone]).origin - rest.origin))
	cur = (cur - axis * cur.dot(axis)).normalized()
	var want := (thumb - axis * thumb.dot(axis)).normalized()
	if cur.length_squared() < 0.5 or want.length_squared() < 0.5:
		return
	var angle := cur.signed_angle_to(want, axis)
	t.basis = Basis(axis, angle) * t.basis
	_skel.set_bone_global_pose(hand, t)


## Turns the forearm with `share` of the hand's twist about it, the hand
## staying exactly where it is. Rigs without forearm twist bones (Tripo's,
## Mixamo's) otherwise wring the whole turn into the wrist, and a gauntlet
## or cuff skinned there folds into slabs; a real forearm rolls with the
## hand.
func _share_wrist_twist(pre: String, share: float) -> void:
	var lower_name := StringName(pre + "LowerArm")
	var hand_name := StringName(pre + "Hand")
	if not (_b.has(lower_name) and _b.has(hand_name)):
		return
	var lower: int = _b[lower_name]
	var hand: int = _b[hand_name]
	if _skel.get_bone_parent(hand) != lower:
		return
	var lt := _skel.get_bone_global_pose(lower)
	var ht := _skel.get_bone_global_pose(hand)
	var axis := ht.origin - lt.origin
	if axis.length_squared() < 1e-8:
		return
	axis = axis.normalized()
	# The hand's turn on the forearm since rest, then its twist about the
	# forearm (swing-twist decomposition), as a signed angle.
	var rest_hand := lt.basis.orthonormalized() * _skel.get_bone_rest(hand).basis.orthonormalized()
	var turn := (ht.basis.orthonormalized() * rest_hand.inverse()).get_rotation_quaternion()
	var along := Vector3(turn.x, turn.y, turn.z).dot(axis)
	var angle := wrapf(2.0 * atan2(along, turn.w), -PI, PI)
	if absf(angle) < 0.02:
		return
	lt.basis = Basis(axis, angle * share) * lt.basis
	_skel.set_bone_global_pose(lower, lt)
	_skel.set_bone_global_pose(hand, ht)


## The thumb's bones, base to tip, and how much of the wrap each takes.
const THUMB_SEGMENTS: Array[String] = ["ThumbMetacarpal", "ThumbProximal", "ThumbIntermediate", "ThumbDistal"]
const THUMB_SHARE := [0.35, 0.6, 0.6, 0.45]


## Wraps the thumb across the palm toward the little-finger side, as it lies
## over the fingers round a sword's grip (0 = at rest, 1 = round the grip).
func _curl_thumb(pre: String, amount: float) -> void:
	if amount < 0.01:
		return
	var hand_name := StringName(pre + "Hand")
	var mid := StringName(pre + "MiddleProximal")
	if not _b.has(hand_name) or not _b.has(mid):
		return
	var hand: int = _b[hand_name]
	var ht := _skel.get_bone_global_pose(hand)
	var rest := _skel.get_bone_global_rest(hand)
	var turn := ht.basis * rest.basis.inverse()
	var palm := (turn * (_frame * Vector3.DOWN)).normalized()
	var fingers := (_pos(mid) - ht.origin).normalized()
	# Where the thumb side is (as the hand carries it), and so the way across
	# the palm, away from it.
	var base_name := StringName(pre + "ThumbMetacarpal") if _b.has(StringName(pre + "ThumbMetacarpal")) else StringName(pre + "ThumbProximal")
	if not _b.has(base_name):
		return
	var side := turn * (_skel.get_bone_global_rest(_b[base_name]).origin - rest.origin)
	side = (side - fingers * side.dot(fingers)).normalized()
	var toward := (palm * 0.75 - side * 0.65).normalized()
	for k in THUMB_SEGMENTS.size():
		var bone_name := StringName(pre + THUMB_SEGMENTS[k])
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
		var axis := along.normalized().cross(toward)
		if axis.length_squared() < 1e-8:
			continue
		t.basis = Basis(axis.normalized(), amount * float(THUMB_SHARE[k])) * t.basis
		_skel.set_bone_global_pose(i, t)


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
