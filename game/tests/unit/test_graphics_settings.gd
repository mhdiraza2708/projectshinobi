extends TestCase
## The Graphics tab: presets set the quality options (and anything changed
## by hand makes it Custom), and each option reaches the renderer: 3D
## resolution, anti-aliasing, frame cap, shadows, bloom, brightness and the
## camera's field of view.

const Scene := preload("res://scenes/training_ground.tscn")

var scene: Node3D


func after_each() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
	Settings.reset_values()


func test_presets_set_the_quality_options() -> void:
	Graphics.apply_preset("low")
	assert_eq(Settings.get_value(&"graphics_preset"), "low")
	assert_eq(Settings.get_value(&"anti_aliasing"), "off")
	assert_near(float(Settings.get_value(&"render_scale")), 0.75, 0.001)
	assert_false(Settings.get_value(&"bloom"))
	assert_eq(Graphics.matching_preset(), "low")
	Graphics.apply_preset("ultra")
	assert_eq(Settings.get_value(&"graphics_quality"), "cinematic")
	assert_eq(Graphics.matching_preset(), "ultra")
	Settings.set_value(&"bloom", false)
	assert_eq(Graphics.matching_preset(), "custom", "a hand-changed option is a custom setup")


func test_presets_leave_personal_options_alone() -> void:
	Settings.set_value(&"fov", 90.0)
	Settings.set_value(&"max_fps", 60)
	Graphics.apply_preset("high")
	assert_near(float(Settings.get_value(&"fov")), 90.0, 0.001)
	assert_eq(Settings.get_value(&"max_fps"), 60)


func test_display_options_reach_the_viewport() -> void:
	var root := Engine.get_main_loop().root as Window
	Settings.set_value(&"render_scale", 0.6)
	assert_near(root.scaling_3d_scale, 0.6, 0.001, "3D resolution")
	Settings.set_value(&"anti_aliasing", "msaa4")
	assert_eq(root.msaa_3d, Viewport.MSAA_4X)
	assert_eq(root.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED)
	Settings.set_value(&"anti_aliasing", "fxaa")
	assert_eq(root.screen_space_aa, Viewport.SCREEN_SPACE_AA_FXAA)
	assert_eq(root.msaa_3d, Viewport.MSAA_DISABLED)
	Settings.set_value(&"max_fps", 144)
	assert_eq(Engine.max_fps, 144)
	Settings.set_value(&"max_fps", 0)
	assert_eq(Engine.max_fps, 0)


func test_scene_options_relight_the_world() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	await physics_frames(3)
	var env: Environment = scene.get_node("WorldEnvironment").environment
	var exposure := env.tonemap_exposure
	Settings.set_value(&"brightness", 1.3)
	assert_near(env.tonemap_exposure, exposure * 1.3, 0.001, "brightness")
	Settings.set_value(&"bloom", false)
	assert_false(env.glow_enabled, "bloom off")
	Settings.set_value(&"ambient_occlusion", false)
	assert_false(env.ssao_enabled, "ambient occlusion off")
	Settings.set_value(&"fov", 85.0)
	assert_near(scene.player.camera_rig.camera.fov, 85.0, 0.001, "field of view")


func test_the_pause_menu_has_a_graphics_tab() -> void:
	Game.start_mode = Game.Mode.TRAINING
	scene = Scene.instantiate()
	root.add_child(scene)
	await physics_frames(3)
	var menu: PauseMenu = scene.pause_menu
	menu.open()
	menu._select_tab(PauseMenu.TAB_GRAPHICS)
	await physics_frames(2)
	var tab: Control = menu._tabs.get_current_tab_control()
	var preset := tab.find_child("Preset", true, false) as OptionButton
	assert_true(preset != null, "a preset picker")
	preset.item_selected.emit(Graphics.PRESET_ORDER.find("high"))
	await physics_frames(2)
	assert_eq(Settings.get_value(&"graphics_quality"), "high", "choosing High sets the options")
	var labels := menu._tabs.get_current_tab_control().find_children("*", "Label", true, false).map(
		func(l: Label) -> String: return l.text)
	for title in ["Window", "VSync", "Frame rate cap", "Anti-aliasing", "Shadows", "Field of view", "Brightness"]:
		assert_true(labels.has(title), "%s is offered" % title)
	menu.close()
