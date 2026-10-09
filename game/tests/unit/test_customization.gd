extends TestCase
## Character customization: material slots, tints, measured gear fitting,
## body/identity options, persistence, and the customize screen.

const Scene := preload("res://scenes/training_ground.tscn")

var model: CharacterModel


# The roster and appearance editing underneath the main character.
func before_each() -> void:
	CharacterModel.use_main = false


func after_each() -> void:
	CharacterModel.use_main = true
	Profile.persist = false
	Profile.save_path = ""


func _model(path := CharacterModel.DEFAULT_MODEL) -> CharacterModel:
	model = CharacterModel.new()
	model.model_path = path
	root.add_child(model)
	return model


func _gear_bones() -> Array:
	return model.gear.attachments().map(func(n: BoneAttachment3D) -> StringName: return StringName(n.bone_name))


func test_material_names_map_to_colour_slots() -> void:
	var cases := {
		# VRoid Studio export naming
		"N00_000_Hair_00_HAIR (Instance)": "hair",
		"N00_000_00_FaceBrow_00_FACE (Instance)": "hair",
		"N00_000_00_EyeIris_00_EYE (Instance)": "eyes",
		"N00_000_00_EyeWhite_00_EYE (Instance)": "",
		"N00_000_00_FaceMouth_00_FACE (Instance)": "",
		"N00_000_00_Face_00_SKIN (Instance)": "skin",
		"N00_000_00_Body_00_SKIN (Instance)": "skin",
		"N00_002_01_Tops_01_CLOTH (Instance)": "outfit",
		"N00_001_01_Bottoms_01_CLOTH (Instance)": "lower",
		"N00_007_02_Shoes_01_CLOTH (Instance)": "shoes",
		"N00_010_01_Onepiece_00_CLOTH (Instance)": "outfit",
		# Other common VRM naming
		"Alicia_hair": "hair", "Alicia_hair_wear": "accessory", "Alicia_eye": "eyes",
		"Alicia_eye_white": "", "Alicia_face_mastuge": "", "Alicia_body": "skin",
		"Alicia_body_wear": "outfit", "Alicia_other_zwrite": "accessory",
	}
	for n: String in cases:
		assert_eq(CharacterStyler.classify(n), cases[n], n)


func test_unrecognised_models_get_one_body_slot() -> void:
	_model(CharacterModel.PLACEHOLDER_MODEL)
	assert_eq(model.styler.available_slots(), PackedStringArray(["body"]), "Godette's Face/Body materials")


func test_tint_recolours_this_character_only() -> void:
	_model(CharacterModel.PLACEHOLDER_MODEL)
	var entry: Dictionary = model.styler.slots["body"][0]
	var original: Color = entry["lit"]
	Profile.set_tint("body", Color(0.5, 0.25, 1.0))
	var mat: ShaderMaterial = entry["material"]
	var now: Color = mat.get_shader_parameter(&"_Color")
	assert_near(now.r, original.r * 0.5, 0.01)
	assert_near(now.g, original.g * 0.25, 0.01)
	# The imported resource shared by other instances is untouched.
	var fresh := CharacterModel.new()
	fresh.model_path = CharacterModel.PLACEHOLDER_MODEL
	fresh.use_profile = false
	root.add_child(fresh)
	var fresh_color: Color = (fresh.styler.slots["body"][0]["material"] as ShaderMaterial).get_shader_parameter(&"_Color")
	assert_true(fresh_color.is_equal_approx(original), "shared material unchanged")
	Profile.set_tint("body", Color.WHITE)
	assert_true((mat.get_shader_parameter(&"_Color") as Color).is_equal_approx(original), "white restores")


