class_name ContinentStreamer
extends Node3D
## Streams the continent's terrain around a point. The land is a quadtree of
## square chunks: 64 m ones close in, each ring out twice the size of the one
## inside it, so detail falls off with distance and a view of several
## kilometres costs a few dozen chunks. Every chunk is the same grid of
## quads (see ContinentMesh), so a bigger chunk is a coarser one.
##
## Chunks are built on worker threads (WorkerThreadPool) and added to the
## scene a few per frame. A chunk that is wanted but not built yet is
## covered by whatever coarser or finer chunk is already there, so the
## ground never has a hole while detail swaps; chunks nobody needs are freed.
## Only the finest chunks (the ones near you) carry collision; trees and
## boulders are added to the nearest few rings.

## Emitted once, after begin(), when the ground around the focus is built
## and solid.
signal near_ready

## The smallest chunk, and how many times it doubles to the whole continent.
const MIN_SIZE := 64.0
const MAX_LEVEL := 6
## A chunk splits into four while you are nearer than its size times this.
const SPLIT_FACTOR := 1.35
## Once split, a chunk stays split until you are this much further away.
const HYSTERESIS := 1.2
## Chunks further than this are dropped (metres).
const VIEW_DISTANCE := 2800.0
## Trees and boulders go on chunks up to this level (the second takes every
## other spot), and are drawn out to these distances per level.
const SCATTER_LEVEL := 2
const SCATTER_RANGE := [250.0, 400.0, 650.0]
const SCATTER_FADE := 30.0
## Chunks up to this level cast shadows.
const SHADOW_LEVEL := 1
## Workers building at once, chunks added per frame, and the most time the
## main thread spends adding them (milliseconds).
const MAX_JOBS := 3
const MAX_ADDS := 2
const ADD_BUDGET_MS := 3.0
## Seconds between looking again at which chunks are wanted.
const RESELECT_EVERY := 0.1
## The ground within this many metres of the focus must be built before the
## area counts as ready.
const READY_RADIUS := 100.0

enum State { PENDING, BUILDING, BUILT }

## The detail dial: smaller splits chunks later (coarser, cheaper).
var split_scale := 1.0
var view_distance := VIEW_DISTANCE

## Where to look from, in this node's space.
var focus := Vector3.ZERO
var material: Material

## Per level: milliseconds the worker took to build a chunk, and how many
## built since the last reset.
var build_ms: Dictionary = {}
## Milliseconds of main-thread time spent adding each chunk.
var add_ms: Array[float] = []
## Chunks ever built and freed.
var built_total := 0
var freed_total := 0

var _land: ContinentLand
var _chunks: Dictionary = {}          # Vector3i(level, ix, iz) -> Chunk
var _leaf: Dictionary = {}            # the chunks wanted
var _split: Dictionary = {}           # the quadtree nodes above them
var _cover: Dictionary = {}           # what is shown
var _sea: Dictionary = {}             # key -> bool, nodes of pure sea
var _since := 0.0
var _selected_focus := Vector3(1.0e9, 0.0, 0.0)
var _dirty := true
var _watching_ready := false
var _jobs := 0


## One chunk's life: wanted, built by a worker, added to the scene.
class Chunk extends RefCounted:
	var key := Vector3i.ZERO
	var level := 0
	var rect := Rect2()
	var state := State.PENDING
	var task := -1
	var data: Dictionary = {}
	var root: Node3D
	var priority := 0.0
	var body: StaticBody3D


func setup(land: ContinentLand, mat: Material) -> void:
	_land = land
	material = mat
	name = "Terrain"
	ContinentScatter.warm()


## The square a quadtree key covers (x, z).
static func rect_of(key: Vector3i) -> Rect2:
	var size := MIN_SIZE * pow(2.0, key.x)
	return Rect2(-ContinentLand.HALF + key.y * size, -ContinentLand.HALF + key.z * size, size, size)


## Starts watching the area round `at`: near_ready fires once it is built
## and solid, and until then chunks are added as fast as they arrive.
func begin(at: Vector3) -> void:
	focus = at
	_watching_ready = true
	_reselect()


func _process(delta: float) -> void:
	if _land == null:
		return
	_since += delta
	var moved := Vector2(focus.x - _selected_focus.x, focus.z - _selected_focus.z).length()
	if _dirty or (_since >= RESELECT_EVERY and moved > 2.0) or _since >= RESELECT_EVERY * 5.0:
		_reselect()
	_integrate()
	_launch()
	if _watching_ready and is_ready(Vector2(focus.x, focus.z), READY_RADIUS):
		_watching_ready = false
		near_ready.emit()


