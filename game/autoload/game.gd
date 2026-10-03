extends Node
## Which mode the game scene starts in, story progress, trial records and
## play time. Saved in the active save slot (see SaveSlots). Autoloaded as
## `Game`.

enum Mode { TITLE, TRAINING, TRIAL, STORY, WORLD }

## Experience was earned (`reason` is a SkillTrees XP key).
signal xp_gained(amount: int, reason: String)
## A new level: one more skill point to spend.
signal leveled_up(level: int)
## A skill was learned, or the points were taken back.
signal skills_changed

## Read by the game scene when it loads. Tests set TRAINING.
var start_mode := Mode.TITLE
## The chapter id a STORY start plays.
var story_chapter := ""
## When false nothing touches disk (tests, screenshots).
var persist := true
## Overridable for tests; empty = the active save slot's file.
var records_path := ""
## Seconds played in the active slot. Counts only while `tracking` (the game
## scene sets it outside the title screen) and not paused.
var playtime := 0.0
var tracking := false

const AUTOSAVE_EVERY := 30.0

var _records := ConfigFile.new()
var _since_save := 0.0


func _ready() -> void:
	load_records()


func _process(delta: float) -> void:
	if not tracking or get_tree().paused:
		return
	playtime += delta
	_since_save += delta
	if _since_save >= AUTOSAVE_EVERY:
		save_records()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		save_records()


func path() -> String:
	return records_path if records_path != "" else SaveSlots.records_path()


func load_records() -> void:
	_records = ConfigFile.new()
	if persist and path() != "":
		_records.load(path())
	playtime = float(_records.get_value("meta", "playtime", 0.0))
	_since_save = 0.0
	SkillTrees.invalidate()


## A new game: no progress, no records.
func reset_records() -> void:
	_records = ConfigFile.new()
	playtime = 0.0
	_since_save = 0.0
	SkillTrees.invalidate()


func save_records() -> void:
	_since_save = 0.0
	if not persist or path() == "":
		return
	_records.set_value("meta", "playtime", playtime)
	DirAccess.make_dir_recursive_absolute(path().get_base_dir())
	_records.save(path())


## The ultimate meter, carried from fight to fight and saved with the slot
## (on the next autosave, scene change or quit).
func ult_charge() -> float:
	return float(_records.get_value("ultimate", "charge", 0.0))


func set_ult_charge(value: float) -> void:
	_records.set_value("ultimate", "charge", value)


## A value saved in the slot's records (quests, the open world).
func record(section: String, key: String, default: Variant = null) -> Variant:
	# ConfigFile reads a null default as "no default" and complains.
	if not _records.has_section_key(section, key):
		return default
	return _records.get_value(section, key)


func set_record(section: String, key: String, value: Variant) -> void:
	_records.set_value(section, key, value)


## Experience earned in this slot (see SkillTrees for what it's worth).
func xp() -> int:
	return int(_records.get_value("skills", "xp", 0))


## Adds experience and announces any new levels. Returns the levels gained.
func add_xp(amount: int, reason := "") -> int:
	if amount <= 0:
		return 0
	var before := SkillTrees.level()
	_records.set_value("skills", "xp", xp() + amount)
	xp_gained.emit(amount, reason)
	var after := SkillTrees.level()
	for level in range(before + 1, after + 1):
		leveled_up.emit(level)
	return after - before


## Ranks learned in each skill node: {node_id: rank}.
func skill_ranks() -> Dictionary:
	return (_records.get_value("skills", "ranks", {}) as Dictionary).duplicate()


func set_skill_ranks(ranks: Dictionary) -> void:
	_records.set_value("skills", "ranks", ranks)
	SkillTrees.invalidate()
	skills_changed.emit()


## Best completion time in seconds for `trial`, or 0.0 if never completed.
func best_time(trial: String) -> float:
	return float(_records.get_value("best_time", trial, 0.0))


## Stores `seconds` if it beats the best time. Returns true for a new record.
func record_time(trial: String, seconds: float) -> bool:
	var best := best_time(trial)
	if best > 0.0 and seconds >= best:
		return false
	_records.set_value("best_time", trial, seconds)
	save_records()
	return true


## Reloads the game scene in `mode`.
func restart(mode: Mode) -> void:
	save_records()
	start_mode = mode
	get_tree().paused = false
	get_tree().reload_current_scene()


## Reloads the game scene into the open world.
func start_world() -> void:
	restart(Mode.WORLD)


## Reloads the game scene into a story chapter.
func start_story(chapter_id: String) -> void:
	story_chapter = chapter_id
	restart(Mode.STORY)


func chapter_done(chapter_id: String) -> bool:
	return bool(_records.get_value("story", chapter_id, false))


func mark_chapter_done(chapter_id: String) -> void:
	_records.set_value("story", chapter_id, true)
	save_records()


static func format_time(seconds: float) -> String:
	return "%d:%04.1f" % [int(seconds) / 60, fmod(seconds, 60.0)]
