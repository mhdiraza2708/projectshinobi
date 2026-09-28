class_name TerrainMaterial
extends RefCounted
## The textured ground material (assets/shaders/terrain.gdshader): four
## tileable layers from art/blender/textures.py, each tinted so its average
## colour becomes the colour asked for (an island's palette).

const SHADER := preload("res://assets/shaders/terrain.gdshader")
const TEX := "res://assets/textures/"
const LAYERS: PackedStringArray = ["grass", "dirt", "rock", "sand"]

static var _means: Dictionary = {}


## `textures`: layer -> texture set name (e.g. {"grass": "snow"} on a snowy
## island). `colors`: layer -> the average colour wanted (null keeps the
## texture's own colour); "grass2" is a second grass colour for broad patches.
static func make(textures := {}, colors := {}, arena_radius := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	for layer in LAYERS:
		var set_name: String = textures.get(layer, layer)
		m.set_shader_parameter(StringName(layer + "_albedo"), load(TEX + set_name + "_albedo.png"))
		m.set_shader_parameter(StringName(layer + "_normal"), load(TEX + set_name + "_normal.png"))
		var want: Variant = colors.get(layer)
		if want is Color:
			m.set_shader_parameter(StringName(layer + "_tint"), tint(set_name, want))
		if layer == "grass":
			var want2: Variant = colors.get("grass2", want)
			if want2 is Color:
				m.set_shader_parameter(&"grass_tint2", tint(set_name, want2))
	# What ray-traced reflections see: each layer's colour, in splat order.
	var palette := PackedColorArray()
	for layer in LAYERS:
		var want: Variant = colors.get(layer)
		palette.append(want if want is Color else mean_color(textures.get(layer, layer)))
	m.set_meta(&"rt_palette", palette)
	m.set_meta(&"rt_color", palette[0])
	m.set_shader_parameter(&"noise", load("res://assets/vfx/noise.png"))
	m.set_shader_parameter(&"arena_radius", arena_radius)
	return m


## The multiplier that makes a texture set average out to `want`. The shader
## multiplies after the texture is converted to linear light, so the ratio
## is taken in linear light too.
static func tint(set_name: String, want: Color) -> Vector3:
	var mean := mean_color(set_name).srgb_to_linear()
	var lin := want.srgb_to_linear()
	return Vector3(lin.r / maxf(mean.r, 0.004), lin.g / maxf(mean.g, 0.004), lin.b / maxf(mean.b, 0.004))


## A texture set's average colour (cached), in sRGB like the image.
static func mean_color(set_name: String) -> Color:
	if not _means.has(set_name):
		var tex: Texture2D = load(TEX + set_name + "_albedo.png")
		var img := tex.get_image()
		if img == null:
			_means[set_name] = Color(0.5, 0.5, 0.5)
		else:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			img.clear_mipmaps()
			# Halving step by step averages every pixel (one big resize only
			# samples a few near the middle).
			while img.get_width() > 1 or img.get_height() > 1:
				img.resize(maxi(img.get_width() / 2, 1), maxi(img.get_height() / 2, 1), Image.INTERPOLATE_BILINEAR)
			_means[set_name] = img.get_pixel(0, 0)
	return _means[set_name]
