class_name HitStop
extends RefCounted
## The half-beat the world holds when a cut lands: Engine.time_scale drops
## to almost nothing for a few frames, and a timer that ignores time scale
## (and pauses) puts it back. It only ever dips from a plain 1.0, so it never
## fights another slow-motion (Mirror Eye), and it stays out of cutscenes,
## ultimates and a paused game.

## What the world slows to while it holds.
const SCALE := 0.04

static var _active := false


## Holds the world for `seconds` of real time. Returns whether it did.
static func freeze(tree: SceneTree, seconds := 0.06) -> bool:
	if _active or tree == null or tree.paused or not is_equal_approx(Engine.time_scale, 1.0):
		return false
	if Cutscene.active != null or UltimateSequence.active != null:
		return false
	_active = true
	Engine.time_scale = SCALE
	# Real time, not slowed time; it fires through a pause too.
	tree.create_timer(seconds, true, false, true).timeout.connect(release)
	return true


## Lets the world go again. Also called when whoever started the hold is
## gone, so it can't stay held.
static func release() -> void:
	# Someone else's slow-motion (set meanwhile) is left alone.
	if _active and is_equal_approx(Engine.time_scale, SCALE):
		Engine.time_scale = 1.0
	_active = false


static func is_active() -> bool:
	return _active
