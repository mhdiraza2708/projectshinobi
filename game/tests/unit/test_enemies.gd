extends TestCase
## Enemy shinobi, the Trial of the Five Natures, and the title screen, in
## the real game scene.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player


func before_each() -> void:
	seed(1234)


func after_each() -> void:
	for action: StringName in DefaultBindings.table():
		Input.action_release(action)


func _load(mode := Game.Mode.TRAINING) -> void:
	Game.start_mode = mode
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	await physics_frames(10)


func _spawn(rank: StringName, element: int, pos: Vector3) -> EnemyShinobi:
	var e := EnemyShinobi.new()
	e.rank = rank
	e.element = element
	e.target = player
	e.position = pos
	scene.add_child(e)
	return e


func _await_fight(e: EnemyShinobi) -> void:
	await physics_frames(ceili(EnemyShinobi.SPAWN_TIME * 60.0) + 5)
	assert_true(e.state != EnemyShinobi.State.SPAWNING, "spawned and fighting")


func test_enemy_is_a_styled_lockable_fighter() -> void:
	await _load()
	var e := _spawn(&"genin", Element.WIND, player.global_position + Vector3(0, 0, -8))
	await _await_fight(e)
	assert_true(e.is_in_group(&"lockable"))
	assert_true(e.model.instance != null and e.model.animator != null, "character model loaded")
	assert_eq(e.stats.affinity, Element.WIND)
	assert_near(e.stats.max_health, EnemyShinobi.RANKS[&"genin"]["health"])
	assert_true(e.display_name().contains("Wind Genin"))
	assert_true(e.model.loaded_path in EnemyShinobi.rival_models(Element.WIND), "in the wind rival's own design")
	assert_true(e.model.gear.attachments().is_empty(), "with no gear over it")
	assert_false(e.jutsu_list.is_empty(), "has jutsu")
	for j in e.jutsu_list:
		assert_eq(j.element, Element.WIND)


func test_fire_genin_wear_the_masked_raider_and_jonin_the_rogue_elite() -> void:
	await _load()
	var raider := EnemyShinobi.RIVAL_DIR.path_join("fire_raider.glb")
	assert_true(EnemyShinobi.rival_models(Element.FIRE).has(raider))
	var genin := _spawn(&"genin", Element.FIRE, player.global_position + Vector3(-2, 0, -8))
	var jonin := _spawn(&"jonin", Element.FIRE, player.global_position + Vector3(2, 0, -8))
	await _await_fight(genin)
	var m := genin.model
	assert_eq(m.loaded_path, raider)
	assert_true(m.poser.active and m.animator.clips != null, "the game's poses and clips drive it")
	assert_near(m.measure_height(), m.target_height, 0.05, "at shinobi height")
	assert_true(m.gear.attachments().is_empty(), "it comes with its own mask and gear")
	var body := m.instance.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mat := body.get_active_material(0) as BaseMaterial3D
	assert_eq(mat.diffuse_mode, BaseMaterial3D.DIFFUSE_TOON, "cel-shaded like the VRoid cast")
	assert_true(mat.next_pass != null, "with an ink outline")
	assert_eq(jonin.model.loaded_path, EnemyShinobi.RIVAL_DIR.path_join("jonin_rogue_elite.glb"),
		"a jonin of any nature wears the rogue elite")
	assert_true(jonin.model.gear.has_sword(), "with a katana at the hip")
	for nature in [Element.LIGHTNING, Element.EARTH, Element.WATER, Element.WIND]:
		assert_false(EnemyShinobi.rival_models(nature).is_empty(), "%s has its rival" % Element.NAMES[nature])


