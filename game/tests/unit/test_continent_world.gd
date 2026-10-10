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


func test_the_ground_is_solid_and_dry_at_the_regions() -> void:
	_make()
	# The ground follows whoever walks: stand a marker in two regions in turn.
	var marker := Node3D.new()
	root.add_child(marker)
	world.continent.target = marker
	var space := world.get_world_3d().direct_space_state
	for id: String in ["emberwood", "five_winds"]:
		var c := world.to_global(world.offset(id))
		marker.global_position = c
		await root.get_tree().process_frame
		assert_true(await _until_ground(), "%s: the ground came up" % id)
		var q := PhysicsRayQueryParameters3D.create(c + Vector3(7, 300, 7), c + Vector3(7, -60, 7), Combat.LAYER_WORLD)
		var hit := space.intersect_ray(q)
		assert_false(hit.is_empty(), "%s: ground under the pad" % id)
		assert_near(hit.get("position", Vector3.ZERO).y, c.y, 0.5, "%s: the pad's height" % id)
	marker.free()
	var body := CharacterBody3D.new()
	assert_false(world.on_water(body), "a body that is not standing is not on water")
	body.free()
