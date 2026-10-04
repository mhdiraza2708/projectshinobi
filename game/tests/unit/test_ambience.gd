extends TestCase
## The air around the player (Ambience): each island has its own drifting
## particles, night brings fireflies to every island, the set follows the
## player and fades between islands and hours, the lowest graphics preset
## turns it off, and the game scene feeds it in free roam and on a story
## island alike.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var air: Ambience
var anchor: Node3D


func before_each() -> void:
	Profile.persist = false
	Profile.reset()
	Game.reset_records()
	Settings.reset_values()


# Not a coroutine: the runner starts the next test without waiting.
func after_each() -> void:
	for node in [scene, air, anchor]:
		if is_instance_valid(node):
			node.queue_free()
	Settings.reset_values()
	Game.reset_records()
	Profile.reset()


## An Ambience standing in the tree, following a bare node at `at`.
func _make_air(at := Vector3(10.0, 2.0, 5.0)) -> void:
	anchor = Node3D.new()
	root.add_child(anchor)
	anchor.global_position = at
	air = Ambience.new()
	air.follow = anchor
	root.add_child(air)


## Two frames: the scene hands the air its context from its own _process.
func _frames() -> void:
	await root.get_tree().process_frame
	await root.get_tree().process_frame


func _particles(node: Node) -> Array[CPUParticles3D]:
	var out: Array[CPUParticles3D] = []
	for child in node.get_children():
		if child is CPUParticles3D and not child.is_queued_for_deletion():
			out.append(child)
	return out


func test_each_island_has_its_own_air() -> void:
	assert_eq(Ambience.kinds("ashen_pass", "day"), PackedStringArray(["embers", "ash"]))
	assert_eq(Ambience.kinds("autumn_wood", "day"), PackedStringArray(["leaves"]))
	assert_eq(Ambience.kinds("frozen_road", "day"), PackedStringArray(["snow"]))
	assert_eq(Ambience.kinds("old_dam", "day"), PackedStringArray(["mist"]))
	assert_eq(Ambience.kinds("five_winds", "day"), PackedStringArray(["wind"]))
	assert_eq(Ambience.kinds("emberwood", "day"), PackedStringArray(["pollen", "petals"]))
	assert_eq(Ambience.kinds("emberwood", "dusk"), PackedStringArray(["pollen", "petals"]), "pollen glows at golden hour")
	assert_true(Ambience.kinds("", "day").is_empty(), "nothing out at sea")
	assert_true(Ambience.kinds("no_such_island", "night").is_empty())
	for id: String in Ambience.SETS:
		assert_true(Island.exists(id), "%s is an island" % id)


func test_night_brings_fireflies_to_every_island() -> void:
	for id: String in Island.PRESETS:
		var night := Ambience.kinds(id, "night")
		assert_true(night.has("fireflies"), "%s has fireflies at night" % id)
		assert_false(night.has("pollen") or night.has("petals"), "%s: pollen is for the day" % id)
		assert_false(Ambience.kinds(id, "day").has("fireflies"), "%s: no fireflies by day" % id)
	assert_eq(Ambience.kinds("emberwood", "night"), PackedStringArray(["fireflies"]))
	assert_eq(Ambience.kinds("ashen_pass", "night"), PackedStringArray(["embers", "fireflies"]))


func test_it_never_runs_more_than_two_emitters() -> void:
	for id: String in Island.PRESETS:
		for time in ["dawn", "day", "dusk", "night"]:
			for weather in ["none", "rain", "storm", "snow", "leaves"]:
				assert_true(Ambience.kinds(id, time, weather).size() <= 2, "%s %s %s" % [id, time, weather])


func test_weather_that_brings_the_same_particles_stands_in_for_them() -> void:
	assert_true(Ambience.kinds("frozen_road", "day", "snow").is_empty(), "the snow weather is the snow")
	assert_true(Ambience.kinds("autumn_wood", "day", "leaves").is_empty(), "the leaves weather is the leaves")
	assert_eq(Ambience.kinds("ashen_pass", "day", "snow"), PackedStringArray(["embers", "ash"]), "embers don't mind snow")
	assert_false(Ambience.kinds("old_dam", "night", "snow").has("fireflies"), "no fireflies in the snow")
	for id: String in Island.PRESETS:
		assert_true(Ambience.kinds(id, "night", "storm").is_empty(), "%s: a storm has its own rain" % id)
		assert_true(Ambience.kinds(id, "day", "rain").is_empty())


func test_the_air_changes_with_the_island_and_the_hour_and_fades() -> void:
	_make_air()
	air.set_context("autumn_wood", "day")
	assert_eq(air.active(), PackedStringArray(["leaves"]))
	var leaves := air.emitter("leaves")
	assert_true(leaves != null and leaves.emitting, "falling leaves")
	assert_true(leaves.amount <= 120, "a light touch: %d particles" % leaves.amount)
	assert_true(leaves.preprocess > 0.0, "the air is already full when it appears")
	air.settle()
	# A new island: the leaves go and the snow comes, over a second or two.
	air.set_context("frozen_road", "day")
	assert_eq(air.active(), PackedStringArray(["snow"]))
	await seconds(0.3)
	assert_eq(_particles(air).size(), 2, "the leaves are still fading out")
	await seconds(Ambience.FADE + 0.6)
	assert_eq(_particles(air).size(), 1, "and then gone")
	# Night: the island's air and the fireflies, no more.
	air.set_context("frozen_road", "night")
	assert_eq(air.active(), PackedStringArray(["snow", "fireflies"]))
	air.settle()
	assert_eq(_particles(air).size(), 2)
	var total := 0
	for p in _particles(air):
		total += p.amount
	assert_true(total <= 400, "at most a few hundred particles in all: %d" % total)
	# Back to sea: it all fades away.
	air.set_context("", "night")
	assert_true(air.active().is_empty())
	air.settle()
	assert_eq(_particles(air).size(), 0)


