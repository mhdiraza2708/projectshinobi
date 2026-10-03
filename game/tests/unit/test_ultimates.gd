extends TestCase
## Ultimates: the data, the meter (charged by fighting), unleashing one (a
## frozen world, a title card, the blow), and choosing yours.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player


func before_each() -> void:
	Profile.persist = false
	Profile.reset()
	# The meter carries over between fights: start each test empty.
	Game.set_ult_charge(0.0)
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player


func after_each() -> void:
	if UltimateSequence.active:
		UltimateSequence.active.skip()
	scene.queue_free()
	Profile.reset()


func _foe(at: Vector3, rank := &"genin") -> EnemyShinobi:
	var e := EnemyShinobi.new()
	e.rank = rank
	e.element = Element.WIND
	scene.add_child(e)
	e.global_position = at
	return e


## Foes smoke in and can't be hurt for their first EnemyShinobi.SPAWN_TIME.
func _ready_foes() -> void:
	await physics_frames(ceili(EnemyShinobi.SPAWN_TIME * 60.0) + 6)


func test_the_data_is_valid_and_original() -> void:
	Ultimates.reload()
	assert_eq(Ultimates.errors, [] as Array[String])
	var natures := {}
	for u in Ultimates.all():
		natures[u["element_id"]] = true
		for ch in str(u["kanji"]):
			assert_true(UiKit.font(&"brush").has_char(ch.unicode_at(0)), "%s's kanji %s is in the font" % [u["id"], ch])
	for e in [Element.NONE, Element.FIRE, Element.WIND, Element.LIGHTNING, Element.EARTH, Element.WATER]:
		assert_true(natures.has(e), "an ultimate for %s" % Element.display_name(e))


func test_fighting_fills_the_meter() -> void:
	await physics_frames(3)
	var dummy: Node = scene.find_children("*", "TrainingDummy", true, false)[0]
	var dealt := Combat.apply_hit(dummy, 20.0, Element.NONE, player)
	assert_near(player.ult_charge, dealt * Ultimates.PER_DAMAGE_DEALT, 0.01, "landing a blow charges it")
	var before := player.ult_charge
	player.take_hit(10.0, Element.NONE, null)
	assert_true(player.ult_charge > before, "and so does taking one")
	player.gain_ultimate(1000.0)
	assert_eq(player.ult_charge, Ultimates.MAX_CHARGE, "it stops at full")
	assert_true(player.ultimate_ready())


func test_a_shade_clones_blows_charge_its_owner() -> void:
	await physics_frames(3)
	var clone := EnemyShinobi.new()
	clone.team = &"player"
	clone.clone_of = player
	scene.add_child(clone)
	var foe := _foe(player.global_position + Vector3(0, 0, -6))
	await _ready_foes()
	Combat.apply_hit(foe, 10.0, Element.NONE, clone)
	assert_true(player.ult_charge > 0.0)


func test_it_cannot_be_used_until_full() -> void:
	await physics_frames(3)
	player.ult_charge = 40.0
	assert_false(player.try_ultimate())
	assert_true(UltimateSequence.active == null)


