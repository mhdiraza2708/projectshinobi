class_name ContinentLand
extends RefCounted
## The shape of the continent, as pure functions of (x, z): a landmass about
## SIZE metres across in open sea, with a noisy coast, rolling hills, a
## mountain range in the north, river valleys running to the coast, a lake,
## a flat pad at each region's centre (the six story islands, spread out
## from Archipelago.LAYOUT) and a road network between them.
##
## Everything is deterministic from WORLD_SEED and read-only once built, so
## chunk workers call height_at() and paint() from any thread. "Up" is +y;
## north is -z, as on the islands.

const SIZE := 4096.0
const HALF := SIZE * 0.5
const WORLD_SEED := 7141
const SEA_LEVEL := Archipelago.SEA_LEVEL

# --- Regions ---------------------------------------------------------------------
## Archipelago.LAYOUT stretched by this and shifted so Emberwood, home, sits
## near the south coast and Five Winds high in the northern mountains.
const REGION_SCALE := 3.0
const REGION_ORIGIN := Vector2(0.0, 1350.0)
## A region's pad is dead flat out to PAD_FLAT metres, then blends into the
## land over PAD_FALLOFF more.
const PAD_FLAT := 40.0
const PAD_FALLOFF := 90.0
const MIN_PAD_HEIGHT := 2.5
## region_at() names a region within this many metres of its centre.
const REGION_RADIUS := 380.0
## The ground takes on a region's colours between these distances.
const BIOME_INNER := 200.0
const BIOME_OUTER := 650.0
## The packed-earth yard at a region's centre (radius, metres).
const YARD := 22.0
## How much of a region's ground is snow, however low.
const REGION_SNOW := {"frozen_road": 0.9}
## The continent's own colours (Emberwood's), for ground far from any region.
const BASE_REGION := "emberwood"

# --- Land ----------------------------------------------------------------------------
const COAST_LEVEL := 0.85
const COAST_NOISE := 0.15
const SQUARENESS := 0.5
const REGION_LAND_BOOST := 0.4
const BASE_HEIGHT := 3.0
const HILL_AMP := 52.0
## Hills calm down around regions so they sit in open country.
const REGION_HILL := 0.3
const MOUNTAIN_START := -650.0
const MOUNTAIN_FULL := -1150.0
const FOOTHILLS := 55.0
const PEAK_HEIGHT := 300.0
const SNOW_LINE := 150.0
const ROCK_LINE := 125.0
const SEA_FLOOR := -2.2
## What paint()'s colour multiplier is divided by to fit a byte.
const TINT_RANGE := 4.0

# --- Rivers, lakes, roads ------------------------------------------------------------
const RIVER_DEPTH := 1.1
## The bed climbs to the bank crest over RIVER_BANK metres beyond the water's
## edge, and the bank blends into the land by RIVER_REACH.
const RIVER_BANK := 8.0
const RIVER_REACH := 24.0
const RIVER_CREST := 1.0
const RIVER_SPACING := 12.0
## How far a river slides sideways to find its valley floor.
const VALLEY_REACH := 70.0
const RIVER_HALF_WIDTH := Vector2(2.4, 6.0)
const ROAD_HALF := 2.6
const ROAD_FALLOFF := 5.0
const ROAD_SPACING := 8.0
const ROAD_DIRT_FADE := 1.8
## The footpaths of a region are only looked for this close to its centre.
const FOOTPATH_REACH := 90.0
## Rivers: where they start (a point, or a lake by index) and the sea they
## run toward. The route finds its own way down.
const RIVERS: Array[Dictionary] = [
	{"name": "Westwater", "lake": 0, "toward": Vector2(-2200.0, 100.0)},
	{"name": "Southwater", "from": Vector2(380.0, -980.0), "toward": Vector2(700.0, 2300.0)},
	{"name": "Eastwater", "from": Vector2(1000.0, -900.0), "toward": Vector2(2300.0, -250.0)},
]
## Lakes: beside a region, by an offset, with a radius and depth in metres.
const LAKES: Array[Dictionary] = [
	{"near": "old_dam", "offset": Vector2(-70.0, -300.0), "radius": 120.0, "depth": 6.0},
]

var regions := PackedStringArray()
var roads: ContinentPaths
var rivers: ContinentPaths
## [{at: Vector2, radius, level, floor}] once built.
var lakes: Array[Dictionary] = []
## Road links as pairs of region ids.
var road_links: Array[PackedStringArray] = []
## The places of interest (see plan_sites); the scatter keeps clear of them.
var sites: ContinentSites

