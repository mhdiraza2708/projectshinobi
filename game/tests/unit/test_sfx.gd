extends TestCase
## Sound effects: every sound the code asks for exists, volumes reach the
## buses, and gameplay/UI events actually make noise.

const Scene := preload("res://scenes/training_ground.tscn")
const SOURCE_DIRS := ["res://autoload", "res://scripts"]

var player: Player


func before_each() -> void:
	Sfx.history.clear()


func after_each() -> void:
	for action: StringName in DefaultBindings.table():
		Input.action_release(action)
	Sfx.stop_all_loops()


func _load_scene() -> void:
	var scene := Scene.instantiate()
	root.add_child(scene)
	player = scene.player
	await physics_frames(10)
	Sfx.history.clear()


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await physics_frames(1)
	Input.action_release(action)
	await physics_frames(1)


func _script_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_script_files(dir.path_join(d)))
	return out


func test_every_sound_the_code_names_exists() -> void:
	# First sound argument of play/play_at/ui, the sound of start_loop, and
	# the alternative of `&"a" if cond else &"b"`.
	var direct := RegEx.create_from_string(r'Sfx\.(?:play|play_at|ui)\(&"(\w+)"')
	var looped := RegEx.create_from_string(r'Sfx\.start_loop\(&"\w+",\s*&"(\w+)"')
	var alternative := RegEx.create_from_string(r'else &"(\w+)"')
	var named := 0
	for dir: String in SOURCE_DIRS:
		for path in _script_files(dir):
			for line in FileAccess.get_file_as_string(path).split("\n"):
				if not line.contains("Sfx."):
					continue
				var found: Array[RegExMatch] = direct.search_all(line)
				found.append_array(looped.search_all(line))
				if line.contains(" if "):
					found.append_array(alternative.search_all(line))
				for m in found:
					named += 1
					assert_true(Sfx.has_sound(StringName(m.get_string(1))),
						"%s names missing sound '%s'" % [path.get_file(), m.get_string(1)])
	assert_true(named >= 20, "the scan found the sound calls (%d)" % named)


func test_every_seal_bank_and_jutsu_has_a_sound() -> void:
	for bank in Seal.BANKS:
		assert_true(Sfx.has_sound(StringName("seal_%d" % (bank + 1))), "bank %d" % bank)
	for jutsu: JutsuDefinition in JutsuRegistry.all():
		var sound := JutsuCaster.cast_sound(jutsu)
		if jutsu.form == JutsuDefinition.Form.WALL:
			assert_eq(sound, &"", "walls make their own sound")
		else:
			assert_true(Sfx.has_sound(sound), "%s -> %s" % [jutsu.id, sound])


func test_volume_settings_drive_the_buses() -> void:
	var sfx_bus := AudioServer.get_bus_index(Sfx.BUS_SFX)
	var ui_bus := AudioServer.get_bus_index(Sfx.BUS_UI)
	assert_true(sfx_bus > 0 and ui_bus > 0, "buses exist")
	assert_eq(AudioServer.get_bus_send(sfx_bus), &"Master")
	Settings.set_value(&"sfx_volume", 0.5)
	assert_near(AudioServer.get_bus_volume_db(sfx_bus), linear_to_db(0.5), 0.01)
	assert_false(AudioServer.is_bus_mute(sfx_bus))
	Settings.set_value(&"ui_volume", 0.0)
	assert_true(AudioServer.is_bus_mute(ui_bus), "zero mutes")
	Settings.reset_values()
	assert_false(AudioServer.is_bus_mute(ui_bus))
	assert_near(AudioServer.get_bus_volume_db(sfx_bus), 0.0, 0.01)


func test_many_sounds_at_once_reuse_the_pool() -> void:
	await physics_frames(3)  # past the repeat guard for sounds earlier tests played
	var before := Sfx.get_child_count()
	var sounds := Sfx.sounds()
	for i in sounds.size():
		if i % 2 == 0:
			Sfx.play(sounds[i])
		else:
			Sfx.play_at(sounds[i], Vector3.ZERO)
	assert_eq(Sfx.get_child_count(), before, "no players created on the fly")
	assert_eq(Sfx.history.size(), sounds.size(), "all %d started" % sounds.size())


func test_same_sound_retriggered_instantly_plays_once() -> void:
	await physics_frames(3)
	Sfx.play_at(&"impact", Vector3.ZERO)
	Sfx.play_at(&"impact", Vector3.ZERO)
	Sfx.play_at(&"impact", Vector3.ZERO)
	assert_eq(Sfx.history, [&"impact"] as Array[StringName])


func test_weaving_and_casting_make_sounds() -> void:
	await _load_scene()
	Input.action_press(&"weave")
	await physics_frames(2)
	await _tap(&"seal_left")    # Tiger (bank I)
	Input.action_press(&"seal_layer_1")
	await physics_frames(1)
	await _tap(&"seal_right")   # Snake (bank II), not a jutsu: misfire
	Input.action_release(&"seal_layer_1")
	Input.action_release(&"weave")
	await physics_frames(3)
	for s: StringName in [&"weave_start", &"seal_1", &"seal_2", &"misfire"]:
		assert_true(Sfx.history.has(s), "played %s (got %s)" % [s, Sfx.history])

	Sfx.history.clear()
	await physics_frames(5)
	player.caster.cast(JutsuRegistry.get_jutsu(&"ember_volley"))
	assert_true(Sfx.history.has(&"cast_fire"), "fire cast sound")


func test_kunai_throw_and_hit_sounds() -> void:
	await _load_scene()
	await _tap(&"throw_tool")
	assert_true(Sfx.history.has(&"kunai_throw"))
	await physics_frames(40)
	assert_true(Sfx.history.has(&"kunai_hit"), "hit sound (got %s)" % [Sfx.history])


func test_charge_hum_loops_while_charging() -> void:
	await _load_scene()
	Input.action_press(&"charge_chakra")
	await physics_frames(3)
	assert_eq(player.state, Player.State.CHARGING)
	assert_true(Sfx.is_looping(&"charge"), "hum started")
	await physics_frames(30)
	assert_true(Sfx.is_looping(&"charge"), "hum holds")
	Input.action_release(&"charge_chakra")
	await physics_frames(2)
	assert_false(Sfx.is_looping(&"charge"), "hum stops on release")


func test_strike_on_dummy_whooshes_and_hits() -> void:
	await _load_scene()
	await _tap(&"lock_on")
	var dummy := player.lock_target as TrainingDummy
	player.global_position = dummy.global_position + Vector3(0, 0, 1.4)
	await physics_frames(2)
	await _tap(&"attack")
	assert_true(Sfx.history.has(&"strike_whoosh"))
	assert_true(Sfx.history.has(&"strike_hit"))


func test_menus_open_close_and_buttons_click() -> void:
	await _load_scene()
	var menu := (player.get_parent() as Node).get("pause_menu") as PauseMenu
	menu.open()
	assert_true(Sfx.history.has(&"ui_open"))
	var buttons := menu.find_children("*", "Button", true, false)
	assert_true(buttons.size() > 3, "menu has buttons")
	Sfx.history.clear()
	(buttons[0] as Button).pressed.emit()
	assert_true(Sfx.history.has(&"ui_select"), "button press clicks")
	await physics_frames(10)
	menu.close()
	assert_true(Sfx.history.has(&"ui_close"))
