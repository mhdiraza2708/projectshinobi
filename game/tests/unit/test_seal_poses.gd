extends TestCase
## Hand seals: each of the twelve has its own shape, and the fingers really
## take it (straight where it says straight, folded where it says folded).

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player


func _load() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	await physics_frames(5)


func after_each() -> void:
	Input.action_release(&"weave")


## Weaves `seal` and waits for the hands to settle into it.
func _hold(seal: int) -> void:
	Input.action_press(&"weave")
	player._begin_weave()
	await physics_frames(4)
	player.weaver.add_seal(seal)
	await physics_frames(40)


## Degrees each finger of a hand bends from base to tip, read after the poser
## (a skeleton modifier) has run.
func _bends(side: String) -> Dictionary:
	var skel := player.model.skeleton
	var out := {}
	var grab := func() -> void:
		if not out.is_empty():
			return
		for f in ["Index", "Middle", "Ring", "Little"]:
			var total := 0.0
			var chain := ["%sHand" % side, "%s%sProximal" % [side, f], "%s%sIntermediate" % [side, f], "%s%sDistal" % [side, f]]
			for k in range(1, chain.size() - 1):
				var a := skel.find_bone(chain[k - 1])
				var b := skel.find_bone(chain[k])
				var c := skel.find_bone(chain[k + 1])
				if a < 0 or b < 0 or c < 0:
					continue
				var pa := skel.get_bone_global_pose(a).origin
				var pb := skel.get_bone_global_pose(b).origin
				var pc := skel.get_bone_global_pose(c).origin
				total += rad_to_deg((pb - pa).angle_to(pc - pb))
			out[f] = total
	skel.skeleton_updated.connect(grab)
	await physics_frames(3)
	skel.skeleton_updated.disconnect(grab)
	return out


func test_there_are_twelve_seals_each_with_both_hands() -> void:
	for seal in Seal.COUNT:
		var p := SealPoses.pose(seal)
		for key in ["seal_L", "seal_R", "hand_L", "hand_R", "thumb_L", "thumb_R", "wrap_L", "wrap_R",
				"spread_L", "spread_R", "fin_L_0", "fin_R_3"]:
			assert_true(p.has(key), "%s has %s" % [Seal.NAMES[seal], key])
	assert_eq(SealPoses._table().size(), Seal.COUNT, "exactly one shape per seal")
	assert_eq(SealPoses.pose(-1), {})
	assert_eq(SealPoses.pose(12), {})


func test_no_two_seals_share_a_finger_formation_and_placement() -> void:
	for a in Seal.COUNT:
		for b in range(a + 1, Seal.COUNT):
			var pa := SealPoses.pose(a)
			var pb := SealPoses.pose(b)
			var diff := 0.0
			for side in ["L", "R"]:
				for i in 4:
					diff += absf(float(pa["fin_%s_%d" % [side, i]]) - float(pb["fin_%s_%d" % [side, i]]))
				diff += absf(float(pa["spread_" + side]) - float(pb["spread_" + side]))
				diff += absf(float(pa["wrap_" + side]) - float(pb["wrap_" + side]))
				diff += (pa["hand_" + side] as Vector3).distance_to(pb["hand_" + side])
				diff += (pa["seal_" + side] as Vector3).distance_to(pb["seal_" + side]) * 4.0
			assert_true(diff > 0.5, "%s and %s look alike (%.2f)" % [Seal.NAMES[a], Seal.NAMES[b], diff])


func test_tiger_holds_two_fingers_straight_and_folds_the_rest() -> void:
	await _load()
	await _hold(Seal.TIGER)
	var bends := await _bends("Left")
	assert_true(bends["Index"] < 25.0 and bends["Middle"] < 25.0, "index and middle straight: %s" % bends)
	assert_true(bends["Ring"] > 60.0 and bends["Little"] > 60.0, "ring and little folded: %s" % bends)


func test_boar_holds_the_index_and_little_fingers_up_as_horns() -> void:
	await _load()
	await _hold(Seal.BOAR)
	var bends := await _bends("Right")
	assert_true(bends["Index"] < 25.0 and bends["Little"] < 25.0, "index and little straight: %s" % bends)
	assert_true(bends["Middle"] > 60.0 and bends["Ring"] > 60.0, "middle and ring folded: %s" % bends)


func test_fingers_take_each_seal_and_change_between_them() -> void:
	await _load()
	await _hold(Seal.OX)
	var flat := await _bends("Left")
	for f in flat:
		assert_true(flat[f] < 25.0, "ox: a flat hand, %s straight (%s)" % [f, flat])
	player.weaver.add_seal(Seal.SNAKE)
	await physics_frames(40)
	var laced := await _bends("Left")
	for f in laced:
		assert_true(laced[f] > 40.0, "snake: fingers bent to lace (%s)" % [laced])


func test_the_held_seal_ends_with_the_weave() -> void:
	await _load()
	await _hold(Seal.HARE)
	var poser := player.animator.poser
	assert_eq(poser.seal_pose, Seal.HARE, "the poser holds the seal woven")
	Input.action_release(&"weave")
	await physics_frames(10)
	assert_eq(poser.seal_pose, -1, "and lets it go when the weave ends")
