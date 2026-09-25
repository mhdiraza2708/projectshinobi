extends TestCase


func test_bank_and_direction_map_to_zodiac_grid() -> void:
	assert_eq(Seal.from_input(0, Seal.Direction.BOTTOM), Seal.RAT)
	assert_eq(Seal.from_input(0, Seal.Direction.TOP), Seal.HARE)
	assert_eq(Seal.from_input(1, Seal.Direction.RIGHT), Seal.SNAKE)
	assert_eq(Seal.from_input(2, Seal.Direction.LEFT), Seal.DOG)
	assert_eq(Seal.from_input(2, Seal.Direction.TOP), Seal.BOAR)


func test_every_seal_round_trips_through_bank_and_direction() -> void:
	for seal in Seal.COUNT:
		assert_eq(Seal.from_input(Seal.bank_of(seal), Seal.direction_of(seal)), seal)


func test_names_round_trip() -> void:
	for seal in Seal.COUNT:
		assert_eq(Seal.from_name(Seal.NAMES[seal]), seal)
	assert_eq(Seal.from_name(" Tiger "), Seal.TIGER)
	assert_eq(Seal.from_name("cat"), -1)


func test_weaver_records_sequence_and_finishes() -> void:
	var w := SealWeaver.new()
	w.begin()
	assert_true(w.add_seal(Seal.TIGER))
	assert_true(w.add_seal(Seal.OX))
	var result := w.finish()
	assert_eq(result, [Seal.TIGER, Seal.OX] as Array[int])
	assert_false(w.is_weaving)
	assert_true(w.sequence.is_empty())


func test_weaver_ignores_seals_when_not_weaving() -> void:
	var w := SealWeaver.new()
	assert_false(w.add_seal(Seal.RAT))
	assert_true(w.finish().is_empty())


func test_weaver_breaks_after_timeout_but_keeps_weaving() -> void:
	var w := SealWeaver.new()
	var broke := [false]
	w.broken.connect(func() -> void: broke[0] = true)
	w.begin()
	w.add_seal(Seal.RAT)
	w.tick(SealWeaver.BASE_TIMEOUT * 0.5)
	assert_eq(w.sequence.size(), 1, "still inside window")
	w.tick(SealWeaver.BASE_TIMEOUT)
	assert_true(broke[0], "broken signal")
	assert_true(w.sequence.is_empty())
	assert_true(w.is_weaving, "can start again without releasing")


func test_timeout_scale_zero_means_no_time_limit() -> void:
	var w := SealWeaver.new()
	w.timeout_scale = 0.0
	w.begin()
	w.add_seal(Seal.RAT)
	w.tick(999.0)
	assert_eq(w.sequence.size(), 1)
	assert_near(w.window_remaining(), 1.0)


func test_timeout_scale_widens_window() -> void:
	var w := SealWeaver.new()
	w.timeout_scale = 2.0
	w.begin()
	w.add_seal(Seal.RAT)
	w.tick(SealWeaver.BASE_TIMEOUT * 1.5)
	assert_eq(w.sequence.size(), 1)


func test_weaver_caps_sequence_length() -> void:
	var w := SealWeaver.new()
	w.begin()
	for i in SealWeaver.MAX_SEALS:
		assert_true(w.add_seal(Seal.RAT))
	assert_false(w.add_seal(Seal.RAT))


func test_element_cycle_is_closed() -> void:
	var natures := [Element.FIRE, Element.WIND, Element.LIGHTNING, Element.EARTH, Element.WATER]
	for e in natures:
		var beats := 0
		var loses := 0
		for other in natures:
			if Element.multiplier(e, other) > 1.0:
				beats += 1
			if Element.multiplier(e, other) < 1.0:
				loses += 1
		assert_eq(beats, 1, "%s beats exactly one" % Element.display_name(e))
		assert_eq(loses, 1, "%s loses to exactly one" % Element.display_name(e))


func test_neutral_chakra_has_no_matchups() -> void:
	for e in Element.NAMES.size():
		assert_near(Element.multiplier(Element.NONE, e), 1.0)
		assert_near(Element.multiplier(e, Element.NONE), 1.0)
