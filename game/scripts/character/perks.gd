class_name Perks
extends RefCounted
## Clans and eye arts: what you choose in character creation, and what it
## does (skill trees add theirs too: SkillTrees). Both are data (res://data/clans.json, eye_arts.json); a perk is a
## named number that the game reads where it matters (health, dash, chakra
## cost, damage, lock-on, enemy seal speed...). Every clan and eye art here
## is original.

const CLANS_FILE := "res://data/clans.json"
const EYE_ARTS_FILE := "res://data/eye_arts.json"

## Perk keys and how they read. "%" fractions are shown as percentages.
const PERK_TEXT := {
	"max_health": "+%d%% health",
	"chakra_regen": "+%d%% chakra recovery",
	"move_speed": "+%d%% run speed",
	"dash_cooldown": "%d%% dash cooldown",
	"damage": "+%d%% damage",
	"cost": "%d%% chakra cost",
	"heal": "+%d%% healing",
	"guard": "+%d%% damage blocked when guarding",
	"cast_speed": "+%d%% faster seal weaving for quick-cast",
	"clone_time": "+%d%% Shade Clone lifetime",
	"lock_range": "+%d%% lock-on range",
	"homing": "+%d%% jutsu homing",
	"enemy_seal_slow": "Rivals weave %d%% slower",
	"max_chakra": "+%d%% maximum chakra",
	"ult_gain": "+%d%% ultimate charge",
	"eye_time": "+%d%% eye art open time",
	"nature_damage": "+%d%% damage with your clan's nature",
}
const FLAG_TEXT := {
	"clones": "+%d Shade Clone",
	"reads_natures": "Shows which natures are weak to you",
	"dodge_focus": "A clean dash through a hit slows time and refunds chakra",
	"perfect_guard": "A guard raised just before a hit blocks it entirely",
	"second_wind": "Once a fight, a blow that would defeat you leaves you standing (back after 30 s unhurt)",
	"twin_weave": "Every projectile jutsu fires a second, echoing shot",
	"shadow_bloom": "Shade Clones burst when they fade or fall, striking every foe nearby",
}
const FOCUS_TIME_SCALE := 0.35
const FOCUS_SECONDS := 0.5
const FOCUS_CHAKRA := 10.0
## A guard raised this recently blocks everything (Still Eye).
const PERFECT_GUARD_WINDOW := 0.25

## Seconds an eye art rests after closing, if the data doesn't say.
const EYE_COOLDOWN := 25.0

static var errors: Array[String] = []
static var _clans: Array[Dictionary] = []
static var _arts: Array[Dictionary] = []
static var _eye_settings: Dictionary = {}
static var _loaded := false


static func reload() -> void:
	_loaded = false
	errors = []
	_clans = _load("clans", CLANS_FILE, ["id", "name", "kanji", "element", "color", "blurb", "perks", "eye_arts"])
	_arts = _load("eye_arts", EYE_ARTS_FILE, ["id", "name", "kanji", "color", "blurb", "perks", "pattern", "active", "awakened"])
	var arts_file: Variant = JSON.parse_string(FileAccess.get_file_as_string(EYE_ARTS_FILE))
	_eye_settings = {}
	if arts_file is Dictionary:
		_eye_settings = {"awaken_after": str(arts_file.get("awaken_after", "")),
			"cooldown": float(arts_file.get("cooldown", EYE_COOLDOWN))}
	for art in _arts:
		if not EyePattern.PATTERNS.has(str(art["pattern"])):
			errors.append("eye art %s: unknown pattern '%s'" % [art["id"], art["pattern"]])
		for form_key: String in ["active", "awakened"]:
			var f: Variant = art[form_key]
			if not f is Dictionary or not (f as Dictionary).has("name") or not (f as Dictionary).get("perks") is Dictionary:
				errors.append("eye art %s: %s needs a name and perks" % [art["id"], form_key])
				continue
			if float(f.get("seconds", 0)) <= 0.0 or float(f.get("cost", -1)) < 0.0:
				errors.append("eye art %s: %s needs seconds and a cost" % [art["id"], form_key])
			for key: String in f["perks"]:
				if not PERK_TEXT.has(key) and not key.begins_with("damage_"):
					errors.append("eye art %s: %s has unknown perk '%s'" % [art["id"], form_key, key])
		for form_key: String in ["active", "awakened"]:
			var ability := str((art[form_key] as Dictionary).get("ability", ""))
			if ability != "" and not EyeArtMode.ABILITIES.has(ability):
				errors.append("eye art %s: %s has unknown ability '%s'" % [art["id"], form_key, ability])
		if not (art["awakened"] as Dictionary).has("kanji"):
			errors.append("eye art %s: the awakened form needs a kanji" % art["id"])
	var art_ids := _arts.map(func(a: Dictionary) -> String: return a["id"])
	var seen := {}
	for clan in _clans:
		if seen.has(clan["id"]):
			errors.append("clan %s appears twice" % clan["id"])
		seen[clan["id"]] = true
		if Element.from_name(str(clan["element"])) < 0:
			errors.append("clan %s: unknown element '%s'" % [clan["id"], clan["element"]])
		for art: String in clan["eye_arts"]:
			if not art_ids.has(art):
				errors.append("clan %s: unknown eye art '%s'" % [clan["id"], art])
	for entry in _clans + _arts:
		if not Color.html_is_valid(str(entry["color"])):
			errors.append("%s: bad colour" % entry["id"])
		for key: String in entry["perks"]:
			if not PERK_TEXT.has(key) and not FLAG_TEXT.has(key) and not key.begins_with("damage_"):
				errors.append("%s: unknown perk '%s'" % [entry["id"], key])
			elif key.begins_with("damage_") and Element.from_name(key.trim_prefix("damage_")) < 0:
				errors.append("%s: unknown element in perk '%s'" % [entry["id"], key])
	_loaded = true


