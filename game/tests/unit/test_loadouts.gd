extends TestCase
## Jutsu loadouts: eight quick-cast slots filled from named presets that can
## be made, renamed, copied and deleted, are saved with the character, and
## switch in play; slots can be instant (no seals, more chakra).

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player


func after_each() -> void:
	Profile.reset()
	for action: StringName in DefaultBindings.table():
		Input.action_release(action)
	InputDevice.current = Binding.Device.KEYBOARD_MOUSE


func _load() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	await physics_frames(5)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await physics_frames(3)
	Input.action_release(action)
	await physics_frames(2)


func test_a_new_game_has_starter_presets() -> void:
	var list := Loadouts.all()
	assert_eq(list.size(), 3)
	assert_eq(list[0]["name"], "Balanced")
	assert_eq((list[0]["slots"] as Array).size(), Loadouts.SLOTS)
	for preset: Dictionary in list:
		for id: String in preset["slots"]:
			assert_true(id == "" or JutsuRegistry.get_jutsu(StringName(id)) != null, "%s is a real jutsu" % id)
		assert_eq((preset["styles"] as Array).size(), Loadouts.SLOTS)
	for preset: Dictionary in list:
		assert_eq(preset["slots"][Loadouts.CLONES_SLOT], "shade_clones", "%s keeps Shade Clones on the first page" % preset["name"])


func test_the_starters_are_built_round_your_nature() -> void:
	for nature in [Element.FIRE, Element.WIND, Element.LIGHTNING, Element.EARTH, Element.WATER]:
		var own := JutsuRegistry.all().filter(func(j: JutsuDefinition) -> bool: return j.element == nature)
		assert_true(own.size() >= 3, "%s has jutsu of its own" % Element.display_name(nature))
		var list := Loadouts.starters(nature)
		for preset: Dictionary in list:
			var slots: Array = preset["slots"]
			for j: JutsuDefinition in own:
				assert_true(slots.has(String(j.id)), "%s %s has %s" % [Element.display_name(nature), preset["name"], j.id])
			assert_eq(slots[Loadouts.CLONES_SLOT], "shade_clones")
			for id: String in slots:
				var j := JutsuRegistry.get_jutsu(StringName(id))
				assert_true(id == "" or j != null)
				assert_true(id == "" or j.element == nature or j.element == Element.NONE,
					"%s %s: only its own nature and neutral jutsu (%s)" % [Element.display_name(nature), preset["name"], id])
		# Balanced and Assault lead with the nature's own jutsu.
		for k in 2:
			assert_eq(JutsuRegistry.get_jutsu(StringName(list[k]["slots"][0])).element, nature,
				"%s %s leads with its nature" % [Element.display_name(nature), list[k]["name"]])


func test_untouched_starters_follow_a_change_of_nature_but_your_own_presets_stay() -> void:
	Profile.set_value(&"affinity", Element.WATER)
	assert_eq(JutsuRegistry.get_jutsu(StringName(Loadouts.active()["slots"][0])).element, Element.WATER)
	Loadouts.equip(1)  # stores the (unchanged) starters
	Profile.set_value(&"affinity", Element.EARTH)
	assert_eq(Loadouts.index(), 1, "still on the same preset")
	assert_eq(JutsuRegistry.get_jutsu(StringName(Loadouts.active()["slots"][0])).element, Element.EARTH,
		"unchanged starters became earth's")
	# An old save's fixed starters count as untouched too.
	var legacy := Loadouts.LEGACY.map(func(p: Array) -> Dictionary: return Loadouts._preset(p[0], p[1]))
	Profile.set_value(&"loadouts", legacy)
	assert_eq(Loadouts.all(), Loadouts.starters(), "an old save's starters follow your nature")
	# A preset you changed is yours: a new nature leaves it be.
	Loadouts.assign(0, &"tide_lance")
	Profile.set_value(&"affinity", Element.WIND)
	assert_eq(Loadouts.active()["slots"][0], "tide_lance", "your own loadout is kept")


