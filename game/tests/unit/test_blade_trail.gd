extends TestCase
## The sword's finish: a ribbon behind the blade while it cuts or is drawn
## (one per sword, gone with it), the glint that runs up the blade as it comes
## out, and the half-beat the world holds when a cut lands.

const Scene := preload("res://scenes/training_ground.tscn")

var model: CharacterModel
var scene: Node3D


func after_each() -> void:
	if is_instance_valid(model):
		model.queue_free()
	if is_instance_valid(scene):
		scene.queue_free()
	HitStop.release()
	Engine.time_scale = 1.0
	root.get_tree().paused = false


func _armed(back := "ninjato") -> CharacterModel:
	model = CharacterModel.new()
	model.model_path = CharacterModel.DEFAULT_MODEL
	model.use_profile = false
	model.style = {"back": back}
	root.add_child(model)
	return model


func _frames(n: int) -> void:
	for i in n:
		await root.get_tree().process_frame


## Frames with the late update done by hand: the game runs it just before
## each frame is drawn, and a headless run draws none.
func _drawn_frames(trail: BladeTrail, n: int) -> void:
	for i in n:
		await root.get_tree().process_frame
		trail.refresh()


func test_a_sword_has_one_trail_and_an_unarmed_character_has_none() -> void:
	_armed()
	await _frames(2)
	var gear := model.gear
	assert_true(gear.blade_trail != null, "a sword has its trail")
	assert_eq(gear.blade_trail.get_parent(), gear.sword, "on the sword")
	assert_eq(gear.sword.find_children("*", "BladeTrail", true, false).size(), 1, "just one")
	assert_true(gear.blade_trail.has_meta(&"gear"), "counted as gear, not body")
	assert_false(gear.blade_trail.is_showing(), "nothing drawn while sheathed")
	model.queue_free()
	_armed("none")
	await _frames(2)
	assert_true(model.gear.blade_trail == null, "no sword, no trail")


func test_the_trail_shows_in_the_draw_and_in_cuts_only() -> void:
	_armed()
	await _frames(2)
	var anim := model.animator
	var trail := model.gear.blade_trail
	await seconds(0.3)
	assert_false(trail.is_showing(), "nothing without a cut")
	assert_false(trail.is_processing(), "and it costs nothing to idle")
	anim.strike()
	assert_false(trail.emitting, "the blade is still in the scabbard")
	await seconds(HumanoidPoser.DRAW_TIME * 0.8)
	assert_true(trail.emitting and trail.is_showing(), "the draw leaves a ribbon")
	await seconds(HumanoidPoser.DRAW_TIME * 0.2 + trail.lifetime + 0.3)
	assert_false(trail.emitting, "the draw is over")
	assert_false(trail.is_showing(), "and the ribbon has faded away")
	assert_false(trail.is_processing(), "and stopped working")
	anim.strike(1)
	await seconds(HumanoidPoser.CUT_TIME * 0.6)
	assert_true(trail.emitting and trail.is_showing(), "a cut leaves a ribbon")
	await seconds(HumanoidPoser.CUT_TIME + trail.lifetime + 0.3)
	assert_false(trail.is_showing(), "gone again")


func test_the_ribbon_is_drawn_between_the_guard_and_the_point() -> void:
	_armed()
	await _frames(2)
	var anim := model.animator
	var trail := model.gear.blade_trail
	anim.strike()
	await seconds(HumanoidPoser.DRAW_TIME + 0.1)
	anim.strike(0)
	await _drawn_frames(trail, 10)
	assert_eq(trail.mesh.get_surface_count(), 2, "the sheet and the line along the point")
	# It lies on the blade: the newest edge is the blade as it stands.
	var point := model.gear.sword.to_global(Vector3(0, CharacterGear.GUARD_Y - CharacterGear.BLADE_LENGTH, 0))
	var box := trail.mesh.get_aabb()
	assert_true(box.size.length() > 0.3, "it has size (%s)" % box.size)
	assert_true(box.grow(0.02).has_point(point), "and reaches the point of the blade")
	var latest := trail._tip[trail._slot(trail._count - 1)]
	assert_true(latest.distance_to(point) < 0.01, "the newest sample is the blade as drawn now")