func test_coming_back_before_the_set_has_gone_brings_it_back() -> void:
	_make_air()
	air.set_context("old_dam", "day")
	var mist := air.emitter("mist")
	air.set_context("", "day")
	assert_true(air.emitter("mist") == null)
	air.set_context("old_dam", "day")
	assert_true(air.emitter("mist") == mist, "the same mist fades back in")
	assert_eq(_particles(air).size(), 1)


func test_the_air_follows_the_player() -> void:
	_make_air(Vector3(10.0, 2.0, 5.0))
	air.set_context("ashen_pass", "day")
	await physics_frames(2)
	await root.get_tree().process_frame
	assert_near(air.global_position.x, 10.0, 0.5)
	assert_near(air.global_position.z, 5.0, 0.5)
	# Running: the box moves with them, leading a little.
	for i in 20:
		anchor.global_position += Vector3(0.2, 0.0, 0.0)
		await root.get_tree().process_frame
	assert_true(air.global_position.x > anchor.global_position.x - 1.0, "it keeps up")
	assert_true(air.global_position.x - anchor.global_position.x <= Ambience.RADIUS, "and leads at most a little")
	# A jump (teleport, respawn): the old particles are left behind and a new set starts.
	var before := air.emitter("embers")
	anchor.global_position = Vector3(500.0, 3.0, -300.0)
	await root.get_tree().process_frame
	assert_near(air.global_position.x, 500.0, 0.5)
	assert_near(air.global_position.z, -300.0, 0.5)
	assert_true(air.emitter("embers") != before, "the air starts over around the player")
	assert_eq(air.active(), PackedStringArray(["embers", "ash"]))


func test_the_lowest_preset_has_none_and_lighter_ones_have_fewer() -> void:
	_make_air()
	Graphics.apply_preset("high")
	assert_near(Ambience.density(), 1.0, 0.001)
	air.set_context("autumn_wood", "day")
	var full := air.emitter("leaves").amount
	Graphics.apply_preset("medium")
	assert_true(Ambience.density() < 1.0 and Ambience.density() > 0.0)
	air.set_context("autumn_wood", "day")
	air.settle()
	assert_true(air.emitter("leaves").amount < full, "the plainer lighting gets fewer leaves")
	Graphics.apply_preset("low")
	assert_eq(Ambience.density(), 0.0)
	# The setting itself reaches it even though nothing else changed.
	air.set_context("autumn_wood", "day")
	assert_true(air.active().is_empty(), "nothing at all on the lowest")
	air.settle()
	assert_eq(_particles(air).size(), 0)
	Graphics.apply_preset("ultra")
	air.set_context("autumn_wood", "day")
	assert_eq(air.active(), PackedStringArray(["leaves"]), "and back when the setting rises")


func test_a_story_island_has_its_air_by_the_chapters_hour() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	await physics_frames(2)
	assert_true(scene.ambience.active().is_empty(), "the training ground has none")
	scene.use_island("autumn_wood")
	scene.set_time_of_day("dusk")
	await _frames()
	assert_eq(scene.ambient_island(), "autumn_wood")
	assert_eq(scene.ambience.active(), PackedStringArray(["leaves"]))
	scene.set_time_of_day("night")
	await _frames()
	assert_eq(scene.ambience.active(), PackedStringArray(["leaves", "fireflies"]))
	# Weather that brings its own leaves takes their place.
	scene.set_weather("leaves")
	await _frames()
	assert_eq(scene.ambience.active(), PackedStringArray(["fireflies"]))
	scene.set_weather("none")


func test_free_roam_gives_each_island_its_air() -> void:
	Game.start_mode = Game.Mode.TITLE
	scene = Scene.instantiate()
	root.add_child(scene)
	await physics_frames(2)
	scene.instant_world = true
	await scene.start_world()
	var world: OpenWorld = scene.world
	await physics_frames(3)
	await _frames()
	assert_eq(scene.ambient_island(), "emberwood")
	assert_eq(scene.ambience.active(), PackedStringArray(["pollen", "petals"]), "a new game starts by day in Emberwood")
	scene.player.global_position = world.archipelago.on_island("ashen_pass", Vector2(0, 10)) + Vector3.UP * 0.3
	scene.player.velocity = Vector3.ZERO
	await physics_frames(3)
	await _frames()
	assert_eq(scene.ambient_island(), "ashen_pass")
	assert_eq(scene.ambience.active(), PackedStringArray(["embers", "ash"]))
	# The day turns to night: fireflies come out.
	scene.transition_time("night", 0.0)
	await _frames()
	assert_eq(scene.ambience.active(), PackedStringArray(["embers", "fireflies"]))
	# Out on the open sea there is nothing.
	scene.player.global_position = world.archipelago.to_global(Vector3(220.0, Archipelago.SEA_LEVEL + 1.0, -90.0))
	scene.player.velocity = Vector3.ZERO
	await physics_frames(3)
	await _frames()
	assert_eq(scene.ambient_island(), "")
	assert_true(scene.ambience.active().is_empty())
