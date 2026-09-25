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
	assert_true(e.model.gear.attachments().size() > 0, "clone gear fitted")
	assert_false(e.jutsu_list.is_empty(), "has jutsu")
	for j in e.jutsu_list:
		assert_eq(j.element, Element.WIND)


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
	var shots := 0
	scene.child_entered_tree.connect(func(n: Node) -> void:
		if n is JutsuProjectile and n.caster == e:
			shots += 1)
	var before := player.stats.health
	await physics_frames(420)
	assert_true(shots > 0 or player.stats.health < before, "it threw, cast or struck within 7 s")


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
