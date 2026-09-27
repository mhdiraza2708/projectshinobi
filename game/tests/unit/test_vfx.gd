extends TestCase
## Visual effects: every technique has its look, effects never pile up
## (they free themselves), trails finish in place, and the player's moves
## (strike, charge) show.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player


func _load() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	await physics_frames(10)


## Effect nodes living directly in the world (not on a character).
func _loose_effects() -> Array:
	return scene.get_children().filter(func(n: Node) -> bool:
		return n is VfxTrail or n is VfxBolt or n is CPUParticles3D or n is JutsuProjectile \
			or (n is MeshInstance3D and n.material_override is BaseMaterial3D \
				and (n.material_override as BaseMaterial3D).albedo_texture != null))


func test_textures_are_there() -> void:
	for t in [&"glow", &"star", &"ring", &"spark", &"trail", &"slash", &"smoke", &"flame", &"noise"]:
		assert_true(Vfx.tex(t) != null, "%s.png" % t)


func test_every_jutsu_plays_and_cleans_up_after_itself() -> void:
	await _load()
	player.toggle_lock()
	await physics_frames(2)
	for j: JutsuDefinition in JutsuRegistry.all():
		player.stats.chakra = player.stats.max_chakra
		player.caster._cooldowns.clear()
		assert_true(player.caster.cast(j, player.lock_target), "%s casts" % j.id)
		await physics_frames(8)
	await seconds(4.0)
	var left := _loose_effects()
	assert_eq(left.size(), 0, "effects all freed themselves (left: %s)" % [left.map(func(n: Node) -> String: return n.get_class())])


func test_projectiles_wear_their_nature() -> void:
	await _load()
	for id in [&"ember_volley", &"tide_lance", &"crescent_cutter", &"thunder_needle", &"chakra_bolt"]:
		var j := JutsuRegistry.get_jutsu(id)
		var p := JutsuProjectile.new()
		p.element = j.element
		p.radius = j.radius
		p.caster = player
		p.max_range = 100.0
		p.direction = Vector3.UP
		scene.add_child(p)
		p.global_position = Vector3(0, 30, 0)
		var visual := p.get_node_or_null(^"Visual")
		assert_true(visual != null, "%s has a look" % id)
		assert_true(visual.find_children("*", "VfxTrail", true, false).size() > 0, "%s leaves a trail" % id)
		if j.element == Element.LIGHTNING:
			assert_true(visual.find_children("*", "ArcCluster", true, false).size() > 0, "lightning crackles")
		p.queue_free()


func test_trails_finish_in_place_after_impact() -> void:
	await _load()
	var p := JutsuProjectile.new()
	p.element = Element.FIRE
	p.radius = 0.3
	p.caster = player
	p.direction = Vector3.FORWARD
	p.speed = 30.0
	scene.add_child(p)
	p.global_position = player.global_position + Vector3(0, 1, -2)
	var dummy: Node3D = scene.find_children("*", "TrainingDummy", true, false)[0]
	p.direction = (dummy.global_position + Vector3.UP - p.global_position).normalized()
	for i in 60:
		await physics_frames(1)
		if not is_instance_valid(p):
			break
	assert_false(is_instance_valid(p), "the projectile hit")
	var trails := scene.get_children().filter(func(n: Node) -> bool: return n is VfxTrail)
	assert_true(trails.size() > 0, "its trail stays behind to fade")
	await seconds(1.0)
	assert_eq(scene.get_children().filter(func(n: Node) -> bool: return n is VfxTrail).size(), 0, "then goes")


func test_charging_shows_an_aura_that_goes_away() -> void:
	await _load()
	Input.action_press(&"charge_chakra")
	await physics_frames(6)
	assert_true(player.get_node_or_null(^"ChargeAura") != null, "chakra aura while charging")
	Input.action_release(&"charge_chakra")
	await physics_frames(4)
	await seconds(0.5)
	assert_true(player.get_node_or_null(^"ChargeAura") == null, "gone when you stop")


func test_strike_shows_a_slash_and_a_hit_spark() -> void:
	await _load()
	player.toggle_lock()
	await physics_frames(2)
	player.global_position = player.lock_target.global_position + Vector3(0, 0, 1.6)
	await physics_frames(2)
	var before := scene.get_child_count()
	player._strike()
	var added := scene.get_children().slice(before)
	var textures := added.filter(func(n: Node) -> bool: return n is MeshInstance3D) \
		.map(func(n: MeshInstance3D) -> String: return (n.material_override as BaseMaterial3D).albedo_texture.resource_path.get_file())
	assert_true(textures.has("slash.png"), "a slash arc")
	assert_true(textures.has("star.png"), "a hit flash")
	assert_true(added.any(func(n: Node) -> bool: return n is CPUParticles3D), "sparks")


func test_buff_aura_lasts_its_duration() -> void:
	await _load()
	var j := JutsuRegistry.get_jutsu(&"storm_mantle")
	player.stats.chakra = player.stats.max_chakra
	player.caster.cast(j)
	await physics_frames(2)
	assert_true(player.get_node_or_null(^"Aura") != null, "the mantle shows")
	await seconds(j.duration + 1.0)
	assert_true(player.get_node_or_null(^"Aura") == null, "and fades when the buff ends")
