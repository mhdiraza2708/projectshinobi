extends TestCase
## The player's jump with a Mixamo jump clip: the body leaves the ground the
## same frame as without one, and the clips only change how it looks.

const Scene := preload("res://scenes/training_ground.tscn")
const FIXTURES := "res://tests/fixtures/mixamo"
const NO_CLIPS := "res://tests/fixtures/no_clips_here"

var player: Player


func before_each() -> void:
	var scene := Scene.instantiate()
	root.add_child(scene)
	player = scene.player


func after_each() -> void:
	Input.action_release(&"jump")


func _use_clips(dir: String) -> void:
	player.model.clip_dir = dir
	player.model.load_model(player.model.loaded_path)
	await physics_frames(2)


## Physics frames from pressing jump until the body is off the ground.
func _frames_to_leave() -> int:
	await physics_frames(10)
	Input.action_press(&"jump")
	var frames := 0
	while player.is_on_floor() and frames < 20:
		await physics_frames(1)
		frames += 1
	Input.action_release(&"jump")
	return frames


func test_the_jump_leaves_the_ground_on_the_same_frame_with_or_without_the_clip() -> void:
	await _use_clips(NO_CLIPS)
	assert_false(player.animator.has_jump_phases())
	var before := await _frames_to_leave()
	assert_true(before <= 3, "it jumps at once (%d frames)" % before)
	await seconds(1.5)
	await _use_clips(FIXTURES)
	assert_true(player.animator.has_jump_phases(), "now with the Mixamo jump")
	var after := await _frames_to_leave()
	assert_eq(after, before, "the same frame")
	assert_near(player.velocity.y, player.jump_velocity - player.gravity * 0.05, 3.0, "and as fast")
	await seconds(0.12)
	assert_eq(player.animator.current_clip(), &"jump", "the clip takes over from the push-off")
	var p := player.model.poser._target_params()
	assert_false(p["use_legs"], "the legs are the clip's in the air")
