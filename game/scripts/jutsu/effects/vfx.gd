class_name Vfx
extends RefCounted
## The effects kit: textured billboard particles, ribbons, bolts and energy
## shaders, and the effects built from them (a look per chakra nature for
## projectiles, impacts, blasts and auras, plus strikes, smoke puffs, dust
## and hit flashes). Works in both the Forward+ and Compatibility renderers.
## One-shot effects add themselves to `parent` and free themselves.

const ENERGY_SHADER := preload("res://assets/shaders/energy_shell.gdshader")
const ENERGY_MIX_SHADER := preload("res://assets/shaders/energy_shell_mix.gdshader")
const FIRE_SHADER := preload("res://assets/shaders/fireball.gdshader")
const KUNAI_MODEL := preload("res://assets/models/kunai.gltf")
const TEX_DIR := "res://assets/vfx/"

static var _tex: Dictionary = {}
static var _materials: Dictionary = {}


# --- Materials -------------------------------------------------------------------

static func tex(name: StringName) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load(TEX_DIR + name + ".png")
	return _tex[name]


## Unshaded, vertex-coloured, camera-facing particle material. `atlas`
## textures hold 2x2 variations; each particle picks one.
static func particle_material(texture_name: StringName, additive := true, atlas := false) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [texture_name, additive, atlas]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex(texture_name)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	if atlas:
		m.particles_anim_h_frames = 2
		m.particles_anim_v_frames = 2
		m.particles_anim_loop = false
	_materials[key] = m
	return m


## Material for ribbons, bolts, rings and slashes (not billboarded).
static func surface_material(texture: Texture2D, additive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = texture
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


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


## Energy with a fresnel rim. Alpha-blended by default so it keeps its
## colour in daylight; `additive` for glows that should bloom.
static func energy_material(color: Color, intensity := 1.4, core := 0.25, rim_power := 2.2, additive := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ENERGY_SHADER if additive else ENERGY_MIX_SHADER
	m.set_shader_parameter(&"color", color)
	m.set_shader_parameter(&"intensity", intensity)
	m.set_shader_parameter(&"core", core)
	m.set_shader_parameter(&"rim_power", rim_power)
	m.set_shader_parameter(&"noise", tex(&"noise"))
	return m


static func fire_material(intensity := 1.3) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FIRE_SHADER
	m.set_shader_parameter(&"intensity", intensity)
	m.set_shader_parameter(&"noise", tex(&"noise"))
	return m


# --- Building blocks -------------------------------------------------------------

static func sphere(radius: float, material: Material, segments := 24) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = segments / 2
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


static func gradient(colors: Array, offsets: Array = []) -> Gradient:
	var g := Gradient.new()
	var pts := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		pts.append(offsets[i] if i < offsets.size() else float(i) / maxf(colors.size() - 1, 1))
		cols.append(colors[i])
	g.offsets = pts
	g.colors = cols
	return g


static func curve(points: Array) -> Curve:
	var c := Curve.new()
	for p: Vector2 in points:
		c.add_point(p)
	return c


## A quad with a streak texture crossed with itself, for sparks that point
## along their velocity (particle_flag_align_y).
static func streak_mesh(length: float, width: float, additive := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		var s := axis * width * 0.5
		var top := Vector3.UP * length * 0.5
		var quad := [[-s - top, Vector2(0, 1)], [s - top, Vector2(1, 1)], [s + top, Vector2(1, 0)],
			[-s - top, Vector2(0, 1)], [s + top, Vector2(1, 0)], [-s + top, Vector2(0, 0)]]
		for v: Array in quad:
			st.set_color(Color.WHITE)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	var mat := surface_material(tex(&"spark"), additive)
	st.set_material(mat)
	return st.commit()


## Particles from a spec. Keys (all optional):
##   texture, additive (default off: colours hold up in daylight), atlas, amount, lifetime, one_shot, explosiveness,
##   size [min, max], size_curve (Curve), colors (Gradient), speed [min, max],
##   direction, spread, gravity, radius (sphere emission), ring [radius, axis],
##   damping, local, spin [min, max] (deg/s), mesh (Mesh), align (bool),
##   randomness, tangential [min, max], radial [min, max], orbit [min, max]
static func particles(spec: Dictionary) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = spec.get("amount", 16)
	p.lifetime = spec.get("lifetime", 0.5)
	p.one_shot = spec.get("one_shot", false)
	p.explosiveness = spec.get("explosiveness", 1.0 if p.one_shot else 0.0)
	p.randomness = spec.get("randomness", 0.3)
	p.local_coords = spec.get("local", false)
	p.fixed_fps = 0
	p.draw_order = CPUParticles3D.DRAW_ORDER_INDEX
	if spec.has("mesh"):
		p.mesh = spec["mesh"]
	else:
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		quad.material = particle_material(spec.get("texture", &"glow"), spec.get("additive", false), spec.get("atlas", false))
		p.mesh = quad
	if spec.get("atlas", false):
		p.anim_offset_min = 0.0
		p.anim_offset_max = 1.0
	var size: Array = spec.get("size", [0.3, 0.5])
	p.scale_amount_min = size[0]
	p.scale_amount_max = size[1]
	p.scale_amount_curve = spec.get("size_curve", curve([Vector2(0, 0.6), Vector2(0.2, 1.0), Vector2(1, 0.0)]))
	if spec.has("colors"):
		p.color_ramp = spec["colors"]
	var speed: Array = spec.get("speed", [0.0, 0.0])
	p.initial_velocity_min = speed[0]
	p.initial_velocity_max = speed[1]
	p.direction = spec.get("direction", Vector3.UP)
	p.spread = spec.get("spread", 180.0)
	p.gravity = spec.get("gravity", Vector3.ZERO)
	var damping: float = spec.get("damping", 0.0)
	p.damping_min = damping
	p.damping_max = damping
	if spec.has("radius"):
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = spec["radius"]
	if spec.has("ring"):
		var ring: Array = spec["ring"]
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		p.emission_ring_radius = ring[0]
		p.emission_ring_inner_radius = ring[0] * 0.85
		p.emission_ring_height = 0.05
		p.emission_ring_axis = ring[1] if ring.size() > 1 else Vector3.UP
	if spec.has("spin"):
		var spin: Array = spec["spin"]
		p.angular_velocity_min = spin[0]
		p.angular_velocity_max = spin[1]
		p.angle_min = 0.0
		p.angle_max = 360.0
	for key in ["tangential", "radial", "orbit"]:
		if spec.has(key):
			var r: Array = spec[key]
			match key:
				"tangential":
					p.tangential_accel_min = r[0]
					p.tangential_accel_max = r[1]
				"radial":
					p.radial_accel_min = r[0]
					p.radial_accel_max = r[1]
				"orbit":
					p.orbit_velocity_min = r[0]
					p.orbit_velocity_max = r[1]
	p.particle_flag_align_y = spec.get("align", false)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = not p.one_shot
	return p


## Adds a one-shot effect node at `position` and frees it when done.
static func _spawn(parent: Node, node: Node3D, position: Vector3, life: float) -> Node3D:
	if parent == null or not parent.is_inside_tree():
		node.free()
		return null
	parent.add_child(node)
	node.global_position = position
	var emitters: Array = node.find_children("*", "CPUParticles3D", true, false)
	if node is CPUParticles3D:
		emitters.append(node)
	for p: CPUParticles3D in emitters:
		if p.one_shot:
			p.restart()
	node.get_tree().create_timer(life, false).timeout.connect(node.queue_free)
	return node


static func burst_particles(parent: Node, position: Vector3, spec: Dictionary) -> void:
	var s := spec.duplicate()
	s["one_shot"] = true
	var p := particles(s)
	_spawn(parent, p, position, p.lifetime * 1.6 + 0.1)


## Detaches ribbons and particle emitters from a node that's about to go,
## so they finish in place instead of vanishing mid-air.
static func linger(node: Node, world: Node) -> void:
	if world == null or not world.is_inside_tree():
		return
	for child in node.get_children():
		if child is VfxTrail:
			var trail := child as VfxTrail
			trail.emitting = false
			trail.reparent(world)
		elif child is CPUParticles3D and not (child as CPUParticles3D).local_coords:
			var p := child as CPUParticles3D
			p.emitting = false
			p.reparent(world)
			p.get_tree().create_timer(p.lifetime + 0.1, false).timeout.connect(p.queue_free)


static func trail(color: Color, width: float, lifetime := 0.25, additive := false) -> VfxTrail:
	var t := VfxTrail.new()
	t.color = color
	t.width = width
	t.lifetime = lifetime
	t.additive = additive
	return t


## Ribbons winding round the node's +Y (turn it to aim): wind curling off a
## blade, a whirlwind, the twist of a water lance. See VfxSpiral.
static func spiral(color: Color, length: float, radius_base: float, radius_tip: float, turns := 1.5,
		spin := 8.0, ribbons := 3, width := 0.14, additive := false, lifetime := 0.0) -> VfxSpiral:
	var s := VfxSpiral.new()
	s.color = color
	s.length = length
	s.radius_base = radius_base
	s.radius_tip = radius_tip
	s.turns = turns
	s.spin = spin
	s.ribbons = ribbons
	s.width = width
	s.additive = additive
	s.lifetime = lifetime
	return s


## A soft camera-facing glare that stays where it's put (the flare at the
## head of a projectile): a `glow` or `star` quad `size` across.
static func glare(texture: StringName, color: Color, size: float, additive := true) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var m := surface_material(tex(texture), additive)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = color
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- One-shot effects -------------------------------------------------------------

## A bright flash that pops and fades (hits, casts, impacts).
static func flash(parent: Node, position: Vector3, color: Color, size := 1.5, duration := 0.18, texture := &"star", additive := true) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var m := surface_material(tex(texture), additive)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# A flash reads over whatever it's inside (a hit lands on a body).
	m.no_depth_test = true
	m.albedo_color = color
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _spawn(parent, mi, position, duration + 0.05) == null:
		return
	mi.scale = Vector3.ONE * size * 0.4
	mi.rotation.z = randf() * TAU
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, duration).set_ease(Tween.EASE_IN)


## A ring racing out along the ground (or facing `normal`).
static func shockwave(parent: Node, position: Vector3, color: Color, radius := 3.0, duration := 0.45, normal := Vector3.UP) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	quad.orientation = PlaneMesh.FACE_Z
	var m := surface_material(tex(&"ring"), false)
	m.albedo_color = color
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _spawn(parent, mi, position + normal * 0.06, duration + 0.05) == null:
		return
	mi.global_basis = Basis.looking_at(-normal, Vector3.FORWARD if absf(normal.y) > 0.9 else Vector3.UP)
	mi.scale = Vector3.ONE * radius * 0.1
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## A patch pressed into the ground that fades away: a scorch from a bolt, a
## wet stain from a splash.
static func ground_mark(parent: Node, position: Vector3, color: Color, radius := 1.2, duration := 1.4) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 2.0
	quad.orientation = PlaneMesh.FACE_Y
	var m := surface_material(tex(&"glow"), false)
	m.albedo_color = color
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _spawn(parent, mi, position + Vector3.UP * 0.04, duration + 0.05) == null:
		return
	mi.scale = Vector3.ONE * radius * 0.5
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, 0.15).set_ease(Tween.EASE_OUT)
	# It holds for a while, then fades.
	tw.tween_property(m, "albedo_color:a", 0.0, duration * 0.6).set_delay(duration * 0.4)


## The ninja's puff of smoke: arrivals, exits, clones popping.
static func smoke_puff(parent: Node, position: Vector3, size := 1.0, tint := Color(0.92, 0.92, 0.95)) -> void:
	flash(parent, position, Color(1, 1, 1, 0.8), 1.6 * size, 0.12, &"glow")
	burst_particles(parent, position, {"texture": &"smoke", "atlas": true, "additive": false,
		"amount": 18, "lifetime": 0.9, "size": [0.9 * size, 1.5 * size], "speed": [1.5 * size, 3.5 * size],
		"damping": 5.0, "radius": 0.35 * size, "gravity": Vector3(0, 0.6, 0), "spin": [-60, 60],
		"size_curve": curve([Vector2(0, 0.4), Vector2(0.25, 1.0), Vector2(1, 1.25)]),
		"colors": gradient([Color(tint, 0.95), Color(tint, 0.8), Color(tint.darkened(0.15), 0.0)], [0.0, 0.5, 1.0])})


## Dust kicked up from the ground (dashes, landings, walls rising).
static func dust(parent: Node, position: Vector3, size := 1.0, color := Color(0.78, 0.7, 0.58)) -> void:
	burst_particles(parent, position + Vector3.UP * 0.1, {"texture": &"smoke", "atlas": true, "additive": false,
		"amount": 12, "lifetime": 0.7, "size": [0.6 * size, 1.0 * size], "speed": [1.0 * size, 2.6 * size],
		"direction": Vector3.UP, "spread": 75.0, "damping": 4.0, "ring": [0.4 * size], "spin": [-40, 40],
		"size_curve": curve([Vector2(0, 0.5), Vector2(0.3, 1.0), Vector2(1, 1.3)]),
		"colors": gradient([Color(color, 0.7), Color(color, 0.0)])})


## Hot streaks thrown out from a hit.
static func sparks(parent: Node, position: Vector3, color: Color, count := 14, speed := 7.0, direction := Vector3.UP, spread := 180.0, gravity := -9.0) -> void:
	burst_particles(parent, position, {"mesh": streak_mesh(0.34, 0.08), "align": true, "amount": count,
		"lifetime": 0.38, "size": [0.7, 1.2], "speed": [speed * 0.5, speed], "direction": direction,
		"spread": spread, "gravity": Vector3(0, gravity, 0), "damping": 2.0,
		"size_curve": curve([Vector2(0, 1.0), Vector2(1, 0.0)]),
		"colors": gradient([Color(1, 1, 0.85), color, Color(color.darkened(0.2), 0.0)], [0.0, 0.35, 1.0])})


## A blade cutting through something: a tight, fast spray of sparks along the
## line of the swing (`direction`) and a few strays, thrown from `position`.
static func blade_sparks(parent: Node, position: Vector3, direction: Vector3, size := 1.0, color := Color(1.0, 0.82, 0.5)) -> void:
	sparks(parent, position, color, int(10 * size + 4), 12.0, direction, 20.0, -9.0)
	sparks(parent, position, color, int(4 * size + 2), 5.0, direction, 70.0, -14.0)


## Chunks of rock flung out and falling.
static func debris(parent: Node, position: Vector3, color: Color, count := 10, speed := 6.0, size := 1.0) -> void:
	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.16, 0.12, 0.14) * size
	var m := Toon.flat(color, 1.0)
	m.vertex_color_use_as_albedo = true
	chunk.material = m
	burst_particles(parent, position, {"mesh": chunk, "amount": count, "lifetime": 0.9,
		"size": [0.6, 1.4], "speed": [speed * 0.5, speed], "direction": Vector3.UP, "spread": 60.0,
		"gravity": Vector3(0, -16, 0), "spin": [-400, 400], "size_curve": curve([Vector2(0, 1), Vector2(0.8, 1), Vector2(1, 0)]),
		"colors": gradient([Color.WHITE, Color.WHITE])})


