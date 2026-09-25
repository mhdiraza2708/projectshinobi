class_name Vfx
extends RefCounted
## Tiny procedural VFX kit so every jutsu reads clearly before real effects
## art exists. Works in both the Forward+ and Compatibility renderers.


static func glow_material(color: Color, energy := 2.5, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func sphere(radius: float, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func light(color: Color, light_range: float, energy := 2.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.omni_range = light_range
	l.light_energy = energy
	return l


static func trail(color: Color, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.35
	p.local_coords = false
	p.direction = Vector3.ZERO
	p.spread = 180.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = glow_material(color, 2.0, 0.8)
	p.mesh = mesh
	return p


## A sphere that expands and fades, then frees itself.
static func burst(parent: Node, position: Vector3, color: Color, radius: float, duration := 0.4) -> void:
	var s := sphere(1.0, glow_material(color, 3.0, 0.55))
	parent.add_child(s)
	s.global_position = position
	s.scale = Vector3.ONE * radius * 0.2
	var mat := s.material_override as StandardMaterial3D
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "scale", Vector3.ONE * radius, duration) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(s.queue_free)
