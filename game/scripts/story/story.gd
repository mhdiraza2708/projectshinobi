class_name Story
extends RefCounted
## The story mode's cast and chapters, loaded from res://data/story/ and
## validated strictly so a typo in a chapter file is an error, not a
## silently skipped scene (docs/STORY.md explains the format).

const DIR := "res://data/story"
const CHARACTERS_FILE := "characters.json"
## The story's chapters: each a numbered, titled group of missions (the
## mission files say which chapter they belong to with "part").
const PARTS_FILE := "parts.json"
## Beat kinds: required keys, optional keys.
const BEATS := {
	"enter": [["who", "at"], []],
	"exit": [["who"], []],
	"say": [["lines"], ["music"]],
	"task": [["text", "goal"], ["count", "jutsu", "enemies", "music"]],
	"fight": [["waves"], ["text"]],
	"survive": [["seconds", "enemies"], ["text", "max_alive"]],
	"ally": [["who", "rank"], ["health", "at"]],
	"boss": [["who", "rank", "health"], ["at", "element", "taunt", "phases", "size", "aura"]],
	"wait": [["seconds"], []],
	"banner": [["text"], []],
	"scene": [["steps"], []],
}
## Cutscene steps: the action key (holding the main value), then the other
## keys it takes. Every step may also have "async": true.
const SCENE_STEPS := {
	"wait": [],
	"cam": ["on", "from", "at", "to", "look", "look_to", "seconds", "blend", "fov", "dist", "height", "side", "radius", "degrees"],
	"say": [],
	"enter": ["at", "from", "facing", "puff"],
	"exit": ["puff"],
	"move": ["to", "run"],
	"leap": ["to", "from", "height", "seconds"],
	"face": ["to"],
	"pose": ["as", "seconds"],
	"weave": ["seals"],
	"cast": ["element", "at", "kind"],
	"fx": ["at", "from", "to", "on", "color", "element", "seconds", "size"],
	"grow": ["scale", "seconds"],
	"music": [],
	"sfx": [],
	"time": [],
	"weather": [],
	"fade": ["seconds", "color"],
	"title": ["sub", "seconds"],
}
## Camera framings and their defaults: [distance, height, side, fov].
const SHOTS := {
	"close": [1.5, 1.5, 1.0, 40.0],
	"mid": [3.0, 1.4, 0.6, 46.0],
	"wide": [7.5, 2.2, 0.0, 50.0],
	"low": [3.2, 0.35, 0.4, 50.0],
	"over": [0.0, 0.0, 1.0, 46.0],
	"two": [0.0, 0.0, 1.0, 50.0],
	"orbit": [0.0, 1.5, 0.0, 50.0],
	"free": [0.0, 0.0, 0.0, 50.0],
}
const SCENE_POSES := {"idle": HumanoidPoser.Pose.LOCOMOTION, "weave": HumanoidPoser.Pose.WEAVE,
	"guard": HumanoidPoser.Pose.GUARD, "charge": HumanoidPoser.Pose.CHARGE}
const CAST_KINDS: PackedStringArray = ["projectile", "blast", "bolt"]
const FX_KINDS: PackedStringArray = ["flash", "shake", "lightning", "blast", "smoke", "dust", "aura", "beam"]
const GOALS: PackedStringArray = ["kunai_hit", "strike_hit", "jutsu_hit", "weak_hit", "cast", "guard", "dash", "charge", "lock_on", "interrupt"]
const TIMES: PackedStringArray = ["dawn", "day", "dusk", "night"]
const WEATHERS: PackedStringArray = ["none", "rain", "storm", "snow", "leaves"]
const CHAPTER_REQUIRED: PackedStringArray = ["id", "number", "title", "location", "time", "beats"]
const CHAPTER_OPTIONAL: PackedStringArray = ["summary", "dummies", "player_at", "weather", "part", "island", "objective", "music"]
const CHARACTER_KEYS: PackedStringArray = ["name", "title", "kanji", "element", "model", "voice", "style"]
## A character's recorded voice (see art/audio/make_voices.py): a Kokoro
## voice (or blend), a speed, and an optional effect.
const VOICE_KEYS: PackedStringArray = ["speaker", "speed", "effect"]
const VOICE_EFFECTS: PackedStringArray = ["", "spirit"]
const NUMERALS: PackedStringArray = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
## The player speaks as "player".
const PLAYER := "player"

