extends TestCase
## Skill trees (SkillTrees): the data is valid and original, XP turns into
## levels and points, nodes need their prerequisites, tier points and a free
## point, ranks feed Perks (and the player, live), points come back on reset,
## fights / chapters / trials give XP, the three final skills work, and the
## pause menu's Skills tab learns a rank with a press.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player


func before_each() -> void:
	Profile.persist = false
	Profile.reset()
	Game.reset_records()
	SkillTrees.reload()


# Not a coroutine: the runner starts the next test without waiting.
func after_each() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
	Game.reset_records()
	Profile.reset()


func _load() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	await physics_frames(5)


func _foe(rank := &"genin", distance := 8.0) -> EnemyShinobi:
	var e := EnemyShinobi.new()
	e.rank = rank
	scene.add_child(e)
	e.global_position = player.global_position + Vector3(0, 0.1, -distance)
	return e


func _give_levels(levels: int) -> void:
	Game.add_xp(SkillTrees.xp_for_level(SkillTrees.level() + levels) - Game.xp())


func test_the_data_is_valid_and_original() -> void:
	assert_eq(SkillTrees.errors, [] as Array[String])
	assert_eq(SkillTrees.trees().size(), 3)
	var total := 0
	var banned := ["sharingan", "rasengan", "chidori", "kage bunshin", "byakugan", "rinnegan", "sage mode"]
	for t in SkillTrees.trees():
		var finals := 0
		for n: Dictionary in t["nodes"]:
			total += int(n["ranks"])
			finals += 1 if int(n["tier"]) == 5 else 0
			assert_true(UiKit.font(&"brush").has_char(str(n["kanji"]).unicode_at(0)), "%s's kanji is in the font" % n["id"])
			for word: String in banned:
				assert_false(str(n["name"]).to_lower().contains(word), "%s borrows %s" % [n["id"], word])
		assert_eq(finals, 1, "%s ends in one final skill" % t["id"])
	assert_true(total <= SkillTrees.max_level() - 1, "the highest level can learn everything (%d ranks)" % total)
	assert_true(UiKit.font(&"bold").has_char("技".unicode_at(0)), "the tab's kanji is in the font")


func test_xp_turns_into_levels_and_points() -> void:
	assert_eq(SkillTrees.level(), 1)
	assert_eq(SkillTrees.points_free(), 0)
	assert_eq(SkillTrees.xp_for_level(2), SkillTrees.xp_to_next(1))
	var levels: Array[int] = []
	Game.leveled_up.connect(func(l: int) -> void: levels.append(l))
	assert_eq(Game.add_xp(SkillTrees.xp_for_level(4)), 3, "three levels at once")
	assert_eq(levels, [2, 3, 4] as Array[int], "each level is announced")
	assert_eq(SkillTrees.points_free(), 3)
	assert_eq(SkillTrees.level_for_xp(SkillTrees.xp_for_level(6) - 1), 5)
	assert_eq(SkillTrees.level_for_xp(100000000), SkillTrees.max_level(), "levels stop at the cap")
	assert_near(SkillTrees.level_progress(), 0.0, 0.001)


func test_nodes_need_points_prerequisites_and_open_tiers() -> void:
	assert_eq(SkillTrees.can_learn("iron_hide"), SkillTrees.NO_POINTS)
	_give_levels(10)
	assert_eq(SkillTrees.can_learn("light_feet"), SkillTrees.NEEDS_NODE, "the branch needs its root")
	assert_true(SkillTrees.learn("iron_hide"))
	assert_true(SkillTrees.learn("light_feet"))
	assert_eq(SkillTrees.can_learn("wind_step"), SkillTrees.NEEDS_POINTS, "tier 3 needs 3 points in the tree")
	assert_true(SkillTrees.learn("light_feet"))
	assert_true(SkillTrees.learn("wind_step"))
	assert_true(SkillTrees.learn("iron_hide"))
	assert_true(SkillTrees.learn("iron_hide"))
	assert_eq(SkillTrees.can_learn("iron_hide"), SkillTrees.MAXED)
	assert_false(SkillTrees.learn("iron_hide"))
	assert_eq(SkillTrees.points_spent("body"), 6)
	assert_eq(SkillTrees.points_spent("chakra"), 0)
	assert_eq(SkillTrees.points_free(), 4)
	assert_eq(SkillTrees.can_learn("second_wind"), SkillTrees.NEEDS_NODE)
	SkillTrees.reset("body")
	assert_eq(SkillTrees.points_free(), 10, "points come back")
	assert_eq(SkillTrees.rank("iron_hide"), 0)


func test_ranks_feed_perks_and_the_player_live() -> void:
	await _load()
	var health := player.stats.max_health
	var chakra := player.stats.max_chakra
	_give_levels(6)
	SkillTrees.learn("iron_hide")
	SkillTrees.learn("iron_hide")
	assert_near(Perks.value(&"max_health"), 0.12, 0.001)
	assert_near(player.stats.max_health, health * 1.12, 0.01, "the player gets tougher at once")
	SkillTrees.learn("deep_well")
	assert_near(player.stats.max_chakra, chakra * 1.08, 0.01, "and the chakra well deeper")
	SkillTrees.reset()
	assert_near(player.stats.max_health, health, 0.01, "and back after a reset")


