extends TestCase
## Life on the open sea: islets and sea stacks along the routes between the
## islands (Islets), surf along every coast (ShoreFoam), and gulls (Seabirds).

const Scene := preload("res://scenes/training_ground.tscn")

var archipelago: Archipelago


func after_each() -> void:
	if is_instance_valid(archipelago):
		archipelago.queue_free()


func _build_world() -> void:
	archipelago = Archipelago.new()
	root.add_child(archipelago)
	await physics_frames(2)
	archipelago.build_now()
	await physics_frames(3)


func _ray_down(at: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		archipelago.to_global(Vector3(at.x, 60.0, at.y)), archipelago.to_global(Vector3(at.x, -20.0, at.y)), Combat.LAYER_WORLD)
	return archipelago.get_world_3d().direct_space_state.intersect_ray(query)


func test_the_plan_is_the_same_every_time_and_dotted_along_every_route() -> void:
	var a := Islets.plan()
	var b := Islets.plan()
	assert_eq(var_to_str(a), var_to_str(b), "the same sea every time")
	assert_true(a.size() >= Islets.ROUTES.size(), "a cluster for every route and one off every coast (%d)" % a.size())
	var all := Islets.outcrops(a)
	assert_true(all.size() >= 12 and all.size() <= 60, "a dozen or so outcrops, not hundreds (%d)" % all.size())
	var tall := all.filter(func(o: Dictionary) -> bool: return float(o["height"]) >= 12.0)
	var low := all.filter(func(o: Dictionary) -> bool: return o["style"] == "islet")
	assert_true(tall.size() >= 5, "tall stacks (%d)" % tall.size())
	assert_true(low.size() >= 5, "low islets you can walk onto (%d)" % low.size())
	var features := all.map(func(o: Dictionary) -> String: return str(o["feature"]))
	assert_true(features.has("shrine") and features.has("watchtower"), "a shrine islet and a watch-tower")


func test_islets_keep_a_clear_lane_between_every_pair_of_islands() -> void:
	var ids: Array = Archipelago.LAYOUT.keys()
	for o: Dictionary in Islets.outcrops():
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				var from: Vector2 = Archipelago.LAYOUT[ids[i]]
				var to: Vector2 = Archipelago.LAYOUT[ids[j]]
				var gap := (o["at"] as Vector2).distance_to(Geometry2D.get_closest_point_to_segment(o["at"], from, to))
				assert_true(gap >= float(o["radius"]) + Islets.LANE - 0.01,
					"%s at %s is %.0f m from the way %s to %s" % [o["style"], o["at"], gap - float(o["radius"]), ids[i], ids[j]])


func test_islets_stand_clear_of_the_islands_and_of_each_other() -> void:
	var all := Islets.outcrops()
	for i in all.size():
		var o: Dictionary = all[i]
		for id: String in Archipelago.LAYOUT:
			# An island's coast wanders by a tenth.
			var reach := float(Island.PRESETS[id]["coast"]) * 1.1 + float(o["radius"])
			assert_true((o["at"] as Vector2).distance_to(Archipelago.LAYOUT[id]) > reach + 20.0, "%s is clear of %s" % [o["at"], id])
		for j in range(i + 1, all.size()):
			var other: Dictionary = all[j]
			var apart := (o["at"] as Vector2).distance_to(other["at"])
			assert_true(apart > float(o["radius"]) + float(other["radius"]) + 2.0, "%s and %s don't touch" % [o["at"], other["at"]])


