class_name ProceduralAnimator
extends Node
## Poses the blockout character by rotating its jointed parts (named Hips,
## Torso, Head, ArmL/R, LegL/R in the Blender script). This stands in for real
## skeletal animation, which needs a rigged model and authored/mocap clips
## (roadmap M2). Keep the public API (pose, speed_ratio, strike(), ...) when
## swapping to an AnimationTree so the player controller doesn't change.

enum Pose { LOCOMOTION, WEAVE, CHARGE, GUARD, DASH }

const PART_NAMES: PackedStringArray = ["Hips", "Torso", "Head", "ArmL", "ArmR", "LegL", "LegR"]
const BLEND_RATE := 16.0

var pose := Pose.LOCOMOTION
## 0 = idle, 1 = full run, above 1 = sprinting.
var speed_ratio := 0.0
var airborne := false

var _parts: Dictionary = {}
var _rest_pos: Dictionary = {}
var _time := 0.0
var _phase := 0.0
var _strike_t := 0.0
var _strike_side := 1.0
var _flick_t := 0.0


func bind(model: Node) -> void:
	_parts.clear()
	for part_name in PART_NAMES:
		var n := model.find_child(part_name, true, false) as Node3D
		if n:
			_parts[part_name] = n
			_rest_pos[part_name] = n.position


func is_bound() -> bool:
	return _parts.size() == PART_NAMES.size()


func strike() -> void:
	_strike_t = 0.22
	_strike_side = -_strike_side


func seal_flick() -> void:
	_flick_t = 0.12


func _process(delta: float) -> void:
	if _parts.is_empty():
		return
	_time += delta
	_strike_t = maxf(0.0, _strike_t - delta)
	_flick_t = maxf(0.0, _flick_t - delta)
	if speed_ratio > 0.05 and not airborne:
		_phase += delta * lerpf(5.0, 13.0, clampf(speed_ratio, 0.0, 1.5) / 1.5)

	var rot := {}
	for n in PART_NAMES:
		rot[n] = Vector3.ZERO
	var hips_drop := 0.0

	match pose:
		Pose.LOCOMOTION:
			if airborne:
				rot["LegL"] = Vector3(0.7, 0, 0)
				rot["LegR"] = Vector3(-0.25, 0, 0)
				rot["ArmL"] = Vector3(0.3, 0, -0.6)
				rot["ArmR"] = Vector3(0.3, 0, 0.6)
			elif speed_ratio > 1.05:
				# Sprint: forward lean with arms swept back.
				var s := sin(_phase)
				rot["Torso"] = Vector3(-0.45, 0, 0)
				rot["Head"] = Vector3(0.35, 0, 0)
				rot["ArmL"] = Vector3(-1.1, 0, -0.25)
				rot["ArmR"] = Vector3(-1.1, 0, 0.25)
				rot["LegL"] = Vector3(s * 0.95, 0, 0)
				rot["LegR"] = Vector3(-s * 0.95, 0, 0)
				hips_drop = 0.06 - absf(cos(_phase)) * 0.05
			elif speed_ratio > 0.05:
				var s := sin(_phase)
				var k := clampf(speed_ratio, 0.0, 1.0)
				rot["Torso"] = Vector3(-0.12 * k, sin(_phase) * 0.08 * k, 0)
				rot["ArmL"] = Vector3(-s * 0.7 * k, 0, -0.08)
				rot["ArmR"] = Vector3(s * 0.7 * k, 0, 0.08)
				rot["LegL"] = Vector3(s * 0.75 * k, 0, 0)
				rot["LegR"] = Vector3(-s * 0.75 * k, 0, 0)
				hips_drop = absf(cos(_phase)) * 0.04 * k
			else:
				var breath := sin(_time * 2.0)
				rot["Torso"] = Vector3(breath * 0.02, 0, 0)
				rot["ArmL"] = Vector3(0.05, 0, -0.1 - breath * 0.02)
				rot["ArmR"] = Vector3(0.05, 0, 0.1 + breath * 0.02)
		Pose.WEAVE:
			var flick := sin(_flick_t / 0.12 * PI) * 0.25
			rot["Torso"] = Vector3(-0.06, 0, 0)
			rot["Head"] = Vector3(-0.1, 0, 0)
			rot["ArmL"] = Vector3(0.95 + flick, 0, 0.5)
			rot["ArmR"] = Vector3(0.95 + flick, 0, -0.5)
			rot["LegL"] = Vector3(0, 0, -0.08)
			rot["LegR"] = Vector3(0, 0, 0.08)
		Pose.CHARGE:
			var tremble := sin(_time * 40.0) * 0.015
			rot["Torso"] = Vector3(0.1 + tremble, 0, 0)
			rot["Head"] = Vector3(0.15, 0, 0)
			rot["ArmL"] = Vector3(-0.1, 0, -0.45)
			rot["ArmR"] = Vector3(-0.1, 0, 0.45)
			rot["LegL"] = Vector3(0, 0, -0.18)
			rot["LegR"] = Vector3(0, 0, 0.18)
			hips_drop = 0.07
		Pose.GUARD:
			rot["Torso"] = Vector3(-0.15, 0, 0)
			rot["ArmL"] = Vector3(1.75, 0, 0.55)
			rot["ArmR"] = Vector3(1.9, 0, -0.55)
			rot["LegL"] = Vector3(0.25, 0, -0.1)
			rot["LegR"] = Vector3(-0.2, 0, 0.1)
			hips_drop = 0.05
		Pose.DASH:
			rot["Torso"] = Vector3(-0.6, 0, 0)
			rot["Head"] = Vector3(0.4, 0, 0)
			rot["ArmL"] = Vector3(-1.2, 0, -0.3)
			rot["ArmR"] = Vector3(-1.2, 0, 0.3)
			rot["LegL"] = Vector3(0.8, 0, 0)
			rot["LegR"] = Vector3(-0.7, 0, 0)
			hips_drop = 0.1

	if _strike_t > 0.0:
		var punch := sin(_strike_t / 0.22 * PI)
		var arm := "ArmR" if _strike_side > 0.0 else "ArmL"
		rot[arm] = Vector3(1.55 * punch + rot[arm].x * (1.0 - punch), 0, 0)
		rot["Torso"] += Vector3(0, -0.35 * _strike_side * punch, 0)

	var w := 1.0 - exp(-BLEND_RATE * delta)
	for n: String in _parts:
		var part: Node3D = _parts[n]
		part.rotation = part.rotation.lerp(rot[n], w)
	var hips: Node3D = _parts.get("Hips")
	if hips:
		hips.position.y = lerpf(hips.position.y, _rest_pos["Hips"].y - hips_drop, w)
