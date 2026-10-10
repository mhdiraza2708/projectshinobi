class_name ContinentScatter
extends RefCounted
## Trees, bamboo and boulders over the continent. Every 64 m cell has a grid
## of candidate spots; a stateless hash of (cell, spot) decides what grows
## there, so the same spot gives the same tree whatever the chunk around it
## is (a chunk of any size just gathers its cells), and a coarse chunk takes
## every other spot. Free of scene-tree access: runs on worker threads, after
## ModelMeshes.warm(SPECIES) has filled the mesh cache.

## Cells are this wide (metres); each has GRID x GRID candidate spots.
const CELL := 64.0
const GRID := 12
## Jitter of a spot around its grid point, as a fraction of the spacing.
const JITTER := 0.34
## Every model scatter uses.
const SPECIES: PackedStringArray = ["pine", "broadleaf", "maple", "dead_tree", "snow_pine", "bamboo", "rock"]
## Scale range of each model.
const SCALES := {
	"pine": Vector2(0.9, 1.35), "broadleaf": Vector2(0.85, 1.2), "maple": Vector2(0.9, 1.4), "dead_tree": Vector2(0.8, 1.4),
	"snow_pine": Vector2(0.9, 1.5), "bamboo": Vector2(0.9, 1.2), "rock": Vector2(0.6, 2.4),
}
## The big, detailed models (thousands of triangles each) are thinned out and
## drawn over a shorter range, so a wood of them costs what one of pines does.
const THINNING := {"broadleaf": 0.5, "maple": 0.5, "bamboo": 0.4, "rock": 1.0}
const RANGE_SCALE := {"broadleaf": 0.6, "maple": 0.6, "bamboo": 0.45, "rock": 0.75}
## What grows in the wilds between regions: [[model, weight], ...].
const WILD_MIX := [["pine", 50.0], ["broadleaf", 30.0], ["maple", 4.0], ["rock", 8.0]]
## Chance that a spot in thick forest, and in open ground, grows a tree.
const FOREST_DENSITY := 0.3
const MEADOW_DENSITY := 0.025
## Chance that a spot picked for a boulder gets one.
const ROCK_DENSITY := 0.3
## Trees stop climbing the mountains between these heights.
const TREE_LINE := Vector2(105.0, 185.0)
## Nothing grows this close to a region's centre, and it thickens to full by
## the second distance.
const CLEAR_RADIUS := Vector2(75.0, 170.0)
## Steepest ground a tree stands on (1 - normal y).
const MAX_SLOPE := 0.34

static var _mixes: Dictionary = {}


## The models' meshes, ready for worker threads. Call once on the main thread.
static func warm() -> void:
	ModelMeshes.warm(SPECIES)
	_mix_table()


## Every scatter instance in `rect`, taking one spot in `thin` (1 = all, 2 =
## half): {model: PackedFloat32Array of (x, y, z, yaw, scale) per instance}.
static func instances(land: ContinentLand, rect: Rect2, thin := 1) -> Dictionary:
	var out := {}
	var spacing := CELL / GRID
	var mix_table := _mix_table()
	for cz in range(int(floorf(rect.position.y / CELL)), int(ceilf(rect.end.y / CELL))):
		for cx in range(int(floorf(rect.position.x / CELL)), int(ceilf(rect.end.x / CELL))):
			var cell_key := ((cx + 4096) * 8192 + (cz + 4096)) * 256
			for gz in GRID:
				for gx in GRID:
					if thin > 1 and (gx + gz) % thin != 0:
						continue
					var key := cell_key + gz * GRID + gx
					var roll := _unit(key, 0)
					# Cheap early out: nothing is denser than the forest.
					if roll > FOREST_DENSITY:
						continue
					var x := cx * CELL + (gx + 0.5 + (_unit(key, 1) - 0.5) * 2.0 * JITTER) * spacing
					var z := cz * CELL + (gz + 0.5 + (_unit(key, 2) - 0.5) * 2.0 * JITTER) * spacing
					_try_spot(land, mix_table, x, z, key, roll, out)
	return out


