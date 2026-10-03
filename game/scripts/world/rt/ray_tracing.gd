class_name RayTracing
extends Node
## Turns on RayTracedLighting when the GPU can do it and the player wants
## it, and keeps its picture of the level current: every shadow-casting mesh
## (props, terrain, scattered trees) goes in as-is, and characters, whose
## skinned meshes change shape every frame, go in as capsules that follow
## them. Also tells it where the sun is, for lighting reflections.

const CAPSULE := &"character_capsule"
## What a character looks like in a reflection that falls off screen.
const CAPSULE_COLOR := Color(0.2, 0.19, 0.22)
## Milliseconds per frame spent preparing new meshes (a new island has many).
const PREP_BUDGET_MS := 8

var effect: RayTracedLighting

var _env: WorldEnvironment
var _level: Node
var _ssao_default := true
## [key, node, multimesh index or -1] for each thing to trace.
var _tracked: Array = []
var _sent: Dictionary = {}
var _rescan := 0.0


func _init(level: Node, env: WorldEnvironment) -> void:
	name = "RayTracing"
	_level = level
	_env = env
	if env and env.environment:
		_ssao_default = env.environment.ssao_enabled


func _ready() -> void:
	# After everything has moved, so capsules match this frame's characters.
	process_priority = 1000
	Settings.value_changed.connect(func(key: StringName, _v: Variant) -> void:
		if key == &"ray_tracing":
			_apply())
	_apply()


static func available() -> bool:
	return RayTracedLighting.supported()


func active() -> bool:
	return effect != null and not effect.failed


func _apply() -> void:
	var on := bool(Settings.get_value(&"ray_tracing")) and available()
	if on and effect == null:
		effect = RayTracedLighting.new()
		# `-- --rt-debug` shows the traced occlusion itself.
		effect.debug_view = OS.get_cmdline_user_args().has("--rt-debug")
		var comp := Compositor.new()
		comp.compositor_effects = [effect]
		_env.compositor = comp
		# The traced occlusion replaces the screen-space kind.
		_env.environment.ssao_enabled = false
		_env.environment.set_meta(&"rt_active", true)
		_sent.clear()
		_rescan = 0.0
	elif not on and effect != null:
		_env.compositor = null
		_env.environment.remove_meta(&"rt_active")
		_env.environment.ssao_enabled = _ssao_default and bool(Settings.get_value(&"ambient_occlusion"))
		effect = null
		_tracked.clear()
		_sent.clear()


func _process(delta: float) -> void:
	if effect == null:
		return
	if effect.failed:
		_env.compositor = null
		_env.environment.remove_meta(&"rt_active")
		_env.environment.ssao_enabled = _ssao_default and bool(Settings.get_value(&"ambient_occlusion"))
		effect = null
		return
	_rescan -= delta
	if _rescan <= 0.0:
		_rescan = 0.5
		if not _scan():
			_rescan = 0.0  # more meshes to prepare next frame
	_light()
	var instances := []
	for t: Array in _tracked:
		# Freed since the last scan (an island swapped out).
		if not is_instance_valid(t[1]):
			continue
		var node: Node3D = t[1]
		if not node.is_inside_tree() or not node.is_visible_in_tree():
			continue
		match t[2]:
			-1:
				instances.append([t[0], node.global_transform])
			-2:
				instances.append([t[0], Transform3D(Basis.IDENTITY, node.global_position + Vector3(0, 0.9, 0))])
			_:
				var mmi := node as MultiMeshInstance3D
				instances.append([t[0], mmi.global_transform * mmi.multimesh.get_instance_transform(t[2])])
	effect.set_instances(instances)


## Sun and ambient light for reflections that fall off screen.
func _light() -> void:
	var sun: DirectionalLight3D = null
	for n in _level.find_children("*", "DirectionalLight3D", true, false):
		if (n as DirectionalLight3D).is_visible_in_tree():
			sun = n
			break
	if sun:
		effect.sun_dir = sun.global_transform.basis.z
		effect.sun_color = sun.light_color.srgb_to_linear() * sun.light_energy
	else:
		effect.sun_color = Color.BLACK
	var env := _env.environment
	effect.ambient = env.ambient_light_color.srgb_to_linear() * env.ambient_light_energy
	var island: Variant = _level.get("island")
	effect.water_level = (island as Island).water_level if is_instance_valid(island) and island is Island else NAN


## Picks up meshes that came and went. False if it ran out of time before
## preparing every new one.
func _scan() -> bool:
	_tracked = collect(_level)
	var keys := {}
	var start := Time.get_ticks_msec()
	var done := true
	for t: Array in _tracked:
		keys[t[0]] = true
		if _sent.has(t[0]):
			continue
		if Time.get_ticks_msec() - start > PREP_BUDGET_MS:
			done = false
			continue
		_sent[t[0]] = true
		if t[2] == -2:
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.27
			capsule.height = 1.7
			capsule.radial_segments = 12
			capsule.rings = 4
			var tri := triangles(capsule, CAPSULE_COLOR)
			effect.add_mesh(CAPSULE, tri[0], tri[1], tri[2], true)
		else:
			var mesh := (t[1] as MultiMeshInstance3D).multimesh.mesh if t[1] is MultiMeshInstance3D else (t[1] as MeshInstance3D).mesh
			var tri := triangles(mesh)
			effect.add_mesh(t[0], tri[0], tri[1], tri[2])
	for key: Variant in _sent.keys():
		if not keys.has(key):
			_sent.erase(key)
			effect.remove_mesh(key)
	return done


