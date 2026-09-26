class_name CharacterWardrobe
extends RefCounted
## Mix and match between VRoid (or similarly built VRM) characters: keep one
## character's face and skeleton, and wear another's hair and another's
## outfit.
##
## Each surface is sorted by mesh and material name:
##   face    - surfaces of the face mesh (always the base character's)
##   hair    - "hair" materials anywhere else (VRoid: Hair001 + HairBack)
##   outfit  - everything else on the body: clothes, shoes and the body
##             itself, since VRoid trims the body under its own clothes.
## Donor surfaces are copied with their skin weights and rebound to the base
## skeleton by bone name. Bones the base lacks (VRoid hair joints, skirt and
## hood bones) are added under the same parent at the same rest offset, and
## the donor's spring bones for them come along, so borrowed hair and skirts
## still sway.

const FACE := "face"
const HAIR := "hair"
const OUTFIT := "outfit"


## Which part a surface belongs to.
static func part_of(mesh_name: String, material_name: String) -> String:
	if mesh_name.to_lower().begins_with("face"):
		return FACE
	if material_name.to_lower().contains("hair"):
		return HAIR
	return OUTFIT


## True when a model keeps hair and outfit on separate surfaces, so they can
## be swapped (VRoid exports do; single-material models don't).
static func is_swappable(root: Node) -> bool:
	var parts := {}
	for mi in _meshes(root):
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			parts[part_of(mi.name, mat.resource_name if mat else "")] = true
	return parts.has(HAIR) and parts.has(OUTFIT) and parts.has(FACE)


## Swaps hair and/or outfit on `root` (already in the tree). An empty path
## keeps the base character's own part. Returns the meshes it added.
static func apply(root: Node3D, skel: Skeleton3D, hair_from: String, outfit_from: String) -> Array[MeshInstance3D]:
	var added: Array[MeshInstance3D] = []
	if (hair_from == "" and outfit_from == "") or not is_swappable(root):
		return added
	var replace := {HAIR: hair_from != "", OUTFIT: outfit_from != ""}

	# 1. Drop the base character's replaced parts.
	for mi in _meshes(root):
		var keep: Array[int] = []
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if not replace.get(part_of(mi.name, mat.resource_name if mat else ""), false):
				keep.append(s)
		if keep.size() == mi.mesh.get_surface_count():
			continue
		if keep.is_empty():
			mi.visible = false
			mi.set_meta(&"wardrobe_hidden", true)
		else:
			mi.mesh = _subset(mi, keep)

	# 2. Bring in the donors' parts (one donor may supply both).
	var donors := {}
	if hair_from != "":
		donors[hair_from] = [HAIR]
	if outfit_from != "":
		donors[outfit_from] = donors.get(outfit_from, []) + [OUTFIT]
	var springs: Array = []
	for path: String in donors:
		var scene := load(path) as PackedScene
		if scene == null:
			push_warning("Wardrobe: can't load %s" % path)
			continue
		var donor := scene.instantiate() as Node3D
		var donor_skel := _skeleton(donor)
		if donor_skel == null or not is_swappable(donor):
			donor.free()
			continue
		var new_bones := {}
		for mi in _meshes(donor):
			var take: Array[int] = []
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s)
				if donors[path].has(part_of(mi.name, mat.resource_name if mat else "")):
					take.append(s)
			if take.is_empty():
				continue
			var copy := MeshInstance3D.new()
			copy.name = "%s_from_%s" % [mi.name, path.get_file().get_basename()]
			copy.mesh = _subset(mi, take)
			copy.skin = _rebind(mi, donor_skel, skel, new_bones)
			copy.set_meta(&"wardrobe", true)
			skel.add_child(copy)
			copy.skeleton = copy.get_path_to(skel)
			added.append(copy)
		springs.append_array(_springs_for(donor, new_bones))
		donor.free()

	# 3. Let the borrowed hair and cloth bones sway.
	if not springs.is_empty():
		var secondary := root.get_node_or_null("secondary")
		if secondary and secondary.get("spring_bones") != null:
			var list: Array = secondary.get("spring_bones").duplicate()
			list.append_array(springs)
			secondary.set("spring_bones", list)
			if secondary.is_inside_tree():
				secondary.call("_ready")
	return added


