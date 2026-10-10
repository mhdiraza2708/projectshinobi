class_name Island
extends Node3D
## A story island: land rising out of the sea around a flat clearing where the
## fighting happens, dressed with trees, buildings and landmarks from a preset.
## Built procedurally when a chapter starts (see PRESETS and docs/STORY.md).
##
## The clearing (radius `clearing`, height 0) keeps every chapter's positions
## valid on any island. An invisible wall at `clearing` + WALK_MARGIN keeps
## everyone near the action; beyond it the island is scenery.

const WATER_SHADER := preload("res://assets/shaders/water.gdshader")
const MODELS := "res://assets/models/"
## Terrain grid: from -HALF to +HALF metres on each axis, one vertex per STEP.
const HALF := 80.0
const STEP := 1.25
const WALK_MARGIN := 16.0

## Local collision boxes per prop scene: [centre, size] in metres (Godot axes).
const COLLIDERS := {
	"gate": [[Vector3(-2, 2, 0), Vector3(0.5, 4, 0.5)], [Vector3(2, 2, 0), Vector3(0.5, 4, 0.5)]],
	"gate_broken": [[Vector3(-2, 2, 0), Vector3(0.5, 4, 0.5)], [Vector3(2, 0.9, 0), Vector3(0.5, 1.8, 0.5)],
		[Vector3(1.2, 0.25, 1.6), Vector3(5.4, 0.5, 0.5)]],
	"lantern": [[Vector3(0, 0.75, 0), Vector3(0.7, 1.5, 0.7)]],
	"house": [[Vector3(0, 2, 0.4), Vector3(6.6, 4, 5.4)]],
	"shrine": [[Vector3(0, 2, 0.6), Vector3(6.2, 4, 6.2)]],
	"pillar": [[Vector3(0, 3, 0), Vector3(1.7, 6, 1.7)]],
	"dam": [[Vector3(0, 5.5, 0), Vector3(42, 11, 4.4)]],
	"fence": [[Vector3(0, 0.6, 0), Vector3(4.1, 1.2, 0.2)]],
	"rock": [[Vector3(0, 0.5, 0), Vector3(1.6, 1, 1.3)]],
}
const TREES: PackedStringArray = ["pine", "broadleaf", "maple", "dead_tree", "snow_pine", "bamboo"]

