extends TestCase
## Stats, the caster, and every jutsu form against real training dummies.

const DummyScene := preload("res://scenes/training_dummy.tscn")

var _body: CharacterBody3D
var _stats: Stats
var _caster: JutsuCaster


func before_each() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	root.add_child(ground)

	_body = CharacterBody3D.new()
	_body.collision_layer = Combat.LAYER_PLAYER
	_stats = Stats.new()
	_body.add_child(_stats)
	_caster = JutsuCaster.new()
	_caster.position = Vector3(0, 1.2, -0.6)
	_caster.stats = _stats
	_caster.body = _body
	_body.add_child(_caster)
	root.add_child(_body)


func _dummy(affinity: String, pos: Vector3) -> TrainingDummy:
	var d: TrainingDummy = DummyScene.instantiate()
	d.affinity = affinity
	root.add_child(d)
	d.global_position = pos
	return d


func _jutsu(id: StringName) -> JutsuDefinition:
	return JutsuRegistry.get_jutsu(id)


# --- Stats ---------------------------------------------------------------------

func test_elemental_damage_multipliers() -> void:
	var s := Stats.new()
	root.add_child(s)
	s.affinity = Element.EARTH
	assert_near(s.take_damage(10.0, Element.LIGHTNING), 15.0, 0.001, "lightning beats earth")
	assert_near(s.take_damage(10.0, Element.WATER), 7.5, 0.001, "earth resists water")
	assert_near(s.take_damage(10.0, Element.FIRE), 10.0, 0.001, "neutral matchup")


func test_guard_reduction_and_invulnerability_stack_correctly() -> void:
	var s := Stats.new()
	root.add_child(s)
	s.guard_multiplier = 0.3
	s.add_modifier(&"damage_reduction", 0.5, 5.0)
	assert_near(s.take_damage(20.0), 3.0)
	s.is_invulnerable = true
	assert_near(s.take_damage(50.0), 0.0)


func test_chakra_spend_and_charge() -> void:
	var s := Stats.new()
	root.add_child(s)
	assert_true(s.spend_chakra(90.0))
	assert_false(s.spend_chakra(20.0), "can't overspend")
	s.is_charging = true
	s._process(1.0)
	assert_near(s.chakra, 10.0 + s.charge_regen, 0.01)


func test_modifiers_refresh_instead_of_stacking_and_expire() -> void:
	var s := Stats.new()
	root.add_child(s)
	s.add_modifier(&"move_speed", 0.4, 2.0)
	s.add_modifier(&"move_speed", 0.2, 1.0)
	assert_near(s.modifier(&"move_speed"), 0.4, 0.001, "keeps stronger")
	s._process(2.5)
	assert_near(s.modifier(&"move_speed"), 0.0, 0.001, "expired")


func test_heal_is_capped() -> void:
	var s := Stats.new()
	root.add_child(s)
	s.take_damage(30.0)
	s.heal(100.0)
	assert_near(s.health, s.max_health)


# --- Caster ------------------------------------------------------------------

func test_cast_spends_chakra_and_starts_cooldown() -> void:
	await physics_frames(1)
	var bolt := _jutsu(&"chakra_bolt")
	assert_true(_caster.cast(bolt))
	assert_near(_stats.chakra, _stats.max_chakra - bolt.chakra_cost, 0.1)
	assert_true(_caster.cooldown_left(bolt.id) > 0.0)
	assert_eq(_caster.block_reason(bolt), &"cooldown")
	assert_false(_caster.cast(bolt), "blocked while cooling down")


func test_cast_fails_without_chakra() -> void:
	_stats.chakra = 1.0
	var reasons: Array[StringName] = []
	_caster.cast_failed.connect(func(_j: JutsuDefinition, r: StringName) -> void: reasons.append(r))
	assert_false(_caster.cast(_jutsu(&"sunfall_orb")))
	assert_eq(reasons, [&"chakra"] as Array[StringName])


func test_misfire_costs_a_little_chakra() -> void:
	var reasons: Array[StringName] = []
	_caster.cast_failed.connect(func(_j: JutsuDefinition, r: StringName) -> void: reasons.append(r))
	assert_eq(_caster.cast_sequence([Seal.BOAR, Seal.BOAR, Seal.BOAR]), null)
	assert_eq(reasons, [&"misfire"] as Array[StringName])
	assert_near(_stats.chakra, _stats.max_chakra - JutsuCaster.MISFIRE_CHAKRA, 0.1)


func test_projectile_hits_target_with_elemental_bonus() -> void:
	var earth := _dummy("earth", Vector3(0, 0, -8))
	await physics_frames(2)
	var needle := _jutsu(&"thunder_needle")
	assert_true(_caster.cast(needle, earth))
	await physics_frames(30)
	assert_near(earth.stats.max_health - earth.stats.health, needle.power * Element.ADVANTAGE_MULTIPLIER, 0.01)


func test_projectile_fan_spawns_count() -> void:
	await physics_frames(1)
	var volley := _jutsu(&"ember_volley")
	_caster.cast(volley)
	var projectiles := root.get_children().filter(func(n: Node) -> bool: return n is JutsuProjectile)
	assert_eq(projectiles.size(), volley.count)


func test_wall_blocks_projectiles() -> void:
	var dummy := _dummy("none", Vector3(0, 0, -10))
	await physics_frames(2)
	assert_true(_caster.cast(_jutsu(&"stone_bulwark")))
	await physics_frames(20)  # let it rise
	var walls := root.get_children().filter(func(n: Node) -> bool: return n is JutsuWall)
	assert_eq(walls.size(), 1)
	_caster.cast(_jutsu(&"tide_lance"), dummy)
	await physics_frames(40)
	assert_near(dummy.stats.health, dummy.stats.max_health, 0.01, "wall absorbed the lance")


func test_area_hits_everything_in_radius_but_not_caster() -> void:
	var near_a := _dummy("none", Vector3(2, 0, 0))
	var near_b := _dummy("none", Vector3(-2, 0, 1))
	var far := _dummy("none", Vector3(0, 0, -15))
	await physics_frames(2)
	var stomp := _jutsu(&"quake_stomp")
	var caster_hp := _stats.health
	assert_true(_caster.cast(stomp))
	assert_true(near_a.stats.health < near_a.stats.max_health)
	assert_true(near_b.stats.health < near_b.stats.max_health)
	assert_near(far.stats.health, far.stats.max_health, 0.01)
	assert_near(_stats.health, caster_hp, 0.01, "caster unharmed")


func test_buff_and_heal_forms() -> void:
	await physics_frames(1)
	assert_true(_caster.cast(_jutsu(&"storm_mantle")))
	assert_near(_stats.modifier(&"move_speed"), 0.4)
	_stats.take_damage(50.0)
	assert_true(_caster.cast(_jutsu(&"mending_palm")))
	assert_near(_stats.health, 80.0, 0.01)


func test_attack_power_buff_scales_damage() -> void:
	var dummy := _dummy("none", Vector3(0, 0, -6))
	await physics_frames(2)
	_caster.cast(_jutsu(&"focus_seal"))
	_caster.cast(_jutsu(&"chakra_bolt"), dummy)
	await physics_frames(30)
	assert_near(dummy.stats.max_health - dummy.stats.health, 8.0 * 1.5, 0.01)
