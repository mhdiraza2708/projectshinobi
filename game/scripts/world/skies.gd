class_name Skies
extends RefCounted
## Photographed skies and the light that goes with them. Each is a Poly
## Haven pure-sky HDRI (CC0), packed by art/polyhaven/fetch.py into
## assets/skies/<key>.jpg with its light level, sun position and colours in
## data/skies.json. apply() puts one over the world: the panorama turned so
## the photo's sun has the same bearing as the game's sun, the sun raised
## to the photo's elevation and given its colour, the ambient light and
## reflections taken from the sky, and the fog coloured like its horizon.

const DATA := "res://data/skies.json"
const DIR := "res://assets/skies/"
const SHADER := preload("res://assets/shaders/hdri_sky.gdshader")
## Per sky: how bright it's drawn (times the photo's own level), the sun's
## light energy, the ambient light energy and how bright the sun's disc is.
const LOOKS := {
	"day": {"sky": 0.8, "sun": 1.5, "ambient": 0.55, "disc": 1.0},
	"dawn": {"sky": 0.9, "sun": 1.3, "ambient": 0.6, "disc": 0.8},
	"dusk": {"sky": 1.0, "sun": 1.2, "ambient": 0.6, "disc": 0.8},
	"night": {"sky": 0.7, "sun": 0.4, "ambient": 0.6, "disc": 0.12},
	"overcast": {"sky": 0.75, "sun": 0.4, "ambient": 0.6, "disc": 0.0},
	"snow": {"sky": 0.8, "sun": 0.5, "ambient": 0.6, "disc": 0.0},
}
## The sun never sits lower than this: a sun on the horizon leaves the
## arena in one long shadow.
const MIN_ELEVATION := 10.0
## Angular radius of the sun (or moon) disc, in radians.
const DISC_RADIUS := 0.0047
## The Compatibility renderer shows these light levels without the filmic
## curve that brings their middle tones down in Forward+: scale the light
## by about as much instead.
const COMPATIBILITY_GAIN := 0.5

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if parsed is Dictionary and (parsed as Dictionary).get("skies") is Dictionary:
			_data = parsed["skies"]
	return _data


static func has_sky(key: String) -> bool:
	return data().has(key) and ResourceLoader.exists(DIR + key + ".jpg")


## The sky a time of day shows in a weather: a grey sky in rain, storms and
## snow (except at night, which only darkens).
static func key_for(time: String, weather: String) -> String:
	if time != "night":
		if weather in ["rain", "storm"] and has_sky("overcast"):
			return "overcast"
		if weather == "snow" and has_sky("snow"):
			return "snow"
	return time if has_sky(time) else "day"


## The direction a point of the panorama (u, v in 0-1) looks in.
static func panorama_direction(uv: Vector2) -> Vector3:
	var phi := (uv.x - 0.5) * TAU
	var theta := uv.y * PI
	return Vector3(sin(theta) * sin(phi), cos(theta), -sin(theta) * cos(phi))


## The turn about the vertical that brings `from` to the bearing of `to`.
static func turn_between(from: Vector3, to: Vector3) -> Basis:
	var angle := Vector2(from.x, from.z).angle_to(Vector2(to.x, to.z))
	# A 2D angle from X toward Z is the opposite way round to a turn about +Y.
	return Basis(Vector3.UP, -angle)


## Puts the sky `key` over `env` and points `sun` at its sun, on a bearing
## of `yaw` degrees. `dim` darkens everything (a night storm).
static func apply(env: Environment, sun: DirectionalLight3D, key: String, yaw: float, dim := 1.0) -> void:
	if not has_sky(key):
		return
	var s: Dictionary = data()[key]
	var look: Dictionary = LOOKS.get(key, LOOKS["day"])
	dim *= 1.0 if Graphics.supported() else COMPATIBILITY_GAIN
	var scale := float(s["scale"]) * float(look["sky"]) * dim
	var elevation := maxf(float(s["sun_elevation"]), MIN_ELEVATION)
	var sun_rot := Vector3(deg_to_rad(-elevation), deg_to_rad(yaw), 0.0)
	# A DirectionalLight shines down its -Z: +Z points at the sun.
	var toward := Basis.from_euler(sun_rot).z
	var photo_sun := panorama_direction(Vector2(s["sun_uv"][0], s["sun_uv"][1]))
	var turn := turn_between(photo_sun, toward)
	var sun_rgb := _color(s["sun_color"])

	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter(&"panorama", load(DIR + key + ".jpg"))
	mat.set_shader_parameter(&"scale", scale)
	mat.set_shader_parameter(&"to_panorama", turn.inverse())
	mat.set_shader_parameter(&"sun_direction", (turn * photo_sun).normalized())
	mat.set_shader_parameter(&"sun_color", Vector3(sun_rgb.r, sun_rgb.g, sun_rgb.b) * float(look["disc"]) * dim)
	mat.set_shader_parameter(&"sun_radius", DISC_RADIUS)
	var sky := Sky.new()
	sky.sky_material = mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3.ZERO

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = float(look["ambient"]) * dim
	# Still kept up to date for what reads it directly (ray-traced reflections).
	env.ambient_light_color = _srgb(_color(s["ambient"]) * scale)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Distant ground fades into the colour of the sky behind it.
	var horizon := _color(s["horizon"]) * scale
	var peak := maxf(horizon.r, maxf(horizon.g, horizon.b))
	env.fog_light_color = _srgb(horizon / maxf(peak, 1e-4))
	env.fog_light_energy = peak
	env.fog_aerial_perspective = 0.7
	env.fog_sky_affect = 0.0

	sun.rotation = sun_rot
	sun.light_color = _srgb(sun_rgb)
	sun.light_energy = float(look["sun"]) * dim


## The sky shader's material on `env`, if it has one of these skies.
static func material(env: Environment) -> ShaderMaterial:
	if env and env.sky and env.sky.sky_material is ShaderMaterial \
			and (env.sky.sky_material as ShaderMaterial).shader == SHADER:
		return env.sky.sky_material
	return null


static func _color(a: Array) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]))


## Linear light to the sRGB a Color property expects.
static func _srgb(c: Color) -> Color:
	return Color(c.r, c.g, c.b).linear_to_srgb()