static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh and mi.skin and not mi.has_meta(&"gear") and not mi.has_meta(&"wardrobe_hidden"):
			out.append(mi)
	return out


static func _skeleton(root: Node) -> Skeleton3D:
	var found := root.find_children("*", "Skeleton3D", true, false)
	return found[0] if not found.is_empty() else null


## A copy of `mi`'s mesh with only `surfaces`, keeping materials, blend
## shapes and 8-weight skinning.
static func _subset(mi: MeshInstance3D, surfaces: Array[int]) -> ArrayMesh:
	var src := mi.mesh as ArrayMesh
	var out := ArrayMesh.new()
	out.resource_name = src.resource_name
	for b in src.get_blend_shape_count():
		out.add_blend_shape(src.get_blend_shape_name(b))
	out.blend_shape_mode = src.blend_shape_mode
	for s in surfaces:
		var flags := src.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), src.surface_get_arrays(s),
			src.surface_get_blend_shape_arrays(s), {}, flags)
		var i := out.get_surface_count() - 1
		out.surface_set_material(i, mi.get_active_material(s))
		out.surface_set_name(i, src.surface_get_name(s))
	return out


## A skin for `mi`'s mesh that binds by bone name, adding to `target` any
## bone the donor has and the target lacks (recorded in `added`).
static func _rebind(mi: MeshInstance3D, donor_skel: Skeleton3D, target: Skeleton3D, added: Dictionary) -> Skin:
	var skin := Skin.new()
	for bi in mi.skin.get_bind_count():
		var bone := mi.skin.get_bind_bone(bi)
		var bone_name := String(mi.skin.get_bind_name(bi))
		if bone >= 0:
			bone_name = donor_skel.get_bone_name(bone)
		_ensure_bone(bone_name, donor_skel, target, added)
		skin.add_named_bind(bone_name, mi.skin.get_bind_pose(bi))
	return skin


static func _ensure_bone(bone_name: String, donor_skel: Skeleton3D, target: Skeleton3D, added: Dictionary) -> int:
	var existing := target.find_bone(bone_name)
	if existing >= 0:
		return existing
	var donor_idx := donor_skel.find_bone(bone_name)
	if donor_idx < 0:
		return -1
	var parent := -1
	var donor_parent := donor_skel.get_bone_parent(donor_idx)
	if donor_parent >= 0:
		parent = _ensure_bone(donor_skel.get_bone_name(donor_parent), donor_skel, target, added)
	var idx := target.get_bone_count()
	target.add_bone(bone_name)
	target.set_bone_parent(idx, parent)
	target.set_bone_rest(idx, donor_skel.get_bone_rest(donor_idx))
	target.reset_bone_pose(idx)
	added[bone_name] = true
	# Bring the whole chain: spring bones need the unweighted tip joints too.
	for child in donor_skel.get_bone_children(donor_idx):
		_ensure_bone(donor_skel.get_bone_name(child), donor_skel, target, added)
	return idx


## The donor's spring bones that move only bones we just added.
static func _springs_for(donor: Node, new_bones: Dictionary) -> Array:
	var out: Array = []
	var secondary := donor.get_node_or_null("secondary")
	if secondary == null or secondary.get("spring_bones") == null or new_bones.is_empty():
		return out
	for sb: Resource in secondary.get("spring_bones"):
		var joints: PackedStringArray = sb.get("joint_nodes")
		if joints.is_empty():
			continue
		var all_new := true
		for j in joints:
			if j != "" and not new_bones.has(j):
				all_new = false
				break
		if all_new:
			out.append(sb.duplicate())
	return out
