extends TestCase
## The short films that open and close fights: a boss's entrance, an
## ambush's opening, the slow-motion finish. They hold the boss still and the
## HUD away, can be skipped, play once (not again on a retry) and can be
## switched off.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player
var world: OpenWorld
var _saved_layout: Variant


func before_each() -> void:
	seed(99)
	FightCinema.enabled = true
	Profile.persist = false
	Settings.persist = false
	Profile.reset()
	Game.reset_records()
	Quests.reload()
	_saved_layout = Settings.get_value(&"world_layout")
	Settings.set_value(&"world_layout", "continent")
	Settings.set_value(&"fight_cutscenes", true)


func after_each() -> void:
	FightCinema.enabled = false
	Engine.time_scale = 1.0
	if is_instance_valid(scene):
		scene.queue_free()
	Settings.set_value(&"world_layout", _saved_layout)
	Game.reset_records()
	Profile.reset()


func _load_story() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	await physics_frames(5)


func _load_world() -> void:
	Game.start_mode = Game.Mode.TITLE
	scene = Scene.instantiate()
	root.add_child(scene)
	await physics_frames(2)
	scene.instant_world = true
	await scene.start_world()
	world = scene.world
	player = scene.player
	await physics_frames(3)


func _jump_to(kind: String) -> void:
	var beats: Array = scene.story_director.chapter["beats"]
	scene.dialogue.visible = false
	scene.story_director.beat_index = beats.find_custom(func(b: Dictionary) -> bool: return b["do"] == kind) - 1
	scene.story_director._next()


## The story's own opening scene would be "active" too: skip it first.
func _start_chapter(id: String) -> void:
	scene.start_story(id, true)
	await physics_frames(2)
	for i in 600:
		if Cutscene.active == null:
			break
		Cutscene.active.skip()
		await physics_frames(1)
	await physics_frames(2)


func _film_playing() -> bool:
	return Cutscene.active != null and Cutscene.active.film


## Waits (in frames) until no film is playing.
func _until_film_ends(limit := 1800) -> void:
	for i in limit:
		if not _film_playing():
			return
		await physics_frames(1)


func test_the_builders_make_steps_the_player_understands() -> void:
	for steps: Array in [FightCinema.boss_entrance("炎  Kagerou", "Hunter", Color.RED), FightCinema.ambush("Fight", "3 waves", Color.RED),
			FightCinema.finish(Color.RED)]:
		assert_true(steps.size() >= 2)
		for s: Dictionary in steps:
			assert_true(["cam", "title", "sfx", "fx"].has(s["action"]), "a known step: %s" % s["action"])
			assert_true(s.has("async"))
			if s["action"] == "cam":
				assert_true(Story.SHOTS.has(s["cam"]) and s["seconds"] > 0.0)
			if s["action"] == "sfx":
				assert_true(ResourceLoader.exists("res://assets/audio/sfx/%s.wav" % s["sound"]), "sound %s exists" % s["sound"])
	var total := 0.0
	for s: Dictionary in FightCinema.boss_entrance("x", "y", Color.RED):
		if s["action"] == "cam" and not s["async"]:
			total += float(s["seconds"])
	assert_true(total >= 5.0 and total <= 8.0, "an entrance is a few seconds (%.1f)" % total)


func test_a_story_boss_enters_under_a_film_with_the_boss_held_and_the_hud_away() -> void:
	await _load_story()
	await _start_chapter("ch5_kagerou")
	_jump_to("boss")
	await physics_frames(5)
	var boss: EnemyShinobi = scene.story_director.boss
	assert_true(_film_playing(), "the film is playing")
	assert_true(boss != null and boss.hold, "the boss waits")
	await physics_frames(ceili(EnemyShinobi.SPAWN_TIME * 60.0) + 20)
	assert_eq(boss.state, EnemyShinobi.State.SPAWNING, "still unhittable well after it would have started")
	assert_false(scene.hud.boss_shown(), "no boss bar yet")
	assert_false(player.input_enabled, "and you cannot move")
	Cutscene.active.skip()
	await _until_film_ends()
	assert_false(boss.hold, "released")
	assert_true(scene.hud.boss_shown(), "the boss bar is up")
	assert_true(player.input_enabled and scene.hud.visible, "you have the fight")
	await physics_frames(10)
	assert_true(boss.state != EnemyShinobi.State.SPAWNING, "and it fights")


