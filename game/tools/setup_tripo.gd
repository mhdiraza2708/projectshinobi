extends SceneTree
## Configures every Tripo character (exported with the Mixamo skeleton
## preset) for Godot's humanoid retargeting, the same way as Mixamo clips:
## bone map, renamed bones and a unique "GeneralSkeleton", so the game's
## clips and poser drive them. Covers the main character, rivals and bosses.
##
## Run via `make tripo`, which imports, runs this, and re-imports.

const DIRS := ["res://assets/characters/main", "res://assets/characters/rivals", "res://assets/characters/bosses"]
const SetupMixamo := preload("res://tools/setup_mixamo.gd")


func _initialize() -> void:
	var configured := 0
	for dir: String in DIRS:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for file in DirAccess.get_files_at(dir):
			var path := dir.path_join(file)
			# Once configured, the skeleton is already renamed: leave it be.
			if file.get_extension().to_lower() in ["glb", "fbx"] and not _configured(path):
				if SetupMixamo.configure(path):
					configured += 1
	print("Configured %d Tripo character(s). Re-import to apply." % configured)
	quit(0)


static func _configured(path: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path + ".import") != OK:
		return false
	return var_to_str(cfg.get_value("params", "_subresources", {})).contains("retarget/bone_map")
