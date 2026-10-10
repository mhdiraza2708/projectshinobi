extends TestCase
## The game's main character: everyone plays as them (a Tripo model on the
## humanoid rig), wearing their own clothes, the katana at the hip and the
## headband the player picks; the customize screen keeps who they are
## (name, clan, dojutsu, jutsu) and the headband.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D
var player: Player


func before_each() -> void:
	Profile.persist = false
	Profile.reset()


func after_each() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
	Profile.reset()


func _load() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	await physics_frames(5)


func test_everyone_plays_the_main_character_with_a_katana_at_the_hip() -> void:
	assert_true(CharacterModel.has_main(), "the main character ships with the game")
	Profile.set_value(&"model", CharacterModel.DEFAULT_MODEL)
	await _load()
	var m := player.model
	assert_eq(m.loaded_path, CharacterModel.MAIN_MODEL, "whatever model the profile names")
	assert_true(m.is_main())
	assert_true(m.poser.active and m.animator.clips != null, "the game's poses and clips drive them")
	assert_near(m.measure_height(), m.target_height, 0.05, "at shinobi height")
	assert_true(m.gear.has_sword(), "the katana every strike draws")
	var on := m.gear.attachments().map(func(n: BoneAttachment3D) -> StringName: return StringName(n.bone_name))
	for bone: StringName in on:
		assert_true(bone in [&"Hips", &"RightHand", &"Head"], "only the sword and a headband: %s" % bone)


func test_the_player_picks_the_main_characters_headband() -> void:
	Profile.set_value(&"headband", "none")
	await _load()
	var m := player.model
	assert_true(m.gear.headband == null, "none")
	Profile.set_value(&"headband", "hachigane")
	await physics_frames(2)
	assert_true(m.gear.headband != null, "a hachigane, fitted to their head and hair")
	assert_true(m.gear.has_sword(), "the katana stays")
	Profile.set_value(&"mask", true)
	Profile.set_value(&"scarf", true)
	await physics_frames(2)
	var on := m.gear.attachments().map(func(n: BoneAttachment3D) -> StringName: return StringName(n.bone_name))
	assert_eq(on.count(&"Head"), 1, "the headband alone on the head: no mask over their design")
	assert_false(on.has(&"Neck"), "and no scarf")


func test_customize_keeps_who_they_are_and_their_headband() -> void:
	await _load()
	var menu: CustomizeMenu = scene.customize_menu
	menu.open()
	await physics_frames(2)
	for tab in [CustomizeMenu.T_LOOK, CustomizeMenu.T_COLOURS]:
		assert_false(menu._tab_buttons[tab].visible, "no %s tab" % CustomizeMenu.TABS[tab][1])
	for tab in [CustomizeMenu.T_GEAR, CustomizeMenu.T_IDENTITY, CustomizeMenu.T_CLAN, CustomizeMenu.T_EYES, CustomizeMenu.T_JUTSU]:
		assert_true(menu._tab_buttons[tab].visible, "%s stays" % CustomizeMenu.TABS[tab][1])
	assert_eq(menu._tabs.current_tab, CustomizeMenu.T_GEAR, "it opens on their headband")
	menu.close()


func test_shade_clones_are_the_main_character_too() -> void:
	await _load()
	player.caster._cooldowns.clear()
	player.stats.chakra = player.stats.max_chakra
	assert_true(player.caster.cast(JutsuRegistry.get_jutsu(&"shade_clones")))
	await physics_frames(3)
	var clones := player.caster.clones()
	assert_false(clones.is_empty())
	for c in clones:
		assert_eq(c.model.loaded_path, CharacterModel.MAIN_MODEL)


func test_the_drawn_sword_takes_the_cap_on_its_grip() -> void:
	await _load()
	var gear := player.model.gear
	assert_true(gear.has_sword())
	var scabbard := (gear.scabbard as MeshInstance3D).mesh.get_aabb()
	var sword := (gear.sword as MeshInstance3D).mesh.get_aabb()
	assert_true(scabbard.end.y <= CharacterGear.GUARD_Y + 0.01,
		"nothing of the scabbard above the guard to be left at the hip (%.3f)" % scabbard.end.y)
	assert_true(sword.end.y > CharacterGear.GRIP_Y + 0.1, "the grip ends in its cap (%.3f)" % sword.end.y)


## The radius of the headband's knot (it grows with the band's size).
func _knot_radius(m: CharacterModel) -> float:
	for att in m.gear.attachments():
		for mi in att.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).mesh is SphereMesh:
				return ((mi as MeshInstance3D).mesh as SphereMesh).radius
	return 0.0


func test_the_player_sets_their_height_and_headband_size() -> void:
	Profile.set_value(&"headband", "cloth")
	await _load()
	var m := player.model
	var tall := m.measure_height()
	var knot := _knot_radius(m)
	assert_true(knot > 0.0, "a band to size")
	Profile.set_value(&"height", 1.08)
	Profile.set_value(&"headband_size", 1.4)
	await physics_frames(2)
	assert_near(m.measure_height() / tall, 1.08, 0.02, "taller by the slider")
	# The whole band grows by the size (the ring still hugs the head).
	assert_near(_knot_radius(m) / knot, 1.4, 0.05, "a bigger band")
