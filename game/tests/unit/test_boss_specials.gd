extends TestCase
## A boss's signature attacks: warned before they land, they hurt only if you
## are still where they fall.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player
var boss: EnemyShinobi
var specials: BossSpecials


func before_each() -> void:
	seed(99)


func _load() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	await physics_frames(10)
	boss = EnemyShinobi.new()
	boss.rank = &"jonin"
	boss.element = Element.EARTH
	boss.target = player
	boss.position = player.global_position + Vector3(0, 0, -12)
	scene.add_child(boss)
	await physics_frames(ceili(EnemyShinobi.SPAWN_TIME * 60.0) + 5)
	# Hold the boss still and keep it from fighting: only the special is tested.
	boss.set_physics_process(false)
	specials = BossSpecials.new()
	specials.boss = boss
	boss.add_child(specials)
	player.stats.health = player.stats.max_health


## Waits until the special has run its course (not for a fixed time: a slow
## machine runs the game slower than the clock).
func _until_spent(limit := 15.0) -> void:
	await physics_frames(3)
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while specials.is_busy() and Time.get_ticks_msec() < end:
		await physics_frames(1)


func _spec(kind: String, extra := {}) -> Dictionary:
	var s := {"kind": kind, "delay": 0.4, "damage": 20.0}
	s.merge(extra, true)
	return BossSpecials.full(s)


func test_a_spec_keeps_what_it_says_and_fills_in_the_rest() -> void:
	var s := BossSpecials.full({"kind": "ring", "damage": 33.0})
	assert_eq(s["damage"], 33.0)
	assert_eq(s["radius"], BossSpecials.DEFAULTS["ring"]["radius"])
	assert_eq(BossSpecials.errors_in({"kind": "quake"}).size(), 0)
	assert_true(BossSpecials.errors_in({"kind": "dance"}).size() > 0, "an unknown kind is an error")
	assert_true(BossSpecials.errors_in("quake").size() > 0, "and so is a non-object")


func test_a_quake_hurts_whoever_stays_and_spares_whoever_leaves() -> void:
	await _load()
	var before := player.stats.health
	specials._run(_spec("quake", {"count": 3}))
	await _until_spent()
	assert_true(player.stats.health < before, "standing in the mark hurts")
	player.stats.health = player.stats.max_health
	before = player.stats.health
	specials._run(_spec("quake", {"count": 3}))
	await physics_frames(5)
	player.global_position += Vector3(30, 0, 0)
	await _until_spent()
	assert_eq(player.stats.health, before, "leaving the marks takes no damage")


func test_a_ring_runs_along_the_ground_and_a_jump_clears_it() -> void:
	await _load()
	player.set_physics_process(false)
	var before := player.stats.health
	specials._run(_spec("ring", {"delay": 0.2}))
	await _until_spent()
	assert_true(player.stats.health < before, "the ring catches you on the ground")
	player.stats.health = player.stats.max_health
	before = player.stats.health
	specials._run(_spec("ring", {"delay": 0.2}))
	await physics_frames(5)
	player.global_position.y += 4.0
	await _until_spent()
	assert_eq(player.stats.health, before, "above it, it passes under you")
	assert_false(specials.is_busy(), "and it is spent")


func test_a_chain_brings_the_boss_to_you_in_steps() -> void:
	await _load()
	var start := boss.global_position
	specials._run(_spec("chain", {"count": 2, "delay": 0.3}))
	await _until_spent()
	assert_true(boss.global_position.distance_to(start) > 4.0, "the boss blinked")
	assert_true(boss.global_position.distance_to(player.global_position) < 8.0, "to strike round you")


func test_specials_scale_with_the_story_tier() -> void:
	await _load()
	boss.tier = 0
	var before := player.stats.health
	specials._run(_spec("quake", {"count": 1, "radius": 5.0}))
	await _until_spent()
	var plain := before - player.stats.health
	player.stats.health = player.stats.max_health
	boss.tier = 5
	before = player.stats.health
	specials._run(_spec("quake", {"count": 1, "radius": 5.0}))
	await _until_spent()
	var late := before - player.stats.health
	assert_true(plain > 0.0 and late > plain, "later bosses hit harder (%.1f then %.1f)" % [plain, late])


func test_the_schedule_runs_them_one_at_a_time() -> void:
	await _load()
	specials.specs = [_spec("quake", {"every": 5.0, "count": 1, "delay": 0.2})]
	specials._left.assign([0.05])
	var before := player.stats.health
	await physics_frames(10)
	assert_true(specials.is_busy(), "it starts by itself when its time comes")
	await _until_spent()
	assert_true(player.stats.health < before, "and lands")
	assert_false(specials.is_busy(), "then it is spent until its next turn")


