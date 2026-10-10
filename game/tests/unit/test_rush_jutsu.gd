extends TestCase
## Rush jutsu (gather in the hand, then drive it in): Cyclone Core bursts at
## the first foe and throws everyone near back; Stormpiercer pierces through
## a line of them. And the over-the-shoulder camera.

const Scene := preload("res://scenes/training_ground.tscn")
const DummyScene := preload("res://scenes/training_dummy.tscn")

var scene: Node3D
var player: Player


func before_each() -> void:
	Profile.persist = false
	Profile.reset()


func after_each() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
	Settings.set_value(&"camera_style", "shoulder")
	Settings.set_value(&"camera_side", "right")
	Profile.reset()


func _load() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	await physics_frames(5)
	for dummy in scene.find_children("*", "TrainingDummy", true, false):
		dummy.free()
	player.stats.chakra = player.stats.max_chakra


## A dummy `ahead` metres in front of the player (and `aside` to their right).
func _dummy(ahead: float, aside := 0.0) -> TrainingDummy:
	var d: TrainingDummy = DummyScene.instantiate()
	d.affinity = "none"
	scene.add_child(d)
	var forward := -player.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	d.global_position = player.global_position + forward * ahead + right * aside
	return d


func _hurt(d: TrainingDummy) -> float:
	return d.stats.max_health - d.stats.health


func test_rush_jutsu_load_and_need_a_gather() -> void:
	for id: StringName in [&"cyclone_core", &"stormpiercer"]:
		var j := JutsuRegistry.get_jutsu(id)
		assert_true(j != null, "%s is in the registry" % id)
		assert_eq(j.form, JutsuDefinition.Form.RUSH)
	var errors: Array[String] = []
	var bad := JutsuDefinition.from_dict({"id": "bad_rush", "name": "Bad", "rank": "C", "element": "wind",
		"form": "rush", "seals": ["rat"], "chakra_cost": 5, "power": 10, "speed": 10, "range": 5, "radius": 1}, errors)
	assert_true(bad == null and not errors.is_empty(), "a rush without a gather is refused")


func test_enemies_never_pick_a_rush() -> void:
	for nature in [Element.WIND, Element.LIGHTNING]:
		for j in EnemyShinobi.jutsu_for(nature, 999.0):
			assert_true(j.form != JutsuDefinition.Form.RUSH, "%s" % j.id)


func test_cyclone_core_gathers_then_drives_in_and_bursts() -> void:
	await _load()
	var start := player.global_position
	var target := _dummy(6.0)
	var near := _dummy(6.5, 1.6)
	assert_true(player.caster.cast(JutsuRegistry.get_jutsu(&"cyclone_core"), target))
	assert_eq(player.state, Player.State.RUSHING)
	await physics_frames(15)
	assert_near(player.global_position.distance_to(start), 0.0, 0.3, "planted while it gathers")
	assert_near(_hurt(target), 0.0, 0.01, "nothing yet")
	await physics_frames(60)
	assert_true(_hurt(target) > 0.0, "it lands on the foe ahead")
	assert_true(_hurt(near) > 0.0, "and the burst catches the one beside them")
	assert_true(player.global_position.distance_to(start) > 3.0, "the caster drove forward")
	assert_eq(player.state, Player.State.FREE, "and is free again")


func test_stormpiercer_pierces_a_line_of_foes() -> void:
	await _load()
	var first := _dummy(4.0)
	var second := _dummy(9.0)
	assert_true(player.caster.cast(JutsuRegistry.get_jutsu(&"stormpiercer"), first))
	await physics_frames(90)
	assert_true(_hurt(first) > 0.0, "through the first")
	assert_true(_hurt(second) > 0.0, "and on into the second")
	assert_eq(player.state, Player.State.FREE)


func test_a_heavy_blow_knocks_you_out_of_the_gather() -> void:
	await _load()
	var target := _dummy(6.0)
	assert_true(player.caster.cast(JutsuRegistry.get_jutsu(&"cyclone_core"), target))
	await physics_frames(5)
	player.take_hit(player.interrupt_damage + 1.0, Element.NONE, null)
	await physics_frames(70)
	assert_eq(player.state, Player.State.FREE)
	assert_near(_hurt(target), 0.0, 0.01, "it never went off")


func test_the_camera_looks_over_the_shoulder() -> void:
	await _load()
	var rig := player.camera_rig
	assert_near(rig.spring.spring_length, CameraRig.STYLES["shoulder"]["distance"], 0.01, "close behind")
	await physics_frames(30)
	var right := rig.camera.global_position - player.global_position
	assert_true(right.dot(rig.flat_basis().x) > 0.4, "off to the right (%.2f)" % right.dot(rig.flat_basis().x))
	Settings.set_value(&"camera_side", "left")
	await physics_frames(60)
	right = rig.camera.global_position - player.global_position
	assert_true(right.dot(rig.flat_basis().x) < -0.4, "or the left")
	Settings.set_value(&"camera_style", "classic")
	await physics_frames(60)
	assert_near(rig.spring.spring_length, CameraRig.STYLES["classic"]["distance"], 0.01, "classic is further back")
	right = rig.camera.global_position - player.global_position
	assert_near(right.dot(rig.flat_basis().x), 0.0, 0.05, "and centred")


func test_the_shoulder_stops_short_of_a_wall() -> void:
	await _load()
	var rig := player.camera_rig
	var wall := StaticBody3D.new()
	wall.collision_layer = Combat.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 6.0, 6.0)
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	# A wall just past the right shoulder, 0.5 m from the camera's pivot.
	wall.global_basis = rig.flat_basis()
	wall.global_position = rig.global_position + rig.flat_basis().x * 0.6
	await physics_frames(30)
	assert_true(rig.pivot.position.x < 0.35, "pulled in from the wall (%.2f)" % rig.pivot.position.x)
