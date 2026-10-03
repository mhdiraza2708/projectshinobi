extends TestCase
## Photographed skies (Skies) and the scanned ground (TerrainMaterial): every
## time of day has its sky, the game's sun lines up with the sun in the
## photo, weather picks a grey sky without stacking up, and the terrain
## uses the scanned layers at their real sizes.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node


func after_each() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await physics_frames(2)


func test_every_time_of_day_has_a_photographed_sky() -> void:
	for key in ["dawn", "day", "dusk", "night", "overcast", "snow"]:
		assert_true(Skies.has_sky(key), key)
		var s: Dictionary = Skies.data()[key]
		for field in ["scale", "sun_uv", "sun_elevation", "sun_color", "horizon", "ambient"]:
			assert_true(s.has(field), "%s has %s" % [key, field])
		assert_true(float(s["scale"]) > 0.0, "%s has a light level" % key)


func test_weather_picks_the_sky() -> void:
	assert_eq(Skies.key_for("day", "none"), "day")
	assert_eq(Skies.key_for("dawn", "rain"), "overcast")
	assert_eq(Skies.key_for("dusk", "storm"), "overcast")
	assert_eq(Skies.key_for("day", "snow"), "snow")
	assert_eq(Skies.key_for("night", "storm"), "night", "a storm at night stays a night sky")
	assert_eq(Skies.key_for("day", "leaves"), "day")


func test_turning_the_panorama_brings_its_sun_to_the_light() -> void:
	for yaw in [-110.0, 0.0, 30.0, 40.0, 70.0, 175.0]:
		for key in ["day", "dawn", "dusk", "night"]:
			var env := Environment.new()
			var sun := DirectionalLight3D.new()
			Skies.apply(env, sun, key, yaw)
			var toward := Basis.from_euler(sun.rotation).z
			var drawn: Vector3 = Skies.material(env).get_shader_parameter(&"sun_direction")
			var a := Vector2(toward.x, toward.z).normalized()
			var b := Vector2(drawn.x, drawn.z).normalized()
			assert_true(a.dot(b) > 0.9999, "%s at yaw %d: the photo's sun has the light's bearing" % [key, yaw])
			var elevation := rad_to_deg(asin(toward.y))
			var photo := maxf(float(Skies.data()[key]["sun_elevation"]), Skies.MIN_ELEVATION)
			assert_near(elevation, photo, 0.01, "%s: the light is as high as the photo's sun" % key)
			# And the shader's turn really is the inverse: looking at the drawn
			# sun looks at the photo's sun in the panorama.
			var to_pano: Basis = Skies.material(env).get_shader_parameter(&"to_panorama")
			var uv: Array = Skies.data()[key]["sun_uv"]
			assert_true((to_pano * drawn).dot(Skies.panorama_direction(Vector2(uv[0], uv[1]))) > 0.9999,
				"%s: the panorama is sampled at its sun" % key)
			sun.free()


func test_weather_relights_from_scratch() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	await physics_frames(3)
	var env: Environment = scene.get_node("WorldEnvironment").environment
	var sun: DirectionalLight3D = scene.get_node("Sun")
	var clear_fog := env.fog_density
	scene.set_weather("rain")
	var energy := sun.light_energy
	var fog := env.fog_density
	scene.set_weather("rain")
	assert_near(sun.light_energy, energy, 0.0001, "rain twice is no darker than once")
	assert_near(env.fog_density, fog, 0.0001)
	assert_near(fog, clear_fog * 4.0, 0.0001, "rain thickens the fog")
	assert_eq(Skies.material(env).get_shader_parameter(&"panorama").resource_path, Skies.DIR + "overcast.jpg")
	scene.set_weather("none")
	assert_near(env.fog_density, clear_fog, 0.0001, "clearing up thins it again")
	assert_eq(Skies.material(env).get_shader_parameter(&"panorama").resource_path, Skies.DIR + "day.jpg")
	scene.set_weather("none")


func test_terrain_uses_the_scanned_ground_at_real_size() -> void:
	var m := TerrainMaterial.make({}, {"grass": Color("4f6a2e")})
	var grass: Texture2D = m.get_shader_parameter(&"grass_albedo")
	assert_eq(grass.resource_path, TerrainMaterial.GROUND + "grass_albedo.jpg")
	var tiles: Vector4 = m.get_shader_parameter(&"tile_sizes")
	assert_near(tiles.x, 2.0, 0.01, "the grass scan covers two metres")
	assert_near(tiles.y, 3.15, 0.01, "the dirt scan covers 3.15 metres")
	var snowy := TerrainMaterial.make({"grass": "snow"})
	assert_eq((snowy.get_shader_parameter(&"grass_albedo") as Texture2D).resource_path,
		TerrainMaterial.GROUND + "snow_albedo.jpg", "a snowy island's ground is the snow scan")