func test_the_film_plays_once_and_not_again_on_a_retry() -> void:
	await _load_story()
	await _start_chapter("ch2_rival")
	_jump_to("boss")
	await physics_frames(5)
	assert_true(_film_playing())
	Cutscene.active.skip()
	await _until_film_ends()
	player.take_hit(1000.0, Element.NONE, null)
	await physics_frames(100)
	scene._on_results_primary()
	await physics_frames(10)
	assert_true(scene.story_director.boss != null, "the fight restarted")
	assert_false(_film_playing(), "straight in, no second film")
	assert_false(scene.story_director.boss.hold)


func test_a_boss_falls_in_slow_motion_and_the_game_speeds_up_again() -> void:
	await _load_story()
	await _start_chapter("ch5_kagerou")
	_jump_to("boss")
	await physics_frames(5)
	Cutscene.active.skip()
	await _until_film_ends()
	await physics_frames(ceili(EnemyShinobi.SPAWN_TIME * 60.0) + 10)
	var boss: EnemyShinobi = scene.story_director.boss
	boss.take_hit(99999.0, Element.NONE, player)
	await physics_frames(4)
	assert_near(Engine.time_scale, FightCinema.FINISH_SPEED, 0.001, "slow motion for the last blow")
	assert_true(_film_playing(), "under a film")
	Cutscene.active.skip()
	await _until_film_ends()
	assert_near(Engine.time_scale, 1.0, 0.001, "and normal speed again")


func test_switching_the_cutscenes_off_goes_straight_in() -> void:
	await _load_story()
	Settings.set_value(&"fight_cutscenes", false)
	await _start_chapter("ch5_kagerou")
	_jump_to("boss")
	await physics_frames(3)
	assert_false(_film_playing(), "no film")
	assert_true(scene.hud.boss_shown())
	assert_false(scene.story_director.boss.hold)


func test_a_wave_fight_opens_with_an_ambush_film() -> void:
	await _load_story()
	await _start_chapter("m19_seventh_lantern")
	_jump_to("fight")
	await physics_frames(5)
	assert_true(_film_playing(), "the ambush film plays first")
	assert_true(scene.story_director.fight == null, "and the waves wait for it")
	Cutscene.active.skip()
	await _until_film_ends()
	await physics_frames(5)
	assert_true(scene.story_director.fight != null, "then they begin")


func test_a_wanted_shinobi_makes_an_entrance_in_the_open_world() -> void:
	await _load_world()
	var lair := world.sites.plan.of_kind("lair")[0]
	var node := world.sites.build_site(lair["id"])
	await world._put_player_at(node.spot("den") + Vector3(12, 0, 0))
	world.sites.update()
	await physics_frames(3)
	for i in 40:
		if not world.dialogue.is_open():
			break
		world.dialogue.advance()
		world.dialogue.advance()
		await physics_frames(1)
	await physics_frames(5)
	var e := world._duelist
	assert_true(e != null and e.hold, "the duelist waits for the film")
	assert_true(_film_playing())
	assert_false(scene.hud.boss_shown())
	Cutscene.active.skip()
	await _until_film_ends()
	assert_false(e.hold)
	assert_true(scene.hud.boss_shown(), "then the fight")
	assert_true(world.busy and player.input_enabled)


func test_a_camp_ambush_has_its_film_too_and_only_once() -> void:
	await _load_world()
	var camp := world.sites.plan.of_kind("camp")[0]
	var node := world.sites.build_site(camp["id"])
	await world._put_player_at(node.spot("fire") + Vector3(8, 0, 0))
	world.sites.update()
	await physics_frames(5)
	assert_true(_film_playing(), "the film")
	assert_true(world._fight == null, "the raiders wait for it")
	Cutscene.active.skip()
	await _until_film_ends()
	await physics_frames(5)
	assert_true(is_instance_valid(world._fight), "then they attack")
	# Lose and try again: no second film.
	world._on_player_defeated()
	await seconds(2.5)
	await world._put_player_at(node.spot("fire") + Vector3(8, 0, 0))
	await physics_frames(5)
	assert_false(_film_playing(), "no second film for the same camp")
