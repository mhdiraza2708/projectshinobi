class_name CharacterGear
extends RefCounted
## Ninja gear that fits any humanoid: headband / hachigane, face mask, scarf,
## a ninjato worn at the left hip (drawn into the right hand to fight) and a
## kunai pouch.
##
## Fitting is measured, not guessed: every skinned vertex is assigned to its
## dominant bone, giving the real extents of the head, torso and thigh in the
## canonical character frame (facing -Z). Gear is sized and placed from
## those, then attached to bones so it follows every pose.

const REFERENCE_HEIGHT := 1.6
const PLATE_SHADER := preload("res://assets/shaders/hitai_plate.gdshader")
## Modelled in art/blender/build_assets.py (hilt up; pouch front facing +Z).
const NINJATO := preload("res://assets/models/ninjato.gltf")
const POUCH := preload("res://assets/models/pouch.gltf")

var _skel: Skeleton3D
var _frame := Basis.IDENTITY          # canonical -> skeleton
var _regions: Dictionary = {}         # bone index -> AABB (canonical space)
## The face's own skin (VRoid "Face" mesh), without hair: masks and plates
## fit this. Zero size when the model has no separate face mesh.
var _face := AABB()
var _height := REFERENCE_HEIGHT
var _attachments: Array[Node] = []
## Every skinned vertex of the head and hair (canonical space, rest pose):
## headbands are fitted around these.
var _head_points := PackedVector3Array()
## The last headband's fitted shape (null when none is worn).
var headband: HeadbandShape
## The ninjato's parts (null when none is worn): the scabbard at the hip,
## the hilt showing from it while sheathed, the drawn blade in the right
## hand, and a marker on the sheathed grip (where the hand goes to draw).
var scabbard: Node3D
var sheathed_hilt: Node3D
var sword: Node3D
var hilt_grip: Node3D
var _drawn := false


func bind(skeleton: Skeleton3D, canonical_to_skeleton: Basis) -> void:
	_skel = skeleton
	_frame = canonical_to_skeleton
	var head_points: Array = []
	_regions = measure_regions(skeleton, _frame, head_points)
	_head_points = PackedVector3Array(head_points)
	_face = measure_face(skeleton, _frame)
	var head := region(&"Head")
	var foot_y := INF
	for foot in [&"LeftFoot", &"RightFoot", &"LeftToes", &"RightToes"]:
		var r := region(foot)
		if r.size != Vector3.ZERO:
			foot_y = minf(foot_y, r.position.y)
	if head.size != Vector3.ZERO and foot_y < INF:
		_height = head.end.y - foot_y


## Canonical-space extents of the vertices a bone dominates (zero size if none).
func region(bone_name: StringName) -> AABB:
	var i := _skel.find_bone(bone_name)
	return _regions.get(i, AABB())


func character_height() -> float:
	return _height