func test_the_trail_starts_afresh_when_the_blade_was_sheathed_or_carried_off() -> void:
	_armed()
	await _frames(2)
	var anim := model.animator
	var trail := model.gear.blade_trail
	anim.strike()
	await seconds(HumanoidPoser.DRAW_TIME + 0.05)
	anim.strike(0)
	await seconds(HumanoidPoser.CUT_TIME * 0.5)
	assert_true(trail.is_showing())
	model.gear.set_drawn(false)
	await _frames(2)
	assert_false(trail.is_showing(), "a sheathed sword leaves nothing behind")
	# Carried off (a teleport) in the middle of a cut.
	model.gear.set_drawn(true)
	trail.emitting = true
	await _drawn_frames(trail, 6)
	assert_true(trail._count > 2, "a ribbon building")
	model.global_position += Vector3(40, 0, 0)
	await _drawn_frames(trail, 1)
	assert_true(trail._count <= 2, "no streak across the teleport (%d samples)" % trail._count)


func test_the_trail_is_freed_with_its_sword() -> void:
	_armed()
	await _frames(2)
	var trail := model.gear.blade_trail
	model.gear.clear()
	await _frames(2)
	assert_false(is_instance_valid(trail), "gone with the sword")
	assert_true(model.gear.blade_trail == null)


func test_the_trail_does_not_pile_up_samples() -> void:
	_armed()
	await _frames(2)
	var anim := model.animator
	var trail := model.gear.blade_trail
	anim.strike()
	await seconds(HumanoidPoser.DRAW_TIME + 0.05)
	trail.emitting = true
	await seconds(1.0)
	assert_true(trail._count <= BladeTrail.CAPACITY, "bounded")
	assert_true(trail._count <= ceili(trail.lifetime / BladeTrail.MIN_STEP) + 2, "and only as old as its life (%d)" % trail._count)


func test_drawing_the_sword_glints_and_rings() -> void:
	_armed()
	await _frames(2)
	var anim := model.animator
	var trail := model.gear.blade_trail
	Sfx.history.clear()
	anim.strike()
	await seconds(HumanoidPoser.DRAW_TIME * HumanoidPoser.DRAW_REACH + 0.06)
	trail.refresh()
	assert_true(trail._flare != null and trail._flare.visible, "a glint runs up the blade")
	assert_true(Sfx.history.has(&"kunai_throw"), "with the sound of steel")
	var guard := model.gear.sword.to_global(Vector3(0, CharacterGear.GUARD_Y, 0))
	var point := model.gear.sword.to_global(Vector3(0, CharacterGear.GUARD_Y - CharacterGear.BLADE_LENGTH, 0))
	var at := trail._flare.global_position
	var along := (point - guard).normalized()
	var off := (at - guard) - along * (at - guard).dot(along)
	assert_true(off.length() < 0.03, "on the blade (%.3f m off it)" % off.length())
	assert_true((at - guard).dot(along) > -0.01 and (at - guard).dot(along) < guard.distance_to(point) + 0.01, "between the guard and the point")
	await seconds(BladeTrail.GLINT_TIME + 0.2)
	assert_false(trail._flare.visible, "and it is quick")


func test_cut_directions_follow_the_swing() -> void:
	var down := HumanoidPoser.cut_direction(0)
	var up := HumanoidPoser.cut_direction(1)
	var overhead := HumanoidPoser.cut_direction(2)
	var draw := HumanoidPoser.cut_direction(-1)
	for d: Vector3 in [down, up, overhead, draw]:
		assert_near(d.length(), 1.0, 0.001, "unit length")
	assert_true(down.x < -0.3 and down.y < -0.3, "the first cut goes down and to the left")
	assert_true(up.x > 0.3 and up.y > 0.3, "the next rises back to the right")
	assert_true(overhead.y < -0.9, "the finisher comes straight down")
	assert_true(draw.x > 0.8, "the draw sweeps across to the right")
	assert_eq(HumanoidPoser.cut_direction(3), down, "the combo wraps")


# --- Hit-stop ----------------------------------------------------------------------

