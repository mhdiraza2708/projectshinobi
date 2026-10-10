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
		elif jutsu.form == JutsuDefinition.Form.RUSH:
			# A rush sounds as it gathers, as it launches and as it lands.
			assert_eq(sound, &"", "rushes make their own sound")
			var own := [&"charge_start", &"charge_loop", &"wind_loop", &"dash", &"explosion", &"thunder",
				&"strike_hit", StringName("cast_" + Element.NAMES[jutsu.element])]
			for s: StringName in own:
				assert_true(Sfx.has_sound(s), "%s -> %s" % [jutsu.id, s])
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
	await seconds(0.06)  # past the repeat guard for sounds earlier tests played
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
	await seconds(0.06)
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
	# A cut with the sword slices; bare fists thud.
	var hit := &"blade_hit" if player.animator and player.animator.has_sword() else &"strike_hit"
	assert_true(Sfx.history.has(hit), "%s (got %s)" % [hit, Sfx.history])


func test_menus_open_close_and_buttons_click() -> void:
	await _load_scene()
	var menu := (player.get_parent() as Node).get("pause_menu") as PauseMenu
	menu.open()
	assert_true(Sfx.history.has(&"ui_open"))
	var buttons := menu.find_children("*", "Button", true, false)
	assert_true(buttons.size() > 3, "menu has buttons")
	Sfx.history.clear()
	# Tabs have their own sound; every other button clicks.
	var plain := buttons.filter(func(b: Button) -> bool: return not b.has_meta(&"sfx"))
	assert_true(not plain.is_empty(), "menu has plain buttons")
	(plain[0] as Button).pressed.emit()
	assert_true(Sfx.history.has(&"ui_select"), "button press clicks")
	await seconds(0.06)
	Sfx.history.clear()
	(buttons[0] as Button).pressed.emit()
	assert_true(Sfx.history.has(&"ui_tab") and not Sfx.history.has(&"ui_select"), "a tab ticks instead (%s)" % [Sfx.history])
	await physics_frames(10)
	menu.close()
	assert_true(Sfx.history.has(&"ui_close"))


# --- Takes, the mix and the new sounds -----------------------------------------------

const NEW_SOUNDS: Array[StringName] = [
	&"sword_draw", &"sword_sheathe", &"sword_snap", &"blade_hit", &"blade_clash", &"guard_break",
	&"step_dirt", &"step_grass", &"step_stone", &"step_sand", &"step_snow", &"step_water",
	&"charge_start", &"charge_end", &"dodge", &"perfect_dodge", &"windup", &"lock_on", &"lock_off",
	&"ult_ready", &"ui_tab", &"map_open", &"quest_accept", &"quest_done", &"level_up", &"skill_learn", &"pickup",
]


func test_the_once_silent_actions_have_sounds() -> void:
	for sound in NEW_SOUNDS:
		assert_true(Sfx.has_sound(sound), "%s exists" % sound)
	for surface in Sfx.SURFACES:
		assert_true(Sfx.has_sound(StringName("step_" + surface)), "a step on %s" % surface)


func test_frequent_sounds_come_in_takes_that_alternate() -> void:
	for sound: StringName in [&"strike_hit", &"strike_whoosh", &"blade_hit", &"impact", &"step_dirt", &"step_grass"]:
		assert_true(Sfx.take_count(sound) >= 2, "%s has takes" % sound)
	for sound: StringName in [&"step_dirt", &"blade_clash", &"strike_hit"]:
		var seen := {}
		var last: AudioStream = null
		for i in 40:
			var stream := Sfx._stream_for(sound)
			assert_true(stream != last, "%s never repeats the take it just played" % sound)
			last = stream
			seen[stream] = true
		assert_eq(seen.size(), Sfx.take_count(sound), "%s uses every take" % sound)
	# Played by its plain name, whichever take sounds.
	await seconds(0.06)
	Sfx.play(&"strike_hit")
	assert_eq(Sfx.history, [&"strike_hit"] as Array[StringName])