## Canonical-space bounds of the face skin: surfaces of a mesh named Face*
## whose material is skin. Hair is excluded, so gear fits the face itself.
static func measure_face(skel: Skeleton3D, frame: Basis) -> AABB:
	var to_canonical := frame.inverse()
	var out := AABB()
	var first := true
	for node in skel.find_children("Face*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.has_meta(&"gear"):
			continue
		var to_skel := skel.global_transform.affine_inverse() * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat == null or CharacterStyler.classify(mat.resource_name) != "skin":
				continue
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p := to_canonical * (to_skel * v)
				if first:
					out = AABB(p, Vector3.ZERO)
					first = false
				else:
					out = out.expand(p)
	return out


## The face bounds, or `head` when the model has no separate face.
func face_or(head: AABB) -> AABB:
	return _face if _face.size.x > 0.05 else head


## `head_points`, when given, also receives every vertex that the Head bone
## or anything below it (hair joints) dominates.
static func measure_regions(skel: Skeleton3D, frame: Basis, head_points = null) -> Dictionary:
	var to_canonical := frame.inverse()
	var regions := {}
	var rests: Array[Transform3D] = []
	for b in skel.get_bone_count():
		rests.append(skel.get_bone_global_rest(b))
	var head_bone := skel.find_bone(&"Head")
	var under_head := PackedByteArray()
	under_head.resize(skel.get_bone_count())
	for b in skel.get_bone_count():
		var walk := b
		while walk >= 0:
			if walk == head_bone:
				under_head[b] = 1
				break
			walk = skel.get_bone_parent(walk)
	for node in skel.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.skin == null or mi.has_meta(&"gear"):
			continue
		var skin := mi.skin
		var bind_bone: Array[int] = []
		var bind_xf: Array[Transform3D] = []
		for bi in skin.get_bind_count():
			var bone := skin.get_bind_bone(bi)
			if bone < 0:
				bone = skel.find_bone(skin.get_bind_name(bi))
			bind_bone.append(bone)
			bind_xf.append(rests[bone] * skin.get_bind_pose(bi) if bone >= 0 else Transform3D.IDENTITY)
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if bones == null or weights == null or verts.is_empty():
				continue
			var per := floori(float(bones.size()) / verts.size())
			for v in verts.size():
				var best := 0
				for k in range(1, per):
					if weights[v * per + k] > weights[v * per + best]:
						best = k
				var bi: int = bones[v * per + best]
				if bi < 0 or bi >= bind_bone.size() or bind_bone[bi] < 0:
					continue
				var p := to_canonical * (bind_xf[bi] * verts[v])
				var bone: int = bind_bone[bi]
				if head_points != null and head_bone >= 0 and under_head[bone] == 1:
					head_points.append(p)
				if regions.has(bone):
					regions[bone] = (regions[bone] as AABB).expand(p)
				else:
					regions[bone] = AABB(p, Vector3.ZERO)
	return regions


## Removes existing gear and builds what the profile asks for.
func rebuild(settings: Dictionary) -> void:
	clear()
	var head := region(&"Head")
	if head.size == Vector3.ZERO:
		return
	var k := _height / REFERENCE_HEIGHT * float(settings.get("gear_scale", 1.0))
	var lift := float(settings.get("gear_lift", 0.0)) * head.size.y
	var rx := head.size.x * 0.5
	var rz := head.size.z * 0.5
	var c := head.get_center()

	var face := face_or(head)
	headband = null
	var kind: String = settings.get("headband", "none")
	if kind != "none":
		_attach(&"Head", _build_headband(kind, settings, head, face, k, lift))

	if settings.get("mask", false):
		# Cloth over the nose and mouth, snug to the face (not the hair).
		var fc := face.get_center()
		var mask_rx := face.size.x * 0.5 * 1.04
		var mask_rz := face.size.z * 0.55 if face != head else rz * 1.04
		var mask := _ring(mask_rx, mask_rz, face.size.y * 0.3, settings["mask_color"])
		var mask_z := face.position.z + mask_rz * 0.98 if face != head else c.z - head.size.z * 0.03
		mask.position = Vector3(fc.x, face.position.y + face.size.y * 0.2, mask_z)
		_attach(&"Head", mask)

	if settings.get("scarf", false) and _skel.find_bone(&"Neck") >= 0:
		var neck := _to_canonical(_skel.get_bone_global_rest(_skel.find_bone(&"Neck")).origin)
		# Snug around the measured neck; fall back to a fraction of head width.
		var neck_region := region(&"Neck")
		var neck_r := maxf(neck_region.size.x, neck_region.size.z) * 0.5 * 1.15 \
			if neck_region.size != Vector3.ZERO else rx * 0.45
		var tube := 0.015 * k
		var scarf := Node3D.new()
		scarf.position = Vector3(neck.x, neck.y + 0.005 * k, neck_region.get_center().z if neck_region.size != Vector3.ZERO else neck.z)
		var torus := TorusMesh.new()
		torus.inner_radius = neck_r
		torus.outer_radius = neck_r + tube * 2.0
		torus.rings = 24
		torus.ring_segments = 10
		scarf.add_child(_mesh(torus, settings["scarf_color"]))
		for side in [-1.0, 1.0]:
			var tail := _box(Vector3(0.07, 0.3, 0.012) * k, settings["scarf_color"])
			tail.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)) * Basis(Vector3.FORWARD, deg_to_rad(6.0 * side)),
				Vector3(0.045 * side * k, -0.16 * k, neck_r + tube * 2.0))
			scarf.add_child(tail)
		_attach(&"Neck", scarf)

	if settings.get("back", "none") == "ninjato":
		_build_ninjato(k)

	var thigh := region(&"RightUpperLeg")
	if settings.get("pouch", false) and thigh.size != Vector3.ZERO:
		var pouch: Node3D = POUCH.instantiate()
		Toon.apply(pouch, 0.004)
		# Front (flap and stud) facing out from the thigh.
		pouch.transform = Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * 0.65 * k),
			Vector3(thigh.end.x + 0.02 * k, thigh.get_center().y + thigh.size.y * 0.12, thigh.get_center().z))
		_attach(&"RightUpperLeg", pouch)


