extends Node
## Headless test runner. Run with:
##   godot --headless --path game res://tests/test_runner.tscn
## Exits with code 1 if any test fails. Pass `-- --filter=<text>` to run only
## suites or tests whose name contains <text>.

const UNIT_DIR := "res://tests/unit"


## Records GDScript runtime errors: they abort a test function silently, so
## without this a crashing test would still count as passed.
class ScriptErrorCatcher extends Logger:
	var errors: PackedStringArray = []
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != Logger.ERROR_TYPE_SCRIPT:
			return
		_lock.lock()
		errors.append("%s (%s:%d in %s)" % [rationale if rationale != "" else code, file, line, function])
		_lock.unlock()

	func take() -> PackedStringArray:
		_lock.lock()
		var out := errors.duplicate()
		errors.clear()
		_lock.unlock()
		return out


func _ready() -> void:
	# Tests must never read or clobber the player's real settings/profile.
	Settings.persist = false
	Settings.load_from_disk()
	Profile.persist = false
	Profile.load_from_disk()
	Game.persist = false
	Game.load_records()
	Game.start_mode = Game.Mode.TRAINING
	var catcher := ScriptErrorCatcher.new()
	OS.add_logger(catcher)

	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")

	var files := Array(DirAccess.get_files_at(UNIT_DIR)).filter(
		func(f: String) -> bool: return f.begins_with("test_") and f.ends_with(".gd"))
	files.sort()

	var passed := 0
	var failed: Array[String] = []
	for file: String in files:
		var suite: TestCase = load(UNIT_DIR.path_join(file)).new()
		suite.root = self
		for method in suite.get_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			if filter != "" and not (file.contains(filter) or name.contains(filter)):
				continue
			suite._current = "%s::%s" % [file.get_basename(), name]
			var before := suite.failures.size()
			catcher.take()
			suite.before_each()
			await suite.call(name)
			suite.after_each()
			for err in catcher.take():
				suite.fail("script error: " + err)
			# Reset shared global state between tests.
			get_tree().paused = false
			Settings.load_from_disk()
			Profile.load_from_disk()
			Game.load_records()
			Game.start_mode = Game.Mode.TRAINING
			for child in get_children():
				child.queue_free()
			await get_tree().process_frame
			if suite.failures.size() == before:
				passed += 1
				print("  PASS  ", suite._current)
			else:
				for f in suite.failures.slice(before):
					failed.append(f)
					print("  FAIL  ", f)

	print("\n%d passed, %d failed" % [passed, failed.size()])
	get_tree().quit(1 if not failed.is_empty() or passed == 0 else 0)
