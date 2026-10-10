extends TestCase
## Background music: the tracks, crossfading, ducking, and which music each
## mode and story beat plays.

const Scene := preload("res://scenes/training_ground.tscn")


func test_every_track_is_a_long_seamless_loop() -> void:
	for track in Music.TRACKS:
		assert_true(Music.has_track(track), "%s.ogg exists" % track)
		var stream: AudioStream = load(Music.DIR + track + ".ogg")
		assert_true(stream is AudioStreamOggVorbis, "%s is Ogg Vorbis" % track)
		assert_true(stream.get_length() > 45.0, "%s lasts %.0f s" % [track, stream.get_length()])


func test_play_crossfades_and_resumes() -> void:
	Music.play(&"calm", 0.1)
	assert_eq(Music.current, &"calm")
	await seconds(0.3)
	var calm_player: AudioStreamPlayer = Music._players[Music._active]
	assert_true(calm_player.playing)
	assert_near(calm_player.volume_db, 0.0, 0.5, "faded in")
	Music.play(&"battle", 0.1)
	assert_eq(Music.current, &"battle")
	await seconds(0.3)
	assert_false(calm_player.playing, "the old track faded out and stopped")
	assert_true(Music._positions.has(&"calm"), "where calm left off is remembered")
	Music.play(&"battle")
	assert_eq(Music.current, &"battle", "same track again is a no-op")
	Music.stop(0.05)
	assert_eq(Music.current, &"")


func test_missing_track_is_silence_not_an_error() -> void:
	Music.play(&"calm", 0.05)
	Music.play(&"no_such_track", 0.05)
	assert_eq(Music.current, &"")


func test_duck_lowers_the_music_under_a_voice() -> void:
	Music.play(&"calm", 0.05)
	await seconds(0.2)
	Music.duck(true)
	await seconds(0.4)
	assert_near(Music._players[Music._active].volume_db, Music.DUCK_DB, 0.5)
	Music.duck(false)
	await seconds(0.4)
	assert_near(Music._players[Music._active].volume_db, 0.0, 0.5)


func test_music_volume_setting_drives_its_bus() -> void:
	var bus := AudioServer.get_bus_index(Sfx.BUS_MUSIC)
	assert_true(bus >= 0, "Music bus exists")
	Settings.set_value(&"music_volume", 0.5)
	assert_near(AudioServer.get_bus_volume_db(bus), linear_to_db(0.5), 0.01)
	Settings.set_value(&"music_volume", 0.0)
	assert_true(AudioServer.is_bus_mute(bus))
	assert_true(AudioServer.get_bus_index(Sfx.BUS_VOICE) >= 0, "Voice bus exists")


func test_each_mode_has_its_music() -> void:
	Game.start_mode = Game.Mode.TITLE
	var scene: Node3D = Scene.instantiate()
	root.add_child(scene)
	await physics_frames(5)
	assert_eq(Music.current, &"title")
	scene.start_trial()
	assert_eq(Music.current, &"battle")


func test_story_beats_choose_the_music() -> void:
	var d := StoryDirector.new()
	root.add_child(d)
	d._score("say")
	assert_eq(Music.current, &"calm")
	d._score("fight")
	assert_eq(Music.current, &"battle")
	d._score("enter")
	assert_eq(Music.current, &"battle", "an entrance mid-fight keeps the battle music")
	d._score("boss")
	assert_eq(Music.current, &"boss")
	d._score("task")
	assert_eq(Music.current, &"calm")


func test_missions_name_their_music() -> void:
	var d := StoryDirector.new()
	root.add_child(d)
	d.chapter = {"number": 7, "island": "frozen_road", "music": "tension"}
	d._score("say")
	assert_eq(Music.current, &"tension", "a mission's own music for talking")
	d._score("task")
	assert_eq(Music.current, &"tension", "and for lessons")
	d._score("say", {"music": "sorrow"})
	assert_eq(Music.current, &"sorrow", "a beat can name its own")
	d._score("boss")
	assert_eq(Music.current, &"boss", "bosses keep their theme")
	d._score("boss", {"music": "finale"})
	assert_eq(Music.current, &"finale", "unless the beat names one")
	d.chapter = {"number": 8, "island": "frozen_road"}
	d._score("say")
	assert_eq(Music.current, &"frozen_road", "without a name, the island's theme")
	d._score("survive")
	assert_eq(Music.current, &"battle2", "the eighth mission fights to the second battle theme")
	d.chapter = {"number": 9, "island": "old_dam"}
	d._score("fight")
	assert_eq(Music.current, &"battle3", "the ninth to the third")
	d.chapter = {"number": 10, "island": "old_dam"}
	d._score("fight")
	assert_eq(Music.current, &"battle", "and they come round again")
	d.queue_free()
	var story := Story.load_all()
	assert_eq(story.errors, [] as Array[String])
	var kagerou := story.chapter("ch5_kagerou")
	assert_eq(kagerou["music"], "tension")
	assert_true(kagerou["beats"].any(func(b: Dictionary) -> bool: return b.get("music", "") == "sorrow"), "Kagerou's defeat is sad")
	var scroll := story.chapter("m15_scroll_remembers")
	assert_eq(scroll["music"], "sorrow")
	assert_true(scroll["beats"].any(func(b: Dictionary) -> bool: return b["do"] == "task" and b.get("music", "") == "tension"), "the seal is tense")
	assert_eq(story.chapter("ch1_graduation")["music"], "", "most missions leave it to the island")


