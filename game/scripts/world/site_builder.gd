class_name SiteBuilder
extends RefCounted
## Builds a place of interest (a ContinentSites site) from the props the
## islands already use: a camp's barricade and fire, a village's houses, a
## shrine's gate and lanterns, a ruin's fallen pillars. Every layout is drawn
## from the site's own seed, so a site looks the same each time it is built.

## How far each kind spreads from its middle (metres): the scatter keeps
## trees out of it.
const RADIUS := {"camp": 15.0, "shrine": 11.0, "village": 30.0, "ruin": 15.0}
const SCENERY_RANGE := 560.0
const FIRE := Color("ff8a2e")


## The site as a node standing at its place (position = the site's x, y, z in
## the world's space). `height_at(x, z)` is the world's ground.
static func build(site: Dictionary, height_at: Callable) -> SiteNode:
	var node := SiteNode.new()
	node.site = site
	node.name = str(site["id"])
	var at: Vector2 = site["at"]
	node.position = Vector3(at.x, float(site["y"]), at.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site["seed"])
	var yaw := float(site["yaw"])
	var props: Array[Dictionary] = []
	match str(site["kind"]):
		ContinentSites.CAMP:
			_camp(props, node, rng)
		ContinentSites.SHRINE:
			_shrine(props, node)
		ContinentSites.VILLAGE:
			_village(props, node, rng)
		ContinentSites.RUIN:
			_ruin(props, node, rng)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = Combat.LAYER_WORLD
	node.add_child(body)
	for prop: Dictionary in props:
		_place(node, body, prop, yaw, height_at)
	# Anchors turn with the site, too.
	for key: String in node.anchors.keys():
		var a: Vector3 = node.anchors[key]
		node.anchors[key] = _ground_point(node, a, yaw, height_at)
	return node


# --- The layouts (x, z in metres from the middle; they turn with the site) -------

static func _camp(props: Array[Dictionary], node: SiteNode, rng: RandomNumberGenerator) -> void:
	node.anchors["fire"] = Vector3.ZERO
	for i in 6:
		var a := TAU * i / 6.0
		props.append({"scene": "rock", "at": Vector2(cos(a), sin(a)) * 1.5, "scale": 0.3, "yaw": rng.randf() * 360.0, "solid": false})
	# A barricade of fences and rocks across the way in, shacks behind it.
	for i in 3:
		props.append({"scene": "fence", "at": Vector2(-4.4 + 4.4 * i, 9.5), "yaw": 0.0})
	props.append({"scene": "house", "at": Vector2(-6.5, -5.5), "scale": 0.55, "yaw": 25.0})
	props.append({"scene": "house", "at": Vector2(6.0, -6.0), "scale": 0.5, "yaw": -35.0})
	props.append({"scene": "lantern", "at": Vector2(3.0, 3.0), "yaw": 20.0})
	for i in 4:
		var a := rng.randf_range(0.0, TAU)
		props.append({"scene": "rock", "at": Vector2(cos(a), sin(a)) * rng.randf_range(10.0, 14.0), "scale": rng.randf_range(0.8, 1.5),
			"yaw": rng.randf() * 360.0})
	for i in 2:
		var a := rng.randf_range(0.0, TAU)
		props.append({"scene": "dead_tree", "at": Vector2(cos(a), sin(a)) * rng.randf_range(9.0, 13.0), "scale": rng.randf_range(0.9, 1.2),
			"yaw": rng.randf() * 360.0, "solid": false})


static func _shrine(props: Array[Dictionary], node: SiteNode) -> void:
	node.anchors["interact"] = Vector3(0.0, 0.0, 4.5)
	props.append({"scene": "shrine", "at": Vector2(0.0, -6.0), "scale": 0.8})
	props.append({"scene": "gate", "at": Vector2(0.0, 2.0), "scale": 0.7})
	props.append({"scene": "lantern", "at": Vector2(-3.4, 5.0), "yaw": 30.0})
	props.append({"scene": "lantern", "at": Vector2(3.4, 5.0), "yaw": -30.0})
	props.append({"scene": "rock", "at": Vector2(-7.0, -2.0), "scale": 0.9, "yaw": 40.0})
	props.append({"scene": "rock", "at": Vector2(7.5, -3.0), "scale": 0.7, "yaw": 200.0})