var _rx := PackedFloat32Array()
var _rz := PackedFloat32Array()
var _pad_h := PackedFloat32Array()
var _yard := PackedFloat32Array()
## Each region's own footpaths (its island preset's "paths"): per region a list
## of [PackedVector2Array of world points, half width].
var _footpaths: Array = []
var _snow := PackedFloat32Array()
## Tint of every region's layers relative to the continent's base colours:
## 4 per region (grass, dirt, rock, sand), as multipliers.
var _ratio := PackedColorArray()
var _lx := PackedFloat32Array()
var _lz := PackedFloat32Array()
var _lr := PackedFloat32Array()
var _lfloor := PackedFloat32Array()
var _coast := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _mask := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _wobble := FastNoiseLite.new()
var _router: ContinentRouter


func _init() -> void:
	_coast = _make_noise(1, 0.0011, 4)
	_hills = _make_noise(2, 0.0021, 5)
	_detail = _make_noise(3, 0.035, 3)
	_ridge = _make_noise(4, 0.0013, 5, FastNoiseLite.FRACTAL_RIDGED)
	_mask = _make_noise(5, 0.0009, 3)
	_forest = _make_noise(6, 0.0042, 3)
	_wobble = _make_noise(7, 0.006, 2)
	_place_regions()
	_place_lakes()
	_router = ContinentRouter.new(func(x: float, z: float) -> float: return _height(x, z, false))
	_build_rivers()
	_build_roads()
	_router = null


## Plans the places of interest (once). Call on the main thread before the
## scatter runs, which reads them from worker threads.
func plan_sites() -> ContinentSites:
	if sites == null:
		sites = ContinentSites.new(self)
	return sites


func _make_noise(offset: int, freq: float, octaves: int, fractal := FastNoiseLite.FRACTAL_FBM) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = WORLD_SEED + offset * 101
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	return n


# --- Regions ---------------------------------------------------------------------------

## Where a region's centre is on the continent, as (x, z).
static func region_position(id: String) -> Vector2:
	var at: Vector2 = Archipelago.LAYOUT.get(id, Vector2.ZERO)
	return at * REGION_SCALE + REGION_ORIGIN


func _place_regions() -> void:
	var base_palette: Dictionary = Island.PRESETS[BASE_REGION]
	for id: String in Archipelago.LAYOUT:
		var at := region_position(id)
		regions.append(id)
		_rx.append(at.x)
		_rz.append(at.y)
		_yard.append(YARD)
		_snow.append(float(REGION_SNOW.get(id, 0.0)))
		var preset: Dictionary = Island.PRESETS[id]
		var walks: Array = []
		for path: Array in preset.get("paths", []):
			var pts := PackedVector2Array()
			for q: Array in path[0]:
				pts.append(at + Vector2(q[0], q[1]))
			walks.append([pts, float(path[1]) * 0.5])
		_footpaths.append(walks)
		for layer in ["grass", "dirt", "rock", "sand"]:
			var want := (preset[layer] as Color).srgb_to_linear()
			var have := (base_palette[layer] as Color).srgb_to_linear()
			_ratio.append(Color(clampf(want.r / maxf(have.r, 0.004), 0.1, 3.9), clampf(want.g / maxf(have.g, 0.004), 0.1, 3.9),
				clampf(want.b / maxf(have.b, 0.004), 0.1, 3.9), 1.0))
	# Pads sit at the land's own height there (never under water).
	for i in regions.size():
		var h := 0.0
		for k in 5:
			var a := TAU * k / 5.0
			h += _terrain(_rx[i] + cos(a) * 30.0, _rz[i] + sin(a) * 30.0)
		_pad_h.append(maxf(h / 5.0, SEA_LEVEL + MIN_PAD_HEIGHT))


func region_index(id: String) -> int:
	return regions.find(id)


## A region's centre as (x, z); (0, 0) for an unknown one.
func region_center(id: String) -> Vector2:
	var i := regions.find(id)
	return Vector2(_rx[i], _rz[i]) if i >= 0 else Vector2.ZERO


## The height of a region's flat pad.
func pad_height(id: String) -> float:
	var i := regions.find(id)
	return _pad_h[i] if i >= 0 else 0.0


