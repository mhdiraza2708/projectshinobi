extends TestCase
## The continent's places of interest: planned from the land, the same every
## time, on level dry ground and spread across the whole of it.

var land := ContinentLand.new()


func test_the_plan_is_the_same_every_time() -> void:
	var a := ContinentSites.new(land)
	var b := ContinentSites.new(ContinentLand.new())
	assert_eq(a.sites.size(), b.sites.size())
	for i in a.sites.size():
		assert_eq(a.sites[i]["at"], b.sites[i]["at"], "site %d" % i)
		assert_eq(a.sites[i]["kind"], b.sites[i]["kind"], "site %d kind" % i)


func test_there_are_many_of_every_kind() -> void:
	var plan := ContinentSites.new(land)
	assert_true(plan.sites.size() >= 36, "%d sites" % plan.sites.size())
	assert_true(plan.sites.size() <= ContinentSites.MAX_SITES)
	for kind in ContinentSites.KINDS:
		assert_true(plan.of_kind(kind).size() >= 4, "%d of %s" % [plan.of_kind(kind).size(), kind])


func test_sites_are_apart_clear_of_regions_and_on_level_dry_ground() -> void:
	var plan := ContinentSites.new(land)
	for i in plan.sites.size():
		var s: Dictionary = plan.sites[i]
		var at: Vector2 = s["at"]
		assert_true(plan.suitable(at.x, at.y), "%s is on level dry ground" % s["id"])
		assert_near(float(s["y"]), land.height_at(at.x, at.y), 0.001, "%s height" % s["id"])
		for id: String in land.regions:
			assert_true(at.distance_to(land.region_center(id)) >= ContinentSites.REGION_CLEAR, "%s is clear of %s" % [s["id"], id])
		for j in range(i + 1, plan.sites.size()):
			assert_true(at.distance_to(plan.sites[j]["at"]) >= ContinentSites.SPACING, "%s and %s apart" % [s["id"], plan.sites[j]["id"]])


func test_sites_spread_over_the_land_and_follow_the_roads() -> void:
	var plan := ContinentSites.new(land)
	var near_road := 0
	var quadrants := {}
	var danger := {}
	for s: Dictionary in plan.sites:
		var at: Vector2 = s["at"]
		if land.roads.query(at.x, at.y).x < 100.0:
			near_road += 1
		quadrants[Vector2i(int(signf(at.x)), int(signf(at.y)))] = true
		danger[int(s["danger"])] = true
		assert_true(s["name"] != "" and land.regions.has(s["region"]), "%s has a name and a region" % s["id"])
	assert_true(near_road >= 8, "%d of %d are by a road" % [near_road, plan.sites.size()])
	for v: Dictionary in plan.of_kind(ContinentSites.VILLAGE):
		assert_true(land.roads.query(v["at"].x, v["at"].y).x < 90.0, "%s lies by a road" % v["id"])
	assert_eq(quadrants.size(), 4, "every quarter of the continent has some")
	assert_true(danger.size() >= 2, "the dangers differ across the land")


func test_the_regions_set_the_danger() -> void:
	var plan := ContinentSites.new(land)
	for s: Dictionary in plan.sites:
		assert_eq(int(s["danger"]), int(ContinentSites.DANGER[s["region"]]), "%s" % s["id"])
	assert_eq(plan.site("site_00")["id"], "site_00")
	assert_true(plan.site("nope").is_empty())