func test_weave_shows_seals_then_casts() -> void:
	await _load()
	var e := _spawn(&"genin", Element.FIRE, player.global_position + Vector3(0, 0, -8))
	await _await_fight(e)
	var volley := JutsuRegistry.get_jutsu(&"ember_volley")
	e._start_weave(volley)
	var shown := ""
	for i in 90:
		await physics_frames(1)
		if e._seal_label.text.length() > shown.length():
			shown = e._seal_label.text
		if e.state != EnemyShinobi.State.WEAVING:
			break
	assert_eq(shown, Seal.kanji(Seal.TIGER) + Seal.kanji(Seal.OX), "seals shown above its head")
	assert_true(e.caster.cooldown_left(&"ember_volley") > 0.0, "cast when the weave finished")


func test_kunai_sized_hit_interrupts_a_genin_but_not_a_chunin() -> void:
	await _load()
	var genin := _spawn(&"genin", Element.FIRE, player.global_position + Vector3(-3, 0, -8))
	var chunin := _spawn(&"chunin", Element.FIRE, player.global_position + Vector3(3, 0, -8))
	await _await_fight(genin)
	var volley := JutsuRegistry.get_jutsu(&"ember_volley")
	genin._start_weave(volley)
	chunin._start_weave(volley)
	await physics_frames(2)
	genin.take_hit(5.0, Element.NONE, player)
	chunin.take_hit(5.0, Element.NONE, player)
	assert_eq(genin.state, EnemyShinobi.State.STAGGERED, "genin interrupted")
	assert_eq(chunin.state, EnemyShinobi.State.WEAVING, "chunin keeps weaving")
	await physics_frames(60)
	assert_eq(genin.caster.cooldown_left(&"ember_volley"), 0.0, "interrupted jutsu never cast")


func test_enemies_never_hurt_each_other() -> void:
	await _load()
	var a := _spawn(&"genin", Element.FIRE, player.global_position + Vector3(-2, 0, -8))
	var b := _spawn(&"genin", Element.FIRE, player.global_position + Vector3(2, 0, -8))
	await _await_fight(a)
	assert_eq(Combat.apply_hit(b, 20.0, Element.NONE, a), 0.0)
	assert_near(b.stats.health, b.stats.max_health)
	var p := JutsuProjectile.new()
	p.caster = a
	scene.add_child(p)
	assert_true(p._exclude.has(b.get_rid()), "projectiles fly through allies")
	assert_false(p._exclude.has(player.get_rid()))
	p.queue_free()


func test_melee_combo_hurts_the_player() -> void:
	await _load()
	var e := _spawn(&"genin", Element.FIRE, player.global_position + Vector3(0, 0, -1.6))
	await _await_fight(e)
	var before := player.stats.health
	e._start_windup()
	await physics_frames(60)
	assert_true(player.stats.health < before, "strike connected")


func test_left_alone_an_enemy_attacks() -> void:
	await _load()
	var e := _spawn(&"chunin", Element.LIGHTNING, player.global_position + Vector3(0, 0, -9))
	# A lambda's captured locals are copies: the count lives in an array.
	var shots: Array[int] = [0]
	scene.child_entered_tree.connect(func(n: Node) -> void:
		if n is JutsuProjectile and n.caster == e:
			shots[0] += 1)
	var before := player.stats.health
	await physics_frames(420)
	assert_true(shots[0] > 0 or player.stats.health < before, "it threw, cast or struck within 7 s")


func test_defeat_vanishes_and_moves_lock_on() -> void:
	await _load()
	for d in scene.find_children("*", "TrainingDummy", true, false):
		d.free()
	var a := _spawn(&"genin", Element.FIRE, player.global_position + Vector3(0, 0, -6))
	var b := _spawn(&"genin", Element.FIRE, player.global_position + Vector3(4, 0, -8))
	await _await_fight(a)
	player._set_lock(a)
	var fired := [false]
	a.defeated.connect(func(_e: EnemyShinobi) -> void: fired[0] = true)
	a.take_hit(500.0, Element.NONE, player)
	assert_true(fired[0], "defeated signal")
	assert_false(a.is_in_group(&"lockable"))
	await physics_frames(2)
	assert_true(player.lock_target == b, "lock moved to the other enemy")
	await physics_frames(70)
	assert_false(is_instance_valid(a), "vanished")


