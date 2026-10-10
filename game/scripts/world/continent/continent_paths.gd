class_name ContinentPaths
extends RefCounted
## A set of smooth paths over the continent (the roads, or the rivers): each
## node carries a height and a half width. A spatial hash answers "how near
## is the closest path here" fast enough for a height function that runs
## thousands of times per chunk on worker threads. Build it with add_path()
## and finish(); after that it is read-only, so any thread may query it.

## Cell size of the spatial hash (metres).
const CELL := 64.0
## What query() reports as the distance when no path is near.
const NONE := 1.0e9

## Every path as added: {points: PackedVector2Array, heights: PackedFloat32Array,
## widths: PackedFloat32Array}.
var paths: Array[Dictionary] = []
## How far from a path's edge a query still finds it (metres).
var reach := 24.0

var _ax := PackedFloat32Array()
var _az := PackedFloat32Array()
var _bx := PackedFloat32Array()
var _bz := PackedFloat32Array()
var _ah := PackedFloat32Array()
var _bh := PackedFloat32Array()
var _aw := PackedFloat32Array()
var _bw := PackedFloat32Array()
var _grid: Dictionary = {}


func _init(search_reach := 24.0) -> void:
	reach = search_reach


## Adds a path: `points` in (x, z), with a height and a half width at each.
func add_path(points: PackedVector2Array, heights: PackedFloat32Array, half_widths: PackedFloat32Array) -> void:
	paths.append({"points": points, "heights": heights, "widths": half_widths})


## Sorts every segment into the hash. Call once, after the last add_path.
func finish() -> void:
	_grid.clear()
	for path in paths:
		var pts: PackedVector2Array = path["points"]
		var hs: PackedFloat32Array = path["heights"]
		var ws: PackedFloat32Array = path["widths"]
		for i in pts.size() - 1:
			var id := _ax.size()
			_ax.append(pts[i].x)
			_az.append(pts[i].y)
			_bx.append(pts[i + 1].x)
			_bz.append(pts[i + 1].y)
			_ah.append(hs[i])
			_bh.append(hs[i + 1])
			_aw.append(ws[i])
			_bw.append(ws[i + 1])
			var pad := reach + maxf(ws[i], ws[i + 1])
			var lo := Vector2(minf(pts[i].x, pts[i + 1].x), minf(pts[i].y, pts[i + 1].y)) - Vector2(pad, pad)
			var hi := Vector2(maxf(pts[i].x, pts[i + 1].x), maxf(pts[i].y, pts[i + 1].y)) + Vector2(pad, pad)
			for cx in range(int(floorf(lo.x / CELL)), int(floorf(hi.x / CELL)) + 1):
				for cz in range(int(floorf(lo.y / CELL)), int(floorf(hi.y / CELL)) + 1):
					var key := cx * 8192 + cz
					var list: PackedInt32Array = _grid.get(key, PackedInt32Array())
					list.append(id)
					_grid[key] = list


func is_empty() -> bool:
	return paths.is_empty()


## The nearest path at (x, z) as Vector3(e, height, half width): e is the
## distance beyond the path's edge (negative on it), NONE when nothing is
## within reach.
func query(x: float, z: float) -> Vector3:
	var list: Variant = _grid.get(int(floorf(x / CELL)) * 8192 + int(floorf(z / CELL)))
	if list == null:
		return Vector3(NONE, 0.0, 0.0)
	var best_e := NONE
	var best_h := 0.0
	var best_w := 0.0
	for id: int in (list as PackedInt32Array):
		var ax := _ax[id]
		var az := _az[id]
		var dx := _bx[id] - ax
		var dz := _bz[id] - az
		var len2 := dx * dx + dz * dz
		var t := clampf(((x - ax) * dx + (z - az) * dz) / maxf(len2, 0.0001), 0.0, 1.0)
		var px := x - (ax + dx * t)
		var pz := z - (az + dz * t)
		var w := lerpf(_aw[id], _bw[id], t)
		var e := sqrt(px * px + pz * pz) - w
		if e < best_e:
			best_e = e
			best_h = lerpf(_ah[id], _bh[id], t)
			best_w = w
	return Vector3(best_e, best_h, best_w)


## Total length of every path (metres).
func total_length() -> float:
	var sum := 0.0
	for path in paths:
		var pts: PackedVector2Array = path["points"]
		for i in pts.size() - 1:
			sum += pts[i].distance_to(pts[i + 1])
	return sum
