extends TestCase
## Clans and eye arts: the data is valid and original, choosing them changes
## what the character can do, and each eye art's effect works in play.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player


func after_each() -> void:
	Profile.reset()
	Engine.time_scale = 1.0
	Input.action_release(&"guard")


func _load() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	await physics_frames(5)


func test_the_data_is_valid() -> void:
	Perks.reload()
	assert_eq(Perks.errors, [] as Array[String], "clans and eye arts load cleanly")
	assert_eq(Perks.clans().size(), 6, "five natures' clans and the wayfarer")
	assert_eq(Perks.eye_arts().size(), 4)
	for clan in Perks.clans():
		assert_true(Perks.arts_for(clan["id"]).size() >= 2, "%s has eye arts to choose from" % clan["id"])
		assert_true(UiKit.font(&"brush").has_char(str(clan["kanji"]).unicode_at(0)), "%s's crest is in the font" % clan["id"])
	for art in Perks.eye_arts():
		assert_true(UiKit.font(&"brush").has_char(str(art["kanji"]).unicode_at(0)), "%s's kanji is in the font" % art["id"])


func test_no_clan_or_art_borrows_a_canon_name() -> void:
	# The design doc rules out the source material's names and abilities.
	var banned := ["uchiha", "hyuga", "hyūga", "uzumaki", "sharingan", "byakugan", "rinnegan", "nara", "akimichi", "senju", "sarutobi"]
	for entry in Perks.clans() + Perks.eye_arts():
		var text := (str(entry["name"]) + " " + str(entry["blurb"])).to_lower()
		for word: String in banned:
			assert_false(text.contains(word), "%s mentions %s" % [entry["id"], word])


func test_a_clan_gives_its_perks_and_only_its_eye_arts() -> void:
	Profile.set_value(&"clan", "stonewright")
	assert_near(Perks.value(&"max_health"), 0.25, 0.001)
	assert_near(Perks.damage_multiplier(Element.EARTH), 1.08, 0.001)
	assert_near(Perks.damage_multiplier(Element.FIRE), 1.0, 0.001, "other natures get nothing")
	Profile.set_value(&"eye_art", "mirror_eye")
	assert_true(Perks.active_eye_art().is_empty(), "a Stonewright can't take Mirror Eye")
	Profile.set_value(&"eye_art", "still_eye")
	assert_eq(Perks.active_eye_art()["id"], "still_eye")
	assert_true(Perks.has(&"perfect_guard"))
	Profile.set_value(&"clan", "")
	assert_false(Perks.has(&"perfect_guard"), "without the clan the art is lost")
	assert_near(Perks.value(&"max_health"), 0.0, 0.001)


func test_perks_read_in_words() -> void:
	var lines := Perks.describe(Perks.clan("gale")["perks"])
	assert_true(lines.has("+10% run speed"), str(lines))
	assert_true(lines.has("-25% dash cooldown"), str(lines))
	assert_true(lines.has("+8% Wind damage"), str(lines))
	assert_true(Perks.describe(Perks.clan("wayfarer")["perks"]).has("+1 Shade Clone"))


func test_clan_changes_the_player() -> void:
	await _load()
	var base_health := player.stats.max_health
	var base_run := player.run_speed
	var base_dash := player.dash_cooldown
	Profile.set_value(&"clan", "gale")
	assert_near(player.run_speed, base_run * 1.10, 0.01, "faster")
	assert_near(player.dash_cooldown, base_dash * 0.75, 0.01, "dashes sooner")
	Profile.set_value(&"clan", "stonewright")
	assert_near(player.stats.max_health, base_health * 1.25, 0.1, "tougher")
	assert_near(player.run_speed, base_run, 0.01, "and the old clan's speed is gone")
	assert_near(player.guard_damage_multiplier, 0.3 * 0.75, 0.001, "guards block more")
	Profile.set_value(&"clan", "tidebound")
	assert_near(player.stats.chakra_regen, 3.0 * 1.4, 0.01, "recovers chakra faster")
	Profile.set_value(&"clan", "")
	assert_near(player.stats.max_health, base_health, 0.1, "no clan, no bonus")


func test_damage_cost_and_healing_follow_the_clan() -> void:
	await _load()
	var ember := JutsuRegistry.get_jutsu(&"ember_volley")
	var plain := player.caster.cost_of(ember)
	Profile.set_value(&"clan", "wayfarer")
	assert_near(player.caster.cost_of(ember), plain * 0.92 * (1.0 / 0.8) * 0.8, 0.01, "wayfarers pay less")
	var enemy_caster := JutsuCaster.new()
	enemy_caster.stats = Stats.new()
	assert_near(enemy_caster.cost_of(ember), ember.chakra_cost, 0.001, "only the player has perks")
	enemy_caster.free()
	Profile.set_value(&"clan", "tidebound")
	player.stats.health = 10.0
	player.stats.chakra = 100.0
	var mending := JutsuRegistry.get_jutsu(&"mending_palm")
	player.caster._cooldowns.clear()
	player.caster.cast(mending)
	assert_near(player.stats.health, 10.0 + mending.power * 1.25, 0.1, "heals 25% more")