func test_you_can_stand_on_an_islet_and_a_flat_stack() -> void:
	archipelago = Archipelago.new()
	root.add_child(archipelago)
	var islets := Islets.new()
	archipelago.add_child(islets)
	islets.build()
	await physics_frames(3)
	var stood := 0
	var flat_stack := 0
	for o: Dictionary in Islets.outcrops():
		if o["feature"] != "" or not bool(o["flat"]):
			continue
		var hit := _ray_down((o["at"] as Vector2) + (o["lean"] as Vector2))
		assert_false(hit.is_empty(), "something solid at %s" % o["at"])
		if hit.is_empty():
			continue
		# A tree may stand at the very middle of a small stack: only its
		# ground counts.
		assert_true(hit["position"].y <= Archipelago.SEA_LEVEL + float(o["height"]) + 0.05, "the top of an outcrop")
		assert_true(hit["position"].y >= Archipelago.SEA_LEVEL + float(o["height"]) - 4.5, "an outcrop's top is solid, not just its foot")
		stood += 1
		flat_stack += 1 if o["style"] == "stack" else 0
	assert_true(stood >= 8, "flat tops to stand on (%d)" % stood)
	assert_true(flat_stack >= 1, "some stacks are broad enough to stand on")
	# The shrine stands on its islet, and the sea stays walkable around it.
	assert_true(islets.lanterns.size() == 2, "a lantern either side of the shrine's way")


func test_the_rock_faces_outward_in_godots_winding() -> void:
	var rock := SurfaceTool.new()
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)
	var surf := SurfaceTool.new()
	surf.begin(Mesh.PRIMITIVE_TRIANGLES)
	for style: String in ["islet", "stack"]:
		var o := {"style": style, "radius": 6.0, "height": 9.0, "seed": 5, "feature": "", "flat": style == "islet",
			"lean": Vector2(0.9, -0.4) if style == "stack" else Vector2.ZERO}
		Islets._add_outcrop(rock, surf, o, Vector2.ZERO)
	var mesh := rock.commit()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_true(verts.size() > 200 and verts.size() % 3 == 0, "plenty of triangles (%d vertices)" % verts.size())
	# Godot builds a face's normal from clockwise corners; the mesh's own
	# normals (tilted up a little for the light) must agree, and point away
	# from the middle.
	var wrong := 0
	var inward := 0
	for t in verts.size() / 3:
		var a := verts[t * 3]
		var b := verts[t * 3 + 1]
		var c := verts[t * 3 + 2]
		var winding := Plane(a, b, c).normal
		if winding.dot(normals[t * 3]) < 0.6:
			wrong += 1
		var centre := (a + b + c) / 3.0
		if normals[t * 3].dot(Vector3(centre.x, 0.0, centre.z)) < -0.001 and normals[t * 3].y < 0.5:
			inward += 1
	assert_eq(wrong, 0, "faces wound the way their normals say")
	assert_eq(inward, 0, "no face looks inward")


func test_every_coast_gets_surf_that_follows_its_waterline() -> void:
	for id: String in Island.PRESETS:
		var island := Island.new()
		root.add_child(island)
		island.build(id)
		var foam := island.get_node_or_null("Foam") as MeshInstance3D
		assert_true(foam != null, "%s has surf" % id)
		if foam:
			var box := foam.mesh.get_aabb()
			assert_near(box.position.y, island.water_level, 0.001, "%s's surf lies on its sea" % id)
			assert_true(box.size.x > float(island.preset["coast"]) * 1.4, "%s's surf goes all the way round (%.0f m)" % [id, box.size.x])
			assert_true(foam.material_override == null and foam.mesh.surface_get_material(0) == ShoreFoam.material(), "%s shares one foam material" % id)
		# The trace sits right on the waterline wherever it finds one.
		var radii := ShoreFoam.trace_coast(island.height_at, island.water_level)
		assert_eq(radii.size(), ShoreFoam.COAST_STEPS)
		for i in radii.size():
			if radii[i] > ShoreFoam.SEARCH_START - 1.0:
				continue
			var dir := Vector2.from_angle(TAU * i / radii.size())
			assert_true(island.height_at(dir.x * (radii[i] - 0.3), dir.y * (radii[i] - 0.3)) >= island.water_level - 0.001, "%s: land just inside bearing %d" % [id, i])
			assert_true(island.height_at(dir.x * (radii[i] + 0.3), dir.y * (radii[i] + 0.3)) <= island.water_level + 0.001, "%s: sea just outside bearing %d" % [id, i])
		island.free()