func test_the_story_checks_music_names() -> void:
	var s := Story.new()
	var chapter := {"id": "t", "number": 1, "title": "T", "location": "L", "time": "day", "music": "polka",
		"beats": [{"do": "banner", "text": "x"}]}
	s._parse_chapter("t.json", chapter)
	assert_true("\n".join(s.errors).contains("unknown music 'polka'"), "a chapter names a track that doesn't exist")
	s.errors.clear()
	chapter["music"] = "tension"
	assert_eq(s._parse_chapter("t.json", chapter)["music"], "tension")
	assert_eq(s.errors, [] as Array[String])
	s._parse_beat("beat", {"do": "say", "lines": [["player", "hi"]], "music": "polka"}, {})
	s._parse_beat("beat", {"do": "task", "text": "t", "goal": "dash", "music": "polka"}, {})
	assert_eq(s.errors.size(), 2, "say and task beats are checked too")
	s.errors.clear()
	s._parse_beat("beat", {"do": "fight", "waves": [{"element": "fire", "enemies": ["genin"]}], "music": "battle2"}, {})
	assert_true("\n".join(s.errors).contains("unknown key 'music'"), "only talking, lessons and bosses take a track")
	s.errors.clear()
	s._parse_beat("beat", {"do": "boss", "who": "nue", "rank": "jonin", "health": 100, "music": "finale"}, {})
	assert_false("\n".join(s.errors).contains("music"), "a boss may name its own theme")
	s.errors.clear()
	s._parse_beat("beat", {"do": "boss", "who": "nue", "rank": "jonin", "health": 100, "music": "polka"}, {})
	assert_true("\n".join(s.errors).contains("unknown music 'polka'"))


func test_every_track_is_listed_and_every_name_in_code_and_data_exists() -> void:
	var on_disk := Music.tracks()
	for track in Music.TRACKS:
		assert_true(on_disk.has(String(track)), "%s.ogg exists" % track)
	for file in on_disk:
		assert_true(Music.TRACKS.has(StringName(file)), "%s.ogg is listed in Music.TRACKS" % file)
	var named: Array[StringName] = []
	named.append_array(Music.BATTLES)
	named.append_array([OpenWorld.SEA_TRACK, OpenWorld.NIGHT_TRACK])
	for id: String in Island.PRESETS:
		assert_true(Music.ISLAND_THEMES.has(id), "%s has a theme" % id)
	for theme: StringName in Music.ISLAND_THEMES.values():
		named.append(theme)
	# Every Music.play(&"name") in the scripts.
	var literal := RegEx.create_from_string("Music\\.play\\(&\"([a-z0-9_]+)\"")
	for dir in ["res://scripts", "res://autoload"]:
		for path in _scripts_under(dir):
			for m in literal.search_all(FileAccess.get_file_as_string(path)):
				named.append(StringName(m.get_string(1)))
	# Every track the story names, in a chapter, a beat or a scene.
	var story := Story.load_all()
	for c in story.chapters:
		if c["music"] != "":
			named.append(StringName(c["music"]))
		for b: Dictionary in c["beats"]:
			if b.has("music"):
				named.append(StringName(b["music"]))
			for step: Dictionary in b.get("steps", []):
				if step.get("track", "none") != "none":
					named.append(StringName(step["track"]))
	assert_true(named.size() > 20, "found the names (%d)" % named.size())
	for track in named:
		assert_true(Music.has_track(track), "the track named '%s' exists in assets/audio/music" % track)


func _scripts_under(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts_under(dir.path_join(d)))
	return out


func test_audio_pack_preset_lists_every_track() -> void:
	# Exported builds carry music in audio_1.pck: a track missing from the
	# preset would silently vanish from the game.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK)
	var listed := PackedStringArray()
	for section in cfg.get_sections():
		if cfg.get_value(section, "name", "") == "Audio":
			listed = cfg.get_value(section, "export_files", PackedStringArray())
	for track in Music.tracks():
		assert_true(listed.has(Music.DIR + track + ".ogg"),
			"%s.ogg in the Audio preset (run art/audio/sync_audio_pack.py)" % track)
	for section in cfg.get_sections():
		if cfg.get_value(section, "name", "") in ["Windows Desktop", "Linux"]:
			assert_true(String(cfg.get_value(section, "exclude_filter", "")).contains("assets/audio/music/*"),
				"%s leaves music to the pack" % cfg.get_value(section, "name"))


func test_title_warns_about_each_missing_pack() -> void:
	assert_eq(Packs.missing_warning(true, true), "")
	assert_true(Packs.missing_warning(false, true).contains("CHARACTERS MISSING"))
	assert_false(Packs.missing_warning(false, true).contains("MUSIC"))
	assert_true(Packs.missing_warning(true, false).contains("audio_1.pck"))
	assert_true(Packs.audio_installed(), "music is available in tests")
