class_name TerrainMaterial
extends RefCounted
## The textured ground material (assets/shaders/terrain.gdshader): four
## layers, each tinted so its average colour becomes the colour asked for
## (an island's palette). The layers are photo-scanned surfaces from Poly
## Haven in GROUND (art/polyhaven/fetch.py; data/ground.json has each one's
## real size), falling back to the procedural sets in TEX (art/blender/
## textures.py) for any set that wasn't scanned.

const SHADER := preload("res://assets/shaders/terrain.gdshader")
const TEX := "res://assets/textures/"
const GROUND := "res://assets/textures/ground/"
const GROUND_DATA := "res://data/ground.json"
const LAYERS: PackedStringArray = ["grass", "dirt", "rock", "sand"]
## Metres per repeat of a procedural set.
const PROCEDURAL_TILE := 4.0
## How rough each kind of ground is (anything else: DEFAULT_ROUGHNESS).
const ROUGHNESS := {"rock": 0.8, "sand": 0.88, "snow": 0.6}
const DEFAULT_ROUGHNESS := 0.94

static var _means: Dictionary = {}
static var _sizes: Dictionary = {}


## `textures`: layer -> texture set name (e.g. {"grass": "snow"} on a snowy
## island). `colors`: layer -> the average colour wanted (null keeps the
## texture's own colour); "grass2" is a second grass colour for broad patches.
static func make(textures := {}, colors := {}, arena_radius := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var tiles := Vector4.ONE
	var rough := Vector4.ONE
	for i in LAYERS.size():
		var layer := LAYERS[i]
		var set_name: String = textures.get(layer, layer)
		m.set_shader_parameter(StringName(layer + "_albedo"), load(albedo_path(set_name)))
		m.set_shader_parameter(StringName(layer + "_normal"), load(normal_path(set_name)))
		tiles[i] = tile_size(set_name)
		rough[i] = ROUGHNESS.get(set_name, DEFAULT_ROUGHNESS)
		var want: Variant = colors.get(layer)
		if want is Color:
			m.set_shader_parameter(StringName(layer + "_tint"), tint(set_name, want))
		if layer == "grass":
			var want2: Variant = colors.get("grass2", want)
			if want2 is Color:
				m.set_shader_parameter(&"grass_tint2", tint(set_name, want2))
	m.set_shader_parameter(&"tile_sizes", tiles)
	m.set_shader_parameter(&"roughness", rough)
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


static func scanned(set_name: String) -> bool:
	return ResourceLoader.exists(GROUND + set_name + "_albedo.jpg")


static func albedo_path(set_name: String) -> String:
	return GROUND + set_name + "_albedo.jpg" if scanned(set_name) else TEX + set_name + "_albedo.png"


static func normal_path(set_name: String) -> String:
	return GROUND + set_name + "_normal.jpg" if scanned(set_name) else TEX + set_name + "_normal.png"


## Metres per repeat: a scanned surface's real size.
static func tile_size(set_name: String) -> float:
	if _sizes.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GROUND_DATA))
		if parsed is Dictionary and (parsed as Dictionary).get("ground") is Dictionary:
			for k: String in parsed["ground"]:
				_sizes[k] = float(parsed["ground"][k].get("size", PROCEDURAL_TILE))
		_sizes[&""] = 0.0  # loaded
	return _sizes.get(set_name, PROCEDURAL_TILE) if scanned(set_name) else PROCEDURAL_TILE


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
		var tex: Texture2D = load(albedo_path(set_name))
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
