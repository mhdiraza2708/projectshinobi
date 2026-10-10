class_name ContinentRouter
extends RefCounted
## Least-cost routes over a coarse grid of the continent, for laying roads and
## finding where rivers run. The caller says what each cell costs (a weight,
## or negative for "never"); this finds the cheapest chain of cells and turns
## it into a smooth path.

## Metres per grid cell.
const STEP := 48.0

var cells := 0
## Ground height and slope (rise over run) at each cell's middle.
var heights := PackedFloat32Array()
var slopes := PackedFloat32Array()

var _astar := AStarGrid2D.new()


## `height_fn(x, z) -> float` gives the ground to measure cells on.
func _init(height_fn: Callable) -> void:
	cells = int(ceil(ContinentLand.SIZE / STEP))
	heights.resize(cells * cells)
	slopes.resize(cells * cells)
	for j in cells:
		for i in cells:
			var p := cell_pos(Vector2i(i, j))
			heights[j * cells + i] = height_fn.call(p.x, p.y)
	for j in cells:
		for i in cells:
			var dx := heights[j * cells + mini(i + 1, cells - 1)] - heights[j * cells + maxi(i - 1, 0)]
			var dz := heights[mini(j + 1, cells - 1) * cells + i] - heights[maxi(j - 1, 0) * cells + i]
			slopes[j * cells + i] = sqrt(dx * dx + dz * dz) / (2.0 * STEP)
	_astar.region = Rect2i(0, 0, cells, cells)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_astar.update()


func cell_pos(c: Vector2i) -> Vector2:
	return Vector2(-ContinentLand.HALF + (c.x + 0.5) * STEP, -ContinentLand.HALF + (c.y + 0.5) * STEP)


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int((p.x + ContinentLand.HALF) / STEP), 0, cells - 1),
		clampi(int((p.y + ContinentLand.HALF) / STEP), 0, cells - 1))


## The cheapest route from `from` to `to` (x, z), as cell middles with the two
## ends exact. `weights` has one cost per cell (row by row; negative cells
## cannot be crossed). Empty when there is no route.
func route(from: Vector2, to: Vector2, weights: PackedFloat32Array) -> PackedVector2Array:
	var a := cell_of(from)
	var b := cell_of(to)
	for j in cells:
		for i in cells:
			var w := weights[j * cells + i]
			var c := Vector2i(i, j)
			_astar.set_point_solid(c, w < 0.0)
			if w >= 0.0:
				_astar.set_point_weight_scale(c, maxf(w, 0.05))
	_astar.set_point_solid(a, false)
	_astar.set_point_solid(b, false)
	var out := PackedVector2Array()
	var ids := _astar.get_id_path(a, b)
	if ids.is_empty():
		return out
	out.append(from)
	for k in range(1, ids.size() - 1):
		out.append(cell_pos(ids[k]))
	out.append(to)
	return out


## Rounds off a route's corners (Chaikin) without moving its ends.
static func smooth(points: PackedVector2Array, rounds := 3) -> PackedVector2Array:
	var pts := points
	for r in rounds:
		if pts.size() < 3:
			break
		var next := PackedVector2Array()
		next.append(pts[0])
		for i in pts.size() - 1:
			next.append(pts[i].lerp(pts[i + 1], 0.25))
			next.append(pts[i].lerp(pts[i + 1], 0.75))
		next.append(pts[pts.size() - 1])
		pts = next
	return pts


## Points along a path every `spacing` metres (the ends included).
static func resample(points: PackedVector2Array, spacing: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.is_empty():
		return out
	out.append(points[0])
	var carry := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var seg := a.distance_to(b)
		var pos := spacing - carry
		while pos <= seg:
			out.append(a.lerp(b, pos / seg))
			pos += spacing
		carry = seg - (pos - spacing)
	if out[out.size() - 1].distance_to(points[points.size() - 1]) > spacing * 0.25:
		out.append(points[points.size() - 1])
	else:
		out[out.size() - 1] = points[points.size() - 1]
	return out


## A moving average of `values` (window of +-radius nodes).
static func blur(values: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(values.size())
	for i in values.size():
		var sum := 0.0
		var count := 0
		for k in range(maxi(i - radius, 0), mini(i + radius, values.size() - 1) + 1):
			sum += values[k]
			count += 1
		out[i] = sum / count
	return out
