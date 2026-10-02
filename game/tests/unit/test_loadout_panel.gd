extends TestCase
## The loadout editor: pick a slot, equip jutsu into it, cast styles, presets.

var panel: LoadoutPanel


func before_each() -> void:
	Profile.persist = false
	Profile.reset()
	panel = LoadoutPanel.new(false)
	root.add_child(panel)


func after_each() -> void:
	panel.queue_free()
	Profile.reset()


func _jutsu(id: StringName) -> JutsuDefinition:
	return JutsuRegistry.get_jutsu(id)


func test_it_lists_eight_slots_and_every_jutsu() -> void:
	var names := panel.find_children("*", "Button", true, false).filter(
		func(b: Button) -> bool: return b.has_meta(&"focus_key") and str(b.get_meta(&"focus_key")).begins_with("slot"))
	assert_eq(names.size(), Loadouts.SLOTS, "eight quick-cast slots")
	var equips := panel.find_children("*", "Button", true, false).filter(
		func(b: Button) -> bool: return b.has_meta(&"focus_key") and str(b.get_meta(&"focus_key")).begins_with("equip_"))
	assert_eq(equips.size(), JutsuRegistry.all().size(), "a row for every jutsu")


func test_equipping_fills_the_picked_slot_and_moves_to_the_next_empty_one() -> void:
	panel._pick_slot(6)
	panel._equip_to_slot(_jutsu(&"gale_palm"))
	assert_eq(Loadouts.active()["slots"][6], "gale_palm")
	assert_eq(panel._slot, 7, "the next empty slot is picked")
	panel._equip_to_slot(_jutsu(&"cinder_bloom"))
	assert_eq(Loadouts.active()["slots"][7], "cinder_bloom")
	assert_eq(panel._slot, 7, "with none left it stays put")


func test_a_jutsu_moves_rather_than_doubling() -> void:
	panel._pick_slot(7)
	panel._equip_to_slot(_jutsu(&"chakra_bolt"))
	var slots: Array = Loadouts.active()["slots"]
	assert_eq(slots[7], "chakra_bolt")
	assert_eq(slots.count("chakra_bolt"), 1, "only one slot holds it")
	assert_eq(slots[0], "", "the old slot is emptied")


func test_style_toggle_and_clear() -> void:
	panel._toggle_style(0, false)
	assert_eq(Loadouts.style_in(Loadouts.active(), 0), Loadouts.INSTANT)
	panel._toggle_style(0, true)
	assert_eq(Loadouts.style_in(Loadouts.active(), 0), Loadouts.WEAVE)
	panel._clear_slot(0)
	assert_eq(Loadouts.active()["slots"][0], "")


func test_presets_copy_switch_and_delete_with_confirmation() -> void:
	var count := Loadouts.all().size()
	panel._copy(Loadouts.index())
	assert_eq(Loadouts.all().size(), count + 1, "copied")
	assert_eq(Loadouts.index(), count, "and the copy is the one you carry")
	panel._new_empty()
	assert_eq(Loadouts.all().size(), count + 2)
	assert_eq((Loadouts.active()["slots"] as Array).filter(func(s: String) -> bool: return s != "").size(), 0, "empty")
	panel._delete(Loadouts.index())
	assert_eq(Loadouts.all().size(), count + 2, "the first press only asks")
	panel._delete(Loadouts.index())
	assert_eq(Loadouts.all().size(), count + 1, "the second deletes")
	panel._equip(0)
	assert_eq(Loadouts.index(), 0)


func test_the_last_preset_cannot_be_deleted() -> void:
	while Loadouts.all().size() > 1:
		Loadouts.remove(0)
	var del: Button = panel.find_children("*", "Button", true, false).filter(
		func(b: Button) -> bool: return b.has_meta(&"focus_key") and b.get_meta(&"focus_key") == "delete")[0]
	assert_true(del.disabled)


func test_restore_starters_brings_back_the_defaults() -> void:
	Loadouts.rename(0, "Mine")
	Loadouts.add("Extra")
	panel._restore_starters()
	assert_eq(Loadouts.all().size(), Loadouts.starters().size())
	assert_eq(Loadouts.active()["name"], Loadouts.starters()[0]["name"])


func test_renaming_does_not_rebuild_the_panel_under_the_cursor() -> void:
	var edit: LineEdit = panel.find_children("*", "LineEdit", true, false)[0]
	edit.text = "Fire storm"
	edit.text_changed.emit("Fire storm")
	assert_eq(Loadouts.active()["name"], "Fire storm", "saved as you type")
	assert_true(is_instance_valid(edit) and edit.is_inside_tree(), "the same field is still there to type in")


func test_the_panel_follows_changes_made_elsewhere() -> void:
	# Cycling presets with the keys changes the equipped one; the open panel shows it.
	Loadouts.add("Second")
	await physics_frames(1)
	var edit: LineEdit = panel.find_children("*", "LineEdit", true, false)[0]
	assert_eq(edit.text, "Second")
