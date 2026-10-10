extends TestCase
## The continent prototype (Continent and the files beside it): a seeded
## landmass with flat region pads, roads, rivers and mountains, streamed as
## chunks of several levels of detail with collision near you.

## A character that walks across the continent on its physics.
class Walker extends CharacterBody3D:
	var heading := Vector3.FORWARD
	var speed := 8.0

	func _physics_process(delta: float) -> void:
		velocity.x = heading.x * speed
		velocity.z = heading.z * speed
		velocity.y -= 24.0 * delta
		move_and_slide()


var continent: Continent


func after_each() -> void:
	if is_instance_valid(continent):
		continent.queue_free()


func _make() -> Continent:
	continent = Continent.new()
	root.add_child(continent)
	return continent


## Waits (in frames) until the streamer has built everything it wants.
func _until_complete(limit_seconds := 90.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit_seconds * 1000.0)
	while not continent.streamer.is_complete() and Time.get_ticks_msec() < end:
		await root.get_tree().process_frame
	return continent.streamer.is_complete()


func _ray_down(at: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 400.0, at + Vector3.DOWN * 40.0, Combat.LAYER_WORLD)
	return continent.get_world_3d().direct_space_state.intersect_ray(q)


func test_the_land_is_the_same_every_time() -> void:
	var a := ContinentLand.new()
	var b := ContinentLand.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 300:
		var x := rng.randf_range(-ContinentLand.HALF, ContinentLand.HALF)
		var z := rng.randf_range(-ContinentLand.HALF, ContinentLand.HALF)
		assert_eq(a.height_at(x, z), b.height_at(x, z), "height at %.0f, %.0f" % [x, z])
	assert_eq(a.roads.total_length(), b.roads.total_length(), "same roads")
	assert_eq(a.rivers.total_length(), b.rivers.total_length(), "same rivers")


func test_land_in_the_middle_sea_all_round() -> void:
	var land := ContinentLand.new()
	assert_true(land.height_at(0.0, 0.0) > 3.0, "dry land in the middle")
	for p: Vector2 in [Vector2(-2040, -2040), Vector2(2040, 2040), Vector2(2040, -2040), Vector2(-2040, 2040),
			Vector2(0, 2040), Vector2(0, -2040), Vector2(2040, 0), Vector2(-2040, 0)]:
		assert_true(land.height_at(p.x, p.y) < ContinentLand.SEA_LEVEL - 5.0, "deep sea at the edge %s" % p)
	var peak := -INF
	for z in range(-2000, -600, 40):
		for x in range(-1600, 1600, 40):
			peak = maxf(peak, land.height_at(x, z))
	assert_true(peak > 200.0, "mountains in the north (peak %.0f m)" % peak)
	for z in range(1000, 1800, 40):
		for x in range(-1000, 1000, 40):
			assert_true(land.height_at(x, z) < 120.0, "the south is gentle")


func test_every_region_has_a_flat_walkable_pad() -> void:
	_make()
	var land := continent.land
	for id: String in Archipelago.LAYOUT:
		var c := land.region_center(id)
		var pad := land.pad_height(id)
		assert_true(pad >= ContinentLand.SEA_LEVEL + ContinentLand.MIN_PAD_HEIGHT, "%s is above the sea" % id)
		for k in 16:
			var a := TAU * k / 16.0
			for r: float in [0.0, 12.0, 25.0, ContinentLand.PAD_FLAT - 2.0]:
				assert_near(land.height_at(c.x + cos(a) * r, c.y + sin(a) * r), pad, 0.001, "%s pad at r=%.0f" % [id, r])
		assert_near(continent.region_center(id).y, pad, 0.001)
		assert_eq(land.region_at(c.x, c.y), id)
		assert_eq(land.region_at(c.x + 100.0, c.y - 100.0), id, "a region reaches past its pad")
		assert_true(land.roads.query(c.x, c.y).x < 3.0, "a road reaches %s" % id)
		# The regions are spread out, as Archipelago.LAYOUT scaled up.
		var scaled: Vector2 = Archipelago.LAYOUT[id] * ContinentLand.REGION_SCALE + ContinentLand.REGION_ORIGIN
		assert_eq(c, scaled)
	assert_eq(land.region_at(-1500.0, -1500.0), "", "the wilds belong to no region")
	assert_true(land.region_center("emberwood").y > land.region_center("five_winds").y, "Emberwood is south of Five Winds")


