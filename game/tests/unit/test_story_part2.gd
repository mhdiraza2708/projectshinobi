extends TestCase
## Part Two mechanics: allies, survive beats, interrupt drills, weather,
## the oversized possessed boss and the Five-Nature Seal.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player


func before_each() -> void:
	seed(7)


func after_each() -> void:
	for action: StringName in DefaultBindings.table():
		Input.action_release(action)


func _load() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	await physics_frames(3)


func _jump_to(kind: String, nth := 0) -> void:
	var beats: Array = scene.story_director.chapter["beats"]
	var found := -1
	var seen := 0
	for i in beats.size():
		if beats[i]["do"] == kind:
			if seen == nth:
				found = i
				break
			seen += 1
	scene.dialogue.visible = false
	scene.story_director.beat_index = found - 1
	scene.story_director._next()


func _director() -> StoryDirector:
	return scene.story_director


func test_ally_fights_enemies_and_ignores_friendly_fire() -> void:
	await _load()
	scene.start_story("ch7_wood", true)
	await physics_frames(2)
	_jump_to("ally")
	await physics_frames(2)
	var asahi: EnemyShinobi = _director().allies["asahi"]
	assert_true(asahi.is_ally() and asahi.is_in_group(&"player"))
	assert_false(asahi.is_in_group(&"lockable"), "you can't lock on to allies")
	assert_eq(Combat.apply_hit(asahi, 50.0, Element.NONE, player), 0.0, "no friendly fire")
	var foe := EnemyShinobi.new()
	foe.position = asahi.global_position + Vector3(0, 0, -3)
	scene.add_child(foe)
	player.global_position = asahi.global_position + Vector3(0, 0, 25)
	await physics_frames(ceili(EnemyShinobi.SPAWN_TIME * 60.0) + 5)
	assert_true(asahi.pick_target() == foe, "ally hunts the enemy")
	assert_true(foe.pick_target() == asahi, "a far-away player means the enemy turns on the ally")
	assert_true(foe.take_hit(10.0, Element.NONE, asahi) > 0.0, "allies can hurt enemies")


func test_ally_returns_after_a_lost_fight() -> void:
	await _load()
	scene.start_story("ch7_wood", true)
	await physics_frames(2)
	_jump_to("ally")
	await physics_frames(2)
	var asahi: EnemyShinobi = _director().allies["asahi"]
	asahi.dismiss()
	assert_false(_director().allies.has("asahi"), "retreated")
	_jump_to("fight")
	await physics_frames(2)
	player.take_hit(1000.0, Element.NONE, null)
	_director().retry()
	await physics_frames(3)
	assert_true(_director().allies.has("asahi") and is_instance_valid(_director().allies["asahi"]), "back for the retry")
	assert_eq(_director().current_beat()["do"], "fight")


func test_survive_beat_ends_when_time_runs_out() -> void:
	await _load()
	scene.start_story("ch8_dam", true)
	await physics_frames(2)
	_jump_to("survive")
	assert_true(_director().survive_left > 40.0)
	await physics_frames(ceili(EnemyShinobi.SPAWN_TIME * 60.0) + 60)
	var foes := scene.find_children("*", "EnemyShinobi", true, false).filter(
		func(e: EnemyShinobi) -> bool: return not e.is_ally() and not e.is_defeated())
	assert_true(foes.size() >= 1 and foes.size() <= 3, "enemies keep coming, capped (%d)" % foes.size())
	assert_true(scene.hud.objective().contains("Hisame"), scene.hud.objective())
	_director().survive_left = 0.05
	await physics_frames(20)
	assert_eq(_director().survive_left, 0.0)
	assert_true(_director().current_beat()["do"] != "survive", "moved on")
	await physics_frames(2)
	for e: EnemyShinobi in foes:
		assert_true(not is_instance_valid(e) or e.is_defeated(), "clones cleared")


func test_interrupt_drill_counts_only_real_interrupts() -> void:
	await _load()
	scene.start_story("ch6_rain", true)
	await physics_frames(2)
	_jump_to("task")
	await physics_frames(2)
	assert_eq(_director().drills.size(), 1, "a practice clone appears")
	var clone: EnemyShinobi = _director().drills[0]
	assert_true(clone.drill)
	await physics_frames(ceili(EnemyShinobi.SPAWN_TIME * 60.0) + 5)
	clone.take_hit(1.0, Element.NONE, player)
	assert_eq(_director().task_done, 0, "a hit outside a weave doesn't count")
	clone._start_weave(clone.jutsu_list[0])
	await physics_frames(2)
	clone.take_hit(5.0, Element.NONE, player)
	assert_eq(_director().task_done, 1, "interrupting counts")
	clone.dismiss()
	await physics_frames(70)
	assert_eq(_director().drills.size(), 1, "a fallen practice clone is replaced")


func test_weather_particles_and_sound() -> void:
	await _load()
	for kind in ["rain", "snow", "leaves", "storm"]:
		scene.set_weather(kind)
		assert_true(scene.weather_particles != null and scene.weather_particles.amount > 0, kind)
		assert_true(Sfx.is_looping(&"weather"), "%s ambience" % kind)
	scene._next_flash = 0.0
	for i in 3:
		await root.get_tree().process_frame
	assert_true(scene._next_flash > 5.0, "a storm flashes lightning")
	scene.set_weather("none")
	assert_true(scene.weather_particles == null)
	assert_false(Sfx.is_looping(&"weather"))


func test_possessed_boss_is_bigger_and_sealing_ends_it() -> void:
	await _load()
	scene.start_story("ch10_nue", true)
	await physics_frames(2)
	_jump_to("ally")
	await physics_frames(4)
	assert_eq(_director().current_beat()["do"], "boss", "allies join, then the boss")
	var nue: EnemyShinobi = _director().boss
	assert_near(nue.size, 1.35)
	var capsule := (nue.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
	assert_near(capsule.height, 1.75 * 1.35, 0.001, "bigger body")
	assert_true(nue.aura_color.a > 0.0)
	assert_true(_director().allies.size() == 2, "Asahi and Tsumugi fight beside you")
	await physics_frames(ceili(EnemyShinobi.SPAWN_TIME * 60.0) + 5)
	nue.take_hit(99999.0, Element.NONE, player)
	for i in 300:
		await physics_frames(1)
		if scene.dialogue.is_open():
			scene.dialogue.advance()
			scene.dialogue.advance()
		if _director().current_beat().get("do") == "task":
			break
	assert_eq(_director().task["jutsu"], &"five_nature_seal")
	var seal := JutsuRegistry.get_jutsu(&"five_nature_seal")
	assert_eq(seal.seals.size(), 5)
	player.stats.chakra = player.stats.max_chakra
	assert_true(player.caster.cast(seal), "the seal can be cast")
	await physics_frames(60)
	assert_true(_director().current_beat().get("do") != "task", "sealing moves the story on")
