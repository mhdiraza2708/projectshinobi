extends TestCase
## Weaving by hand, the camera comes round and in so the hand seals show, and
## goes back exactly where it was after; quick-casts and the setting leave it be.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player
var rig: CameraRig


func before_each() -> void:
	Settings.persist = false
	Settings.set_value(&"weave_camera", true)


func after_each() -> void:
	Input.action_release(&"weave")
	Settings.set_value(&"weave_camera", true)
	if is_instance_valid(scene):
		scene.queue_free()


func _load() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	rig = player.camera_rig
	await physics_frames(5)


func test_weaving_brings_the_camera_round_and_in_and_back() -> void:
	await _load()
	var length := rig.spring.spring_length
	var yaw := rig.yaw
	Input.action_press(&"weave")
	player._begin_weave()
	await physics_frames(40)
	assert_near(rig.weave, 1.0, 0.01, "eased in")
	assert_true(rig.spring.spring_length < length - 0.3, "closer (%.2f from %.2f)" % [rig.spring.spring_length, length])
	assert_near(absf(angle_difference(rig.yaw, rig.rotation.y)), CameraRig.WEAVE_TURN, 0.05, "round to the side")
	assert_near(rig.yaw, yaw, 0.001, "the orbit itself is untouched (aim stays put)")
	Input.action_release(&"weave")
	await physics_frames(60)
	assert_eq(player.state, Player.State.FREE)
	assert_near(rig.weave, 0.0, 0.001, "eased out")
	assert_near(rig.spring.spring_length, length, 0.001, "back to its own length")
	assert_near(angle_difference(rig.yaw, rig.rotation.y), 0.0, 0.001, "and behind you again")


func test_a_quick_cast_leaves_the_camera_be() -> void:
	await _load()
	var jutsu: JutsuDefinition = JutsuRegistry.all()[0]
	player.stats.chakra = player.stats.max_chakra
	player._auto_jutsu = jutsu
	player._auto_queue = jutsu.seals.duplicate()
	player._enter(Player.State.AUTO_WEAVING)
	for i in 20:
		assert_near(rig.weave, 0.0, 0.001, "never comes in")
		await physics_frames(1)


func test_the_setting_turns_it_off() -> void:
	await _load()
	Settings.set_value(&"weave_camera", false)
	Input.action_press(&"weave")
	player._begin_weave()
	await physics_frames(30)
	assert_near(rig.weave, 0.0, 0.001)


func test_a_conversation_takes_the_camera_from_a_weave() -> void:
	await _load()
	var length := rig.spring.spring_length
	Input.action_press(&"weave")
	player._begin_weave()
	await physics_frames(30)
	var someone := Node3D.new()
	scene.add_child(someone)
	someone.global_position = player.global_position + Vector3(0, 0, -4)
	rig.begin_conversation(someone)
	assert_near(rig.weave, 0.0, 0.001, "dropped at once")
	rig.end_conversation()
	assert_near(rig.spring.spring_length, length, 0.001, "and the arm's length is the player's own")
	someone.queue_free()