func test_roads_are_flatter_than_their_surroundings() -> void:
	var land := ContinentLand.new()
	assert_true(land.roads.paths.size() >= land.regions.size() - 1, "a network joining every region")
	var on_road := 0.0
	var beside := 0.0
	var count := 0
	for path in land.roads.paths:
		var pts: PackedVector2Array = path["points"]
		for i in range(4, pts.size() - 4, 3):
			var dir := (pts[i + 1] - pts[i - 1]).normalized()
			var side := dir.orthogonal()
			# Across the road, then the same far from it.
			var here := pts[i]
			var away := pts[i] + side * 45.0
			on_road += absf(land.height_at(here.x + side.x * 2.0, here.y + side.y * 2.0) - land.height_at(here.x - side.x * 2.0, here.y - side.y * 2.0))
			beside += absf(land.height_at(away.x + side.x * 2.0, away.y + side.y * 2.0) - land.height_at(away.x - side.x * 2.0, away.y - side.y * 2.0))
			count += 1
	on_road /= count
	beside /= count
	assert_true(on_road < 0.1, "a road is level across (%.3f m over 4 m)" % on_road)
	assert_true(on_road < beside * 0.5, "flatter than the ground beside it (%.3f vs %.3f)" % [on_road, beside])
	# And the material shows dirt there.
	var mid: Vector2 = (land.roads.paths[0]["points"] as PackedVector2Array)[20]
	assert_eq(land.surface_at(mid.x, mid.y), &"dirt", "roads are dirt")


func test_rivers_run_in_flat_beds_below_the_banks() -> void:
	var land := ContinentLand.new()
	assert_true(land.rivers.paths.size() >= 2, "two or more rivers")
	var sampled := 0
	var hanging := 0
	for path in land.rivers.paths:
		var pts: PackedVector2Array = path["points"]
		var beds: PackedFloat32Array = path["heights"]
		for i in range(2, pts.size() - 2, 5):
			var here := pts[i]
			var side := (pts[i + 1] - pts[i - 1]).normalized().orthogonal()
			var reach: float = ContinentLand.RIVER_HALF_WIDTH.y + ContinentLand.RIVER_BANK
			var bank := land.height_at(here.x + side.x * reach, here.y + side.y * reach)
			var other := land.height_at(here.x - side.x * reach, here.y - side.y * reach)
			sampled += 1
			# A stretch on a steep hillside may have one low bank; most don't.
			if minf(bank, other) < beds[i] + 0.4:
				hanging += 1
			assert_true(land.water_level_at(here.x, here.y) > beds[i], "there is water over the bed")
			if land.roads.query(here.x, here.y).x < 16.0:
				continue
			assert_near(land.height_at(here.x, here.y), beds[i], 0.35, "the bed follows the river")
			if i > 6:
				assert_true(beds[i] <= beds[i - 5] + 0.001, "water only runs downhill")
		assert_true(beds[beds.size() - 1] < ContinentLand.SEA_LEVEL + 0.2, "it reaches the sea")
	assert_true(hanging <= sampled / 8, "rivers run in valleys: %d of %d stretches have a low bank" % [hanging, sampled])
	assert_eq(land.surface_at(land.rivers.paths[0]["points"][10].x, land.rivers.paths[0]["points"][10].y), &"water")


func test_chunks_meet_across_their_borders() -> void:
	var land := ContinentLand.new()
	var n := ContinentMesh.QUADS + 1
	# Neighbours at the same level: the shared edge is the same ground.
	for at: Vector2 in [Vector2(-640.0, 704.0), Vector2(256.0, -1088.0), Vector2(1216.0, -448.0), Vector2(-64.0, 1280.0)]:
		var left := ContinentMesh.build(land, Rect2(at, Vector2(64, 64)))
		var right := ContinentMesh.build(land, Rect2(at + Vector2(64, 0), Vector2(64, 64)))
		var below := ContinentMesh.build(land, Rect2(at + Vector2(0, 64), Vector2(64, 64)))
		var hl: PackedFloat32Array = left["heights"]
		var hr: PackedFloat32Array = right["heights"]
		var hb: PackedFloat32Array = below["heights"]
		for k in n:
			assert_near(hl[k * n + (n - 1)], hr[k * n], 0.001, "east border at %s" % at)
			assert_near(hl[(n - 1) * n + k], hb[k], 0.001, "south border at %s" % at)
	# A coarse chunk's edge is the true ground (the skirt covers the rest).
	var big := Rect2(Vector2(-512.0, -1280.0), Vector2(512, 512))
	var mesh := ContinentMesh.build(land, big)
	var hs: PackedFloat32Array = mesh["heights"]
	for k in n:
		var x := big.position.x + big.size.x * k / ContinentMesh.QUADS
		assert_near(hs[k], land.height_at(x, big.position.y), 0.001, "coarse north edge")
	# Heights are continuous either side of every chunk size's borders.
	for level in 7:
		var size := 64.0 * pow(2.0, level)
		for k in 6:
			var x := -ContinentLand.HALF + size * (k + 1)
			var z := -300.0 + k * 90.0
			assert_true(absf(land.height_at(x - 0.01, z) - land.height_at(x + 0.01, z)) < 0.05, "no step at x=%.0f (level %d)" % [x, level])


