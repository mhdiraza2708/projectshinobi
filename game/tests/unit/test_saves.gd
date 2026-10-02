extends TestCase
## Save slots: three independent games (character, progress, play time) in
## separate folders, a nothing-is-saved state before a game is loaded, and
## the old single save becoming slot 1.

const TMP := "user://test_saves"

var _was_persist: Array = []


func before_each() -> void:
	_was_persist = [Profile.persist, Game.persist]
	_wipe(TMP)
	SaveSlots.root = TMP
	SaveSlots.active = 0
	SaveSlots.legacy_profile = TMP + "_old_profile.cfg"
	SaveSlots.legacy_records = TMP + "_old_records.cfg"
	Profile.persist = true
	Game.persist = true


func after_each() -> void:
	SaveSlots.root = "user://saves"
	SaveSlots.active = 0
	SaveSlots.legacy_profile = "user://profile.cfg"
	SaveSlots.legacy_records = "user://records.cfg"
	Profile.persist = false
	Game.persist = false
	_wipe(TMP)
	for f in [TMP + "_old_profile.cfg", TMP + "_old_records.cfg"]:
		DirAccess.remove_absolute(f)
	# Back to a default character so later tests start clean.
	Profile.reset()
	Game.reset_records()
	Game.tracking = false


static func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func test_slots_are_independent_games() -> void:
	SaveSlots.create(1)
	Profile.set_value(&"name", "Kaze")
	Profile.set_value(&"clan", "hearth")
	Game.mark_chapter_done("ch1_graduation")
	SaveSlots.create(2)
	assert_eq(Profile.get_value(&"name"), "Nameless", "a new game starts from a blank shinobi")
	assert_false(Game.chapter_done("ch1_graduation"), "with no progress")
	Profile.set_value(&"name", "Rin")
	SaveSlots.activate(1)
	assert_eq(Profile.get_value(&"name"), "Kaze", "slot 1 kept its shinobi")
	assert_eq(Profile.get_value(&"clan"), "hearth")
	assert_true(Game.chapter_done("ch1_graduation"), "and its progress")
	SaveSlots.activate(2)
	assert_eq(Profile.get_value(&"name"), "Rin", "slot 2 kept its own")
	assert_false(Game.chapter_done("ch1_graduation"))


func test_loading_reports_a_change_so_the_character_reloads() -> void:
	SaveSlots.create(1)
	Profile.set_value(&"name", "A")
	SaveSlots.create(2)
	var changed := []
	var listener := func(key: StringName) -> void: changed.append(key)
	Profile.changed.connect(listener)
	SaveSlots.activate(1)
	Profile.changed.disconnect(listener)
	assert_true(changed.has(&""), "everything about the character changed")


func test_slot_cards_read_from_the_files() -> void:
	SaveSlots.create(1)
	Profile.set_value(&"name", "Kaze")
	Profile.set_value(&"affinity", Element.WIND)
	Profile.set_value(&"clan", "gale")
	Game.mark_chapter_done("ch1_graduation")
	Game.mark_chapter_done("ch2_rival")
	Game.playtime = 3725.0
	Game.save_records()
	var m := SaveSlots.meta(1)
	assert_true(m["exists"])
	assert_eq(m["name"], "Kaze")
	assert_eq(m["clan"], "gale")
	assert_eq(m["nature"], Element.WIND)
	assert_eq(m["cleared"], 2)
	assert_near(m["playtime"], 3725.0, 0.01)
	assert_false(SaveSlots.meta(2)["exists"], "an empty slot")
	assert_eq(SaveSlots.format_playtime(3725.0), "1h 02m")
	assert_eq(SaveSlots.format_playtime(14.0 * 60.0), "14m")
	assert_eq(SaveSlots.format_playtime(20.0), "just begun")


func test_erasing_a_slot() -> void:
	SaveSlots.create(1)
	SaveSlots.create(3)
	assert_eq(SaveSlots.last(), 3, "the newest game is the one to continue")
	SaveSlots.erase(3)
	assert_false(SaveSlots.exists(3))
	assert_true(SaveSlots.exists(1), "the others are untouched")
	assert_eq(SaveSlots.active, 0, "nothing is loaded after erasing the loaded slot")
	assert_eq(SaveSlots.first_free(), 2)


func test_nothing_is_saved_without_a_slot() -> void:
	assert_eq(Profile.path(), "")
	Profile.set_value(&"name", "Ghost")
	Game.mark_chapter_done("ch1_graduation")
	assert_false(DirAccess.dir_exists_absolute(TMP), "no files written")
	assert_false(SaveSlots.any())


func test_a_changed_game_is_saved_as_you_go() -> void:
	SaveSlots.create(1)
	Profile.set_value(&"name", "Saved")
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(SaveSlots.profile_path(1)), OK)
	assert_eq(cfg.get_value("profile", "name"), "Saved")


func test_play_time_counts_only_while_playing() -> void:
	SaveSlots.create(1)
	Game.tracking = false
	Game._process(5.0)
	assert_near(Game.playtime, 0.0, 0.001, "not on the title screen")
	Game.tracking = true
	Game._process(5.0)
	assert_near(Game.playtime, 5.0, 0.001)
	Game._process(Game.AUTOSAVE_EVERY)
	assert_near(SaveSlots.meta(1)["playtime"], 5.0 + Game.AUTOSAVE_EVERY, 0.01, "and is saved every so often")


func test_the_old_single_save_becomes_slot_one() -> void:
	var old := ConfigFile.new()
	old.set_value("profile", "name", "Veteran")
	old.save(SaveSlots.legacy_profile)
	var records := ConfigFile.new()
	records.set_value("story", "ch1_graduation", true)
	records.save(SaveSlots.legacy_records)
	SaveSlots.boot()
	assert_true(SaveSlots.exists(1), "migrated")
	assert_eq(SaveSlots.active, 1, "and picked up")
	assert_eq(SaveSlots.meta(1)["name"], "Veteran")
	assert_eq(SaveSlots.meta(1)["cleared"], 1)
	assert_true(SaveSlots.meta(1)["created"], "an existing character needs no creation")
	assert_true(FileAccess.file_exists(SaveSlots.legacy_profile), "the old file is left alone")
	SaveSlots.boot()
	assert_eq(SaveSlots.meta(1)["name"], "Veteran", "migrating twice changes nothing")