## Everything an island can be. Colours are sRGB. Angles in degrees
## (0 = +X, 90 = +Z, the side behind the player's usual start).
const PRESETS := {
	"emberwood": {
		"name": "Emberwood",
		"seed": 11, "clearing": 22.0, "coast": 66.0, "hills": 10.0, "open_dir": 90.0, "open_low": 0.25,
		"grass": Color("5f8f3e"), "grass2": Color("4d7d35"), "dirt": Color("8c6d4b"), "rock": Color("6f6a64"),
		"sand": Color("d9c89a"), "deep": Color("1d4f66"), "shallow": Color("3f8a92"), "tufts": Color("6a9b45"),
		"far": Color("4d6680"),
		"paths": [[[[0, -20], [0, -30], [-2, -40], [-6, -52]], 3.5], [[[20, 2], [34, 6], [48, 14]], 2.5]],
		"props": [
			{"scene": "gate", "at": [0, -24]},
			{"scene": "lantern", "at": [-4.2, -22], "yaw": 57}, {"scene": "lantern", "at": [4.2, -22], "yaw": 2},
			{"scene": "lantern", "at": [-14, -4], "yaw": 25}, {"scene": "lantern", "at": [14, -4], "yaw": 20},
			{"scene": "lantern", "at": [-10, 12], "yaw": 66}, {"scene": "lantern", "at": [10, 12], "yaw": 61},
			{"scene": "house", "at": [-13, -33], "yaw": 10}, {"scene": "house", "at": [13, -34], "yaw": -12},
			{"scene": "house", "at": [-27, -20], "yaw": 60}, {"scene": "shrine", "at": [0, -44]},
			{"scene": "fence", "at": [-20, 8], "yaw": 70}, {"scene": "fence", "at": [-21.5, 4], "yaw": 80},
			{"scene": "fence", "at": [20, 8], "yaw": -70}, {"scene": "fence", "at": [21.5, 4], "yaw": -80},
			{"scene": "rock", "at": [17, 14], "scale": 1.1}, {"scene": "rock", "at": [-18, 15], "scale": 0.9},
		],
		"scatter": [
			{"scene": "pine", "count": 70, "min_r": 27.0, "max_r": 60.0, "scale": [0.9, 1.35]},
			{"scene": "broadleaf", "count": 30, "min_r": 27.0, "max_r": 58.0, "scale": [0.85, 1.2]},
			{"scene": "bamboo", "count": 14, "min_r": 26.0, "max_r": 40.0, "scale": [0.9, 1.2]},
			{"scene": "rock", "count": 16, "min_r": 25.0, "max_r": 62.0, "scale": [0.6, 1.6]},
		],
	},
	"ashen_pass": {
		"name": "Ashen Pass",
		"seed": 23, "clearing": 22.0, "coast": 62.0, "hills": 16.0, "open_dir": 100.0, "open_low": 0.35,
		"grass": Color("5b5550"), "grass2": Color("4a4541"), "dirt": Color("6e6259"), "rock": Color("3d3a39"),
		"sand": Color("7a7169"), "deep": Color("1b2a33"), "shallow": Color("33474f"), "tufts": Color("77705a"),
		"far": Color("4a4a55"), "textures": {"grass": "dirt"},
		"paths": [[[[0, -20], [0, -34], [4, -46]], 3.0]],
		"props": [
			# Burned with the rest of the pass: charred, not lacquer-bright.
			{"scene": "gate_broken", "at": [0, -24], "tint": "#57463f"},
			{"scene": "shrine", "at": [0, -38], "yaw": 4},
			{"scene": "lantern", "at": [-4.2, -21], "yaw": 57}, {"scene": "lantern", "at": [4.2, -21], "yaw": 2},
			{"scene": "lantern", "at": [-13, 6], "yaw": 25}, {"scene": "lantern", "at": [13, 6], "yaw": 20},
			{"scene": "rock", "at": [-9, -15], "scale": 1.4}, {"scene": "rock", "at": [16, -10], "scale": 1.8},
			{"scene": "rock", "at": [-17, 9], "scale": 1.2},
		],
		"scatter": [
			{"scene": "dead_tree", "count": 45, "min_r": 25.0, "max_r": 58.0, "scale": [0.8, 1.4]},
			{"scene": "rock", "count": 45, "min_r": 24.0, "max_r": 60.0, "scale": [0.8, 2.6]},
			{"scene": "pine", "count": 10, "min_r": 40.0, "max_r": 58.0, "scale": [0.7, 1.0]},
		],
	},
	"autumn_wood": {
		"name": "Autumn Wood",
		"seed": 37, "clearing": 22.0, "coast": 68.0, "hills": 8.0, "open_dir": -60.0, "open_low": 0.3,
		"grass": Color("9a8a3e"), "grass2": Color("8a6f35"), "dirt": Color("86653f"), "rock": Color("6d655c"),
		"sand": Color("d6c393"), "deep": Color("22495c"), "shallow": Color("4b8686"), "tufts": Color("b59a45"),
		"far": Color("6a5f70"),
		"paths": [[[[-48, 20], [-30, 10], [-12, 4], [12, -4], [30, -12], [50, -16]], 3.0]],
		"props": [
			{"scene": "shrine", "at": [-4, -40], "yaw": 12},
			{"scene": "gate", "at": [-2, -28], "yaw": 8},
			{"scene": "lantern", "at": [-8, -24], "yaw": 30}, {"scene": "lantern", "at": [4, -25], "yaw": 10},
			{"scene": "fence", "at": [18, 12], "yaw": -40}, {"scene": "fence", "at": [21, 9], "yaw": -50},
			{"scene": "rock", "at": [-16, -12], "scale": 1.3},
		],
		"scatter": [
			{"scene": "maple", "count": 75, "min_r": 25.0, "max_r": 62.0, "scale": [0.9, 1.4]},
			{"scene": "broadleaf", "count": 15, "min_r": 30.0, "max_r": 62.0, "scale": [0.9, 1.3]},
			{"scene": "pine", "count": 15, "min_r": 36.0, "max_r": 62.0, "scale": [0.9, 1.3]},
			{"scene": "rock", "count": 14, "min_r": 25.0, "max_r": 62.0, "scale": [0.6, 1.4]},
		],
	},
	"old_dam": {
		"name": "The Old Dam",
		"seed": 41, "clearing": 22.0, "coast": 66.0, "hills": 18.0, "open_dir": 90.0, "open_low": 0.15,
		"grass": Color("4f6b3f"), "grass2": Color("3f5a36"), "dirt": Color("6d5d4c"), "rock": Color("5a5856"),
		"sand": Color("a3977c"), "deep": Color("16384a"), "shallow": Color("2f6477"), "tufts": Color("5b7a44"),
		"far": Color("3f4b5c"),
		"carve": [{"at": [0, -60], "radius": [30, 24], "height": 4.0}, {"at": [0, -30], "radius": [9, 6], "height": -2.0}],
		"props": [
			{"scene": "dam", "at": [0, -36]},
			{"scene": "lantern", "at": [-12, -20], "yaw": 20}, {"scene": "lantern", "at": [12, -20], "yaw": -20},
			{"scene": "rock", "at": [-15, -8], "scale": 1.5}, {"scene": "rock", "at": [16, 4], "scale": 1.7},
			{"scene": "house", "at": [-26, 10], "yaw": 70},
		],
		"reservoir": {"at": [0, -60], "size": [44, 36], "height": 8.2},
		"waterfall": {"at": [0, -34.1], "width": 7.6, "top": 7.6, "bottom": -1.0},
		"scatter": [
			{"scene": "pine", "count": 60, "min_r": 26.0, "max_r": 60.0, "scale": [0.9, 1.4]},
			{"scene": "broadleaf", "count": 15, "min_r": 28.0, "max_r": 60.0, "scale": [0.8, 1.2]},
			{"scene": "rock", "count": 30, "min_r": 24.0, "max_r": 62.0, "scale": [0.8, 2.2]},
		],
	},
	"frozen_road": {
		"name": "Frozen Road",
		"seed": 53, "clearing": 22.0, "coast": 64.0, "hills": 12.0, "open_dir": 180.0, "open_low": 0.3,
		"grass": Color("e4e9ef"), "grass2": Color("cfd8e2"), "dirt": Color("b8b3ac"), "rock": Color("5c6068"),
		"sand": Color("cfd3d6"), "deep": Color("1d3c52"), "shallow": Color("5b8ea3"), "tufts": null,
		"far": Color("8a9bb0"), "textures": {"grass": "snow", "sand": "snow"},
		"paths": [[[[0, 50], [0, 30], [0, -30], [-6, -50]], 4.0]],
		"props": [
			{"scene": "lantern", "at": [-3.5, -20]}, {"scene": "lantern", "at": [3.5, -20]},
			{"scene": "lantern", "at": [-3.5, 20]}, {"scene": "lantern", "at": [3.5, 20]},
			{"scene": "lantern", "at": [-3.5, -32]}, {"scene": "lantern", "at": [3.5, -32]},
			{"scene": "gate", "at": [0, -26]},
			{"scene": "shrine", "at": [-4, -46], "yaw": 14},
			{"scene": "house", "at": [-16, 30], "yaw": 80},
			{"scene": "rock", "at": [-12, -10], "scale": 1.2}, {"scene": "rock", "at": [14, 8], "scale": 1.4},
		],
		"scatter": [
			{"scene": "snow_pine", "count": 90, "min_r": 25.0, "max_r": 60.0, "scale": [0.9, 1.5]},
			{"scene": "rock", "count": 20, "min_r": 24.0, "max_r": 60.0, "scale": [0.8, 1.8]},
		],
	},
	"five_winds": {
		"name": "Five Winds",
		"seed": 67, "clearing": 22.0, "coast": 52.0, "hills": 0.0, "open_dir": 0.0, "open_low": 1.0,
		"plateau": 28.0,
		"grass": Color("6b7a57"), "grass2": Color("5b6a4b"), "dirt": Color("8a7d6c"), "rock": Color("58565a"),
		"sand": Color("7f7a70"), "deep": Color("13283a"), "shallow": Color("27506a"), "tufts": Color("7b8a5e"),
		"far": Color("485468"),
		"props": [
			{"scene": "pillar", "at": [0, -21], "orb": "fire"},
			{"scene": "pillar", "at": [19.97, -6.49], "orb": "wind"},
			{"scene": "pillar", "at": [12.34, 16.99], "orb": "lightning"},
			{"scene": "pillar", "at": [-12.34, 16.99], "orb": "earth"},
			{"scene": "pillar", "at": [-19.97, -6.49], "orb": "water"},
			{"scene": "gate", "at": [0, -27]},
			{"scene": "shrine", "at": [0, -35]},
		],
		"scatter": [
			{"scene": "pine", "count": 14, "min_r": 27.0, "max_r": 34.0, "scale": [0.7, 1.1]},
			{"scene": "rock", "count": 24, "min_r": 24.0, "max_r": 36.0, "scale": [0.8, 2.0]},
		],
	},
}

