class_name JutsuProjectile
extends Node3D
## A travelling hit. Collision is swept in sub-steps no longer than the
## projectile's radius, so fast techniques can't tunnel through thin targets.

## How long a thrown kunai stays stuck in what it hit.
const STUCK_TIME := 1.6

var power := 10.0
var element := Element.NONE
var speed := 20.0
var max_range := 20.0
var radius := 0.3
var direction := Vector3.FORWARD
var caster: Node3D
var target: Node3D
var color := Color.WHITE
## &"orb" (glowing chakra) or &"kunai" (steel blade that sticks where it lands).
var style := &"orb"
## How quickly the projectile turns toward its target (rad/s).
var homing_rate := 2.2
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
	if style == &"kunai":
		add_child(Vfx.kunai())
		add_child(Vfx.trail(Color(1, 1, 1, 0.9), 0.05))
		_orient()
	else:
		add_child(Vfx.sphere(radius, Vfx.glow_material(color, 3.0)))
		add_child(Vfx.light(color, radius * 10.0 + 2.0))
		add_child(Vfx.trail(color, radius * 0.6))


func _physics_process(delta: float) -> void:
	if is_instance_valid(target) and target.is_inside_tree():
		var aim := target.global_position + Vector3.UP * 1.0 - global_position
		if aim.length() > 0.5:
			direction = direction.slerp(aim.normalized(), clampf(homing_rate * delta, 0.0, 1.0)).normalized()
	if style == &"kunai":
		_orient()

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
	Sfx.play_at(&"kunai_hit" if style == &"kunai" else &"impact", global_position,
		0.0 if victim else -6.0)
	if style == &"kunai":
		_stick(collider as Node3D)
	else:
		Vfx.burst(get_parent(), global_position, color, radius * 3.0 + 0.6, 0.3)
	queue_free()


## Points the blade along its flight.
func _orient() -> void:
	if direction.length_squared() > 0.0001:
		global_basis = Basis.looking_at(direction, Vector3.UP if absf(direction.y) < 0.99 else Vector3.BACK)


## Leaves a kunai stuck in whatever was hit, riding along with it.
func _stick(into: Node3D) -> void:
	var stuck := Vfx.kunai()
	var holder: Node = into if into and into.is_inside_tree() else get_parent()
	holder.add_child(stuck)
	stuck.global_transform = Transform3D(global_basis, global_position - direction * 0.08)
	Vfx.burst(get_parent(), global_position, Color(1.0, 0.95, 0.8), 0.35, 0.15)
	stuck.get_tree().create_timer(STUCK_TIME).timeout.connect(stuck.queue_free)
