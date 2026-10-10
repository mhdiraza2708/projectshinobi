class_name Bounties
extends RefCounted
## The wanted shinobi of the continent (res://data/bounties.json): each holds
## a lair in the wilds and is a fight of their own, with a rival's model and
## a nature. Loaded once.

const PATH := "res://data/bounties.json"
const MODEL_DIR := "res://assets/characters/rivals/"

static var _all: Array[Dictionary] = []
static var errors: Array[String] = []


static func all() -> Array[Dictionary]:
	if _all.is_empty():
		_load()
	return _all


static func get_bounty(id: String) -> Dictionary:
	for b: Dictionary in all():
		if b["id"] == id:
			return b
	return {}


## The rival model file for a bounty ("" when it is missing).
static func model_path(b: Dictionary) -> String:
	var path := MODEL_DIR + str(b.get("model", "")) + ".glb"
	return path if ResourceLoader.exists(path) else ""


static func _load() -> void:
	errors.clear()
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		errors.append("%s is missing" % PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not (parsed as Dictionary).get("bounties") is Array:
		errors.append("%s has no bounties list" % PATH)
		return
	var seen := {}
	for b: Dictionary in (parsed as Dictionary)["bounties"]:
		for key: String in ["id", "name", "kanji", "element", "model", "health", "danger", "lair", "taunt"]:
			if not b.has(key):
				errors.append("bounty %s: missing %s" % [b.get("id", "?"), key])
		if seen.has(b.get("id")):
			errors.append("bounty %s: duplicate id" % b.get("id"))
		seen[b.get("id")] = true
		if Element.from_name(str(b.get("element", ""))) < 0:
			errors.append("bounty %s: unknown element '%s'" % [b.get("id"), b.get("element")])
		for spec: Variant in b.get("specials", []):
			for problem in BossSpecials.errors_in(spec):
				errors.append("bounty %s: %s" % [b.get("id"), problem])
		_all.append(b)
