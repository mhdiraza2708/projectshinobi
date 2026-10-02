extends Node
## Which mode the game scene starts in, story progress, trial records and
## play time. Saved in the active save slot (see SaveSlots). Autoloaded as
## `Game`.

enum Mode { TITLE, TRAINING, TRIAL, STORY }

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


## A new game: no progress, no records.
func reset_records() -> void:
	_records = ConfigFile.new()
	playtime = 0.0
	_since_save = 0.0


func save_records() -> void:
	_since_save = 0.0
	if not persist or path() == "":
		return
	_records.set_value("meta", "playtime", playtime)
	DirAccess.make_dir_recursive_absolute(path().get_base_dir())
	_records.save(path())


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
