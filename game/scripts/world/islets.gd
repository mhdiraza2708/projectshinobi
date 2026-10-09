class_name Islets
extends Node3D
## Rocky islets and sea stacks between the islands, so the sea you run across
## has something in it: a cluster or two along each route and a small one off
## every island's coast. Low grassy islets with a pine or two, tall stacks of
## rock, a shrine gate on one and a watch-tower (its lamp lit at dusk) on
## another. They're planned from fixed seeds (plan() is plain data, so every
## game and every test sees the same sea), kept well clear of a lane along
## every straight line between two islands, and solid, so you can stand on
## them. A cluster is a handful of nodes (one rock mesh, one strip of surf, a
## body, its trees and landmark), faded out when far away.

const MODELS := Island.MODELS
## Half the width of the open lane kept along every line between two island
## centres, beyond an outcrop's own radius (metres).
const LANE := 26.0
## Open water kept between an outcrop and an island's surf.
const ISLAND_GAP := 30.0
## Clusters stay at least this far from each other.
const CLUSTER_APART := 110.0
## Outcrops in a cluster keep this much water between them.
const WATER_BETWEEN := 4.0
## Rock stays drawn this far; trees and landmarks a shorter way.
const RANGE := 1600.0
const SCENERY_RANGE := 440.0
## Where the clusters along the routes go: a hint at how far along (0-1) and
## which side of the line, with a landmark for two of them. The planner picks
## the exact spot from a seed.
const ROUTES := [
	{"from": "emberwood", "to": "autumn_wood", "t": 0.5, "side": 1.0, "feature": "shrine"},
	{"from": "emberwood", "to": "ashen_pass", "t": 0.5, "side": -1.0, "feature": ""},
	{"from": "emberwood", "to": "old_dam", "t": 0.5, "side": -1.0, "feature": "watchtower"},
	{"from": "ashen_pass", "to": "old_dam", "t": 0.5, "side": 1.0, "feature": ""},
	{"from": "autumn_wood", "to": "frozen_road", "t": 0.5, "side": 1.0, "feature": ""},
	{"from": "old_dam", "to": "frozen_road", "t": 0.5, "side": -1.0, "feature": ""},
	{"from": "old_dam", "to": "five_winds", "t": 0.5, "side": 1.0, "feature": ""},
	{"from": "frozen_road", "to": "five_winds", "t": 0.5, "side": -1.0, "feature": ""},
]
## The watch-tower's lamp, lit or not (emission strength).
const LAMP_ON := 4.0
const LAMP_OFF := 0.12

## Lanterns on the islets, for the night lights (like Island.lanterns).
var lanterns: Array[Node3D] = []
## Every cluster's node, by plan index, and the plan they were built from.
var clusters: Array[Node3D] = []
var plan_data: Array[Dictionary] = []

var _lamp: StandardMaterial3D
var _lamp_light: OmniLight3D
var _glow: MeshInstance3D
static var _parts_cache: Dictionary = {}
static var _material_cache: Dictionary = {}


# --- The plan ------------------------------------------------------------------------

## Every cluster, in order: {index, at (x, z in the archipelago), near (the
## closest island), outcrops: [{at, radius, height, style ("islet" or
## "stack"), flat, seed, feature}]}. Nothing but the layout and fixed seeds
## goes in, so the same sea comes out every time.
static func plan() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in ROUTES.size():
		var route: Dictionary = ROUTES[r]
		var a: Vector2 = Archipelago.LAYOUT[route["from"]]
		var b: Vector2 = Archipelago.LAYOUT[route["to"]]
		var perp := (b - a).normalized().orthogonal()
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s>%s" % [route["from"], route["to"]])
		for attempt in 160:
			var t := clampf(float(route["t"]) + rng.randf_range(-0.14, 0.14), 0.22, 0.78)
			var side := float(route["side"]) * (1.0 if attempt < 80 else -1.0)
			var at := a.lerp(b, t) + perp * side * rng.randf_range(46.0, 120.0)
			var cluster := _cluster(out.size(), at, _compose(str(route["feature"]), r, rng), out)
			if not cluster.is_empty():
				out.append(cluster)
				break
	# And a small one off each island's own shore: the coast reads better
	# with something standing in the surf.
	for id: String in Archipelago.LAYOUT:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(id + "stacks")
		var centre: Vector2 = Archipelago.LAYOUT[id]
		var start := rng.randf() * TAU
		for attempt in 48:
			var ang := start + attempt * TAU / 24.0 * (1.0 if attempt % 2 == 0 else -1.0)
			var reach := float(Island.PRESETS[id]["coast"]) * 1.12 + ISLAND_GAP + rng.randf_range(10.0, 34.0)
			var at := centre + Vector2.from_angle(ang) * reach
			var cluster := _cluster(out.size(), at, _compose("coast", out.size(), rng), out)
			if not cluster.is_empty():
				out.append(cluster)
				break
	return out