func _exit_tree() -> void:
	for chunk: Chunk in _chunks.values():
		if chunk.state == State.BUILDING:
			WorkerThreadPool.wait_for_task_completion(chunk.task)


# --- What is wanted ------------------------------------------------------------------

func _reselect() -> void:
	_since = 0.0
	_dirty = false
	_selected_focus = focus
	var above := maxf(focus.y - _land.height_at(focus.x, focus.z), 0.0)
	_leaf.clear()
	_split.clear()
	_select(Vector3i(MAX_LEVEL, 0, 0), Vector2(focus.x, focus.z), above)
	for key: Vector3i in _leaf:
		if not _chunks.has(key):
			var chunk := Chunk.new()
			chunk.key = key
			chunk.level = key.x
			chunk.rect = rect_of(key)
			_chunks[key] = chunk
	for chunk: Chunk in _chunks.values():
		chunk.priority = _distance(chunk.rect, Vector2(focus.x, focus.z), 0.0) + chunk.level * 40.0
	_cover.clear()
	var shown: Variant = _covering(Vector3i(MAX_LEVEL, 0, 0))
	if shown != null:
		for key: Vector3i in shown:
			_cover[key] = true
	# Free what is neither shown nor wanted; show what is shown.
	for key: Vector3i in _chunks.keys():
		var chunk: Chunk = _chunks[key]
		if chunk.state == State.BUILDING:
			continue
		if not _cover.has(key) and not _leaf.has(key):
			_free_chunk(chunk)
			_chunks.erase(key)
		elif chunk.root != null:
			chunk.root.visible = _cover.has(key)


func _select(key: Vector3i, p: Vector2, above: float) -> void:
	var rect := rect_of(key)
	var dist := _distance(rect, p, above)
	if dist > view_distance or _is_sea(key):
		return
	var factor := SPLIT_FACTOR * split_scale * (HYSTERESIS if _has_children(key) else 1.0)
	if key.x > 0 and dist < rect.size.x * factor:
		_split[key] = true
		for child in _children(key):
			_select(child, p, above)
	else:
		_leaf[key] = true


static func _distance(rect: Rect2, p: Vector2, above: float) -> float:
	var dx := maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), 0.0)
	var dz := maxf(maxf(rect.position.y - p.y, p.y - rect.end.y), 0.0)
	return sqrt(dx * dx + dz * dz + above * above)


static func _children(key: Vector3i) -> Array[Vector3i]:
	var l := key.x - 1
	return [Vector3i(l, key.y * 2, key.z * 2), Vector3i(l, key.y * 2 + 1, key.z * 2),
		Vector3i(l, key.y * 2, key.z * 2 + 1), Vector3i(l, key.y * 2 + 1, key.z * 2 + 1)]


func _has_children(key: Vector3i) -> bool:
	if key.x == 0:
		return false
	for child in _children(key):
		if _chunks.has(child) or _split.has(child):
			return true
	return false


func _is_sea(key: Vector3i) -> bool:
	if not _sea.has(key):
		_sea[key] = _land.is_open_sea(rect_of(key))
	return _sea[key]


## The chunks to show under `key`: an array of keys, or null when it can't be
## covered yet (the caller falls back to something coarser).
func _covering(key: Vector3i) -> Variant:
	var chunk: Chunk = _chunks.get(key)
	var built := chunk != null and chunk.state == State.BUILT
	if _leaf.has(key):
		return [key] if built else _built_below(key)
	if _split.has(key):
		var out: Array[Vector3i] = []
		for child in _children(key):
			if not _split.has(child) and not _leaf.has(child):
				continue
			var part: Variant = _covering(child)
			if part == null:
				return [key] if built else null
			out.append_array(part)
		return out
	return []


## Chunks already built beneath `key` that together fill it, or null.
func _built_below(key: Vector3i) -> Variant:
	var chunk: Chunk = _chunks.get(key)
	if chunk != null and chunk.state == State.BUILT:
		return [key]
	if key.x == 0:
		return null
	var out: Array[Vector3i] = []
	for child in _children(key):
		if _is_sea(child):
			continue
		var part: Variant = _built_below(child)
		if part == null:
			return null
		out.append_array(part)
	return out


