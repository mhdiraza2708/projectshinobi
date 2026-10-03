class_name Graphics
extends RefCounted
## Rendering quality presets: how close to a film the world is lit.
## "standard" is the original look (fast everywhere). "high" adds real-time
## global illumination (SDFGI: light bounces off the ground and walls),
## screen-space indirect light, volumetric fog with sun shafts, soft
## shadows and a filmic (AgX) tone curve. "cinematic" adds depth of field in
## cutscenes and ultimates, film grain and a vignette.
##
## The Compatibility renderer (old GPUs, the web) has none of these: there
## every preset looks like "standard".

const LEVELS: PackedStringArray = ["standard", "high", "cinematic"]
const LABELS := {"standard": "Standard (fastest)", "high": "High (global illumination, volumetric fog)",
	"cinematic": "Cinematic (adds depth of field and film grain)"}

## The graphics menu's presets: each sets these options (window, frame rate,
## brightness and field of view stay as the player left them).
const PRESETS := {
	"low": {&"graphics_quality": "standard", &"render_scale": 0.75, &"anti_aliasing": "off",
		&"shadow_quality": "low", &"ambient_occlusion": false, &"bloom": false},
	"medium": {&"graphics_quality": "standard", &"render_scale": 1.0, &"anti_aliasing": "fxaa",
		&"shadow_quality": "medium", &"ambient_occlusion": true, &"bloom": true},
	"high": {&"graphics_quality": "high", &"render_scale": 1.0, &"anti_aliasing": "msaa2",
		&"shadow_quality": "high", &"ambient_occlusion": true, &"bloom": true},
	"ultra": {&"graphics_quality": "cinematic", &"render_scale": 1.0, &"anti_aliasing": "taa",
		&"shadow_quality": "high", &"ambient_occlusion": true, &"bloom": true},
}
const PRESET_ORDER: PackedStringArray = ["low", "medium", "high", "ultra", "custom"]
const WINDOW_MODES: PackedStringArray = ["windowed", "borderless", "fullscreen"]
const AA_MODES: PackedStringArray = ["off", "fxaa", "msaa2", "msaa4", "taa"]
const SHADOW_LEVELS: PackedStringArray = ["low", "medium", "high"]
const FPS_CAPS: Array[int] = [30, 60, 120, 144, 240, 0]
## Sun shadow map size and soft-shadow filter per shadow quality.
const SHADOW_SIZES := {"low": 2048, "medium": 4096, "high": 8192}
const SHADOW_FILTERS := {"low": RenderingServer.SHADOW_QUALITY_HARD,
	"medium": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "high": RenderingServer.SHADOW_QUALITY_SOFT_HIGH}


## Applies a preset's options (and remembers it was chosen).
static func apply_preset(preset: String) -> void:
	if not PRESETS.has(preset):
		return
	for key: StringName in PRESETS[preset]:
		Settings.set_value(key, PRESETS[preset][key])
	Settings.set_value(&"graphics_preset", preset)


## The preset the current options match, or "custom".
static func matching_preset() -> String:
	for preset: String in PRESETS:
		var all := true
		for key: StringName in PRESETS[preset]:
			if Settings.get_value(key) != PRESETS[preset][key]:
				all = false
				break
		if all:
			return preset
	return "custom"


