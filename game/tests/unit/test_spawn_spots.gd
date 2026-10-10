extends TestCase
## Fighters are never placed inside a rock, a wall or a prop: Combat.clear_spot
## finds the nearest free spot, and the story's and the trials' spawn points
## use it. (Ashen Pass, with the biggest rocks, had the most spawn points
## buried in them.)

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D


func after_each() -> void:
	if is_instance_valid(scene):
		scene.queue_free()


func _load(island: String) -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	await physics_frames(5)
	scene.use_island(island)
	await physics_frames(4)


## Whether a standing fighter overlaps anything solid at `p`.
func _buried(p: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 0.9, 0))
	q.collision_mask = Combat.LAYER_WORLD | Combat.LAYER_WALLS
	return not scene.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func test_open_ground_is_left_alone() -> void:
	await _load("ashen_pass")
	var spot := Vector3(0.0, 0.2, 6.0)
	assert_eq(Combat.clear_spot(scene.get_world_3d(), spot, scene.island.height_at), spot)


func test_a_spot_inside_a_rock_moves_out() -> void:
	await _load("ashen_pass")
	# The biggest rock stands at (16, -10), scaled 1.8.
	var buried := Vector3(16.0, 0.2, -10.0)
	assert_true(_buried(buried), "the spot is inside the rock to begin with")
	var spot := Combat.clear_spot(scene.get_world_3d(), buried, scene.island.height_at)
	assert_false(_buried(spot), "the new spot is clear")
	assert_true(spot.distance_to(buried) < 6.0, "and close by (%.1f m)" % spot.distance_to(buried))
	assert_near(spot.y, buried.y, 0.5, "on the same ground")


func test_story_spawn_points_are_never_inside_anything() -> void:
	await _load("ashen_pass")
	var director := StoryDirector.new()
	director.player = scene.player
	director.stage = scene
	var bad := 0
	var total := 0
	for id: String in Island.PRESETS:
		scene.use_island(id)
		await physics_frames(3)
		for px in range(-18, 19, 6):
			for pz in range(-18, 19, 6):
				if Vector2(px, pz).length() > 19.0:
					continue
				scene.player.global_position = Vector3(px, 0.2, pz)
				for deg in range(0, 360, 45):
					scene.player.camera_rig.yaw = deg_to_rad(deg)
					for count in [1, 2, 3]:
						for index in count:
							total += 1
							if _buried(director._spawn_point(index, count)):
								bad += 1
	director.free()
	assert_true(total > 500, "enough points were tried (%d)" % total)
	assert_eq(bad, 0, "%d of %d story spawn points were inside something solid" % [bad, total])


func test_trial_spawn_points_are_never_inside_or_on_top_of_anything() -> void:
	await _load("ashen_pass")
	var bad := 0
	var high := 0
	var total := 0
	for id: String in Island.PRESETS:
		scene.use_island(id)
		await physics_frames(3)
		var fight := TrialDirector.new()
		fight.player = scene.player
		fight.ground_at = scene.island.height_at
		scene.add_child(fight)
		for px in range(-18, 19, 6):
			for pz in range(-18, 19, 6):
				if Vector2(px, pz).length() > 19.0:
					continue
				scene.player.global_position = Vector3(px, 0.2, pz)
				for deg in range(0, 360, 45):
					scene.player.camera_rig.yaw = deg_to_rad(deg)
					for count in [1, 2, 3]:
						for index in count:
							total += 1
							var p := fight.spawn_point(index, count)
							if _buried(p):
								bad += 1
							# The clearing is flat: nobody is up on a rock.
							if p.y > 1.0:
								high += 1
		fight.queue_free()
	assert_true(total > 500, "enough points were tried (%d)" % total)
	assert_eq(bad, 0, "%d of %d trial spawn points were inside something solid" % [bad, total])
	assert_eq(high, 0, "%d of %d were up on top of a rock" % [high, total])