# --- Building ------------------------------------------------------------------------------

func _launch() -> void:
	if _jobs >= MAX_JOBS:
		return
	var pending: Array[Chunk] = []
	for chunk: Chunk in _chunks.values():
		if chunk.state == State.PENDING and _leaf.has(chunk.key):
			pending.append(chunk)
	if pending.is_empty():
		return
	pending.sort_custom(func(a: Chunk, b: Chunk) -> bool: return a.priority < b.priority)
	for chunk in pending:
		if _jobs >= MAX_JOBS:
			break
		chunk.state = State.BUILDING
		chunk.task = WorkerThreadPool.add_task(_work.bind(chunk), false, "continent chunk")
		_jobs += 1


## The worker: terrain mesh, collision heights and scatter for a chunk.
func _work(chunk: Chunk) -> void:
	var t0 := Time.get_ticks_usec()
	var data := ContinentMesh.build(_land, chunk.rect)
	var step := chunk.rect.size.x / ContinentMesh.QUADS
	if chunk.level == 0:
		# Height maps are scaled uniformly, so the shape holds heights in steps.
		var h: PackedFloat32Array = data["heights"]
		var scaled := PackedFloat32Array()
		scaled.resize(h.size())
		for k in h.size():
			scaled[k] = h[k] / step
		data["collision"] = scaled
	data.erase("heights")
	data["scatter"] = [] as Array[Dictionary]
	if chunk.level <= SCATTER_LEVEL:
		var found := ContinentScatter.instances(_land, chunk.rect, 1 if chunk.level < SCATTER_LEVEL else 2)
		data["scatter"] = ContinentScatter.multimeshes(found, chunk.rect.get_center())
	data["total_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	chunk.data = data


## Adds finished chunks to the scene, nearest first, within the frame's
## budget (all of them while waiting to be ready).
func _integrate() -> void:
	var finished: Array[Chunk] = []
	for chunk: Chunk in _chunks.values():
		if chunk.state == State.BUILDING and WorkerThreadPool.is_task_completed(chunk.task):
			finished.append(chunk)
	if finished.is_empty():
		return
	finished.sort_custom(func(a: Chunk, b: Chunk) -> bool: return a.priority < b.priority)
	var start := Time.get_ticks_usec()
	var added := 0
	for chunk in finished:
		if not _watching_ready and (added >= MAX_ADDS or (Time.get_ticks_usec() - start) / 1000.0 > ADD_BUDGET_MS):
			break
		WorkerThreadPool.wait_for_task_completion(chunk.task)
		_jobs -= 1
		if not _leaf.has(chunk.key) and not _cover.has(chunk.key):
			# Nobody wants it any more.
			_chunks.erase(chunk.key)
			continue
		var t0 := Time.get_ticks_usec()
		_add_chunk(chunk)
		add_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		var times: Array = build_ms.get(chunk.level, [])
		times.append(float(chunk.data["total_ms"]))
		build_ms[chunk.level] = times
		added += 1
		built_total += 1
	_dirty = true


func _add_chunk(chunk: Chunk) -> void:
	var data := chunk.data
	var root := Node3D.new()
	root.name = "Chunk_%d_%d_%d" % [chunk.key.x, chunk.key.y, chunk.key.z]
	var centre := chunk.rect.get_center()
	root.position = Vector3(centre.x, 0.0, centre.y)
	var mi := MeshInstance3D.new()
	mi.name = "Land"
	mi.mesh = data["mesh"]
	mi.material_override = material
	if chunk.level > SHADOW_LEVEL:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if data.has("collision"):
		var shape := HeightMapShape3D.new()
		shape.map_width = ContinentMesh.QUADS + 1
		shape.map_depth = ContinentMesh.QUADS + 1
		shape.map_data = data["collision"]
		var col := CollisionShape3D.new()
		col.shape = shape
		col.scale = Vector3.ONE * (chunk.rect.size.x / ContinentMesh.QUADS)
		var body := StaticBody3D.new()
		body.name = "Ground"
		body.collision_layer = Combat.LAYER_WORLD
		body.collision_mask = 0
		body.add_child(col)
		root.add_child(body)
		chunk.body = body
	for entry: Dictionary in data["scatter"]:
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Scatter_" + String(entry["model"])
		mmi.multimesh = entry["multimesh"]
		mmi.visibility_range_end = scatter_range(chunk.level, String(entry["model"]))
		mmi.visibility_range_end_margin = SCATTER_FADE
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mmi)
	chunk.root = root
	chunk.state = State.BUILT
	root.visible = false
	add_child(root)


