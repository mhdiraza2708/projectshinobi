class_name ContinentMesh
extends RefCounted
## Builds one terrain chunk's mesh (and the heights its collision needs) from
## ContinentLand. Static and free of scene-tree access, so it runs on worker
## threads. Every chunk is a QUADS x QUADS grid whatever its size, so a
## bigger chunk is a coarser one, and all chunks share one index buffer.
## A skirt hangs down round each chunk's edge to hide the cracks where
## neighbours of different detail meet.

## Quads along one side of a chunk.
const QUADS := 48
## Skirt depth: this plus SKIRT_PER_STEP times the chunk's vertex spacing.
const SKIRT_BASE := 1.5
const SKIRT_PER_STEP := 0.7

static var _indices := PackedInt32Array()
static var _index_lock := Mutex.new()


## The triangles shared by every chunk: the grid, then the skirt.
static func indices() -> PackedInt32Array:
	_index_lock.lock()
	if _indices.is_empty():
		var n := QUADS + 1
		var out := PackedInt32Array()
		for j in QUADS:
			for i in QUADS:
				var a := j * n + i
				out.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
		# Skirt vertices follow the grid, edge by edge clockwise from above
		# (north, east, south, west), each QUADS + 1 of them; each hangs
		# below the grid vertex it duplicates.
		var edges := _edge_cells()
		for e in 4:
			for k in QUADS:
				var top0: int = edges[e][k]
				var top1: int = edges[e][k + 1]
				var low0 := n * n + e * n + k
				var low1 := low0 + 1
				out.append_array([top0, low0, top1, top1, low0, low1])
		_indices = out
	var result := _indices
	_index_lock.unlock()
	return result


## The grid vertex indices along each edge, clockwise from above.
static func _edge_cells() -> Array:
	var n := QUADS + 1
	var north := []
	var east := []
	var south := []
	var west := []
	for k in n:
		north.append(k)
		east.append(k * n + QUADS)
		south.append(QUADS * n + (QUADS - k))
		west.append((QUADS - k) * n)
	return [north, east, south, west]


## Builds the chunk covering `rect` (x, z): returns {mesh: ArrayMesh,
## heights: PackedFloat32Array (the grid, row by row, for collision),
## ms: float}.
static func build(land: ContinentLand, rect: Rect2) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var n := QUADS + 1
	var step := rect.size.x / QUADS
	var wide := QUADS + 3
	# Heights with a one-vertex margin, so normals match across chunk borders.
	var hs := PackedFloat32Array()
	hs.resize(wide * wide)
	for j in wide:
		var z := rect.position.y + (j - 1) * step
		for i in wide:
			hs[j * wide + i] = land.height_at(rect.position.x + (i - 1) * step, z)

	var count := n * n + 4 * n
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	# The region palette multiplier and snow ride in UV and UV2 (see terrain.gdshader).
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	verts.resize(count)
	normals.resize(count)
	colors.resize(count)
	uv.resize(count)
	uv2.resize(count)
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var half := rect.size.x * 0.5
	var paint := PackedFloat32Array()
	paint.resize(8)
	for j in n:
		var z := rect.position.y + j * step
		for i in n:
			var k := (j + 1) * wide + i + 1
			var h := hs[k]
			var nrm := Vector3(hs[k - 1] - hs[k + 1], 2.0 * step, hs[k - wide] - hs[k + wide]).normalized()
			var v := j * n + i
			var x := rect.position.x + i * step
			verts[v] = Vector3(i * step - half, h, j * step - half)
			normals[v] = nrm
			heights[v] = h
			land.paint(x, z, h, nrm.y, paint)
			colors[v] = Color(paint[0], paint[1], paint[2], paint[3])
			uv[v] = Vector2(paint[4], paint[5])
			uv2[v] = Vector2(paint[6], paint[7])
	var depth := SKIRT_BASE + SKIRT_PER_STEP * step
	var edges := _edge_cells()
	for e in 4:
		for k in n:
			var top: int = edges[e][k]
			var low := n * n + e * n + k
			verts[low] = verts[top] - Vector3(0.0, depth, 0.0)
			normals[low] = normals[top]
			colors[low] = colors[top]
			uv[low] = uv[top]
			uv2[low] = uv2[top]

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": mesh, "heights": heights, "ms": (Time.get_ticks_usec() - t0) / 1000.0}
