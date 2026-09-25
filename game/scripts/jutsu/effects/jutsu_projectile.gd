class_name JutsuProjectile
extends Node3D
## A travelling hit. Collision is swept in sub-steps no longer than the
## projectile's radius, so fast techniques can't tunnel through thin targets.

## How quickly the projectile turns toward the lock-on target (rad/s).
const HOMING_RATE := 2.2

var power := 10.0
var element := Element.NONE
var speed := 20.0
var max_range := 20.0
var radius := 0.3
var direction := Vector3.FORWARD
var caster: Node3D
var target: Node3D
var color := Color.WHITE
## Called with the node that was hit (or null for world geometry).
var on_hit: Callable

var _travelled := 0.0
var _exclude: Array[RID] = []
var _shape_params: PhysicsShapeQueryParameters3D


func _ready() -> void:
	if caster is CollisionObject3D:
		_exclude.append((caster as CollisionObject3D).get_rid())
	var shape := SphereShape3D.new()
	shape.radius = radius
	_shape_params = PhysicsShapeQueryParameters3D.new()
	_shape_params.shape = shape
	_shape_params.collision_mask = Combat.HIT_MASK
	_shape_params.exclude = _exclude

	color = Element.color(element)
	add_child(Vfx.sphere(radius, Vfx.glow_material(color, 3.0)))
	add_child(Vfx.light(color, radius * 10.0 + 2.0))
	add_child(Vfx.trail(color, radius * 0.6))


func _physics_process(delta: float) -> void:
	if is_instance_valid(target) and target.is_inside_tree():
		var aim := target.global_position + Vector3.UP * 1.0 - global_position
		if aim.length() > 0.5:
			direction = direction.slerp(aim.normalized(), clampf(HOMING_RATE * delta, 0.0, 1.0)).normalized()

	var distance := speed * delta
	var steps := maxi(1, ceili(distance / maxf(radius, 0.05)))
	var step := distance / steps
	var space := get_world_3d().direct_space_state
	for i in steps:
		global_position += direction * step
		_travelled += step
		_shape_params.transform = Transform3D(Basis.IDENTITY, global_position)
		var hits := space.intersect_shape(_shape_params, 1)
		if not hits.is_empty():
			_impact(hits[0]["collider"])
			return
		if _travelled >= max_range:
			queue_free()
			return


func _impact(collider: Node) -> void:
	var victim := Combat.find_hittable(collider)
	if victim:
		Combat.apply_hit(victim, power, element, caster)
	if on_hit.is_valid():
		on_hit.call(victim)
	Vfx.burst(get_parent(), global_position, color, radius * 3.0 + 0.6, 0.3)
	queue_free()
