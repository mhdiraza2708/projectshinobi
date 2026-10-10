class_name Archipelago
extends Node3D
## The open world: every story island in one sea, built around you and
## travelled on foot. Shinobi run on water, so the sea between islands is
## ground (an endless plane at SEA_LEVEL), and the sprint runs faster across
## it. Five Winds is a summit: leap stones at the foot of its cliffs throw
## you up to the top and back down.
##
## Story chapters were written with their island at the world origin, so
## before one plays, focus_on() shifts the whole archipelago (and you) to put
## that island there. Nothing about a chapter changes in the open world.

signal built
## The world moved by `delta` (focus_on): anything placed in world space
## outside the archipelago should move with it.
signal rebased(delta: Vector3)

const SEA_LEVEL := -1.0
## Where each island stands, in metres across the sea. Emberwood, where the
## story begins, is home and the origin.
const LAYOUT := {
	"emberwood": Vector2(0.0, 0.0),
	"autumn_wood": Vector2(440.0, -170.0),
	"ashen_pass": Vector2(-410.0, -240.0),
	"old_dam": Vector2(-70.0, -560.0),
	"frozen_road": Vector2(410.0, -610.0),
	"five_winds": Vector2(60.0, -980.0),
}
## Sprinting on open water is this much faster (chakra-running).
const WATER_SPRINT := 1.6
## The sea's colours (sRGB).
const DEEP := Color("1d4f66")
const SHALLOW := Color("3f8a92")
## The detailed sea follows you in steps this big (so its waves don't swim).
const SEA_STEP := 40.0
## Leap stones: where they sit around Five Winds (angle in degrees, 90 = +Z,
## facing home) and how far out from its centre at the foot and the top.
const LEAP_ANGLE := 90.0
const LEAP_FOOT := 64.0
const LEAP_TOP := 40.0

var islands: Dictionary = {}
var player: Node3D
var ready_islands := 0
## The rocky islets and stacks between the islands, and the gulls over it all.
var islets: Islets
var birds: Seabirds

var _sea: MeshInstance3D
var _far_sea: MeshInstance3D
var _water: StaticBody3D
var _hour := ""
var _hour_check := 0.0


func _init() -> void:
	name = "Archipelago"


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = Island.WATER_SHADER
	mat.set_shader_parameter(&"deep", DEEP)
	mat.set_shader_parameter(&"shallow", SHALLOW)
	for part: Array in [["Sea", 900.0, 90, 0.0], ["FarSea", 16000.0, 1, -0.08]]:
		var plane := PlaneMesh.new()
		plane.size = Vector2(part[1], part[1])
		plane.subdivide_width = part[2]
		plane.subdivide_depth = part[2]
		plane.material = mat
		var sea := MeshInstance3D.new()
		sea.name = part[0]
		sea.mesh = plane
		sea.position.y = SEA_LEVEL + part[3]
		sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sea)
		if part[0] == "Sea":
			_sea = sea
		else:
			_far_sea = sea
	# The sea is ground for a shinobi.
	_water = StaticBody3D.new()
	_water.name = "Water"
	_water.set_meta(&"surface", &"water")
	_water.collision_layer = Combat.LAYER_WORLD
	var col := CollisionShape3D.new()
	col.shape = WorldBoundaryShape3D.new()
	_water.add_child(col)
	_water.position.y = SEA_LEVEL
	add_child(_water)


## Builds every island, the one nearest `near` (archipelago space) first, one
## a frame so the game never stalls for long.
func build(near := Vector3.ZERO) -> void:
	if ready_islands >= LAYOUT.size():
		built.emit()
		return
	var ids: Array = LAYOUT.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return Vector3(LAYOUT[a].x, 0, LAYOUT[a].y).distance_to(near) < Vector3(LAYOUT[b].x, 0, LAYOUT[b].y).distance_to(near))
	for id: String in ids:
		if not is_inside_tree():
			return
		_build_island(id)
		ready_islands += 1
		await get_tree().process_frame
	_build_leap_stones()
	_build_sea_life()
	built.emit()


## Builds them all at once (tests, screenshots).
func build_now() -> void:
	if ready_islands >= LAYOUT.size():
		return
	for id: String in LAYOUT:
		_build_island(id)
	ready_islands = LAYOUT.size()
	_build_leap_stones()
	_build_sea_life()
	built.emit()


func _build_island(id: String) -> void:
	if islands.has(id):
		return
	var island := Island.new()
	island.open_world = true
	island.position = offset_of(id)
	add_child(island)
	island.build(id)
	islands[id] = island


## Where an island's origin (its clearing) sits in the archipelago. A summit
## is lifted so its own sea level meets the shared one.
static func offset_of(id: String) -> Vector3:
	var at: Vector2 = LAYOUT.get(id, Vector2.ZERO)
	return Vector3(at.x, float(Island.PRESETS.get(id, {}).get("plateau", 0.0)), at.y)


