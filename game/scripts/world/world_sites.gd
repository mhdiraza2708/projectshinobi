class_name WorldSites
extends Node3D
## The continent's places of interest in play: builds the ones near you (and
## frees the ones behind), and keeps what you have found and finished with the
## slot. What to do at them (fight a camp, attune a shrine, take a relic) is
## OpenWorld's; this is where they stand and what state they are in.

signal discovered(site: Dictionary)
## A site's props now stand (the scene lights its lanterns if it is dusk).
signal site_built(node: SiteNode)

## Sites within this of you are built; they stay until you are KEEP_RANGE away.
const BUILD_RANGE := 560.0
const KEEP_RANGE := 860.0
## Close enough to find a place (and have it named on the map).
const FOUND_RANGE := 60.0
const RECORD := "sites"
const FOUND := "found"
const DONE := "done"

var world: ContinentWorld
var player: Node3D
var plan: ContinentSites
## id -> SiteNode of the sites that are built now.
var built: Dictionary = {}

var _since := 0.0


func _ready() -> void:
	name = "Sites"
	plan = world.continent.land.plan_sites()


func _process(delta: float) -> void:
	_since += delta
	if _since >= 0.5:
		_since = 0.0
		update()


## Builds what is near, frees what is far, and finds what is close. One
## site is built per call, so arriving somewhere never stalls.
func update() -> void:
	if player == null or world == null or not is_inside_tree():
		return
	var p := world.to_local(player.global_position)
	var here := Vector2(p.x, p.z)
	var made := false
	for s: Dictionary in plan.sites:
		var id: String = s["id"]
		var d := here.distance_to(s["at"])
		if d < BUILD_RANGE and not built.has(id) and not made:
			_build(s)
			made = true
		elif d > KEEP_RANGE and built.has(id):
			(built[id] as SiteNode).queue_free()
			built.erase(id)
		if d < FOUND_RANGE and state(id) == "":
			set_state(id, FOUND)
			discovered.emit(s)


func _build(s: Dictionary) -> void:
	var node := SiteBuilder.build(s, func(x: float, z: float) -> float: return world.continent.height_at(x, z))
	add_child(node)
	node.set_active(state(s["id"]) != DONE)
	built[s["id"]] = node
	site_built.emit(node)


## The lantern props of every built site.
func lanterns() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for id: String in built:
		out.append_array((built[id] as SiteNode).lanterns)
	return out


## Builds a site now (tests, travel).
func build_site(id: String) -> SiteNode:
	if not built.has(id):
		var s := plan.site(id)
		if s.is_empty():
			return null
		_build(s)
	return built[id]


# --- State (saved with the slot) --------------------------------------------------

## "" (not found yet), FOUND or DONE.
func state(id: String) -> String:
	return str(Game.record(RECORD, id, ""))


func set_state(id: String, value: String) -> void:
	Game.set_record(RECORD, id, value)
	if built.has(id):
		(built[id] as SiteNode).set_active(value != DONE)


func is_found(id: String) -> bool:
	return state(id) != ""


func is_done(id: String) -> bool:
	return state(id) == DONE


## How many sites of a kind are done.
func done_count(kind: String) -> int:
	var n := 0
	for s: Dictionary in plan.of_kind(kind):
		if is_done(s["id"]):
			n += 1
	return n


## The sites you have found, optionally of one kind.
func found_sites(kind := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in plan.sites:
		if is_found(s["id"]) and (kind == "" or s["kind"] == kind):
			out.append(s)
	return out


# --- Where ------------------------------------------------------------------------

## A site's middle in world space, on the ground.
func position_of(id: String) -> Vector3:
	var s := plan.site(id)
	if s.is_empty():
		return Vector3.ZERO
	var at: Vector2 = s["at"]
	return world.to_global(Vector3(at.x, float(s["y"]), at.y))


## The built site whose anchor is nearest to `point` within `reach`, among
## the given kinds: {site, node, anchor, distance} or {}.
func nearest(point: Vector3, kinds: Array, anchor: String, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	for id: String in built:
		var node: SiteNode = built[id]
		if not is_instance_valid(node) or not kinds.has(node.site["kind"]) or not node.anchors.has(anchor):
			continue
		var d := node.spot(anchor).distance_to(point)
		if d < best_d:
			best_d = d
			best = {"site": node.site, "node": node, "anchor": anchor, "distance": d}
	return best
