class_name Continent
extends Node3D
## One huge landmass in the sea, in place of the archipelago: about SIZE
## metres each way, the same for every player (built from a seed constant,
## see ContinentLand). Terrain streams in around a target as chunks of
## several levels of detail (ContinentStreamer), dressed with trees and
## boulders by biome, with roads between the six regions, rivers and a lake,
## and the sea all round. Positions in this node's own space are "local";
## the API taking a world position converts, so the continent can be moved.
##
## Standalone for now (a prototype beside the Archipelago): add it to a
## scene, set `target` to what the terrain should follow and await start().

## The ground around start()'s position is built and solid.
signal near_ready

const SIZE := ContinentLand.SIZE
const SEA_LEVEL := ContinentLand.SEA_LEVEL
## The detailed sea follows the target in steps this big (so waves don't swim).
const SEA_STEP := 40.0
## Rivers' water: colours (sRGB), how far its ribbon reaches past the bed, and
## how many nodes make one mesh (they hide when out of range).
const RIVER_DEEP := Color("2c6b78")
const RIVER_SHALLOW := Color("5ba3a4")
const RIVER_EDGE := 3.0
const RIVER_MESH_NODES := 24
const RIVER_RANGE := 1600.0

## What the terrain follows (the player or camera).
var target: Node3D
## The sea is ground a shinobi can run on, as in the Archipelago.
var sea_is_ground := true
var land: ContinentLand
var streamer: ContinentStreamer
var material: ShaderMaterial

var _sea: MeshInstance3D
var _far_sea: MeshInstance3D
var _water: StaticBody3D
var _built := false


func _init() -> void:
	name = "Continent"
	land = ContinentLand.new()


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	land.plan_sites()
	material = make_material()
	streamer = ContinentStreamer.new()
	streamer.setup(land, material)
	streamer.near_ready.connect(func() -> void: near_ready.emit())
	add_child(streamer)
	_build_sea()
	_build_rivers()
	_build_lakes()


## The terrain material: the project's ground shader, tinted to the base
## palette, with per-vertex region colours and snow (see terrain.gdshader).
static func make_material() -> ShaderMaterial:
	var base: Dictionary = Island.PRESETS[ContinentLand.BASE_REGION]
	var palette := {}
	for layer in ["grass", "grass2", "dirt", "rock", "sand"]:
		palette[layer] = base[layer]
	var mat := TerrainMaterial.make({}, palette)
	mat.set_shader_parameter(&"water_level", SEA_LEVEL)
	mat.set_shader_parameter(&"biome_tint", ContinentLand.TINT_RANGE)
	return mat


# --- API ---------------------------------------------------------------------------------

## Ground height at (x, z) in this node's space.
func height_at(x: float, z: float) -> float:
	return land.height_at(x, z)


## What the ground is under a world position, for footsteps (grass, dirt,
## stone, sand, snow or water).
func surface_at(world_pos: Vector3) -> StringName:
	var p := to_local(world_pos)
	return land.surface_at(p.x, p.z)


## The region a world position is in ("" in the wilds between them).
func region_at(world_pos: Vector3) -> String:
	var p := to_local(world_pos)
	return land.region_at(p.x, p.z)


## Where a region stands: its pad's middle, on the ground, in world space.
func region_center(id: String) -> Vector3:
	var c := land.region_center(id)
	return to_global(Vector3(c.x, land.pad_height(id), c.y))


## The sea as ground a shinobi can run on (null when it is not ground).
func water_body() -> StaticBody3D:
	return _water


## Ids of the regions (the island ids).
func region_ids() -> PackedStringArray:
	return land.regions


## Builds the ground round the world position `near` and waits until it is
## solid. Needs to be in the tree. The terrain keeps following `target` if
## there is one (else it stays round `near`).
func start(near: Vector3) -> void:
	_build()
	streamer.begin(to_local(near))
	await near_ready


## The terrain's own statistics (chunks, instances, triangles, build times).
func stats() -> Dictionary:
	return streamer.stats()


func _process(_delta: float) -> void:
	if not _built:
		return
	var at := streamer.focus
	if target != null and is_instance_valid(target):
		at = to_local(target.global_position)
		streamer.focus = at
	_sea.position = Vector3(snappedf(at.x, SEA_STEP), SEA_LEVEL, snappedf(at.z, SEA_STEP))
	_far_sea.position = Vector3(snappedf(at.x, SEA_STEP), SEA_LEVEL - 0.08, snappedf(at.z, SEA_STEP))


# --- Water -------------------------------------------------------------------------------

func _build_sea() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = Island.WATER_SHADER
	mat.set_shader_parameter(&"deep", Archipelago.DEEP)
	mat.set_shader_parameter(&"shallow", Archipelago.SHALLOW)
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
	if sea_is_ground:
		_water = StaticBody3D.new()
		_water.name = "Water"
		_water.set_meta(&"surface", &"water")
		_water.collision_layer = Combat.LAYER_WORLD
		var col := CollisionShape3D.new()
		col.shape = WorldBoundaryShape3D.new()
		_water.add_child(col)
		_water.position.y = SEA_LEVEL
		add_child(_water)


func _water_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = Island.WATER_SHADER
	mat.set_shader_parameter(&"deep", RIVER_DEEP)
	mat.set_shader_parameter(&"shallow", RIVER_SHALLOW)
	mat.set_shader_parameter(&"swell", 0.03)
	return mat


## Each river as ribbons of water along its bed, a few dozen nodes apiece.
func _build_rivers() -> void:
	var mat := _water_material()
	var index := 0
	for path in land.rivers.paths:
		var pts: PackedVector2Array = path["points"]
		var beds: PackedFloat32Array = path["heights"]
		var widths: PackedFloat32Array = path["widths"]
		var first := 0
		while first < pts.size() - 1:
			var last := mini(first + RIVER_MESH_NODES, pts.size() - 1)
			var verts := PackedVector3Array()
			var indices := PackedInt32Array()
			for i in range(first, last + 1):
				var a := pts[maxi(i - 1, 0)]
				var b := pts[mini(i + 1, pts.size() - 1)]
				var side := (b - a).normalized().orthogonal() * (widths[i] + RIVER_EDGE)
				var y := beds[i] + ContinentLand.RIVER_DEPTH
				verts.append(Vector3(pts[i].x - side.x, y, pts[i].y - side.y))
				verts.append(Vector3(pts[i].x + side.x, y, pts[i].y + side.y))
				if i > first:
					var k := (i - first) * 2
					indices.append_array([k - 2, k - 1, k, k - 1, k + 1, k])
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_INDEX] = indices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, mat)
			var mi := MeshInstance3D.new()
			mi.name = "River%d_%d" % [index, first]
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = RIVER_RANGE
			add_child(mi)
			first = last
		index += 1


func _build_lakes() -> void:
	var mat := _water_material()
	var index := 0
	for lake in land.lakes:
		var disc := CylinderMesh.new()
		disc.top_radius = float(lake["radius"]) * 0.97
		disc.bottom_radius = disc.top_radius
		disc.height = 0.02
		disc.radial_segments = 40
		disc.rings = 1
		disc.material = mat
		var mi := MeshInstance3D.new()
		mi.name = "Lake%d" % index
		mi.mesh = disc
		var at: Vector2 = lake["at"]
		mi.position = Vector3(at.x, float(lake["level"]), at.y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = RIVER_RANGE
		add_child(mi)
		index += 1
