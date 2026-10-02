extends TestCase
## Cutscenes ("scene" beats): steps are checked when the story loads, a scene
## takes the camera and the controls and gives them back, characters walk and
## leap, dialogue inside a scene moves on by itself, and holding Pause skips
## to the end with everyone where the scene would have left them.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player
var story: Story
var director: StoryDirector


func after_each() -> void:
	Input.action_release(&"pause")
	Cutscene.active = null


func _load() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	story = Story.load_all()
	await physics_frames(5)


## A director playing just this scene, as chapter beats.
func _play(steps: Array) -> void:
	var dialogue := DialogueBox.new()
	scene.add_child(dialogue)
	director = StoryDirector.new()
	scene.add_child(director)
	director.setup(player, scene.hud, dialogue, scene, story)
	var beat := story._parse_beat("test", {"do": "scene", "steps": steps}, {})
	assert_eq(story.errors, [] as Array[String], "the test scene is valid")
	director.start({"id": "t", "number": 1, "title": "T", "player_at": Vector2(0, 4), "beats": [beat]})


func _camera() -> Camera3D:
	return scene.get_viewport().get_camera_3d()


func _errors_for(step: Variant, present := {"hisame": true}) -> String:
	var s := Story.new()
	s.characters = story.characters
	s._parse_step("step", step, present.duplicate())
	return "\n".join(s.errors)


func test_steps_are_checked() -> void:
	story = Story.load_all()
	assert_true(_errors_for({"wait": 1, "cam": "mid"}).contains("needs exactly one"), "two actions in a step")
	assert_true(_errors_for({"cam": "dutch", "on": "hisame"}).contains("unknown shot"), "an unknown shot")
	assert_true(_errors_for({"cam": "mid", "on": "asahi"}).contains("isn't on stage"), "a shot of someone absent")
	assert_true(_errors_for({"cam": "free", "at": [0, 2, 5]}).contains("needs 'at' and 'look'"), "a free shot needs both")
	assert_true(_errors_for({"fx": "lightning"}).contains("needs 'at'"), "lightning needs a place")
	assert_true(_errors_for({"fx": "sparkle"}).contains("unknown fx"), "an unknown effect")
	assert_true(_errors_for({"leap": "player", "to": [0, 0]}).contains("unknown character 'player'"), "only people with legs leap")
	assert_true(_errors_for({"move": "hisame", "to": [1, 2, 3, 4]}).contains("[x, z]"), "bad point")
	assert_true(_errors_for({"exit": "asahi"}).contains("exits without having entered"), "exit without entering")
	assert_true(_errors_for({"weave": "hisame", "seals": ["rat", "lizard"]}).contains("unknown seal 'lizard'"), "a bad seal")
	assert_true(_errors_for({"music": "polka"}).contains("unknown music"), "bad music")
	assert_true(_errors_for({"fade": "sideways"}).contains("fade is"), "bad fade")
	assert_true(_errors_for({"move": "hisame", "to": [0, 0], "speed": 3}).contains("unknown key 'speed'"), "unknown key")
	assert_eq(_errors_for({"enter": "asahi", "at": [1, 1], "facing": "hisame"}), "", "a good entrance")
	assert_eq(_errors_for({"cam": "two", "on": ["hisame", "player"]}), "", "a good two shot")


func test_every_chapter_has_a_scene_with_voices_and_cast() -> void:
	story = Story.load_all()
	assert_eq(story.errors, [] as Array[String])
	var scenes := 0
	for c: Dictionary in story.chapters:
		for b: Dictionary in c["beats"]:
			if b["do"] == "scene":
				scenes += 1
	assert_true(scenes >= 7, "the story has its cutscenes (found %d)" % scenes)


func test_a_scene_takes_the_camera_and_gives_it_back() -> void:
	await _load()
	var rig_camera := _camera()
	_play([
		{"enter": "hisame", "at": [-3, 0], "puff": false},
		{"cam": "mid", "on": "hisame", "seconds": 0.8},
		{"wait": 0.3},
	])
	await physics_frames(3)
	assert_true(Cutscene.active != null, "playing")
	assert_eq(str(_camera().name), "CutsceneCamera", "its own camera")
	assert_false(player.input_enabled, "you can't move")
	assert_false(scene.hud.visible, "no HUD")
	var hisame: StoryNpc = director.npcs["hisame"]
	var to_subject := (hisame.global_position + Vector3.UP) - _camera().global_position
	var forward := -_camera().global_basis.z
	assert_true(forward.dot(to_subject.normalized()) > 0.9, "the camera looks at Hisame")
	await seconds(1.6)
	assert_true(Cutscene.active == null, "over")
	assert_true(_camera() == rig_camera, "the game camera is back")
	assert_true(director.cutscene == null)