func _free_chunk(chunk: Chunk) -> void:
	if chunk.root != null:
		chunk.root.queue_free()
		freed_total += 1


# --- Questions ---------------------------------------------------------------------------

## The ground within `radius` of `p` (x, z) is all built, and the finest
## chunks among it solid.
func is_ready(p: Vector2, radius: float) -> bool:
	var any := false
	for key: Vector3i in _leaf:
		var chunk: Chunk = _chunks.get(key)
		if _distance(rect_of(key), p, 0.0) > radius:
			continue
		any = true
		if chunk == null or chunk.state != State.BUILT:
			return false
	return any


## Every wanted chunk is built.
func is_complete() -> bool:
	if _leaf.is_empty():
		return false
	for key: Vector3i in _leaf:
		var chunk: Chunk = _chunks.get(key)
		if chunk == null or chunk.state != State.BUILT:
			return false
	return true


## Chunks built and in the scene, per level.
func counts() -> Dictionary:
	var out := {}
	for chunk: Chunk in _chunks.values():
		if chunk.state == State.BUILT:
			out[chunk.level] = int(out.get(chunk.level, 0)) + 1
	return out


## How far a scatter model is drawn on a chunk of this level (metres).
static func scatter_range(level: int, model: String) -> float:
	return float(SCATTER_RANGE[level]) * float(ContinentScatter.RANGE_SCALE.get(model, 1.0))


## What is in the scene: chunks, collision bodies, and what the camera at the
## focus draws: scatter instances and triangles within their visibility
## range (all counts are of whole chunks), plus everything loaded.
func stats() -> Dictionary:
	var shown := 0
	var bodies := 0
	var loaded_instances := 0
	var instances := 0
	var draws := 0
	var land_triangles := 0
	var scatter_triangles := 0
	var tri_per_chunk := (ContinentMesh.QUADS * ContinentMesh.QUADS * 2 + ContinentMesh.QUADS * 4 * 2)
	var at := Vector2(focus.x, focus.z)
	for chunk: Chunk in _chunks.values():
		if chunk.state != State.BUILT:
			continue
		if chunk.body != null:
			bodies += 1
		if not chunk.root.visible:
			continue
		shown += 1
		draws += 1
		land_triangles += tri_per_chunk
		var near := _distance(chunk.rect, at, 0.0)
		for entry: Dictionary in chunk.data["scatter"]:
			loaded_instances += int(entry["count"])
			if near > scatter_range(chunk.level, String(entry["model"])):
				continue
			instances += int(entry["count"])
			var mesh := (entry["multimesh"] as MultiMesh).mesh
			draws += mesh.get_surface_count()
			for part in mesh.get_surface_count():
				scatter_triangles += int(entry["count"]) * mesh.surface_get_array_index_len(part) / 3
	return {"chunks": _chunks.size(), "shown": shown, "bodies": bodies, "instances": instances,
		"loaded_instances": loaded_instances, "draw_calls": draws, "land_triangles": land_triangles,
		"scatter_triangles": scatter_triangles, "levels": counts(),
		"pending": _leaf.size() - _built_leaves(), "jobs": _jobs}


func _built_leaves() -> int:
	var n := 0
	for key: Vector3i in _leaf:
		var chunk: Chunk = _chunks.get(key)
		if chunk != null and chunk.state == State.BUILT:
			n += 1
	return n


## A chunk of this quadtree key is built and in the scene.
func has_chunk(key: Vector3i) -> bool:
	var chunk: Chunk = _chunks.get(key)
	return chunk != null and chunk.state == State.BUILT


## The squares of land being drawn now (x, z).
func shown_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for key: Vector3i in _cover:
		out.append(rect_of(key))
	return out


## The squares of land that have collision (x, z).
func body_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for chunk: Chunk in _chunks.values():
		if chunk.body != null:
			out.append(chunk.rect)
	return out


## The solid ground chunk under (x, z), if built: its body.
func body_under(x: float, z: float) -> StaticBody3D:
	for chunk: Chunk in _chunks.values():
		if chunk.body != null and chunk.rect.has_point(Vector2(x, z)):
			return chunk.body
	return null