func test_scatter_is_deterministic_and_keeps_clear() -> void:
	var land := ContinentLand.new()
	ContinentScatter.warm()
	var rect := Rect2(Vector2(-256.0, 960.0), Vector2(256, 256))
	var a := ContinentScatter.instances(land, rect)
	var b := ContinentScatter.instances(land, rect)
	var total := 0
	for model: String in a:
		assert_eq(a[model], b[model], "%s scatter repeats" % model)
		total += (a[model] as PackedFloat32Array).size() / 5
	assert_true(total > 100, "woods (%d)" % total)
	var half := ContinentScatter.instances(land, rect, 2)
	var half_total := 0
	for model: String in half:
		half_total += (half[model] as PackedFloat32Array).size() / 5
	assert_true(half_total < total and half_total > total / 4, "a coarser chunk takes fewer (%d of %d)" % [half_total, total])
	# Nothing grows on a road, in a river or on a region's pad.
	var near_pad := Rect2(land.region_center("emberwood") - Vector2(100, 100), Vector2(200, 200))
	for model: String in ContinentScatter.instances(land, near_pad):
		var list: PackedFloat32Array = ContinentScatter.instances(land, near_pad)[model]
		for i in list.size() / 5:
			var p := Vector2(list[i * 5], list[i * 5 + 2])
			assert_true(p.distance_to(land.region_center("emberwood")) > ContinentScatter.CLEAR_RADIUS.x, "%s off the pad" % model)
			assert_true(land.roads.query(p.x, p.y).x >= 3.5, "%s off the road" % model)


func test_surface_and_region_names() -> void:
	_make()
	var land := continent.land
	var high := 0
	var white := 0
	for z in range(-2000, -700, 20):
		for x in range(-1600, 1600, 20):
			var h := land.height_at(x, z)
			if h > ContinentLand.SNOW_LINE + 90.0:
				high += 1
				if continent.surface_at(Vector3(x, h, z)) == &"snow":
					white += 1
	assert_true(high > 50 and white > high / 4, "the high north is snowy (%d of %d high spots)" % [white, high])
	assert_eq(continent.surface_at(Vector3(-2000.0, 0.0, 0.0)), &"water", "open sea")
	var c := continent.region_center("old_dam")
	assert_eq(continent.region_at(c), "old_dam")
	assert_true(continent.surface_at(c) in [&"dirt", &"grass"], "the yard is packed earth or grass")
	assert_true(continent.surface_at(continent.region_center("emberwood") + Vector3(0, 0, 150.0)) in [&"grass", &"dirt", &"sand"])


func test_chunks_stream_in_and_out_as_the_target_moves() -> void:
	_make()
	var player := Node3D.new()
	root.add_child(player)
	var home := continent.land.region_center("emberwood")
	player.position = Vector3(home.x, continent.land.pad_height("emberwood") + 1.0, home.y)
	continent.target = player
	await continent.start(player.position)
	assert_true(continent.streamer.is_ready(home, 90.0), "the ground round the start is built")
	var first := continent.stats()
	assert_true(int(first["chunks"]) >= 8, "chunks stream in (%s)" % first)
	var level0 := ContinentStreamer.rect_of(Vector3i(0, int((home.x + ContinentLand.HALF) / 64.0), int((home.y + ContinentLand.HALF) / 64.0)))
	assert_true(continent.streamer.has_chunk(Vector3i(0, int((home.x + ContinentLand.HALF) / 64.0), int((home.y + ContinentLand.HALF) / 64.0))), "the finest chunk is under the player (%s)" % level0)
	await _until_complete()
	var near_levels: Dictionary = continent.stats()["levels"]
	assert_true(near_levels.has(0) and near_levels.has(3), "fine near, coarse far: %s" % near_levels)
	# What is shown tiles the land: no overlaps.
	var rects := continent.streamer.shown_rects()
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			assert_false(rects[i].grow(-0.01).intersects(rects[j].grow(-0.01)), "chunks %s and %s overlap" % [rects[i], rects[j]])
	# Run a long way: the old fine chunks go, new ones come.
	var far := continent.land.region_center("autumn_wood")
	player.position = Vector3(far.x, continent.land.pad_height("autumn_wood") + 1.0, far.y)
	var old_key := Vector3i(0, int((home.x + ContinentLand.HALF) / 64.0), int((home.y + ContinentLand.HALF) / 64.0))
	await seconds(0.4)
	assert_true(await _until_complete(), "the new area finishes loading")
	await seconds(0.3)
	assert_false(continent.streamer.has_chunk(old_key), "the finest chunks left behind are unloaded")
	var new_key := Vector3i(0, int((far.x + ContinentLand.HALF) / 64.0), int((far.y + ContinentLand.HALF) / 64.0))
	assert_true(continent.streamer.has_chunk(new_key), "and the ones ahead are loaded")
	var after := continent.stats()
	assert_true(int(after["chunks"]) < 160, "a bounded number of chunks: %s" % after)
	for rect in continent.streamer.body_rects():
		assert_true(Vector2(player.position.x, player.position.z).distance_to(rect.get_center()) < 300.0, "collision only near the player (%s)" % rect)
	assert_true(int(after["bodies"]) <= 64, "few collision bodies (%d)" % int(after["bodies"]))
	player.free()


