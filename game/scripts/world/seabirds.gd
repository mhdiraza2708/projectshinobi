class_name Seabirds
extends MultiMeshInstance3D
## Gulls wheeling over every island and islet. All of them are one MultiMesh
## drawn in a single call; each bird's circle and wingbeat is worked out in
## the vertex shader (assets/shaders/gull.gdshader), so they cost the
## processor nothing. They go to roost at night.

const SHADER := preload("res://assets/shaders/gull.gdshader")
## Wingtip to wingtip, in metres (a little bigger than life, so they read).
const WINGSPAN := 3.0
## Metres a second along the circle.
const SPEED := Vector2(5.5, 9.0)

## Birds in the flocks added so far, each [middle (Vector3), radius, count,
## seed].
var flocks: Array[Array] = []
var count := 0

var _material: ShaderMaterial
var _tween: Tween


## A flock circling `radius` metres round `centre` (in this node's space,
## the middle of the circle: its height is where they fly).
func add_flock(centre: Vector3, radius: float, birds: int, seed_value: int) -> void:
	flocks.append([centre, radius, birds, seed_value])
	count += birds


## Makes the birds of every flock added (once, after the last add_flock).
func commit() -> void:
	name = "Seabirds"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# They fly all over the sea: never cull them with the frame.
	custom_aabb = AABB(Vector3(-2500, -50, -3000), Vector3(5000, 400, 4200))
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	var mesh := _gull_mesh()
	mesh.surface_set_material(0, _material)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	# (Every attribute is spelled out, so no renderer has to guess a default.)
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var i := 0
	for flock: Array in flocks:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(flock[3])
		var around := float(flock[1])
		var turn := 1.0 if rng.randf() < 0.5 else -1.0
		for b in int(flock[2]):
			var ring := around * rng.randf_range(0.75, 1.25)
			var rate := rng.randf_range(SPEED.x, SPEED.y) / ring * turn
			# Spread round the circle, a few going the other way.
			var phase := TAU * (float(b) + rng.randf_range(-0.2, 0.2)) / float(flock[2])
			if rng.randf() < 0.15:
				rate = -rate
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, flock[0]))
			mm.set_instance_color(i, Color.WHITE)
			mm.set_instance_custom_data(i, Color(ring, rate, phase, rng.randf_range(0.85, 1.2)))
			i += 1
	multimesh = mm


## At night the gulls are gone.
func set_night(night: bool, instant := false) -> void:
	if _material == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	if instant or not is_inside_tree():
		_material.set_shader_parameter(&"roost", 1.0 if night else 0.0)
		return
	_tween = create_tween()
	_tween.tween_property(_material, "shader_parameter/roost", 1.0 if night else 0.0, 4.0)


func roosting() -> bool:
	return _material != null and float(_material.get_shader_parameter(&"roost")) > 0.5


## A gull seen from the side: a slim body, a hooked bill, a fan of tail and
## two wings of three panels each (bowed and flapped in the shader), white
## with dark tips.
static func _gull_mesh() -> ArrayMesh:
	var white := Color(0.86, 0.87, 0.88)
	var grey := Color(0.55, 0.58, 0.62)
	var tip := Color(0.08, 0.08, 0.1)
	var bill := Color(0.95, 0.68, 0.1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := WINGSPAN * 0.5
	# Body: a flattened diamond.
	var nose := Vector3(0, 0.03, 0.5)
	var back := Vector3(0, 0.12, 0.05)
	var belly := Vector3(0, -0.1, 0.1)
	var tail := Vector3(0, 0.02, -0.5)
	var left := Vector3(-0.13, 0.0, 0.08)
	var right := Vector3(0.13, 0.0, 0.08)
	_tri(st, nose, left, back, white)
	_tri(st, nose, back, right, white)
	_tri(st, back, left, tail, white)
	_tri(st, back, tail, right, white)
	_tri(st, nose, belly, left, white)
	_tri(st, nose, right, belly, white)
	_tri(st, belly, tail, left, white)
	_tri(st, belly, right, tail, white)
	# The bill, and a fan of tail.
	_tri(st, Vector3(-0.04, 0.03, 0.46), Vector3(0.04, 0.03, 0.46), Vector3(0, 0.0, 0.72), bill)
	_tri(st, Vector3(-0.14, 0.0, -0.42), Vector3(0.14, 0.0, -0.42), Vector3(0, 0.02, -0.72), grey)
	# Wings, root to tip: leading edge in front, trailing edge behind.
	for side in [-1.0, 1.0]:
		var panels := [
			[0.12, 0.28, -0.22, white], [0.42 * half, 0.22, -0.26, white],
			[0.78 * half, 0.1, -0.3, grey], [half, -0.1, -0.38, tip]]
		for k in panels.size() - 1:
			var a: Array = panels[k]
			var b: Array = panels[k + 1]
			var a_front := Vector3(side * float(a[0]), 0.08, float(a[1]))
			var a_back := Vector3(side * float(a[0]), 0.04, float(a[2]))
			var b_front := Vector3(side * float(b[0]), 0.08, float(b[1]))
			var b_back := Vector3(side * float(b[0]), 0.04, float(b[2]))
			_quad(st, a_front, b_front, b_back, a_back, a[3], b[3])
	return st.commit()


## A triangle, wound so its normal faces up (Godot's front faces run
## clockwise); the material draws both sides.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var n := -(b - a).cross(c - a)
	if n.y < 0.0:
		var swap := b
		b = c
		c = swap
		n = -n
	n = n.normalized()
	for v: Vector3 in [a, b, c]:
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(v)


## A quad from two edges (`a`..`d` in order round it), coloured by the end
## it is nearer to.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, near: Color, far: Color) -> void:
	var tris := [[a, b, c, near, far, far], [a, c, d, near, far, near]]
	for t: Array in tris:
		var n: Vector3 = -((t[1] as Vector3) - (t[0] as Vector3)).cross((t[2] as Vector3) - (t[0] as Vector3))
		var pts: Array = [t[0], t[1], t[2]]
		var cols: Array = [t[3], t[4], t[5]]
		if n.y < 0.0:
			pts = [t[0], t[2], t[1]]
			cols = [t[3], t[5], t[4]]
			n = -n
		n = n.normalized()
		for i in 3:
			st.set_normal(n)
			st.set_color(cols[i])
			st.add_vertex(pts[i])