func test_default_gear_is_fitted_to_measured_body() -> void:
	_model()
	var bones := _gear_bones()
	for bone in [&"Head", &"Neck", &"RightUpperLeg"]:
		assert_true(bones.has(bone), "gear on %s" % bone)
	assert_true(bones.has(&"Hips"), "the ninjato worn at the hip")
	assert_true(bones.has(&"RightHand"), "and fitted to the right hand, to be drawn")
	var head := model.gear.region(&"Head")
	assert_true(head.size.x > 0.05 and head.size.y > 0.05, "head measured from skinned mesh")
	var band_att: BoneAttachment3D = model.gear.attachments().filter(
		func(n: BoneAttachment3D) -> bool: return n.bone_name == "Head")[0]
	var band := band_att.find_child("Band", true, false) as MeshInstance3D
	assert_true(band.get_aabb().size.x >= head.size.x * 0.8, "headband wraps round the head")


func test_headband_hugs_the_head_and_hair() -> void:
	_model()
	var shape := model.gear.headband
	assert_true(shape != null, "headband fitted")
	var head := model.gear.region(&"Head")
	var face := model.gear.face_or(head)
	var around := head.grow(0.03)
	for i in 16:
		var ang := TAU * i / 16.0
		var p := shape.point(ang)
		assert_true(around.has_point(p), "band stays on the head at %d deg (%s)" % [i * 22.5, p])
		assert_true(shape.radius_at(ang) > face.size.x * 0.35, "band clears the skull at %d deg" % [i * 22.5])
	# Across the forehead, above the eyes and below the top of the head.
	assert_true(shape.point(0.0).y > face.position.y + face.size.y * 0.6)
	assert_true(shape.point(0.0).y < head.end.y)
	assert_true(shape.point(PI).y < shape.point(0.0).y, "lower at the back")


func test_hachigane_has_an_engraved_plate_and_cloth_does_not() -> void:
	_model()
	Profile.set_value(&"headband", "hachigane")
	await root.get_tree().process_frame
	var plate := model.find_child("Plate", true, false) as MeshInstance3D
	assert_true(plate != null, "steel plate")
	assert_eq((plate.material_override as ShaderMaterial).shader, CharacterGear.PLATE_SHADER)
	assert_true(plate.get_aabb().size.y > 0.02 and plate.get_aabb().size.x > 0.05, "plate has real size")
	Profile.set_value(&"headband", "cloth")
	await root.get_tree().process_frame
	assert_true(model.find_child("Plate", true, false) == null, "cloth band has no plate")
	assert_eq(model.find_children("Tail*", "GearRibbon", true, false).size(), 2, "two knot tails")


func test_headband_tails_hang_and_swing() -> void:
	_model()
	await physics_frames(30)
	var tails := model.find_children("Tail*", "GearRibbon", true, false)
	assert_eq(tails.size(), 2)
	var tail: GearRibbon = tails[0]
	var pts := tail.points().duplicate()
	assert_true(pts[pts.size() - 1].y < pts[0].y - 0.05, "hangs down from the knot")
	var seg := pts[0].distance_to(pts[1])
	for i in range(1, pts.size()):
		assert_near(pts[i - 1].distance_to(pts[i]), seg, 0.002, "cloth doesn't stretch")
	# Whip the head round: the tip lags behind the knot, then settles.
	var tip_before := pts[pts.size() - 1]
	model.rotation.y += 1.2
	# process_frame fires before nodes process: wait for the tail's own step.
	await root.get_tree().process_frame
	await root.get_tree().process_frame
	var knot_moved := tail.points()[0].distance_to(pts[0])
	var tip_moved := tail.points()[pts.size() - 1].distance_to(tip_before)
	assert_true(knot_moved > 0.01, "the knot turns with the head")
	assert_true(tip_moved < knot_moved, "the tip trails behind")


func test_gear_options_rebuild_live() -> void:
	_model()
	Profile.set_value(&"headband", "none")
	Profile.set_value(&"scarf", false)
	Profile.set_value(&"back", "none")
	Profile.set_value(&"pouch", false)
	await root.get_tree().process_frame
	assert_eq(_gear_bones().size(), 0, "everything removed")
	Profile.set_value(&"mask", true)
	await root.get_tree().process_frame
	assert_eq(_gear_bones(), [&"Head"], "mask only")


