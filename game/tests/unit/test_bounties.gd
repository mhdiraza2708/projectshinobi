extends TestCase
## The wanted shinobi: the data is whole and every one can be fought.


func test_the_data_is_valid() -> void:
	assert_eq(Bounties.all().size() >= 8, true, "a good number of them")
	assert_eq(Bounties.errors, [] as Array[String])
	var dangers := {}
	for b: Dictionary in Bounties.all():
		assert_true(Bounties.model_path(b) != "", "%s has a model that exists" % b["id"])
		assert_true(float(b["health"]) >= 300.0, "%s is a real fight" % b["id"])
		assert_true(str(b["taunt"]).length() > 20, "%s has something to say" % b["id"])
		dangers[int(b["danger"])] = true
	assert_eq(dangers.size(), 3, "bounties for every danger")


func test_a_bounty_is_found_by_id() -> void:
	assert_eq(Bounties.get_bounty("kiln_hand")["name"], "Goro Kiln-Hand")
	assert_true(Bounties.get_bounty("nobody").is_empty())