var id := ""
var preset: Dictionary = {}
## Part of the open world (Archipelago): the shared sea and horizon replace
## this island's own, there is no invisible wall (a fight raises its own,
## ArenaWall), every tree is solid, and scenery fades out with distance.
var open_world := false
## How far scenery stays drawn in the open world (metres).
const SCENERY_RANGE := 520.0
## And the surf along its coast.
const FOAM_RANGE := 1500.0
## Lantern props, for the night lights.
var lanterns: Array[Node3D] = []
var water_level := -1.0

var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _mesh_cache: Dictionary = {}
var _paths: Array = []   # [[PackedVector2Array, width]]
var _body: StaticBody3D


static func exists(island_id: String) -> bool:
	return PRESETS.has(island_id)


static func display_name(island_id: String) -> String:
	return PRESETS[island_id]["name"] if PRESETS.has(island_id) else ""


func build(island_id: String) -> void:
	assert(PRESETS.has(island_id), "Unknown island %s" % island_id)
	id = island_id
	name = "Island_" + island_id
	preset = PRESETS[island_id]
	water_level = -1.0 - float(preset.get("plateau", 0.0))
	_noise.seed = int(preset["seed"])
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.018
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_detail.seed = int(preset["seed"]) + 7
	_detail.frequency = 0.11
	for p: Array in preset.get("paths", []):
		var pts := PackedVector2Array()
		for q: Array in p[0]:
			pts.append(Vector2(q[0], q[1]))
		_paths.append([pts, float(p[1])])

	_body = StaticBody3D.new()
	_body.name = "Ground"
	add_child(_body)
	_build_terrain()
	_build_water()
	_build_foam()
	if not open_world:
		_build_wall()
	var avoid: Array[Vector2] = []
	for prop: Dictionary in preset.get("props", []):
		avoid.append(_place_prop(prop))
	for s: Dictionary in preset.get("scatter", []):
		_scatter(s, avoid)
	if preset.get("tufts") != null:
		_build_tufts(preset["tufts"])
	if not open_world:
		_build_horizon()