func test_trial_runs_waves_to_victory() -> void:
	await _load()
	scene.start_trial([
		{"element": Element.FIRE, "enemies": [&"genin"]},
		{"element": Element.WATER, "enemies": [&"genin", &"genin"]},
	])
	var d: TrialDirector = scene.director
	await physics_frames(1)
	assert_eq(scene.find_children("*", "TrainingDummy", true, false).size(), 0, "dummies cleared")
	var result := []
	d.finished.connect(func(won: bool, seconds: float, record: bool) -> void: result.append_array([won, seconds, record]))
	for wave in 2:
		await physics_frames(ceili(TrialDirector.ANNOUNCE_TIME * 60.0) + 70)
		assert_eq(d.wave, wave)
		assert_eq(d.alive.size(), wave + 1)
		assert_true(scene.hud.objective().contains("Wave %d/2" % (wave + 1)), scene.hud.objective())
		player.stats.health = 50.0
		for e in d.alive.duplicate():
			e.take_hit(1000.0, Element.NONE, player)
		if wave == 0:
			assert_true(player.stats.health > 50.0, "healed between waves")
			await physics_frames(ceili(TrialDirector.BREATHER * 60.0))
	assert_eq(result.size(), 3, "finished")
	assert_true(result[0], "won")
	assert_true(result[2], "first clear is a record")
	assert_eq(d.waves_cleared, 2)
	assert_near(Game.best_time(TrialDirector.TRIAL_ID), result[1], 0.001)
	await physics_frames(110)
	assert_true(scene.results.is_open(), "results shown")


func test_trial_is_lost_when_the_player_falls() -> void:
	await _load()
	scene.start_trial()
	var d: TrialDirector = scene.director
	await physics_frames(ceili(TrialDirector.ANNOUNCE_TIME * 60.0) + 70)
	var lost := [false]
	d.finished.connect(func(won: bool, _s: float, _r: bool) -> void: lost[0] = not won)
	player.take_hit(1000.0, Element.NONE, null)
	assert_eq(player.state, Player.State.DOWN)
	assert_true(lost[0], "trial failed")
	for e in d.alive:
		assert_true(e.target == null, "enemies stand down")
	await physics_frames(110)
	assert_true(scene.results.is_open())
	player.revive()
	assert_eq(player.state, Player.State.FREE)
	assert_near(player.stats.health, player.stats.max_health)


func test_title_screen_leads_to_each_mode() -> void:
	await _load(Game.Mode.TITLE)
	assert_true(scene.title_screen.is_open())
	assert_false(scene.hud.visible)
	assert_false(player.input_enabled)
	# Customize from the title returns to the title.
	scene.title_screen.customize_chosen.emit()
	assert_true(scene.customize_menu.is_open())
	scene.customize_menu.close()
	assert_true(scene.title_screen.is_open(), "back on the title")
	assert_false(player.input_enabled)
	scene.title_screen.trial_chosen.emit()
	assert_false(scene.title_screen.is_open())
	assert_true(scene.hud.visible and player.input_enabled)
	assert_true(scene.director != null and scene.director.running, "trial started")


func test_training_mode_keeps_dummies() -> void:
	await _load(Game.Mode.TITLE)
	scene.title_screen.training_chosen.emit()
	assert_eq(scene.mode, Game.Mode.TRAINING)
	assert_true(scene.find_children("*", "TrainingDummy", true, false).size() > 0)
	assert_true(scene.director == null)