## id -> {name, title, kanji, element: int, style: Dictionary}
var characters: Dictionary = {}
## Sorted by number. Each: {id, number, title, location, time, summary,
## dummies, player_at: Vector2, beats: Array[Dictionary]}.
var chapters: Array[Dictionary] = []
## The big chapters, in order: {number, title, kanji, summary}. Each holds the
## missions (entries in `chapters`) whose "part" is its number.
var parts: Array[Dictionary] = []
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


## Where a save picks up: the first chapter not cleared yet ({} once all are).
## Adds people who aren't in the story cast (the open world's quest givers)
## so dialogue and NPCs can use them.
func add_cast(people: Dictionary) -> void:
	for id: String in people:
		if not characters.has(id):
			_parse_character(id, people[id])


func resume_chapter() -> Dictionary:
	for c in chapters:
		if not Game.chapter_done(c["id"]):
			return c
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
	if n >= 0 and n < NUMERALS.size():
		return NUMERALS[n]
	if n < 100:
		# 十一 ... 九十九.
		var tens := n / 10
		var ones := n % 10
		return (NUMERALS[tens] if tens > 1 else "") + "十" + (NUMERALS[ones] if ones > 0 else "")
	return str(n)


## A big chapter by number ({} if none).
func part(number: int) -> Dictionary:
	for p in parts:
		if p["number"] == number:
			return p
	return {}


## The missions of a big chapter, in order.
func missions_in(number: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in chapters:
		if c["part"] == number:
			out.append(c)
	return out


## Which mission of its chapter this is (1-based).
func mission_index(c: Dictionary) -> int:
	return missions_in(c["part"]).find_custom(func(m: Dictionary) -> bool: return m["id"] == c["id"]) + 1


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
		return f.get_extension() == "json" and f != CHARACTERS_FILE and f != PARTS_FILE)
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
	_load_parts(dir)