## Window, frame rate, 3D resolution, anti-aliasing and shadow maps: what
## belongs to the window rather than a scene.
static func apply_display(root: Window) -> void:
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		match str(Settings.get_value(&"window_mode")):
			"borderless":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			"fullscreen":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			_:
				if DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if Settings.get_value(&"vsync") else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(Settings.get_value(&"max_fps"))
	var scale := clampf(float(Settings.get_value(&"render_scale")), 0.5, 1.0)
	root.scaling_3d_scale = scale
	# FSR sharpens what it upscales; the Compatibility renderer only has bilinear.
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 and supported() else Viewport.SCALING_3D_MODE_BILINEAR
	var aa := str(Settings.get_value(&"anti_aliasing"))
	# The Compatibility renderer has no FXAA or TAA: MSAA stands in for both.
	if not supported() and aa in ["fxaa", "taa"]:
		aa = "msaa2"
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
	root.msaa_3d = {"msaa2": Viewport.MSAA_2X, "msaa4": Viewport.MSAA_4X}.get(aa, Viewport.MSAA_DISABLED)
	root.use_taa = aa == "taa"
	var shadows := str(Settings.get_value(&"shadow_quality"))
	RenderingServer.directional_shadow_atlas_set_size(int(SHADOW_SIZES.get(shadows, 4096)), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(SHADOW_FILTERS.get(shadows, RenderingServer.SHADOW_QUALITY_SOFT_LOW))
	RenderingServer.positional_soft_shadow_filter_set_quality(SHADOW_FILTERS.get(shadows, RenderingServer.SHADOW_QUALITY_SOFT_LOW))


static func level() -> String:
	var l := str(Settings.get_value(&"graphics_quality"))
	return l if LEVELS.has(l) else "standard"


static func at_least(l: String) -> bool:
	return LEVELS.find(level()) >= LEVELS.find(l)


## Whether this renderer can do the high presets at all.
static func supported() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


## Applies the preset to an environment and the sun (call again after
## either is replaced, e.g. by a time-of-day change).
static func apply(env: Environment, sun: DirectionalLight3D, mood := "day") -> void:
	var rich := at_least("high") and supported()
	env.tonemap_mode = Environment.TONE_MAPPER_AGX if rich else Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0 if rich else 1.0
	# AgX compresses highlights: a touch more exposure keeps daylight bright.
	env.tonemap_exposure = ((1.0 if mood == "night" else 1.2) if rich else 1.0) * float(Settings.get_value(&"brightness"))
	env.sdfgi_enabled = rich
	if rich:
		env.sdfgi_use_occlusion = true
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = 0.2
		env.sdfgi_energy = 1.0
		env.sdfgi_bounce_feedback = 0.5
	env.ssil_enabled = rich
	env.ssil_intensity = 0.8
	# Screen-space AO, unless the player turned it off or ray-traced AO
	# replaces it (RayTracing turns it off while active).
	if not env.has_meta(&"rt_active"):
		env.ssao_enabled = bool(Settings.get_value(&"ambient_occlusion"))
	env.ssao_intensity = 2.2 if rich else 2.0
	env.ssao_power = 1.6 if rich else 1.5
	env.volumetric_fog_enabled = rich
	if rich:
		var night := mood == "night"
		env.volumetric_fog_density = {"day": 0.0035, "dawn": 0.012, "dusk": 0.012, "night": 0.02}.get(mood, 0.005)
		env.volumetric_fog_albedo = Color(0.82, 0.84, 0.9)
		env.volumetric_fog_anisotropy = 0.55
		env.volumetric_fog_length = 90.0
		env.volumetric_fog_ambient_inject = 0.15 if night else 0.3
		env.volumetric_fog_sky_affect = 0.25
		env.fog_enabled = false
	env.glow_enabled = bool(Settings.get_value(&"bloom"))
	env.glow_intensity = 0.7 if rich else 0.8
	env.glow_bloom = 0.06 if rich else 0.0
	env.glow_hdr_threshold = 1.1 if rich else 1.0
	env.adjustment_enabled = rich
	if rich:
		# A little grittier than a cartoon: more contrast, slightly muted colour.
		env.adjustment_contrast = 1.08
		env.adjustment_saturation = 0.95
		env.adjustment_brightness = 1.0
	if sun:
		sun.light_angular_distance = 0.6 if rich else 0.0
		sun.shadow_blur = 1.2 if rich else 1.0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.light_volumetric_fog_energy = 1.4 if rich else 1.0


## Film grain and a vignette over the 3D view (Cinematic only), or null.
static func grain_layer() -> CanvasLayer:
	if not at_least("cinematic"):
		return null
	var layer := CanvasLayer.new()
	layer.name = "FilmGrain"
	# Under the HUD and menus.
	layer.layer = 2
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/film_grain.gdshader")
	rect.material = mat
	layer.add_child(rect)
	return layer


## Depth of field for a cinematic shot focused `focus` metres away (null below
## Cinematic: no blur).
static func shot_attributes(focus: float) -> CameraAttributesPractical:
	if not at_least("cinematic") or not supported():
		return null
	var a := CameraAttributesPractical.new()
	a.dof_blur_far_enabled = true
	a.dof_blur_far_distance = focus + 2.5
	a.dof_blur_far_transition = maxf(focus * 1.5, 4.0)
	a.dof_blur_amount = 0.08
	return a