## What to trace under `root`: [key, node, -1 (mesh), -2 (character capsule)
## or a multimesh instance index]. Keys identify the mesh, so copies share
## one acceleration structure.
static func collect(root: Node) -> Array:
	var out := []
	for n: Node in root.find_children("*", "", true, false):
		if n is CharacterBody3D or n is StoryNpc:
			out.append([CAPSULE, n, -2])
			continue
		if not n is GeometryInstance3D:
			continue
		var g := n as GeometryInstance3D
		if g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or _in_character(g, root):
			continue
		if g is MeshInstance3D:
			var mi := g as MeshInstance3D
			if mi.mesh != null and mi.skin == null:
				out.append([mi.mesh.get_rid(), mi, -1])
		elif g is MultiMeshInstance3D:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm != null and mm.mesh != null:
				for i in mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count:
					out.append([mm.mesh.get_rid(), g, i])
	return out


static func _in_character(n: Node, root: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != root:
		if p is CharacterBody3D or p is StoryNpc:
			return true
		p = p.get_parent()
	return false


## A mesh's triangles as [vertices, indices, records], every surface merged.
## Records are 16 bytes a triangle: its object-space normal (3 floats) and
## its colour (RGBA8, sRGB), for lighting reflections.
static func triangles(mesh: Mesh, color: Variant = null) -> Array:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var recs := PackedByteArray()
	for s in mesh.get_surface_count():
		# Primitive meshes (boxes, capsules...) are always triangles.
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var ind: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if ind.is_empty():
			for i in v.size() - v.size() % 3:
				ind.append(i)
		var base := verts.size()
		verts.append_array(v)
		if base == 0:
			idx.append_array(ind)
		else:
			for i: int in ind:
				idx.append(base + i)

		var mat := mesh.surface_get_material(s)
		var flat: Color = color if color is Color else surface_color(mat)
		var vcol: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		# Terrain: vertex colours are layer weights over the material's palette.
		var palette: PackedColorArray = mat.get_meta(&"rt_palette") if mat and mat.has_meta(&"rt_palette") else PackedColorArray()
		var tint := not vcol.is_empty() and mat is BaseMaterial3D and (mat as BaseMaterial3D).vertex_color_use_as_albedo
		var count := ind.size() / 3
		var o := recs.size()
		recs.resize(o + count * 16)
		for k in count:
			var i0 := ind[k * 3]
			var i1 := ind[k * 3 + 1]
			var i2 := ind[k * 3 + 2]
			var nrm := (v[i2] - v[i0]).cross(v[i1] - v[i0])
			nrm = nrm.normalized() if nrm.length_squared() > 1e-12 else Vector3.UP
			var c := flat
			if palette.size() >= 4 and not vcol.is_empty():
				var w := vcol[i0] + vcol[i1] + vcol[i2]
				var total := maxf(w.r + w.g + w.b + w.a, 1e-4)
				c = (palette[0] * w.r + palette[1] * w.g + palette[2] * w.b + palette[3] * w.a) / total
			elif tint:
				c = flat * ((vcol[i0] + vcol[i1] + vcol[i2]) / 3.0)
			recs.encode_float(o, nrm.x)
			recs.encode_float(o + 4, nrm.y)
			recs.encode_float(o + 8, nrm.z)
			recs.encode_u32(o + 12, c.to_abgr32())
			o += 16
	return [verts, idx, recs]


static var _texture_means: Dictionary = {}


## A surface's average colour (sRGB): its albedo times its texture's average.
static func surface_color(mat: Material) -> Color:
	if mat == null:
		return Color(0.5, 0.5, 0.5)
	if mat.has_meta(&"rt_color"):
		return mat.get_meta(&"rt_color")
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		var c := bm.albedo_color
		if bm.albedo_texture:
			c *= texture_mean(bm.albedo_texture)
		return c
	return Color(0.5, 0.5, 0.5)


## A texture's average colour (cached).
static func texture_mean(tex: Texture2D) -> Color:
	var key := tex.get_rid()
	if not _texture_means.has(key):
		var img := tex.get_image()
		var mean := Color(0.5, 0.5, 0.5)
		if img != null:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			img.clear_mipmaps()
			# Halving step by step averages every pixel.
			while img.get_width() > 1 or img.get_height() > 1:
				img.resize(maxi(img.get_width() / 2, 1), maxi(img.get_height() / 2, 1), Image.INTERPOLATE_BILINEAR)
			mean = img.get_pixel(0, 0)
		_texture_means[key] = mean
	return _texture_means[key]