func test_lock_on_prefers_enemies_over_dummies() -> void:
	await _load()
	# The neutral dummy is dead ahead; the enemy is off to the side.
	var e := _spawn(&"genin", Element.FIRE, player.global_position + Vector3(3, 0, -9))
	await _await_fight(e)
	e.set_physics_process(false)
	assert_true(player.find_lock_target() == e, "locks the enemy, not the dummy")
	assert_true(player.soft_target() == e, "soft aim takes the enemy in its cone over the dummy")
	e.dismiss()
	await physics_frames(2)
	assert_true(player.find_lock_target() is TrainingDummy, "dummies are still targetable on their own")


func test_projectile_outlives_its_thrower_safely() -> void:
	await _load()
	# Off to the side, clear of the training dummies.
	var a := _spawn(&"genin", Element.FIRE, player.global_position + Vector3(10, 0, 0))
	var b := _spawn(&"genin", Element.WATER, player.global_position + Vector3(10, 0, 4))
	await _await_fight(a)
	var p := JutsuProjectile.new()
	p.caster = a
	p.target = player
	p.direction = Vector3(-1, 0, 0)
	p.speed = 30.0
	scene.add_child(p)
	p.global_position = a.global_position + Vector3(-1, 1, 0)
	a.free()
	# The other enemy scans projectiles for dodging; the hit must still land.
	var before := player.stats.health
	await physics_frames(40)
	assert_true(is_instance_valid(b))
	assert_true(player.stats.health < before, "an orphaned projectile still hits")


# --- Readable, fair fights ---------------------------------------------------------

func _kunai_in_flight(by: EnemyShinobi) -> int:
	var n := 0
	for p in root.get_tree().get_nodes_in_group(&"projectiles"):
		if p is JutsuProjectile and p.caster == by and p.style == &"kunai":
			n += 1
	return n


func test_a_thrower_stops_and_tells_before_the_kunai_leaves() -> void:
	await _load()
	var e := _spawn(&"genin", Element.FIRE, player.global_position + Vector3(0, 0, -8))
	await _await_fight(e)
	e._start_aim()
	assert_eq(e.state, EnemyShinobi.State.AIMING)
	assert_eq(e._seal_label.text, "投", "a mark over its head")
	var aim: float = EnemyShinobi.RANKS[&"genin"]["aim"]
	await physics_frames(int(aim * 60.0) - 8)
	assert_eq(e.state, EnemyShinobi.State.AIMING, "still holding")
	assert_eq(_kunai_in_flight(e), 0, "nothing thrown during the tell")
	await physics_frames(14)
	assert_true(_kunai_in_flight(e) > 0 or player.stats.health < player.stats.max_health, "then it throws")
	assert_true(e.state != EnemyShinobi.State.AIMING)


func test_a_hit_breaks_a_throw_but_a_kunai_does_not() -> void:
	await _load()
	var e := _spawn(&"genin", Element.FIRE, player.global_position + Vector3(0, 0, -8))
	await _await_fight(e)
	e.set_physics_process(false)
	e._enter(EnemyShinobi.State.AIMING)
	e.take_hit(5.0, Element.NONE, player)
	assert_eq(e.state, EnemyShinobi.State.AIMING, "a kunai doesn't stop the throw")
	e.take_hit(8.0, Element.NONE, player)
	assert_eq(e.state, EnemyShinobi.State.STAGGERED, "a strike does")


func test_enemy_jutsu_home_less_the_faster_they_fly() -> void:
	await _load()
	var e := _spawn(&"chunin", Element.LIGHTNING, player.global_position + Vector3(0, 0, -8))
	var needle := JutsuRegistry.get_jutsu(&"thunder_needle")
	var tamed := e._tamed_jutsu(needle)
	assert_true(tamed.homing < needle.homing, "the 55 m/s needle homes less")
	assert_eq(needle.homing, 2.2, "the registry's definition is untouched")
	assert_true(tamed.homing >= EnemyShinobi.HOMING_CAP_RANGE.x)
	assert_eq(tamed.id, needle.id, "same jutsu, same cooldown")