func test_hawk_eye_reaches_further_and_names_who_is_weak() -> void:
	await _load()
	var base_range := player.lock_range
	Profile.set_value(&"clan", "hearth")
	Profile.set_value(&"eye_art", "hawk_eye")
	assert_near(player.lock_range, base_range * 1.6, 0.01, "lock-on reaches further")
	var water := EnemyShinobi.new()
	water.element = Element.WATER
	scene.add_child(water)
	var wind := EnemyShinobi.new()
	wind.element = Element.WIND
	scene.add_child(wind)
	await physics_frames(40)
	Profile.set_value(&"affinity", Element.FIRE)
	water._update_hint()
	wind._update_hint()
	assert_eq(water._hint_label.text, "▼", "fire is resisted by water")
	assert_eq(wind._hint_label.text, "▲", "fire beats wind")
	assert_true(wind._hint_label.visible)
	Profile.set_value(&"eye_art", "")
	wind._update_hint()
	assert_false(wind._hint_label.visible, "no eye art, no hint")


func test_seal_eye_slows_rivals_and_speeds_you() -> void:
	await _load()
	var before := EnemyShinobi.new()
	scene.add_child(before)
	await physics_frames(2)
	var plain: float = before._r["seal_time"]
	Profile.set_value(&"clan", "gale")
	Profile.set_value(&"eye_art", "seal_eye")
	var after := EnemyShinobi.new()
	scene.add_child(after)
	await physics_frames(2)
	assert_near(after._r["seal_time"], plain * 1.4, 0.001, "rivals' seals come slower")
	var ally := EnemyShinobi.new()
	ally.team = &"player"
	scene.add_child(ally)
	await physics_frames(2)
	assert_near(ally._r["seal_time"], plain, 0.001, "allies are not slowed")
	var normal := float(Settings.get_value(&"auto_weave_seal_time"))
	assert_near(player._seal_time(), normal * 0.75, 0.001, "your own weave is quicker")


func test_still_eye_blocks_a_well_timed_guard() -> void:
	await _load()
	Profile.set_value(&"clan", "stonewright")
	Profile.set_value(&"eye_art", "still_eye")
	player.stats.chakra = 20.0
	Input.action_press(&"guard")
	await physics_frames(4)
	assert_eq(player.state, Player.State.GUARDING)
	var hp := player.stats.health
	player.take_hit(30.0, Element.NONE, null)
	assert_near(player.stats.health, hp, 0.001, "an early guard takes nothing")
	assert_true(player.stats.chakra > 20.0, "and refunds chakra")
	await seconds(0.4)
	var late := player.stats.health
	player.take_hit(30.0, Element.NONE, null)
	assert_true(player.stats.health < late, "a late guard only softens the blow")
	assert_true(late - player.stats.health < 30.0 * 0.3, "though Stonewright guards well")


func test_mirror_eye_slows_time_after_a_dodge() -> void:
	await _load()
	Profile.set_value(&"clan", "hearth")
	Profile.set_value(&"eye_art", "mirror_eye")
	player.stats.chakra = 30.0
	player._enter(Player.State.DASHING)
	player.stats.is_invulnerable = true
	player.take_hit(25.0, Element.NONE, null)
	assert_near(Engine.time_scale, Perks.FOCUS_TIME_SCALE, 0.001, "the world slows")
	assert_near(player.stats.health, player.stats.max_health, 0.001, "and nothing landed")
	assert_true(player.stats.chakra >= 30.0 + Perks.FOCUS_CHAKRA - 0.5, "chakra steadied")
	await seconds(0.9)
	assert_near(Engine.time_scale, 1.0, 0.001, "back to normal")
	Profile.set_value(&"eye_art", "")
	player._enter(Player.State.FREE)
	player._enter(Player.State.DASHING)
	player.stats.is_invulnerable = true
	player.take_hit(25.0, Element.NONE, null)
	assert_near(Engine.time_scale, 1.0, 0.001, "no eye art, no slow-motion")


func test_eye_arts_colour_the_eyes() -> void:
	await _load()
	Profile.set_value(&"clan", "hearth")
	Profile.set_value(&"eye_art", "hawk_eye")
	var look := player.model.current_look()
	assert_eq(look[&"tints"]["eyes"], Color("#e3a23a"), "amber eyes")
	Profile.set_value(&"eye_art", "")
	assert_false((player.model.current_look()[&"tints"] as Dictionary).has("eyes"))


## Exports only pack .json files the preset names: a data file outside its
## include filter works in the editor and goes missing in the shipped game.
func test_every_data_folder_is_packed_into_the_export() -> void:
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	var filters := ""
	for line in cfg.split("\n"):
		if line.begins_with("include_filter=") and "data/" in line:
			filters = line
			break
	assert_true(filters != "", "the export preset lists its data files")
	assert_true("data/*.json" in filters, "clans.json and eye_arts.json are packed")
	for dir in DirAccess.get_directories_at("res://data"):
		assert_true(("data/%s/*.json" % dir) in filters, "data/%s is packed" % dir)
