class_name RayTracedLighting
extends CompositorEffect
## Hardware ray tracing on top of the finished frame, against a Vulkan
## acceleration structure of the level (RayTracing gathers the meshes):
##
## - Ambient occlusion: every pixel fires a few short rays and darkens by how
##   much nearby geometry they hit (contact shadows under characters, props
##   sitting in the ground). A depth-aware blur removes the noise.
## - Reflections: glossy pixels (the sea, polished steel) fire a mirror ray.
##   A hit that is on screen reuses the rendered pixel; one that isn't is lit
##   from its triangle's colour and normal, with a second ray for the sun's
##   shadow. Blended in by Fresnel, so water at a grazing angle mirrors the
##   island and water seen from above stays water.
##
## Runs as a ray tracing pipeline (raygen, miss and closest-hit shaders), so
## it needs a GPU with hardware ray tracing (NVIDIA RTX, AMD RX 6000+, Intel
## Arc), Vulkan and the Forward+ renderer; `supported()` checks.

## Metres an occlusion ray looks for something to be occluded by.
var radius := 1.8
## How dark full occlusion gets (0 = off, 1 = black).
var strength := 0.75
var rays_per_pixel := 4
## Beyond this distance from the camera occlusion fades out.
var max_distance := 90.0
## 0 turns reflections off.
var reflections := 1.0
## Show the occlusion itself instead of the shaded scene (for tuning).
var debug_view := false

## Sun direction (towards the sun), colour × energy, and ambient colour ×
## energy, in linear light: how off-screen reflection hits are lit.
var sun_dir := Vector3(0.3, 0.8, 0.4)
var sun_color := Color(1, 1, 1)
var ambient := Color(0.3, 0.3, 0.35)
## Sea level (the sea is transparent, so it's found by height, not in the
## depth buffer); NAN when there's no sea.
var water_level := NAN

## Set when the device refused something (the effect then does nothing).
var failed := false

var _rd: RenderingDevice
var _ready_gpu := false
var _rt_shader: RID
var _rt_pipeline: RID
var _hit_sbt: RID
var _hit_range := 0
var _apply_shader: RID
var _apply_pipeline: RID
var _sampler: RID
var _params: RID
var _ao: RID
var _refl: RID
var _size := Vector2i.ZERO
var _tlas: RID
var _tlas_capacity := 0
## key -> {blas, vertices, indices, one_sided, tris (PackedByteArray), offset}
var _blas: Dictionary = {}
## Every mesh's per-triangle records (normal + colour) back to back; each
## instance finds its own from its id.
var _tri_buffer: RID
var _tris_dirty := true
var _frame := 0

var _mutex := Mutex.new()
var _pending_meshes: Array = []
var _dropped: Array = []
var _instances: Array = []  # [key, Transform3D]


static func supported() -> bool:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return false
	var rd := RenderingServer.get_rendering_device()
	return rd != null and rd.has_feature(RenderingDevice.SUPPORTS_RAYTRACING_PIPELINE)


func _init() -> void:
	# After transparents: with MSAA the colour is only final (resolved) then.
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_normal_roughness = true
	_rd = RenderingServer.get_rendering_device()
	RenderingServer.call_on_render_thread(_init_gpu)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd:
		# The TLAS first (it points at the BLASes), each BLAS before its buffers.
		var rids: Array[RID] = [_tlas, _ao, _refl, _params, _sampler, _tri_buffer, _hit_sbt, _rt_pipeline,
			_rt_shader, _apply_pipeline, _apply_shader]
		for entry: Dictionary in _blas.values():
			rids.append_array([entry["blas"], entry["vertices"], entry["indices"]])
		for rid in rids:
			if rid.is_valid():
				_rd.free_rid(rid)


# --- Scene data (from the main thread) ------------------------------------------

