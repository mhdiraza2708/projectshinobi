class_name ContinentSites
extends RefCounted
## Where the continent's places of interest stand: roadside shrines,
## villages, raiders' camps and ruins. Planned from the land alone (the same
## every time, nothing to save): candidates along the roads and out in the
## wilds, each kept only where the ground is dry and level enough, apart from
## the other sites and from the regions (which have props of their own).

const CAMP := "camp"
const SHRINE := "shrine"
const VILLAGE := "village"
const RUIN := "ruin"
## A wanted shinobi's hideout (see Bounties): one lair for each of them.
const LAIR := "lair"
const KINDS: Array[String] = [CAMP, SHRINE, VILLAGE, RUIN, LAIR]

const SEED := 4242
## No two sites closer than this (metres).
const SPACING := 240.0
## Sites keep this far from a region's centre (its pad has props of its own).
const REGION_CLEAR := 190.0
## The most the ground may differ across a site's footprint (metres).
const LEVEL := 2.6
const FOOTPRINT := 12.0
## The most sites there will be.
const MAX_SITES := 72
## Villages are few and lie by roads.
const MAX_VILLAGES := 8
## The order kinds are handed out, so the world has a mix.
const PATTERN: Array[String] = [SHRINE, CAMP, VILLAGE, CAMP, RUIN, SHRINE, CAMP, CAMP, VILLAGE, RUIN]

## How dangerous a region's surroundings are (0 to 2): which fighters a
## camp there holds.
const DANGER := {
	"emberwood": 0, "autumn_wood": 0, "old_dam": 1, "ashen_pass": 1, "frozen_road": 2, "five_winds": 2,
}

const NAMES := {
	CAMP: ["Raiders' Camp", "Bandit Hollow", "Outlaw Den", "Ronin Camp", "Smugglers' Camp", "Deserters' Camp",
		"Tollkeepers' Camp", "Ambush Ground", "Poachers' Camp", "Warband Camp"],
	SHRINE: ["Wayside Shrine", "Fox Shrine", "Moss Shrine", "Lantern Shrine", "Crane Shrine", "Stillwater Shrine",
		"Hilltop Shrine", "Traveller's Shrine", "Cedar Shrine", "Twin-Lantern Shrine"],
	VILLAGE: ["Farmstead", "Waystop", "Fishing Hamlet", "Charcoal Village", "Bamboo Hamlet", "Hot-Spring Village",
		"Millstream", "Ferry Landing"],
	RUIN: ["Broken Gate", "Fallen Watchpost", "Old Boundary Stones", "Toppled Shrine", "Sunken Court",
		"Burnt Waystation", "Forgotten Hall", "Leaning Pillars"],
}

## [{id, kind, name, at (Vector2), y, yaw, region, danger, seed}] (a lair also
## has "bounty": the id of who holds it).
var sites: Array[Dictionary] = []

const CELL := 128.0

var _land: ContinentLand
var _rng := RandomNumberGenerator.new()
var _grid: Dictionary = {}
var _taken: Dictionary = {}


func _init(land: ContinentLand) -> void:
	_land = land
	_rng.seed = SEED
	_plan()


## A site by id ({} for none).
func site(id: String) -> Dictionary:
	for s: Dictionary in sites:
		if s["id"] == id:
			return s
	return {}