## The region whose centre is nearest (x, z), and how far it is.
func nearest_region(x: float, z: float) -> Dictionary:
	var best := 0
	var best_d2 := INF
	for i in _rx.size():
		var dx := x - _rx[i]
		var dz := z - _rz[i]
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best = i
	return {"id": regions[best], "distance": sqrt(best_d2)}


## The region whose land (x, z) is part of, or "" in the wilds between them.
func region_at(x: float, z: float) -> String:
	var near := nearest_region(x, z)
	return near["id"] if float(near["distance"]) <= REGION_RADIUS else ""


# --- Height ------------------------------------------------------------------------------

## Ground height at (x, z), roads and rivers carved in. Exactly the region's
## pad height across a pad.
func height_at(x: float, z: float) -> float:
	return _height(x, z, true)


func _height(x: float, z: float, with_roads: bool) -> float:
	var h := _terrain(x, z)
	for i in _lx.size():
		var dx := x - _lx[i]
		var dz := z - _lz[i]
		var d2 := dx * dx + dz * dz
		if d2 < _lr[i] * _lr[i]:
			h = minf(h, lerpf(_lfloor[i], h, smoothstep(_lr[i] * 0.6, _lr[i], sqrt(d2))))
	if rivers != null:
		var q := rivers.query(x, z)
		if q.x < RIVER_REACH:
			# A flat bed, banks climbing to a crest just above the water on
			# both sides, then easing into the land.
			var channel := lerpf(q.y, q.y + RIVER_DEPTH + RIVER_CREST, smoothstep(0.0, RIVER_BANK, q.x))
			h = lerpf(channel, h, smoothstep(RIVER_BANK, RIVER_REACH, q.x))
	if with_roads and roads != null:
		var q := roads.query(x, z)
		if q.x < ROAD_FALLOFF:
			h = lerpf(q.y, h, smoothstep(0.0, ROAD_FALLOFF, q.x))
	return _flatten_pads(x, z, h)


func _flatten_pads(x: float, z: float, h: float) -> float:
	const REACH := PAD_FLAT + PAD_FALLOFF
	for i in _rx.size():
		var dx := x - _rx[i]
		var dz := z - _rz[i]
		var d2 := dx * dx + dz * dz
		if d2 < REACH * REACH:
			h = lerpf(h, _pad_h[i], 1.0 - smoothstep(PAD_FLAT, REACH, sqrt(d2)))
	return h


## How much like land (x, z) is: above 0 is dry, 0 is the shoreline.
func land_value(x: float, z: float) -> float:
	var near2 := 1.0e12
	for i in _rx.size():
		var dx := x - _rx[i]
		var dz := z - _rz[i]
		near2 = minf(near2, dx * dx + dz * dz)
	return _land_value(x, z, sqrt(near2))


func _land_value(x: float, z: float, near_region: float) -> float:
	var ax := absf(x) / HALF
	var az := absf(z) / HALF
	var d := lerpf(sqrt(ax * ax + az * az), maxf(ax, az), SQUARENESS)
	return COAST_LEVEL - d + COAST_NOISE * _coast.get_noise_2d(x, z) \
		+ REGION_LAND_BOOST * (1.0 - smoothstep(150.0, 520.0, near_region))


## The bare land: continental shelf, coast, hills and mountains. No pads,
## rivers or roads yet.
func _terrain(x: float, z: float) -> float:
	var near2 := 1.0e12
	for i in _rx.size():
		var dx := x - _rx[i]
		var dz := z - _rz[i]
		near2 = minf(near2, dx * dx + dz * dz)
	var near_d := sqrt(near2)
	var c := _land_value(x, z, near_d)
	var h_sea := SEA_FLOOR + maxf(c, -0.5) * 50.0
	if c < -0.02:
		return h_sea
	var rise := smoothstep(0.03, 0.17, c)
	var calm := smoothstep(120.0, 420.0, near_d)
	var n := 0.5 + 0.5 * _hills.get_noise_2d(x, z)
	var h := BASE_HEIGHT + HILL_AMP * (0.2 + 0.8 * n) * lerpf(REGION_HILL, 1.0, calm) \
		+ 1.3 * _detail.get_noise_2d(x, z) * calm
	var north := smoothstep(MOUNTAIN_START, MOUNTAIN_FULL, z + 260.0 * _mask.get_noise_2d(x, z))
	if north > 0.0:
		var r := clampf(0.5 + 0.5 * _ridge.get_noise_2d(x, z), 0.0, 1.0)
		h += north * calm * (FOOTHILLS + PEAK_HEIGHT * r * r)
	var h_land := lerpf(0.6, h, rise)
	if c >= 0.025:
		return h_land
	return lerpf(h_sea, h_land, smoothstep(-0.02, 0.025, c))


