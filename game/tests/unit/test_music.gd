extends TestCase
## Background music: the tracks, crossfading, ducking, and which music each
## mode and story beat plays.

const Scene := preload("res://scenes/training_ground.tscn")
const TRACKS: Array[StringName] = [&"title", &"calm", &"battle", &"boss"]


func test_every_track_is_a_long_seamless_loop() -> void:
	for track in TRACKS:
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
