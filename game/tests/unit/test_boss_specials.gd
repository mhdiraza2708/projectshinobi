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
	await seconds(0.7)
	assert_true(player.stats.health < before, "standing in the mark hurts")
	player.stats.health = player.stats.max_health
	before = player.stats.health
	specials._run(_spec("quake", {"count": 3}))
	await physics_frames(5)
	player.global_position += Vector3(30, 0, 0)
	await seconds(0.7)
	assert_eq(player.stats.health, before, "leaving the marks takes no damage")


func test_a_ring_runs_along_the_ground_and_a_jump_clears_it() -> void:
	await _load()
	player.set_physics_process(false)
	var before := player.stats.health
	specials._run(_spec("ring", {"delay": 0.2}))
	await seconds(1.6)
	assert_true(player.stats.health < before, "the ring catches you on the ground")
	player.stats.health = player.stats.max_health
	before = player.stats.health
	specials._run(_spec("ring", {"delay": 0.2}))
	await physics_frames(5)
	player.global_position.y += 4.0
	await seconds(1.6)
	assert_eq(player.stats.health, before, "above it, it passes under you")
	assert_false(specials.is_busy(), "and it is spent")


func test_a_chain_brings_the_boss_to_you_in_steps() -> void:
	await _load()
	var start := boss.global_position
	specials._run(_spec("chain", {"count": 2, "delay": 0.3}))
	await seconds(1.0)
	assert_true(boss.global_position.distance_to(start) > 4.0, "the boss blinked")
	assert_true(boss.global_position.distance_to(player.global_position) < 8.0, "to strike round you")


func test_specials_scale_with_the_story_tier() -> void:
	await _load()
	boss.tier = 0
	var before := player.stats.health
	specials._run(_spec("quake", {"count": 1, "radius": 5.0}))
	await seconds(0.7)
	var plain := before - player.stats.health
	player.stats.health = player.stats.max_health
	boss.tier = 5
	before = player.stats.health
	specials._run(_spec("quake", {"count": 1, "radius": 5.0}))
	await seconds(0.7)
	var late := before - player.stats.health
	assert_true(plain > 0.0 and late > plain, "later bosses hit harder (%.1f then %.1f)" % [plain, late])


func test_the_schedule_runs_them_one_at_a_time() -> void:
	await _load()
	specials.specs = [_spec("quake", {"every": 5.0, "count": 1, "delay": 0.2})]
	specials._left.assign([0.05])
	var before := player.stats.health
	await physics_frames(10)
	assert_true(specials.is_busy(), "it starts by itself when its time comes")
	await seconds(0.8)
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
	await seconds(0.8)
	assert_true(player.stats.health < before, "below the threshold it does")


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
