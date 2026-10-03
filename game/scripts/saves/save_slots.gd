class_name SaveSlots
extends RefCounted
## Ten save slots. Each is a separate game: its own shinobi (the Profile:
## look, clan, eye art, name, jutsu loadouts), story progress and records
## (Game). They live in user://saves/slot_N/. Settings (controls, audio,
## accessibility) belong to the machine, not a slot.
##
## No active slot means "no game loaded yet": nothing is written to disk.

const COUNT := 10

## Where the slots live (tests point this somewhere disposable).
static var root := "user://saves"
## The slot being played (1-based), 0 for none.
static var active := 0

## The single save of earlier versions (tests point these elsewhere).
static var legacy_profile := "user://profile.cfg"
static var legacy_records := "user://records.cfg"


static func slot_dir(slot: int) -> String:
	return "%s/slot_%d" % [root, slot]


## The active slot's Profile file ("" with no slot: nothing is saved).
static func profile_path(slot := active) -> String:
	return "" if slot < 1 else slot_dir(slot).path_join("profile.cfg")


static func records_path(slot := active) -> String:
	return "" if slot < 1 else slot_dir(slot).path_join("records.cfg")


static func exists(slot: int) -> bool:
	return slot >= 1 and slot <= COUNT and FileAccess.file_exists(profile_path(slot))


static func any() -> bool:
	for slot in range(1, COUNT + 1):
		if exists(slot):
			return true
	return false


## The slot played most recently (0 if none survives).
static func last() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(root.path_join("last.cfg")) != OK:
		return 0
	var slot := int(cfg.get_value("last", "slot", 0))
	return slot if exists(slot) else 0


static func first_free() -> int:
	for slot in range(1, COUNT + 1):
		if not exists(slot):
			return slot
	return 0


## Called once at start-up (before the Profile reads its file): brings an
## old single save into slot 1 and picks the slot played last.
static func boot() -> void:
	_migrate_legacy()
	var slot := last()
	if slot > 0:
		active = slot


## Switches to a saved slot: loads its character and progress.
static func activate(slot: int) -> void:
	assert(exists(slot))
	active = slot
	_write_last(slot)
	Profile.reload()
	Game.load_records()


## Starts a new game in `slot` (erasing whatever was there): a fresh
## character that hasn't been created yet.
static func create(slot: int) -> void:
	assert(slot >= 1 and slot <= COUNT)
	erase(slot)
	DirAccess.make_dir_recursive_absolute(slot_dir(slot))
	active = slot
	_write_last(slot)
	Game.reset_records()
	Profile.reset()
	Game.save_records()


static func erase(slot: int) -> void:
	var dir := slot_dir(slot)
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)
	if active == slot:
		# Nothing is loaded any more: the title shows a blank character.
		active = 0
		Game.reset_records()
		Profile.reset()
	if last() == 0 and FileAccess.file_exists(root.path_join("last.cfg")):
		DirAccess.remove_absolute(root.path_join("last.cfg"))


## What a slot's card shows, read straight from its files (so it never goes
## stale): {exists, name, clan, nature, created, cleared, playtime, modified}.
static func meta(slot: int) -> Dictionary:
	var profile := ConfigFile.new()
	if not exists(slot) or profile.load(profile_path(slot)) != OK:
		return {"exists": false}
	var records := ConfigFile.new()
	records.load(records_path(slot))
	var cleared := 0
	if records.has_section("story"):
		for chapter in records.get_section_keys("story"):
			if bool(records.get_value("story", chapter, false)):
				cleared += 1
	return {
		"exists": true,
		"name": str(profile.get_value("profile", "name", "Nameless")),
		"clan": str(profile.get_value("profile", "clan", "")),
		"nature": int(profile.get_value("profile", "affinity", Element.FIRE)),
		"created": bool(profile.get_value("profile", "created", false)),
		"cleared": cleared,
		"level": SkillTrees.level_for_xp(int(records.get_value("skills", "xp", 0))),
		"playtime": float(records.get_value("meta", "playtime", 0.0)),
		"modified": FileAccess.get_modified_time(profile_path(slot)),
	}


## "2h 05m" / "14m" / "new".
static func format_playtime(seconds: float) -> String:
	var minutes := int(seconds / 60.0)
	if minutes < 1:
		return "just begun"
	return "%dh %02dm" % [minutes / 60, minutes % 60] if minutes >= 60 else "%dm" % minutes


static func _write_last(slot: int) -> void:
	if not Profile.persist:
		return
	DirAccess.make_dir_recursive_absolute(root)
	var cfg := ConfigFile.new()
	cfg.set_value("last", "slot", slot)
	cfg.save(root.path_join("last.cfg"))


## The single profile/records of earlier versions become slot 1 (the old
## files are left in place).
static func _migrate_legacy() -> void:
	if exists(1) or not FileAccess.file_exists(legacy_profile):
		return
	var profile := ConfigFile.new()
	if profile.load(legacy_profile) != OK:
		return
	DirAccess.make_dir_recursive_absolute(slot_dir(1))
	# A character from before slots was already created.
	profile.set_value("profile", "created", true)
	profile.save(profile_path(1))
	if FileAccess.file_exists(legacy_records):
		DirAccess.copy_absolute(legacy_records, records_path(1))
	_write_last_raw(1)


static func _write_last_raw(slot: int) -> void:
	DirAccess.make_dir_recursive_absolute(root)
	var cfg := ConfigFile.new()
	cfg.set_value("last", "slot", slot)
	cfg.save(root.path_join("last.cfg"))
