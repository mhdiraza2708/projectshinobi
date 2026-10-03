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
	env.tonemap_exposure = (1.0 if mood == "night" else 1.2) if rich else 1.0
	env.sdfgi_enabled = rich
	if rich:
		env.sdfgi_use_occlusion = true
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = 0.2
		env.sdfgi_energy = 1.0
		env.sdfgi_bounce_feedback = 0.5
	env.ssil_enabled = rich
	env.ssil_intensity = 0.8
	# (Whether SSAO is on is the ray tracing toggle's business.)
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
	env.glow_enabled = true
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