func test_area_jutsu_mark_the_ground_they_will_hit() -> void:
	await _load()
	var e := _spawn(&"jonin", Element.EARTH, player.global_position + Vector3(0, 0, -3))
	await _await_fight(e)
	var stomp := JutsuRegistry.get_jutsu(&"quake_stomp")
	e._start_weave(stomp)
	await physics_frames(3)
	assert_true(e._danger != null and e._danger.visible, "a zone on the ground")
	assert_near(e._danger.scale.x, stomp.radius, 0.01, "as big as the blast")
	e.take_hit(50.0, Element.NONE, player)
	assert_false(e._danger.visible, "gone once the weave is broken")
	e._start_weave(JutsuRegistry.get_jutsu(&"ember_volley"))
	assert_false(e._danger.visible, "projectile jutsu mark nothing")


func test_a_light_hit_rocks_the_enemy_and_a_flurry_staggers_it() -> void:
	await _load()
	var e := _spawn(&"genin", Element.FIRE, player.global_position + Vector3(0, 0, -8))
	await _await_fight(e)
	e.set_physics_process(false)
	e.take_hit(7.0, Element.NONE, player)
	assert_eq(e.state, EnemyShinobi.State.FIGHT, "one strike doesn't stagger a genin")
	assert_true(e._recoil > 0.0, "but stops it for a beat")
	assert_true(e.velocity.z < -1.0, "and slides it back, away from the player")
	assert_true(e.model.rotation.x > 0.1, "and tips the body back, whatever the model")
	e.take_hit(8.75, Element.NONE, player)
	assert_eq(e.state, EnemyShinobi.State.STAGGERED, "two strikes in a row break its poise")


func test_a_flurry_cannot_hold_an_enemy_down() -> void:
	await _load()
	var e := _spawn(&"genin", Element.FIRE, player.global_position + Vector3(0, 0, -8))
	await _await_fight(e)
	e.set_physics_process(false)
	e.stats.max_health = 1000.0
	e.stats.health = 1000.0
	e.take_hit(10.0, Element.NONE, player)
	e.take_hit(10.0, Element.NONE, player)
	assert_eq(e.state, EnemyShinobi.State.STAGGERED)
	# More blows while it reels do not restart the stagger.
	e._state_time = 0.3
	e.take_hit(10.0, Element.NONE, player)
	assert_near(e._state_time, 0.3, 0.001, "stagger not restarted")
	# Back on its feet it shrugs off the next flurry for a moment.
	e._enter(EnemyShinobi.State.FIGHT)
	assert_true(e._armor > 0.0)
	e.take_hit(10.0, Element.NONE, player)
	e.take_hit(10.0, Element.NONE, player)
	assert_eq(e.state, EnemyShinobi.State.FIGHT, "a reeling enemy can't be chain-staggered")
	# A big blow still sends it flying.
	e.take_hit(30.0, Element.NONE, player)
	assert_eq(e.state, EnemyShinobi.State.STAGGERED)


func test_enemies_in_a_crowd_take_turns() -> void:
	await _load()
	var es: Array[EnemyShinobi] = []
	for i in 4:
		es.append(_spawn(&"genin", Element.FIRE, player.global_position + Vector3(i * 2 - 3, 0, -9)))
	await _await_fight(es[0])
	for e in es:
		e.set_physics_process(false)
	var wait := ceili(AttackTokens.START_GAP * 60.0) + 2
	assert_true(AttackTokens.may_attack(es[0], false), "nobody else is attacking")
	es[1]._start_aim()
	assert_false(AttackTokens.may_attack(es[0], false), "too soon after the first attack began")
	await physics_frames(wait)
	assert_true(AttackTokens.may_attack(es[0], false), "a second may go")
	es[2]._enter(EnemyShinobi.State.WEAVING)
	es[2]._attack_frame = Engine.get_physics_frames()
	await physics_frames(wait)
	assert_false(AttackTokens.may_attack(es[0], false), "two attacks at once are the limit")
	assert_false(AttackTokens.may_attack(es[0], true))
	es[1]._enter(EnemyShinobi.State.FIGHT)
	es[2]._enter(EnemyShinobi.State.FIGHT)
	es[3]._rush = 2.0
	assert_false(AttackTokens.may_attack(es[0], true), "one fighter at a time runs in")
	assert_true(AttackTokens.may_attack(es[0], false), "while others can still throw")
	es[0].title_override = "Boss"
	assert_true(AttackTokens.may_attack(es[0], true), "a boss isn't made to wait")
	es[0].title_override = ""
	es[0].team = &"player"
	assert_true(AttackTokens.may_attack(es[0], true), "allies aren't limited")


