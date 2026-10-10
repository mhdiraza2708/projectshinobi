extends TestCase
## The scenes that show the player, framed for the main character (a Tripo
## model with no irises, hair over the eyes and its own height): the skill
## screen's stage, the ultimate's close-up and the dojutsu glow. Each is
## measured from the model, so it holds for any humanoid.

const Scene := preload("res://scenes/training_ground.tscn")
const SIZE := Vector2i(1280, 720)

var scene: Node3D
var stage: SkillStage


func before_each() -> void:
	Profile.persist = false
	Profile.reset()


func after_each() -> void:
	if is_instance_valid(stage):
		stage.queue_free()
	if is_instance_valid(scene):
		scene.queue_free()
	Profile.reset()


func _stage(tree: String) -> void:
	stage = SkillStage.new()
	stage.size = SIZE
	root.add_child(stage)
	stage.show_tree(tree, false)
	await physics_frames(8)


## Whether a world point lands inside the stage's frame (the camera is
## shifted right of the character by its h_offset, which the paper covers).
func _in_frame(at: Vector3, margin := 0.0) -> bool:
	var p := stage.camera.unproject_position(at)
	return p.x >= margin and p.x <= SIZE.x - margin and p.y >= margin and p.y <= SIZE.y - margin


func test_the_stage_shows_the_main_character_head_to_foot() -> void:
	await _stage("body")
	assert_true(stage.model.is_main(), "the main character stands on the stage")
	for tree in ["body", "chakra", "mind", "kenjutsu"]:
		stage.show_tree(tree, false)
		await physics_frames(4)
		var skel := stage.model.skeleton
		for bone in [&"Head", &"LeftFoot", &"RightFoot"]:
			var at := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(bone)).origin
			assert_true(_in_frame(at, 12.0), "%s: the %s is in frame" % [tree, bone])


func test_the_dojutsu_close_up_looks_at_the_eyes() -> void:
	await _stage("eye")
	var eyes := EyeArtMode.eye_point_of(stage.model)
	assert_true(eyes != Vector3.INF, "the eyes are found without irises")
	var p := stage.camera.unproject_position(eyes)
	assert_near(p.y, SIZE.y * 0.5, SIZE.y * 0.05, "the eyes are at the frame's middle height")
	# The head, hair and all, fits in the frame.
	var head := EyeArtMode.head_height_of(stage.model)
	assert_true(head > 0.15 and head < 0.45, "a head %.2f m tall" % head)
	for dy in [-head * 0.45, head * 0.45]:
		assert_true(_in_frame(eyes + Vector3(0.0, dy, 0.0)), "the head's top and chin are in frame")


func test_a_vroid_models_eyes_are_still_measured_from_its_irises() -> void:
	var m := CharacterModel.new()
	m.use_profile = false
	m.model_path = "res://assets/characters/roster/sendagaya_shino.vrm"
	root.add_child(m)
	await physics_frames(3)
	var eyes := EyeArtMode.eyes_in_head(m)
	assert_true(eyes[0] != Vector3.ZERO and eyes[1] != Vector3.ZERO, "the irises are found")
	assert_true(eyes[0].distance_to(eyes[1]) > 0.015, "and one eye is told from between them")
	var at := EyeArtMode.eye_point_of(m)
	assert_true(at != Vector3.INF and at.y > 1.2 and at.y < 1.7, "up the head (%.2f)" % at.y)
	m.queue_free()


func test_the_head_is_framed_from_where_it_is_not_a_fixed_height() -> void:
	await _stage("eye")
	var before := stage.camera.global_position
	stage.model.position.y = 0.5
	await physics_frames(3)
	var after := stage.camera.global_position
	assert_true(after.y > before.y + 0.3, "the camera follows the head up (%.2f -> %.2f)" % [before.y, after.y])


func test_a_dojutsu_glows_at_the_eyes_when_there_are_no_irises() -> void:
	Profile.set_value(&"clan", "hearth")
	Profile.set_value(&"eye_art", str(Perks.clan("hearth")["eye_arts"][0]))
	await _stage("eye")
	var glow := stage.get_node_or_null(^"EyeGlow") as OmniLight3D
	assert_true(glow != null, "a glow in the dojutsu's colour")
	var eyes := EyeArtMode.eye_point_of(stage.model)
	assert_true(glow.global_position.distance_to(eyes) < 0.5, "at the eyes")
	stage.show_tree("body", false)
	await physics_frames(3)
	assert_true(stage.get_node_or_null(^"EyeGlow") == null, "and gone on the other trees")


func test_the_ultimates_close_up_follows_the_eyes() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	await physics_frames(5)
	var seq := UltimateSequence.new()
	var player: Player = scene.player
	seq.player = player
	var height := player.model.measure_height()
	var eyes := seq._eye_point()
	assert_true(eyes.y > player.global_position.y + height * 0.75 and eyes.y < player.global_position.y + height,
		"between the eyes, up the head (%.2f of %.2f)" % [eyes.y, height])
	assert_near(seq._body_scale(), height / UltimateSequence.CLOSE_FRAMED_FOR, 0.01)
	seq.free()


func test_the_showcase_is_framed_for_the_height_it_shows() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	await physics_frames(5)
	var rig: CameraRig = scene.player.camera_rig
	var k := rig.showcase_scale()
	assert_near(k, scene.player.model.measure_height() / CameraRig.SHOWCASE_FOR, 0.01)
	rig.begin_showcase()
	assert_near(rig.spring.spring_length, 2.7 * k, 0.001, "the camera backs off for taller shinobi")
	assert_near(rig.follow_height, 1.05 * k, 0.001, "and aims at the same part of them")
	rig.end_showcase()
