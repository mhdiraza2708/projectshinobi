extends TestCase
## The VRM character pipeline and the rig-agnostic procedural poser, run on
## the real default VRM (the same import path a VRoid Studio export takes).

var model: CharacterModel


func before_each() -> void:
	model = CharacterModel.new()
	model.model_path = CharacterModel.DEFAULT_MODEL
	root.add_child(model)


## Bone position in the CharacterModel's space (the player's space).
## Modifier results only exist while the frame's final pose is being built,
## so read them after `await _posed()`.
func _bone(bone: StringName) -> Vector3:
	var skel := model.skeleton
	var world := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(bone)).origin
	return model.to_local(world)


func _arm_len() -> float:
	return _bone(&"LeftUpperArm").distance_to(_bone(&"LeftLowerArm")) \
		+ _bone(&"LeftLowerArm").distance_to(_bone(&"LeftHand"))


func _hold(pose: HumanoidPoser.Pose, frames := 40) -> void:
	model.poser.pose = pose
	for i in frames:
		await root.get_tree().process_frame
	await _posed()


## Resumes inside Skeleton3D.skeleton_updated, when modified poses are live.
func _posed() -> void:
	await model.skeleton.skeleton_updated


func test_default_vrm_loads_with_humanoid_rig() -> void:
	assert_true(model.skeleton != null, "has skeleton")
	assert_true(model.poser != null and model.poser.active, "poser active")
	assert_true(model.expressions != null and model.expressions.has_animation(&"blink"), "VRM expressions available")


func test_model_faces_forward_and_is_game_scale() -> void:
	var dir := (model.global_basis.inverse() * model.skeleton.global_basis) * model.poser.forward_in_skeleton()
	assert_true(dir.normalized().dot(Vector3.FORWARD) > 0.95, "faces -Z, got %s" % dir)
	var h := model.measure_height()
	assert_true(h >= model.min_height and h <= model.max_height, "height %.2f in range" % h)


func test_idle_arms_hang_at_sides() -> void:
	await _hold(HumanoidPoser.Pose.LOCOMOTION)
	var shoulder_y := _bone(&"LeftUpperArm").y
	for side in ["Left", "Right"]:
		var hand := _bone(StringName(side + "Hand"))
		assert_true(hand.y < shoulder_y - 0.6 * _arm_len(), "%s hand hangs down (T-pose undone)" % side)


func test_weave_presses_palms_together_in_front_of_chest() -> void:
	await _hold(HumanoidPoser.Pose.WEAVE)
	var l := _bone(&"LeftHand")
	var r := _bone(&"RightHand")
	var chest := _bone(&"Chest")
	assert_true(l.distance_to(r) < 0.2 * _arm_len(), "hands together (%.3f)" % l.distance_to(r))
	assert_true((l + r).z * 0.5 < chest.z - 0.15 * _arm_len(), "hands in front of chest")
	assert_true((l + r).y * 0.5 > _bone(&"Hips").y, "hands above hips")


func test_guard_raises_forearms_to_face() -> void:
	await _hold(HumanoidPoser.Pose.GUARD)
	var shoulder_y := _bone(&"LeftUpperArm").y
	assert_true(_bone(&"LeftHand").y > shoulder_y - 0.1 * _arm_len(), "left hand up")
	assert_true(_bone(&"RightHand").y > shoulder_y - 0.1 * _arm_len(), "right hand up")
	# Crossed: each hand has moved past the midline.
	assert_true(_bone(&"LeftHand").x > _bone(&"RightHand").x - 0.1 * _arm_len(), "forearms crossed")


func test_run_cycle_alternates_feet() -> void:
	model.poser.speed_ratio = 1.0
	var min_z := INF
	var max_z := -INF
	for i in 90:
		await _posed()
		var z := _bone(&"LeftFoot").z - _bone(&"RightFoot").z
		min_z = minf(min_z, z)
		max_z = maxf(max_z, z)
	assert_true(min_z < -0.05 and max_z > 0.05, "left foot passes in front of and behind the right (%.2f..%.2f)" % [min_z, max_z])


func test_rig_without_humanoid_bones_is_rejected_safely() -> void:
	var skel := Skeleton3D.new()
	skel.add_bone("Root")
	root.add_child(skel)
	var poser := HumanoidPoser.new()
	skel.add_child(poser)
	assert_false(poser.setup(skel))
	assert_false(poser.active)
