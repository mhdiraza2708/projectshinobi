extends Node
## Headless test runner. Run with:
##   godot --headless --path game res://tests/test_runner.tscn
## Exits with code 1 if any test fails. Pass `-- --filter=<text>` to run only
## suites or tests whose name contains <text>.

const UNIT_DIR := "res://tests/unit"


func _ready() -> void:
	# Tests must never read or clobber the player's real settings file.
	Settings.persist = false
	Settings.load_from_disk()

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
			suite.before_each()
			await suite.call(name)
			suite.after_each()
			# Reset shared global state between tests.
			Settings.load_from_disk()
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
