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


func test_spirals_wind_round_an_axis_and_free_themselves() -> void:
	await _load()
	var s := Vfx.spiral(Color(0.5, 1.0, 0.7, 0.8), 3.0, 0.2, 0.8, 2.0, 9.0, 3, 0.2, false, 0.4)
	scene.add_child(s)
	await physics_frames(6)
	assert_eq(s.mesh.get_surface_count(), 1, "the ribbons are drawn")
	assert_true(s.mesh.get_aabb().size.y > 2.0, "they run the length of the axis (%s)" % s.mesh.get_aabb().size)
	assert_true(s.mesh.get_aabb().size.x > 0.5, "and wind out round it")
	await seconds(0.8)
	assert_false(is_instance_valid(s), "gone when its time is up")


func test_a_bolt_stays_attached_when_its_ends_move() -> void:
	await _load()
	var v := Vfx.bolt(scene, Vector3(0, 5, 0), Vector3(0, 5, 10), Color.WHITE, 0.1, 0.0)
	await physics_frames(3)
	var shape: PackedVector3Array = v._paths[0]
	v.a = Vector3(4, 5, 0)
	v.b = Vector3(4, 9, 7)
	var moved := v._to_world(shape)
	assert_true(moved[0].is_equal_approx(v.a) and moved[moved.size() - 1].is_equal_approx(v.b), "the same bolt, between its new ends")
	v.queue_free()


func test_a_bolt_crackles_then_holds_its_shape_and_fades() -> void:
	await _load()
	var v := Vfx.bolt(scene, Vector3.ZERO, Vector3(0, 8, 0), Color.WHITE, 0.1, 0.8)
	await seconds(0.55)
	var held: PackedVector3Array = v._paths[0]
	await physics_frames(6)
	assert_eq(v._paths[0], held, "no more crackle in the afterglow")
	await seconds(0.4)
	assert_false(is_instance_valid(v), "then gone")


func test_the_needle_trails_a_bolt_of_its_own() -> void:
	var visual := Vfx.projectile_visual(Element.LIGHTNING, 0.2)
	var arcs: ArcCluster = visual.find_children("*", "ArcCluster", true, false)[0]
	assert_true(arcs.tail > 1.0, "a line of lightning streaming behind")
	visual.free()


func test_water_and_wind_carry_spirals() -> void:
	for element in [Element.WATER, Element.WIND]:
		var visual := Vfx.projectile_visual(element, 0.35)
		assert_true(visual.find_children("*", "VfxSpiral", true, false).size() >= 1, "%s twists" % Element.display_name(element))
		visual.free()
	var crescent := Vfx.crescent(Color(0.5, 1.0, 0.7), 1.0)
	assert_true(crescent.find_children("*", "VfxSpiral", true, false).size() == 1, "the crescent has air curling off it")
	crescent.free()


func test_the_crescent_is_a_solid_bow_that_tapers_to_points() -> void:
	var mesh := Vfx.crescent_mesh(2.0, 0.5, Color.WHITE, Color(1, 1, 1, 0.0))
	var box := mesh.get_aabb()
	assert_true(box.size.x > 3.0 and box.size.y < 0.01, "a wide flat bow (%s)" % box.size)
	assert_true(box.position.z < 0.0, "bowing forward, toward -Z")
	var points := mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var widest := 0.0
	for p in points:
		widest = maxf(widest, absf(p.x))
	var tips := {}
	for p in points:
		if absf(p.x) > widest - 0.001:
			tips[p.snappedf(0.001)] = true
	assert_eq(tips.size(), 2, "each end is a single point")


func test_every_nature_lands_and_blasts_then_leaves_nothing_behind() -> void:
	await _load()
	var at := player.global_position + Vector3(0, 1.0, -6)
	for element in [Element.FIRE, Element.WIND, Element.LIGHTNING, Element.EARTH, Element.WATER, Element.NONE]:
		Vfx.impact(scene, at, element, 1.0)
		Vfx.area_blast(scene, at, element, 3.0)
		await physics_frames(4)
	await seconds(4.0)
	var left := _loose_effects()
	assert_eq(left.size(), 0, "all of it freed itself (left: %s)" % [left.map(func(n: Node) -> String: return n.get_class())])


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


func test_an_armed_strike_throws_steel_sparks_and_a_fainter_arc() -> void:
	await _load()
	player.toggle_lock()
	await physics_frames(2)
	player.global_position = player.lock_target.global_position + Vector3(0, 0, 1.6)
	await physics_frames(2)
	assert_true(player.animator.has_sword(), "a sword at the hip")
	var before := scene.get_child_count()
	player._strike()
	var added := scene.get_children().slice(before)
	var arcs := added.filter(func(n: Node) -> bool:
		return n is MeshInstance3D and (n.material_override as BaseMaterial3D).albedo_texture.resource_path.get_file() == "slash.png")
	assert_eq(arcs.size(), 2, "the arc is two layers")
	assert_true((arcs[0].material_override as BaseMaterial3D).albedo_color.a < 0.5, "faint, the blade has its own trail")
	var streaks := added.filter(func(n: Node) -> bool: return n is CPUParticles3D and (n as CPUParticles3D).particle_flag_align_y)
	assert_true(streaks.size() >= 3, "sparks along the cut (%d emitters)" % streaks.size())


func test_the_quest_pillar_is_a_soft_additive_beam() -> void:
	var beacon := QuestBeacon.new()
	root.add_child(beacon)
	await physics_frames(2)
	var beams := beacon.get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D and n.mesh is CylinderMesh)
	assert_eq(beams.size(), 2, "a wide soft beam and a bright core")
	for b: MeshInstance3D in beams:
		var m := b.material_override as ShaderMaterial
		assert_true(m != null and m.shader.code.contains("blend_add"), "light, not a solid tube")
		assert_true(m.shader.code.contains("near_fade"), "and it fades away up close")
		assert_true((b.mesh as CylinderMesh).height >= 100.0, "tall enough to find from across the sea")
		assert_eq(b.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var motes := beacon.get_node_or_null(^"Motes") as CPUParticles3D
	assert_true(motes != null and motes.emitting, "motes drifting up")
	assert_true(motes.initial_velocity_min > 0.0 and motes.direction.y > 0.9, "upward")
	var ground := beacon.get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D and n.mesh is PlaneMesh)
	assert_eq(ground.size(), 1, "a glow on the ground")
	beacon.queue_free()
