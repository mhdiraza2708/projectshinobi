extends Node
## Loads extra content packs (*.pck) that sit next to the game executable,
## such as the character packs, before anything else looks for them.
## Autoloaded first as `Packs`. In the editor there are none to load.

## The packs that loaded, by file name.
var loaded: PackedStringArray = []


func _init() -> void:
	if OS.has_feature("editor"):
		return
	var dir := OS.get_executable_path().get_base_dir()
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.get_extension() == "pck")
	files.sort()
	for f: String in files:
		if ProjectSettings.load_resource_pack(dir.path_join(f), false):
			loaded.append(f)
		else:
			push_warning("Packs: could not load %s" % f)
