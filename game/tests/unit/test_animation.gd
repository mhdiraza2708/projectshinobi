extends TestCase
## Motion-captured clips (Universal Animation Library, CC0) retargeted onto
## the humanoid skeleton: gaits by speed, punches, casts, flinches, a fall
## and a talking idle, on every roster rig, with the procedural layer on top.

const Scene := preload("res://scenes/training_ground.tscn")

var model: CharacterModel


func _model(path := CharacterModel.DEFAULT_MODEL) -> CharacterModel:
	model = CharacterModel.new()
	model.model_path = path
	root.add_child(model)
	return model


func after_each() -> void:
	if is_instance_valid(model):
		model.queue_free()


func _frames(n: int) -> void:
	for i in n:
		await root.get_tree().process_frame


func _bone(bone: StringName) -> Vector3:
	var skel := model.skeleton
	return model.to_local(skel.global_transform * skel.get_bone_global_pose(skel.find_bone(bone)).origin)


func test_the_library_holds_every_clip_the_game_uses() -> void:
	var lib := CharacterAnimator.load_library(CharacterAnimator.CLIP_DIR)
	for clip: StringName in CharacterAnimator.CLIP_SOURCES:
		assert_true(lib.has_animation(clip), "%s is there" % clip)
		if lib.has_animation(clip):
			var anim := lib.get_animation(clip)
			assert_true(String(anim.track_get_path(0)).begins_with("%GeneralSkeleton:"), "%s is retargeted" % clip)
	assert_eq(lib.get_animation(&"idle").loop_mode, Animation.LOOP_LINEAR, "idle loops")
	assert_eq(lib.get_animation(&"strike_1").loop_mode, Animation.LOOP_NONE, "a punch doesn't")


func test_gait_follows_speed() -> void:
	_model()
	await _frames(2)
	var anim := model.animator
	var cases := [[0.0, &"idle"], [0.12, &"walk"], [0.5, &"run"], [1.0, &"sprint"], [1.7, &"sprint"]]
	for c: Array in cases:
		anim.speed_ratio = c[0]
		await _frames(2)
		assert_eq(anim.current_clip(), c[1], "at speed ratio %.2f" % c[0])
		var scale := anim.clips.speed_scale
		assert_true(scale >= CharacterAnimator.GAIT_SPEED_RANGE.x and scale <= CharacterAnimator.GAIT_SPEED_RANGE.y,
			"playback speed %.2f stays believable" % scale)


func test_walking_feet_keep_pace_with_the_ground() -> void:
	# At the walk's own pace the clip plays at its natural speed.
	_model()
	await _frames(2)
	var anim := model.animator
	anim.speed_ratio = CharacterAnimator.STRIDE[&"walk"] * model.poser.leg_length() / anim.run_speed
	await _frames(2)
	assert_eq(anim.current_clip(), &"walk")
	assert_near(anim.clips.speed_scale, 1.0, 0.05)


func test_standing_strikes_are_punches_and_moving_ones_are_arm_swings() -> void:
	_model()
	await _frames(2)
	var anim := model.animator
	anim.strike()
	assert_eq(anim.current_clip(), &"strike_2", "a cross (alternating with the jab)")
	anim.strike()
	assert_eq(anim.current_clip(), &"strike_1", "then a jab")
	await seconds(0.7)
	assert_eq(anim.current_clip(), &"idle", "back to the stance when it's done")
	anim.speed_ratio = 1.0
	await _frames(2)
	anim.strike()
	assert_eq(anim.current_clip(), &"sprint", "running legs keep running")
	assert_true(model.poser._strike_t > 0.0, "the arms punch on their own")


func test_casting_and_flinching() -> void:
	_model()
	await _frames(2)
	var anim := model.animator
	anim.cast()
	assert_eq(anim.current_clip(), &"cast", "palms out as the jutsu leaves")
	anim.hit()
	assert_eq(anim.current_clip(), &"hit", "a blow cuts in")
	anim.hit(true)
	assert_eq(anim.current_clip(), &"hit_head", "a heavy one snaps the head back")
	anim.pose = HumanoidPoser.Pose.GUARD
	assert_eq(anim._action, &"", "raising a guard cuts an action short")
	anim.pose = HumanoidPoser.Pose.LOCOMOTION
	anim.speed_ratio = 0.8
	anim.cast()
	assert_true(model.poser._cast_t > 0.0, "on the move, the arms alone push the jutsu out")