static func _try_spot(land: ContinentLand, mix_table: Dictionary, x: float, z: float, key: int, roll: float, out: Dictionary) -> void:
	var near := land.nearest_region(x, z)
	var d: float = near["distance"]
	var clear := smoothstep(CLEAR_RADIUS.x, CLEAR_RADIUS.y, d)
	if clear <= 0.0:
		return
	# Which model: the region's own mix near it, the wilds' farther out.
	var biome := 1.0 - smoothstep(ContinentLand.BIOME_INNER, ContinentLand.BIOME_OUTER, d)
	var mix: Dictionary = mix_table[near["id"]] if _unit(key, 3) < biome else mix_table[""]
	var pick := _unit(key, 4) * float(mix["total"])
	var model := ""
	for entry: Array in mix["list"]:
		if pick <= float(entry[1]):
			model = entry[0]
			break
	if model == "" or _unit(key, 8) > float(THINNING.get(model, 1.0)):
		return
	var h := land.height_at(x, z)
	if h < ContinentLand.SEA_LEVEL + 0.8:
		return
	if model == "rock":
		if _unit(key, 5) > ROCK_DENSITY:
			return
	else:
		var density := lerpf(MEADOW_DENSITY, FOREST_DENSITY, land.forest_at(x, z)) * clear \
			* (1.0 - smoothstep(TREE_LINE.x, TREE_LINE.y, h))
		if roll > density:
			return
	if land.slope_at(x, z) > MAX_SLOPE * (2.2 if model == "rock" else 1.0):
		return
	if land.roads != null and land.roads.query(x, z).x < 3.5:
		return
	if land.rivers != null and land.rivers.query(x, z).x < 4.0:
		return
	for lake in land.lakes:
		if Vector2(x, z).distance_to(lake["at"]) < float(lake["radius"]) + 4.0:
			return
	var scale_range: Vector2 = SCALES[model]
	var list: PackedFloat32Array = out.get(model, PackedFloat32Array())
	list.append_array([x, h - 0.08, z, _unit(key, 6) * TAU, lerpf(scale_range.x, scale_range.y, _unit(key, 7))])
	out[model] = list


## MultiMeshes for a node: [{model, multimesh, count}], one per mesh of each
## model. `origin` is the chunk's centre (x, z): instances sit relative to it.
static func multimeshes(found: Dictionary, origin: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for model: String in found:
		var raw: PackedFloat32Array = found[model]
		var count := raw.size() / 5
		for part: Array in ModelMeshes.parts(model):
			var xf: Transform3D = part[1]
			var buffer := PackedFloat32Array()
			buffer.resize(count * 12)
			for i in count:
				var s := raw[i * 5 + 4]
				var t := Transform3D(Basis(Vector3.UP, raw[i * 5 + 3]).scaled(Vector3.ONE * s),
					Vector3(raw[i * 5] - origin.x, raw[i * 5 + 1], raw[i * 5 + 2] - origin.y)) * xf
				var b := t.basis
				var o := i * 12
				buffer[o] = b.x.x
				buffer[o + 1] = b.y.x
				buffer[o + 2] = b.z.x
				buffer[o + 3] = t.origin.x
				buffer[o + 4] = b.x.y
				buffer[o + 5] = b.y.y
				buffer[o + 6] = b.z.y
				buffer[o + 7] = t.origin.y
				buffer[o + 8] = b.x.z
				buffer[o + 9] = b.y.z
				buffer[o + 10] = b.z.z
				buffer[o + 11] = t.origin.z
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = count
			mm.buffer = buffer
			out.append({"model": model, "multimesh": mm, "count": count})
	return out


# --- Biome mixes -------------------------------------------------------------------------

## What grows where: region id (and "" for the wilds) -> {list: [[model,
## cumulative weight], ...], total}, from the island presets' scatter lists.
## Built by warm() on the main thread; workers only read it.
static func _mix_table() -> Dictionary:
	if not _mixes.is_empty():
		return _mixes
	var table := {"": _cumulative(WILD_MIX)}
	for id: String in Island.PRESETS:
		var spec: Array = []
		for s: Dictionary in Island.PRESETS[id].get("scatter", []):
			spec.append([s["scene"], float(s["count"])])
		table[id] = _cumulative(spec)
	_mixes = table
	return table


static func _cumulative(spec: Array) -> Dictionary:
	var list := []
	var total := 0.0
	for entry: Array in spec:
		if not SPECIES.has(entry[0]):
			continue
		total += float(entry[1])
		list.append([entry[0], total])
	return {"list": list, "total": total}


## A repeatable number in [0, 1) for a spot and a purpose.
static func _unit(key: int, purpose: int) -> float:
	var v := (key * 2654435761 + purpose * 40503 + ContinentLand.WORLD_SEED) & 0xFFFFFFFF
	v = ((v ^ (v >> 16)) * 0x7feb352d) & 0xFFFFFFFF
	v = ((v ^ (v >> 15)) * 0x846ca68b) & 0xFFFFFFFF
	v = v ^ (v >> 16)
	return float(v) / 4294967296.0
