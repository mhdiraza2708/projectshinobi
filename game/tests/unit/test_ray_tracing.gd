extends TestCase
## Ray tracing: what goes into the acceleration structure (level meshes as
## they are, characters as capsules, effects and water left out), the
## per-triangle records reflections are lit from, and machines without a
## ray tracing GPU (like this headless run) carrying on as before.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D


func _load() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	await physics_frames(5)


func test_level_meshes_go_in_and_characters_become_capsules() -> void:
	await _load()
	var tracked := RayTracing.collect(scene)
	var nodes := tracked.map(func(t: Array) -> Node: return t[1])
	assert_true(nodes.has(scene.get_node("Ground/GroundMesh")), "the ground")
	assert_true(tracked.any(func(t: Array) -> bool: return t[1] == scene.player and t[2] == -2),
		"the player as a capsule")
	for t: Array in tracked:
		var n: Node = t[1]
		if t[2] == -2:
			continue
		assert_false(scene.player.is_ancestor_of(n), "nothing from inside the player (%s)" % n.name)
		assert_true((n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"effects and water stay out (%s)" % n.name)
	var dummies := scene.find_children("*", "TrainingDummy", true, false)
	assert_true(tracked.any(func(t: Array) -> bool: return dummies[0].is_ancestor_of(t[1])), "the dummies")


func test_island_scatter_goes_in_tree_by_tree() -> void:
	var island := Island.new()
	root.add_child(island)
	island.build("autumn_wood")
	var tracked := RayTracing.collect(island)
	for mmi: MultiMeshInstance3D in island.find_children("Scatter_*", "MultiMeshInstance3D", true, false):
		var count := tracked.filter(func(t: Array) -> bool: return t[1] == mmi).size()
		assert_eq(count, mmi.multimesh.instance_count, "every %s" % mmi.name)
	assert_false(tracked.any(func(t: Array) -> bool: return t[1].name == "Tufts"), "grass tufts are too small to bother")
	island.free()


func test_triangle_records_carry_normals_and_colour() -> void:
	var box := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.1)
	box.material = mat
	var tri := RayTracing.triangles(box)
	var verts: PackedVector3Array = tri[0]
	var idx: PackedInt32Array = tri[1]
	var recs: PackedByteArray = tri[2]
	assert_eq(idx.size(), 36, "12 triangles")
	assert_eq(recs.size(), 12 * 16, "one record each")
	assert_true(Array(idx).max() < verts.size())
	for k in 12:
		var n := Vector3(recs.decode_float(k * 16), recs.decode_float(k * 16 + 4), recs.decode_float(k * 16 + 8))
		assert_near(n.length(), 1.0, 0.001, "unit normal")
		assert_near(absf(n.x) + absf(n.y) + absf(n.z), 1.0, 0.001, "a box's faces are axis-aligned")
		assert_eq(recs.decode_u32(k * 16 + 12), mat.albedo_color.to_abgr32(), "the material's colour")


func test_terrain_reflects_its_palette() -> void:
	var m := TerrainMaterial.make({}, {"grass": Color("5f8f3e"), "dirt": Color("8c6d4b"), "rock": Color("6f6a64"), "sand": Color("d9c89a")})
	var palette: PackedColorArray = m.get_meta(&"rt_palette")
	assert_eq(palette.size(), 4)
	assert_eq(palette[1], Color("8c6d4b"), "dirt")
	var island := Island.new()
	root.add_child(island)
	island.build("emberwood")
	var terrain: MeshInstance3D = island.find_child("Terrain", true, false)
	var recs: PackedByteArray = RayTracing.triangles(terrain.mesh)[2]
	# The very middle of the clearing is dirt (two triangles per grid cell).
	var cells := int(Island.HALF * 2.0 / Island.STEP)
	var mid := 2 * ((cells / 2) * cells + cells / 2)
	var c := Color.hex(0)
	var abgr := recs.decode_u32(mid * 16 + 12)
	c = Color((abgr & 0xff) / 255.0, ((abgr >> 8) & 0xff) / 255.0, ((abgr >> 16) & 0xff) / 255.0)
	var dirt: Color = island.preset["dirt"]
	assert_near(c.r, dirt.r, 0.05, "the clearing reflects as dirt")
	assert_near(c.g, dirt.g, 0.05)
	island.free()


func test_without_a_ray_tracing_gpu_nothing_changes() -> void:
	assert_false(RayTracing.available(), "no ray tracing GPU in a headless run")
	await _load()
	var rt: RayTracing = scene.get_node("RayTracing")
	assert_false(rt.active())
	var env: WorldEnvironment = scene.get_node("WorldEnvironment")
	assert_true(env.compositor == null, "no effect attached")
	assert_true(env.environment.ssao_enabled, "screen-space AO stays on")


func test_the_menu_greys_the_option_out_without_saving_it_off() -> void:
	Settings.set_value(&"ray_tracing", true)
	await _load()
	scene.pause_menu.open()
	await physics_frames(2)
	assert_true(bool(Settings.get_value(&"ray_tracing")), "a save moved to a PC with ray tracing still has it on")
	scene.pause_menu.close()
