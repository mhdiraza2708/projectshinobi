class_name Toon
extends RefCounted
## Converts imported materials to a cel-shaded look with an inverted-hull
## outline. Cheap and renderer-agnostic, which makes it a good default
## until a custom anime shader lands.

const OUTLINE_COLOR := Color(0.04, 0.04, 0.07)

static var _outline_cache: Dictionary = {}


static func apply(root: Node, outline_width := 0.012) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			if not src is BaseMaterial3D:
				continue
			var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
			m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			m.specular_mode = BaseMaterial3D.SPECULAR_TOON
			m.roughness = 0.85
			m.rim_enabled = true
			m.rim = 0.35
			m.rim_tint = 0.7
			if outline_width > 0.0:
				m.next_pass = outline(outline_width)
			mi.set_surface_override_material(i, m)


static func outline(width: float) -> StandardMaterial3D:
	if _outline_cache.has(width):
		return _outline_cache[width]
	var o := StandardMaterial3D.new()
	o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	o.albedo_color = OUTLINE_COLOR
	o.cull_mode = BaseMaterial3D.CULL_FRONT
	o.grow = true
	o.grow_amount = width
	_outline_cache[width] = o
	return o


static func flat(color: Color, roughness := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = roughness
	return m