## Surface slope as 1 - the normal's y (0 flat), from height samples.
func slope_at(x: float, z: float) -> float:
	var dx := height_at(x + 1.0, z) - height_at(x - 1.0, z)
	var dz := height_at(x, z + 1.0) - height_at(x, z - 1.0)
	return 1.0 - Vector3(-dx, 2.0, -dz).normalized().y


## True when everything in the square is open sea well below the surface (no
## need to build it).
func is_open_sea(rect: Rect2) -> bool:
	for k in 25:
		var p := rect.position + Vector2(rect.size.x * (k % 5) / 4.0, rect.size.y * (k / 5) / 4.0)
		if land_value(p.x, p.y) > -0.12:
			return false
	return true


# --- Look ------------------------------------------------------------------------------------

## How wooded (x, z) is, 0 to 1 (the trees follow it, and so does the ground's
## colour from afar).
func forest_at(x: float, z: float) -> float:
	return smoothstep(-0.05, 0.3, _forest.get_noise_2d(x, z))


## Paints a point of ground for the terrain shader. `out` receives: [0..3]
## splat weights (grass, dirt, rock, sand), [4..6] the colour multiplier for
## the region's palette (/ TINT_RANGE) and [7] snow. `ny` is the surface
## normal's y.
func paint(x: float, z: float, h: float, ny: float, out: PackedFloat32Array) -> void:
	var slope := 1.0 - ny
	var n := _detail.get_noise_2d(x, z)
	var rock := maxf(smoothstep(0.30, 0.52, slope), 0.85 * smoothstep(ROCK_LINE, ROCK_LINE + 80.0, h + n * 14.0))
	var sand := smoothstep(SEA_LEVEL + 1.2, SEA_LEVEL + 0.3, h)
	var dirt := 0.0
	if roads != null:
		var rq := roads.query(x, z)
		if rq.x < ROAD_DIRT_FADE:
			dirt = 1.0 - smoothstep(0.0, ROAD_DIRT_FADE, rq.x)
	if rivers != null:
		var vq := rivers.query(x, z)
		if vq.x < 3.5:
			sand = maxf(sand, 0.75 * (1.0 - smoothstep(0.0, 3.5, vq.x)))
	# Biomes: each region's palette, fading in toward its centre.
	var wsum := 0.0
	var wmax := 0.0
	var snow_acc := 0.0
	var wd := dirt
	var wg := 1.0 - dirt
	var ws := sand
	wg *= 1.0 - sand
	wd *= 1.0 - sand
	var wr := rock
	wg *= 1.0 - rock
	wd *= 1.0 - rock
	ws *= 1.0 - rock
	var regional := Color(0, 0, 0, 0)
	for i in _rx.size():
		var dx := x - _rx[i]
		var dz := z - _rz[i]
		var d := sqrt(dx * dx + dz * dz)
		if d < _yard[i] + 6.0:
			var yard := 1.0 - smoothstep(_yard[i] - 5.0, _yard[i] + 1.0, d + 2.0 * n)
			var take := yard * (1.0 - rock)
			wd += (wg + ws) * take
			wg *= 1.0 - take
			ws *= 1.0 - take
		if d < FOOTPATH_REACH:
			var walk := _footpath_weight(i, x, z) * (1.0 - rock)
			if walk > 0.0:
				wd += (wg + ws) * walk
				wg *= 1.0 - walk
				ws *= 1.0 - walk
		var w := 1.0 - smoothstep(BIOME_INNER, BIOME_OUTER, d)
		if w > 0.0:
			var b := i * 4
			regional += (_ratio[b] * wg + _ratio[b + 1] * wd + _ratio[b + 2] * wr + _ratio[b + 3] * ws) * w
			wsum += w
			wmax = maxf(wmax, w)
			snow_acc += _snow[i] * w
	var w_default := 1.0 - wmax
	var total := wsum + w_default
	var mul := (regional + Color(1, 1, 1, 0) * w_default) / total
	var forest := forest_at(x, z)
	var shade := 1.0 - 0.2 * forest * wg
	var snow := maxf(smoothstep(SNOW_LINE, SNOW_LINE + 70.0, h + n * 20.0), snow_acc / total)
	snow *= (1.0 - 0.6 * smoothstep(0.45, 0.75, slope)) * (1.0 - wd * 0.85) * (1.0 - ws)
	out[0] = wg
	out[1] = wd
	out[2] = wr
	out[3] = ws
	out[4] = clampf(mul.r * shade / TINT_RANGE, 0.0, 1.0)
	out[5] = clampf(mul.g * shade / TINT_RANGE, 0.0, 1.0)
	out[6] = clampf(mul.b * shade / TINT_RANGE, 0.0, 1.0)
	out[7] = snow