func test_unleashing_freezes_the_world_and_lands_the_blow() -> void:
	await physics_frames(3)
	Profile.set_value(&"affinity", Element.FIRE)
	var foes := [_foe(player.global_position + Vector3(-1.5, 0.1, -7)), _foe(player.global_position + Vector3(1.5, 0.1, -7))]
	await _ready_foes()
	player.ult_charge = Ultimates.MAX_CHARGE
	var used := []
	player.ultimate_used.connect(func(u: Dictionary) -> void: used.append(u["id"]))
	assert_true(player.try_ultimate(), "a full meter unleashes it")
	assert_eq(used, ["hearthfall"], "the fire nature's own ultimate")
	assert_eq(player.ult_charge, 0.0, "the meter empties")
	var seq := UltimateSequence.active
	assert_true(seq != null)
	assert_true(seq.frozen_count() >= 2, "the foes stand frozen")
	for f: EnemyShinobi in foes:
		assert_eq(f.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_false(player.input_enabled, "the player is in the cinematic")
	assert_true(player.stats.is_invulnerable, "and can't be hurt during it")
	assert_false(scene.hud.visible, "the HUD steps aside")
	await seconds(0.4)
	assert_true(seq.card_text().contains("HEARTHFALL") and seq.card_text().contains("陽墜"), "the title card")
	await seq.finished
	await root.get_tree().process_frame
	for f: Variant in foes:
		# Defeated foes are freed; the rest must be hurt and moving again.
		if is_instance_valid(f):
			assert_true(f.stats.health < f.stats.max_health, "the blow landed")
			assert_true(f.process_mode != Node.PROCESS_MODE_DISABLED, "time moves again")
	assert_true(player.input_enabled)
	assert_true(scene.hud.visible, "the HUD is back")
	assert_eq(player.ult_charge, 0.0, "its own blow doesn't refill the meter")


func test_every_ultimate_plays_and_hits() -> void:
	await physics_frames(3)
	for u in Ultimates.all():
		var nature: int = u["element_id"] if u["element_id"] != Element.NONE else Element.FIRE
		Profile.set_value(&"affinity", nature)
		Profile.set_value(&"ultimate", u["id"])
		var foe := _foe(player.global_position + Vector3(0.5, 0.1, -6.5), &"jonin")
		await _ready_foes()
		player.ult_charge = Ultimates.MAX_CHARGE
		assert_true(player.try_ultimate(), "%s starts" % u["id"])
		assert_eq(UltimateSequence.active.ult["id"], u["id"])
		var seq := UltimateSequence.active
		await seq.finished
		assert_true(is_instance_valid(foe) and foe.stats.health < foe.stats.max_health, "%s hit the foe" % u["id"])
		foe.queue_free()
		player.stats.is_invulnerable = false
		await physics_frames(2)


func test_the_cyclone_lifts_its_targets() -> void:
	await physics_frames(3)
	Profile.set_value(&"affinity", Element.WIND)
	var foe := _foe(player.global_position + Vector3(0, 0.1, -6), &"jonin")
	await _ready_foes()
	var ground_y := foe.global_position.y
	player.ult_charge = Ultimates.MAX_CHARGE
	player.try_ultimate()
	await seconds(UltimateSequence.CLOSE_TIME + 0.75)
	assert_true(foe.global_position.y > ground_y + 1.0, "lifted (%.2f above the ground)" % (foe.global_position.y - ground_y))
	await UltimateSequence.active.finished
	assert_near(foe.global_position.y, ground_y, 0.3, "and set down again")


func test_holding_pause_skips_to_the_blow() -> void:
	await physics_frames(3)
	var foe := _foe(player.global_position + Vector3(0, 0.1, -6), &"jonin")
	await _ready_foes()
	player.ult_charge = Ultimates.MAX_CHARGE
	player.try_ultimate()
	var seq := UltimateSequence.active
	var started := Time.get_ticks_msec()
	Input.action_press(&"pause")
	await seq.finished
	Input.action_release(&"pause")
	assert_true(Time.get_ticks_msec() - started < 2200, "much shorter than the full cinematic")
	assert_true(foe.stats.health < foe.stats.max_health, "the blow still lands")
	assert_false(scene.pause_menu.is_open(), "holding Pause didn't open the menu")


func test_choosing_an_ultimate() -> void:
	Profile.set_value(&"affinity", Element.WATER)
	assert_eq(Ultimates.equipped()["id"], "leviathan_tide", "your nature's own by default")
	Profile.set_value(&"ultimate", "hundred_shades")
	assert_eq(Ultimates.equipped()["id"], "hundred_shades", "or the one any nature can learn")
	Profile.set_value(&"ultimate", "hearthfall")
	assert_eq(Ultimates.equipped()["id"], "leviathan_tide", "but not another nature's")
	var panel := LoadoutPanel.new()
	root.add_child(panel)
	var buttons := panel.find_children("*", "Button", true, false).filter(
		func(b: Button) -> bool: return str(b.get_meta(&"focus_key", "")).begins_with("ult_"))
	assert_eq(buttons.size(), Ultimates.all().size(), "a row for each")
	var fire: Button = buttons.filter(func(b: Button) -> bool: return b.get_meta(&"focus_key") == "ult_hearthfall")[0]
	assert_true(fire.disabled, "another nature's is locked")
	panel._equip_ultimate("hundred_shades")
	assert_eq(Profile.get_value(&"ultimate"), "hundred_shades")
	panel.queue_free()


func test_the_hud_shows_the_meter() -> void:
	await physics_frames(3)
	player.gain_ultimate(50.0)
	assert_true(scene.hud._ult_text.text.begins_with("50"), "half full (%s)" % scene.hud._ult_text.text)
	player.gain_ultimate(50.0)
	assert_true(scene.hud._ult_text.text.begins_with("READY"), "ready, with the button")


func test_the_meter_keeps_its_charge_between_fights() -> void:
	await physics_frames(2)
	player.gain_ultimate(60.0)
	scene.queue_free()
	await physics_frames(2)
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	await physics_frames(2)
	assert_near(player.ult_charge, 60.0, 0.01, "the next fight starts where the last one left off")
	assert_near(Game.ult_charge(), 60.0, 0.01, "and it's kept with the save")

