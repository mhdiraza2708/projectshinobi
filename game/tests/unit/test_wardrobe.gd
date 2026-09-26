extends TestCase
## The VRoid wardrobe: bundled CC0 characters, hair and outfit swaps with
## their bones and spring physics, and the customize pickers.

const R := CharacterModel.ROSTER_DIR
const SHINO := R + "/sendagaya_shino.vrm"
const KAI := R + "/hairsample_male.vrm"
const VITA := R + "/vita.vrm"

var model: CharacterModel


func _model(path: String, style := {}) -> CharacterModel:
	model = CharacterModel.new()
	model.use_profile = false
	model.model_path = path
	model.style = style
	root.add_child(model)
	return model


func _visible_materials(m: CharacterModel) -> PackedStringArray:
	var out := PackedStringArray()
	for n in m.instance.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.visible or mi.has_meta(&"gear"):
			continue
		for s in mi.mesh.get_surface_count():
			out.append(mi.get_active_material(s).resource_name)
	return out


func _count(mats: PackedStringArray, word: String) -> int:
	return Array(mats).filter(func(m: String) -> bool: return m.contains(word)).size()


func test_bundled_characters_are_cc0_vroid_models() -> void:
	var roster := CharacterModel.roster()
	assert_true(roster.size() >= 10, "nine VRoid samples plus Godette")
	assert_eq(CharacterModel.resolve_path_default(), CharacterModel.DEFAULT_MODEL, "a VRoid sample is the default")
	for entry: Dictionary in roster:
		var path: String = entry["path"]
		if not path.begins_with(R):
			continue
		# The licence travels inside the file: check it rather than trust a list.
		var f := FileAccess.open(path, FileAccess.READ)
		f.seek(12)
		var length := f.get_32()
		f.get_32()
		var meta: Dictionary = JSON.parse_string(f.get_buffer(length).get_string_from_utf8())["extensions"]["VRM"]["meta"]
		assert_eq(meta["licenseName"], "CC0", "%s licence" % path.get_file())


func test_own_parts_by_default_and_swappable() -> void:
	_model(SHINO)
	assert_true(model.swappable)
	var mats := _visible_materials(model)
	assert_true(_count(mats, "HAIR") > 0 and _count(mats, "Tops") == 1)
	var pl := _model(CharacterModel.PLACEHOLDER_MODEL)
	assert_false(pl.swappable, "single-material models can't swap parts")


func test_hair_swap_replaces_hair_and_carries_its_bones_and_springs() -> void:
	var base := _model(SHINO)
	var own_hair := _count(_visible_materials(base), "HAIR")
	var bones_before := base.skeleton.get_bone_count()
	var springs_before: int = base.instance.get_node("secondary").get("spring_bones").size()
	var swapped := _model(SHINO, {"hair_from": "hairsample_male"})
	var mats := _visible_materials(swapped)
	assert_true(_count(mats, "HAIR") > 0, "has hair")
	assert_true(_count(mats, "HAIR") != own_hair, "different hair")
	assert_eq(_count(mats, "Tops"), 1, "own outfit kept")
	assert_true(swapped.skeleton.get_bone_count() > bones_before, "donor hair joints added")
	var springs: int = swapped.instance.get_node("secondary").get("spring_bones").size()
	assert_true(springs > springs_before, "donor hair springs added (%d > %d)" % [springs, springs_before])
	# Borrowed hair is bound to this skeleton, so it follows the head.
	var hair_mesh: MeshInstance3D = swapped.skeleton.find_children("Hair*_from_*", "MeshInstance3D", false, false)[0]
	assert_true(hair_mesh.get_node(hair_mesh.skeleton) == swapped.skeleton)
	for i in hair_mesh.skin.get_bind_count():
		assert_true(swapped.skeleton.find_bone(hair_mesh.skin.get_bind_name(i)) >= 0, "bind %s resolves" % hair_mesh.skin.get_bind_name(i))


func test_outfit_swap_keeps_face_and_hair() -> void:
	_model(SHINO, {"outfit_from": "hairsample_male"})
	var mats := _visible_materials(model)
	assert_true(_count(mats, "M00_006_01_Tops") == 1, "wearing the hoodie")
	assert_eq(_count(mats, "F00_001_01_Tops"), 0, "own top gone")
	assert_true(_count(mats, "F00_000_Hair") > 0, "own hair kept")
	assert_true(_count(mats, "FaceMouth") == 1, "own face kept")
	assert_true(model.gear.region(&"Head").size != Vector3.ZERO, "gear still measures the body")


func test_swapped_parts_can_be_recoloured() -> void:
	_model(SHINO, {"hair_from": VITA, "outfit_from": KAI, "tints": {"hair": Color(1, 0, 0), "outfit": Color(0, 0, 1)}})
	var slots := model.styler.available_slots()
	assert_true(slots.has("hair") and slots.has("outfit"))
	var e: Dictionary = model.styler.slots["hair"][0]
	var now: Color = (e["material"] as ShaderMaterial).get_shader_parameter(&"_Color")
	assert_near(now.g, 0.0, 0.001, "hair tinted red")


func test_customize_hair_picker_reloads_the_player() -> void:
	var scene: Node3D = preload("res://scenes/training_ground.tscn").instantiate()
	root.add_child(scene)
	await physics_frames(2)
	var menu: CustomizeMenu = scene.customize_menu
	menu.open()
	await physics_frames(1)
	var buttons := menu.find_children("*", "Button", true, false)
	var own_hair := buttons.filter(func(b: Button) -> bool: return b.text == "Own")
	assert_eq(own_hair.size(), 2, "hair and outfit pickers")
	var vita := buttons.filter(func(b: Button) -> bool: return b.text == "Vita")
	assert_true(vita.size() >= 3, "Vita as face, hair and outfit options")
	vita[1].pressed.emit()
	await physics_frames(2)
	assert_eq(Profile.get_value(&"hair_from"), VITA)
	assert_true(scene.player.model.skeleton.find_children("Hair*_from_vita", "MeshInstance3D", false, false).size() > 0,
		"the player wears Vita's hair")
	assert_true(scene.player.animator != null, "animator follows the reload")
	menu.close()