func _weave_all() -> Array:
	var styles := []
	styles.resize(Loadouts.SLOTS)
	styles.fill(Loadouts.WEAVE)
	return styles


func test_shade_clones_is_locked_into_every_preset() -> void:
	Loadouts.add("Empty", false)
	Loadouts.duplicate_preset(0)
	Loadouts.assign(0, &"gale_palm", 1)
	for p: Dictionary in Loadouts.all():
		assert_eq(p["slots"][Loadouts.CLONES_SLOT], "shade_clones",
			"%s has Shade Clones in slot %d" % [p["name"], Loadouts.CLONES_SLOT + 1])
	var legacy := Loadouts.LEGACY.map(func(p: Array) -> Dictionary: return Loadouts._preset(p[0], p[1]))
	Profile.set_value(&"loadouts", legacy)
	for p: Dictionary in Loadouts.all():
		assert_eq(p["slots"][Loadouts.CLONES_SLOT], "shade_clones", "an old save's %s too" % p["name"])

	# A saved preset without it gets it back; what held the slot moves to the
	# first empty one, with its cast style.
	var styles := _weave_all()
	styles[3] = Loadouts.INSTANT
	Profile.set_value(&"loadouts", [{"name": "Mine", "styles": styles,
		"slots": ["tide_lance", "gale_palm", "", "chakra_bolt", "", "", "", ""]}])
	var slots: Array = Loadouts.active()["slots"]
	assert_eq(slots[Loadouts.CLONES_SLOT], "shade_clones")
	assert_eq(slots[2], "chakra_bolt", "the bolt moved to the empty slot")
	assert_eq(Loadouts.style_in(Loadouts.active(), 2), Loadouts.INSTANT, "keeping its style")
	assert_eq(Loadouts.style_in(Loadouts.active(), Loadouts.CLONES_SLOT), Loadouts.WEAVE)
	assert_eq(slots.slice(0, 2), ["tide_lance", "gale_palm"], "the rest stay put")

	# Saved in another slot: it moves to its own, keeping its style.
	styles = _weave_all()
	styles[7] = Loadouts.INSTANT
	Profile.set_value(&"loadouts", [{"name": "Mine", "styles": styles,
		"slots": ["", "", "", "tide_lance", "", "", "", "shade_clones"]}])
	slots = Loadouts.active()["slots"]
	assert_eq(slots[Loadouts.CLONES_SLOT], "shade_clones")
	assert_eq(slots.count("shade_clones"), 1, "in one slot only")
	assert_eq(Loadouts.style_in(Loadouts.active(), Loadouts.CLONES_SLOT), Loadouts.INSTANT)
	assert_eq(slots[0], "tide_lance", "what held its slot moved")

	# Nothing replaces it, clears it or moves it.
	var before := (Loadouts.active()["slots"] as Array).duplicate()
	Loadouts.assign(Loadouts.CLONES_SLOT, &"gale_palm")
	Loadouts.assign(Loadouts.CLONES_SLOT, &"")
	Loadouts.assign(5, &"shade_clones")
	assert_eq(Loadouts.active()["slots"], before, "its slot is locked")
	# Its cast style can still change.
	Loadouts.set_style(Loadouts.CLONES_SLOT, Loadouts.WEAVE)
	assert_eq(Loadouts.style_in(Loadouts.active(), Loadouts.CLONES_SLOT), Loadouts.WEAVE)


func test_presets_can_be_made_renamed_copied_and_deleted() -> void:
	var made := Loadouts.add("Duelling")
	assert_eq(made, 3, "added at the end")
	assert_eq(Loadouts.index(), 3, "and equipped")
	assert_eq(Loadouts.active()["name"], "Duelling")
	assert_eq(Loadouts.active()["slots"], Loadouts.all()[0]["slots"], "starts as a copy of the one you had")
	Loadouts.rename(3, "  A really very long loadout name  ")
	assert_eq(Loadouts.active()["name"].length(), Loadouts.MAX_NAME, "names are kept short")
	Loadouts.rename(3, "   ")
	assert_eq(Loadouts.active()["name"], "Loadout", "never blank")
	var copy := Loadouts.duplicate_preset(0)
	assert_eq(Loadouts.all()[copy]["name"], "Balanced copy")
	Loadouts.remove(copy)
	assert_eq(Loadouts.all().size(), 4)
	Loadouts.equip(1)
	Loadouts.remove(0)
	assert_eq(Loadouts.active()["name"], "Assault", "still on the same preset after one before it went")
	while Loadouts.all().size() > 1:
		Loadouts.remove(0)
	Loadouts.remove(0)
	assert_eq(Loadouts.all().size(), 1, "one always remains")


