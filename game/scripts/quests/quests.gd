class_name Quests
extends RefCounted
## The open world's quests. The main quest is the story: the next chapter
## not yet cleared, played where it happens. Side quests are data
## (res://data/quests.json): someone on an island asks for help (gather,
## defeat, duel or deliver), and a quest opens once its "requires" (a chapter
## or another quest) is done. Progress lives in the save slot (Game records,
## section "quests"); finishing one gives XP (SkillTrees).

const FILE := "res://data/quests.json"
const TYPES: PackedStringArray = ["gather", "defeat", "duel", "deliver"]
const ITEMS := {
	"kunai": {"name": "practice kunai", "color": "#c9d2dc"},
	"herb": {"name": "red-leaf herbs", "color": "#d9452e"},
	"seal": {"name": "warding seals", "color": "#f2e6c8"},
}
## The id the main (story) quest is tracked under.
const MAIN := "main"

## Statuses.
const LOCKED := "locked"
const AVAILABLE := "available"
const ACTIVE := "active"
const DONE := "done"

static var errors: Array[String] = []
static var _people: Dictionary = {}
static var _list: Array[Dictionary] = []
static var _loaded := false


static func reload() -> void:
	errors = []
	_list = []
	_people = {}
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	if not parsed is Dictionary:
		errors.append("%s: not a JSON object" % FILE)
		return
	_people = parsed.get("people", {})
	var seen := {}
	for raw: Variant in parsed.get("quests", []):
		var q: Dictionary = raw
		for key: String in ["id", "name", "kanji", "island", "giver", "giver_at", "requires", "type", "objective", "intro", "xp"]:
			if not q.has(key):
				errors.append("quest %s: missing %s" % [q.get("id", "?"), key])
		if seen.has(q.get("id")):
			errors.append("quest %s appears twice" % q["id"])
		seen[q.get("id")] = true
		if not TYPES.has(str(q.get("type"))):
			errors.append("quest %s: unknown type '%s'" % [q.get("id"), q.get("type")])
		if not Archipelago.LAYOUT.has(str(q.get("island"))):
			errors.append("quest %s: unknown island '%s'" % [q.get("id"), q.get("island")])
		match str(q.get("type")):
			"gather":
				if not ITEMS.has(str(q.get("item"))) or int(q.get("count", 0)) < 1:
					errors.append("quest %s: gather needs a known item and a count" % q.get("id"))
			"defeat":
				if not q.get("waves") is Array or (q["waves"] as Array).is_empty():
					errors.append("quest %s: defeat needs waves" % q.get("id"))
			"duel":
				if not q.get("foe") is Dictionary:
					errors.append("quest %s: duel needs a foe" % q.get("id"))
			"deliver":
				if not Archipelago.LAYOUT.has(str(q.get("to_island"))) or not q.has("to_at"):
					errors.append("quest %s: deliver needs to_island and to_at" % q.get("id"))
		_list.append(q)
	for q in _list:
		for who in [q.get("giver"), q.get("to")]:
			if who != null and not person(str(who)).has("name"):
				errors.append("quest %s: nobody called '%s'" % [q["id"], who])


static func _ensure() -> void:
	if not _loaded:
		reload()


static func all() -> Array[Dictionary]:
	_ensure()
	return _list


static func quest(id: String) -> Dictionary:
	for q in all():
		if q["id"] == id:
			return q
	return {}


## Someone quests mention: a quest person, or a story character.
static func person(who: String) -> Dictionary:
	_ensure()
	if _people.has(who):
		return _people[who]
	var cast: Variant = JSON.parse_string(FileAccess.get_file_as_string(Story.DIR.path_join(Story.CHARACTERS_FILE)))
	if cast is Dictionary and (cast as Dictionary).has(who):
		return cast[who]
	return {}


static func people() -> Dictionary:
	_ensure()
	return _people


# --- State ---------------------------------------------------------------------

static func status(id: String) -> String:
	var saved := str(Game.record("quests", id, ""))
	if saved == ACTIVE or saved == DONE:
		return saved
	return AVAILABLE if requirement_met(id) else LOCKED


## Whether what a quest requires (a chapter or a quest) is done.
static func requirement_met(id: String) -> bool:
	var need := str(quest(id).get("requires", ""))
	if need == "":
		return true
	if quest(need).has("id"):
		return status(need) == DONE
	return Game.chapter_done(need)


static func accept(id: String) -> bool:
	if status(id) != AVAILABLE:
		return false
	Game.set_record("quests", id, ACTIVE)
	Game.set_record("quests", id + ":progress", 0)
	set_tracked(id)
	Game.save_records()
	return true


static func progress(id: String) -> int:
	return int(Game.record("quests", id + ":progress", 0))


static func set_progress(id: String, value: int) -> void:
	Game.set_record("quests", id + ":progress", value)


## Marks a quest done and pays its XP. Returns whether it was active.
static func complete(id: String) -> bool:
	if status(id) != ACTIVE:
		return false
	Game.set_record("quests", id, DONE)
	if tracked() == id:
		set_tracked(MAIN)
	Game.add_xp(int(quest(id).get("xp", 0)), "quest")
	Game.save_records()
	return true


## Gives a quest up (it can be taken again).
static func abandon(id: String) -> void:
	if status(id) == ACTIVE:
		Game.set_record("quests", id, "")
		Game.set_record("quests", id + ":progress", 0)
		if tracked() == id:
			set_tracked(MAIN)


static func with_status(wanted: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q in all():
		if status(q["id"]) == wanted:
			out.append(q)
	return out


## The quest the HUD points at: MAIN or a side quest id.
static func tracked() -> String:
	var id := str(Game.record("quests", "tracked", MAIN))
	return id if id == MAIN or status(id) == ACTIVE else MAIN


static func set_tracked(id: String) -> void:
	Game.set_record("quests", "tracked", id)


## The chapter the main quest is on ({} once the story is over).
static func main_chapter(story: Story) -> Dictionary:
	return story.resume_chapter()


## How much a quest still needs ("3 / 6"), or "".
static func counter(id: String) -> String:
	var q := quest(id)
	match str(q.get("type")):
		"gather":
			return "%d / %d" % [progress(id), int(q["count"])]
		"defeat":
			return "wave %d / %d" % [mini(progress(id) + 1, (q["waves"] as Array).size()), (q["waves"] as Array).size()]
	return ""