## How much of (x, z) a region's footpaths cover (0-1): beaten earth along the
## paths the island presets draw, fading over ROAD_DIRT_FADE at the edge.
func _footpath_weight(region: int, x: float, z: float) -> float:
	var best := 1.0e9
	for walk: Array in _footpaths[region]:
		var pts: PackedVector2Array = walk[0]
		for k in range(pts.size() - 1):
			var a := pts[k]
			var b := pts[k + 1]
			var ab := b - a
			var t := clampf(((x - a.x) * ab.x + (z - a.y) * ab.y) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			best = minf(best, Vector2(x, z).distance_to(a + ab * t) - float(walk[1]))
	return 1.0 - smoothstep(0.0, ROAD_DIRT_FADE, best)


## What the ground is at (x, z), for footsteps: grass, dirt, stone, sand,
## snow or water.
func surface_at(x: float, z: float) -> StringName:
	var h := height_at(x, z)
	if h < SEA_LEVEL:
		return &"water"
	if rivers != null:
		var q := rivers.query(x, z)
		if q.x < 0.0 and h < q.y + RIVER_DEPTH:
			return &"water"
	var dx := height_at(x + 1.0, z) - height_at(x - 1.0, z)
	var dz := height_at(x, z + 1.0) - height_at(x, z - 1.0)
	var out := PackedFloat32Array()
	out.resize(8)
	paint(x, z, h, Vector3(-dx, 2.0, -dz).normalized().y, out)
	if out[7] > 0.5:
		return &"snow"
	var names: Array[StringName] = [&"grass", &"dirt", &"stone", &"sand"]
	var best := 0
	for k in 4:
		if out[k] > out[best]:
			best = k
	return names[best]


## The water's surface height where a river or lake covers (x, z), or -INF
## on dry ground.
func water_level_at(x: float, z: float) -> float:
	for i in _lx.size():
		if Vector2(x - _lx[i], z - _lz[i]).length() < _lr[i] * 0.9:
			return float(lakes[i]["level"])
	if rivers != null:
		var q := rivers.query(x, z)
		if q.x < 0.0:
			return q.y + RIVER_DEPTH
	return -INF


# --- Lakes -------------------------------------------------------------------------------------

func _place_lakes() -> void:
	for spec in LAKES:
		var at := region_center(spec["near"]) + (spec["offset"] as Vector2)
		var r: float = spec["radius"]
		# The water stands as high as the lowest part of the rim, so it never
		# hangs over a lower side.
		var rim := INF
		for k in 16:
			var a := TAU * k / 16.0
			rim = minf(rim, _terrain(at.x + cos(a) * r, at.y + sin(a) * r))
		var level := rim - 0.4
		lakes.append({"at": at, "radius": r, "level": level, "floor": level - float(spec["depth"])})
		_lx.append(at.x)
		_lz.append(at.y)
		_lr.append(r)
		_lfloor.append(level - float(spec["depth"]))


# --- Rivers -----------------------------------------------------------------------------------

func _build_rivers() -> void:
	var found := ContinentPaths.new(RIVER_REACH + 2.0)
	for spec in RIVERS:
		var to: Vector2 = spec["toward"]
		var start: Vector2
		var start_level := INF
		if spec.has("lake"):
			var lake: Dictionary = lakes[spec["lake"]]
			var dir := ((to - (lake["at"] as Vector2)) as Vector2).normalized()
			start = (lake["at"] as Vector2) + dir * (float(lake["radius"]) * 1.15)
			start_level = float(lake["level"]) - 0.3
		else:
			start = spec["from"]
		var weights := _river_weights(start)
		var route := _router.route(start, _coast_crossing(start, to), weights)
		if route.size() < 3:
			continue
		var pts := ContinentRouter.resample(ContinentRouter.smooth(route), RIVER_SPACING)
		# Carry it on into the sea if the route stopped short, then stop where
		# it meets the water.
		pts = _to_the_sea(pts)
		var cut := pts.size()
		for i in pts.size():
			if _height(pts[i].x, pts[i].y, false) < SEA_LEVEL + 0.1:
				cut = i + 2
				break
		pts = pts.slice(0, mini(cut, pts.size()))
		pts = _wobbled(pts, 22.0, 120.0)
		pts = _in_the_valley(pts)
		var banks := PackedFloat32Array()
		for p in pts:
			banks.append(_height(p.x, p.y, false))
		banks = ContinentRouter.blur(banks, 4)
		var beds := PackedFloat32Array()
		var widths := PackedFloat32Array()
		var cur := minf(start_level, banks[0] - RIVER_DEPTH * 0.8)
		for i in pts.size():
			cur = minf(cur - 0.0015 * RIVER_SPACING, banks[i] - 0.9)
			cur = maxf(cur, SEA_LEVEL + 0.05)
			beds.append(cur - RIVER_DEPTH)
			widths.append(lerpf(RIVER_HALF_WIDTH.x, RIVER_HALF_WIDTH.y, float(i) / maxf(pts.size() - 1, 1.0)))
		found.add_path(pts, beds, widths)
	found.finish()
	rivers = found


## Extends a river straight on until it is over the sea.
func _to_the_sea(pts: PackedVector2Array) -> PackedVector2Array:
	var dir := (pts[pts.size() - 1] - pts[maxi(pts.size() - 4, 0)]).normalized()
	var p := pts[pts.size() - 1]
	for k in 60:
		if _terrain(p.x, p.y) < SEA_LEVEL - 0.3:
			break
		p += dir * RIVER_SPACING
		pts.append(p)
	return pts


## Slides each node of a river sideways to the low ground beside it (within
## VALLEY_REACH metres), smoothly along the river, so it runs along the valley
## floor and not along a slope.
func _in_the_valley(pts: PackedVector2Array) -> PackedVector2Array:
	var shifts := PackedFloat32Array()
	var sides: Array[Vector2] = []
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var side := (b - a).normalized().orthogonal()
		sides.append(side)
		var best := 0.0
		var best_h := INF
		for k in range(-8, 9):
			var o := k * VALLEY_REACH / 8.0
			var h := _height(pts[i].x + side.x * o, pts[i].y + side.y * o, false) + 0.008 * absf(o)
			if h < best_h:
				best_h = h
				best = o
		shifts.append(best)
	shifts = ContinentRouter.blur(shifts, 3)
	var out := PackedVector2Array()
	for i in pts.size():
		out.append(pts[i] + sides[i] * shifts[i])
	return out


## Route costs for a river: it likes low ground and gentle slopes, and keeps
## out of the regions' yards.
func _river_weights(start: Vector2) -> PackedFloat32Array:
	var cells := _router.cells
	var weights := PackedFloat32Array()
	weights.resize(cells * cells)
	var h0 := _router.heights[_router.cell_of(start).y * cells + _router.cell_of(start).x]
	for j in cells:
		for i in cells:
			var k := j * cells + i
			var p := _router.cell_pos(Vector2i(i, j))
			var h := _router.heights[k]
			var w := 1.0 + 0.06 * maxf(h, 0.0) + 14.0 * _router.slopes[k] * _router.slopes[k] + 0.25 * maxf(h - h0, 0.0)
			if h < SEA_LEVEL + 0.3:
				w = -1.0
			for r in _rx.size():
				if Vector2(p.x - _rx[r], p.y - _rz[r]).length() < PAD_FLAT + PAD_FALLOFF + 40.0:
					w = -1.0
			weights[k] = w
	return weights


## Where the straight line from `from` toward the sea at `toward` first meets
## the coast, coming in from the sea.
func _coast_crossing(from: Vector2, toward: Vector2) -> Vector2:
	for k in 241:
		var p := toward.lerp(from, k / 240.0)
		if _terrain(p.x, p.y) > SEA_LEVEL + 1.0:
			return p
	return toward


## A path nudged sideways by a slow noise, so it winds.
func _wobbled(pts: PackedVector2Array, amount: float, wavelength: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var side := (b - a).normalized().orthogonal()
		var edge := minf(minf(i, pts.size() - 1 - i) * RIVER_SPACING / wavelength, 1.0)
		out.append(pts[i] + side * amount * edge * _wobble.get_noise_2d(pts[i].x, pts[i].y) * 2.0)
	return out


# --- Roads --------------------------------------------------------------------------------------

func _build_roads() -> void:
	var found := ContinentPaths.new(ROAD_FALLOFF + 2.0)
	var weights := _road_weights()
	var cells := _router.cells
	var links := _road_links()
	for link in links:
		var a := region_center(link[0])
		var b := region_center(link[1])
		var route := _router.route(a, b, weights)
		if route.size() < 2:
			continue
		var pts := ContinentRouter.resample(ContinentRouter.smooth(route), ROAD_SPACING)
		pts = _wobbled_road(pts)
		# The roadbed follows the land, evened out, and fords a river.
		var heights := PackedFloat32Array()
		for p in pts:
			heights.append(_height(p.x, p.y, false))
		heights = ContinentRouter.blur(heights, 3)
		var widths := PackedFloat32Array()
		for i in pts.size():
			var vq := rivers.query(pts[i].x, pts[i].y)
			if vq.x < 3.0:
				heights[i] = minf(heights[i], vq.y + RIVER_DEPTH - 0.35)
			widths.append(ROAD_HALF)
		found.add_path(pts, heights, widths)
		road_links.append(PackedStringArray([link[0], link[1]]))
		# Later roads like to share the way.
		for p in pts:
			var c := _router.cell_of(p)
			for dj in range(-1, 2):
				for di in range(-1, 2):
					var k := clampi(c.y + dj, 0, cells - 1) * cells + clampi(c.x + di, 0, cells - 1)
					if weights[k] > 0.0:
						weights[k] = maxf(weights[k] * 0.8, 0.5)
	found.finish()
	roads = found


func _wobbled_road(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var side := (b - a).normalized().orthogonal()
		# Ends stay on the regions' centres.
		var edge := minf(minf(i, pts.size() - 1 - i) * ROAD_SPACING / 60.0, 1.0)
		out.append(pts[i] + side * 5.0 * edge * _wobble.get_noise_2d(pts[i].x + 900.0, pts[i].y) * 2.0)
	return out


## Route costs for roads: water is out, steep ground is slow, rivers are a
## nuisance to cross.
func _road_weights() -> PackedFloat32Array:
	var cells := _router.cells
	var weights := PackedFloat32Array()
	weights.resize(cells * cells)
	for j in cells:
		for i in cells:
			var k := j * cells + i
			var p := _router.cell_pos(Vector2i(i, j))
			var h := _router.heights[k]
			var w := 1.0 + 40.0 * _router.slopes[k] * _router.slopes[k]
			if h < SEA_LEVEL + 0.8:
				w = -1.0
			elif rivers != null and rivers.query(p.x, p.y).x < ContinentRouter.STEP * 0.6:
				w += 2.5
			for l in _lx.size():
				if Vector2(p.x - _lx[l], p.y - _lz[l]).length() < _lr[l] + 12.0:
					w = -1.0
			weights[k] = w
	return weights


## Which regions the roads join: the shortest tree reaching every region,
## plus the shortest two roads that would close a loop.
func _road_links() -> Array[PackedStringArray]:
	var links: Array[PackedStringArray] = []
	var joined := {regions[0]: true}
	while joined.size() < regions.size():
		var best := PackedStringArray()
		var best_d := INF
		for a: String in joined:
			for b in regions:
				if joined.has(b):
					continue
				var d := region_center(a).distance_to(region_center(b))
				if d < best_d:
					best_d = d
					best = PackedStringArray([a, b])
		joined[best[1]] = true
		links.append(best)
	var extras: Array[PackedStringArray] = []
	for i in regions.size():
		for j in range(i + 1, regions.size()):
			if not links.any(func(l: PackedStringArray) -> bool: return l.has(regions[i]) and l.has(regions[j])):
				extras.append(PackedStringArray([regions[i], regions[j]]))
	extras.sort_custom(func(l: PackedStringArray, m: PackedStringArray) -> bool:
		return region_center(l[0]).distance_to(region_center(l[1])) < region_center(m[0]).distance_to(region_center(m[1])))
	links.append_array(extras.slice(0, 2))
	return links