## A bolt of lightning from a to b.
static func bolt(parent: Node, a: Vector3, b: Vector3, color: Color, width := 0.08, duration := 0.2, branches := 2) -> VfxBolt:
	if parent == null or not parent.is_inside_tree():
		return null
	var v := VfxBolt.new()
	v.a = a
	v.b = b
	v.color = color
	v.width = width
	v.lifetime = duration
	v.branches = branches
	parent.add_child(v)
	return v


## A crescent slash swept across the front of `origin` (sword strikes,
## wind blades): a coloured edge with a white-hot inner arc. `tilt` rolls
## the arc round the direction of the swing. `strength` scales its opacity.
static func slash(parent: Node, origin: Transform3D, color: Color, size := 1.6, tilt := 0.0, duration := 0.18, strength := 1.0) -> void:
	var forward := -origin.basis.z.normalized()
	var flat := Basis.looking_at(forward, Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
	var basis := Basis(forward, tilt) * flat
	for layer in 2:
		var quad := QuadMesh.new()
		quad.size = Vector2(2.0, 1.0)
		var m := surface_material(tex(&"slash"), layer == 1)
		m.albedo_color = Color(color, color.a * strength) if layer == 0 else Color(1, 1, 1, 0.9 * strength)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _spawn(parent, mi, origin.origin, duration + 0.05) == null:
			return
		var s := size * (1.0 if layer == 0 else 0.86)
		mi.global_basis = basis
		mi.global_position = origin.origin + forward * size * 0.35
		mi.scale = Vector3.ONE * s * 0.7
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "scale", Vector3.ONE * s, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "albedo_color:a", 0.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


## A flat crescent: a bow of `radius` curving round toward -Z, `thickness`
## at its fullest and tapering to a point at each tip, lying in the XZ
## plane. The outer (leading) edge takes `outer` and the inner one `inner`,
## so it can be a hard bright edge fading toward its trailing side.
static func crescent_mesh(radius: float, thickness: float, outer: Color, inner: Color, half_arc := 1.15) -> ArrayMesh:
	var steps := 20
	var center := Vector3(0, 0, radius * 0.55)
	var out_pts := PackedVector3Array()
	var in_pts := PackedVector3Array()
	for i in steps + 1:
		var a := lerpf(-half_arc, half_arc, float(i) / steps)
		var dir := Vector3(sin(a), 0.0, -cos(a))
		var t := thickness * pow(maxf(cos(a * PI * 0.5 / half_arc), 0.0), 0.8)
		out_pts.append(center + dir * radius)
		in_pts.append(center + dir * (radius - t))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		for v: Array in [[out_pts[i], outer], [in_pts[i], inner], [out_pts[i + 1], outer],
				[in_pts[i], inner], [in_pts[i + 1], inner], [out_pts[i + 1], outer]]:
			st.set_color(v[1])
			st.add_vertex(v[0])
	return st.commit()


## Solid crescents of wind, one for each of `arcs` ([scale, roll]: the roll in
## degrees round the line of flight). Crossing arcs mean one or the other
## shows from any side. Each is three layers: a darker edge that shows
## against bright sky, the body in `color` and a white-hot core.
static func _crescent_blades(color: Color, size: float, arcs: Array) -> Node3D:
	var root := Node3D.new()
	var dark := color.darkened(0.5)
	# [radius, thickness, leading edge, trailing edge, additive]
	var layers: Array = [[1.06, 0.4, Color(dark, 0.95), Color(dark, 0.5), false],
		[1.0, 0.3, Color(color, 1.0), Color(color, 0.55), false],
		[0.99, 0.16, Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.0), true]]
	for arc: Array in arcs:
		var pivot := Node3D.new()
		pivot.rotation.z = deg_to_rad(arc[1])
		root.add_child(pivot)
		for layer: Array in layers:
			var mi := MeshInstance3D.new()
			mi.mesh = crescent_mesh(size * arc[0] * layer[0], size * arc[0] * layer[1], layer[2], layer[3])
			mi.material_override = surface_material(null, layer[4])
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pivot.add_child(mi)
	return root


