class_name Footsteps
extends Node
## The sound of a character's feet. A child of the CharacterAnimator: while a
## walking, running or sprinting clip plays, a step sounds at each moment a
## foot comes down in its cycle (PLANTS); a character without those clips
## steps once per STRIDE metres instead.
##
## What's underfoot picks the sound (see surface_of): an island's ground by
## what the terrain is made of there, the sea as water, and anything whose
## "surface" meta names a ground (one of Sfx.SURFACES).

## Where in each clip's cycle the left and right foot land (0-1): the clips
## are jog/walk/sprint loops, so the feet come down at the start and middle.
const PLANTS := {
	&"walk": [0.0, 0.5],
	&"run": [0.0, 0.5],
	&"sprint": [0.0, 0.5],
}
## Metres per step when there is no clip to follow.
const STRIDE := {&"walk": 0.75, &"run": 1.5, &"sprint": 2.0}
## Volume of a step by gait. Sounds are mastered for the loudest case, so
## these only turn them down.
const GAIT_DB := {&"walk": -6.0, &"run": -2.0, &"sprint": 0.0}
## A shuffle slower than this (a share of run speed) makes no sound.
const MIN_SPEED := 0.12
## Steps further than this from the camera aren't played at all.
const HEARING_RANGE := 30.0
## How far above and below the feet the ground is looked for.
const PROBE_UP := 0.4
const PROBE_DOWN := 0.8

var _animator: CharacterAnimator
var _body: Node3D
var _clip := &""
var _phase := 0.0
var _last_position := Vector3.ZERO
var _distance := 0.0


func _ready() -> void:
	_animator = get_parent() as CharacterAnimator
	var node := get_parent()
	while node and not node is CharacterBody3D:
		node = node.get_parent()
	# Cutscene actors and NPCs aren't bodies: their nearest spatial parent.
	_body = node as Node3D if node else _spatial_ancestor()
	set_process(_animator != null and _body != null)


func _process(_delta: float) -> void:
	if not _body.is_inside_tree():
		return
	var position := _body.global_position
	var moved := Vector2(position.x - _last_position.x, position.z - _last_position.z).length()
	_last_position = position
	var gait := _gait()
	if gait == &"":
		_clip = &""
		_distance = 0.0
		return
	var clip := _animator.current_clip()
	if PLANTS.has(clip) and _animator.clips.current_animation_length > 0.0:
		var phase := _animator.clips.current_animation_position / _animator.clips.current_animation_length
		if clip != _clip:
			# A new clip: start from where it is, without stepping.
			_clip = clip
		else:
			var marks: Array = PLANTS[clip]
			for foot in marks.size():
				if _crossed(_phase, phase, float(marks[foot])):
					_step(gait)
		_phase = phase
		return
	_clip = &""
	_distance += moved
	if _distance >= float(STRIDE[gait]):
		_distance -= float(STRIDE[gait])
		_step(gait)


## Which gait the feet are in (&"" when they aren't stepping at all).
func _gait() -> StringName:
	if _animator.airborne or _animator.speed_ratio < MIN_SPEED:
		return &""
	if _animator.pose != HumanoidPoser.Pose.LOCOMOTION and _animator.pose != HumanoidPoser.Pose.GUARD:
		return &""
	match _animator.current_clip():
		&"walk", &"run", &"sprint":
			return _animator.current_clip()
	if _animator.speed_ratio > 1.15:
		return &"sprint"
	return &"run" if _animator.speed_ratio > 0.45 else &"walk"


## Whether the cycle position went past `mark` between `from` and `to`
## (the cycle wraps from 1 back to 0).
static func _crossed(from: float, to: float, mark: float) -> bool:
	if to >= from:
		return from < mark and mark <= to
	return mark > from or mark <= to


func _step(gait: StringName) -> void:
	var position := _body.global_position
	var camera := get_viewport().get_camera_3d()
	if camera and camera.global_position.distance_to(position) > HEARING_RANGE:
		return
	# A little uneven, like real footfalls (never louder than the gait's).
	Sfx.footstep(surface_at(position), position, float(GAIT_DB[gait]) - randf_range(0.0, 1.5))


## The ground under `position`: found by looking down from the feet.
func surface_at(position: Vector3) -> StringName:
	var query := PhysicsRayQueryParameters3D.create(position + Vector3.UP * PROBE_UP,
		position + Vector3.DOWN * PROBE_DOWN, Combat.LAYER_WORLD)
	if _body is CollisionObject3D:
		query.exclude = [(_body as CollisionObject3D).get_rid()]
	var hit := _body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return &"dirt"
	return surface_of(hit["collider"] as Node, hit["position"])


## The ground a collider is at `point`: its "surface" meta if it has one, an
## island's terrain by Island.surface_at, otherwise packed earth.
static func surface_of(collider: Node, point: Vector3) -> StringName:
	if collider == null:
		return &"dirt"
	if collider.has_meta(&"surface"):
		return StringName(collider.get_meta(&"surface"))
	var island := collider.get_parent() as Island
	if island:
		return island.surface_at(point)
	return &"dirt"


func _spatial_ancestor() -> Node3D:
	var node := get_parent()
	while node and not node is Node3D:
		node = node.get_parent()
	return node as Node3D