func test_there_is_a_limit_to_presets() -> void:
	while Loadouts.all().size() < Loadouts.MAX_PRESETS:
		assert_true(Loadouts.add() >= 0)
	assert_eq(Loadouts.add(), -1)
	assert_eq(Loadouts.duplicate_preset(0), -1)


func test_assigning_moves_a_jutsu_between_slots() -> void:
	Loadouts.equip(0)
	var before := (Loadouts.active()["slots"] as Array).duplicate()
	var other := (Loadouts.all()[1]["slots"] as Array).duplicate()
	var was := Loadouts.slot_of(&"chakra_bolt")
	assert_true(was >= 0 and was != 7, "the bolt starts in another slot")
	Loadouts.assign(7, &"chakra_bolt")
	var after: Array = Loadouts.active()["slots"]
	assert_eq(after[7], "chakra_bolt")
	assert_eq(after[was], "", "it left its old slot: a jutsu sits in one slot only")
	assert_eq(Loadouts.slot_of(&"chakra_bolt"), 7)
	assert_eq(Loadouts.all()[1]["slots"], other, "other presets are untouched")
	Loadouts.assign(7, &"")
	assert_eq((Loadouts.active()["slots"] as Array)[7], "", "and slots can be cleared")
	assert_true(before != Loadouts.active()["slots"])


func test_presets_are_saved_with_the_character() -> void:
	var file := "user://test_loadouts_roundtrip.cfg"
	Profile.persist = true
	Profile.save_path = file
	Loadouts.add("Saved one")
	Loadouts.assign(2, &"tide_lance")
	Loadouts.set_style(2, Loadouts.INSTANT)
	Profile._values.clear()   # forget everything, then read the file back
	Profile.load_from_disk()
	Profile.persist = false
	Profile.save_path = ""
	DirAccess.remove_absolute(file)
	assert_eq(Loadouts.active()["name"], "Saved one", "the loadouts came back")
	assert_eq(Loadouts.index(), 3, "and which one was equipped")
	assert_eq(Loadouts.jutsu_in(Loadouts.active(), 2), &"tide_lance")
	assert_eq(Loadouts.style_in(Loadouts.active(), 2), Loadouts.INSTANT, "with their cast styles")


func test_the_player_has_eight_slots_from_the_equipped_preset() -> void:
	await _load()
	assert_eq(player.quick_slots.size(), 8)
	assert_eq(player.quick_slots[0], StringName(Loadouts.starters()[0]["slots"][0]))
	Loadouts.equip(1)
	assert_eq(player.quick_slots[1], StringName(Loadouts.starters()[1]["slots"][1]), "the player follows the equipped preset")
	assert_eq(player.quick_slots[Loadouts.CLONES_SLOT], &"shade_clones")
	player.assign_quick_slot(4, &"tide_lance")
	assert_eq(player.quick_slots[4], &"tide_lance", "assigning edits the loadout")
	assert_eq(Loadouts.active()["slots"][4], "tide_lance")
	player.assign_quick_slot(Loadouts.CLONES_SLOT, &"tide_lance")
	assert_eq(player.quick_slots[Loadouts.CLONES_SLOT], &"shade_clones", "not over Shade Clones")


func test_keys_five_to_eight_cast_the_upper_slots() -> void:
	await _load()
	Loadouts.equip(1)
	player.assign_quick_slot(7, &"focus_seal")
	player.stats.chakra = 100.0
	await _tap(&"quick_cast_8")
	await seconds(1.2)
	assert_true(player.caster.cooldown_left(&"focus_seal") > 0.0, "slot 8 cast Focus Seal")