func test_natures_voice_boosts_only_the_clans_nature() -> void:
	Profile.set_value(&"clan", "hearth")
	var fire := Perks.damage_multiplier(Element.FIRE)
	var water := Perks.damage_multiplier(Element.WATER)
	Game.set_skill_ranks({"natures_voice": 2})
	assert_near(Perks.damage_multiplier(Element.FIRE) - fire, 0.16, 0.001)
	assert_near(Perks.damage_multiplier(Element.WATER), water, 0.001)


func test_gathering_storm_fills_the_ultimate_faster() -> void:
	await _load()
	player.ult_charge = 0.0
	Game.set_skill_ranks({"keen_eye": 1, "gathering_storm": 3})
	player.gain_ultimate(10.0)
	assert_near(player.ult_charge, 13.0, 0.01)


func test_defeating_enemies_clearing_trials_and_chapters_gives_xp() -> void:
	await _load()
	var foe := _foe(&"chunin")
	await seconds(EnemyShinobi.SPAWN_TIME + 0.1)
	foe.take_hit(99999.0, Element.NONE, player)
	assert_eq(Game.xp(), SkillTrees.xp_for("chunin"))
	var clone := _foe(&"genin", 3.0)
	await physics_frames(1)
	clone.dismiss()
	assert_eq(Game.xp(), SkillTrees.xp_for("chunin"), "sending one away gives nothing")
	SkillTrees.award("trial")
	assert_eq(Game.xp(), SkillTrees.xp_for("chunin") + SkillTrees.xp_for("trial"))
	assert_true(SkillTrees.xp_for("chapter") > SkillTrees.xp_for("chapter_replay"), "a first clear is worth more")


func test_second_wind_saves_you_once_then_comes_back() -> void:
	await _load()
	Game.set_skill_ranks({"second_wind": 1})
	var dealt := player.take_hit(99999.0, Element.NONE, null)
	assert_true(dealt > 0.0)
	assert_false(player.is_down(), "the blow doesn't defeat you")
	assert_near(player.stats.health, player.stats.max_health * SkillTrees.SECOND_WIND_HEALTH, 0.5)
	assert_false(player.second_wind_ready)
	assert_true(player.stats.is_invulnerable, "a moment untouchable")
	player.stats.is_invulnerable = false
	player.take_hit(99999.0, Element.NONE, null)
	assert_true(player.is_down(), "not twice in a row")
	player.revive()
	assert_true(player.second_wind_ready, "it's back for the next fight")


func test_without_second_wind_a_lethal_blow_is_lethal() -> void:
	await _load()
	player.take_hit(99999.0, Element.NONE, null)
	assert_true(player.is_down())


func test_twin_weave_fires_an_echo() -> void:
	await _load()
	var j := JutsuRegistry.get_jutsu(&"chakra_bolt")
	var count := func() -> int: return scene.find_children("*", "JutsuProjectile", true, false).size()
	player.stats.chakra = player.stats.max_chakra
	assert_true(player.caster.cast(j))
	await seconds(SkillTrees.TWIN_WEAVE_DELAY + 0.1)
	var plain: int = count.call()
	for p in scene.find_children("*", "JutsuProjectile", true, false):
		p.free()
	Game.set_skill_ranks({"twin_weave": 1})
	player.caster._cooldowns.clear()
	player.stats.chakra = player.stats.max_chakra
	assert_true(player.caster.cast(j))
	assert_eq(count.call(), plain, "the first shot goes at once")
	await seconds(SkillTrees.TWIN_WEAVE_DELAY + 0.1)
	assert_eq(count.call(), plain * 2, "then its echo")


func test_shadow_bloom_clones_burst_when_they_go() -> void:
	await _load()
	var foe := _foe(&"jonin", 4.0)
	var clone := EnemyShinobi.new()
	clone.team = &"player"
	clone.clone_of = player
	clone.lifetime = 10.0
	clone.bloom_power = SkillTrees.SHADOW_BLOOM_POWER
	scene.add_child(clone)
	clone.global_position = foe.global_position + Vector3(1.0, 0.0, 0.0)
	await seconds(EnemyShinobi.SPAWN_TIME + 0.1)
	var before := foe.stats.health
	clone.leave()
	assert_true(foe.stats.health < before, "the foe beside it is struck")
	assert_eq(Game.xp(), 0, "a clone going away isn't a defeat")


func test_the_skills_tab_learns_with_a_press() -> void:
	await _load()
	_give_levels(2)
	var menu: PauseMenu = scene.pause_menu
	menu.open()
	menu._select_tab(PauseMenu.TAB_SKILLS)
	await physics_frames(2)
	var panel: SkillTreePanel = menu._skills
	assert_true(panel._level.text.contains(str(SkillTrees.level())), "it shows the level")
	assert_true(panel._points.text.begins_with("2 skill points"))
	var root_node: SkillNodeButton = panel._nodes["iron_hide"]
	root_node.pressed.emit()
	assert_eq(SkillTrees.rank("iron_hide"), 1)
	assert_true(panel._points.text.begins_with("1 skill point"))
	assert_eq(root_node.rank, 1, "the seal shows its rank")
	(panel._tree_buttons["mind"] as Button).pressed.emit()
	assert_eq(panel.tree_id, "mind")
	assert_true(panel._nodes.has("shadow_bloom"))
	(panel._nodes["long_shadow"] as SkillNodeButton).pressed.emit()
	assert_eq(SkillTrees.rank("long_shadow"), 0, "a locked node stays locked")
	assert_true(panel._card_need.text.contains("Keen Eye"), "and says what it needs")
	menu.close()
