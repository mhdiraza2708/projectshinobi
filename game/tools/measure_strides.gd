extends SceneTree
## Measures how fast each locomotion clip carries a character, in leg lengths
## per second, by following the planted foot through the cycle on real rigs.
## The results go in CharacterAnimator.STRIDE.
##   godot --headless --path game --script res://tools/measure_strides.gd

const ROSTER := "res://assets/characters/roster"
const CLIPS: Array[StringName] = [&"walk", &"run", &"sprint"]
const SAMPLES := 240


var _done := false


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run()
	return false


func _run() -> void:
	var lib := CharacterAnimator.load_library(CharacterAnimator.CLIP_DIR)
	var totals := {}
	var rigs := 0
	for file in DirAccess.get_files_at(ROSTER):
		if file.get_extension() != "vrm":
			continue
		var scene := load(ROSTER.path_join(file)) as PackedScene
		if scene == null:
			continue
		var model := scene.instantiate() as Node3D
		root.add_child(model)
		var skel := model.get_node_or_null(^"%GeneralSkeleton") as Skeleton3D
		if skel == null:
			model.free()
			continue
		var player := AnimationPlayer.new()
		model.add_child(player)
		player.root_node = player.get_path_to(model)
		player.add_animation_library(&"", lib)
		var leg := _leg(skel)
		var line := "%-28s leg %.2fm" % [file.get_basename(), leg]
		for clip in CLIPS:
			var speed := _measure(player, skel, clip) / leg
			totals[clip] = totals.get(clip, 0.0) + speed
			line += "  %s %.2f" % [clip, speed]
		print(line)
		rigs += 1
		model.free()
	for clip in CLIPS:
		print("%s: %.2f leg lengths/s (mean of %d rigs)" % [clip, totals.get(clip, 0.0) / maxi(rigs, 1), rigs])
	quit()


func _leg(skel: Skeleton3D) -> float:
	var hip := skel.get_bone_global_rest(skel.find_bone(&"LeftUpperLeg")).origin
	var knee := skel.get_bone_global_rest(skel.find_bone(&"LeftLowerLeg")).origin
	var foot := skel.get_bone_global_rest(skel.find_bone(&"LeftFoot")).origin
	return hip.distance_to(knee) + knee.distance_to(foot)


## How fast a planted foot slides backward under the body: the ground speed
## the clip shows. Contact = within 3% of a leg length of the foot's lowest.
func _measure(player: AnimationPlayer, skel: Skeleton3D, clip: StringName) -> float:
	player.play(clip)
	var length := player.get_animation(clip).length
	var dt := length / SAMPLES
	var feet := [skel.find_bone(&"LeftFoot"), skel.find_bone(&"RightFoot")]
	var toe := skel.find_bone(&"LeftToes")
	var fwd := skel.get_bone_global_rest(toe).origin - skel.get_bone_global_rest(feet[0]).origin
	fwd.y = 0.0
	fwd = fwd.normalized()
	var track := [[], []]
	for i in SAMPLES + 1:
		player.seek(i * dt, true)
		player.advance(0.0)
		skel.force_update_all_bone_transforms()
		for f in 2:
			track[f].append(skel.get_bone_global_pose(feet[f]).origin)
	var leg := _leg(skel)
	var speeds: Array[float] = []
	for f in 2:
		var low := INF
		for p: Vector3 in track[f]:
			low = minf(low, p.y)
		for i in range(1, track[f].size()):
			var a: Vector3 = track[f][i - 1]
			var b: Vector3 = track[f][i]
			if a.y < low + 0.03 * leg and b.y < low + 0.03 * leg:
				speeds.append(-(b - a).dot(fwd) / dt)
	speeds.sort()
	# Cross-check: each foot sweeps its fore-aft range twice a cycle.
	var lo := INF
	var hi := -INF
	for p: Vector3 in track[0]:
		lo = minf(lo, p.dot(fwd))
		hi = maxf(hi, p.dot(fwd))
	print("    %s: cycle %.2fs, foot range %.2f legs -> %.2f legs/s" % [clip, length, (hi - lo) / leg, 2.0 * (hi - lo) / leg / length])
	return speeds[speeds.size() / 2] if not speeds.is_empty() else 0.0
