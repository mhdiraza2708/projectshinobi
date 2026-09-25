class_name CharacterStyler
extends RefCounted
## Recolours a character by tinting its materials per slot (hair, eyes, skin,
## outfit...). Slots are found from material names: VRoid exports tag them
## (_HAIR, _CLOTH, _SKIN, _EYE...), and most other VRMs use similar words.
##
## A tint multiplies the original colours, so it shifts and darkens but can't
## make dark hair blond. Materials are duplicated per character, so shared
## imported resources are never modified.

const SLOT_LABELS := {
	"hair": "Hair", "eyes": "Eyes", "skin": "Skin", "outfit": "Outfit", "lower": "Lower",
	"shoes": "Shoes", "accessory": "Accessories", "body": "Body",
}

## slot -> Array of {material, lit: Color, shade: Color}
var slots: Dictionary = {}


## Returns the slot for a material name, or "" to leave it alone.
static func classify(material_name: String) -> String:
	var n := material_name.to_lower()
	var has := func(words: Array) -> bool:
		return words.any(func(w: String) -> bool: return n.contains(w))
	# Face details keep their authored colours (brows follow the hair).
	if has.call(["brow"]):
		return "hair"
	if has.call(["eyewhite", "eye_white", "highlight", "eyeline", "eyelash", "lash", "mastuge", "mouth", "tooth", "teeth"]):
		return ""
	if has.call(["iris", "_eye", "eye_", "eyes"]) or n.ends_with("eye"):
		return "eyes"
	if has.call(["acc", "other", "ribbon"]) or (has.call(["hair"]) and has.call(["wear"])):
		return "accessory"
	if has.call(["shoe", "boot", "sandal"]):
		return "shoes"
	if has.call(["bottom", "pants", "skirt", "trouser"]):
		return "lower"
	if has.call(["hair"]):
		return "hair"
	if has.call(["skin"]):
		return "skin"
	if has.call(["cloth", "wear", "top", "onepiece", "jacket", "shirt", "coat", "dress", "outfit"]):
		return "outfit"
	if has.call(["body", "face"]):
		return "skin"
	return ""


## Collects (and duplicates) every recolourable material under `root`.
func bind(root: Node) -> void:
	slots.clear()
	var found: Array[Dictionary] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.has_meta(&"gear"):
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			if src == null:
				continue
			var slot := classify(src.resource_name)
			var mat := src.duplicate() as Material
			mi.set_surface_override_material(i, mat)
			var entry := {"material": mat, "slot": slot}
			if mat is ShaderMaterial:
				entry["lit"] = _param(mat, &"_Color", Color.WHITE)
				entry["shade"] = _param(mat, &"_ShadeColor", Color.WHITE)
			elif mat is BaseMaterial3D:
				entry["lit"] = (mat as BaseMaterial3D).albedo_color
			else:
				continue
			found.append(entry)

	# Models without recognisable naming get one whole-model slot, so they can
	# still be recoloured instead of mislabelling their outfit as "Skin".
	var named := found.any(func(e: Dictionary) -> bool: return e["slot"] in ["hair", "outfit", "lower"])
	for e in found:
		var slot: String = e["slot"] if named else "body"
		if slot == "":
			continue
		if not slots.has(slot):
			slots[slot] = []
		slots[slot].append(e)


func available_slots() -> PackedStringArray:
	var out := PackedStringArray()
	for slot in Profile.COLOR_SLOTS:
		if slots.has(slot):
			out.append(slot)
	return out


func apply_tint(slot: String, tint: Color) -> void:
	for e: Dictionary in slots.get(slot, []):
		var mat: Material = e["material"]
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter(&"_Color", _mul(e["lit"], tint))
			(mat as ShaderMaterial).set_shader_parameter(&"_ShadeColor", _mul(e["shade"], tint))
		elif mat is BaseMaterial3D:
			(mat as BaseMaterial3D).albedo_color = _mul(e["lit"], tint)


func current_tint_of(slot: String) -> Color:
	var list: Array = slots.get(slot, [])
	if list.is_empty():
		return Color.WHITE
	var e: Dictionary = list[0]
	var mat: Material = e["material"]
	var now: Color = (mat as ShaderMaterial).get_shader_parameter(&"_Color") if mat is ShaderMaterial \
		else (mat as BaseMaterial3D).albedo_color
	var base: Color = e["lit"]
	return Color(now.r / maxf(base.r, 0.001), now.g / maxf(base.g, 0.001), now.b / maxf(base.b, 0.001))


static func _mul(a: Color, b: Color) -> Color:
	return Color(a.r * b.r, a.g * b.g, a.b * b.b, a.a)


static func _param(mat: ShaderMaterial, param: StringName, fallback: Color) -> Color:
	var v: Variant = mat.get_shader_parameter(param)
	if v is Color:
		return v
	if v is Vector4:
		return Color(v.x, v.y, v.z, v.w)
	return fallback
