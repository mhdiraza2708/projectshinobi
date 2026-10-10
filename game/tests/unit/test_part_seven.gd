extends TestCase
## Part Seven, "The Hollow Court": every mission can be played from its pillar
## to the end, in the world, with the fighters knocked out as they appear.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player
var world: OpenWorld


func before_each() -> void:
	Profile.persist = false
	Profile.reset()
	Game.reset_records()
	Quests.reload()


func after_each() -> void:
	Engine.time_scale = 1.0
	if is_instance_valid(scene):
		scene.queue_free()
	Game.reset_records()
	Profile.reset()


func _load() -> void:
	Game.start_mode = Game.Mode.TITLE
	scene = Scene.instantiate()
	root.add_child(scene)
	await physics_frames(2)
	scene.instant_world = true
	await scene.start_world()
	world = scene.world
	player = scene.player
	await physics_frames(3)


## Plays a mission through: dialogue clicked past, every hostile fighter
## knocked out, until it finishes and you are back in the world.
func _play(id: String) -> void:
	await _load()
	var chapter := world.story.chapter(id)
	for c: Dictionary in world.story.chapters:
		if int(c["number"]) < int(chapter["number"]):
			Game.mark_chapter_done(c["id"])
	for b: Dictionary in chapter["beats"]:
		if b["do"] == "survive":
			b["seconds"] = 2.0
	world.refresh()
	Engine.time_scale = 4.0
	scene.start_story_in_world(id)
	await physics_frames(3)
	var finished := []
	scene.story_director.chapter_finished.connect(func(c: Dictionary) -> void: finished.append(c["id"]))
	for i in 9000:
		if scene.dialogue.is_open():
			scene.dialogue.advance()
			scene.dialogue.advance()
		for e: Node in scene.find_children("*", "EnemyShinobi", true, false):
			var foe := e as EnemyShinobi
			if foe.team != &"player" and foe.state != EnemyShinobi.State.SPAWNING and foe.state != EnemyShinobi.State.DEFEATED:
				foe.take_hit(99999.0, Element.NONE, player)
		if not finished.is_empty():
			break
		await physics_frames(1)
	assert_eq(finished, [id], "%s finishes (stuck at beat %d)" % [id, scene.story_director.beat_index])
	for i in 600:
		if scene.mode == Game.Mode.WORLD:
			break
		await physics_frames(1)
	assert_eq(scene.mode, Game.Mode.WORLD, "and you are back in the world")


func test_the_part_has_six_missions_that_cross_the_islands() -> void:
	var story := Story.load_all()
	var missions := story.missions_in(7)
	assert_eq(missions.size(), 6)
	var islands := {}
	for c: Dictionary in missions:
		islands[c["island"]] = true
		var bosses: Array = c["beats"].filter(func(b: Dictionary) -> bool: return b["do"] == "boss")
		for b: Dictionary in bosses:
			assert_true((b["specials"] as Array).size() >= 1, "%s: the boss has signature attacks" % c["id"])
	assert_eq(islands.size(), 6, "one on every island")
	var final: Dictionary = missions[5]
	assert_true(final["beats"].any(func(b: Dictionary) -> bool: return b["do"] == "banner"), "it ends with a banner")


func test_1_the_seventh_lantern() -> void:
	await _play("m19_seventh_lantern")


func test_2_ink_in_the_maples() -> void:
	await _play("m20_ink_in_the_maples")


func test_3_the_ash_blades_debt() -> void:
	await _play("m21_ash_blades_debt")


func test_4_the_drowned_ledger() -> void:
	await _play("m22_drowned_ledger")


func test_5_whiteout() -> void:
	await _play("m23_whiteout")


func test_6_the_hollow_court() -> void:
	await _play("m24_hollow_court")
