extends TestCase
## The world gets harder as the story goes on (EnemyTier): part 1 is exactly
## the plain rank tables, every part after is tougher, quicker and
## stronger, and the story's director passes its part on to everyone it
## sends.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D


func after_each() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
	Profile.reset()


func _load() -> void:
	Profile.persist = false
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	await physics_frames(5)


func _table(rank: StringName, tier: int) -> Dictionary:
	var r: Dictionary = EnemyShinobi.RANKS[rank].duplicate()
	EnemyTier.apply(r, tier)
	return r


func test_part_one_is_the_plain_rank_table() -> void:
	for rank: StringName in EnemyShinobi.RANKS:
		var plain: Dictionary = EnemyShinobi.RANKS[rank]
		var tiered := _table(rank, EnemyTier.of_part(1))
		for key: String in plain:
			assert_eq(tiered[key], plain[key], "%s %s unchanged in part 1" % [rank, key])
	assert_eq(EnemyTier.of_part(0), 0, "no part is part 1's")
	assert_eq(EnemyTier.of_part(EnemyTier.STORY_MAX + 1), EnemyTier.STORY_MAX)
	assert_eq(EnemyTier.of_part(99), EnemyTier.STORY_MAX, "and it stops at the last part")


func test_every_part_is_tougher_than_the_one_before() -> void:
	for rank: StringName in EnemyShinobi.RANKS:
		for tier in range(1, EnemyTier.MAX + 1):
			var before := _table(rank, tier - 1)
			var now := _table(rank, tier)
			var label := "%s tier %d" % [rank, tier]
			for key: String in ["health", "power", "melee", "run", "poise", "interrupt", "max_cost"]:
				assert_true(float(now[key]) > float(before[key]), "%s: more %s" % [label, key])
			for key: String in ["seal_time", "jutsu_cd", "kunai_cd", "think", "engage"]:
				var a: Variant = now[key]
				var b: Variant = before[key]
				var smaller: bool = (a.x < b.x) if a is Vector2 else (float(a) < float(b))
				assert_true(smaller, "%s: quicker %s" % [label, key])
			assert_true(float(now["dodge"]) >= float(before["dodge"]) and float(now["dodge"]) <= EnemyTier.MAX_DODGE, label + ": dodge")
			assert_true(float(now["guard"]) >= float(before["guard"]) and float(now["guard"]) <= EnemyTier.MAX_GUARD, label + ": guard")


func test_the_tells_stay_readable() -> void:
	for rank: StringName in EnemyShinobi.RANKS:
		var last := _table(rank, EnemyTier.MAX)
		assert_true(float(last["windup"]) >= 0.3, "%s still winds up long enough to read (%.2f s)" % [rank, last["windup"]])
		assert_true(float(last["aim"]) >= 0.3, "%s still aims long enough to read (%.2f s)" % [rank, last["aim"]])
		assert_true(float(last["windup"]) < float(EnemyShinobi.RANKS[rank]["windup"]), "but a little sooner")


func test_the_last_part_is_a_real_step_up() -> void:
	var plain := _table(&"genin", 0)
	var last := _table(&"genin", EnemyTier.MAX)
	assert_true(float(last["health"]) >= float(plain["health"]) * 1.6, "at least 60% tougher")
	assert_true(float(last["power"]) >= float(plain["power"]) * 1.4, "at least 40% harder-hitting")
	assert_true(float(last["max_cost"]) > 25.0, "a genin reaches for a chunin's jutsu by the end")


func test_a_fighter_wears_its_tier() -> void:
	await _load()
	var plain := EnemyShinobi.new()
	plain.rank = &"chunin"
	plain.element = Element.WIND
	var late := EnemyShinobi.new()
	late.rank = &"chunin"
	late.element = Element.WIND
	late.tier = EnemyTier.MAX
	var drill := EnemyShinobi.new()
	drill.rank = &"chunin"
	drill.element = Element.WIND
	drill.drill = true
	drill.tier = EnemyTier.MAX
	for e in [plain, late, drill]:
		e.position = Vector3(0, 0.2, -30)
		scene.add_child(e)
	assert_near(plain.stats.max_health, float(EnemyShinobi.RANKS[&"chunin"]["health"]), 0.01, "tier 0 is the table")
	assert_near(late.stats.max_health, float(EnemyShinobi.RANKS[&"chunin"]["health"]) * EnemyTier.health_mult(EnemyTier.MAX), 0.01)
	assert_true(late.caster.power_scale > plain.caster.power_scale, "and hits harder")
	assert_near(drill.stats.max_health, plain.stats.max_health, 0.01, "practice clones stay gentle")
	assert_near(drill.caster.power_scale, 0.25, 0.001)


func test_a_written_boss_health_is_scaled_too() -> void:
	await _load()
	var boss := EnemyShinobi.new()
	boss.rank = &"jonin"
	boss.element = Element.FIRE
	boss.health_override = 460.0
	boss.tier = EnemyTier.MAX
	boss.position = Vector3(0, 0.2, -30)
	scene.add_child(boss)
	assert_near(boss.stats.max_health, 460.0 * EnemyTier.health_mult(EnemyTier.MAX), 0.01)


func test_the_story_director_sends_its_part() -> void:
	var director := StoryDirector.new()
	for part in range(1, 7):
		director.chapter = {"part": part}
		assert_eq(director._tier(), part - 1, "part %d" % part)
	director.chapter = {}
	assert_eq(director._tier(), 0, "no chapter, no scaling")
	director.free()


func test_every_story_chapter_has_a_part_to_scale_by() -> void:
	var story := Story.load_all()
	var seen := {}
	for c: Dictionary in story.chapters:
		seen[int(c["part"])] = true
	assert_eq(seen.size(), 7, "seven parts, seven steps up")
	assert_true(seen.has(1) and seen.has(EnemyTier.STORY_MAX + 1))


func test_difficulty_and_new_game_plus_add_tiers_on_top_of_the_story() -> void:
	Settings.persist = false
	Game.reset_records()
	var before: Variant = Settings.get_value(&"difficulty")
	assert_eq(EnemyTier.bonus(), 0, "normal, first time round")
	Settings.set_value(&"difficulty", "hard")
	assert_eq(EnemyTier.of_part(1), 2, "hard starts two tiers up")
	assert_eq(EnemyTier.of_part(4), 5)
	Settings.set_value(&"difficulty", "nightmare")
	assert_eq(EnemyTier.of_part(1), 4)
	assert_eq(EnemyTier.of_part(7), EnemyTier.MAX, "the last part on nightmare is the ceiling")
	Settings.set_value(&"difficulty", "normal")
	Game.set_record("meta", "ng_plus", 1)
	assert_eq(EnemyTier.of_part(1), EnemyTier.PER_ROUND, "a second round starts higher")
	Game.set_record("meta", "ng_plus", 9)
	assert_eq(EnemyTier.of_part(7), EnemyTier.MAX, "and nothing passes the ceiling")
	Game.reset_records()
	Settings.set_value(&"difficulty", before)
