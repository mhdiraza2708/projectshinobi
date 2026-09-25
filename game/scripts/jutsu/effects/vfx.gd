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


## A kunai: diamond steel blade, cord-wrapped grip and pommel ring, pointing
## down -Z. About 30 cm long, like the real thing.
static func kunai() -> Node3D:
	var root := Node3D.new()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.62, 0.64, 0.7)
	steel.metallic = 0.8
	steel.roughness = 0.3
	var cord := StandardMaterial3D.new()
	cord.albedo_color = Color(0.12, 0.1, 0.1)
	var blade := CylinderMesh.new()
	blade.top_radius = 0.0
	blade.bottom_radius = 0.035
	blade.height = 0.17
	blade.radial_segments = 4
	var blade_mi := MeshInstance3D.new()
	blade_mi.mesh = blade
	blade_mi.material_override = steel
	blade_mi.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(1.0, 0.35, 1.0)), Vector3(0, 0, -0.085))
	root.add_child(blade_mi)
	var grip := CylinderMesh.new()
	grip.top_radius = 0.01
	grip.bottom_radius = 0.01
	grip.height = 0.1
	var grip_mi := MeshInstance3D.new()
	grip_mi.mesh = grip
	grip_mi.material_override = cord
	grip_mi.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.05))
	root.add_child(grip_mi)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.014
	ring.outer_radius = 0.022
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.material_override = steel
	ring_mi.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.12))
	root.add_child(ring_mi)
	# Oversized for readability at combat distance.
	root.scale = Vector3.ONE * 2.0
	return root
