class_name Story
extends RefCounted
## The story mode's cast and chapters, loaded from res://data/story/ and
## validated strictly so a typo in a chapter file is an error, not a
## silently skipped scene (docs/STORY.md explains the format).

const DIR := "res://data/story"
const CHARACTERS_FILE := "characters.json"
## Beat kinds: required keys, optional keys.
const BEATS := {
	"enter": [["who", "at"], []],
	"exit": [["who"], []],
	"say": [["lines"], []],
	"task": [["text", "goal"], ["count", "jutsu"]],
	"fight": [["waves"], ["text"]],
	"boss": [["who", "rank", "health"], ["at", "element", "taunt", "phases"]],
	"wait": [["seconds"], []],
	"banner": [["text"], []],
}
const GOALS: PackedStringArray = ["kunai_hit", "strike_hit", "jutsu_hit", "weak_hit", "cast", "guard", "dash", "charge", "lock_on"]
const TIMES: PackedStringArray = ["dawn", "day", "dusk", "night"]
const CHAPTER_REQUIRED: PackedStringArray = ["id", "number", "title", "location", "time", "beats"]
const CHAPTER_OPTIONAL: PackedStringArray = ["summary", "dummies", "player_at"]
const CHARACTER_KEYS: PackedStringArray = ["name", "title", "kanji", "element", "style"]
const NUMERALS: PackedStringArray = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
## The player speaks as "player".
const PLAYER := "player"

## id -> {name, title, kanji, element: int, style: Dictionary}
var characters: Dictionary = {}
## Sorted by number. Each: {id, number, title, location, time, summary,
## dummies, player_at: Vector2, beats: Array[Dictionary]}.
var chapters: Array[Dictionary] = []
var errors: Array[String] = []


static func load_all(dir := DIR) -> Story:
	var s := Story.new()
	s._load(dir)
	return s


func chapter(id: String) -> Dictionary:
	for c in chapters:
		if c["id"] == id:
			return c
	return {}


## The chapter after `id`, or {} after the last one.
func next_chapter(id: String) -> Dictionary:
	for i in chapters.size() - 1:
		if chapters[i]["id"] == id:
			return chapters[i + 1]
	return {}


## First chapter, or the previous one is cleared.
func is_unlocked(id: String) -> bool:
	for i in chapters.size():
		if chapters[i]["id"] == id:
			return i == 0 or Game.chapter_done(chapters[i - 1]["id"])
	return false


func speaker_name(who: String) -> String:
	if who == PLAYER:
		return str(Profile.get_value(&"name"))
	return characters[who]["name"] if characters.has(who) else who


func speaker_kanji(who: String) -> String:
	if who == PLAYER:
		return Element.kanji(Profile.get_value(&"affinity"))
	return characters[who]["kanji"] if characters.has(who) else "?"


static func numeral(n: int) -> String:
	return NUMERALS[n] if n >= 0 and n < NUMERALS.size() else str(n)


## Fills {name}, {nature} and {action} placeholders: an input action name
## becomes the key or button for the device in use.
static func format(text: String) -> String:
	var out := text.replace("{name}", str(Profile.get_value(&"name")))
	out = out.replace("{nature}", Element.display_name(Profile.get_value(&"affinity")).to_lower())
	var re := RegEx.create_from_string(r"\{(\w+)\}")
	for m in re.search_all(out):
		var action := m.get_string(1)
		if InputMap.has_action(action):
			out = out.replace(m.get_string(), InputDevice.glyph(StringName(action)))
	return out


# --- Loading ---------------------------------------------------------------------