# --- Shape ---------------------------------------------------------------------

## Ground height at (x, z). Exactly 0 across the clearing.
func height_at(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var clearing: float = preset["clearing"]
	var inland := smoothstep(clearing, clearing + 9.0, r)
	var detail := 0.45 * _detail.get_noise_2d(x, z) * inland
	var plateau := float(preset.get("plateau", 0.0))
	var h := 0.0
	if plateau > 0.0:
		# A summit: the land falls away in cliffs to a sea far below.
		var ang := atan2(z, x)
		var rim: float = float(preset["coast"]) * (1.0 + 0.12 * _noise.get_noise_2d(cos(ang) * 60.0, sin(ang) * 60.0))
		h = -plateau * smoothstep(rim - 10.0, rim, r) * (1.0 + 0.2 * _noise.get_noise_2d(x * 2.0, z * 2.0))
		h -= 8.0 * smoothstep(rim, rim + 20.0, r)
		h += detail * 2.0 * (1.0 - smoothstep(rim - 10.0, rim, r))
	else:
		var ang := atan2(z, x)
		var coast: float = float(preset["coast"]) * (1.0 + 0.1 * _noise.get_noise_2d(cos(ang) * 50.0, sin(ang) * 50.0))
		var open := 0.5 + 0.5 * cos(ang - deg_to_rad(float(preset["open_dir"])))
		var amp: float = float(preset["hills"]) * lerpf(1.0, float(preset["open_low"]), open * open)
		var n := 0.5 + 0.5 * _noise.get_noise_2d(x, z)
		var hill := amp * (0.3 + 0.7 * n) * inland * (1.0 - smoothstep(coast - 24.0, coast - 6.0, r))
		var base := lerpf(0.0, water_level - 6.0, smoothstep(coast - 8.0, coast + 10.0, r))
		h = base + hill + detail
	for c: Dictionary in preset.get("carve", []):
		var d := Vector2((x - c["at"][0]) / c["radius"][0], (z - c["at"][1]) / c["radius"][1]).length()
		h = lerpf(h, float(c["height"]), 1.0 - smoothstep(0.7, 1.0, d))
	return h


func walk_radius() -> float:
	return float(preset["clearing"]) + WALK_MARGIN


func _slope(x: float, z: float) -> float:
	var dx := height_at(x + 1.0, z) - height_at(x - 1.0, z)
	var dz := height_at(x, z + 1.0) - height_at(x, z - 1.0)
	return 1.0 - Vector3(-dx, 2.0, -dz).normalized().y


## What the ground is at a world position, for footsteps: the terrain layer
## that dominates there (the same blend _build_terrain paints), named as a
## Sfx surface: grass, dirt, stone, sand or snow (what the preset's textures
## make of grass and sand).
func surface_at(world_position: Vector3) -> StringName:
	var local := to_local(world_position)
	var x := local.x
	var z := local.z
	var r := sqrt(x * x + z * z)
	var clearing: float = preset["clearing"]
	var dirt := 1.0 - smoothstep(clearing - 11.0, clearing - 5.0, r + 2.0 * _detail.get_noise_2d(x * 0.5, z * 0.5))
	if not _paths.is_empty() and r > clearing - 8.0:
		dirt = lerpf(dirt, 1.0, 1.0 - smoothstep(-0.5, 0.8, _path_distance(Vector2(x, z))))
	var sand := smoothstep(water_level + 1.1, water_level + 0.3, height_at(x, z))
	var rock := smoothstep(0.28, 0.5, _slope(x, z))
	var layers := {&"rock": rock, &"sand": (1.0 - rock) * sand,
		&"dirt": (1.0 - rock) * (1.0 - sand) * dirt, &"grass": (1.0 - rock) * (1.0 - sand) * (1.0 - dirt)}
	var best := &"grass"
	for layer: StringName in layers:
		if float(layers[layer]) > float(layers[best]):
			best = layer
	var textures: Dictionary = preset.get("textures", {})
	var made_of := StringName(textures.get(String(best), String(best)))
	return &"stone" if made_of == &"rock" else made_of


func _path_distance(p: Vector2) -> float:
	var best := INF
	for path: Array in _paths:
		var pts: PackedVector2Array = path[0]
		for i in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			best = minf(best, p.distance_to(q) - float(path[1]) * 0.5)
	return best


# --- Terrain ---------------------------------------------------------------------

func _build_terrain() -> void:
	var n := int(HALF * 2.0 / STEP) + 1
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for j in n:
		var z := -HALF + j * STEP
		for i in n:
			heights[j * n + i] = height_at(-HALF + i * STEP, z)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	# Splat weights for the terrain shader: r grass, g dirt, b rock, a sand.
	const GRASS := Color(1, 0, 0, 0)
	const DIRT := Color(0, 1, 0, 0)
	const ROCK := Color(0, 0, 1, 0)
	const SAND := Color(0, 0, 0, 1)
	var clearing: float = preset["clearing"]
	for j in n:
		for i in n:
			var k := j * n + i
			var x := -HALF + i * STEP
			var z := -HALF + j * STEP
			var h := heights[k]
			var hl := heights[k - 1] if i > 0 else h
			var hr := heights[k + 1] if i < n - 1 else h
			var hd := heights[k - n] if j > 0 else h
			var hu := heights[k + n] if j < n - 1 else h
			var nrm := Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized()
			verts[k] = Vector3(x, h, z)
			normals[k] = nrm
			var r := sqrt(x * x + z * z)
			var c := GRASS.lerp(DIRT, 1.0 - smoothstep(clearing - 11.0, clearing - 5.0, r + 2.0 * _detail.get_noise_2d(x * 0.5, z * 0.5)))
			if not _paths.is_empty() and r > clearing - 8.0:
				c = c.lerp(DIRT, 1.0 - smoothstep(-0.5, 0.8, _path_distance(Vector2(x, z))))
			c = c.lerp(SAND, smoothstep(water_level + 1.1, water_level + 0.3, h))
			c = c.lerp(ROCK, smoothstep(0.28, 0.5, 1.0 - nrm.y))
			colors[k] = c
	var indices := PackedInt32Array()
	indices.resize((n - 1) * (n - 1) * 6)
	var w := 0
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			indices[w] = a
			indices[w + 1] = a + 1
			indices[w + 2] = a + n
			indices[w + 3] = a + 1
			indices[w + 4] = a + n + 1
			indices[w + 5] = a + n
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var palette := {}
	for layer in ["grass", "grass2", "dirt", "rock", "sand"]:
		palette[layer] = preset[layer]
	var mat := TerrainMaterial.make(preset.get("textures", {}), palette)
	mat.set_shader_parameter(&"water_level", water_level)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	_body.add_child(mi)

	# Collision: the same heights, in a grid of STEP-metre cells (uniformly
	# scaled, which height maps support).
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	var scaled := PackedFloat32Array()
	scaled.resize(n * n)
	for k in n * n:
		scaled[k] = heights[k] / STEP
	shape.map_data = scaled
	var col := CollisionShape3D.new()
	col.shape = shape
	col.scale = Vector3.ONE * STEP
	_body.add_child(col)


func _build_water() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter(&"deep", preset["deep"])
	mat.set_shader_parameter(&"shallow", preset["shallow"])
	# A detailed sea near the island, and a flat one out to the horizon (the
	# open world has one sea for every island).
	for part: Array in ([] if open_world else [["Sea", 700.0, 70, 0.0], ["FarSea", 12000.0, 1, -0.08]]):
		var plane := PlaneMesh.new()
		plane.size = Vector2(part[1], part[1])
		plane.subdivide_width = part[2]
		plane.subdivide_depth = part[2]
		plane.material = mat
		var sea := MeshInstance3D.new()
		sea.name = part[0]
		sea.mesh = plane
		sea.position.y = water_level + part[3]
		sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sea)
	if preset.has("reservoir"):
		var r: Dictionary = preset["reservoir"]
		var lake := PlaneMesh.new()
		lake.size = Vector2(r["size"][0], r["size"][1])
		lake.subdivide_width = 20
		lake.subdivide_depth = 20
		lake.material = mat
		var mi := MeshInstance3D.new()
		mi.name = "Reservoir"
		mi.mesh = lake
		mi.position = Vector3(r["at"][0], r["height"], r["at"][1])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	if preset.has("waterfall"):
		var f: Dictionary = preset["waterfall"]
		var fall_mat := ShaderMaterial.new()
		fall_mat.shader = WATER_SHADER
		fall_mat.set_shader_parameter(&"deep", Color(preset["shallow"]).lightened(0.35))
		fall_mat.set_shader_parameter(&"shallow", Color(0.92, 0.96, 1.0))
		fall_mat.set_shader_parameter(&"falling", 1.0)
		var sheet := QuadMesh.new()
		var height: float = float(f["top"]) - float(f["bottom"])
		sheet.size = Vector2(f["width"], height)
		sheet.material = fall_mat
		var mi := MeshInstance3D.new()
		mi.name = "Waterfall"
		mi.mesh = sheet
		mi.position = Vector3(f["at"][0], float(f["bottom"]) + height * 0.5, f["at"][1])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## The surf: a band of white foam along the waterline all the way round,
