extends TestCase
## Places of interest in play: built from the island props where you are,
## freed behind you, remembered with the slot, and kept clear of trees.

var world: ContinentWorld
var marker: Node3D


func before_each() -> void:
	Game.reset_records()


func after_each() -> void:
	if is_instance_valid(world):
		world.queue_free()
	if is_instance_valid(marker):
		marker.queue_free()
	Game.reset_records()


func _make() -> WorldSites:
	marker = Node3D.new()
	root.add_child(marker)
	world = ContinentWorld.new()
	world.player = marker
	root.add_child(world)
	world.build_now()
	var sites := WorldSites.new()
	sites.world = world
	sites.player = marker
	world.add_child(sites)
	return sites


func _stand_at(s: Dictionary) -> void:
	var at: Vector2 = s["at"]
	marker.global_position = world.to_global(Vector3(at.x, float(s["y"]), at.y))


func test_every_kind_builds_with_its_anchors_and_props_on_the_ground() -> void:
	var sites := _make()
	var expect := {"camp": "fire", "shrine": "interact", "village": "board", "ruin": "relic", "lair": "den"}
	for kind: String in ContinentSites.KINDS:
		var s: Dictionary = sites.plan.of_kind(kind)[0]
		var node := sites.build_site(s["id"])
		assert_true(node != null, "%s builds" % kind)
		assert_true(node.anchors.has(expect[kind]), "%s has its %s" % [kind, expect[kind]])
		var models := 0
		var radius := float(SiteBuilder.RADIUS[kind])
		for child in node.get_children():
			if child is SiteMarker or child is StaticBody3D or child is OmniLight3D or (child is MeshInstance3D):
				continue
			models += 1
			var c := child as Node3D
			assert_true(Vector2(c.position.x, c.position.z).length() <= radius + 12.0, "%s: %s is within its footprint" % [kind, c.name])
			var ground := world.continent.height_at(node.position.x + c.position.x, node.position.z + c.position.z) - node.position.y
			assert_true(absf(c.position.y - ground) < 2.2, "%s: %s stands on the ground (%.2f vs %.2f)" % [kind, c.name, c.position.y, ground])
		assert_true(models >= 5, "%s has props (%d)" % [kind, models])
		if kind != "ruin" or true:
			assert_true((node.get_node("Body") as StaticBody3D).get_child_count() > 0, "%s has solid props" % kind)


func test_a_site_looks_the_same_each_time() -> void:
	var sites := _make()
	var s: Dictionary = sites.plan.of_kind("village")[0]
	var a := sites.build_site(s["id"])
	var first: Array[Vector3] = []
	for c in a.get_children():
		if c is Node3D:
			first.append((c as Node3D).position)
	a.queue_free()
	sites.built.erase(s["id"])
	await root.get_tree().process_frame
	var b := sites.build_site(s["id"])
	var second: Array[Vector3] = []
	for c in b.get_children():
		if c is Node3D:
			second.append((c as Node3D).position)
	assert_eq(first, second)


func test_sites_are_built_near_you_and_freed_behind_you() -> void:
	var sites := _make()
	var near: Dictionary = sites.plan.sites[0]
	_stand_at(near)
	sites.update()
	assert_true(sites.built.has(near["id"]), "the site you stand at is built")
	var far := {}
	for s: Dictionary in sites.plan.sites:
		if (s["at"] as Vector2).distance_to(near["at"]) > WorldSites.KEEP_RANGE + 50.0:
			far = s
			break
	assert_false(far.is_empty())
	_stand_at(far)
	sites.update()
	assert_false(sites.built.has(near["id"]), "and freed once you are far away")
	assert_true(sites.built.has(far["id"]), "the one you reached is built")


func test_arriving_finds_a_place_once_and_it_is_remembered() -> void:
	var sites := _make()
	var s: Dictionary = sites.plan.sites[3]
	var heard := []
	sites.discovered.connect(func(f: Dictionary) -> void: heard.append(f["id"]))
	assert_eq(sites.state(s["id"]), "")
	_stand_at(s)
	sites.update()
	assert_eq(sites.state(s["id"]), WorldSites.FOUND)
	assert_eq(heard, [s["id"]])
	sites.update()
	assert_eq(heard.size(), 1, "announced once")
	assert_true(sites.found_sites().size() >= 1)
	sites.set_state(s["id"], WorldSites.DONE)
	assert_true(sites.is_done(s["id"]))
	assert_eq(sites.done_count(s["kind"]), 1)
	assert_eq(sites.found_sites(s["kind"]).size(), 1)


func test_nearest_finds_the_closest_anchor_of_a_kind() -> void:
	var sites := _make()
	var shrine: Dictionary = sites.plan.of_kind("shrine")[0]
	var node := sites.build_site(shrine["id"])
	var at := node.spot("interact")
	var hit := sites.nearest(at + Vector3(1, 0, 0), ["shrine"], "interact", 5.0)
	assert_eq(hit["site"]["id"], shrine["id"])
	assert_true(sites.nearest(at + Vector3(30, 0, 0), ["shrine"], "interact", 5.0).is_empty(), "nothing within reach")
	assert_true(sites.nearest(at, ["camp"], "interact", 5.0).is_empty(), "wrong kind")


func test_trees_keep_out_of_every_footprint() -> void:
	var land := ContinentLand.new()
	land.plan_sites()
	var checked := 0
	for s: Dictionary in land.sites.sites.slice(0, 12):
		var at: Vector2 = s["at"]
		var r := float(SiteBuilder.RADIUS[s["kind"]])
		var found := ContinentScatter.instances(land, Rect2(at.x - 64.0, at.y - 64.0, 128.0, 128.0))
		for model: String in found:
			var list: PackedFloat32Array = found[model]
			for i in range(0, list.size(), 5):
				checked += 1
				assert_true(Vector2(list[i], list[i + 2]).distance_to(at) >= r, "%s: a %s grows inside the %s" % [s["id"], model, s["kind"]])
	assert_true(checked > 0, "there were trees to check (%d)" % checked)