## Queues a mesh for its own acceleration structure. `tris`: 16 bytes per
## triangle (object-space normal as 3 floats, then its colour as RGBA8).
## `one_sided`: rays starting inside it pass out through its back faces (the
## capsules that stand in for characters, whose skin lies inside them).
func add_mesh(key: Variant, vertices: PackedVector3Array, indices: PackedInt32Array, tris: PackedByteArray, one_sided := false) -> void:
	_mutex.lock()
	_pending_meshes.append([key, vertices, indices, tris, one_sided])
	_mutex.unlock()


func remove_mesh(key: Variant) -> void:
	_mutex.lock()
	_dropped.append(key)
	_mutex.unlock()


## Where every mesh is this frame: [[key, Transform3D], ...].
func set_instances(instances: Array) -> void:
	_mutex.lock()
	_instances = instances
	_mutex.unlock()


# --- GPU -----------------------------------------------------------------------

## Compiles {stage: source} into one shader.
func _compile(stages: Dictionary) -> RID:
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	for stage: RenderingDevice.ShaderStage in stages:
		src.set_stage_source(stage, stages[stage])
	var spirv := _rd.shader_compile_spirv_from_source(src)
	for stage: RenderingDevice.ShaderStage in stages:
		var err := spirv.get_stage_compile_error(stage)
		if err != "":
			push_error("Ray tracing shader (stage %d): %s" % [stage, err])
			return RID()
	return _rd.shader_create_from_spirv(spirv, "RayTracedLighting")


func _stage(shader: RID) -> RDPipelineShader:
	var ps := RDPipelineShader.new()
	ps.shader = shader
	return ps


func _init_gpu() -> void:
	if _rd == null or not _rd.has_feature(RenderingDevice.SUPPORTS_RAYTRACING_PIPELINE):
		failed = true
		return
	_rt_shader = _compile({
		RenderingDevice.SHADER_STAGE_RAYGEN: RtShaders.RAYGEN,
		RenderingDevice.SHADER_STAGE_MISS: RtShaders.MISS,
		RenderingDevice.SHADER_STAGE_CLOSEST_HIT: RtShaders.CLOSEST_HIT,
	})
	_apply_shader = _compile({RenderingDevice.SHADER_STAGE_COMPUTE: RtShaders.APPLY})
	if not _rt_shader.is_valid() or not _apply_shader.is_valid():
		failed = true
		return
	var hit := RDHitGroup.new()
	hit.closest_hit_shader = _stage(_rt_shader)
	var raygen: Array[RDPipelineShader] = [_stage(_rt_shader)]
	var miss: Array[RDPipelineShader] = [_stage(_rt_shader)]
	var hits: Array[RDHitGroup] = [hit]
	_rt_pipeline = _rd.raytracing_pipeline_create(raygen, miss, hits, 1)
	if not _rt_pipeline.is_valid():
		failed = true
		return
	# Every instance uses the one hit group.
	_hit_sbt = _rd.hit_sbt_create(_rt_pipeline, 1)
	_hit_range = _rd.hit_sbt_range_alloc(_hit_sbt, 1)
	_rd.hit_sbt_range_update(_hit_sbt, _hit_range, 0, PackedInt32Array([0]))
	_apply_pipeline = _rd.compute_pipeline_create(_apply_shader)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_sampler = _rd.sampler_create(ss)
	_params = _rd.uniform_buffer_create(PARAMS_SIZE)
	_ready_gpu = true


func _free_blas(entry: Dictionary) -> void:
	for k in ["blas", "vertices", "indices"]:
		var rid: RID = entry.get(k, RID())
		if rid.is_valid():
			_rd.free_rid(rid)