func _load_parts(dir: String) -> void:
	var data: Variant = _read_json(dir.path_join(PARTS_FILE)) if FileAccess.file_exists(dir.path_join(PARTS_FILE)) else null
	if data is Dictionary and (data as Dictionary).get("parts") is Array:
		for raw: Variant in data["parts"]:
			if not raw is Dictionary or not (raw as Dictionary).has("title"):
				errors.append("%s: each part needs a title" % PARTS_FILE)
				continue
			parts.append({"number": parts.size() + 1, "title": str(raw["title"]), "kanji": str(raw.get("kanji", "")),
				"summary": str(raw.get("summary", ""))})
	# Older data with no parts file: one part per number in use.
	if parts.is_empty():
		var seen := {}
		for c in chapters:
			if not seen.has(c["part"]):
				seen[c["part"]] = true
				parts.append({"number": c["part"], "title": "Part %d" % c["part"], "kanji": "", "summary": ""})
	# Missions run part by part: a mission can't sit in an earlier part than
	# the one before it.
	var last := 0
	for c in chapters:
		if part(c["part"]).is_empty():
			errors.append("%s: no chapter %d in %s" % [c["id"], c["part"], PARTS_FILE])
		if c["part"] < last:
			errors.append("%s: chapter %d comes after chapter %d" % [c["id"], c["part"], last])
		last = c["part"]


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
	if data.has("model") and CharacterModel.resolve_roster(str(data["model"])) == "":
		errors.append("%s: no roster character '%s' in %s" % [label, data["model"], CharacterModel.ROSTER_DIR])
	var voice: Variant = data.get("voice", {})
	if not voice is Dictionary:
		errors.append("%s: 'voice' must be an object" % label)
		voice = {}
	for key: String in voice:
		if not VOICE_KEYS.has(key):
			errors.append("%s: unknown voice key '%s'" % [label, key])
	if not VOICE_EFFECTS.has(str(voice.get("effect", ""))):
		errors.append("%s: unknown voice effect '%s'" % [label, voice["effect"]])
	characters[id] = {
		"name": str(data["name"]),
		"title": str(data.get("title", "")),
		"kanji": str(data["kanji"]),
		"element": maxi(element, 0),
		"model": str(data.get("model", "")),
		"voice": voice,
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
		if key in ["hair_from", "outfit_from"] and CharacterModel.resolve_roster(str(value)) == "":
			errors.append("%s: no roster character '%s' for %s" % [label, value, key])
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


## A music track named in a chapter, a beat or a scene: one of Music.TRACKS.
func _track(label: String, value: Variant) -> String:
	var track := str(value)
	if not Music.TRACKS.has(StringName(track)):
		errors.append("%s: unknown music '%s' (one of %s)" % [label, track, Music.TRACKS])
	return track


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
		"weather": str(data.get("weather", "none")),
		"island": str(data.get("island", "emberwood")),
		"part": int(data.get("part", 1)),
		"objective": str(data.get("objective", "")),
		"music": _track(file, data["music"]) if data.has("music") else "",
		"player_at": _vec2(file, data.get("player_at", [0, 4])),
		"beats": [],
	}
	if not TIMES.has(c["time"]):
		errors.append("%s: time must be one of %s" % [file, TIMES])
	if not WEATHERS.has(c["weather"]):
		errors.append("%s: weather must be one of %s" % [file, WEATHERS])
	if not Island.exists(c["island"]):
		errors.append("%s: no island '%s' (see Island.PRESETS)" % [file, c["island"]])
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
			if raw.has("music"):
				b["music"] = _track(label, raw["music"])
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
			if raw.has("music"):
				b["music"] = _track(label, raw["music"])
			b["text"] = str(raw["text"])
			b["goal"] = str(raw["goal"])
			b["count"] = int(raw.get("count", 1))
			b["jutsu"] = StringName(str(raw.get("jutsu", "")))
			b["enemies"] = _pairs(label, raw.get("enemies", []))
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
		"survive":
			b["seconds"] = float(raw["seconds"])
			b["enemies"] = _pairs(label, raw["enemies"])
			b["max_alive"] = int(raw.get("max_alive", 3))
			b["text"] = str(raw.get("text", "Hold out"))
			if b["enemies"].is_empty():
				errors.append("%s: survive needs enemies [[rank, element], ...]" % label)
		"ally":
			b["who"] = _who(label, raw["who"], false)
			var ally_rank := _ranks(label, [raw["rank"]])
			b["rank"] = ally_rank[0] if not ally_rank.is_empty() else &"chunin"
			b["health"] = float(raw.get("health", 0.0))
			b["at"] = _vec2(label, raw.get("at", [2, 3]))
			present[b["who"]] = true
		"boss":
			b["size"] = float(raw.get("size", 1.0))
			b["aura"] = Color.html(str(raw["aura"])) if raw.has("aura") and Color.html_is_valid(str(raw["aura"])) else Color(0, 0, 0, 0)
			if raw.has("aura") and not Color.html_is_valid(str(raw["aura"])):
				errors.append("%s: aura must be a colour" % label)
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
		"scene":
			b["steps"] = []
			if not raw["steps"] is Array or raw["steps"].is_empty():
				errors.append("%s: steps must be a non-empty list" % label)
			else:
				for i in raw["steps"].size():
					var step := _parse_step("%s step %d" % [label, i + 1], raw["steps"][i], present)
					if not step.is_empty():
						b["steps"].append(step)
	return b


## [[rank, element], ...] -> [[StringName rank, int element], ...]
func _pairs(label: String, raw: Variant) -> Array:
	var out: Array = []
	if not raw is Array:
		errors.append("%s: expected a list of [rank, element]" % label)
		return out
	for p: Variant in raw:
		if not p is Array or p.size() != 2:
			errors.append("%s: entries are [rank, element]" % label)
			continue
		var rank := _ranks(label, [p[0]])
		out.append([rank[0] if not rank.is_empty() else &"genin", _element(label, p[1])])
	return out


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


