extends TestCase
## Shade Clones: a summon-form jutsu. Doubles in your likeness fight beside
## you, enemies treat them as targets, they tire out and can be struck down,
## and casting again replaces them.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player
var jutsu: JutsuDefinition


func after_each() -> void:
	Profile.reset()


func _load() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	jutsu = JutsuRegistry.get_jutsu(&"shade_clones")
	player.stats.chakra = player.stats.max_chakra
	await physics_frames(5)


func _cast() -> void:
	player.caster._cooldowns.clear()
	player.stats.chakra = player.stats.max_chakra
	assert_true(player.caster.cast(jutsu), "the jutsu casts")


func test_the_jutsu_is_valid_and_reachable_by_seals() -> void:
	JutsuRegistry.reload()
	var j := JutsuRegistry.get_jutsu(&"shade_clones")
	assert_true(j != null, "it ships")
	assert_eq(j.form, JutsuDefinition.Form.SUMMON)
	assert_eq(JutsuRegistry.find_by_seals(j.seals).id, &"shade_clones", "its seals are its own")
	assert_eq(Element.NAMES[j.element], "none", "anyone can cast it")
	assert_false(j.display_name.to_lower().contains("kage"), "an original name")


func test_summon_definitions_are_checked() -> void:
	var base := {"id": "twins", "name": "Twins", "rank": "C", "element": "none", "form": "summon",
		"seals": ["rat"], "chakra_cost": 20, "power": 0.5, "duration": 10, "count": 2, "health": 30}
	var errors: Array[String] = []
	assert_true(JutsuDefinition.from_dict(base, errors) != null, "valid")
	for patch: Dictionary in [{"health": 0}, {"duration": 0}, {"count": 9}, {"power": 3}]:
		var bad := base.duplicate()
		bad.merge(patch, true)
		var errs: Array[String] = []
		assert_eq(JutsuDefinition.from_dict(bad, errs), null, "rejects %s" % patch)
		assert_false(errs.is_empty())


func test_casting_steps_clones_out_beside_you() -> void:
	await _load()
	var chakra := player.stats.chakra
	_cast()
	await physics_frames(3)
	var clones := player.caster.clones()
	assert_eq(clones.size(), 2, "two clones")
	assert_true(chakra - player.stats.chakra >= 0.0)
	assert_true(player.caster.cooldown_left(&"shade_clones") > 10.0, "a long cooldown")
	for c in clones:
		assert_true(c.is_in_group(&"player"), "on your side")
		assert_false(c.is_in_group(&"lockable"), "not a lock-on target")
		assert_true(c.model.use_profile, "wearing your look")
		assert_true(c.display_name().contains(str(Profile.get_value(&"name"))), "named after you")
		assert_true(c.global_position.distance_to(player.global_position) < 4.0, "close by")
		assert_near(c.stats.max_health, jutsu.health, 0.01, "frail")


func test_chakra_decides_whether_you_can_cast() -> void:
	await _load()
	player.stats.chakra = 5.0
	assert_eq(player.caster.block_reason(jutsu), &"chakra", "it's costly")
	player.stats.chakra = 100.0
	assert_eq(player.caster.block_reason(jutsu), &"")


func test_clones_fight_enemies_without_hurting_you() -> void:
	await _load()
	var foe := EnemyShinobi.new()
	foe.rank = &"chunin"
	foe.element = Element.WATER
	foe.position = Vector3(0, 0, -7)
	# A passive target, so anything that damages you came from a clone.
	foe.hunt = false
	scene.add_child(foe)
	_cast()
	player.stats.health = player.stats.max_health
	var before := foe.stats.health
	await seconds(10.0)
	assert_true(foe.stats.health < before or foe.is_defeated(), "the clones hurt it (%.0f of %.0f)" % [foe.stats.health, before])
	assert_near(player.stats.health, player.stats.max_health, 0.001, "and nothing they do touches you")
	for c in player.caster.clones():
		assert_true(is_instance_valid(c.target), "they picked a target")


func test_enemies_go_for_clones() -> void:
	await _load()
	var foe := EnemyShinobi.new()
	foe.position = Vector3(8, 0, -4)
	scene.add_child(foe)
	player.global_position = Vector3(-6, 0.1, 6)
	_cast()
	var clone := player.caster.clones()[0]
	clone.global_position = Vector3(7, 0, -3)
	await physics_frames(2)
	assert_true(foe.pick_target() == clone, "the nearer clone is the target")


func test_a_struck_clone_dissolves_and_a_recast_replaces_them() -> void:
	await _load()
	_cast()
	var first := player.caster.clones()
	await seconds(1.2)  # out of their arrival smoke
	first[0].take_hit(500.0, Element.NONE, null)
	await seconds(0.3)
	assert_eq(player.caster.clones().size(), 1, "one fell, one stands")
	_cast()
	await physics_frames(3)
	assert_eq(player.caster.clones().size(), 2, "recasting restores the pair")
	assert_false(first.any(func(c: Variant) -> bool: return is_instance_valid(c) and not c.is_defeated() and player.caster.clones().has(c)), "and the old ones are gone")


func test_clones_fade_after_their_time() -> void:
	await _load()
	var short := JutsuDefinition.new()
	short.id = &"quick_shade"
	short.form = JutsuDefinition.Form.SUMMON
	short.power = 0.5
	short.duration = 1.0
	short.count = 2
	short.health = 20.0
	short.chakra_cost = 1.0
	player.caster.cast(short)
	await physics_frames(3)
	assert_eq(player.caster.clones().size(), 2)
	await seconds(1.8)
	assert_eq(player.caster.clones().size(), 0, "they're gone")


func test_clones_keep_close_when_there_is_nothing_to_fight() -> void:
	await _load()
	_cast()
	await physics_frames(5)
	for dummy in scene.find_children("*", "TrainingDummy", true, false):
		dummy.free()
	player.global_position = Vector3(10, 0.1, 12)
	await seconds(3.5)
	for c in player.caster.clones():
		assert_true(c.global_position.distance_to(player.global_position) < 6.0, "they followed (%s)" % c.global_position.distance_to(player.global_position))


func test_wayfarers_make_an_extra_clone() -> void:
	await _load()
	Profile.set_value(&"clan", "wayfarer")
	_cast()
	await physics_frames(3)
	assert_eq(player.caster.clones().size(), 3)
	Profile.set_value(&"clan", "tidebound")
	_cast()
	await physics_frames(3)
	assert_eq(player.caster.clones().size(), 2, "back to the usual pair")


func test_enemies_never_summon_them() -> void:
	var picks := EnemyShinobi.jutsu_for(Element.NONE, 100.0)
	assert_false(picks.any(func(j: JutsuDefinition) -> bool: return j.form == JutsuDefinition.Form.SUMMON), "clones are a player technique")