## following the coast as the height map draws it (see ShoreFoam).
func _build_foam() -> void:
	# A summit's cliffs go straight into the sea: the surf climbs them a little.
	var lift := 1.1 if float(preset.get("plateau", 0.0)) > 0.0 else 0.0
	var foam := ShoreFoam.make(ShoreFoam.trace_coast(height_at, water_level), water_level, Vector2.ZERO, ShoreFoam.REACH, lift)
	if open_world:
		foam.visibility_range_end = FOAM_RANGE
	add_child(foam)


## An invisible ring that keeps fighters near the clearing.
func _build_wall() -> void:
	var radius := walk_radius()
	var segments := 48
	var width := TAU * radius / segments + 0.4
	for s in segments:
		var ang := TAU * s / segments
		var shape := BoxShape3D.new()
		shape.size = Vector3(width, 40.0, 1.0)
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = Vector3(cos(ang) * radius, 10.0, sin(ang) * radius)
		col.rotation.y = -ang + PI * 0.5
		_body.add_child(col)


# --- Props -----------------------------------------------------------------------

## Places a landmark; returns where it stands (for scatter to keep clear of).
func _place_prop(prop: Dictionary) -> Vector2:
	var scene_name: String = prop["scene"]
	var at := Vector2(prop["at"][0], prop["at"][1])
	var node: Node3D = (load(MODELS + scene_name + ".gltf") as PackedScene).instantiate()
	node.name = scene_name.capitalize().replace(" ", "")
	var s := float(prop.get("scale", 1.0))
	node.scale = Vector3.ONE * s
	node.rotation.y = deg_to_rad(float(prop.get("yaw", 0.0)))
	node.position = Vector3(at.x, _ground_under(at, 1.5 * s), at.y)
	add_child(node)
	if prop.has("tint"):
		_tint(node, Color(str(prop["tint"])))
	if open_world:
		# Landmarks stay in view further than trees, but not across the map.
		var far := SCENERY_RANGE * (1.8 if scene_name in ["dam", "shrine", "pillar", "gate"] else 1.2)
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).visibility_range_end = far
			(mesh as MeshInstance3D).visibility_range_end_margin = 40.0
			(mesh as MeshInstance3D).visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for box: Array in COLLIDERS.get(scene_name, []):
		var shape := BoxShape3D.new()
		shape.size = box[1] * s
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = node.transform * Transform3D(Basis.IDENTITY, box[0])
		col.basis = col.basis.orthonormalized()
		_body.add_child(col)
	if scene_name == "lantern":
		lanterns.append(node)
	if prop.has("orb"):
		var element := Element.from_name(prop["orb"])
		var orb := Vfx.sphere(0.45, Vfx.glow_material(Element.color(element), 2.2, 0.95))
		orb.position = Vector3(0, 6.75, 0)
		node.add_child(orb)
		var light := OmniLight3D.new()
		light.light_color = Element.color(element)
		light.light_energy = 1.6
		light.omni_range = 9.0
		light.position = orb.position
		node.add_child(light)
	return at