func test_on_a_gamepad_the_dpad_works_the_current_page() -> void:
	await _load()
	Loadouts.equip(1)
	player.assign_quick_slot(7, &"focus_seal")
	InputDevice.current = Binding.Device.GAMEPAD
	player.stats.chakra = 100.0
	await _tap(&"quick_page")
	assert_eq(player.quick_page, 1, "Back flips to the second page")
	await _tap(&"quick_cast_4")  # D-pad left: slot 8 on page two
	await seconds(1.2)
	assert_true(player.caster.cooldown_left(&"focus_seal") > 0.0, "the fourth D-pad direction cast slot 8")
	await _tap(&"quick_page")
	assert_eq(player.quick_page, 0)


func test_holding_lb_turns_the_dpad_to_slots_five_to_eight() -> void:
	await _load()
	Loadouts.equip(1)
	player.assign_quick_slot(7, &"focus_seal")
	InputDevice.current = Binding.Device.GAMEPAD
	player.stats.chakra = 100.0
	assert_eq(player.dpad_page(), 0)
	Input.action_press(&"quick_shift")
	await physics_frames(2)
	assert_eq(player.dpad_page(), 1, "held: the other page")
	await _tap(&"quick_cast_4")  # D-pad left with LB held: slot 8
	Input.action_release(&"quick_shift")
	await seconds(1.2)
	assert_true(player.caster.cooldown_left(&"focus_seal") > 0.0, "LB + D-pad left cast slot 8")
	assert_eq(player.quick_page, 0, "holding doesn't flip the page for good")
	assert_eq(player.dpad_page(), 0, "let go: back to slots 1-4")


func test_the_preset_keys_cycle_loadouts() -> void:
	await _load()
	await _tap(&"preset_next")
	assert_eq(Loadouts.active()["name"], "Assault")
	await _tap(&"preset_prev")
	await _tap(&"preset_prev")
	assert_eq(Loadouts.active()["name"], "Guardian", "wraps around")
	assert_eq(player.quick_slots[0], StringName(Loadouts.starters()[2]["slots"][0]))


func test_instant_slots_skip_the_seals_for_extra_chakra() -> void:
	await _load()
	Loadouts.equip(0)
	var bolt := JutsuRegistry.get_jutsu(&"chakra_bolt")
	assert_near(player.caster.cost_of(bolt, true), player.caster.cost_of(bolt) * 1.35, 0.001)
	var slot := Loadouts.slot_of(&"chakra_bolt")
	Loadouts.set_style(slot, Loadouts.INSTANT)
	player.stats.chakra = 100.0
	player.caster._cooldowns.clear()
	player.start_quick_cast(slot)
	assert_eq(player.state, Player.State.FREE, "no weaving state")
	assert_near(player.stats.chakra, 100.0 - player.caster.cost_of(bolt, true), 0.01, "paid the surcharge")
	assert_true(player.caster.cooldown_left(&"chakra_bolt") > 0.0, "and it cast at once")
	player.stats.chakra = 7.0
	player.caster._cooldowns.clear()
	assert_eq(player.caster.block_reason(bolt, true), &"chakra", "short of chakra for an instant cast")
	assert_eq(player.caster.block_reason(bolt, false), &"", "though a woven one would still work")


func test_woven_slots_still_weave() -> void:
	await _load()
	Loadouts.equip(0)
	player.stats.chakra = 100.0
	player.start_quick_cast(1)
	assert_eq(player.state, Player.State.AUTO_WEAVING)


func test_changing_nature_refills_the_players_bar() -> void:
	await _load()
	Profile.set_value(&"affinity", Element.LIGHTNING)
	await physics_frames(1)
	assert_eq(JutsuRegistry.get_jutsu(player.quick_slots[0]).element, Element.LIGHTNING, "the bar follows the new nature")
	assert_eq(player.quick_slots[Loadouts.CLONES_SLOT], &"shade_clones")