## Where wind blades land: crossed crescent cuts hanging in the air for a
## moment, swelling as they fade.
static func _wind_cut(parent: Node, position: Vector3, color: Color, size: float, duration := 0.3) -> void:
	var cut := _crescent_blades(color, size, [[1.0, 55.0], [0.8, -35.0]])
	if _spawn(parent, cut, position, duration + 0.05) == null:
		return
	cut.rotation.y = randf() * TAU
	cut.scale = Vector3.ONE * 0.5
	var tw := cut.create_tween().set_parallel(true)
	tw.tween_property(cut, "scale", Vector3.ONE * 1.15, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	for mi: MeshInstance3D in cut.find_children("*", "MeshInstance3D", true, false):
		var m := mi.material_override as StandardMaterial3D
		tw.tween_property(m, "albedo_color:a", 0.0, duration * 0.7).set_delay(duration * 0.3)


## A flying crescent cut (Kenjutsu's Crescent Moon): two solid crescents
## crossing round the line of flight, air corkscrewing off them, with
## streaks and ribbons behind. Points along -Z like other projectile visuals.
static func crescent(color: Color, size := 2.0) -> Node3D:
	var root := _crescent_blades(color, size, [[1.0, 50.0], [0.7, -40.0]])
	root.name = "Crescent"
	# Air winding back from the tips: +Y turned round to +Z, wide where it
	# leaves the blade and drawing in behind.
	var curl := spiral(Color(color.lightened(0.1), 0.85), size * 2.4, size * 0.9, size * 0.12, 1.4, -14.0, 3, size * 0.16)
	curl.rotation.x = PI * 0.5
	curl.position.z = size * 0.1
	root.add_child(curl)
	root.add_child(particles({"mesh": streak_mesh(0.8, 0.05), "align": true, "amount": 18, "lifetime": 0.3,
		"size": [0.7, 1.3], "radius": size * 0.7, "speed": [0.1, 0.4],
		"colors": gradient([Color(0.95, 1.0, 0.95, 0.9), Color(color, 0.0)])}))
	root.add_child(trail(Color(color, 0.5), size * 0.5, 0.22))
	root.add_child(trail(Color(1, 1, 1, 0.5), size * 0.2, 0.15, true))
	return root


## Old API: a flash and a ring (kept for callers that just want "a pop").
static func burst(parent: Node, position: Vector3, color: Color, radius: float, duration := 0.4) -> void:
	flash(parent, position, color, radius * 1.4, duration * 0.6, &"glow")
	shockwave(parent, position, color, radius, duration, Vector3.UP)


# --- Per-nature looks ----------------------------------------------------------------

## The travelling part of a jutsu: a node to add to a projectile. It points
## along -Z (the projectile orients itself along its flight).
static func projectile_visual(element: int, radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var color := Element.color(element)
	match element:
		Element.FIRE:
			root.add_child(sphere(radius, fire_material(1.4)))
			var halo := sphere(radius * 1.7, energy_material(Color(1.0, 0.45, 0.1), 0.7, 0.0, 1.5, true))
			root.add_child(halo)
			root.add_child(particles({"texture": &"flame", "atlas": true, "amount": int(18 + radius * 30),
				"lifetime": 0.35, "size": [radius * 1.6, radius * 2.6], "radius": radius * 0.6,
				"speed": [0.4, 1.4], "gravity": Vector3(0, 2.5, 0), "spin": [-30, 30],
				"colors": gradient([Color(1, 0.95, 0.7), Color(1, 0.55, 0.1), Color(0.8, 0.15, 0.03, 0.6), Color(0.2, 0.05, 0.02, 0.0)], [0, 0.25, 0.6, 1.0])}))
			root.add_child(particles({"texture": &"smoke", "atlas": true, "additive": false, "amount": 10,
				"lifetime": 0.6, "size": [radius * 1.5, radius * 2.5], "radius": radius * 0.5, "speed": [0.2, 0.6],
				"gravity": Vector3(0, 1.5, 0), "spin": [-40, 40],
				"size_curve": curve([Vector2(0, 0.3), Vector2(1, 1.2)]),
				"colors": gradient([Color(0.25, 0.2, 0.18, 0.0), Color(0.25, 0.2, 0.18, 0.45), Color(0.3, 0.28, 0.27, 0.0)], [0, 0.3, 1.0])}))
			root.add_child(particles({"mesh": streak_mesh(0.12, 0.03), "align": true, "amount": 8,
				"lifetime": 0.5, "size": [0.6, 1.0], "radius": radius, "speed": [0.5, 2.0],
				"gravity": Vector3(0, 3.0, 0), "colors": gradient([Color(1, 0.8, 0.4), Color(1, 0.3, 0.05, 0.0)])}))
			root.add_child(trail(Color(1.0, 0.45, 0.1, 0.8), radius * 2.0, 0.22))
			root.add_child(light(Color(1.0, 0.55, 0.2), radius * 10.0 + 3.0, 2.5))
		Element.WATER:
			# A spear of water: a pointed body (tip forward) with a rounded
			# swell behind it, a bright core, and streams winding back.
			var tip := CylinderMesh.new()
			tip.top_radius = 0.0
			tip.bottom_radius = radius * 0.75
			tip.height = radius * 8.0
			tip.radial_segments = 16
			var lance := MeshInstance3D.new()
			lance.mesh = tip
			lance.material_override = energy_material(Color(0.12, 0.42, 1.0), 2.6, 0.7, 1.3)
			lance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# +Y (the point) turned to -Z, the way it flies.
			lance.basis = Basis(Vector3.RIGHT, -PI * 0.5)
			lance.position.z = -radius * 0.2
			root.add_child(lance)
			var swell := sphere(radius * 0.75, energy_material(Color(0.12, 0.42, 1.0), 2.4, 0.7, 1.3))
			swell.scale = Vector3(1, 1, 2.0)
			swell.position.z = radius * 3.9
			root.add_child(swell)
			var core := sphere(radius * 0.4, energy_material(Color(0.8, 0.95, 1.0), 1.4, 1.0, 1.2, true))
			core.scale = Vector3(1, 1, 5.0)
			core.position.z = radius * 0.5
			root.add_child(core)
			root.add_child(glare(&"glow", Color(0.55, 0.85, 1.0, 0.8), radius * 6.0))
			# Streams of water twisting back off the body.
			var streams := spiral(Color(0.5, 0.82, 1.0, 0.9), radius * 9.0, radius * 1.1, radius * 2.4, 1.6, 15.0, 2, radius * 0.6)
			streams.rotation.x = PI * 0.5
			streams.position.z = radius * 3.0
			root.add_child(streams)
			var foam := spiral(Color(0.95, 0.98, 1.0, 0.85), radius * 6.0, radius * 1.0, radius * 1.9, 1.2, -19.0, 2, radius * 0.35)
			foam.rotation.x = PI * 0.5
			foam.position.z = radius * 3.0
			root.add_child(foam)
			# Drops shaken off and streaks of spray.
			root.add_child(particles({"texture": &"glow", "amount": 24, "lifetime": 0.5,
				"size": [0.1, 0.22], "radius": radius * 0.9, "speed": [0.6, 2.2], "gravity": Vector3(0, -9, 0),
				"colors": gradient([Color(0.95, 0.98, 1.0, 0.95), Color(0.3, 0.62, 1.0, 0.8), Color(0.15, 0.45, 1.0, 0.0)], [0, 0.4, 1.0])}))
			root.add_child(particles({"mesh": streak_mesh(0.5, 0.06), "align": true, "amount": 12, "lifetime": 0.3,
				"size": [0.7, 1.2], "radius": radius * 1.1, "speed": [0.2, 0.8],
				"colors": gradient([Color(0.95, 0.98, 1.0, 0.9), Color(0.4, 0.7, 1.0, 0.0)])}))
			root.add_child(particles({"texture": &"smoke", "atlas": true, "amount": 10, "lifetime": 0.4,
				"size": [radius * 1.2, radius * 2.0], "radius": radius * 0.5, "speed": [0.2, 0.6],
				"colors": gradient([Color(0.8, 0.92, 1.0, 0.5), Color(0.8, 0.92, 1.0, 0.0)])}))
			root.add_child(trail(Color(0.2, 0.5, 1.0, 0.85), radius * 2.4, 0.32))
			root.add_child(trail(Color(0.85, 0.95, 1.0, 0.9), radius * 0.8, 0.18, true))
			root.add_child(light(Color(0.4, 0.7, 1.0), radius * 8.0 + 2.0, 1.5))
		Element.WIND:
			# Solid crescents crossing and whirling round the line of flight,
			# so they show from any side.
			var spinner := Spinner.new()
			spinner.axis = Vector3.BACK
			spinner.speed = 14.0
			root.add_child(spinner)
			spinner.add_child(_crescent_blades(Color(0.35, 0.9, 0.58), radius * 3.8, [[1.0, 50.0], [0.75, -40.0]]))
			# A ring of wind facing back along the flight, for the view from behind.
			var vortex := MeshInstance3D.new()
			var ring_quad := QuadMesh.new()
			ring_quad.size = Vector2.ONE * radius * 4.0
			vortex.mesh = ring_quad
			var vm := surface_material(tex(&"ring"), false)
			vm.albedo_color = Color(0.4, 0.9, 0.6, 0.75)
			vortex.material_override = vm
			vortex.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			vortex.position.z = radius * 0.8
			root.add_child(vortex)
			# Air corkscrewing back from the blades, and a darker twist so it
			# shows against bright sky.
			var curl := spiral(Color(0.4, 0.9, 0.62, 0.8), radius * 8.0, radius * 2.2, radius * 0.4, 1.5, -15.0, 3, radius * 0.35)
			curl.rotation.x = PI * 0.5
			root.add_child(curl)
			var curl_edge := spiral(Color(0.12, 0.55, 0.38, 0.55), radius * 6.0, radius * 2.0, radius * 0.5, 1.2, 11.0, 2, radius * 0.3)
			curl_edge.rotation.x = PI * 0.5
			root.add_child(curl_edge)
			root.add_child(particles({"mesh": streak_mesh(0.7, 0.05), "align": true, "amount": 24,
				"lifetime": 0.3, "size": [0.7, 1.3], "radius": radius * 1.8, "speed": [0.1, 0.3],
				"colors": gradient([Color(0.5, 0.95, 0.65, 0.9), Color(0.3, 0.8, 0.5, 0.0)])}))
			root.add_child(trail(Color(0.35, 0.85, 0.55, 0.6), radius * 5.0, 0.22))
		Element.LIGHTNING:
			var needle := sphere(radius * 1.3, energy_material(Color(1.0, 0.85, 0.2), 2.2, 1.0, 1.2))
			needle.scale = Vector3(0.7, 0.7, 3.2)
			root.add_child(needle)
			var hot := sphere(radius * 0.8, energy_material(Color(1.0, 0.97, 0.8), 2.0, 1.0, 1.2, true))
			hot.scale = Vector3(0.7, 0.7, 3.4)
			root.add_child(hot)
			# A flare at the tip, arcs jumping round it and a bolt streaming
			# back down the line it flew.
			root.add_child(glare(&"star", Color(1.0, 0.95, 0.65), radius * 12.0))
			root.add_child(glare(&"glow", Color(1.0, 0.8, 0.25, 0.7), radius * 9.0))
			var arcs := ArcCluster.new(radius * 4.5)
			arcs.count = 5
			arcs.width = 0.08
			arcs.tail = radius * 16.0
			root.add_child(arcs)
			root.add_child(trail(Color(1.0, 0.85, 0.2, 0.9), radius * 2.6, 0.14))
			root.add_child(trail(Color(1.0, 1.0, 0.9, 0.9), radius * 0.8, 0.1, true))
			# A faint violet afterglow hanging in the air.
			root.add_child(trail(Color(0.55, 0.5, 1.0, 0.4), radius * 5.0, 0.24))
			root.add_child(particles({"mesh": streak_mesh(0.18, 0.035), "align": true, "amount": 16,
				"lifetime": 0.22, "size": [0.7, 1.1], "radius": radius, "speed": [2.0, 5.0],
				"colors": gradient([Color.WHITE, Color(1, 0.9, 0.3, 0.0)])}))
			root.add_child(light(Color(1.0, 0.95, 0.6), 5.0, 3.0))
		Element.EARTH:
			var rock := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3.ONE * radius * 1.6
			rock.mesh = box
			rock.material_override = Toon.flat(color.darkened(0.2), 1.0)
			rock.rotation = Vector3(0.6, 0.8, 0.3)
			root.add_child(rock)
			root.add_child(particles({"texture": &"smoke", "atlas": true, "additive": false, "amount": 14,
				"lifetime": 0.5, "size": [radius * 1.5, radius * 2.5], "radius": radius, "speed": [0.1, 0.5],
				"colors": gradient([Color(0.6, 0.5, 0.38, 0.6), Color(0.6, 0.5, 0.38, 0.0)])}))
		_:
			root.add_child(sphere(radius, energy_material(color.lightened(0.2), 1.8, 0.7, 1.6)))
			root.add_child(sphere(radius * 1.7, energy_material(color, 0.8, 0.0, 2.5, true)))
			root.add_child(particles({"texture": &"glow", "amount": 16, "lifetime": 0.4,
				"size": [radius * 0.4, radius * 0.8], "radius": radius * 1.2, "speed": [0.2, 0.8],
				"colors": gradient([Color(color.lightened(0.4), 0.9), Color(color, 0.0)])}))
			root.add_child(trail(Color(color.lightened(0.2), 0.8), radius * 1.6, 0.22))
			root.add_child(light(color, radius * 10.0 + 2.0, 2.0))
	return root


## Where a jutsu or kunai hits.
static func impact(parent: Node, position: Vector3, element: int, size := 1.0) -> void:
	var color := Element.color(element)
	match element:
		Element.FIRE:
			flash(parent, position, Color(1.0, 0.75, 0.4), 2.2 * size, 0.2)
			burst_particles(parent, position, {"texture": &"flame", "atlas": true, "amount": int(22 * size + 6),
				"lifetime": 0.5, "size": [0.6 * size, 1.2 * size], "speed": [2.0 * size, 5.0 * size],
				"damping": 6.0, "gravity": Vector3(0, 4, 0), "spin": [-90, 90],
				"colors": gradient([Color(1, 0.95, 0.7), Color(1, 0.5, 0.08), Color(0.7, 0.12, 0.02, 0.5), Color(0.1, 0.05, 0.05, 0.0)], [0, 0.25, 0.6, 1.0])})
			burst_particles(parent, position, {"texture": &"smoke", "atlas": true, "additive": false, "amount": 8,
				"lifetime": 1.0, "size": [0.8 * size, 1.4 * size], "speed": [0.8, 2.0], "damping": 3.0,
				"gravity": Vector3(0, 1.8, 0), "spin": [-40, 40], "size_curve": curve([Vector2(0, 0.4), Vector2(1, 1.3)]),
				"colors": gradient([Color(0.2, 0.17, 0.15, 0.0), Color(0.2, 0.17, 0.15, 0.6), Color(0.35, 0.33, 0.32, 0.0)], [0, 0.25, 1.0])})
			sparks(parent, position, Color(1, 0.6, 0.2), int(10 * size + 6), 8.0)
			shockwave(parent, Vector3(position.x, _ground_y(parent, position), position.z), Color(1.0, 0.45, 0.1), 2.2 * size)
		Element.WATER:
			var ground := Vector3(position.x, _ground_y(parent, position), position.z)
			flash(parent, position, Color(0.75, 0.92, 1.0), 2.4 * size, 0.15, &"glow")
			# Drops flung and falling, long streaks of spray, and a crown of
			# streaks thrown up and out of the spot like a splash in a pool.
			var droplets := gradient([Color(0.95, 0.98, 1.0), Color(0.3, 0.62, 1.0, 0.95), Color(0.2, 0.5, 1.0, 0.0)], [0, 0.45, 1.0])
			burst_particles(parent, position, {"texture": &"glow", "amount": int(34 * size + 12), "lifetime": 0.7,
				"size": [0.18, 0.36], "speed": [3.5, 8.0], "direction": Vector3.UP, "spread": 80.0,
				"gravity": Vector3(0, -14, 0), "colors": droplets})
			burst_particles(parent, position, {"mesh": streak_mesh(0.4, 0.06), "align": true, "amount": int(12 * size + 6),
				"lifetime": 0.45, "size": [0.8, 1.3], "speed": [5.0, 10.0], "direction": Vector3.UP, "spread": 75.0,
				"gravity": Vector3(0, -12, 0), "damping": 1.0,
				"colors": gradient([Color(0.95, 0.98, 1.0, 0.95), Color(0.4, 0.7, 1.0, 0.0)])})
			burst_particles(parent, position - Vector3.UP * 0.3 * size, {"mesh": streak_mesh(1.0, 0.2), "align": true,
				"amount": 18, "lifetime": 0.4, "size": [1.0, 1.7], "ring": [0.35 * size], "speed": [2.0, 3.0],
				"direction": Vector3.UP, "spread": 12.0, "radial": [10.0, 16.0], "gravity": Vector3(0, -9, 0),
				"colors": gradient([Color(1, 1, 1, 0.95), Color(0.45, 0.75, 1.0, 0.8), Color(0.3, 0.6, 1.0, 0.0)], [0, 0.5, 1.0])})
			burst_particles(parent, position, {"texture": &"smoke", "atlas": true, "additive": false, "amount": 8,
				"lifetime": 0.7, "size": [0.6 * size, 1.1 * size], "speed": [1.0, 2.5], "damping": 4.0,
				"colors": gradient([Color(0.85, 0.93, 1.0, 0.6), Color(0.85, 0.93, 1.0, 0.0)])})
			shockwave(parent, ground, Color(0.5, 0.8, 1.0), 2.5 * size)
			shockwave(parent, ground, Color(0.9, 0.97, 1.0, 0.8), 1.5 * size, 0.3)
			ground_mark(parent, ground, Color(0.25, 0.4, 0.6, 0.35), 1.2 * size, 1.6)
		Element.WIND:
			var ground := Vector3(position.x, _ground_y(parent, position), position.z)
			flash(parent, position, Color(0.85, 1.0, 0.92), 1.8 * size, 0.14)
			# Crossed cuts of wind hanging where the blow landed.
			_wind_cut(parent, position, Color(0.35, 0.9, 0.58), 1.3 * size)
			# A ring of pressure at the height of the blow, a wider one along
			# the ground, and a little whirl winding up out of it.
			shockwave(parent, position, Color(0.7, 1.0, 0.85), 2.8 * size, 0.4, Vector3.UP)
			shockwave(parent, ground, Color(0.45, 0.9, 0.65), 2.2 * size, 0.5)
			var whirl := spiral(Color(0.5, 0.95, 0.7, 0.85), 1.9 * size, 0.25 * size, 0.7 * size, 2.0, 22.0, 3, 0.16 * size, false, 0.5)
			if _spawn(parent, whirl, ground + Vector3.UP * 0.1, 0.6) != null:
				var rise := whirl.create_tween().set_parallel(true)
				rise.tween_property(whirl, "scale", Vector3(1.5, 1.2, 1.5), 0.5).from(Vector3(0.6, 0.6, 0.6))
				rise.tween_property(whirl, "global_position:y", ground.y + 0.8, 0.5)
			dust(parent, ground, 0.7 * size, Color(0.85, 0.85, 0.75))
			# Grass and leaves torn up and thrown, and streaks of air.
			debris(parent, position, Color(0.42, 0.68, 0.3), 7, 5.0, 0.6)
			burst_particles(parent, position, {"mesh": streak_mesh(0.5, 0.03), "align": true, "amount": 16,
				"lifetime": 0.3, "size": [0.6, 1.2], "speed": [6.0, 10.0], "damping": 8.0,
				"colors": gradient([Color(0.9, 1.0, 0.95), Color(0.6, 0.9, 0.7, 0.0)])})
		Element.LIGHTNING:
			var ground := Vector3(position.x, _ground_y(parent, position), position.z)
			flash(parent, position, Color(1.0, 0.97, 0.75), 2.8 * size, 0.15)
			# The glare that lingers after the strike.
			flash(parent, position, Color(1.0, 0.82, 0.3, 0.8), 3.4 * size, 0.55, &"glow")
			# A bolt down onto the spot, forks racing out to the ground round
			# it and some thrown up and out.
			bolt(parent, position + Vector3(randf_range(-1, 1), 6.0 * size, randf_range(-1, 1)), position,
				Color(1.0, 0.95, 0.5), 0.14 * size, 0.32)
			for i in 6:
				var heading := TAU * (i + randf()) / 6.0
				var out := Vector3(cos(heading), 0.0, sin(heading)) * randf_range(1.4, 2.6) * size
				bolt(parent, position, ground + Vector3.UP * 0.1 + out, Color(1.0, 0.95, 0.5), 0.07, 0.28, 0)
			for i in 3:
				var d := Vector3(randf_range(-1, 1), randf_range(0.2, 1), randf_range(-1, 1)).normalized()
				bolt(parent, position, position + d * randf_range(1.0, 1.8) * size, Color(1.0, 0.95, 0.5), 0.05, 0.2, 0)
			sparks(parent, position, Color(1.0, 0.9, 0.4), 18, 10.0)
			shockwave(parent, ground, Color(1.0, 0.9, 0.4), 2.4 * size, 0.3)
			ground_mark(parent, ground, Color(0.1, 0.08, 0.06, 0.5), 1.1 * size, 1.4)
		Element.EARTH:
			flash(parent, position, Color(0.95, 0.85, 0.65), 1.4 * size, 0.12, &"glow")
			debris(parent, position, color.darkened(0.2), int(10 * size + 4), 6.0, size)
			dust(parent, position - Vector3.UP * 0.5, 1.2 * size)
		_:
			flash(parent, position, color.lightened(0.5), 2.0 * size, 0.16)
			shockwave(parent, position, color, 2.0 * size, 0.35, Vector3.UP)
			sparks(parent, position, color.lightened(0.3), int(10 * size + 4), 6.0)


## A kunai striking: a small bright flash and metal sparks.
static func kunai_hit(parent: Node, position: Vector3, direction: Vector3) -> void:
	flash(parent, position, Color(1.0, 0.8, 0.4), 0.9, 0.1, &"star", false)
	sparks(parent, position, Color(1.0, 0.85, 0.5), 8, 6.0, -direction, 70.0, -14.0)


## A strike connecting: star flash and sparks, tinted by the attacker's nature.
static func hit_spark(parent: Node, position: Vector3, color := Color(1.0, 0.62, 0.15), size := 1.0, facing := Vector3.ZERO) -> void:
	# A coloured star that holds up in daylight, a white-hot centre on top,
	# and a ring bursting out across the line of the blow.
	flash(parent, position, color, 2.2 * size, 0.2, &"star", false)
	flash(parent, position, Color(1, 1, 0.9), 1.1 * size, 0.12)
	if facing != Vector3.ZERO:
		shockwave(parent, position, Color(1.0, 0.9, 0.7), 1.3 * size, 0.2, facing.normalized())
	sparks(parent, position, color, int(10 * size + 6), 8.0, Vector3.UP, 180.0, -12.0)


## An area jutsu going off.
static func area_blast(parent: Node, center: Vector3, element: int, radius: float) -> void:
	var color := Element.color(element)
	var ground := Vector3(center.x, _ground_y(parent, center), center.z)
	shockwave(parent, ground, color.lightened(0.2), radius * 1.15, 0.55)
	shockwave(parent, ground, Color(1, 1, 1, 0.7), radius * 0.7, 0.3)
	flash(parent, center, color.lightened(0.5), minf(radius * 0.9, 3.0), 0.22, &"glow")
	match element:
		Element.FIRE:
			burst_particles(parent, ground + Vector3.UP * 0.3, {"texture": &"flame", "atlas": true,
				"amount": 60, "lifetime": 0.8, "size": [0.9, 1.8], "speed": [radius * 1.5, radius * 3.0],
				"direction": Vector3.UP, "spread": 80.0, "damping": radius * 1.2, "gravity": Vector3(0, 5, 0),
				"ring": [radius * 0.3], "spin": [-90, 90],
				"colors": gradient([Color(1, 0.95, 0.7), Color(1, 0.5, 0.08), Color(0.7, 0.12, 0.02, 0.5), Color(0.1, 0.05, 0.05, 0.0)], [0, 0.2, 0.55, 1.0])})
			burst_particles(parent, ground + Vector3.UP * 0.5, {"texture": &"smoke", "atlas": true, "additive": false,
				"amount": 16, "lifetime": 1.6, "size": [1.4, 2.4], "speed": [1.0, 3.0], "damping": 2.0,
				"gravity": Vector3(0, 2.5, 0), "ring": [radius * 0.5], "spin": [-30, 30],
				"size_curve": curve([Vector2(0, 0.4), Vector2(1, 1.4)]),
				"colors": gradient([Color(0.2, 0.17, 0.15, 0.0), Color(0.2, 0.17, 0.15, 0.55), Color(0.35, 0.33, 0.32, 0.0)], [0, 0.25, 1.0])})
			sparks(parent, ground + Vector3.UP * 0.5, Color(1, 0.6, 0.2), 30, 12.0, Vector3.UP, 60.0)
			# The white-hot heart of the bloom.
			burst_particles(parent, ground + Vector3.UP * 0.6, {"texture": &"glow", "additive": true, "amount": 14,
				"lifetime": 0.5, "size": [1.2, 2.2], "radius": radius * 0.3, "speed": [0.5, 2.0], "gravity": Vector3(0, 3, 0),
				"colors": gradient([Color(1, 0.95, 0.7, 0.9), Color(1, 0.5, 0.1, 0.0)])})
		Element.EARTH:
			for i in 9:
				var ang := TAU * i / 9.0 + randf_range(-0.2, 0.2)
				var at := ground + Vector3(cos(ang), 0, sin(ang)) * radius * randf_range(0.45, 0.85)
				_spike(parent, at, color.darkened(0.25), randf_range(0.9, 1.6))
			debris(parent, ground + Vector3.UP * 0.3, color.darkened(0.25), 24, 9.0, 1.4)
			dust(parent, ground, radius * 0.6)
		Element.WATER:
			_water_column(parent, ground, radius, 5.5)
			var droplets := gradient([Color(0.95, 0.98, 1.0), Color(0.35, 0.68, 1.0, 0.9), Color(0.2, 0.5, 1.0, 0.0)], [0, 0.45, 1.0])
			# A fountain: drops going up and falling back, long arcing streaks
			# of spray, and the crown of the column breaking at its top.
			burst_particles(parent, ground + Vector3.UP * 0.5, {"texture": &"glow", "amount": 56, "lifetime": 1.1,
				"size": [0.12, 0.28], "speed": [5.0, 11.0], "direction": Vector3.UP, "spread": 25.0,
				"gravity": Vector3(0, -14, 0), "radius": radius * 0.3, "colors": droplets})
			# White water boiling up the column.
			burst_particles(parent, ground + Vector3.UP * 0.3, {"texture": &"smoke", "atlas": true, "additive": false,
				"amount": 30, "lifetime": 0.55, "explosiveness": 0.4, "size": [0.7, 1.2], "speed": [9.0, 13.0],
				"direction": Vector3.UP, "spread": 3.0, "radius": radius * 0.2, "spin": [-60, 60],
				"colors": gradient([Color(1, 1, 1, 0.0), Color(0.95, 0.98, 1.0, 0.75), Color(0.8, 0.9, 1.0, 0.0)], [0, 0.25, 1.0])})
			burst_particles(parent, ground + Vector3.UP * 0.5, {"mesh": streak_mesh(0.5, 0.07), "align": true,
				"amount": 26, "lifetime": 1.0, "size": [0.8, 1.4], "speed": [7.0, 13.0], "direction": Vector3.UP,
				"spread": 22.0, "gravity": Vector3(0, -14, 0), "radius": radius * 0.25,
				"colors": gradient([Color(0.95, 0.98, 1.0, 0.95), Color(0.4, 0.7, 1.0, 0.0)])})
			if is_instance_valid(parent) and parent.is_inside_tree():
				parent.get_tree().create_timer(0.17, false).timeout.connect(func() -> void:
					if is_instance_valid(parent) and parent.is_inside_tree():
						burst_particles(parent, ground + Vector3.UP * 5.0, {"texture": &"glow", "amount": 28,
							"lifetime": 0.9, "size": [0.12, 0.26], "speed": [2.0, 5.0], "direction": Vector3.UP,
							"spread": 70.0, "radial": [1.0, 3.0], "gravity": Vector3(0, -12, 0),
							"radius": radius * 0.3, "colors": droplets}))
			burst_particles(parent, ground, {"texture": &"smoke", "atlas": true, "additive": false, "amount": 14,
				"lifetime": 1.0, "size": [1.0, 1.8], "speed": [2.0, 4.0], "damping": 3.0, "ring": [radius * 0.4],
				"colors": gradient([Color(0.85, 0.93, 1.0, 0.6), Color(0.85, 0.93, 1.0, 0.0)])})
			ground_mark(parent, ground, Color(0.25, 0.4, 0.6, 0.35), radius * 0.9, 1.8)
		Element.WIND:
			_tornado(parent, ground, radius)
			# Rings of air racing out, each a little higher and slower.
			for i in 3:
				shockwave(parent, ground + Vector3.UP * (0.3 + i * 0.7), Color(0.5, 0.92, 0.68),
					radius * (1.3 - i * 0.2), 0.4 + i * 0.1)
			burst_particles(parent, ground + Vector3.UP * 0.8, {"mesh": streak_mesh(0.6, 0.04), "align": true,
				"amount": 32, "lifetime": 0.5, "size": [0.6, 1.2], "ring": [radius * 0.3], "speed": [4.0, 8.0],
				"direction": Vector3.UP, "spread": 90.0, "damping": 2.0,
				"colors": gradient([Color(0.9, 1.0, 0.95), Color(0.6, 0.9, 0.7, 0.0)])})
			debris(parent, ground + Vector3.UP * 0.3, Color(0.42, 0.68, 0.3), 10, 6.0, 0.6)
			dust(parent, ground, radius * 0.5, Color(0.85, 0.85, 0.75))
		Element.LIGHTNING:
			for i in 6:
				var ang := TAU * i / 6.0
				var at := ground + Vector3(cos(ang), 0, sin(ang)) * radius * randf_range(0.3, 0.9)
				bolt(parent, at + Vector3.UP * 9.0, at, Color(1.0, 0.95, 0.5), 0.14, 0.34, 1)
				# Each strike spits a fork along the ground, and leaves its scorch.
				var heading := randf() * TAU
				bolt(parent, at + Vector3.UP * 0.2, at + Vector3.UP * 0.1 + Vector3(cos(heading), 0, sin(heading)) * randf_range(1.0, 2.0),
					Color(1.0, 0.95, 0.5), 0.07, 0.26, 0)
				ground_mark(parent, at, Color(0.1, 0.08, 0.06, 0.5), 0.9, 1.4)
			bolt(parent, ground + Vector3.UP * 9.0, ground + Vector3.UP * 0.2, Color(1.0, 0.95, 0.5), 0.2, 0.36)
			flash(parent, ground + Vector3.UP * 0.5, Color(1.0, 0.82, 0.3, 0.8), minf(radius * 1.2, 4.0), 0.5, &"glow")
			sparks(parent, ground + Vector3.UP * 0.3, Color(1.0, 0.9, 0.4), 30, 10.0, Vector3.UP, 80.0)
		_:
			# Every nature at once: five coloured pillars round the seal.
			for i in 5:
				var e: int = [Element.FIRE, Element.WIND, Element.LIGHTNING, Element.EARTH, Element.WATER][i]
				var ang := TAU * i / 5.0 - PI * 0.5
				var at := ground + Vector3(cos(ang), 0, sin(ang)) * radius * 0.6
				_pillar(parent, at, Element.color(e), 7.0, 1.1)
				shockwave(parent, at, Element.color(e), 1.6, 0.5)
			sparks(parent, ground + Vector3.UP * 0.5, Color.WHITE, 30, 10.0, Vector3.UP, 80.0)


## A column of water thrown up out of the ground and falling away: a body
## tapering up, a bright core, shooting up fast, then thinning and fading.
static func _water_column(parent: Node, at: Vector3, radius: float, height: float) -> void:
	var root := Node3D.new()
	var materials: Array[ShaderMaterial] = []
	for layer in 2:
		var body := CylinderMesh.new()
		body.bottom_radius = radius * (0.32 if layer == 0 else 0.13)
		body.top_radius = radius * (0.22 if layer == 0 else 0.09)
		body.height = height * (1.0 if layer == 0 else 0.9)
		body.cap_top = false
		body.cap_bottom = false
		body.radial_segments = 20
		var m := energy_material(Color(0.3, 0.62, 1.0), 1.1, 0.35, 1.4) if layer == 0 \
			else energy_material(Color(0.88, 0.97, 1.0), 1.3, 0.9, 1.2, true)
		materials.append(m)
		var mi := MeshInstance3D.new()
		mi.mesh = body
		mi.material_override = m
		mi.position.y = body.height * 0.5
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	# Water streaming up the column in twisting ribbons.
	root.add_child(spiral(Color(0.9, 0.97, 1.0, 0.9), height, radius * 0.3, radius * 0.24, 3.0, 22.0, 3, radius * 0.16, false, 0.9))
	root.add_child(spiral(Color(0.3, 0.6, 1.0, 0.8), height * 0.95, radius * 0.34, radius * 0.28, 2.4, -17.0, 3, radius * 0.18, false, 0.9))
	if _spawn(parent, root, at, 1.0) == null:
		return
	root.scale = Vector3(1.0, 0.05, 1.0)
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.25)
	tw.tween_property(root, "scale", Vector3(0.15, 0.7, 0.15), 0.5).set_ease(Tween.EASE_IN)
	for m in materials:
		tw.parallel().tween_method(func(v: float) -> void: m.set_shader_parameter(&"fade", v), 1.0, 0.0, 0.5).set_ease(Tween.EASE_IN)


## A column of coloured energy shooting up and thinning away.
static func _pillar(parent: Node, at: Vector3, color: Color, height: float, duration: float) -> void:
	var tube := CylinderMesh.new()
	tube.top_radius = 0.55
	tube.bottom_radius = 0.45
	tube.height = height
	tube.cap_top = false
	tube.cap_bottom = false
	tube.radial_segments = 20
	var mi := MeshInstance3D.new()
	mi.mesh = tube
	mi.material_override = energy_material(color, 2.2, 0.35, 1.4)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _spawn(parent, mi, at + Vector3.UP * height * 0.5, duration + 0.05) == null:
		return
	mi.scale = Vector3(0.2, 0.05, 0.2)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_interval(duration * 0.4)
	tw.tween_property(mi, "scale", Vector3(0.02, 1.2, 0.02), duration * 0.4).set_ease(Tween.EASE_IN)


## A small flat chip of stone (orbiting granite plates).
static func _chip_mesh(color: Color) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(0.16, 0.2, 0.04)
	var m := Toon.flat(color, 1.0)
	m.vertex_color_use_as_albedo = true
	b.material = m
	return b


## A whirlwind: bands of wind winding up out of the ground, wide at the top,
## with dust and torn-up leaves wheeling round inside, thrown up and away.
static func _tornado(parent: Node, at: Vector3, radius: float) -> void:
	var root := Node3D.new()
	if _spawn(parent, root, at, 1.0) == null:
		return
	var height := 3.8
	# Deep green bands (they show against pale sky), lighter ones turning the
	# other way and a white thread of air that glows.
	root.add_child(spiral(Color(0.2, 0.7, 0.48, 0.9), height, radius * 0.15, radius * 0.8, 2.0, 9.0, 4, radius * 0.22, false, 1.0))
	root.add_child(spiral(Color(0.55, 1.0, 0.75, 0.85), height * 0.95, radius * 0.1, radius * 0.62, 1.6, -12.0, 3, radius * 0.17, false, 1.0))
	root.add_child(spiral(Color(1, 1, 1, 0.7), height * 0.85, radius * 0.08, radius * 0.5, 1.3, 15.0, 2, radius * 0.1, true, 1.0))
	# A faint body so there is something between the bands.
	var funnel := CylinderMesh.new()
	funnel.top_radius = radius * 0.7
	funnel.bottom_radius = radius * 0.18
	funnel.height = height
	funnel.cap_top = false
	funnel.cap_bottom = false
	funnel.radial_segments = 24
	var body := MeshInstance3D.new()
	body.mesh = funnel
	body.material_override = energy_material(Color(0.5, 0.92, 0.65), 0.55, 0.0, 1.2)
	body.position.y = height * 0.5
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spin := Spinner.new()
	spin.speed = 7.0
	spin.add_child(body)
	root.add_child(spin)
	# Dust and leaves are emitted in a turning frame, so they wind round as
	# they climb and fling outward.
	var wheel := Spinner.new()
	wheel.speed = 5.0
	root.add_child(wheel)
	wheel.add_child(particles({"texture": &"smoke", "atlas": true, "local": true, "amount": 22, "lifetime": 0.8,
		"size": [0.5, 0.9], "ring": [radius * 0.2], "direction": Vector3.UP, "spread": 6.0, "speed": [2.5, 4.0],
		"radial": [1.0, 2.2], "spin": [-40, 40],
		"colors": gradient([Color(0.85, 0.8, 0.65, 0.0), Color(0.85, 0.8, 0.65, 0.45), Color(0.85, 0.8, 0.65, 0.0)], [0, 0.3, 1.0])}))
	wheel.add_child(particles({"mesh": _chip_mesh(Color(0.42, 0.68, 0.3)), "local": true, "amount": 12,
		"lifetime": 0.9, "size": [0.8, 1.4], "ring": [radius * 0.25], "direction": Vector3.UP, "spread": 6.0,
		"speed": [2.0, 4.0], "radial": [1.0, 2.5], "spin": [-300, 300],
		"size_curve": curve([Vector2(0, 0), Vector2(0.15, 1), Vector2(0.85, 1), Vector2(1, 0)])}))
	root.scale = Vector3(0.4, 0.2, 0.4)
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "scale", Vector3(1.3, 1.4, 1.3), 0.4)
	tw.parallel().tween_property(root, "position:y", at.y + 1.0, 0.4)
	tw.tween_property(root, "scale", Vector3(0.05, 1.6, 0.05), 0.2).set_ease(Tween.EASE_IN)