func _build_blas(key: Variant, vertices: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	if vertices.is_empty() or indices.size() < 3:
		return {}
	var bits := RenderingDevice.BUFFER_CREATION_DEVICE_ADDRESS_BIT \
		| RenderingDevice.BUFFER_CREATION_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT
	var vdata := vertices.to_byte_array()
	var idata := indices.to_byte_array()
	var entry := {}
	entry["vertices"] = _rd.vertex_buffer_create(vdata.size(), vdata, bits)
	entry["indices"] = _rd.index_buffer_create(indices.size(), RenderingDevice.INDEX_BUFFER_FORMAT_UINT32, idata, false, bits)
	var geo := RDAccelerationStructureGeometry.new()
	geo.vertex_buffer = entry["vertices"]
	geo.vertex_count = vertices.size()
	geo.vertex_stride = 12
	geo.vertex_format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	geo.index_buffer = entry["indices"]
	geo.index_count = indices.size()
	geo.flags = RenderingDevice.ACCELERATION_STRUCTURE_GEOMETRY_OPAQUE_BIT
	entry["blas"] = _rd.blas_create([geo], RenderingDevice.ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT)
	if not (entry["blas"] as RID).is_valid() or _rd.blas_build(entry["blas"]) != OK:
		_free_blas(entry)
		return {}
	return entry


## Brings the acceleration structures up to date. False if there is nothing to trace.
func _sync_scene() -> bool:
	_mutex.lock()
	var pending := _pending_meshes
	var dropped := _dropped
	var instances := _instances
	_pending_meshes = []
	_dropped = []
	_mutex.unlock()
	for key: Variant in dropped:
		if _blas.has(key):
			_free_blas(_blas[key])
			_blas.erase(key)
			_tris_dirty = true
	for m: Array in pending:
		if _blas.has(m[0]):
			_free_blas(_blas[m[0]])
			_blas.erase(m[0])
		var entry := _build_blas(m[0], m[1], m[2])
		if not entry.is_empty():
			entry["tris"] = m[3]
			entry["one_sided"] = m[4]
			_blas[m[0]] = entry
		_tris_dirty = true
	if _tris_dirty:
		_rebuild_triangles()

	var list: Array[RDAccelerationStructureInstance] = []
	for inst: Array in instances:
		var entry: Dictionary = _blas.get(inst[0], {})
		if entry.is_empty():
			continue
		var i := RDAccelerationStructureInstance.new()
		i.blas = entry["blas"]
		i.transform = inst[1]
		i.id = entry["offset"]
		i.hit_sbt_range = _hit_range
		i.flags = RenderingDevice.ACCELERATION_STRUCTURE_INSTANCE_FORCE_OPAQUE_BIT
		if entry["one_sided"]:
			# Godot winds front faces clockwise, the opposite of ray tracing's default.
			i.flags |= RenderingDevice.ACCELERATION_STRUCTURE_INSTANCE_TRIANGLE_FLIP_FACING_BIT
		else:
			i.flags |= RenderingDevice.ACCELERATION_STRUCTURE_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT
		list.append(i)
	if list.is_empty() or not _tri_buffer.is_valid():
		return false
	if list.size() > _tlas_capacity:
		if _tlas.is_valid():
			_rd.free_rid(_tlas)
		_tlas_capacity = maxi(64, nearest_po2(list.size()))
		_tlas = _rd.tlas_create(_tlas_capacity, RenderingDevice.ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT)
	return _tlas.is_valid() and _rd.tlas_build(_tlas, list) == OK


func _rebuild_triangles() -> void:
	_tris_dirty = false
	var all := PackedByteArray()
	for entry: Dictionary in _blas.values():
		entry["offset"] = all.size() / 16
		all.append_array(entry["tris"])
	if _tri_buffer.is_valid():
		_rd.free_rid(_tri_buffer)
		_tri_buffer = RID()
	if not all.is_empty():
		_tri_buffer = _rd.storage_buffer_create(all.size(), all)


func _image(format: RenderingDevice.DataFormat, size: Vector2i) -> RID:
	var fmt := RDTextureFormat.new()
	fmt.format = format
	fmt.width = size.x
	fmt.height = size.y
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	return _rd.texture_create(fmt, RDTextureView.new())


func _render_callback(_type: int, render_data: RenderData) -> void:
	if not _ready_gpu or failed:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene := render_data.get_render_scene_data() as RenderSceneDataRD
	if buffers == null or scene == null:
		return
	var size := buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	if not _sync_scene():
		return
	if size != _size:
		for rid: RID in [_ao, _refl]:
			if rid.is_valid():
				_rd.free_rid(rid)
		_ao = _image(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, size)
		_refl = _image(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, size)
		_size = size
	_frame += 1
	var normal_roughness := buffers.get_texture(&"forward_clustered", &"normal_roughness")

	for view in buffers.get_view_count():
		# The render data's projection is already the Vulkan one (Y flipped,
		# reversed depth); correct it only if a version hands over the raw one.
		var proj := scene.get_view_projection(view)
		if proj.y.y > 0.0:
			proj = Projection.create_depth_correction(true) * proj
		var cam := scene.get_cam_transform()
		var params := _pack_params(proj, cam, size)
		_rd.buffer_update(_params, 0, params.size(), params)
		var depth := buffers.get_depth_layer(view)
		var color := buffers.get_color_layer(view)

		var trace_set := UniformSetCacheRD.get_cache(_rt_shader, 0, [
			_uniform(RenderingDevice.UNIFORM_TYPE_ACCELERATION_STRUCTURE, 0, [_tlas]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_sampler, depth]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_sampler, normal_roughness]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 3, [_ao]),
			_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 4, [_params]),
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 5, [_tri_buffer]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 6, [_refl]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 7, [_sampler, color]),
		])
		var rt := _rd.raytracing_list_begin()
		_rd.raytracing_list_bind_raytracing_pipeline(rt, _rt_pipeline)
		_rd.raytracing_list_bind_uniform_set(rt, trace_set, 0)
		_rd.raytracing_list_trace_rays(rt, 0, _hit_sbt, size.x, size.y, 1)
		_rd.raytracing_list_end()

		var apply_set := UniformSetCacheRD.get_cache(_apply_shader, 0, [
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 0, [_sampler, _ao]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 1, [color]),
			_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 2, [_params]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_sampler, _refl]),
		])
		var groups := Vector2i(ceili(size.x / 8.0), ceili(size.y / 8.0))
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _apply_pipeline)
		_rd.compute_list_bind_uniform_set(list, apply_set, 0)
		_rd.compute_list_dispatch(list, groups.x, groups.y, 1)
		_rd.compute_list_end()