func test_height_and_expression() -> void:
	_model()
	var base := model.instance.scale
	Profile.set_value(&"height", 1.1)
	assert_true(model.instance.scale.is_equal_approx(base * 1.1))
	Profile.set_value(&"expression", "happy")
	assert_eq(model.expressions.current_animation, &"happy")


func test_affinity_discounts_matching_jutsu() -> void:
	var caster := JutsuCaster.new()
	root.add_child(caster)
	var ember := JutsuRegistry.get_jutsu(&"ember_volley")
	var tide := JutsuRegistry.get_jutsu(&"tide_lance")
	var bolt := JutsuRegistry.get_jutsu(&"chakra_bolt")
	caster.affinity = Element.FIRE
	assert_near(caster.cost_of(ember), ember.chakra_cost * (1.0 - JutsuCaster.AFFINITY_DISCOUNT))
	assert_near(caster.cost_of(tide), tide.chakra_cost)
	assert_near(caster.cost_of(bolt), bolt.chakra_cost, 0.001, "neutral jutsu never discounted")


func test_profile_round_trips_and_rejects_bad_types() -> void:
	Profile.persist = true
	Profile.save_path = "user://test_profile_roundtrip.cfg"
	Profile.set_value(&"name", "Hayate")
	Profile.set_tint("hair", Color("9e2430"))
	Profile.set_value(&"height", "tall")  # wrong type: rejected
	Profile.load_from_disk()
	assert_eq(Profile.get_value(&"name"), "Hayate")
	assert_true(Profile.tint("hair").is_equal_approx(Color("9e2430")))
	assert_near(Profile.get_value(&"height"), 1.0)
	DirAccess.remove_absolute(Profile.save_path)


func test_roster_and_missing_model_fallback() -> void:
	var paths := CharacterModel.roster().map(func(e: Dictionary) -> String: return e["path"])
	assert_true(paths.has(CharacterModel.DEFAULT_MODEL))
	Profile.set_value(&"model", "res://assets/characters/does_not_exist.vrm")
	var m := CharacterModel.new()
	root.add_child(m)
	assert_true(m.loaded_path in [CharacterModel.DEFAULT_MODEL, CharacterModel.USER_MODEL], "fell back safely")


func test_customize_screen_freezes_play_and_applies_swatches() -> void:
	var scene := Scene.instantiate()
	root.add_child(scene)
	await physics_frames(3)
	var menu: CustomizeMenu = scene.customize_menu
	var player: Player = scene.player
	menu.open()
	assert_false(player.input_enabled, "player frozen")
	assert_true(player.camera_rig.in_showcase(), "camera shows the character")
	assert_false(scene.hud.visible, "HUD hidden")
	menu._select_tab(1)
	var swatches := menu._tabs.get_current_tab_control().find_children("*", "ColorSwatch", true, false)
	assert_true(swatches.size() > 0, "colour swatches present")
	var pick: ColorSwatch = swatches[3]
	pick.pressed.emit()
	var slot: String = player.model.styler.available_slots()[0]
	assert_true(Profile.tint(slot).is_equal_approx(pick.swatch), "swatch applied to %s" % slot)
	menu.close()
	assert_true(player.input_enabled)
	assert_false(player.camera_rig.in_showcase())
	assert_true(scene.hud.visible)


func test_pause_menu_opens_customize() -> void:
	var scene := Scene.instantiate()
	root.add_child(scene)
	await root.get_tree().process_frame
	scene.pause_menu.open()
	assert_true(root.get_tree().paused)
	# The Customize button closes the pause menu, then asks for the screen.
	var customize_button: Button = scene.pause_menu._resume.get_parent().get_child(1)
	assert_eq(customize_button.text, "Customize")
	customize_button.pressed.emit()
	assert_false(root.get_tree().paused, "game unpaused so the character can be seen")
	assert_true(scene.customize_menu.is_open())
	scene.customize_menu.close()


func test_random_name_is_ninja_flavoured() -> void:
	var n := Profile.random_name()
	assert_true(n.contains(" of the "), n)