func _load(dir: String) -> void:
	var cast: Variant = _read_json(dir.path_join(CHARACTERS_FILE))
	if cast is Dictionary:
		for id: String in cast:
			_parse_character(id, cast[id])
	elif cast != null:
		errors.append("%s: top level must be an object of characters" % CHARACTERS_FILE)

	var files := Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool:
		return f.get_extension() == "json" and f != CHARACTERS_FILE)
	files.sort()
	for f: String in files:
		var data: Variant = _read_json(dir.path_join(f))
		if data is Dictionary:
			var c := _parse_chapter(f, data)
			if not c.is_empty():
				chapters.append(c)
		elif data != null:
			errors.append("%s: top level must be a chapter object" % f)
	chapters.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["number"] < b["number"])
	for i in chapters.size():
		if chapters[i]["number"] != i + 1:
			errors.append("chapters must be numbered 1, 2, 3... without gaps (found %d)" % chapters[i]["number"])
			break


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("missing %s" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("%s:%d: %s" % [path.get_file(), json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _parse_character(id: String, data: Variant) -> void:
	var label := "%s: %s" % [CHARACTERS_FILE, id]
	if id == PLAYER:
		errors.append("%s: '%s' is reserved for the player" % [label, PLAYER])
		return
	if not data is Dictionary:
		errors.append("%s: must be an object" % label)
		return
	for key: String in data:
		if not CHARACTER_KEYS.has(key):
			errors.append("%s: unknown key '%s'" % [label, key])
	for key in ["name", "kanji", "element"]:
		if not data.has(key):
			errors.append("%s: missing '%s'" % [label, key])
			return
	var element := Element.from_name(str(data["element"]))
	if element < 0:
		errors.append("%s: unknown element '%s'" % [label, data["element"]])
	characters[id] = {
		"name": str(data["name"]),
		"title": str(data.get("title", "")),
		"kanji": str(data["kanji"]),
		"element": maxi(element, 0),
		"style": _parse_style(label, data.get("style", {})),
	}


## Converts a JSON look (colours as "#rrggbb") to a CharacterModel style.
func _parse_style(label: String, raw: Variant) -> Dictionary:
	var style := {}
	if not raw is Dictionary:
		errors.append("%s: style must be an object" % label)
		return style
	for key: String in raw:
		var value: Variant = raw[key]
		if key == "tints":
			var tints := {}
			for slot: String in value:
				if not Profile.COLOR_SLOTS.has(slot):
					errors.append("%s: unknown colour slot '%s'" % [label, slot])
				elif not Color.html_is_valid(str(value[slot])):
					errors.append("%s: '%s' is not a colour" % [label, value[slot]])
				else:
					tints[slot] = Color.html(str(value[slot]))
			style["tints"] = tints
			continue
		if not Profile.DEFAULTS.has(StringName(key)) or key in ["model", "name", "affinity"]:
			errors.append("%s: unknown style key '%s'" % [label, key])
			continue
		var want: Variant = Profile.DEFAULTS[StringName(key)]
		if want is Color:
			if not Color.html_is_valid(str(value)):
				errors.append("%s: %s must be a colour" % [label, key])
				continue
			value = Color.html(str(value))
		elif want is float and (value is int or value is float):
			value = float(value)
		elif typeof(value) != typeof(want):
			errors.append("%s: %s must be a %s" % [label, key, type_string(typeof(want))])
			continue
		style[key] = value
	return style


func _parse_chapter(file: String, data: Dictionary) -> Dictionary:
	var start := errors.size()
	for key: String in data:
		if not CHAPTER_REQUIRED.has(key) and not CHAPTER_OPTIONAL.has(key):
			errors.append("%s: unknown key '%s'" % [file, key])
	for key in CHAPTER_REQUIRED:
		if not data.has(key):
			errors.append("%s: missing '%s'" % [file, key])
			return {}
	var c := {
		"id": str(data["id"]),
		"number": int(data["number"]),
		"title": str(data["title"]),
		"location": str(data["location"]),
		"time": str(data["time"]),
		"summary": str(data.get("summary", "")),
		"dummies": bool(data.get("dummies", false)),
		"player_at": _vec2(file, data.get("player_at", [0, 4])),
		"beats": [],
	}
	if not TIMES.has(c["time"]):
		errors.append("%s: time must be one of %s" % [file, TIMES])
	if not data["beats"] is Array or data["beats"].is_empty():
		errors.append("%s: beats must be a non-empty list" % file)
		return {}
	var present := {}
	for i in data["beats"].size():
		var beat := _parse_beat("%s beat %d" % [file, i + 1], data["beats"][i], present)
		if not beat.is_empty():
			c["beats"].append(beat)
	return c if errors.size() == start else {}


## `present` tracks who is on stage, so "exit" and "say" can be checked.
func _parse_beat(label: String, raw: Variant, present: Dictionary) -> Dictionary:
	if not raw is Dictionary or not raw.has("do"):
		errors.append("%s: must be an object with a 'do'" % label)
		return {}
	var kind := str(raw["do"])
	if not BEATS.has(kind):
		errors.append("%s: unknown beat '%s' (one of %s)" % [label, kind, BEATS.keys()])
		return {}
	var required: Array = BEATS[kind][0]
	var optional: Array = BEATS[kind][1]
	for key in required:
		if not raw.has(key):
			errors.append("%s (%s): missing '%s'" % [label, kind, key])
			return {}
	for key: String in raw:
		if key != "do" and not required.has(key) and not optional.has(key):
			errors.append("%s (%s): unknown key '%s'" % [label, kind, key])
	var b := {"do": kind}
	match kind:
		"enter":
			b["who"] = _who(label, raw["who"], false)
			b["at"] = _vec2(label, raw["at"])
			present[b["who"]] = true
		"exit":
			b["who"] = _who(label, raw["who"], false)
			if not present.has(b["who"]):
				errors.append("%s: '%s' exits without having entered" % [label, b["who"]])
			present.erase(b["who"])
		"say":
			b["lines"] = []
			if not raw["lines"] is Array or raw["lines"].is_empty():
				errors.append("%s: lines must be a non-empty list" % label)
			else:
				for line: Variant in raw["lines"]:
					if not line is Array or line.size() < 2 or line.size() > 3:
						errors.append("%s: each line is [who, text] or [who, text, mood]" % label)
						continue
					var who := _who(label, line[0], true)
					if who != PLAYER and not present.has(who):
						errors.append("%s: '%s' speaks but isn't on stage (add an enter beat)" % [label, who])
					var mood := str(line[2]) if line.size() == 3 else ""
					if mood != "" and not Profile.EXPRESSIONS.has(mood):
						errors.append("%s: unknown mood '%s'" % [label, mood])
					b["lines"].append({"who": who, "text": str(line[1]), "mood": mood})
		"task":
			b["text"] = str(raw["text"])
			b["goal"] = str(raw["goal"])
			b["count"] = int(raw.get("count", 1))
			b["jutsu"] = StringName(str(raw.get("jutsu", "")))
			if not GOALS.has(b["goal"]):
				errors.append("%s: unknown goal '%s' (one of %s)" % [label, b["goal"], GOALS])
			if b["jutsu"] != &"" and JutsuRegistry.get_jutsu(b["jutsu"]) == null:
				errors.append("%s: unknown jutsu '%s'" % [label, b["jutsu"]])
		"fight":
			b["text"] = str(raw.get("text", "Defeat the clones"))
			b["waves"] = []
			if not raw["waves"] is Array or raw["waves"].is_empty():
				errors.append("%s: waves must be a non-empty list" % label)
			else:
				for w: Variant in raw["waves"]:
					if not w is Dictionary or not w.has("element") or not w.has("enemies"):
						errors.append("%s: each wave is {element, enemies}" % label)
						continue
					b["waves"].append({"element": _element(label, w["element"]), "enemies": _ranks(label, w["enemies"])})
		"boss":
			b["who"] = _who(label, raw["who"], false)
			# A character on stage steps into the fight; enter them again after.
			present.erase(b["who"])
			var ranks := _ranks(label, [raw["rank"]])
			b["rank"] = ranks[0] if not ranks.is_empty() else &"genin"
			b["health"] = float(raw["health"])
			b["at"] = _vec2(label, raw.get("at", [0, -8]))
			b["taunt"] = str(raw.get("taunt", ""))
			var fallback: int = characters[b["who"]]["element"] if characters.has(b["who"]) else Element.NONE
			b["element"] = _element(label, raw["element"]) if raw.has("element") else fallback
			b["phases"] = []
			for p: Variant in raw.get("phases", []):
				if not p is Dictionary or not p.has("at"):
					errors.append("%s: each phase needs 'at' (health share 0-1)" % label)
					continue
				for key: String in p:
					if not key in ["at", "element", "say", "summon"]:
						errors.append("%s: unknown phase key '%s'" % [label, key])
				var summon: Array = []
				for s: Variant in p.get("summon", []):
					if s is Array and s.size() == 2:
						var rank := _ranks(label, [s[0]])
						summon.append([rank[0] if not rank.is_empty() else &"genin", _element(label, s[1])])
					else:
						errors.append("%s: summon entries are [rank, element]" % label)
				b["phases"].append({
					"at": float(p["at"]),
					"element": _element(label, p["element"]) if p.has("element") else -1,
					"say": str(p.get("say", "")),
					"summon": summon,
				})
		"wait":
			b["seconds"] = float(raw["seconds"])
		"banner":
			b["text"] = str(raw["text"])
	return b


func _who(label: String, raw: Variant, allow_player: bool) -> String:
	var who := str(raw)
	if who == PLAYER and allow_player:
		return who
	if not characters.has(who):
		errors.append("%s: unknown character '%s'" % [label, who])
	return who


func _element(label: String, raw: Variant) -> int:
	var e := Element.from_name(str(raw))
	if e < 0:
		errors.append("%s: unknown element '%s'" % [label, raw])
		return Element.NONE
	return e


func _ranks(label: String, raw: Variant) -> Array:
	var out: Array = []
	if not raw is Array:
		errors.append("%s: enemies must be a list of ranks" % label)
		return out
	for r: Variant in raw:
		if not EnemyShinobi.RANKS.has(StringName(str(r))):
			errors.append("%s: unknown rank '%s' (genin, chunin or jonin)" % [label, r])
		else:
			out.append(StringName(str(r)))
	return out


func _vec2(label: String, raw: Variant) -> Vector2:
	if raw is Array and raw.size() == 2 and (raw[0] is float or raw[0] is int) and (raw[1] is float or raw[1] is int):
		return Vector2(raw[0], raw[1])
	errors.append("%s: positions are [x, z]" % label)
	return Vector2.ZERO