## A cloth band fitted round the head and hair, knotted at the back with two
## tails that swing; "hachigane" adds a curved steel plate on the forehead.
func _build_headband(kind: String, settings: Dictionary, head: AABB, face: AABB, k: float, lift: float) -> Node3D:
	var color: Color = settings["headband_color"]
	var scale := float(settings.get("gear_scale", 1.0))
	var measured := face != head
	# Across the forehead, above the brows (the face mesh runs chin to hairline).
	var y := (face.position.y + face.size.y * 0.76 if measured else head.position.y + head.size.y * 0.72) + lift
	var axis := Vector2(face.get_center().x if measured else head.get_center().x, head.get_center().z)
	var half := Vector2(head.size.x * 0.5, head.size.z * 0.5)
	# Lower at the back, under the curve of the skull.
	var drop := 0.05 * k
	var shape: HeadbandShape
	if _head_points.size() > 500:
		shape = HeadbandShape.fit(_head_points, axis, y, drop, 0.018 * k, half)
	else:
		shape = HeadbandShape.ellipse(axis, y, drop, half * 1.02)
	if not is_equal_approx(scale, 1.0):
		for i in shape.radii.size():
			shape.radii[i] *= scale
	headband = shape

	var root := Node3D.new()
	root.name = "Headband"
	var band_h := 0.034 * k
	var thick := 0.006 * k
	var band := MeshInstance3D.new()
	band.name = "Band"
	band.mesh = shape.band_mesh(band_h, thick)
	var cloth := Toon.flat(color, 0.95)
	cloth.vertex_color_use_as_albedo = true
	cloth.next_pass = Toon.outline(0.0025)
	band.material_override = cloth
	root.add_child(band)

	# The knot at the back: two lobes and the wrap between them.
	var back := shape.point(PI, thick * 1.2)
	var outward := HeadbandShape.direction(PI)
	var knot_mat := Toon.flat(color.darkened(0.12), 0.95)
	knot_mat.next_pass = Toon.outline(0.002)
	for lobe_at: Array in [[-1.0, Vector3(1.0, 0.75, 0.55)], [1.0, Vector3(1.0, 0.75, 0.55)], [0.0, Vector3(0.6, 0.9, 0.7)]]:
		var ball := SphereMesh.new()
		ball.radius = 0.014 * k
		ball.height = 0.028 * k
		ball.radial_segments = 12
		ball.rings = 6
		var lobe := MeshInstance3D.new()
		lobe.mesh = ball
		lobe.material_override = knot_mat
		lobe.scale = lobe_at[1]
		lobe.position = back + outward * 0.006 * k + Vector3(float(lobe_at[0]) * 0.016 * k, 0, 0)
		root.add_child(lobe)
	for side in [-1.0, 1.0]:
		var tail := GearRibbon.new()
		tail.name = "TailLeft" if side < 0.0 else "TailRight"
		tail.anchor = back + outward * 0.008 * k + Vector3(side * 0.008 * k, -0.006 * k, 0)
		tail.head_center = Vector3(axis.x, y - 0.06 * k, axis.y)
		tail.head_radius = shape.radius_at(PI) * 0.97
		tail.length = (0.13 if side < 0.0 else 0.105) * k
		tail.width = 0.026 * k
		tail.side = side
		tail.color = color.darkened(0.04)
		root.add_child(tail)

	if kind == "hachigane":
		var plate_w := (face.size.x if measured else head.size.x * 0.8) * 0.66 * scale
		var plate_h := 0.05 * k
		var half_angle := plate_w * 0.5 / (shape.radius_at(0.0) + thick)
		var plate := MeshInstance3D.new()
		plate.name = "Plate"
		plate.mesh = shape.plate_mesh(half_angle, plate_h, 0.005 * k, thick * 1.05)
		var steel := ShaderMaterial.new()
		steel.shader = PLATE_SHADER
		steel.set_shader_parameter(&"aspect", plate_w / plate_h)
		steel.next_pass = Toon.outline(0.002)
		plate.material_override = steel
		root.add_child(plate)
	return root


## The bone attachments currently holding gear (excludes the model's own).
func attachments() -> Array[BoneAttachment3D]:
	var out: Array[BoneAttachment3D] = []
	for n in _attachments:
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			out.append(n)
	return out


func clear() -> void:
	for n in _attachments:
		if is_instance_valid(n):
			n.queue_free()
	_attachments.clear()
	scabbard = null
	sheathed_hilt = null
	sword = null
	hilt_grip = null