func test_the_open_world_has_islets_surf_and_gulls() -> void:
	await _build_world()
	var islets := archipelago.islets
	assert_true(islets != null and islets.clusters.size() == Islets.plan().size(), "every cluster is built")
	# Few nodes for the whole sea: a rock mesh and a strip of surf each, and
	# trees only where they grow.
	var meshes := islets.find_children("*", "GeometryInstance3D", true, false)
	assert_true(meshes.size() <= 14 * 6 + 8, "islets stay cheap (%d drawables)" % meshes.size())
	for c in islets.clusters:
		assert_true(c.get_node_or_null("Rock") != null and c.get_node_or_null("Foam") != null, "%s has rock and surf" % c.name)
		assert_true((c.get_node("Rock") as MeshInstance3D).visibility_range_end > 0.0, "%s's rock fades with distance" % c.name)
	for id: String in archipelago.islands:
		var foam := archipelago.islands[id].get_node_or_null("Foam") as MeshInstance3D
		assert_true(foam != null and foam.visibility_range_end > 0.0, "%s's surf fades with distance in the open world" % id)
	# Gulls over every island and cluster, all in one draw.
	var birds := archipelago.birds
	assert_true(birds != null and birds.count >= Archipelago.LAYOUT.size() * 6 + islets.clusters.size() * 3, "gulls everywhere (%d)" % birds.count)
	assert_eq(birds.multimesh.instance_count, birds.count)
	assert_true(birds.multimesh.use_custom_data, "each bird's circle rides in its custom data")
	assert_eq(birds.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var over_emberwood := birds.flocks.filter(func(f: Array) -> bool: return (f[0] as Vector3).distance_to(Vector3(0, 20, 0)) < 12.0)
	assert_true(over_emberwood.size() == 1, "a flock over Emberwood")
	birds.set_night(true, true)
	assert_true(birds.roosting(), "gulls roost at night")
	birds.set_night(false, true)
	assert_false(birds.roosting())
	# The watch-tower's lamp.
	assert_false(islets.lamp_lit())
	islets.set_lamp(true)
	assert_true(islets.lamp_lit(), "its lamp burns at dusk")
	islets.set_lamp(false)
	assert_false(islets.lamp_lit())


func test_a_story_island_alone_has_surf_but_no_islets() -> void:
	var island := Island.new()
	root.add_child(island)
	island.build("emberwood")
	assert_true(island.get_node_or_null("Foam") != null)
	assert_eq((island.get_node("Foam") as MeshInstance3D).visibility_range_end, 0.0, "no distance limit in a story chapter")
	assert_true(island.get_children().all(func(n: Node) -> bool: return not n is Islets), "islets belong to the open world")
	island.free()


func test_dusk_lights_the_tower_and_the_shrine_lanterns_and_the_gulls_roost_at_night() -> void:
	Profile.persist = false
	Profile.reset()
	Game.reset_records()
	Game.start_mode = Game.Mode.TITLE
	var scene := Scene.instantiate()
	root.add_child(scene)
	await physics_frames(2)
	scene.instant_world = true
	await scene.start_world()
	await physics_frames(3)
	var sea: Archipelago = scene.world.archipelago
	if sea.islets == null:
		# The continent has no islets or gulls (yet).
		scene.queue_free()
		return
	assert_false(sea.islets.lamp_lit(), "the lamp is out in the morning")
	scene.set_time_of_day("dusk")
	await seconds(1.4)
	assert_true(sea.islets.lamp_lit(), "the watch-tower's lamp is lit at dusk")
	assert_false(sea.birds.roosting(), "the gulls are still up at dusk")
	assert_eq(sea.islets.lanterns.size(), 2)
	for lantern in sea.islets.lanterns:
		assert_true(scene.lanterns().has(lantern), "the shrine's lanterns join the night lights")
	assert_eq(scene.lantern_lights.size(), scene.lanterns().size(), "every lantern has its light")
	scene.set_time_of_day("night")
	await seconds(5.6)
	assert_true(sea.birds.roosting(), "the gulls roost at night")
	scene.set_time_of_day("day")
	await seconds(1.4)
	assert_false(sea.islets.lamp_lit(), "the lamp goes out at dawn")
	scene.queue_free()
	Game.reset_records()
	Profile.reset()