func test_a_special_waits_for_its_health_threshold() -> void:
	await _load()
	specials.specs = [_spec("quake", {"every": 0.2, "below": 0.5, "count": 1, "delay": 0.1})]
	specials._left.assign([0.05])
	boss.stats.health = boss.stats.max_health
	var before := player.stats.health
	await seconds(0.8)
	assert_eq(player.stats.health, before, "at full health it does not start")
	boss.stats.health = boss.stats.max_health * 0.4
	var end := Time.get_ticks_msec() + 10000
	while player.stats.health >= before and Time.get_ticks_msec() < end:
		await physics_frames(2)
	assert_true(player.stats.health < before, "below the threshold it does")


func test_a_sweeping_blade_catches_the_grounded_and_a_jump_clears_it() -> void:
	await _load()
	player.set_physics_process(false)
	var before := player.stats.health
	# The boss turns once, quickly, with a blade long enough to reach the player.
	specials._run(_spec("sweep", {"delay": 0.2, "duration": 1.2, "radius": 20.0}))
	await _until_spent()
	assert_true(player.stats.health < before, "the blade catches you on the ground")
	player.stats.health = player.stats.max_health
	before = player.stats.health
	specials._run(_spec("sweep", {"delay": 0.2, "duration": 1.2, "radius": 20.0}))
	await physics_frames(5)
	player.global_position.y += 4.0
	await _until_spent()
	assert_eq(player.stats.health, before, "high above it, the blade passes under you")


func test_a_pull_drags_you_in_and_bursts_where_you_ended_up() -> void:
	await _load()
	player.set_physics_process(false)
	var start := player.global_position.distance_to(boss.global_position)
	var before := player.stats.health
	specials._run(_spec("pull", {"delay": 0.1, "duration": 1.0, "strength": 8.0, "radius": 6.0}))
	await _until_spent()
	assert_true(player.global_position.distance_to(boss.global_position) < start - 3.0, "you were pulled toward it")
	assert_true(player.stats.health < before, "and the burst caught you")


func test_a_pull_misses_whoever_gets_away() -> void:
	await _load()
	player.set_physics_process(false)
	player.global_position = boss.global_position + Vector3(0, 0, 40)
	var before := player.stats.health
	specials._run(_spec("pull", {"delay": 0.1, "duration": 0.8, "range": 22.0, "radius": 5.0}))
	await _until_spent()
	assert_eq(player.stats.health, before, "out of its reach, nothing pulls you and nothing bursts on you")


func test_a_ward_turns_blows_aside_until_enough_land_to_break_it() -> void:
	await _load()
	var full := boss.stats.max_health
	specials._run(_spec("ward", {"delay": 0.1, "duration": 20.0, "reduction": 0.9, "force": 60.0}))
	await physics_frames(20)
	var dealt := boss.stats.take_damage(20.0, Element.NONE)
	assert_true(dealt < 4.0, "inside the ward a 20 point blow does %.1f" % dealt)
	assert_true(boss.stats.modifier(&"damage_reduction") > 0.5, "the ward is up")
	# Enough raw force breaks it.
	boss.stats.take_damage(40.0, Element.NONE)
	boss.stats.take_damage(40.0, Element.NONE)
	await _until_spent()
	assert_eq(boss.stats.modifier(&"damage_reduction"), 0.0, "once broken the boss is hurt in full again")
	assert_true(boss.stats.health > full - 40.0, "the blows that broke it cost the boss little")
	assert_eq(boss.state, EnemyShinobi.State.STAGGERED, "and breaking it leaves the boss reeling")


func test_a_ward_fades_by_itself() -> void:
	await _load()
	specials._run(_spec("ward", {"delay": 0.05, "duration": 0.5, "force": 9999.0}))
	await _until_spent()
	assert_eq(boss.stats.modifier(&"damage_reduction"), 0.0, "an unbroken ward still ends")
	assert_false(specials.is_busy())


func test_a_call_brings_shinobi_to_the_bosss_side_and_they_leave_with_it() -> void:
	await _load()
	specials._run(_spec("call", {"delay": 0.1, "count": 2, "max": 3, "duration": 60.0}))
	await _until_spent()
	assert_eq(specials._calls.size(), 2, "two answered")
	var calling := 0
	for c in specials._calls:
		if is_instance_valid(c) and c.element == boss.element and c.team == boss.team:
			calling += 1
	assert_eq(calling, 2, "of the boss's own nature and side")
	# A second call only fills what room is left.
	specials._run(_spec("call", {"delay": 0.1, "count": 2, "max": 3, "duration": 60.0}))
	await _until_spent()
	assert_eq(specials._calls.size(), 3, "never more than max at once")
	boss.defeated.emit(boss)
	await physics_frames(5)
	assert_eq(specials._calls.size(), 0, "when the boss falls, the ones it called go too")