func test_falling_holds_until_revived() -> void:
	_model()
	await _frames(2)
	var anim := model.animator
	assert_true(anim.die(), "there is a fall")
	await seconds(0.5)
	anim.speed_ratio = 1.0
	await _frames(5)
	assert_eq(anim.current_clip(), &"death", "stays down whatever else happens")
	anim.strike()
	assert_eq(anim.current_clip(), &"death")
	anim.revive()
	anim.speed_ratio = 0.0
	await _frames(2)
	assert_eq(anim.current_clip(), &"idle", "up again")


func test_speakers_gesture() -> void:
	_model()
	await _frames(2)
	model.animator.talking = true
	await _frames(2)
	assert_eq(model.animator.current_clip(), &"talk")
	model.animator.speed_ratio = 0.5
	await _frames(2)
	assert_eq(model.animator.current_clip(), &"run", "walking off ends the gestures")


func test_every_roster_rig_takes_the_clips() -> void:
	for entry: Dictionary in CharacterModel.roster():
		if entry["path"] == CharacterModel.PLACEHOLDER_MODEL:
			continue
		_model(entry["path"])
		await _frames(2)
		assert_true(model.animator.clips != null, "%s plays clips" % entry["name"])
		model.animator.speed_ratio = 0.5
		var swing := 0.0
		var lo := INF
		for i in 24:
			await model.skeleton.skeleton_updated
			var z := _bone(&"LeftFoot").z - _bone(&"RightFoot").z
			swing = maxf(swing, absf(z))
			lo = minf(lo, _bone(&"Hips").y - maxf(_bone(&"LeftFoot").y, _bone(&"RightFoot").y))
		assert_true(swing > 0.15, "%s: legs stride (%.2f)" % [entry["name"], swing])
		assert_true(lo > 0.2, "%s: feet stay below the hips" % entry["name"])
		model.queue_free()
		await _frames(1)


func test_a_rig_without_the_humanoid_skeleton_stays_procedural() -> void:
	_model(CharacterModel.PLACEHOLDER_MODEL)
	await _frames(2)
	if model.skeleton.get_node_or_null(^"%GeneralSkeleton") == null and model.instance.get_node_or_null(^"%GeneralSkeleton") == null:
		assert_true(model.animator.clips == null, "no clips without the skeleton they target")
	model.animator.strike()
	assert_eq(model.animator.current_clip(), &"" if model.animator.clips == null else model.animator.current_clip())


func test_the_player_flinches_falls_and_gets_up() -> void:
	var scene := Scene.instantiate()
	root.add_child(scene)
	await _frames(3)
	var player: Player = scene.player
	var anim := player.animator
	player.take_hit(5.0, Element.NONE, null)
	assert_eq(anim.current_clip(), &"hit", "a flinch")
	player.stats.take_damage(9999.0, Element.NONE)
	await _frames(2)
	assert_eq(anim.current_clip(), &"death", "a fall")
	assert_near(player.model.rotation.x, 0.0, 0.001, "not toppled like a plank as well")
	player.revive()
	await _frames(3)
	assert_true(anim.current_clip() != &"death", "back on their feet")
	scene.queue_free()


func test_cutscene_walks_walk_and_runs_run() -> void:
	# Story characters are moved at Cutscene.WALK_SPEED / RUN_SPEED.
	for path: String in [CharacterModel.DEFAULT_MODEL, "res://assets/characters/roster/sakurada_fumiriya.vrm"]:
		_model(path)
		await _frames(2)
		var anim := model.animator
		anim.run_speed = Cutscene.RUN_SPEED
		anim.speed_ratio = Cutscene.WALK_SPEED / Cutscene.RUN_SPEED
		await _frames(2)
		assert_eq(anim.current_clip(), &"walk", "%s walks" % path.get_file())
		anim.speed_ratio = 1.0
		await _frames(2)
		assert_true(anim.current_clip() in [&"run", &"sprint"], "%s runs" % path.get_file())
		model.queue_free()
		await _frames(1)


func test_a_jutsu_released_from_the_weave_plays_the_cast() -> void:
	_model()
	await _frames(2)
	var anim := model.animator
	anim.pose = HumanoidPoser.Pose.WEAVE
	await _frames(2)
	anim.cast()
	anim.pose = HumanoidPoser.Pose.LOCOMOTION
	await _frames(2)
	assert_eq(anim.current_clip(), &"cast", "the weave ends in the palms-out release")