func test_sound_calls_only_turn_sounds_down() -> void:
	# Files are mastered to sit right at 0 dB; a boost could only clip.
	var volume_arg := {&"play": 1, &"ui": 1, &"play_at": 2, &"footstep": 2, &"start_loop": 2}
	var checked := 0
	for dir: String in SOURCE_DIRS:
		for path in _script_files(dir):
			if path.ends_with("autoload/sfx.gd"):
				continue
			for line in FileAccess.get_file_as_string(path).split("\n"):
				for call: StringName in volume_arg:
					var start := line.find("Sfx.%s(" % call)
					if start < 0:
						continue
					var args := _call_args(line.substr(start + String(call).length() + 5))
					if args.size() <= int(volume_arg[call]):
						continue
					var arg: String = args[int(volume_arg[call])].strip_edges()
					if arg.is_valid_float():
						checked += 1
						assert_true(float(arg) <= 0.0, "%s boosts a sound: %s" % [path.get_file(), line.strip_edges()])
	assert_true(checked >= 20, "the scan found the volumes (%d)" % checked)


## The top-level arguments of a call, given the text just after its "(".
func _call_args(text: String) -> PackedStringArray:
	var args := PackedStringArray()
	var depth := 0
	var current := ""
	for c in text:
		if c == "(" or c == "[":
			depth += 1
		elif c == ")" or c == "]":
			if depth == 0:
				args.append(current)
				return args
			depth -= 1
		if c == "," and depth == 0:
			args.append(current)
			current = ""
		else:
			current += c
	args.append(current)
	return args


## Peak and loudest-50ms RMS (both dBFS) of a sound's first take.
func _levels(sound: StringName, stride := 1) -> Vector2:
	var file := String(sound) + (".wav" if Sfx.take_count(sound) == 1 else "_v1.wav")
	var wav := AudioStreamWAV.load_from_file(Sfx.DIR + file)
	assert_true(wav != null, "%s loads" % file)
	if wav == null:
		return Vector2(0.0, 0.0)
	var data := wav.data
	var count := data.size() / 2
	var peak := 0
	var i := 0
	while i < count:
		peak = maxi(peak, absi(data.decode_s16(i * 2)))
		i += stride
	var window := 2205
	var loudest := 0.0
	var start := 0
	while start + window <= count:
		var sum := 0.0
		for k in range(start, start + window, 3):
			var v := data.decode_s16(k * 2) / 32768.0
			sum += v * v
		loudest = maxf(loudest, sum / (window / 3.0))
		start += window
	return Vector2(linear_to_db(peak / 32768.0), linear_to_db(sqrt(loudest)))


func test_the_mix_is_balanced() -> void:
	var level := {}
	for sound: StringName in [&"explosion", &"thunder", &"impact", &"strike_hit", &"blade_hit", &"strike_whoosh",
			&"step_dirt", &"step_grass", &"step_sand", &"step_snow", &"ui_move", &"ui_select", &"ui_tab", &"seal_1"]:
		level[sound] = _levels(sound)
	# Blasts, then blows, then movement, then footsteps and the interface.
	assert_true(level[&"explosion"].y > level[&"strike_hit"].y + 2.0, "explosions are louder than blows")
	assert_true(level[&"thunder"].y > level[&"strike_hit"].y, "thunder too")
	assert_true(level[&"impact"].y > level[&"strike_hit"].y, "a jutsu lands harder than a fist")
	assert_true(level[&"strike_hit"].y > level[&"strike_whoosh"].y + 4.0, "a blow is louder than the swing")
	for step: StringName in [&"step_dirt", &"step_grass", &"step_sand", &"step_snow"]:
		assert_true(level[step].y < level[&"strike_hit"].y - 8.0, "%s is quiet beside a blow" % step)
		assert_true(level[step].y < level[&"strike_whoosh"].y, "%s is quieter than a swing" % step)
	for ui: StringName in [&"ui_move", &"ui_select", &"ui_tab"]:
		assert_true(level[ui].y < level[&"strike_hit"].y - 8.0, "%s is quiet beside a blow" % ui)
		assert_true(level[ui].y < level[&"seal_1"].y + 1.0, "%s is no louder than a seal" % ui)


func test_no_sound_clips() -> void:
	for sound: StringName in Sfx.sounds():
		var peak := _levels(sound, 5).x
		assert_true(peak <= -0.9, "%s peaks at %.1f dBFS" % [sound, peak])


func test_the_master_bus_has_a_limiter() -> void:
	var master := AudioServer.get_bus_index(&"Master")
	var found := 0
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			found += 1
	assert_eq(found, 1, "one limiter, however many times Sfx starts")


# --- Footsteps ---------------------------------------------------------------------------

