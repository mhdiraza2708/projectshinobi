extends Node
## Which mode the game scene starts in, story progress and trial records.
## Autoloaded as `Game`.

enum Mode { TITLE, TRAINING, TRIAL, STORY }

const RECORDS_PATH := "user://records.cfg"

## Read by the game scene when it loads. Tests set TRAINING.
var start_mode := Mode.TITLE
## The chapter id a STORY start plays.
var story_chapter := ""
## When false nothing touches disk (tests, screenshots).
var persist := true

var _records := ConfigFile.new()


func _ready() -> void:
	load_records()


func load_records() -> void:
	_records = ConfigFile.new()
	if persist:
		_records.load(RECORDS_PATH)


## Best completion time in seconds for `trial`, or 0.0 if never completed.
func best_time(trial: String) -> float:
	return float(_records.get_value("best_time", trial, 0.0))


## Stores `seconds` if it beats the best time. Returns true for a new record.
func record_time(trial: String, seconds: float) -> bool:
	var best := best_time(trial)
	if best > 0.0 and seconds >= best:
		return false
	_records.set_value("best_time", trial, seconds)
	if persist:
		_records.save(RECORDS_PATH)
	return true


## Reloads the game scene in `mode`.
func restart(mode: Mode) -> void:
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
	if persist:
		_records.save(RECORDS_PATH)


static func format_time(seconds: float) -> String:
	return "%d:%04.1f" % [int(seconds) / 60, fmod(seconds, 60.0)]