static func _village(props: Array[Dictionary], node: SiteNode, rng: RandomNumberGenerator) -> void:
	node.anchors["board"] = Vector3(0.0, 0.0, 0.0)
	props.append({"scene": "pillar", "at": Vector2.ZERO, "scale": 0.4})
	var houses := 3 + rng.randi_range(0, 2)
	var start := rng.randf() * TAU
	for i in houses:
		var a := start + TAU * i / houses + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(15.0, 22.0)
		var p := Vector2(cos(a), sin(a)) * r
		# The door (local +z) toward the middle.
		props.append({"scene": "house", "at": p, "yaw": rad_to_deg(atan2(-p.x, -p.y)), "scale": rng.randf_range(0.95, 1.15)})
		var f := Vector2(cos(a + 0.5), sin(a + 0.5)) * (r + 7.0)
		props.append({"scene": "fence", "at": f, "yaw": rad_to_deg(-(a + 0.5)) + 90.0})
	for i in 4:
		var a := start + TAU * (i + 0.5) / 4.0
		props.append({"scene": "lantern", "at": Vector2(cos(a), sin(a)) * 7.0, "yaw": rng.randf() * 360.0})


static func _ruin(props: Array[Dictionary], node: SiteNode, rng: RandomNumberGenerator) -> void:
	node.anchors["relic"] = Vector3(0.0, 0.0, -3.5)
	props.append({"scene": "gate_broken", "at": Vector2.ZERO, "tint": Color("8a7d74")})
	for i in 3:
		var a := TAU * i / 3.0 + rng.randf_range(-0.5, 0.5)
		props.append({"scene": "pillar", "at": Vector2(cos(a), sin(a)) * rng.randf_range(6.0, 9.5), "scale": rng.randf_range(0.7, 1.1),
			"tint": Color("8a7d74"), "tilt": rng.randf_range(-0.14, 0.14), "sink": rng.randf_range(0.3, 1.2)})
	for i in 4:
		var a := rng.randf_range(0.0, TAU)
		props.append({"scene": "rock", "at": Vector2(cos(a), sin(a)) * rng.randf_range(4.0, 12.0), "scale": rng.randf_range(0.6, 1.3),
			"yaw": rng.randf() * 360.0})
	for i in 2:
		var a := rng.randf_range(0.0, TAU)
		props.append({"scene": "dead_tree", "at": Vector2(cos(a), sin(a)) * rng.randf_range(8.0, 13.0), "yaw": rng.randf() * 360.0, "solid": false})


# --- Placing ------------------------------------------------------------------------

static func _place(node: SiteNode, body: StaticBody3D, prop: Dictionary, yaw: float, height_at: Callable) -> void:
	var scene_name: String = prop["scene"]
	var local: Vector2 = (prop["at"] as Vector2).rotated(-yaw)
	var s := float(prop.get("scale", 1.0))
	var model := (load(Island.MODELS + scene_name + ".gltf") as PackedScene).instantiate() as Node3D
	model.name = scene_name.capitalize().replace(" ", "")
	model.scale = Vector3.ONE * s
	model.rotation = Vector3(float(prop.get("tilt", 0.0)), yaw + deg_to_rad(float(prop.get("yaw", 0.0))), 0.0)
	var world := Vector2(node.position.x, node.position.z) + local
	model.position = Vector3(local.x, _under(world, 1.5 * s, height_at) - node.position.y - float(prop.get("sink", 0.0)), local.y)
	node.add_child(model)
	if scene_name == "lantern":
		node.lanterns.append(model)
	if prop.has("tint"):
		Island._tint(model, prop["tint"])
	var far := SCENERY_RANGE * (1.6 if scene_name in ["shrine", "pillar", "gate"] else 1.0)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).visibility_range_end = far
		(mesh as MeshInstance3D).visibility_range_end_margin = 40.0
		(mesh as MeshInstance3D).visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if not prop.get("solid", true):
		return
	for box: Array in Island.COLLIDERS.get(scene_name, []):
		var shape := BoxShape3D.new()
		shape.size = box[1] * s
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = model.transform * Transform3D(Basis.IDENTITY, box[0])
		col.basis = col.basis.orthonormalized()
		body.add_child(col)


## The lowest ground under a footprint, so a prop never floats on a slope.
static func _under(at: Vector2, radius: float, height_at: Callable) -> float:
	var h: float = height_at.call(at.x, at.y)
	for k in 6:
		var a := TAU * k / 6.0
		h = minf(h, float(height_at.call(at.x + cos(a) * radius, at.y + sin(a) * radius)))
	return h


## An anchor's place in the node's space, turned with the site, on the ground.
static func _ground_point(node: SiteNode, a: Vector3, yaw: float, height_at: Callable) -> Vector3:
	var flat := Vector2(a.x, a.z).rotated(-yaw)
	var world := Vector2(node.position.x, node.position.z) + flat
	return Vector3(flat.x, float(height_at.call(world.x, world.y)) - node.position.y, flat.y)
