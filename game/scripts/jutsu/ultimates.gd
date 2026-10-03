class_name Ultimates
extends RefCounted
## Ultimate techniques: one per chakra nature plus one any nature can learn,
## defined in res://data/ultimates.json. A fight charges the meter (damage
## dealt and taken, interrupts, perfect guards); a full meter lets the player
## unleash their chosen ultimate in a short cinematic (UltimateSequence).
## Every name here is original.

const FILE := "res://data/ultimates.json"
const STYLES: PackedStringArray = ["meteor", "cyclone", "chain", "fist", "wave", "shades"]
const REQUIRED: PackedStringArray = ["id", "name", "kanji", "element", "style", "power", "radius", "blurb"]

## The meter.
const MAX_CHARGE := 100.0
## Charge per point of damage dealt / taken, and for feats.
const PER_DAMAGE_DEALT := 0.35
const PER_DAMAGE_TAKEN := 0.6
const PER_INTERRUPT := 10.0
const PER_PERFECT_GUARD := 8.0

static var errors: Array[String] = []
static var _list: Array[Dictionary] = []
static var _loaded := false


static func reload() -> void:
	errors = []
	_list = []
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	if not parsed is Dictionary or not (parsed as Dictionary).get("ultimates") is Array:
		errors.append("%s: expected {\"ultimates\": [...]}" % FILE)
		return
	var seen := {}
	for raw: Variant in parsed["ultimates"]:
		if not raw is Dictionary:
			errors.append("ultimates: entries are objects")
			continue
		var u: Dictionary = raw
		var missing := Array(REQUIRED).filter(func(k: String) -> bool: return not u.has(k))
		if not missing.is_empty():
			errors.append("ultimate %s: missing %s" % [u.get("id", "?"), missing])
			continue
		if seen.has(u["id"]):
			errors.append("ultimate %s appears twice" % u["id"])
		seen[u["id"]] = true
		var element := Element.from_name(str(u["element"]))
		if element < 0:
			errors.append("ultimate %s: unknown element '%s'" % [u["id"], u["element"]])
		if not STYLES.has(str(u["style"])):
			errors.append("ultimate %s: unknown style '%s'" % [u["id"], u["style"]])
		if float(u["power"]) <= 0.0 or float(u["radius"]) <= 0.0:
			errors.append("ultimate %s: power and radius must be positive" % u["id"])
		var entry := u.duplicate()
		entry["element_id"] = maxi(element, Element.NONE)
		_list.append(entry)


static func all() -> Array[Dictionary]:
	if not _loaded:
		reload()
	return _list


static func get_ultimate(id: String) -> Dictionary:
	for u in all():
		if u["id"] == id:
			return u
	return {}


## Whether a shinobi of `nature` can use it: their own nature's, or one with
## no nature.
static func allowed(u: Dictionary, nature: int) -> bool:
	return u["element_id"] == Element.NONE or u["element_id"] == nature


## The player's ultimate: the one they chose, if their nature allows it,
## else their nature's own.
static func equipped() -> Dictionary:
	var nature := int(Profile.get_value(&"affinity"))
	var chosen := get_ultimate(Profile.get_value(&"ultimate"))
	if not chosen.is_empty() and allowed(chosen, nature):
		return chosen
	for u in all():
		if u["element_id"] == nature:
			return u
	return all()[0] if not all().is_empty() else {}
