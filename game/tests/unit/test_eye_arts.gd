extends TestCase
## Opening an eye art in battle (EyeArtMode, EyeSequence, EyeInsert,
## EyePattern): the data is valid and original, opening costs chakra and
## adds the open form's perks for a while, every opening plays the close-up
## and its drawn cut-in of the eyes, the eye closes and rests, it awakens
## after Part One, and the pattern finds the irises on a VRoid model.

const Scene := preload("res://scenes/training_ground.tscn")
const VROID := "res://assets/characters/roster/sendagaya_shino.vrm"

var scene: Node3D
var player: Player


func before_each() -> void:
	Profile.persist = false
	Profile.reset()
	EyeArtMode.reset_seen()


# Not a coroutine: the runner starts the next test without waiting.
func after_each() -> void:
	for action: StringName in [&"quick_shift", &"charge_chakra", &"guard"]:
		Input.action_release(action)
	if is_instance_valid(scene):
		scene.queue_free()
	EyeArtMode.boost = {}
	Game.reset_records()
	Profile.reset()


func _load(art_id := "hawk_eye") -> void:
	for clan in Perks.clans():
		if (clan["eye_arts"] as Array).has(art_id):
			Profile.set_value(&"clan", clan["id"])
			break
	Profile.set_value(&"eye_art", art_id)
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	await physics_frames(5)
	player.stats.chakra = player.stats.max_chakra


func _foe() -> EnemyShinobi:
	var e := EnemyShinobi.new()
	e.rank = &"genin"
	scene.add_child(e)
	e.global_position = player.global_position + Vector3(0, 0.1, -8.0)
	return e


func test_the_data_is_valid_and_original() -> void:
	Perks.reload()
	assert_eq(Perks.errors, [] as Array[String])
	var banned := ["sharingan", "mangekyo", "mangekyou", "byakugan", "rinnegan", "tenseigan", "tomoe", "uchiha"]
	for art in Perks.eye_arts():
		assert_true(EyePattern.PATTERNS.has(str(art["pattern"])), "%s has a pattern" % art["id"])
		for form_key in ["active", "awakened"]:
			var f: Dictionary = art[form_key]
			assert_true(float(f["seconds"]) > 0.0 and float(f["cost"]) > 0.0, "%s %s" % [art["id"], form_key])
			for word: String in banned:
				assert_false(str(f["name"]).to_lower().contains(word), "%s borrows %s" % [art["id"], word])
		var kanji := str(art["awakened"]["kanji"])
		assert_true(UiKit.font(&"brush").has_char(kanji.unicode_at(0)), "%s's awakened kanji is in the font" % art["id"])
	assert_true(Story.load_all().chapters.any(func(c: Dictionary) -> bool: return c["id"] == Perks.awaken_after()),
		"eyes awaken after a real chapter")