## Every outcrop of the plan in one list.
static func outcrops(clusters_plan := plan()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Dictionary in clusters_plan:
		out.append_array(c["outcrops"])
	return out


## A cluster at `at` made of `parts` (outcrops with `at` relative to the
## cluster's middle), or {} if the main one doesn't fit there. Satellites
## that don't fit are left out.
static func _cluster(index: int, at: Vector2, parts: Array[Dictionary], placed: Array[Dictionary]) -> Dictionary:
	for c: Dictionary in placed:
		if (c["at"] as Vector2).distance_to(at) < CLUSTER_APART:
			return {}
	var kept: Array[Dictionary] = []
	for p: Dictionary in parts:
		var o := p.duplicate()
		o["at"] = at + (p["at"] as Vector2)
		if not fits(o["at"], float(o["radius"])):
			if kept.is_empty():
				return {}
			continue
		if kept.any(func(q: Dictionary) -> bool:
				return (q["at"] as Vector2).distance_to(o["at"]) < float(q["radius"]) + float(o["radius"]) + WATER_BETWEEN):
			continue
		kept.append(o)
	return {"index": index, "at": at, "near": nearest_island(at), "outcrops": kept}


## An outcrop of `radius` here keeps clear of every island and of the lane
## between every pair of them.
static func fits(at: Vector2, radius: float) -> bool:
	var ids: Array = Archipelago.LAYOUT.keys()
	for i in ids.size():
		var centre: Vector2 = Archipelago.LAYOUT[ids[i]]
		if at.distance_to(centre) < float(Island.PRESETS[ids[i]]["coast"]) * 1.12 + ISLAND_GAP + radius:
			return false
		for j in range(i + 1, ids.size()):
			var q := Geometry2D.get_closest_point_to_segment(at, centre, Archipelago.LAYOUT[ids[j]])
			if at.distance_to(q) < LANE + radius:
				return false
	return true


## The direction (unit) from `at` to the closest point on any lane between
## two islands: where the traffic passes.
static func toward_lane(at: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	var ids: Array = Archipelago.LAYOUT.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var q := Geometry2D.get_closest_point_to_segment(at, Archipelago.LAYOUT[ids[i]], Archipelago.LAYOUT[ids[j]])
			if at.distance_to(q) < best_d:
				best_d = at.distance_to(q)
				best = q - at
	return best.normalized()


static func nearest_island(at: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id: String in Archipelago.LAYOUT:
		var d := at.distance_to(Archipelago.LAYOUT[id])
		if d < best_d:
			best_d = d
			best = id
	return best


## The outcrops of one cluster, the main one at its middle and the rest
## around it. `variant` mixes the plain clusters up (a tall stack with an
## islet beside it, or an islet with stacks standing behind).
static func _compose(feature: String, variant: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var main := {}
	var satellites: Array[Dictionary] = []
	match feature:
		"shrine":
			main = _outcrop("islet", rng.randf_range(13.5, 14.5), rng.randf_range(3.8, 4.2), rng, "shrine")
			satellites = [_outcrop("stack", rng.randf_range(4.5, 5.5), rng.randf_range(15.0, 19.0), rng),
				_outcrop("stack", rng.randf_range(2.6, 3.4), rng.randf_range(6.0, 9.0), rng)]
		"watchtower":
			main = _outcrop("islet", rng.randf_range(11.5, 12.5), rng.randf_range(3.8, 4.4), rng, "watchtower")
			satellites = [_outcrop("stack", rng.randf_range(4.0, 5.0), rng.randf_range(11.0, 14.0), rng),
				_outcrop("islet", rng.randf_range(2.6, 3.4), rng.randf_range(1.4, 2.4), rng)]
		"coast":
			main = _outcrop("stack", rng.randf_range(3.6, 5.2), rng.randf_range(9.0, 16.0), rng)
			satellites = [_outcrop("islet", rng.randf_range(2.2, 3.6), rng.randf_range(1.2, 2.6), rng)]
			if rng.randf() < 0.5:
				satellites.append(_outcrop("stack", rng.randf_range(2.2, 3.0), rng.randf_range(4.0, 7.0), rng))
		_:
			if variant % 2 == 0:
				main = _outcrop("stack", rng.randf_range(4.8, 6.4), rng.randf_range(15.0, 22.0), rng)
				satellites = [_outcrop("islet", rng.randf_range(9.0, 12.0), rng.randf_range(2.8, 3.8), rng),
					_outcrop("stack", rng.randf_range(2.6, 3.8), rng.randf_range(5.0, 10.0), rng)]
			else:
				main = _outcrop("islet", rng.randf_range(10.0, 13.0), rng.randf_range(3.0, 4.0), rng)
				satellites = [_outcrop("stack", rng.randf_range(4.0, 5.6), rng.randf_range(12.0, 18.0), rng),
					_outcrop("stack", rng.randf_range(2.4, 3.4), rng.randf_range(4.0, 8.0), rng)]
			if rng.randf() < 0.6:
				satellites.append(_outcrop("islet", rng.randf_range(2.2, 3.2), rng.randf_range(1.4, 2.6), rng))
	main["at"] = Vector2.ZERO
	out.append(main)
	var angle := rng.randf() * TAU
	for s in satellites:
		angle += rng.randf_range(1.7, 2.6)
		s["at"] = Vector2.from_angle(angle) * (float(main["radius"]) + float(s["radius"]) + rng.randf_range(5.0, 12.0))
		out.append(s)
	return out


static func _outcrop(style: String, radius: float, height: float, rng: RandomNumberGenerator, feature := "") -> Dictionary:
	return {"style": style, "radius": radius, "height": height, "seed": rng.randi(), "feature": feature,
		# A top you can stand on: every islet, and the broad low stacks.
		"flat": style == "islet" or (radius >= 3.8 and height <= 14.0),
		# Stacks lean a little, the top out of line with the foot (x, z).
		"lean": Vector2.from_angle(rng.randf() * TAU) * radius * rng.randf_range(0.0, 0.22) if style == "stack" else Vector2.ZERO}


# --- Building -------------------------------------------------------------------------

func build() -> void:
	name = "Islets"
	plan_data = plan()
	for c: Dictionary in plan_data:
		clusters.append(_build_cluster(c))


func _build_cluster(c: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "Cluster%d" % int(c["index"])
	var at: Vector2 = c["at"]
	node.position = Vector3(at.x, Archipelago.SEA_LEVEL, at.y)
	add_child(node)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = Combat.LAYER_WORLD
	body.collision_mask = 0
	node.add_child(body)
	var rock := SurfaceTool.new()
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)
	var surf := SurfaceTool.new()
	surf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var island: String = c["near"]
	var trees: Array[Transform3D] = []
	var tree_name := tree_for(island)
	for o: Dictionary in c["outcrops"]:
		var rel: Vector2 = (o["at"] as Vector2) - at
		var shape := ConvexPolygonShape3D.new()
		shape.points = _add_outcrop(rock, surf, o, rel)
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		match str(o["feature"]):
			"shrine":
				# Pines stand beside the shrine, wherever it faces.
				var yaw := _build_shrine(node, body, o, rel)
				var behind := Basis(Vector3.UP, yaw)
				var spots: Array[Vector2] = []
				for back: Vector3 in [Vector3(-6.6, 0, -2.0), Vector3(6.8, 0, -3.4)]:
					var p := behind * back
					spots.append(Vector2(p.x, p.z))
				trees.append_array(_trees_at(o, rel, spots, body, 0.9))
			"watchtower":
				_build_watchtower(node, rel, float(o["height"]))
				trees.append_array(_trees_at(o, rel, [Vector2(5.0, 3.0), Vector2(-4.2, 4.6)], body, 0.8))
			_:
				if bool(o["flat"]) and float(o["radius"]) >= 7.0:
					trees.append_array(_trees_at(o, rel, [], body, 1.0))
				elif bool(o["flat"]) and o["style"] == "stack":
					trees.append_array(_trees_at(o, rel, [Vector2(0.4, 0.2)], body, 0.8))
	var rock_mesh := rock.commit()
	rock_mesh.surface_set_material(0, rock_material(island))
	var mi := MeshInstance3D.new()
	mi.name = "Rock"
	mi.mesh = rock_mesh
	mi.visibility_range_end = RANGE
	mi.visibility_range_end_margin = 100.0
	node.add_child(mi)
	surf.set_material(ShoreFoam.material())
	var foam := MeshInstance3D.new()
	foam.name = "Foam"
	foam.mesh = surf.commit()
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	foam.visibility_range_end = RANGE
	node.add_child(foam)
	_add_trees(node, tree_name, trees)
	return node


## Adds an outcrop's rock to `rock` and its surf to `surf` (both in the
## cluster's space, the outcrop's middle at `rel`). Returns its outline
## for collision.
static func _add_outcrop(rock: SurfaceTool, surf: SurfaceTool, o: Dictionary, rel: Vector2) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(o["seed"])
	var radius := float(o["radius"])
	var height := float(o["height"])
	var stack: bool = o["style"] == "stack"
	var sides := clampi(int(6.0 + radius * 0.7), 8, 16)
	# Rings from the sea bed up: [height, share of the radius, how ragged].
	var profile: Array
	if stack:
		profile = [[-2.5, 1.4, 0.0], [-0.7, 1.12, 0.05], [0.0, 1.0, 0.12], [height * 0.3, 0.92, 0.22],
			[height * 0.62, 0.8, 0.22], [height * 0.88, 0.7, 0.18], [height, 0.62, 0.1]]
	else:
		profile = [[-2.5, 1.5, 0.0], [-0.7, 1.14, 0.05], [0.0, 1.0, 0.1], [height * 0.34, 0.88, 0.1],
			[height * 0.7, 0.73, 0.1], [height, 0.6, 0.07]]
	var rings: Array[PackedVector3Array] = []
	var waterline := PackedFloat32Array()
	var points := PackedVector3Array()
	for k in profile.size():
		var ring := PackedVector3Array()
		var y := float(profile[k][0])
		# Craggy: the middle rings wander a little up and down.
		if k >= 3 and k < profile.size() - 1:
			y += rng.randf_range(-0.1, 0.1) * height / profile.size()
		# The lean grows toward the top.
		var shift := (o["lean"] as Vector2) * pow(clampf(y / height, 0.0, 1.0), 1.4)
		for i in sides:
			var ang := TAU * i / sides
			var r := radius * float(profile[k][1]) * (1.0 + float(profile[k][2]) * rng.randf_range(-1.0, 1.0))
			ring.append(Vector3(rel.x + shift.x + cos(ang) * r, y, rel.y + shift.y + sin(ang) * r))
			if k == 2:
				waterline.append(r)
		rings.append(ring)
		points.append_array(ring)
	var lean: Vector2 = o["lean"]
	var top := Vector3(rel.x + lean.x, height if bool(o["flat"]) else height * 1.14, rel.y + lean.y)
	points.append(top)
	var axis := Vector3(rel.x, 0.0, rel.y)
	var green: bool = bool(o["flat"])
	for k in rings.size() - 1:
		for i in sides:
			var j := (i + 1) % sides
			_tri(rock, rings[k][i], rings[k + 1][i], rings[k][j], axis, green)
			_tri(rock, rings[k][j], rings[k + 1][i], rings[k + 1][j], axis, green)
	for i in sides:
		_tri(rock, rings[-1][i], top, rings[-1][(i + 1) % sides], axis, green)
	# Surf piles up against the rock: a skirt of foam rising to it, which
	# shows from a low angle where a flat strip on the water would not.
	ShoreFoam.add_ring(surf, rel, waterline, 0.0, clampf(radius * 0.7, 3.6, 8.5), 0.3, 1.1 if stack else 0.6)
	return points


## One flat-shaded triangle, wound so it faces away from `axis`, with the
## ground weights the terrain shader reads (r grass, g dirt, b rock, a sand).
## `green`: a gentle top grows grass (or snow), otherwise it stays bare rock.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, axis: Vector3, green: bool) -> void:
	# Godot's front faces run clockwise.
	var n := -(b - a).cross(c - a)
	if n.dot((a + b + c) / 3.0 - axis) < 0.0:
		var swap := b
		b = c
		c = swap
		n = -n
	n = n.normalized()
	# Lit as if tilted up a little: cliffs get the soft grey of the sky as well
	# as the sun, and the terrain shader never sees a wall edge-on (it builds
	# its texture axes from the normal).
	var shade := (n + Vector3.UP * 0.5).normalized()
	for v: Vector3 in [a, b, c]:
		var level := smoothstep(0.55, 0.8, n.y) if green else 0.0
		# Within reach of the spray, gentle ground is sand and steep ground wet rock.
		var shore := (1.0 - smoothstep(0.25, 1.1, v.y)) * smoothstep(0.35, 0.6, n.y)
		var weights := Color(0, 0, 1, 0).lerp(Color(1, 0, 0, 0), level)
		st.set_normal(shade)
		st.set_color(weights.lerp(Color(0, 0, 0, 1), shore))
		st.add_vertex(v)


## The ground material of the rock near an island: its palette, so stacks
## off the Frozen Road wear snow and those off the Ashen Pass are grey.
static func rock_material(island: String) -> ShaderMaterial:
	if not _material_cache.has(island):
		var preset: Dictionary = Island.PRESETS[island]
		var palette := {}
		for layer in ["grass", "grass2", "dirt", "rock", "sand"]:
			palette[layer] = preset[layer]
		var mat := TerrainMaterial.make(preset.get("textures", {}), palette)
		# Wet where the sea reaches.
		mat.set_shader_parameter(&"water_level", Archipelago.SEA_LEVEL + 0.4)
		_material_cache[island] = mat
	return _material_cache[island]


## The tree an island grows most of (what to plant on its outcrops).
static func tree_for(island: String) -> String:
	for s: Dictionary in Island.PRESETS[island].get("scatter", []):
		if Island.TREES.has(s["scene"]) and s["scene"] != "bamboo":
			return s["scene"]
	return "pine"


## Where trees stand on a flat outcrop: `fixed` (offsets from its middle),
## or scattered across its top if none are given.
func _trees_at(o: Dictionary, rel: Vector2, fixed: Array, body: StaticBody3D, scale_max: float) -> Array[Transform3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(o["seed"]) + 3
	var spots: Array[Vector2] = []
	for f: Vector2 in fixed:
		spots.append(f)
	if fixed.is_empty():
		var top := float(o["radius"]) * 0.6 * 0.8
		var count := clampi(int(float(o["radius"]) / 4.5), 1, 3)
		var start := rng.randf() * TAU
		for i in count:
			spots.append(Vector2.from_angle(start + TAU * i / count) * top * rng.randf_range(0.45, 0.8))
	var out: Array[Transform3D] = []
	for s in spots:
		var size := rng.randf_range(0.65, 1.05) * scale_max
		var lean: Vector2 = o["lean"]
		var at := Vector3(rel.x + lean.x + s.x, float(o["height"]) - 0.08, rel.y + lean.y + s.y)
		out.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size), at))
		var shape := CylinderShape3D.new()
		shape.radius = 0.35 * size
		shape.height = 4.0
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = at + Vector3.UP * 2.0
		body.add_child(col)
	return out


## One MultiMesh per part of the tree model for a whole cluster.
func _add_trees(node: Node3D, tree_name: String, trees: Array[Transform3D]) -> void:
	if trees.is_empty():
		return
	for part: Array in tree_parts(tree_name):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = trees.size()
		for i in trees.size():
			mm.set_instance_transform(i, trees[i] * part[1])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Trees_" + tree_name
		mmi.multimesh = mm
		mmi.visibility_range_end = SCENERY_RANGE
		mmi.visibility_range_end_margin = 40.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		node.add_child(mmi)


## The meshes of a model and their transforms relative to its root.
static func tree_parts(scene_name: String) -> Array:
	if _parts_cache.has(scene_name):
		return _parts_cache[scene_name]
	var root: Node3D = (load(MODELS + scene_name + ".gltf") as PackedScene).instantiate()
	var out := []
	for found in root.find_children("*", "MeshInstance3D", true, false):
		var mi := found as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		out.append([mi.mesh, xf])
	root.free()
	_parts_cache[scene_name] = out
	return out


# --- Landmarks ---------------------------------------------------------------------------

## A shrine with its gate and a lantern either side of the way in, facing the
## nearest lane, on top of an islet. Returns which way it faces (yaw).
func _build_shrine(node: Node3D, body: StaticBody3D, o: Dictionary, rel: Vector2) -> float:
	var top := float(o["height"])
	# The gate looks out toward the closest passing lane.
	var best := toward_lane(o["at"])
	var yaw := atan2(best.x, best.y)
	var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(rel.x, top - 0.05, rel.y))
	_place(node, body, "shrine", frame * Transform3D(Basis.IDENTITY, Vector3(0, 0, -2.2)), 1.0, 1.8)
	_place(node, body, "gate", frame * Transform3D(Basis.IDENTITY, Vector3(0, 0, 4.6)), 1.0, 1.8)
	for side in [-1.0, 1.0]:
		var lantern := _place(node, body, "lantern", frame * Transform3D(Basis(Vector3.UP, 0.5 * side), Vector3(side * 2.5, 0, 1.9)), 1.0, 1.2)
		lanterns.append(lantern)
	return yaw


## A model of the world (Island.MODELS) set on the outcrop, with the collision
## boxes an island gives that prop. `far` scales how far it stays in view.
func _place(node: Node3D, body: StaticBody3D, scene_name: String, xf: Transform3D, size: float, far: float) -> Node3D:
	var prop: Node3D = (load(MODELS + scene_name + ".gltf") as PackedScene).instantiate()
	prop.name = scene_name.capitalize().replace(" ", "")
	prop.transform = xf
	prop.scale = Vector3.ONE * size
	node.add_child(prop)
	for mesh in prop.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		mi.visibility_range_end = SCENERY_RANGE * far
		mi.visibility_range_end_margin = 40.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for box: Array in Island.COLLIDERS.get(scene_name, []):
		var shape := BoxShape3D.new()
		shape.size = box[1] * size
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = prop.transform * Transform3D(Basis.IDENTITY, box[0])
		col.basis = col.basis.orthonormalized()
		body.add_child(col)
	return prop


## A plastered tower with a dark tiled roof and a lamp room: a beacon over
## the water. Its lamp burns from dusk (set_lamp).
func _build_watchtower(node: Node3D, rel: Vector2, top: float) -> void:
	var tower := Node3D.new()
	tower.name = "Watchtower"
	tower.position = Vector3(rel.x, top - 0.1, rel.y)
	node.add_child(tower)
	var plaster := Color(0.86, 0.82, 0.74)
	var timber := Color(0.2, 0.15, 0.12)
	var stone := Color(0.45, 0.43, 0.42)
	var slate := Color(0.17, 0.19, 0.23)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	_lathe(walls, [[0.0, 3.7, stone], [1.3, 3.4, stone], [1.3, 3.0, plaster], [7.0, 2.6, plaster], [7.0, 2.6, timber],
		[7.9, 2.55, timber], [7.9, 2.55, plaster], [15.5, 2.15, timber], [15.5, 3.1, timber], [16.1, 3.1, timber],
		[16.1, 1.9, timber], [16.5, 1.8, timber]], 8)
	# The roof, with upturned eaves, and its finial.
	_lathe(walls, [[19.6, 1.8, slate], [19.6, 3.8, slate], [20.7, 2.5, slate], [23.0, 0.2, slate], [23.0, 0.12, timber],
		[24.8, 0.02, timber]], 8)
	walls.set_material(_flat_material())
	var mi := MeshInstance3D.new()
	mi.name = "Tower"
	mi.mesh = walls.commit()
	mi.visibility_range_end = RANGE
	mi.visibility_range_end_margin = 100.0
	tower.add_child(mi)
	# The lamp room: paper windows that glow.
	var lamp := SurfaceTool.new()
	lamp.begin(Mesh.PRIMITIVE_TRIANGLES)
	_lathe(lamp, [[16.5, 1.8, Color.WHITE], [19.6, 1.8, Color.WHITE]], 8)
	_lamp = StandardMaterial3D.new()
	_lamp.albedo_color = Color(1.0, 0.86, 0.6)
	_lamp.emission_enabled = true
	_lamp.emission = Color(1.0, 0.72, 0.36)
	_lamp.emission_energy_multiplier = LAMP_OFF
	_lamp.roughness = 0.6
	lamp.set_material(_lamp)
	var lamp_mi := MeshInstance3D.new()
	lamp_mi.name = "Lamp"
	lamp_mi.mesh = lamp.commit()
	lamp_mi.visibility_range_end = RANGE
	lamp_mi.visibility_range_end_margin = 100.0
	lamp_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tower.add_child(lamp_mi)
	# A soft halo seen from far off at night, and a light on the rocks.
	var halo := QuadMesh.new()
	halo.size = Vector2(34.0, 34.0)
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_mat.no_depth_test = false
	halo_mat.disable_receive_shadows = true
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1.0, 0.8, 0.45, 0.6), Color(1.0, 0.6, 0.25, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	halo_mat.albedo_texture = tex
	halo.material = halo_mat
	_glow = MeshInstance3D.new()
	_glow.name = "Halo"
	_glow.mesh = halo
	_glow.position = Vector3(0, 18.0, 0)
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.visible = false
	tower.add_child(_glow)
	_lamp_light = OmniLight3D.new()
	_lamp_light.name = "LampLight"
	_lamp_light.light_color = Color(1.0, 0.72, 0.4)
	_lamp_light.light_energy = 2.4
	_lamp_light.omni_range = 34.0
	_lamp_light.position = Vector3(0, 18.0, 0)
	_lamp_light.visible = false
	tower.add_child(_lamp_light)
	# The base is solid (the islet's own hull carries you up to it).
	var base_col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 3.4
	cyl.height = 20.0
	base_col.shape = cyl
	base_col.position = Vector3(rel.x, top + 10.0, rel.y)
	node.get_node("Body").add_child(base_col)


## Lights or puts out the watch-tower's lamp (dusk and night).
func set_lamp(on: bool) -> void:
	if _lamp == null:
		return
	_lamp.emission_energy_multiplier = LAMP_ON if on else LAMP_OFF
	_glow.visible = on
	_lamp_light.visible = on


func lamp_lit() -> bool:
	return _glow != null and _glow.visible


static func _flat_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	return mat


## A solid of revolution: `rings` are [height, radius, colour] from the
## bottom up (the colour is for the band above a ring), `sides` round.
## Two rings at the same height make a step.
static func _lathe(st: SurfaceTool, rings: Array, sides: int) -> void:
	for k in rings.size() - 1:
		var y0 := float(rings[k][0])
		var y1 := float(rings[k + 1][0])
		var r0 := float(rings[k][1])
		var r1 := float(rings[k + 1][1])
		var color: Color = rings[k][2]
		if is_equal_approx(y0, y1) and is_equal_approx(r0, r1):
			continue
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var quad := [d0 * r0 + Vector3(0, y0, 0), d1 * r0 + Vector3(0, y0, 0),
				d1 * r1 + Vector3(0, y1, 0), d0 * r1 + Vector3(0, y1, 0)]
			# Outward (and up, for a roof or a step).
			var rise := y1 - y0
			var out := (d0 + d1).normalized()
			var n := (out * maxf(rise, 0.001) + Vector3.UP * (r0 - r1)).normalized() if rise > 0.001 else (Vector3.UP if r1 < r0 else Vector3.DOWN)
			for tri: Array in [[0, 3, 2], [0, 2, 1]]:
				var pts: Array = [quad[tri[0]], quad[tri[1]], quad[tri[2]]]
				var geometric: Vector3 = -((pts[1] as Vector3) - (pts[0] as Vector3)).cross((pts[2] as Vector3) - (pts[0] as Vector3))
				if geometric.dot(n) < 0.0:
					pts = [pts[0], pts[2], pts[1]]
				for p: Vector3 in pts:
					st.set_normal(n)
					st.set_color(color)
					st.add_vertex(p)
