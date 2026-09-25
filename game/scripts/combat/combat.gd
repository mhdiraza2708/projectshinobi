class_name Combat
extends RefCounted
## Shared hit plumbing. Anything that can be damaged implements:
##   func take_hit(amount: float, element: int, source: Node) -> float

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_TARGETS := 4
const LAYER_PROJECTILES := 8
const LAYER_WALLS := 16

## What attacks can connect with.
const HIT_MASK := LAYER_WORLD | LAYER_PLAYER | LAYER_TARGETS | LAYER_WALLS
## What characters stand on / bump into.
const BODY_MASK := LAYER_WORLD | LAYER_TARGETS | LAYER_WALLS


## Walks up from a collider to the node that owns `take_hit`, if any.
static func find_hittable(node: Node) -> Node:
	var n := node
	for i in 4:
		if n == null:
			return null
		if n.has_method("take_hit"):
			return n
		n = n.get_parent()
	return null


static func apply_hit(target: Node, amount: float, element: int, source: Node) -> float:
	if target == null or target == source or not target.has_method("take_hit"):
		return 0.0
	return target.take_hit(amount, element, source)


## Every distinct hittable overlapping a sphere, excluding `exclude`.
static func hittables_in_sphere(world: World3D, center: Vector3, radius: float,
		exclude: Array[RID] = [], mask := HIT_MASK) -> Array[Node]:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collision_mask = mask
	params.exclude = exclude
	var found: Array[Node] = []
	for hit in world.direct_space_state.intersect_shape(params, 32):
		var h := find_hittable(hit["collider"])
		if h and not found.has(h):
			found.append(h)
	return found


## Returns the ground height under `point`, or `fallback` if there is none.
static func ground_height(world: World3D, point: Vector3, fallback: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * 3.0, point + Vector3.DOWN * 20.0, LAYER_WORLD)
	var hit := world.direct_space_state.intersect_ray(query)
	return hit["position"].y if hit else fallback