## The sites of one kind.
func of_kind(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in sites:
		if s["kind"] == kind:
			out.append(s)
	return out


## Whether (x, z) is somewhere a site can stand, for a footprint of
## `radius`: dry, level, off the road and river and clear of lakes.
func suitable(x: float, z: float, radius := FOOTPRINT) -> bool:
	var h := _land.height_at(x, z)
	if h < ContinentLand.SEA_LEVEL + 4.0 or h > 230.0:
		return false
	for i in 8:
		var a := TAU * i / 8.0
		if absf(_land.height_at(x + cos(a) * radius, z + sin(a) * radius) - h) > LEVEL:
			return false
	if _land.roads.query(x, z).x < radius * 0.8:
		return false
	if _land.rivers.query(x, z).x < radius + 8.0:
		return false
	for lake: Dictionary in _land.lakes:
		if Vector2(x, z).distance_to(lake["at"]) < float(lake["radius"]) + radius + 20.0:
			return false
	return true


func _plan() -> void:
	var candidates: Array[Vector2] = []
	# Beside the roads: every hundred metres or so, a little off to one side
	# (the spacing rule thins them out; roads are where travellers are).
	var roadside: Array[Vector2] = []
	for path: Dictionary in _land.roads.paths:
		var pts: PackedVector2Array = path["points"]
		var gap := _rng.randf_range(20.0, 100.0)
		for i in range(1, pts.size()):
			gap -= pts[i].distance_to(pts[i - 1])
			if gap > 0.0:
				continue
			gap = _rng.randf_range(80.0, 140.0)
			var along := (pts[i] - pts[i - 1]).normalized()
			var side := Vector2(-along.y, along.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
			roadside.append(pts[i] + side * _rng.randf_range(26.0, 62.0))
	_shuffle(roadside)
	candidates.append_array(roadside)
	# Out in the wilds.
	for i in 400:
		candidates.append(Vector2(_rng.randf_range(-1900.0, 1900.0), _rng.randf_range(-1900.0, 1900.0)))
	var counts := {}
	for k in KINDS:
		counts[k] = 0
	for at: Vector2 in candidates:
		if sites.size() >= MAX_SITES:
			break
		if not _allowed(at):
			continue
		var kind := _kind_for(at, sites.size(), counts)
		var region := str(_land.nearest_region(at.x, at.y)["id"])
		var count: int = counts[kind]
		counts[kind] = count + 1
		var danger := int(DANGER.get(region, 0))
		var s := {
			"id": "site_%02d" % sites.size(), "kind": kind, "at": at,
			"y": _land.height_at(at.x, at.y), "yaw": _rng.randf() * TAU, "region": region,
			"danger": danger, "seed": _rng.randi(),
		}
		if kind == LAIR:
			var b := _take_bounty(danger)
			s["bounty"] = b["id"]
			s["name"] = b["lair"]
		else:
			var names: Array = NAMES[kind]
			s["name"] = names[count % names.size()]
		sites.append(s)
	_index()


## Whether (x, z) lies in a site's footprint (trees keep out of it).
func blocked(x: float, z: float) -> bool:
	var list: Variant = _grid.get(int(floorf(x / CELL)) * 8192 + int(floorf(z / CELL)))
	if list == null:
		return false
	for i: int in (list as PackedInt32Array):
		var s: Dictionary = sites[i]
		var at: Vector2 = s["at"]
		var dx := x - at.x
		var dz := z - at.y
		var r := float(SiteBuilder.RADIUS[s["kind"]]) + 3.0
		if dx * dx + dz * dz < r * r:
			return true
	return false


func _index() -> void:
	_grid.clear()
	for i in sites.size():
		var at: Vector2 = sites[i]["at"]
		var r := float(SiteBuilder.RADIUS[sites[i]["kind"]]) + 3.0
		for cx in range(int(floorf((at.x - r) / CELL)), int(floorf((at.x + r) / CELL)) + 1):
			for cz in range(int(floorf((at.y - r) / CELL)), int(floorf((at.y + r) / CELL)) + 1):
				var key := cx * 8192 + cz
				var list: PackedInt32Array = _grid.get(key, PackedInt32Array())
				list.append(i)
				_grid[key] = list


## The next wanted shinobi whose lair suits `danger` (any, once those run out).
func _take_bounty(danger: int) -> Dictionary:
	var fallback := {}
	for b: Dictionary in Bounties.all():
		if _taken.has(b["id"]):
			continue
		if int(b["danger"]) == danger:
			_taken[b["id"]] = true
			return b
		if fallback.is_empty():
			fallback = b
	_taken[fallback["id"]] = true
	return fallback


func _shuffle(list: Array[Vector2]) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t := list[i]
		list[i] = list[j]
		list[j] = t


func _allowed(at: Vector2) -> bool:
	if absf(at.x) > 1900.0 or absf(at.y) > 1900.0:
		return false
	for id: String in _land.regions:
		if at.distance_to(_land.region_center(id)) < REGION_CLEAR:
			return false
	for s: Dictionary in sites:
		if at.distance_to(s["at"]) < SPACING:
			return false
	return suitable(at.x, at.y)


## The pattern's kind, bent to the ground: villages want low ground by a
## road (and are favoured there), camps want to be off it.
func _kind_for(at: Vector2, index: int, counts: Dictionary) -> String:
	var kind := PATTERN[index % PATTERN.size()]
	var road := _land.roads.query(at.x, at.y).x
	var h := _land.height_at(at.x, at.y)
	if int(counts[LAIR]) < Bounties.all().size() and index % 6 == 4 and road >= 40.0:
		return LAIR
	var village_ground := road < 90.0 and h <= 90.0
	if village_ground and int(counts[VILLAGE]) < MAX_VILLAGES and index % 3 == 0:
		return VILLAGE
	if kind == VILLAGE and not village_ground:
		kind = RUIN if h > 90.0 else CAMP
	if kind == CAMP and road < 40.0:
		kind = SHRINE
	return kind