## One cutscene step, checked and filled in with defaults.
func _parse_step(label: String, raw: Variant, present: Dictionary) -> Dictionary:
	if not raw is Dictionary:
		errors.append("%s: must be an object" % label)
		return {}
	var actions: Array = raw.keys().filter(func(k: Variant) -> bool: return SCENE_STEPS.has(k))
	if actions.size() != 1:
		errors.append("%s: needs exactly one of %s" % [label, SCENE_STEPS.keys()])
		return {}
	var action: String = actions[0]
	for key: String in raw:
		if key != action and key != "async" and not SCENE_STEPS[action].has(key):
			errors.append("%s (%s): unknown key '%s'" % [label, action, key])
	var v: Variant = raw[action]
	var s := {"action": action, "async": bool(raw.get("async", false))}
	match action:
		"wait":
			s["seconds"] = float(v)
		"cam":
			var kind := str(v)
			if not SHOTS.has(kind):
				errors.append("%s: unknown shot '%s' (one of %s)" % [label, kind, SHOTS.keys()])
				return {}
			var d: Array = SHOTS[kind]
			s["cam"] = kind
			s["seconds"] = float(raw.get("seconds", 2.0))
			s["blend"] = float(raw.get("blend", 0.0))
			s["fov"] = float(raw.get("fov", d[3]))
			s["dist"] = float(raw.get("dist", d[0]))
			s["height"] = float(raw.get("height", d[1]))
			s["side"] = float(raw.get("side", d[2]))
			s["radius"] = float(raw.get("radius", 5.0))
			s["degrees"] = float(raw.get("degrees", 90.0))
			match kind:
				"free":
					if not raw.has("at") or not raw.has("look"):
						errors.append("%s: a free shot needs 'at' and 'look'" % label)
						return {}
					for key in ["at", "to", "look", "look_to"]:
						if raw.has(key):
							s[key] = _target(label, raw[key], present)
				"two":
					if not raw.get("on") is Array or raw["on"].size() != 2:
						errors.append("%s: a two shot is 'on': [who, who]" % label)
						return {}
					s["on"] = [_actor(label, raw["on"][0], present, true), _actor(label, raw["on"][1], present, true)]
				"over":
					s["from"] = _actor(label, raw.get("from", PLAYER), present, true)
					s["on"] = _actor(label, raw.get("on", ""), present, true)
				_:
					s["on"] = _actor(label, raw.get("on", ""), present, true)
		"say":
			var say := _parse_beat(label, {"do": "say", "lines": v}, present)
			if say.is_empty():
				return {}
			s["lines"] = say["lines"]
		"enter":
			s["who"] = _who(label, v, false)
			s["at"] = _vec2(label, raw.get("at", null))
			s["from"] = _vec3(label, raw["from"]) if raw.has("from") else null
			s["puff"] = bool(raw.get("puff", true))
			present[s["who"]] = true
			s["facing"] = _target(label, raw["facing"], present) if raw.has("facing") else null
		"exit":
			s["who"] = _who(label, v, false)
			if not present.has(s["who"]):
				errors.append("%s: '%s' exits without having entered" % [label, s["who"]])
			present.erase(s["who"])
			s["puff"] = bool(raw.get("puff", true))
		"move":
			s["who"] = _actor(label, v, present, true)
			s["to"] = _target(label, raw.get("to", null), present)
			s["run"] = bool(raw.get("run", false))
		"leap":
			s["who"] = _actor(label, v, present, false)
			s["to"] = _target(label, raw.get("to", null), present)
			s["from"] = _vec3(label, raw["from"]) if raw.has("from") else null
			s["height"] = float(raw.get("height", 2.5))
			s["seconds"] = float(raw.get("seconds", 0.0))
		"face":
			s["who"] = _actor(label, v, present, true)
			s["to"] = _target(label, raw.get("to", null), present)
		"pose":
			s["who"] = _actor(label, v, present, true)
			var pose := str(raw.get("as", ""))
			if not SCENE_POSES.has(pose):
				errors.append("%s: pose 'as' is one of %s" % [label, SCENE_POSES.keys()])
			s["as"] = SCENE_POSES.get(pose, HumanoidPoser.Pose.LOCOMOTION)
			s["seconds"] = float(raw.get("seconds", 0.0))
		"weave":
			s["who"] = _actor(label, v, present, true)
			s["seals"] = []
			for seal_name: Variant in raw.get("seals", []):
				var seal := Seal.from_name(str(seal_name))
				if seal < 0:
					errors.append("%s: unknown seal '%s'" % [label, seal_name])
				else:
					s["seals"].append(seal)
			if s["seals"].is_empty():
				errors.append("%s: weave needs 'seals'" % label)
		"cast":
			s["who"] = _actor(label, v, present, true)
			s["element"] = _element(label, raw.get("element", "none"))
			s["at"] = _target(label, raw.get("at", null), present)
			s["kind"] = str(raw.get("kind", "projectile"))
			if not CAST_KINDS.has(s["kind"]):
				errors.append("%s: cast kind is one of %s" % [label, CAST_KINDS])
		"fx":
			s["fx"] = str(v)
			if not FX_KINDS.has(s["fx"]):
				errors.append("%s: unknown fx '%s' (one of %s)" % [label, v, FX_KINDS])
				return {}
			s["element"] = _element(label, raw["element"]) if raw.has("element") else Element.NONE
			s["color"] = Element.color(s["element"]) if raw.has("element") else Color.WHITE
			if raw.has("color"):
				if Color.html_is_valid(str(raw["color"])):
					s["color"] = Color.html(str(raw["color"]))
				else:
					errors.append("%s: color must be a colour like \"#ffffff\"" % label)
			s["seconds"] = float(raw.get("seconds", 0.0))
			s["size"] = float(raw.get("size", 1.0))
			var needs: Dictionary = {"lightning": ["at"], "blast": ["at"], "smoke": ["at"], "dust": ["at"],
				"aura": ["on"], "beam": ["from", "to"]}
			for key: String in needs.get(s["fx"], []):
				if not raw.has(key):
					errors.append("%s: fx %s needs '%s'" % [label, s["fx"], key])
					return {}
			for key in ["at", "from", "to"]:
				if raw.has(key):
					s[key] = _target(label, raw[key], present)
			if raw.has("on"):
				s["on"] = _actor(label, raw["on"], present, true)
		"grow":
			s["who"] = _actor(label, v, present, false)
			s["scale"] = float(raw.get("scale", 1.0))
			s["seconds"] = float(raw.get("seconds", 1.0))
		"music":
			s["track"] = str(v)
			if s["track"] != "none":
				_track(label, v)
		"sfx":
			s["sound"] = str(v)
			if not ResourceLoader.exists("res://assets/audio/sfx/%s.wav" % s["sound"]):
				errors.append("%s: unknown sound '%s'" % [label, v])
		"time":
			s["time"] = str(v)
			if not TIMES.has(s["time"]):
				errors.append("%s: time is one of %s" % [label, TIMES])
		"weather":
			s["weather"] = str(v)
			if not WEATHERS.has(s["weather"]):
				errors.append("%s: weather is one of %s" % [label, WEATHERS])
		"fade":
			s["fade"] = str(v)
			if not s["fade"] in ["in", "out"]:
				errors.append("%s: fade is \"in\" or \"out\"" % label)
			s["seconds"] = float(raw.get("seconds", 0.8))
			var color := str(raw.get("color", "#000000"))
			s["color"] = Color.html(color) if Color.html_is_valid(color) else Color.BLACK
		"title":
			s["title"] = str(v)
			s["sub"] = str(raw.get("sub", ""))
			s["seconds"] = float(raw.get("seconds", 3.0))
	return s


## A character a step acts on: on stage (or the player, if allowed).
func _actor(label: String, raw: Variant, present: Dictionary, allow_player: bool) -> String:
	var who := _who(label, raw, allow_player)
	if who != PLAYER and not present.has(who):
		errors.append("%s: '%s' isn't on stage (enter them first)" % [label, who])
	return who


## Where a step points: a character on stage (or the player), [x, z] on the
## ground or [x, y, z].
func _target(label: String, raw: Variant, present: Dictionary) -> Variant:
	if raw is String:
		return _actor(label, raw, present, true)
	if raw is Array and raw.size() == 3:
		return _vec3(label, raw)
	return _vec2(label, raw)


func _vec3(label: String, raw: Variant) -> Vector3:
	if raw is Array and raw.size() == 3 and raw.all(func(n: Variant) -> bool: return n is float or n is int):
		return Vector3(raw[0], raw[1], raw[2])
	errors.append("%s: points are [x, y, z]" % label)
	return Vector3.ZERO
