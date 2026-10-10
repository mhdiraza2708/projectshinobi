class_name ContinentWorld
extends Archipelago
## The open world on the continent instead of the sea of islands. The same
## places (the story islands' ids are its regions) and the same ways of
## working (focus_on, on_island, island_near...), so the story and the quests
## play on it unchanged. Each region is an Island in overlay mode: its authored
## props, rocks and colliders standing on the continent's flat pad, with the
## terrain, sea, rivers and scatter coming from the Continent.
##
## Not yet here: Five Winds' leap stones (its summit is a pad in the northern
## mountains now), islets and gulls.

var continent: Continent

var _ground_ok := false


func _init() -> void:
	name = "ContinentWorld"


func _ready() -> void:
	continent = Continent.new()
	add_child(continent)


## Where a region's pad is, in this world's space: its centre at the pad's own
## height, so a region's local y = 0 is the pad.
func offset(id: String) -> Vector3:
	var land := continent.land if continent else ContinentLand.new()
	var c := land.region_center(id)
	return Vector3(c.x, land.pad_height(id), c.y)


func layout() -> Dictionary:
	var out := {}
	for id: String in LAYOUT:
		out[id] = continent.land.region_center(id) if continent else ContinentLand.region_position(id)
	return out


## Every region's overlay, then the ground round `near` (this world's space).
func build(near := Vector3.ZERO) -> void:
	if ready_islands >= LAYOUT.size():
		built.emit()
		return
	var ids: Array = LAYOUT.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return offset(a).distance_to(near) < offset(b).distance_to(near))
	for id: String in ids:
		if not is_inside_tree():
			return
		_build_region(id)
		ready_islands += 1
		await get_tree().process_frame
	await _start_ground(near)
	built.emit()


func build_now(near := Vector3.ZERO) -> void:
	if ready_islands >= LAYOUT.size():
		return
	for id: String in LAYOUT:
		_build_region(id)
	ready_islands = LAYOUT.size()
	# The ground arrives by itself: ground_ready() waits for it.
	_start_ground(near)
	built.emit()


func ground_ready() -> void:
	while not _ground_ok and is_inside_tree():
		await get_tree().process_frame


## Waits until the streamer has built everything it wants round you (more
## than ground_ready(): the far meshes too). For screenshots and tests.
func settle(limit_seconds := 120.0) -> void:
	await ground_ready()
	var end := Time.get_ticks_msec() + int(limit_seconds * 1000.0)
	while is_inside_tree() and not continent.streamer.is_complete() and Time.get_ticks_msec() < end:
		await get_tree().process_frame


## The ground comes up where `near` is, and only then follows the player (who
## stands somewhere else until the world places them).
func _start_ground(near: Vector3) -> void:
	await continent.start(to_global(near))
	continent.target = player
	_ground_ok = true


func _build_region(id: String) -> void:
	if islands.has(id):
		return
	var c := offset(id)
	var island := Island.new()
	island.open_world = true
	island.position = c
	island.ground_at = func(x: float, z: float) -> float:
		return continent.height_at(c.x + x, c.z + z) - c.y
	island.surface_fn = func(p: Vector3) -> StringName:
		return continent.surface_at(p)
	add_child(island)
	island.build(id)
	# The island's own sea level, in its own space.
	island.water_level = SEA_LEVEL - c.y
	islands[id] = island


## The region you're in or beside ("" in the wilds between them).
func island_near(world_pos: Vector3, margin := 18.0) -> String:
	var p := to_local(world_pos)
	var near := continent.land.nearest_region(p.x, p.z)
	return str(near["id"]) if float(near["distance"]) <= ContinentLand.REGION_RADIUS + margin else ""


func on_water(body: CharacterBody3D) -> bool:
	if not body.is_on_floor():
		return false
	var water := continent.water_body()
	for i in body.get_slide_collision_count():
		if body.get_slide_collision(i).get_collider() == water:
			return true
	return false


# There are no leap stones, islets or gulls here yet.
func _build_leap_stones() -> void:
	pass


func _build_sea_life() -> void:
	pass