## A stone spike bursting out of the ground and sinking again.
static func _spike(parent: Node, at: Vector3, color: Color, height: float) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.35 * height
	cone.height = height
	cone.radial_segments = 5
	cone.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	var m := Toon.flat(color, 1.0)
	m.next_pass = Toon.outline(0.02)
	mi.material_override = m
	if _spawn(parent, mi, at - Vector3.UP * height, 1.1) == null:
		return
	mi.rotation = Vector3(randf_range(-0.35, 0.35), randf() * TAU, randf_range(-0.35, 0.35))
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position:y", at.y + height * 0.4, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.6)
	tw.tween_property(mi, "global_position:y", at.y - height, 0.3).set_ease(Tween.EASE_IN)


## A buff: a shimmering shell and rising motes in the nature's colour, for
## `duration` seconds. Add it to the body it wraps.
static func aura(element: int, duration: float) -> Node3D:
	var color := Element.color(element)
	var root := Node3D.new()
	root.name = "Aura"
	var shell := sphere(0.55, energy_material(color, 2.2, 0.0, 2.0))
	shell.scale = Vector3(1.0, 1.9, 1.0)
	shell.position.y = 1.0
	root.add_child(shell)
	var rise := {"texture": &"glow", "amount": 30, "lifetime": 0.9, "size": [0.14, 0.3],
		"ring": [0.5], "speed": [0.8, 1.6], "direction": Vector3.UP, "spread": 10.0,
		"colors": gradient([Color(color.lightened(0.5), 0.0), Color(color.lightened(0.3), 0.9), Color(color, 0.0)], [0, 0.2, 1.0])}
	match element:
		Element.FIRE:
			rise = {"texture": &"flame", "atlas": true, "amount": 36, "lifetime": 0.6, "size": [0.45, 0.8],
				"ring": [0.45], "speed": [1.0, 2.0], "direction": Vector3.UP, "spread": 10.0,
				"colors": gradient([Color(1, 0.9, 0.6, 0.0), Color(1, 0.5, 0.1, 0.8), Color(0.7, 0.1, 0.02, 0.0)], [0, 0.3, 1.0])}
		Element.LIGHTNING:
			var arcs := ArcCluster.new(0.7, 1.6)
			arcs.count = 4
			arcs.width = 0.05
			root.add_child(arcs)
		Element.EARTH:
			rise = {"texture": &"smoke", "atlas": true, "additive": false, "amount": 18, "lifetime": 1.0,
				"size": [0.45, 0.75], "ring": [0.5], "speed": [0.3, 0.7], "direction": Vector3.UP, "spread": 20.0,
				"colors": gradient([Color(0.6, 0.5, 0.36, 0.0), Color(0.6, 0.5, 0.36, 0.65), Color(0.6, 0.5, 0.36, 0.0)], [0, 0.3, 1.0])}
			var plates := particles({"mesh": _chip_mesh(color.darkened(0.2)), "amount": 10, "lifetime": 1.2,
				"size": [0.8, 1.2], "ring": [0.55], "speed": [0.0, 0.1], "orbit": [0.25, 0.4], "spin": [-40, 40],
				"size_curve": curve([Vector2(0, 0), Vector2(0.2, 1), Vector2(0.8, 1), Vector2(1, 0)])})
			plates.position.y = 1.0
			root.add_child(plates)
	var p := particles(rise)
	root.add_child(p)
	root.tree_entered.connect(func() -> void:
		var tw := root.create_tween()
		tw.tween_interval(maxf(duration - 0.4, 0.1))
		tw.tween_callback(func() -> void: p.emitting = false)
		tw.tween_property(shell, "scale", Vector3(0.01, 0.01, 0.01), 0.4).set_ease(Tween.EASE_IN)
		tw.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root


## A boss's standing aura: a tall shimmering shell, flames of its colour
## licking upward and a glow on the ground. Follows the boss.
static func boss_aura(color: Color, size := 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "BossAura"
	var shell := sphere(0.6 * size, energy_material(Color(color, 1.0), 1.2, 0.05, 2.4))
	shell.scale = Vector3(1.0, 1.85, 1.0)
	shell.position.y = 1.0 * size
	root.add_child(shell)
	root.add_child(particles({"texture": &"flame", "atlas": true, "amount": 36, "lifetime": 0.8,
		"size": [0.5 * size, 0.9 * size], "ring": [0.55 * size], "speed": [1.2, 2.4], "direction": Vector3.UP,
		"spread": 10.0, "colors": gradient([Color(color.lightened(0.5), 0.0), Color(color, 0.75), Color(color.darkened(0.4), 0.0)], [0, 0.25, 1.0])}))
	root.add_child(particles({"texture": &"smoke", "atlas": true, "additive": false, "amount": 10, "lifetime": 1.4,
		"size": [0.7 * size, 1.2 * size], "ring": [0.6 * size], "speed": [0.4, 0.9], "direction": Vector3.UP, "spread": 15.0,
		"colors": gradient([Color(0.1, 0.08, 0.12, 0.0), Color(0.1, 0.08, 0.12, 0.4), Color(0.1, 0.08, 0.12, 0.0)], [0, 0.3, 1.0])}))
	var l := light(color, 6.0 * size, 1.8)
	l.position.y = 1.2 * size
	root.add_child(l)
	return root


## Healing: a green glow, a ring and motes floating up round the body.
static func heal(parent: Node, feet: Vector3) -> void:
	var green := Color(0.45, 1.0, 0.55)
	shockwave(parent, feet, green, 2.0, 0.6)
	flash(parent, feet + Vector3.UP, Color(0.7, 1.0, 0.75), 2.0, 0.35, &"glow")
	burst_particles(parent, feet, {"texture": &"glow", "amount": 50, "lifetime": 1.2, "size": [0.18, 0.35],
		"ring": [0.6], "speed": [1.0, 2.5], "direction": Vector3.UP, "spread": 12.0, "damping": 0.5,
		"explosiveness": 0.6, "colors": gradient([Color(0.8, 1, 0.8, 0.0), Color(0.6, 1, 0.65, 1.0), Color(0.4, 1, 0.5, 0.0)], [0, 0.2, 1.0])})
	burst_particles(parent, feet + Vector3.UP, {"texture": &"star", "amount": 6, "lifetime": 0.9,
		"size": [0.3, 0.5], "radius": 0.6, "speed": [0.3, 0.8], "direction": Vector3.UP, "spread": 30.0,
		"colors": gradient([Color(1, 1, 1, 0.0), Color(0.8, 1, 0.8, 1.0), Color(0.6, 1, 0.6, 0.0)], [0, 0.3, 1.0])})


## Chakra gathering while you charge: a flickering aura of pale flames
## rising round you and a glow at your feet. Toggle `emitting` on the
## returned node's particles; free it when charging ends.
static func charge_aura(color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "ChargeAura"
	root.add_child(particles({"texture": &"flame", "atlas": true, "amount": 60, "lifetime": 0.7,
		"size": [0.6, 1.1], "ring": [0.45], "speed": [1.8, 3.4], "direction": Vector3.UP, "spread": 8.0,
		"colors": gradient([Color(color.lightened(0.6), 0.0), Color(color.lightened(0.2), 0.85), Color(color, 0.0)], [0, 0.25, 1.0])}))
	root.add_child(particles({"texture": &"flame", "atlas": true, "additive": true, "amount": 24, "lifetime": 0.5,
		"size": [0.4, 0.7], "ring": [0.35], "speed": [1.5, 2.8], "direction": Vector3.UP, "spread": 8.0,
		"colors": gradient([Color(1, 1, 1, 0.0), Color(color.lightened(0.6), 0.6), Color(color, 0.0)], [0, 0.25, 1.0])}))
	root.add_child(particles({"texture": &"glow", "amount": 20, "lifetime": 0.8, "size": [0.05, 0.12],
		"ring": [1.2], "speed": [0.5, 1.0], "direction": Vector3.UP, "radial": [-3.0, -2.0], "spread": 10.0,
		"colors": gradient([Color(color.lightened(0.6), 0.0), Color(color.lightened(0.5), 1.0), Color(color, 0.0)], [0, 0.3, 1.0])}))
	var shell := sphere(0.55, energy_material(color, 2.0, 0.0, 2.0))
	shell.scale = Vector3(1.0, 1.9, 1.0)
	shell.position.y = 1.0
	root.add_child(shell)
	var ground := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 2.6)
	quad.orientation = PlaneMesh.FACE_Y
	ground.mesh = quad
	var gm := surface_material(tex(&"glow"), true)
	gm.albedo_color = Color(color, 0.8)
	ground.material_override = gm
	ground.position.y = 0.05
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	var l := light(color, 4.0, 1.5)
	l.position.y = 1.0
	root.add_child(l)
	return root


## The ground height under `at` (falls back to its own height).
static func _ground_y(parent: Node, at: Vector3) -> float:
	if parent == null or not parent.is_inside_tree() or not parent is Node3D:
		return at.y - 1.0 if at.y > 0.5 else at.y
	var space := (parent as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.2, at - Vector3.UP * 6.0)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else at.y


## A kunai: leaf-shaped steel blade with a centre ridge, cord-wrapped grip
## and pommel ring, pointing down -Z.
static func kunai() -> Node3D:
	# Modelled in art/blender/build_assets.py.
	var root: Node3D = KUNAI_MODEL.instantiate()
	# Oversized for readability at combat distance.
	root.scale = Vector3.ONE * 2.0
	return root