## Darkens a prop's colours (its own copies of the materials): a burned
## ruin's lacquer, say.
static func _tint(node: Node3D, tint: Color) -> void:
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			if not src is BaseMaterial3D:
				continue
			var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
			m.albedo_color *= tint
			m.roughness = maxf(m.roughness, 0.95)
			mi.set_surface_override_material(i, m)


## The lowest ground under a footprint, so props never float on a slope.
func _ground_under(at: Vector2, radius: float) -> float:
	var h := height_at(at.x, at.y)
	for k in 6:
		var a := TAU * k / 6.0
		h = minf(h, height_at(at.x + cos(a) * radius, at.y + sin(a) * radius))
	return h


func _scatter(spec: Dictionary, avoid: Array[Vector2]) -> void:
	var scene_name: String = spec["scene"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id + scene_name)
	var min_r: float = spec["min_r"]
	var max_r: float = spec["max_r"]
	var placed: Array[Vector2] = []
	var xforms: Array[Transform3D] = []
	var tries := int(spec["count"]) * 10
	var is_tree := TREES.has(scene_name)
	while placed.size() < int(spec["count"]) and tries > 0:
		tries -= 1
		var r := sqrt(lerpf(min_r * min_r, max_r * max_r, rng.randf()))
		var ang := rng.randf() * TAU
		var p := Vector2(cos(ang) * r, sin(ang) * r)
		var h := height_at(p.x, p.y)
		if h < water_level + 0.5 or _slope(p.x, p.y) > 0.45:
			continue
		if not _paths.is_empty() and _path_distance(p) < 1.5:
			continue
		if avoid.any(func(q: Vector2) -> bool: return q.distance_to(p) < 5.0):
			continue
		if placed.any(func(q: Vector2) -> bool: return q.distance_to(p) < 2.6):
			continue
		placed.append(p)
		var s := rng.randf_range(spec["scale"][0], spec["scale"][1])
		xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, h - 0.08, p.y)))
		var near := open_world or r < walk_radius() + 2.0
		if is_tree and near:
			var shape := CylinderShape3D.new()
			shape.radius = 0.35 * s
			shape.height = 4.0
			var col := CollisionShape3D.new()
			col.shape = shape
			col.position = Vector3(p.x, h + 2.0, p.y)
			_body.add_child(col)
		elif scene_name == "rock" and near:
			var shape := BoxShape3D.new()
			shape.size = Vector3(1.6, 1.0, 1.3) * s
			var col := CollisionShape3D.new()
			col.shape = shape
			col.position = Vector3(p.x, h + 0.5 * s, p.y)
			_body.add_child(col)
	for part: Array in _model_meshes(scene_name):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i] * part[1])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Scatter_" + scene_name
		mmi.multimesh = mm
		if open_world:
			mmi.visibility_range_end = SCENERY_RANGE
			mmi.visibility_range_end_margin = 40.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)