func test_a_runner_in_gets_to_swing() -> void:
	await _load()
	var e := _spawn(&"genin", Element.FIRE, player.global_position + Vector3(0, 0, -8))
	await _await_fight(e)
	e._rush = EnemyShinobi.RUSH_TIME
	e._melee_cd = 0.0
	var swung := false
	for i in 150:
		await physics_frames(1)
		if e.state == EnemyShinobi.State.WINDUP:
			swung = true
			break
	assert_true(swung, "it closes the distance and winds up instead of circling at arm's length")


func test_a_crowd_fans_out_instead_of_stacking() -> void:
	await _load()
	var base := player.global_position
	# Four on nearly the same bearing.
	var es: Array[EnemyShinobi] = []
	for i in 4:
		es.append(_spawn(&"genin", Element.WIND, base + Vector3(i * 0.5, 0, -8 - i * 0.6)))
	await physics_frames(260)
	var closest := INF
	for i in es.size():
		for j in range(i + 1, es.size()):
			closest = minf(closest, es[i].global_position.distance_to(es[j].global_position))
	assert_true(closest > 1.4, "no two stand on top of each other (closest %.2f m)" % closest)


func test_an_enemy_can_be_locked_on_only_once_it_has_stepped_out_of_the_smoke() -> void:
	await _load()
	var e := _spawn(&"genin", Element.FIRE, player.global_position + Vector3(0, 0, -8))
	await physics_frames(5)
	assert_false(e.is_in_group(&"lockable"), "still spawning (and untouchable)")
	assert_eq(e.take_hit(10.0, Element.NONE, player), 0.0)
	await _await_fight(e)
	assert_true(e.is_in_group(&"lockable"))


func test_chunin_have_the_jutsu_of_their_nature() -> void:
	var earth := EnemyShinobi.jutsu_for(Element.EARTH, EnemyShinobi.RANKS[&"chunin"]["max_cost"])
	var ids := earth.map(func(j: JutsuDefinition) -> StringName: return j.id)
	assert_true(ids.has(&"quake_stomp"), "earth chunin stomp instead of falling back on a bolt")
	var fire := EnemyShinobi.jutsu_for(Element.FIRE, EnemyShinobi.RANKS[&"genin"]["max_cost"])
	assert_false(fire.map(func(j: JutsuDefinition) -> StringName: return j.id).has(&"sunfall_orb"), "the big fireball stays a jonin's")


func test_trial_enemies_never_appear_in_the_players_lap() -> void:
	await _load()
	var d := TrialDirector.new()
	scene.add_child(d)
	d.player = player
	player.global_position = Vector3(0, 0.1, d.arena_radius - 1.5)
	# Looking outward, toward the arena's edge.
	player.camera_rig.yaw = PI
	for i in 3:
		var at := d.spawn_point(i, 3)
		var flat := Vector2(at.x - player.global_position.x, at.z - player.global_position.z)
		assert_true(flat.length() >= TrialDirector.MIN_SPAWN_DISTANCE - 0.01, "spawn %d is %.1f m away" % [i, flat.length()])
		assert_true(Vector2(at.x, at.z).length() <= d.arena_radius + 0.01, "and inside the arena")