static func _load(key: String, path: String, required: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not (parsed as Dictionary).get(key) is Array:
		errors.append("%s: expected {\"%s\": [...]}" % [path, key])
		return out
	for raw: Variant in parsed[key]:
		if not raw is Dictionary:
			errors.append("%s: entries are objects" % path)
			continue
		var missing := required.filter(func(k: String) -> bool: return not raw.has(k))
		if not missing.is_empty():
			errors.append("%s %s: missing %s" % [path.get_file(), raw.get("id", "?"), missing])
			continue
		out.append(raw)
	return out


static func clans() -> Array[Dictionary]:
	if not _loaded:
		reload()
	return _clans


static func eye_arts() -> Array[Dictionary]:
	if not _loaded:
		reload()
	return _arts


## The clan with this id ({} if none).
static func clan(id: String) -> Dictionary:
	for c in clans():
		if c["id"] == id:
			return c
	return {}


static func eye_art(id: String) -> Dictionary:
	for a in eye_arts():
		if a["id"] == id:
			return a
	return {}


## The eye arts a clan may take.
static func arts_for(clan_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in clan(clan_id).get("eye_arts", []):
		var a := eye_art(id)
		if not a.is_empty():
			out.append(a)
	return out


## The chosen clan's nature (Element.NONE for a Wayfarer or no clan).
static func clan_element(id: String) -> int:
	var c := clan(id)
	return Element.from_name(str(c["element"])) if not c.is_empty() else Element.NONE


## The player's eye art, if their clan allows it ({} otherwise).
static func active_eye_art() -> Dictionary:
	var id: String = Profile.get_value(&"eye_art")
	if id == "":
		return {}
	var allowed := arts_for(Profile.get_value(&"clan"))
	return eye_art(id) if allowed.any(func(a: Dictionary) -> bool: return a["id"] == id) else {}


## Total of a perk across the player's clan, eye art (and the eye art's open
## form, while it's open: EyeArtMode) and skill trees.
static func value(key: StringName) -> float:
	return base_value(key) + float(SkillTrees.perks().get(String(key), 0.0))


## The same without the skill trees (what the clan and eye art give).
static func base_value(key: StringName) -> float:
	var total := 0.0
	var sources: Array[Dictionary] = [clan(Profile.get_value(&"clan")), active_eye_art(), {"perks": EyeArtMode.boost}]
	for source in sources:
		total += float((source.get("perks", {}) as Dictionary).get(String(key), 0.0))
	return total


## The chapter whose clearing awakens every eye art ("" never).
static func awaken_after() -> String:
	if not _loaded:
		reload()
	return str(_eye_settings.get("awaken_after", ""))


## Seconds an eye art rests after it closes.
static func eye_cooldown() -> float:
	if not _loaded:
		reload()
	return float(_eye_settings.get("cooldown", EYE_COOLDOWN))


## What a hit of `element` is multiplied by: 1 plus the general and
## nature-specific damage perks (and Nature's Voice for the clan's own nature;
## neutral jutsu for a Wayfarer).
static func damage_multiplier(element: int) -> float:
	var bonus := value(&"damage")
	if element != Element.NONE:
		bonus += value(StringName("damage_" + Element.NAMES[element]))
	if element == clan_element(Profile.get_value(&"clan")):
		bonus += value(&"nature_damage")
	return 1.0 + bonus


static func has(key: StringName) -> bool:
	return value(key) > 0.0


## A perk dictionary as readable lines ("+15% Fire damage").
static func describe(perks: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for key: String in perks:
		var v := float(perks[key])
		if PERK_TEXT.has(key):
			lines.append(PERK_TEXT[key] % roundi(v * 100.0))
		elif FLAG_TEXT.has(key):
			lines.append(FLAG_TEXT[key] % int(v) if "%" in FLAG_TEXT[key] else FLAG_TEXT[key])
		elif key.begins_with("damage_"):
			lines.append("+%d%% %s damage" % [roundi(v * 100.0), Element.display_name(Element.from_name(key.trim_prefix("damage_")))])
	return lines
