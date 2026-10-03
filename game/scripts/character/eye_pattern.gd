class_name EyePattern
extends RefCounted
## Draws an eye art's pattern over a character's irises (eye_pattern.gdshader
## as a next pass on each iris material). Where the two irises sit in UV
## space is measured from the iris texture, so it fits any VRoid-style model;
## a model without a separate iris material simply shows nothing.

const SHADER := preload("res://assets/shaders/eye_pattern.gdshader")
const PATTERNS: PackedStringArray = ["hawk", "mirror", "seal", "still"]
## Where VRoid puts the irises, if the texture can't be read.
const DEFAULT_LAYOUT := {"a": Vector2(0.25, 0.5), "b": Vector2(0.75, 0.5), "radius": Vector2(0.115, 0.255)}

static var _layouts: Dictionary = {}


## The iris materials of `model` (its eye-slot materials named "iris").
static func iris_materials(model: Node) -> Array[Material]:
	var out: Array[Material] = []
	if model == null:
		return out
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.has_meta(&"gear"):
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m and "iris" in m.resource_name.to_lower() and not out.has(m):
				out.append(m)
	return out


## Puts a pattern on `model`'s irises (replacing any earlier one) and returns
## its material, to animate (intensity, awakened, spin); null if the model
## has no irises to draw on.
static func attach(model: Node, art: Dictionary) -> ShaderMaterial:
	var irises := iris_materials(model)
	if irises.is_empty():
		return null
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.render_priority = 10
	var layout := layout_of(irises[0])
	mat.set_shader_parameter(&"center_a", layout["a"])
	mat.set_shader_parameter(&"center_b", layout["b"])
	mat.set_shader_parameter(&"radius", layout["radius"])
	mat.set_shader_parameter(&"pattern", maxi(0, PATTERNS.find(str(art.get("pattern", "hawk")))))
	mat.set_shader_parameter(&"color", Color(str(art.get("color", "#ffffff"))))
	mat.set_shader_parameter(&"intensity", 0.0)
	for iris in irises:
		iris.next_pass = mat
	return mat


## Takes any pattern off `model`'s irises.
static func detach(model: Node) -> void:
	for iris in iris_materials(model):
		if iris.next_pass and iris.next_pass is ShaderMaterial \
				and (iris.next_pass as ShaderMaterial).shader == SHADER:
			iris.next_pass = null


## Where the two irises are drawn in the iris texture: {a, b: centre UVs,
## radius: half size in UV}. Measured once per texture.
static func layout_of(iris: Material) -> Dictionary:
	var tex: Texture2D = null
	if iris is ShaderMaterial:
		var t: Variant = (iris as ShaderMaterial).get_shader_parameter(&"_MainTex")
		tex = t as Texture2D
	elif iris is BaseMaterial3D:
		tex = (iris as BaseMaterial3D).albedo_texture
	if tex == null:
		return DEFAULT_LAYOUT
	var key := tex.resource_path if tex.resource_path != "" else str(tex.get_rid().get_id())
	if not _layouts.has(key):
		_layouts[key] = _measure(tex)
	return _layouts[key]


## The iris shapes: opaque, non-white pixels, one cluster in each half.
static func _measure(tex: Texture2D) -> Dictionary:
	var img := tex.get_image()
	if img == null:
		return DEFAULT_LAYOUT
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.resize(256, maxi(8, int(256.0 * img.get_height() / maxf(img.get_width(), 1.0))), Image.INTERPOLATE_BILINEAR)
	var w := img.get_width()
	var h := img.get_height()
	var lo := [Vector2(INF, INF), Vector2(INF, INF)]
	var hi := [Vector2(-INF, -INF), Vector2(-INF, -INF)]
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a < 0.5 or c.get_luminance() > 0.9:
				continue
			var side := 0 if x < w / 2 else 1
			var uv := Vector2((x + 0.5) / w, (y + 0.5) / h)
			lo[side] = (lo[side] as Vector2).min(uv)
			hi[side] = (hi[side] as Vector2).max(uv)
	if lo[0].x == INF or lo[1].x == INF:
		return DEFAULT_LAYOUT
	var r0: Vector2 = (hi[0] - lo[0]) * 0.5
	var r1: Vector2 = (hi[1] - lo[1]) * 0.5
	var radius := (r0 + r1) * 0.5
	# A blob too small or too big is not a pair of irises.
	if radius.x < 0.03 or radius.x > 0.3:
		return DEFAULT_LAYOUT
	return {"a": (lo[0] + hi[0]) * 0.5, "b": (lo[1] + hi[1]) * 0.5, "radius": radius}