func test_opening_costs_chakra_adds_perks_and_plays_the_close_up() -> void:
	await _load("hawk_eye")
	var foe := _foe()
	await physics_frames(2)
	var homing_before := Perks.value(&"homing")
	var chakra := player.stats.chakra
	assert_true(player.eye_mode.try_open())
	assert_near(chakra - player.stats.chakra, player.eye_mode.cost(), 0.5, "it costs the form's chakra")
	assert_near(Perks.value(&"homing") - homing_before, float(EyeArtMode.form()["perks"]["homing"]), 0.001,
		"the open form's perks add to the eye art's")
	assert_true(EyeSequence.active != null, "the first opening here is a close-up")
	assert_true(EyeSequence.active.frozen_count() >= 1, "the world stands still")
	assert_eq(foe.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_true(EyeSequence.active.insert() == null, "in on the face first")
	await seconds(EyeSequence.CUT_AT + 0.15)
	var insert := EyeSequence.active.insert()
	assert_true(insert != null, "then a cut to the drawn eyes")
	assert_true(Sfx.history.has(&"eye_open"), "with its sound")
	assert_true(insert.lids() < 0.5, "still shut under the bangs")
	await seconds(EyeSequence.LIDS_OPEN.y + 0.1)
	assert_true(insert.lids() > 0.9, "the eyes open")
	assert_true(EyeSequence.active.card_text().contains("Talon Sight".to_upper()), "the card names the form")
	assert_false(scene.hud.visible, "the HUD steps aside")
	await seconds(EyeSequence.OPEN_TIME)
	assert_true(EyeSequence.active == null, "and it ends")
	assert_false(is_instance_valid(insert), "the cut-in goes with it")
	assert_true(scene.hud.visible)
	assert_true(foe.process_mode != Node.PROCESS_MODE_DISABLED, "time moves again")
	assert_eq(player.eye_mode.phase, EyeArtMode.Phase.ACTIVE)


func test_every_opening_plays_the_close_up_then_it_closes_and_rests() -> void:
	await _load("mirror_eye")
	var run := player.run_speed
	assert_true(player.eye_mode.try_open())
	EyeSequence.active.skip()
	await physics_frames(3)
	assert_true(player.run_speed > run, "Mirror Eye's open form is faster on its feet")
	player.eye_mode.time_left = 0.05
	await physics_frames(6)
	assert_eq(player.eye_mode.phase, EyeArtMode.Phase.RECOVERING, "time ran out")
	assert_near(player.run_speed, run, 0.001, "the perks go with it")
	assert_true(EyeArtMode.boost.is_empty())
	assert_false(player.eye_mode.try_open(), "a resting eye can't open")
	player.eye_mode.time_left = 0.05
	await physics_frames(6)
	assert_eq(player.eye_mode.phase, EyeArtMode.Phase.READY)
	player.stats.chakra = player.stats.max_chakra
	assert_true(player.eye_mode.try_open())
	assert_true(EyeSequence.active != null, "the second opening plays the close-up too")
	EyeSequence.active.skip()


func test_it_needs_chakra_and_an_eye_art() -> void:
	await _load("seal_eye")
	player.stats.chakra = 5.0
	assert_false(player.eye_mode.try_open(), "not enough chakra")
	assert_eq(player.eye_mode.phase, EyeArtMode.Phase.READY)
	Profile.set_value(&"eye_art", "")
	player.stats.chakra = player.stats.max_chakra
	assert_false(player.eye_mode.try_open(), "no eye art, nothing to open")


func test_page_shift_and_charge_opens_it_instead_of_charging() -> void:
	await _load("still_eye")
	Input.action_press(&"quick_shift")
	await physics_frames(2)
	Input.action_press(&"charge_chakra")
	await physics_frames(3)
	assert_eq(player.eye_mode.phase, EyeArtMode.Phase.ACTIVE, "LB + Y opened the eye")
	assert_true(player.state != Player.State.CHARGING, "and didn't charge chakra")


func test_the_eye_awakens_after_part_one() -> void:
	await _load("still_eye")
	assert_eq(EyeArtMode.form()["name"], Perks.eye_art("still_eye")["active"]["name"])
	Game.mark_chapter_done(Perks.awaken_after())
	assert_true(EyeArtMode.awakening_unlocked())
	assert_eq(EyeArtMode.form()["name"], "Lotus Eye")
	assert_true(player.eye_mode.try_open())
	assert_true(player.eye_mode.awakened)
	await seconds(EyeSequence.OPEN_TIME + 0.4)
	assert_true(EyeSequence.active.card_text().contains("AWAKENED"), "the awakening has its own card")
	assert_near(Perks.value(&"heal"), 1.0, 0.001, "and the stronger perks")


func test_the_pattern_finds_a_vroid_models_irises() -> void:
	var model: Node = (load(VROID) as PackedScene).instantiate()
	root.add_child(model)
	var irises := EyePattern.iris_materials(model)
	assert_true(irises.size() >= 1, "the iris material is found")
	var layout := EyePattern.layout_of(irises[0])
	assert_true((layout["a"] as Vector2).distance_to(Vector2(0.25, 0.5)) < 0.06, "one iris on the left of the texture")
	assert_true((layout["b"] as Vector2).distance_to(Vector2(0.75, 0.5)) < 0.06, "the other on the right")
	var mat := EyePattern.attach(model, Perks.eye_art("seal_eye"))
	assert_true(mat != null and irises[0].next_pass == mat, "drawn over the irises")
	assert_eq(mat.get_shader_parameter(&"pattern"), EyePattern.PATTERNS.find("seal"))
	EyePattern.detach(model)
	assert_true(irises[0].next_pass == null, "and taken off again")
	model.queue_free()


## A fire jutsu from `foe` flying at the player from a couple of metres.
func _incoming(foe: Node3D) -> JutsuProjectile:
	var p := JutsuProjectile.new()
	p.element = Element.FIRE
	p.power = 20.0
	p.caster = foe
	var from := player.global_position + Vector3(0, 1.1, -2.5)
	p.direction = (player.global_position + Vector3.UP * 1.1 - from).normalized()
	scene.add_child(p)
	p.global_position = from
	return p


func test_awakened_mirror_eye_absorbs_and_returns_jutsu() -> void:
	await _load("mirror_eye")
	Game.mark_chapter_done(Perks.awaken_after())
	var foe := _foe()
	assert_true(player.eye_mode.try_open())
	EyeSequence.active.skip()
	await physics_frames(3)
	assert_eq(player.eye_mode.ability(), "mirror_return")
	Input.action_press(&"guard")
	await physics_frames(3)
	var health := player.stats.health
	_incoming(foe)
	await physics_frames(12)
	assert_eq(player.eye_mode.held.size(), 1, "the guard swallowed the jutsu")
	assert_near(player.stats.health, health, 0.01, "and it did no harm")
	Input.action_release(&"guard")
	await physics_frames(2)
	assert_true(player.eye_mode.release(), "the chord throws it back")
	assert_true(player.eye_mode.held.is_empty())
	var mine := scene.find_children("*", "JutsuProjectile", true, false).filter(
		func(n: Node) -> bool: return (n as JutsuProjectile).caster == player)
	assert_eq(mine.size(), 1, "one returned jutsu, the player's now")
	assert_near((mine[0] as JutsuProjectile).power, 20.0 * EyeArtMode.MIRROR_POWER * Perks.damage_multiplier(Element.FIRE), 0.01,
		"and stronger")


func test_only_the_awakened_mirror_eye_absorbs() -> void:
	await _load("mirror_eye")
	var foe := _foe()
	assert_true(player.eye_mode.try_open())
	EyeSequence.active.skip()
	await physics_frames(3)
	assert_eq(player.eye_mode.ability(), "", "its first form has no ability")
	Input.action_press(&"guard")
	await physics_frames(3)
	_incoming(foe)
	await physics_frames(12)
	assert_true(player.eye_mode.held.is_empty(), "nothing absorbed before awakening")

