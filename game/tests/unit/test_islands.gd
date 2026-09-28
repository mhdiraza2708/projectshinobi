extends TestCase
## Story islands: every chapter has one, the clearing is flat and walkable,
## an invisible wall keeps fights near it, and chapters teleport you in and out.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D


func _load() -> void:
	scene = Scene.instantiate()
	root.add_child(scene)
	await physics_frames(5)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	return scene.get_world_3d().direct_space_state.intersect_ray(q)


func test_every_chapter_names_an_existing_island() -> void:
	var story := Story.load_all()
	assert_true(story.errors.is_empty(), "\n".join(story.errors))
	var used := {}
	for c: Dictionary in story.chapters:
		assert_true(Island.exists(c["island"]), "%s: island %s" % [c["id"], c["island"]])
		used[c["island"]] = true
	assert_true(used.size() >= 6, "the story visits %d islands" % used.size())


func test_every_island_builds_with_a_flat_clearing() -> void:
	for id: String in Island.PRESETS:
		var island := Island.new()
		root.add_child(island)
		island.build(id)
		for p: Vector2 in [Vector2.ZERO, Vector2(15, 0), Vector2(0, -19), Vector2(-13, 13)]:
			assert_near(island.height_at(p.x, p.y), 0.0, 0.001, "%s is flat at %s" % [id, p])
		assert_true(island.height_at(0, 200) < island.water_level, "%s is surrounded by sea" % id)
		for prop: Dictionary in island.preset.get("props", []):
			assert_true(ResourceLoader.exists(Island.MODELS + prop["scene"] + ".gltf"), "%s: %s model" % [id, prop["scene"]])
		assert_true(island.find_children("Scatter_*", "MultiMeshInstance3D", true, false).size() > 0, "%s has trees" % id)
		island.free()


func test_story_chapter_stands_on_its_island() -> void:
	await _load()
	scene.start_story("ch8_dam", true)
	await physics_frames(10)
	assert_true(scene.island != null and scene.island.id == "old_dam")
	assert_true(scene.get_node_or_null("Ground") == null, "the training ground is gone")
	var hit := _ray(Vector3(3, 10, 3), Vector3(3, -10, 3))
	assert_false(hit.is_empty(), "solid ground in the clearing")
	assert_near(hit.get("position", Vector3.ONE).y, 0.0, 0.05)
	var r: float = scene.island.walk_radius()
	var wall := _ray(Vector3(0, 1.5, 0), Vector3(r + 5.0, 1.5, 0))
	assert_false(wall.is_empty(), "an invisible wall stops you leaving the island's middle")
	assert_true(scene.player.global_position.y > -1.0, "the player stands on the island")


func test_night_lights_the_islands_lanterns() -> void:
	await _load()
	scene.start_story("ch4_pass", true)
	await physics_frames(2)
	assert_eq(scene.lantern_lights.size(), scene.island.lanterns.size())
	assert_true(scene.lantern_lights.size() >= 4, "the abandoned shrine's lanterns are lit")


func test_teleport_out_and_back_in() -> void:
	await _load()
	scene.start_story("ch7_wood", true)
	await physics_frames(5)
	scene._teleport_out()
	await seconds(1.7)
	assert_false(scene.player.visible, "gone in a flash")
	assert_true(scene.find_children("*", "TeleportFx", true, false).is_empty(), "the seal is cleaned up")
	scene._teleport_in()
	assert_true(scene.player.visible, "back")
	assert_true(scene.flash_alpha() > 0.5, "arriving starts in a white flash")
	await seconds(1.2)
	assert_true(scene.flash_alpha() < 0.05, "which fades")