func test_hit_stop_slows_time_then_always_gives_it_back() -> void:
	var tree := root.get_tree()
	assert_true(HitStop.freeze(tree, 0.05), "it holds")
	assert_near(Engine.time_scale, HitStop.SCALE, 0.001, "time all but stops")
	assert_false(HitStop.freeze(tree, 0.05), "a hold doesn't stack on a hold")
	await seconds(0.3)
	assert_near(Engine.time_scale, 1.0, 0.0001, "and goes on again")
	assert_false(HitStop.is_active())


func test_hit_stop_leaves_other_slow_motion_and_pauses_alone() -> void:
	var tree := root.get_tree()
	Engine.time_scale = 0.4
	assert_false(HitStop.freeze(tree, 0.05), "not over a slow-motion")
	assert_near(Engine.time_scale, 0.4, 0.0001)
	Engine.time_scale = 1.0
	tree.paused = true
	assert_false(HitStop.freeze(tree, 0.05), "not while paused")
	tree.paused = false
	assert_near(Engine.time_scale, 1.0, 0.0001)
	# Slow-motion that starts during a hold is not undone by it.
	assert_true(HitStop.freeze(tree, 0.05))
	Engine.time_scale = 0.4
	await seconds(0.3)
	assert_near(Engine.time_scale, 0.4, 0.0001, "the hold lets go of what isn't its own")
	assert_false(HitStop.is_active())


func test_hit_stop_is_released_when_the_pause_menu_opens_in_it() -> void:
	var tree := root.get_tree()
	assert_true(HitStop.freeze(tree, 0.05))
	tree.paused = true
	await seconds(0.3)
	tree.paused = false
	assert_near(Engine.time_scale, 1.0, 0.0001, "the timer runs through a pause")


func test_a_landed_cut_holds_the_world_a_moment_and_throws_sparks() -> void:
	scene = Scene.instantiate()
	root.add_child(scene)
	var player: Player = scene.player
	await physics_frames(10)
	player.toggle_lock()
	await physics_frames(2)
	var dummy := player.lock_target as TrainingDummy
	assert_true(dummy != null, "a dummy to cut")
	player.global_position = dummy.global_position + Vector3(0, 0, 1.4)
	await physics_frames(2)
	assert_true(player.animator.has_sword(), "the player carries a sword")
	var health := dummy.stats.health
	var before := scene.get_children().filter(func(n: Node) -> bool: return n is CPUParticles3D).size()
	player._strike()
	assert_true(dummy.stats.health < health, "the cut landed")
	assert_true(HitStop.is_active(), "the world holds")
	assert_near(Engine.time_scale, HitStop.SCALE, 0.001)
	var after := scene.get_children().filter(func(n: Node) -> bool: return n is CPUParticles3D).size()
	assert_true(after - before >= 3, "sparks flew (%d new emitters)" % (after - before))
	await seconds(0.4)
	assert_near(Engine.time_scale, 1.0, 0.0001, "and lets go")
	# A cut in the air does neither.
	player.lock_target = null
	player.global_position = Vector3(300, 5, 300)
	player._strike_cooldown = 0.0
	player._strike()
	assert_false(HitStop.is_active(), "a miss doesn't hold anything")


func test_leaving_the_scene_mid_hold_gives_time_back() -> void:
	scene = Scene.instantiate()
	root.add_child(scene)
	await physics_frames(5)
	assert_true(HitStop.freeze(root.get_tree(), 5.0), "a long hold")
	scene.queue_free()
	await physics_frames(3)
	assert_near(Engine.time_scale, 1.0, 0.0001, "released as the player goes")
	assert_false(HitStop.is_active())


func test_a_blade_sparks_burst_cleans_up_after_itself() -> void:
	scene = Scene.instantiate()
	root.add_child(scene)
	await physics_frames(3)
	var count := scene.get_children().size()
	Vfx.blade_sparks(scene, Vector3(0, 1, 0), Vector3(1, -1, 0).normalized())
	assert_true(scene.get_children().size() >= count + 2, "two sprays")
	Vfx.slash(scene, Transform3D.IDENTITY.translated(Vector3(0, 1, 0)), Color(0.3, 0.55, 1.0), 1.8, 0.0, 0.18, 0.35)
	await seconds(1.5)
	assert_eq(scene.get_children().size(), count, "all of it freed itself")