# --- The ninjato -----------------------------------------------------------------

## Surfaces of the ninjato model (art/blender/build_assets.py): the lacquered
## scabbard, the steel guard, the wrapped grip, the leather cord.
const SCABBARD_SURFACES := [0, 3]
const HILT_SURFACES := [1, 2]
## Model units (hilt up, +Y): the guard's face and the middle of the grip.
const GUARD_Y := 0.157
const GRIP_Y := 0.29
## The blade the scabbard hides, in model units below the guard.
const BLADE_LENGTH := 0.6
const BLADE_COLOR := Color("cdd3db")


func has_sword() -> bool:
	return sword != null and is_instance_valid(sword)


func is_drawn() -> bool:
	return _drawn and has_sword()


## Out in the right hand, or home in the scabbard.
func set_drawn(drawn: bool) -> void:
	_drawn = drawn
	if not has_sword():
		return
	sword.visible = drawn
	sheathed_hilt.visible = not drawn


## Scabbard through the belt at the left hip (hilt forward, edge up, the way
## a katana is worn), and the drawn blade fitted to the right hand's grip.
func _build_ninjato(k: float) -> void:
	var hips := _merged([&"Hips"])
	var hand := _skel.find_bone(&"RightHand")
	if hips.size == Vector3.ZERO or hand < 0:
		return
	var source := (NINJATO.instantiate() as Node3D)
	var mesh := (source.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	source.free()
	var scale := 0.86 * k

	# Worn: the hilt just in front of the left hip at the belt, the scabbard
	# running back, down and out past the hip.
	var along := HumanoidPoser.SCABBARD.normalized()
	var side := (Vector3(-0.3, -1.0, 0.0) - along * Vector3(-0.3, -1.0, 0.0).dot(along)).normalized()
	var worn := Basis(side, along, side.cross(along)).scaled(Vector3.ONE * scale)
	var guard := Vector3(hips.position.x + 0.03 * k, hips.end.y - hips.size.y * 0.3, hips.position.z + 0.01 * k)
	var at := Transform3D(worn, guard - worn * Vector3(0, GUARD_Y, 0))
	scabbard = _part(mesh, SCABBARD_SURFACES)
	scabbard.name = "Scabbard"
	scabbard.transform = at
	sheathed_hilt = _part(mesh, HILT_SURFACES)
	sheathed_hilt.name = "SheathedHilt"
	sheathed_hilt.transform = at
	hilt_grip = Marker3D.new()
	hilt_grip.name = "HiltGrip"
	hilt_grip.position = Vector3(0, GRIP_Y, 0)
	sheathed_hilt.add_child(hilt_grip)
	_attach(&"Hips", scabbard)
	_attach(&"Hips", sheathed_hilt)

	# Drawn: the grip through the curled fingers, the blade out past the
	# thumb, the edge facing the knuckles. Measured on this rig's resting
	# hand, so it holds on any rig.
	sword = _part(mesh, HILT_SURFACES)
	sword.name = "Katana"
	var blade := _mesh(_blade_mesh(), BLADE_COLOR, true, true)
	blade.name = "Blade"
	sword.add_child(blade)
	sword.transform = _grip_in_hand(scale)
	_attach(&"RightHand", sword)
	set_drawn(_drawn)


## The drawn sword's place in canonical space with the right hand at rest.
func _grip_in_hand(scale: float) -> Transform3D:
	var to_canon := _frame.inverse()
	var hand := _skel.get_bone_global_rest(_skel.find_bone(&"RightHand")).origin
	# T-posed right hand: fingers out to the right, thumb forward.
	var fingers := Vector3.RIGHT
	var thumb := Vector3(0, 0, -1)
	var mid := _skel.find_bone(&"RightMiddleProximal")
	var thumb_bone := _skel.find_bone(&"RightThumbProximal")
	if mid >= 0:
		fingers = (to_canon * (_skel.get_bone_global_rest(mid).origin - hand)).normalized()
	if thumb_bone >= 0:
		var t := to_canon * (_skel.get_bone_global_rest(thumb_bone).origin - hand)
		t -= fingers * t.dot(fingers)
		if t.length_squared() > 1e-8:
			thumb = t.normalized()
	var reach := 0.09 * scale / 0.86
	if mid >= 0:
		reach = (_skel.get_bone_global_rest(mid).origin - hand).length()
	# Resting palms face down; the grip lies just under the palm.
	var palm := Vector3.DOWN - fingers * Vector3.DOWN.dot(fingers)
	palm = palm.normalized() if palm.length_squared() > 1e-6 else Vector3.DOWN
	var grip := to_canon * hand + fingers * reach * 0.85 + palm * reach * 0.35
	# Exactly the thumb side and the knuckles: the poser aims the hand by
	# the same two directions (HumanoidPoser._aim_hand).
	var blade_dir := thumb
	var edge := fingers
	# Model: blade toward -Y, edge toward -X.
	var y := -blade_dir
	var x := -edge
	var basis := Basis(x, y, x.cross(y)).scaled(Vector3.ONE * scale)
	return Transform3D(basis, grip - basis * Vector3(0, GRIP_Y, 0))


## A piece of the ninjato model made of some of its surfaces.
func _part(mesh: Mesh, surfaces: Array) -> MeshInstance3D:
	var part := ArrayMesh.new()
	for i: int in surfaces:
		if i >= mesh.get_surface_count():
			continue
		part.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(i))
		part.surface_set_material(part.get_surface_count() - 1, mesh.surface_get_material(i))
	var mi := MeshInstance3D.new()
	mi.mesh = part
	var holder := Node3D.new()
	holder.add_child(mi)
	Toon.apply(holder, 0.004)
	holder.remove_child(mi)
	holder.free()
	return mi