func test_walls_rise_between_you_and_the_boss_and_then_sink() -> void:
	await _load()
	player.set_physics_process(false)
	specials._run(_spec("walls", {"delay": 0.2, "count": 3, "duration": 0.6}))
	await _until_spent()
	var walls := specials.find_children("*", "JutsuWall", true, false)
	assert_eq(walls.size(), 3, "three slabs stand")
	for w in walls:
		assert_eq((w as JutsuWall).collision_layer, Combat.LAYER_WALLS, "and they are solid")
	# The first is between the two of them.
	var first := walls[0] as JutsuWall
	var to_boss := boss.global_position - player.global_position
	var to_wall := first.global_position - player.global_position
	assert_true(to_wall.dot(to_boss) > 0.0 and to_wall.length() < to_boss.length(), "between you and the boss")
	var end := Time.get_ticks_msec() + 8000
	while specials.find_children("*", "JutsuWall", true, false).size() > 0 and Time.get_ticks_msec() < end:
		await physics_frames(5)
	assert_eq(specials.find_children("*", "JutsuWall", true, false).size(), 0, "they sink away after their time")


func test_a_slab_rising_under_you_hurts_but_standing_clear_does_not() -> void:
	await _load()
	player.set_physics_process(false)
	var before := player.stats.health
	# Radius 0 puts the second slab on the player.
	specials._run(_spec("walls", {"delay": 0.2, "count": 2, "radius": 0.0, "damage": 20.0, "duration": 0.3}))
	await _until_spent()
	assert_true(player.stats.health < before, "the slab rose under you")
	player.stats.health = player.stats.max_health
	before = player.stats.health
	specials._run(_spec("walls", {"delay": 0.4, "count": 2, "radius": 0.0, "damage": 20.0, "duration": 0.3}))
	await physics_frames(5)
	player.global_position += Vector3(30, 0, 0)
	await _until_spent()
	assert_eq(player.stats.health, before, "step away in the warning and it misses")
	var cleanup := Time.get_ticks_msec() + 4000
	while specials.find_children("*", "JutsuWall", true, false).size() > 0 and Time.get_ticks_msec() < cleanup:
		await physics_frames(5)


func test_the_tide_closes_in_and_drains_again() -> void:
	var outer := 15.0
	assert_eq(BossSpecials._tide_safe_radius(0.0, outer, 6.0, 4.0, 10.0, 1.5), outer, "it starts at the edge")
	assert_eq(BossSpecials._tide_safe_radius(4.0, outer, 6.0, 4.0, 10.0, 1.5), 6.0, "closes to the dry circle")
	assert_eq(BossSpecials._tide_safe_radius(8.0, outer, 6.0, 4.0, 10.0, 1.5), 6.0, "holds")
	assert_true(BossSpecials._tide_safe_radius(2.0, outer, 6.0, 4.0, 10.0, 1.5) < outer, "closing")
	assert_true(BossSpecials._tide_safe_radius(10.75, outer, 6.0, 4.0, 10.0, 1.5) > 6.0, "then draining")
	assert_true(BossSpecials._tide_safe_radius(12.0, outer, 6.0, 4.0, 10.0, 1.5) >= outer, "and gone")


func test_a_tide_hurts_in_the_water_and_spares_the_dry_middle() -> void:
	await _load()
	player.set_physics_process(false)
	var before := player.stats.health
	# The player stands 6 m from the middle; the dry circle closes to 2 m.
	specials._run(_spec("tide", {"delay": 0.1, "rise": 0.4, "duration": 1.6, "to": 2.0, "radius": 15.0, "damage": 30.0}))
	await _until_spent()
	assert_true(player.stats.health < before, "in the water you are hurt")
	assert_eq(specials.tide_safe_radius, INF, "and the tide is gone when it is done")
	player.stats.health = player.stats.max_health
	before = player.stats.health
	specials._run(_spec("tide", {"delay": 0.3, "rise": 0.4, "duration": 1.6, "to": 2.0, "radius": 15.0, "damage": 30.0}))
	await physics_frames(2)
	# The middle is halfway between the two of them.
	player.global_position = (player.global_position + boss.global_position) * 0.5
	await _until_spent()
	assert_eq(player.stats.health, before, "on the dry middle it never reaches you")


func test_every_story_boss_and_every_bounty_has_signature_attacks() -> void:
	var story := Story.load_all()
	assert_true(story.errors.is_empty(), "\n".join(story.errors))
	var bosses := 0
	for c: Dictionary in story.chapters:
		for b: Dictionary in c["beats"]:
			if b["do"] == "boss":
				bosses += 1
				assert_true((b["specials"] as Array).size() >= 1, "%s: boss %s has a special" % [c["id"], b["who"]])
	assert_true(bosses >= 8, "%d boss beats" % bosses)
	assert_eq(Bounties.errors, [] as Array[String])
	for b: Dictionary in Bounties.all():
		assert_true((b.get("specials", []) as Array).size() >= 1, "%s has a special" % b["id"])