func test_there_is_ground_under_the_player_after_start() -> void:
	_make()
	var land := continent.land
	for id in ["emberwood", "five_winds"]:
		var c := land.region_center(id)
		var at := Vector3(c.x + 30.0, land.height_at(c.x + 30.0, c.y) + 1.5, c.y)
		await continent.start(at)
		await physics_frames(3)
		var hit := _ray_down(at)
		assert_false(hit.is_empty(), "%s: solid ground under the player" % id)
		assert_near(hit.get("position", Vector3.ZERO).y, land.height_at(at.x, at.z), 0.05, id)
		assert_eq((hit["collider"] as Node).collision_layer, Combat.LAYER_WORLD)


func test_a_player_walks_across_the_land_without_falling_through() -> void:
	_make()
	var land := continent.land
	var home := land.region_center("emberwood")
	var walker := Walker.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = capsule
	col.position.y = 0.9
	walker.add_child(col)
	walker.collision_mask = Combat.LAYER_WORLD
	walker.collision_layer = Combat.LAYER_PLAYER
	root.add_child(walker)
	# Out from Emberwood toward Autumn Wood: over the pad, onto the road.
	var dir := (land.region_center("autumn_wood") - home).normalized()
	walker.heading = Vector3(dir.x, 0.0, dir.y)
	walker.speed = 12.0
	walker.position = Vector3(home.x, land.pad_height("emberwood") + 0.3, home.y)
	continent.target = walker
	await continent.start(walker.position)
	var start := walker.position
	var lowest_gap := INF
	var worst := 0.0
	for i in 360:
		await physics_frames(1)
		var ground := land.height_at(walker.position.x, walker.position.z)
		worst = maxf(worst, absf(walker.position.y - ground))
		lowest_gap = minf(lowest_gap, walker.position.y - ground)
	assert_true(walker.position.distance_to(start) > 60.0, "the walker covered the ground (%.0f m)" % walker.position.distance_to(start))
	assert_true(lowest_gap > -0.5, "never below the ground (lowest %.2f)" % lowest_gap)
	assert_true(worst < 2.5, "stays on the ground (off by %.2f at most)" % worst)
	walker.free()


func test_chunk_build_time_stays_in_budget() -> void:
	var land := ContinentLand.new()
	ContinentScatter.warm()
	var report := []
	for level in 5:
		var size := 64.0 * pow(2.0, level)
		var rect := Rect2(Vector2(-size * 0.5 + 120.0, 900.0), Vector2(size, size))
		var t0 := Time.get_ticks_usec()
		var mesh := ContinentMesh.build(land, rect)
		var t1 := Time.get_ticks_usec()
		var found := {}
		if level <= ContinentStreamer.SCATTER_LEVEL:
			found = ContinentScatter.instances(land, rect, 1 if level < ContinentStreamer.SCATTER_LEVEL else 2)
			ContinentScatter.multimeshes(found, rect.get_center())
		var t2 := Time.get_ticks_usec()
		var trees := 0
		for model: String in found:
			trees += (found[model] as PackedFloat32Array).size() / 5
		report.append("L%d %.0f m: mesh %.0f ms, scatter %.0f ms (%d instances)" % [level, size, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, trees])
		assert_true((t2 - t0) / 1000.0 < 1200.0, "level %d chunk took %.0f ms" % [level, (t2 - t0) / 1000.0])
		assert_true(float(mesh["ms"]) < 600.0, "level %d mesh took %.0f ms" % [level, float(mesh["ms"])])
	print("  chunk build: ", " | ".join(report))
	var t3 := Time.get_ticks_usec()
	var built := ContinentLand.new()
	print("  land + roads + rivers built in %.0f ms" % ((Time.get_ticks_usec() - t3) / 1000.0), " ", built.regions.size(), " regions")
