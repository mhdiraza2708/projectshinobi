extends TestCase


func _valid() -> Dictionary:
	return {
		"id": "test_bolt", "name": "Test Bolt", "rank": "D", "element": "fire",
		"form": "projectile", "seals": ["tiger", "ox"], "chakra_cost": 5,
		"power": 10, "speed": 20, "range": 10, "radius": 0.3,
	}


func test_shipped_jutsu_load_without_errors() -> void:
	JutsuRegistry.reload()
	assert_eq(JutsuRegistry.load_errors, [] as Array[String])
	assert_true(JutsuRegistry.count() >= 10, "starter set present")


func test_every_shipped_form_is_represented() -> void:
	var forms := {}
	for j in JutsuRegistry.all():
		forms[j.form] = true
	for f in JutsuDefinition.FORM_NAMES.size():
		assert_true(forms.has(f), "a shipped jutsu uses form '%s'" % JutsuDefinition.FORM_NAMES[f])


func test_lookup_by_seals() -> void:
	var j := JutsuRegistry.find_by_seals([Seal.TIGER, Seal.OX])
	assert_true(j != null)
	if j:
		assert_eq(j.id, &"ember_volley")
	assert_eq(JutsuRegistry.find_by_seals([Seal.BOAR, Seal.BOAR, Seal.BOAR]), null)


func test_completions_filter_by_prefix() -> void:
	var ids := JutsuRegistry.completions([Seal.TIGER]).map(func(j: JutsuDefinition) -> StringName: return j.id)
	assert_true(ids.has(&"ember_volley"))
	assert_true(ids.has(&"sunfall_orb"))
	assert_false(ids.has(&"chakra_bolt"))
	assert_eq(JutsuRegistry.completions([]).size(), JutsuRegistry.count())


func test_valid_definition_parses() -> void:
	var errors: Array[String] = []
	var j := JutsuDefinition.from_dict(_valid(), errors)
	assert_eq(errors, [] as Array[String])
	assert_true(j != null)
	if j:
		assert_eq(j.element, Element.FIRE)
		assert_eq(j.form, JutsuDefinition.Form.PROJECTILE)
		assert_eq(j.seals, [Seal.TIGER, Seal.OX] as Array[int])
		assert_near(j.max_range, 10.0)


func test_unknown_key_is_rejected() -> void:
	var d := _valid()
	d["damgae"] = 10
	var errors: Array[String] = []
	assert_eq(JutsuDefinition.from_dict(d, errors), null)
	assert_true(errors.size() == 1 and errors[0].contains("damgae"))


func test_missing_key_is_rejected() -> void:
	var d := _valid()
	d.erase("seals")
	var errors: Array[String] = []
	assert_eq(JutsuDefinition.from_dict(d, errors), null)


func test_bad_values_are_rejected() -> void:
	var cases := {
		"seals": ["tiger", "cat"],
		"element": "plasma",
		"form": "clone",
		"rank": "Z",
		"chakra_cost": -5,
		"power": "lots",
		"id": "Bad Id",
	}
	for key: String in cases:
		var d := _valid()
		d[key] = cases[key]
		var errors: Array[String] = []
		assert_eq(JutsuDefinition.from_dict(d, errors), null, "bad %s" % key)
		assert_false(errors.is_empty(), "error reported for bad %s" % key)


func test_form_specific_validation() -> void:
	var d := _valid()
	d["form"] = "buff"
	d["buff_stat"] = "damage_reduction"
	d["power"] = 1.0
	d["duration"] = 5
	var errors: Array[String] = []
	assert_eq(JutsuDefinition.from_dict(d, errors), null, "100% damage reduction is rejected")


func test_registry_rejects_duplicate_ids_and_sequences() -> void:
	var errors: Array[String] = []
	var a := JutsuDefinition.from_dict(_valid(), errors)
	# Same seals as the shipped Ember Volley.
	JutsuRegistry.reload()
	var before := JutsuRegistry.count()
	assert_false(JutsuRegistry.register(a, "test"))
	var d := _valid()
	d["id"] = "chakra_bolt"
	d["seals"] = ["boar", "boar"]
	assert_false(JutsuRegistry.register(JutsuDefinition.from_dict(d, errors), "test"))
	assert_eq(JutsuRegistry.count(), before)
	JutsuRegistry.reload()