## The meshes of a model and their transforms relative to its root.
func _model_meshes(scene_name: String) -> Array:
	if _mesh_cache.has(scene_name):
		return _mesh_cache[scene_name]
	var root: Node3D = (load(MODELS + scene_name + ".gltf") as PackedScene).instantiate()
	var out := []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		out.append([mi.mesh, xf])
	root.free()
	_mesh_cache[scene_name] = out
	return out


## Grass tufts around the clearing's edge and on the lower slopes.
func _build_tufts(color: Color) -> void:
	var mesh := _tuft_mesh(color)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id + "tufts")
	var xforms: Array[Transform3D] = []
	var clearing: float = preset["clearing"]
	for i in 3200:
		var r := sqrt(lerpf(pow(clearing - 4.0, 2), pow(walk_radius() + 14.0, 2), rng.randf()))
		var ang := rng.randf() * TAU
		var x := cos(ang) * r
		var z := sin(ang) * r
		var h := height_at(x, z)
		if h < water_level + 0.4 or (not _paths.is_empty() and _path_distance(Vector2(x, z)) < 0.5):
			continue
		var s := rng.randf_range(0.6, 1.3)
		xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.3), s)),
			Vector3(x, h - 0.02, z)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Tufts"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if open_world:
		# Grass tufts only matter close up.
		mmi.visibility_range_end = 140.0
		mmi.visibility_range_end_margin = 20.0
	add_child(mmi)


