class_name CharacterGear
extends RefCounted
## Ninja gear that fits any humanoid: headband / hachigane, face mask, scarf,
## ninjato on the back and a kunai pouch.
##
## Fitting is measured, not guessed: every skinned vertex is assigned to its
## dominant bone, giving the real extents of the head, torso and thigh in the
## canonical character frame (facing -Z). Gear is sized and placed from
## those, then attached to bones so it follows every pose.

const REFERENCE_HEIGHT := 1.6
const PLATE_SHADER := preload("res://assets/shaders/hitai_plate.gdshader")

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

	var torso := _merged([&"UpperChest", &"Chest", &"Spine"])
	if settings.get("back", "none") == "ninjato" and torso.size != Vector3.ZERO:
		var sword := Node3D.new()
		# Diagonal across the back, hilt over the right shoulder.
		sword.transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(-32.0)),
			Vector3(torso.get_center().x, torso.get_center().y + 0.04 * k, torso.end.z + 0.04 * k))
		var sheath := _box(Vector3(0.045, 0.58, 0.024) * k, Color("1c1718"))
		sword.add_child(sheath)
		var cord := _box(Vector3(0.05, 0.03, 0.03) * k, Color("b8321f"))
		cord.position = Vector3(0, 0.18 * k, 0)
		sword.add_child(cord)
		var guard := _box(Vector3(0.075, 0.012, 0.05) * k, Color("3b3f46"), true)
		guard.position = Vector3(0, 0.3 * k, 0)
		sword.add_child(guard)
		var hilt := CylinderMesh.new()
		hilt.top_radius = 0.016 * k
		hilt.bottom_radius = 0.016 * k
		hilt.height = 0.2 * k
		var hilt_node := _mesh(hilt, Color("2a2324"))
		hilt_node.position = Vector3(0, 0.41 * k, 0)
		sword.add_child(hilt_node)
		_attach(_first_bone([&"UpperChest", &"Chest", &"Spine"]), sword)

	var thigh := region(&"RightUpperLeg")
	if settings.get("pouch", false) and thigh.size != Vector3.ZERO:
		var pouch := _box(Vector3(0.035, 0.07, 0.075) * k, Color("4a3322"))
		pouch.position = Vector3(thigh.end.x + 0.02 * k, thigh.get_center().y + thigh.size.y * 0.12, thigh.get_center().z)
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
