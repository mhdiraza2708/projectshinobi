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
			var mat := Skies.material(env)
			var drawn: Vector3 = mat.get_shader_parameter(&"sun_direction")
			assert_true(toward.dot(drawn) > 0.9999, "%s at yaw %d: the sun is drawn where the light comes from" % [key, yaw])
			var elevation := rad_to_deg(asin(toward.y))
			assert_near(elevation, Skies.elevation_of(key), 0.01, "%s: the light is as high as the look says" % key)
			# The shader's turn really is the inverse, and its lift puts the
			# photo's sun at the light's height: looking at the drawn sun looks
			# at the photo's sun in the panorama.
			var to_pano: Basis = mat.get_shader_parameter(&"to_panorama")
			var elevations: Vector2 = mat.get_shader_parameter(&"elevations")
			var uv: Array = Skies.data()[key]["sun_uv"]
			assert_true((to_pano * Skies.lift(drawn, elevations)).dot(Skies.panorama_direction(Vector2(uv[0], uv[1]))) > 0.9999,
				"%s: the panorama is sampled at its sun" % key)
			sun.free()


func test_the_lift_moves_the_sun_and_nothing_else() -> void:
	var elevations := Vector2(deg_to_rad(12.8), deg_to_rad(8.0))
	var up := Vector3.UP
	assert_true(Skies.lift(up, elevations).dot(up) > 0.99999, "the zenith stays put")
	var level := Vector3(0.6, 0.0, -0.8)
	assert_true(Skies.lift(level, elevations).dot(level) > 0.99999, "and so does the horizon")
	var lifted := Skies.lift(Vector3(0.0, sin(elevations.y), -cos(elevations.y)), elevations)
	assert_near(rad_to_deg(asin(lifted.y)), 12.8, 0.01, "the sun's height becomes the photo's")
	assert_near(lifted.x, 0.0, 0.0001, "the bearing is untouched")
	var same := Vector2(deg_to_rad(40.0), deg_to_rad(40.0))
	var any := Vector3(0.3, 0.5, -0.8).normalized()
	assert_true(Skies.lift(any, same).dot(any) > 0.99999, "equal heights leave the sky as shot")
	# Each height maps to a higher one in the photo, in order (no folding over).
	var last := 0.0
	for deg in range(1, 90, 3):
		var d := Vector3(0.0, sin(deg_to_rad(deg)), -cos(deg_to_rad(deg)))
		var now := asin(Skies.lift(d, elevations).y)
		assert_true(now > last, "the lift keeps the sky in order at %d degrees" % deg)
		last = now


func test_dusk_is_golden_hour() -> void:
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	var day_sun := DirectionalLight3D.new()
	Skies.apply(env, day_sun, "day", 40.0)
	var day_fog := env.fog_light_color
	Skies.apply(env, sun, "dusk", -110.0)
	var c := sun.light_color.srgb_to_linear()
	assert_true(c.r > c.g * 1.3 and c.g > c.b * 1.5, "an amber sun: red over green over blue")
	assert_true(rad_to_deg(-sun.rotation.x) < 10.0 and rad_to_deg(-sun.rotation.x) > 4.0,
		"low enough for long shadows, not on the horizon")
	assert_true(sun.light_energy > day_sun.light_energy * 0.8,
		"stronger light to make up for the glancing angle")
	assert_true(env.fog_light_color.r > env.fog_light_color.b + 0.15, "warm fog")
	assert_true(env.fog_light_color.r - env.fog_light_color.b > day_fog.r - day_fog.b + 0.2, "warmer than the day's")
	var mat := Skies.material(env)
	var low: Vector3 = mat.get_shader_parameter(&"horizon_tint")
	assert_true(low.x > low.z * 3.0, "the sky is warm toward the horizon")
	var high: Vector3 = mat.get_shader_parameter(&"tint")
	assert_true(high.x < low.x and high.z > low.z, "and cooler overhead")
	sun.free()
	day_sun.free()


func test_night_is_moonlit_blue_but_readable() -> void:
	var env := Environment.new()
	var moon := DirectionalLight3D.new()
	Skies.apply(env, moon, "night", 30.0)
	var c := moon.light_color.srgb_to_linear()
	assert_true(c.b > c.g and c.g > c.r * 1.2, "blue moonlight")
	var gain := 1.0 if Graphics.supported() else Skies.COMPATIBILITY_GAIN
	assert_true(moon.light_energy / gain >= 0.6, "bright enough to see the ground by")
	assert_true(env.ambient_light_energy / gain >= 0.9, "the sky's glow still fills the shadows")
	var tint: Vector3 = Skies.material(env).get_shader_parameter(&"tint")
	assert_true(tint.z > tint.y and tint.y > tint.x, "a blue sky")
	assert_true(env.fog_light_color.b > env.fog_light_color.r, "blue mist")
	moon.free()


func test_dawn_is_cool_pink() -> void:
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	Skies.apply(env, sun, "dawn", 70.0)
	var c := sun.light_color.srgb_to_linear()
	assert_true(c.r > c.b and c.b > c.g, "a rose sun: pink, not orange")
	var low: Vector3 = Skies.material(env).get_shader_parameter(&"horizon_tint")
	assert_true(low.x > low.y and low.z > low.y, "pink haze on the horizon")
	var high: Vector3 = Skies.material(env).get_shader_parameter(&"tint")
	assert_true(high.z > high.x, "a cool sky overhead")
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
