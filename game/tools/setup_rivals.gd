extends SceneTree
## Configures every rival model in res://assets/characters/rivals/ (Tripo
## exports with the Mixamo skeleton preset) for Godot's humanoid
## retargeting, the same way as Mixamo clips: bone map, renamed bones and a
## unique "GeneralSkeleton", so the game's clips and poser drive them.
##
## Run via `make rivals`, which imports, runs this, and re-imports.

const RIVAL_DIR := "res://assets/characters/rivals"
const SetupMixamo := preload("res://tools/setup_mixamo.gd")


func _initialize() -> void:
	var configured := 0
	for file in DirAccess.get_files_at(RIVAL_DIR):
		if file.get_extension().to_lower() in ["glb", "fbx"]:
			if SetupMixamo.configure(RIVAL_DIR.path_join(file)):
				configured += 1
	print("Configured %d rival model(s). Re-import to apply." % configured)
	quit(0)