## A slightly curved single-edged blade with a ridged back, from the guard
## (y = GUARD_Y) down to its point: edge toward -X, back toward +X.
static func _blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const STEPS := 14
	var rings: Array = []
	for i in STEPS + 1:
		var t := float(i) / STEPS
		var y := GUARD_Y - t * BLADE_LENGTH
		# Curve (sori): the back bows out toward +X along the length.
		var bow := 0.018 * sin(t * PI * 0.9)
		var width := lerpf(0.03, 0.022, t)
		var thick := lerpf(0.0065, 0.004, t)
		if t > 0.86:
			# The point (kissaki): the edge sweeps up to meet the back.
			var k := (t - 0.86) / 0.14
			width *= 1.0 - k * 0.97
			thick *= 1.0 - k * 0.9
		var back := bow + width * 0.5
		var edge := bow - width * 0.5
		rings.append([Vector3(edge, y, 0.0), Vector3(back, y, thick), Vector3(back, y, -thick)])
	for i in STEPS:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		for f in [[0, 1], [1, 2], [2, 0]]:
			_quad(st, a[f[0]], a[f[1]], b[f[1]], b[f[0]])
	st.generate_normals()
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


func _merged(bones: Array) -> AABB:
	var out := AABB()
	for b: StringName in bones:
		var r := region(b)
		if r.size == Vector3.ZERO:
			continue
		out = r if out.size == Vector3.ZERO else out.merge(r)
	return out


func _first_bone(bones: Array) -> StringName:
	for b: StringName in bones:
		if _skel.find_bone(b) >= 0:
			return b
	return bones[-1]


func _to_canonical(p: Vector3) -> Vector3:
	return _frame.inverse() * p


## Parents `piece` (authored in canonical space) to `bone` so it follows it.
func _attach(bone: StringName, piece: Node3D) -> void:
	var idx := _skel.find_bone(bone)
	if idx < 0:
		piece.free()
		return
	var att := BoneAttachment3D.new()
	att.name = "Gear_%s_%d" % [bone, _attachments.size()]
	att.bone_name = bone
	_skel.add_child(att)
	var in_skeleton := Transform3D(_frame, Vector3.ZERO) * piece.transform
	piece.transform = _skel.get_bone_global_rest(idx).affine_inverse() * in_skeleton
	att.add_child(piece)
	_mark(piece)
	_attachments.append(att)


func _mark(n: Node) -> void:
	n.set_meta(&"gear", true)
	for c in n.get_children():
		_mark(c)


## An open band (cloth wrapped round the head/face), elliptical in plan.
func _ring(radius_x: float, radius_z: float, height: float, color: Color) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = height
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 40
	var mi := _mesh(cyl, color, false, true)
	mi.scale = Vector3(radius_x, 1.0, radius_z)
	return mi


func _box(size: Vector3, color: Color, metal := false) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	return _mesh(box, color, metal)


func _mesh(mesh: Mesh, color: Color, metal := false, two_sided := false) -> MeshInstance3D:
	var mat := Toon.flat(color, 0.35 if metal else 0.9)
	if metal:
		mat.metallic = 0.7
		mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
	if two_sided:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		mat.next_pass = Toon.outline(0.004)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.set_meta(&"gear", true)
	return mi