func _uniform(type: RenderingDevice.UniformType, binding: int, ids: Array) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = type
	u.binding = binding
	for id: RID in ids:
		u.add_id(id)
	return u


# layout(std140) Params: mat4 inv_proj, mat4 view_proj, mat4 view_to_world,
# vec4 settings, frame, sun_dir, sun_color, ambient, water.
const PARAMS_SIZE := 64 * 3 + 16 * 6


func _pack_params(proj: Projection, cam: Transform3D, size: Vector2i) -> PackedByteArray:
	var f := PackedFloat32Array()
	var inv := proj.inverse()
	# World to clip, for finding reflected points on screen.
	var view_proj := proj * Projection(cam.affine_inverse())
	for m: Projection in [inv, view_proj]:
		for c in [m.x, m.y, m.z, m.w]:
			f.append_array([c.x, c.y, c.z, c.w])
	var b := cam.basis
	f.append_array([b.x.x, b.x.y, b.x.z, 0.0, b.y.x, b.y.y, b.y.z, 0.0, b.z.x, b.z.y, b.z.z, 0.0,
		cam.origin.x, cam.origin.y, cam.origin.z, 1.0])
	f.append_array([radius, strength, max_distance, float(rays_per_pixel)])
	f.append_array([float(size.x), float(size.y), float(_frame % 1024), 1.0 if debug_view else 0.0])
	var d := sun_dir.normalized()
	f.append_array([d.x, d.y, d.z, 0.0])
	f.append_array([sun_color.r, sun_color.g, sun_color.b, 0.0])
	f.append_array([ambient.r, ambient.g, ambient.b, reflections])
	var has_sea := not is_nan(water_level)
	f.append_array([water_level if has_sea else 0.0, 1.0 if has_sea else 0.0,
		fmod(Time.get_ticks_msec() / 1000.0, 3600.0), 0.0])
	return f.to_byte_array()