static func _tuft_mesh(color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in 5:
		var ang := TAU * b / 5.0 + 0.3 * b
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := dir.cross(Vector3.UP) * 0.035
		var tip := dir * 0.12 + Vector3.UP * (0.32 + 0.06 * (b % 3))
		st.set_normal(Vector3.UP)
		st.set_color(color.darkened(0.35))
		st.add_vertex(-side)
		st.add_vertex(side)
		st.set_color(color.lightened(0.15))
		st.add_vertex(tip)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.roughness = 1.0
	st.set_material(mat)
	return st.commit()


## Far-off islands on the horizon, faded by the fog.
func _build_horizon() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id + "horizon")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = preset["far"]
	mat.roughness = 1.0
	for i in 6:
		var cone := CylinderMesh.new()
		cone.top_radius = rng.randf_range(6.0, 30.0)
		cone.bottom_radius = rng.randf_range(80.0, 160.0)
		cone.height = rng.randf_range(22.0, 60.0)
		cone.radial_segments = 7
		cone.rings = 1
		cone.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		var ang := TAU * i / 6.0 + rng.randf_range(-0.35, 0.35)
		var dist := rng.randf_range(380.0, 620.0)
		mi.position = Vector3(cos(ang) * dist, water_level + cone.height * 0.5 - 6.0, sin(ang) * dist)
		mi.rotation.y = rng.randf() * TAU
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