func test_a_step_is_counted_when_the_cycle_passes_a_foot_plant() -> void:
	assert_true(Footsteps._crossed(0.4, 0.6, 0.5), "mid cycle")
	assert_false(Footsteps._crossed(0.4, 0.45, 0.5), "not yet")
	assert_true(Footsteps._crossed(0.95, 0.05, 0.0), "across the wrap")
	assert_true(Footsteps._crossed(0.95, 0.05, 0.02), "just after the wrap")
	assert_false(Footsteps._crossed(0.95, 0.05, 0.5), "the other foot isn't")


func test_what_is_underfoot_picks_the_surface() -> void:
	var sea := StaticBody3D.new()
	sea.set_meta(&"surface", &"water")
	assert_eq(Footsteps.surface_of(sea, Vector3.ZERO), &"water")
	sea.free()
	var plain := Node3D.new()
	assert_eq(Footsteps.surface_of(plain, Vector3.ZERO), &"dirt", "anything else is earth")
	assert_eq(Footsteps.surface_of(null, Vector3.ZERO), &"dirt")
	plain.free()
	var island := Island.new()
	root.add_child(island)
	island.build("emberwood")
	assert_eq(island.surface_at(island.global_position), &"dirt", "the clearing is dirt")
	var seen := {}
	for angle in range(0, 360, 15):
		for radius in range(20, 90, 3):
			var at := Vector2.from_angle(deg_to_rad(angle)) * radius
			seen[island.surface_at(island.to_global(Vector3(at.x, 0.0, at.y)))] = true
	for surface: StringName in seen:
		assert_true(Sfx.SURFACES.has(surface), "%s is a surface with a sound" % surface)
	assert_true(seen.has(&"grass") and seen.has(&"sand"), "grass inland, sand at the shore (%s)" % [seen.keys()])
	island.queue_free()


func test_a_snowfield_steps_in_snow() -> void:
	var snowy := ""
	for id: String in Island.PRESETS:
		if (Island.PRESETS[id].get("textures", {}) as Dictionary).get("grass", "") == "snow":
			snowy = id
	assert_true(snowy != "", "an island with snow exists")
	var island := Island.new()
	root.add_child(island)
	island.build(snowy)
	var seen := {}
	for angle in range(0, 360, 20):
		for radius in range(25, 90, 4):
			var at := Vector2.from_angle(deg_to_rad(angle)) * radius
			seen[island.surface_at(island.to_global(Vector3(at.x, 0.0, at.y)))] = true
	assert_true(seen.has(&"snow"), "snow underfoot (%s)" % [seen.keys()])
	assert_false(seen.has(&"grass"), "and no grass")
	island.queue_free()


func _is_step(sound: StringName) -> bool:
	return String(sound).begins_with("step_")


func test_running_makes_footsteps_and_standing_still_does_not() -> void:
	await _load_scene()
	await seconds(0.3)
	assert_false(Sfx.history.any(_is_step), "standing")
	Input.action_press(&"move_forward")
	await seconds(1.6)
	Input.action_release(&"move_forward")
	var steps := Sfx.history.filter(_is_step)
	assert_true(steps.size() >= 3, "a few steps in 1.6 s (%s)" % [Sfx.history])


func test_the_sword_draws_and_sheathes_with_sound() -> void:
	var model := CharacterModel.new()
	model.model_path = CharacterModel.DEFAULT_MODEL
	model.use_profile = false
	model.style = {"back": "ninjato"}
	root.add_child(model)
	await physics_frames(3)
	var anim := model.animator
	assert_true(anim != null and anim.has_sword(), "an armed character")
	Sfx.history.clear()
	anim.strike()
	await seconds(HumanoidPoser.DRAW_TIME * HumanoidPoser.DRAW_REACH + 0.1)
	assert_true(Sfx.history.has(&"sword_draw"), "the draw (got %s)" % [Sfx.history])
	Sfx.history.clear()
	anim._since_cut = CharacterAnimator.SHEATHE_AFTER + 1.0
	await seconds(HumanoidPoser.SHEATHE_TIME + 0.2)
	var slide := Sfx.history.find(&"sword_sheathe")
	var snap := Sfx.history.find(&"sword_snap")
	assert_true(slide >= 0 and snap > slide, "slide, then the knock (got %s)" % [Sfx.history])
	model.queue_free()
