extends TestCase
## The open world on the continent (ContinentWorld): the same regions, props
## and ways of working as the sea of islands, standing on the streamed land.

var world: ContinentWorld


func after_each() -> void:
	if is_instance_valid(world):
		world.queue_free()


func _make() -> ContinentWorld:
	world = ContinentWorld.new()
	root.add_child(world)
	world.build_now()
	return world


## Waits (in frames) until the streamer has built everything it wants.
func _until_ground(limit_seconds := 90.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit_seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if world.continent.streamer != null and world.continent.streamer.is_complete():
			return true
		await root.get_tree().process_frame
	return false


func _walkable(island: Island, p: Vector2) -> bool:
	return island.height_at(p.x, p.y) > island.water_level + 0.8 and island._slope(p.x, p.y) < 0.2


func test_regions_stand_where_the_land_puts_them() -> void:
	_make()
	var layout := world.layout()
	assert_eq(layout.size(), Archipelago.LAYOUT.size(), "every region")
	for id: String in Archipelago.LAYOUT:
		assert_true(layout.has(id), id)
		var c := world.continent.land.region_center(id)
		var at := world.offset(id)
		assert_near(at.x, c.x, 0.001, "%s x" % id)
		assert_near(at.z, c.y, 0.001, "%s z" % id)
		assert_near(at.y, world.continent.land.pad_height(id), 0.001, "%s stands on its pad" % id)
		assert_true(world.islands.has(id), "%s is built" % id)


func test_every_region_keeps_its_authored_props() -> void:
	_make()
	for id: String in Archipelago.LAYOUT:
		var island: Island = world.islands[id]
		var props: Array = Island.PRESETS[id].get("props", [])
		assert_true(props.size() > 0, "%s has props" % id)
		for prop: Dictionary in props:
			var node_name := String(prop["scene"]).capitalize().replace(" ", "")
			assert_true(island.find_child(node_name, true, false) != null, "%s: %s" % [id, node_name])
		# The continent supplies the ground, sea and trees.
		assert_true(island.find_children("Scatter_*", "MultiMeshInstance3D", true, false).is_empty(), "%s adds no trees of its own" % id)
		assert_true(island.water_level < 0.0 or id == "five_winds", "%s sea level" % id)


func test_a_region_is_flat_where_its_clearing_is() -> void:
	_make()
	for id: String in Archipelago.LAYOUT:
		var island: Island = world.islands[id]
		for p: Vector2 in [Vector2.ZERO, Vector2(15, 0), Vector2(0, -19), Vector2(-13, 13)]:
			assert_near(island.height_at(p.x, p.y), 0.0, 0.01, "%s is flat at %s" % [id, p])


func test_every_quest_spot_is_walkable() -> void:
	_make()
	var bad: Array[String] = []
	for q: Dictionary in Quests.all():
		var spots: Array = []
		spots.append([str(q["island"]), q["giver_at"]])
		if q.has("at"):
			spots.append([str(q["island"]), q["at"]])
		if q.has("to_at"):
			spots.append([str(q.get("to_island", q["island"])), q["to_at"]])
		for s: Array in spots:
			var island: Island = world.islands[s[0]]
			var p := Vector2(float(s[1][0]), float(s[1][1]))
			if not _walkable(island, p):
				bad.append("%s at %s on %s (h %.2f, slope %.2f)" % [q["id"], p, s[0], island.height_at(p.x, p.y), island._slope(p.x, p.y)])
	assert_true(bad.is_empty(), "\n".join(bad))


func test_gather_ground_round_each_region_is_mostly_walkable() -> void:
	# Gather quests scatter their items on dry, gentle ground between the
	# clearing and the coast: there has to be enough of it.
	_make()
	for id: String in Archipelago.LAYOUT:
		var island: Island = world.islands[id]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(id)
		var ok := 0
		var tries := 200
		for i in tries:
			var r := rng.randf_range(float(island.preset["clearing"]) + 4.0, float(island.preset["coast"]) - 14.0)
			var a := rng.randf() * TAU
			if _walkable(island, Vector2(cos(a) * r, sin(a) * r)):
				ok += 1
		assert_true(ok >= 20, "%s: %d of %d gather points are walkable" % [id, ok, tries])


func test_island_near_names_the_region_you_are_in() -> void:
	_make()
	for id: String in Archipelago.LAYOUT:
		assert_eq(world.island_near(world.to_global(world.offset(id))), id, "%s centre" % id)
		var edge := world.offset(id) + Vector3(ContinentLand.REGION_RADIUS * 0.5, 0, 0)
		assert_eq(world.island_near(world.to_global(edge)), id, "%s inside" % id)
	assert_eq(world.island_near(Vector3(-1900, 0, -1900)), "", "open sea is no region")


func test_focus_on_puts_the_region_at_the_origin() -> void:
	_make()
	var seen := {"delta": Vector3.ZERO}
	world.rebased.connect(func(d: Vector3) -> void: seen["delta"] = d)
	var delta := world.focus_on("old_dam")
	assert_true(delta.length() > 100.0, "the world moved")
	assert_eq(seen["delta"], delta, "rebased says how far")
	var pad := world.to_global(world.offset("old_dam"))
	assert_near(pad.x, 0.0, 0.001, "pad x")
	assert_near(pad.z, 0.0, 0.001, "pad z")
	assert_eq(world.island_near(Vector3.ZERO), "old_dam", "you are in the dam region")
	# Moving back and forth is exact.
	world.focus_on("emberwood")
	var ember := world.to_global(world.offset("emberwood"))
	assert_near(ember.length(), 0.0, 0.001, "emberwood at the origin")


func test_on_island_stands_on_the_ground() -> void:
	_make()
	var here := world.on_island("ashen_pass", Vector2(0, -24))
	var pad := world.to_global(world.offset("ashen_pass"))
	assert_near(here.y, pad.y, 0.05, "the gate stands on the pad")
	assert_near(here.z, pad.z - 24.0, 0.01)


func test_the_ground_comes_up_where_asked_and_then_follows_the_player() -> void:
	# The player starts somewhere else (the scene's origin): the ground must
	# come up where the world will place them, not under them.
	var marker := Node3D.new()
	root.add_child(marker)
	world = ContinentWorld.new()
	world.player = marker
	root.add_child(world)
	world.build_now(world.offset("five_winds"))
	await world.ground_ready()
	var space := world.get_world_3d().direct_space_state
	var c := world.to_global(world.offset("five_winds"))
	var q := PhysicsRayQueryParameters3D.create(c + Vector3(7, 300, 7), c + Vector3(7, -60, 7), Combat.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	assert_false(hit.is_empty(), "ground under Five Winds' pad")
	assert_near(hit.get("position", Vector3.ZERO).y, c.y, 0.5, "at the pad's height")
	assert_eq(world.continent.target, null, "it waits for the player to be placed")
	world.follow_player()
	assert_eq(world.continent.target, marker, "then follows them")
	# And follows them: walk to Emberwood.
	c = world.to_global(world.offset("emberwood"))
	marker.global_position = c
	await root.get_tree().process_frame
	assert_true(await _until_ground(), "the ground came up at Emberwood")
	q = PhysicsRayQueryParameters3D.create(c + Vector3(7, 300, 7), c + Vector3(7, -60, 7), Combat.LAYER_WORLD)
	hit = space.intersect_ray(q)
	assert_false(hit.is_empty(), "ground under Emberwood's pad")
	assert_near(hit.get("position", Vector3.ZERO).y, c.y, 0.5, "at the pad's height")
	marker.free()
	var body := CharacterBody3D.new()
	assert_false(world.on_water(body), "a body that is not standing is not on water")
	body.free()


func test_the_chart_draws_the_land_rivers_and_roads() -> void:
	_make()
	var img := WorldMap.chart(world).get_image()
	var b := WorldMap.CONTINENT_BOUNDS
	var step := WorldMap.CONTINENT_METRES_PER_PIXEL
	assert_eq(img.get_width(), int(b.size.x / step), "the chart's width")
	var land := world.continent.land
	var wet := 0
	var dry := 0
	for z in range(-1800, 1800, 90):
		for x in range(-1700, 1700, 90):
			var drawn := img.get_pixelv(Vector2i((Vector2(x, z) - b.position) / step)).a > 0.5
			if land.height_at(x, z) > ContinentLand.SEA_LEVEL + 3.0:
				dry += 1
				assert_true(drawn, "land at %d, %d is drawn" % [x, z])
			elif land.height_at(x, z) < ContinentLand.SEA_LEVEL - 3.0:
				wet += 1
				assert_false(drawn, "sea at %d, %d is paper" % [x, z])
	assert_true(dry > 100 and wet > 100, "both land and sea sampled (%d, %d)" % [dry, wet])
	# A road is inked over the land.
	var road: Dictionary = land.roads.paths[0]
	var mid: Vector2 = (road["points"] as PackedVector2Array)[(road["points"] as PackedVector2Array).size() / 2]
	var px := img.get_pixelv(Vector2i((mid - b.position) / step))
	assert_true(px.r > px.b, "the road is brown ink (%s)" % px)
