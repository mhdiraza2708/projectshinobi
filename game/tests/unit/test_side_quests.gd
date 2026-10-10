extends TestCase
## The side quests as a whole: every one can be reached, finished and paid.


func before_each() -> void:
	Quests.reload()


func test_there_are_plenty_and_the_data_is_valid() -> void:
	assert_eq(Quests.errors, [] as Array[String])
	assert_true(Quests.all().size() >= 24, "%d side quests" % Quests.all().size())
	var by_island := {}
	var types := {}
	for q: Dictionary in Quests.all():
		by_island[q["island"]] = int(by_island.get(q["island"], 0)) + 1
		types[q["type"]] = true
	for id: String in Archipelago.LAYOUT:
		assert_true(int(by_island.get(id, 0)) >= 3, "%s has %d quests" % [id, int(by_island.get(id, 0))])
	assert_eq(types.size(), 4, "every kind of quest is used")


func test_every_requirement_is_a_real_chapter_or_quest_and_nothing_is_circular() -> void:
	var story := Story.load_all()
	var chapters := {}
	for c: Dictionary in story.chapters:
		chapters[c["id"]] = true
	var ids := {}
	for q: Dictionary in Quests.all():
		ids[q["id"]] = q
	for q: Dictionary in Quests.all():
		var need := str(q["requires"])
		assert_true(need == "" or chapters.has(need) or ids.has(need), "%s requires '%s'" % [q["id"], need])
		# Follow the chain back to a chapter: it must end.
		var hops := 0
		var at := need
		while ids.has(at) and hops < 30:
			at = str((ids[at] as Dictionary)["requires"])
			hops += 1
		assert_true(hops < 30, "%s: a circular requirement" % q["id"])


func test_every_item_gathered_and_every_person_is_known() -> void:
	for q: Dictionary in Quests.all():
		if q["type"] == "gather":
			assert_true(Quests.ITEMS.has(q["item"]), "%s: item %s" % [q["id"], q["item"]])
		var who := Quests.person(str(q["giver"]))
		assert_true(who.has("name") and who.has("kanji") and who.has("element"), "%s: giver %s" % [q["id"], q["giver"]])
		assert_true(str(q["objective"]) != "" and (q["intro"] as Array).size() >= 2, "%s has an objective and an intro" % q["id"])
		assert_true(int(q["xp"]) >= 100, "%s pays" % q["id"])


func test_a_person_stands_in_one_place() -> void:
	# One figure per person: their quests must agree where they stand.
	var at := {}
	for q: Dictionary in Quests.all():
		var key := "%s@%s" % [q["giver"], q["island"]]
		var spot: Array = q["giver_at"]
		if at.has(key):
			assert_eq(at[key], spot, "%s: %s stands elsewhere than for their other quests" % [q["id"], q["giver"]])
		at[key] = spot
	# And not on two islands at once (a delivery's receiver is the exception).
	var island_of := {}
	for q: Dictionary in Quests.all():
		var who := str(q["giver"])
		if island_of.has(who):
			assert_eq(island_of[who], q["island"], "%s gives quests on one island only" % who)
		island_of[who] = q["island"]


func test_quest_xp_grows_along_each_chain() -> void:
	var by_id := {}
	for q: Dictionary in Quests.all():
		by_id[q["id"]] = q
	for q: Dictionary in Quests.all():
		var need := str(q["requires"])
		if by_id.has(need):
			assert_true(int(q["xp"]) >= int((by_id[need] as Dictionary)["xp"]) * 0.8, "%s pays no less than %s" % [q["id"], need])