## The island you're over or beside ("" out at sea).
func island_near(world_pos: Vector3, margin := 18.0) -> String:
	var p := to_local(world_pos)
	for id: String in LAYOUT:
		var c := offset_of(id)
		var coast := float(Island.PRESETS[id]["coast"])
		if Vector2(p.x - c.x, p.z - c.z).length() < coast + margin:
			return id
	return ""


## A point on an island (its own x, z) in world space, on its ground.
func on_island(id: String, local: Vector2) -> Vector3:
	var island: Island = islands.get(id)
	var h := island.height_at(local.x, local.y) if island else 0.0
	return to_global(offset_of(id) + Vector3(local.x, maxf(h, SEA_LEVEL - offset_of(id).y), local.y))


## Moves the world so `id`'s clearing is at the origin, and the player with
## it. Returns how far everything moved.
func focus_on(id: String) -> Vector3:
	var delta := -to_global(offset_of(id))
	if delta.is_zero_approx():
		return delta
	position += delta
	if player:
		player.global_position += delta
	rebased.emit(delta)
	return delta


## The player is standing on the sea (not on an island's ground).
func on_water(body: CharacterBody3D) -> bool:
	if not body.is_on_floor():
		return false
	for i in body.get_slide_collision_count():
		if body.get_slide_collision(i).get_collider() == _water:
			return true
	return false


func _process(delta: float) -> void:
	_hour_check -= delta
	if _hour_check <= 0.0:
		_hour_check = 1.0
		_follow_the_hour()
	if player == null or _sea == null:
		return
	# The detailed sea stays under you; the far sea reaches the horizon.
	var p := to_local(player.global_position)
	_sea.position = Vector3(snappedf(p.x, SEA_STEP), SEA_LEVEL, snappedf(p.z, SEA_STEP))
	_far_sea.position = Vector3(snappedf(p.x, SEA_STEP), SEA_LEVEL - 0.08, snappedf(p.z, SEA_STEP))


# --- Life on the sea ----------------------------------------------------------------

## Islets and stacks between the islands (Islets) and gulls circling over
## every island and cluster of them (Seabirds).
func _build_sea_life() -> void:
	if islets != null:
		return
	islets = Islets.new()
	add_child(islets)
	islets.build()
	birds = Seabirds.new()
	add_child(birds)
	for id: String in LAYOUT:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(id + "gulls")
		var at := offset_of(id)
		# Wheeling over the shore, above the hills.
		var middle := Vector3(at.x, at.y + rng.randf_range(15.0, 24.0), at.z)
		birds.add_flock(middle, float(Island.PRESETS[id]["coast"]) * rng.randf_range(0.55, 0.9), rng.randi_range(6, 8), rng.randi())
	for c: Dictionary in islets.plan_data:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("gulls%d" % int(c["index"]))
		var at: Vector2 = c["at"]
		var top := float((c["outcrops"][0] as Dictionary)["height"])
		birds.add_flock(Vector3(at.x, SEA_LEVEL + top + rng.randf_range(9.0, 15.0), at.y), rng.randf_range(22.0, 38.0),
			rng.randi_range(3, 4), rng.randi())
	birds.commit()
	_hour = ""
	_follow_the_hour()


## The gulls roost at night and the watch-tower's lamp burns from dusk,
## following the game scene's hour (a test scene has none).
func _follow_the_hour() -> void:
	var scene := get_parent()
	if islets == null or birds == null or scene == null or not scene.has_method(&"time_of_day"):
		return
	var hour: String = scene.time_of_day()
	if hour == _hour:
		return
	var first := _hour == ""
	_hour = hour
	birds.set_night(hour == "night", first)
	islets.set_lamp(hour == "dusk" or hour == "night")


# --- Five Winds' leap stones ------------------------------------------------------

func _build_leap_stones() -> void:
	if not LAYOUT.has("five_winds"):
		return
	var dir := Vector2(cos(deg_to_rad(LEAP_ANGLE)), sin(deg_to_rad(LEAP_ANGLE)))
	var base := offset_of("five_winds")
	var foot := base + Vector3(dir.x * LEAP_FOOT, SEA_LEVEL - base.y, dir.y * LEAP_FOOT)
	var island: Island = islands.get("five_winds")
	var top_y := island.height_at(dir.x * LEAP_TOP, dir.y * LEAP_TOP) if island else 0.0
	var top := base + Vector3(dir.x * LEAP_TOP, top_y, dir.y * LEAP_TOP)
	# Each throws you to just past the other, so you don't land on a stone.
	_leap_stone("LeapUp", foot, top - Vector3(dir.x, 0, dir.y) * 4.0)
	_leap_stone("LeapDown", top, foot + Vector3(dir.x, 0, dir.y) * 5.0)


func _leap_stone(stone_name: String, at: Vector3, to: Vector3) -> void:
	var stone := LeapStone.new()
	stone.name = stone_name
	stone.position = at
	stone.target_local = to
	add_child(stone)
