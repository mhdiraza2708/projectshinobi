extends TestCase
## What is solid on the continent near you: rivers and lakes are stood on
## (like the sea), and trunks and rocks stop you.

var world: ContinentWorld
var marker: Node3D


func after_each() -> void:
	if is_instance_valid(world):
		world.queue_free()
	if is_instance_valid(marker):
		marker.queue_free()


func _make_at(local: Vector3) -> void:
	marker = Node3D.new()
	root.add_child(marker)
	world = ContinentWorld.new()
	world.player = marker
	root.add_child(world)
	world.build_now(local)
	await world.ground_ready()
	await world.settle_ground(world.to_global(local))
	await physics_frames(2)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, Combat.LAYER_WORLD)
	return world.get_world_3d().direct_space_state.intersect_ray(q)


## A point in the middle of a river, on land, with its water well above the bed.
func _river_point(land: ContinentLand) -> Vector2:
	for path: Dictionary in land.rivers.paths:
		var pts: PackedVector2Array = path["points"]
		for i in range(pts.size() / 4, pts.size() * 3 / 4):
			var p := pts[i]
			var wl := land.water_level_at(p.x, p.y)
			if wl > land.height_at(p.x, p.y) + 0.4 and wl > ContinentLand.SEA_LEVEL + 3.0:
				return p
	return Vector2.INF


func test_a_river_is_stood_on_at_its_surface() -> void:
	var land := ContinentLand.new()
	var p := _river_point(land)
	assert_true(p != Vector2.INF, "found a river")
	var level := land.water_level_at(p.x, p.y)
	await _make_at(Vector3(p.x, level, p.y))
	var top := world.to_global(Vector3(p.x, level + 40.0, p.y))
	var hit := _ray(top, top + Vector3.DOWN * 80.0)
	assert_false(hit.is_empty(), "something under the river")
	var y := world.to_local(hit["position"]).y
	assert_near(y, level, 0.35, "at the water's surface (%.2f), not the bed (%.2f)" % [level, land.height_at(p.x, p.y)])
	# A body that lands there is on water (the sprint bonus, the ripples).
	var body := CharacterBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = CapsuleShape3D.new()
	col.position.y = 0.9
	body.add_child(col)
	body.collision_mask = Combat.LAYER_WORLD
	world.add_child(body)
	body.position = Vector3(p.x, level + 1.5, p.y)
	for i in 40:
		body.velocity = Vector3(0, -6, 0)
		body.move_and_slide()
		await physics_frames(1)
	assert_true(body.is_on_floor(), "it stands")
	assert_true(world.on_water(body), "on water")
	body.queue_free()


func test_trunks_and_rocks_stop_you() -> void:
	var land := ContinentLand.new()
	ContinentScatter.warm()
	# A wooded square with a pine and a rock in it.
	var tree := Vector3.INF
	var rock := Vector3.INF
	var rock_scale := 1.0
	for gx in range(-10, 11):
		for gz in range(-10, 11):
			var rect := Rect2(gx * 128.0, gz * 128.0, 128.0, 128.0)
			var found := ContinentScatter.instances(land, rect)
			if tree == Vector3.INF and found.has("pine"):
				var raw: PackedFloat32Array = found["pine"]
				tree = Vector3(raw[0], raw[1], raw[2])
			if rock == Vector3.INF and found.has("rock"):
				var raw: PackedFloat32Array = found["rock"]
				rock = Vector3(raw[0], raw[1], raw[2])
				rock_scale = raw[4]
			if tree != Vector3.INF and rock != Vector3.INF:
				break
		if tree != Vector3.INF and rock != Vector3.INF:
			break
	assert_true(tree != Vector3.INF and rock != Vector3.INF, "found a pine and a rock")
	await _make_at(tree)
	var at := world.to_global(tree + Vector3.UP * 1.0)
	var hit := _ray(at + Vector3(4, 0, 0), at)
	assert_false(hit.is_empty(), "the pine's trunk is solid")
	assert_true(Vector2(hit["position"].x - at.x, hit["position"].z - at.z).length() < 0.8, "and thin, not its crown")
	# A rock, nearby or after a walk there.
	marker.global_position = world.to_global(rock)
	await world.settle_ground(world.to_global(rock))
	await physics_frames(2)
	var spec: Dictionary = ContinentScatter.solid_specs()["rock"]
	var mid := world.to_global(rock + Vector3.UP * float(spec["y"]) * rock_scale)
	hit = _ray(mid + Vector3(0, 0, 6), mid)
	assert_false(hit.is_empty(), "the rock is solid")
