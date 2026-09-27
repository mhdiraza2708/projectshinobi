extends Node
## Loads the content packs (characters_*.pck and other *.pck) that ship
## beside the game, before anything else looks for their content.
## Autoloaded first as `Packs`. In the editor there are none to load.
##
## Packs are looked for next to the executable first, then nearby: Windows'
## "Extract All" puts each downloaded archive in its own folder, so a pack
## often ends up in a sibling folder (Downloads\ProjectShinobi-Characters-1\
## ProjectShinobi\characters_1.pck) rather than beside the exe.

## Pack file names this game makes (anything else is ignored when searching
## outside the executable's own folder).
const PREFIXES: PackedStringArray = ["characters_", "audio_"]
## How deep to look below the folder two levels above the executable.
const SEARCH_DEPTH := 3

## Loaded packs, as full paths.
var loaded: PackedStringArray = []


func _init() -> void:
	if OS.has_feature("editor"):
		return
	var exe_dir := OS.get_executable_path().get_base_dir()
	var by_name := {}
	# Beside the exe (any .pck), then nearby (only this game's packs).
	for f in DirAccess.get_files_at(exe_dir):
		if f.get_extension() == "pck":
			by_name[f] = exe_dir.path_join(f)
	var root := exe_dir.get_base_dir().get_base_dir()
	if root == "" or root == exe_dir:
		root = exe_dir.get_base_dir()
	for path in find_packs(root, SEARCH_DEPTH):
		if not by_name.has(path.get_file()):
			by_name[path.get_file()] = path
	var names := by_name.keys()
	names.sort()
	for n: String in names:
		if ProjectSettings.load_resource_pack(by_name[n], false):
			loaded.append(by_name[n])
		else:
			push_warning("Packs: could not load %s" % by_name[n])


## This game's pack files under `dir`, at most `depth` folders down.
static func find_packs(dir: String, depth: int) -> PackedStringArray:
	var out := PackedStringArray()
	if depth < 0 or not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() == "pck" and Array(PREFIXES).any(func(p: String) -> bool: return f.begins_with(p)):
			out.append(dir.path_join(f))
	if depth > 0:
		for d in DirAccess.get_directories_at(dir):
			if d.begins_with("."):
				continue
			out.append_array(find_packs(dir.path_join(d), depth - 1))
	return out


## True when the bundled VRoid characters are available.
static func characters_installed() -> bool:
	return ResourceLoader.exists(CharacterModel.DEFAULT_MODEL)
