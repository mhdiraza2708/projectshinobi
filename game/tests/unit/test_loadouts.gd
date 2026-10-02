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
	assert_true(list.any(func(p: Dictionary) -> bool: return (p["slots"] as Array).has("shade_clones")), "Shade Clones is on a bar")


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
	Loadouts.assign(7, &"chakra_bolt")
	var after: Array = Loadouts.active()["slots"]
	assert_eq(after[7], "chakra_bolt")
	assert_eq(after[0], "", "it left its old slot: a jutsu sits in one slot only")
	assert_eq(Loadouts.slot_of(&"chakra_bolt"), 7)
	assert_eq((Loadouts.all()[1]["slots"] as Array)[0], "chakra_bolt", "other presets are untouched")
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
	assert_eq(player.quick_slots[0], &"chakra_bolt")
	Loadouts.equip(1)
	assert_eq(player.quick_slots[1], &"ember_volley", "the player follows the equipped preset")
	assert_eq(player.quick_slots[7], &"shade_clones")
	player.assign_quick_slot(3, &"tide_lance")
	assert_eq(player.quick_slots[3], &"tide_lance", "assigning edits the loadout")
	assert_eq(Loadouts.active()["slots"][3], "tide_lance")


func test_keys_five_to_eight_cast_the_upper_slots() -> void:
	await _load()
	Loadouts.equip(1)
	player.stats.chakra = 100.0
	await _tap(&"quick_cast_8")
	await seconds(1.2)
	assert_true(player.caster.cooldown_left(&"shade_clones") > 0.0, "slot 8 cast Shade Clones")


func test_on_a_gamepad_the_dpad_works_the_current_page() -> void:
	await _load()
	Loadouts.equip(1)
	InputDevice.current = Binding.Device.GAMEPAD
	player.stats.chakra = 100.0
	await _tap(&"quick_page")
	assert_eq(player.quick_page, 1, "Back flips to the second page")
	await _tap(&"quick_cast_4")  # D-pad left: slot 8 on page two
	await seconds(1.2)
	assert_true(player.caster.cooldown_left(&"shade_clones") > 0.0, "the fourth D-pad direction cast slot 8")
	await _tap(&"quick_page")
	assert_eq(player.quick_page, 0)


func test_the_preset_keys_cycle_loadouts() -> void:
	await _load()
	await _tap(&"preset_next")
	assert_eq(Loadouts.active()["name"], "Assault")
	await _tap(&"preset_prev")
	await _tap(&"preset_prev")
	assert_eq(Loadouts.active()["name"], "Guardian", "wraps around")
	assert_eq(player.quick_slots[0], &"stone_bulwark")


func test_instant_slots_skip_the_seals_for_extra_chakra() -> void:
	await _load()
	Loadouts.equip(0)
	var bolt := JutsuRegistry.get_jutsu(&"chakra_bolt")
	assert_near(player.caster.cost_of(bolt, true), player.caster.cost_of(bolt) * 1.35, 0.001)
	Loadouts.set_style(0, Loadouts.INSTANT)
	player.stats.chakra = 100.0
	player.caster._cooldowns.clear()
	player.start_quick_cast(0)
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