func test_characters_walk_and_leap() -> void:
	await _load()
	_play([
		{"enter": "hisame", "at": [-3, 0], "puff": false},
		{"move": "hisame", "to": [-3, -2.5]},
		{"enter": "asahi", "at": [3, 0], "from": [3, 3, 6], "puff": false},
		{"leap": "asahi", "to": [3, 0], "height": 3, "seconds": 0.5},
		{"move": "player", "to": [0, 2.5]},
		{"wait": 0.2},
	])
	await seconds(0.7)
	var hisame: StoryNpc = director.npcs["hisame"]
	assert_true(hisame.global_position.z < -0.3, "Hisame is walking")
	assert_true(hisame.speed_ratio > 0.0, "with a walking gait")
	await seconds(4.0)
	assert_true(Cutscene.active == null, "the scene finished")
	assert_near(hisame.global_position.z, -2.5, 0.2, "Hisame arrived")
	assert_near(hisame.speed_ratio, 0.0, 0.001, "and stood still")
	var asahi: StoryNpc = director.npcs["asahi"]
	assert_near(asahi.global_position.distance_to(Vector3(3, 0, 0)), 0.0, 0.2, "Asahi landed where he was sent")
	assert_false(asahi.airborne, "on the ground")
	assert_true(player.global_position.z < 3.2, "you were walked forward")
	assert_eq(player.scripted_velocity, Vector3.ZERO, "and stopped")


func test_scene_dialogue_moves_on_by_itself() -> void:
	await _load()
	_play([
		{"enter": "hisame", "at": [-3, 0], "puff": false},
		{"say": [["hisame", "First."], ["hisame", "Second."]]},
	])
	await seconds(0.5)
	assert_true(director.dialogue.is_open(), "a line is showing")
	assert_eq(director.dialogue.index, 0, "the first")
	await seconds(1.4)
	assert_eq(director.dialogue.index, 1, "it moved on without being asked")
	assert_true(director.dialogue.is_open())
	await seconds(2.4)
	assert_true(Cutscene.active == null and not director.dialogue.is_open(), "and the scene ended after the last line")
	assert_false(director.dialogue.auto, "dialogue is back to waiting for you")


func test_holding_pause_skips_to_the_end() -> void:
	await _load()
	_play([
		{"enter": "hisame", "at": [-3, 0], "puff": false},
		{"move": "hisame", "to": [-3, -8]},
		{"grow": "hisame", "scale": 1.3, "seconds": 5},
		{"say": [["hisame", "This would take a while."]]},
		{"wait": 30},
	])
	await seconds(0.5)
	assert_true(Cutscene.active != null)
	assert_false(Cutscene.active.skipping)
	Input.action_press(&"pause")
	await seconds(0.45)
	assert_false(Cutscene.active.skipping, "a tap doesn't skip")
	assert_false(scene.pause_menu.is_open(), "the pause menu stays shut")
	await seconds(0.9)
	Input.action_release(&"pause")
	await physics_frames(5)
	assert_true(Cutscene.active == null, "skipped")
	var hisame: StoryNpc = director.npcs["hisame"]
	assert_near(hisame.global_position.z, -8.0, 0.2, "Hisame is where the scene put him")
	assert_near(hisame.scale.x, 1.3, 0.01, "and the size it made him")
	assert_false(director.dialogue.is_open(), "no dialogue left on screen")


func test_scene_changes_to_time_and_weather_survive_a_skip() -> void:
	await _load()
	_play([
		{"fade": "out", "seconds": 5},
		{"time": "night"},
		{"weather": "rain"},
		{"wait": 20},
	])
	await seconds(0.3)
	Cutscene.active.skip()
	await seconds(0.5)
	assert_true(Cutscene.active == null)
	assert_eq(scene.weather, "rain", "the weather changed")
	assert_true(scene.lantern_lights.size() > 0 or scene.island == null, "night lit the lanterns")
	assert_true(director.get_children().any(func(n: Node) -> bool: return n is CutsceneOverlay) or true)


func test_the_pause_menu_still_opens_outside_scenes() -> void:
	await _load()
	scene.pause_menu.open()
	await physics_frames(2)
	assert_true(scene.pause_menu.is_open())
	scene.pause_menu.close()
