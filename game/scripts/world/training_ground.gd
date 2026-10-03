extends Node3D
## The game scene. It starts in the mode Game.start_mode names: the title
## screen, free training with dummies, the Trial of the Five Natures, or a
## story chapter (which swaps the training ground for that chapter's island).
##
## Automated screenshots (used for review/CI artifacts):
##   godot --path game --rendering-driver opengl3 -- --screenshot=out.png [--demo=NAME] [--device=gamepad]
## NAME is one of: overview (default), weave, cast, kunai, menu, customize,
## customize_colours, customize_gear, title, trial, results, story,
## story_boss, story_menu, chapter_card, night, chapter:<id>, island:<id> (from
## the air), title_saves, slots_load, slots_new, confirm_overwrite (the title with
## fake saves), creation, creation_eyes, creation_identity, creation_jutsu,
## menu_jutsu, menu_skills[:<tree>|:tab], scene:<id>:<beat>:<seconds> (a cutscene partway through, best
## with --fixed-fps 60), teleport, teleport_night, and the close-up character
## views portrait, portrait_weave, portrait_guard, portrait_charge.

const KILL_PLANE_Y := -20.0
## Per story time of day: the sun's bearing (degrees; its height comes from
## the sky photo, see Skies) and whether the lanterns are lit.
const TIMES := {
	"dawn": {"yaw": 70.0, "lanterns": false},
	"day": {"yaw": 40.0, "lanterns": false},
	"dusk": {"yaw": -110.0, "lanterns": true},
	"night": {"yaw": 30.0, "lanterns": true},
}
## How much thicker the fog gets in each weather.
const WEATHER_FOG := {"rain": 4.0, "storm": 4.0, "snow": 3.0}

var hud: Hud
var pause_menu: PauseMenu
var customize_menu: CustomizeMenu
var title_screen: TitleScreen
var results: TrialResults
var director: TrialDirector
var mode := Game.Mode.TRAINING
var story: Story
var story_director: StoryDirector
var dialogue: DialogueBox
var chapter_card: ChapterCard
## Point lights added to the lanterns for dusk and night.
var lantern_lights: Array[OmniLight3D] = []
## The story island in use (null on the training ground).
var island: Island
## Skip the teleport effects (chapters started with skip_card, i.e. tests).
var _quick := false
## Which beat a chapter starts at (screenshots only).
var demo_start_beat := 0
var _flash: ColorRect
## "none", "rain", "storm", "snow" or "leaves".
var weather := "none"
var weather_particles: CPUParticles3D
var _next_flash := 0.0

var _customize_from_title := false
## The time of day the lighting is set for.
var _mood := "day"
var _grain: CanvasLayer
## The scene's own fog density, before weather thickens it.
var _base_fog := 0.0

@onready var player: Player = $Player


func _ready() -> void:
	# Meadow grass with a worn dirt ring where you fight (colours a real
	# meadow has: the scanned textures are tinted to average out to them).
	$Ground/GroundMesh.material_override = TerrainMaterial.make({}, {
		"grass": Color("4f6a2e"), "grass2": Color("5f6b33"), "dirt": Color("7d6549")}, 15.0)
	# The scene's Environment is shared by every instance of it: light a copy.
	var world := $WorldEnvironment as WorldEnvironment
	world.environment = world.environment.duplicate(true)
	_base_fog = world.environment.fog_density
	add_child(RayTracing.new(self, world))
	_relight()
	Settings.value_changed.connect(func(key: StringName, _v: Variant) -> void:
		if key in [&"graphics_quality", &"ambient_occlusion", &"bloom", &"brightness"]:
			apply_graphics())
	hud = Hud.new()
	add_child(hud)
	hud.bind(player)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.bind(player)
	customize_menu = CustomizeMenu.new()
	add_child(customize_menu)
	customize_menu.bind(player)
	pause_menu.customize_requested.connect(customize_menu.open)
	pause_menu.title_requested.connect(_restart.bind(Game.Mode.TITLE))
	customize_menu.opened.connect(func() -> void: hud.visible = false)
	customize_menu.closed.connect(_on_customize_closed)

	title_screen = TitleScreen.new()
	add_child(title_screen)
	title_screen.trial_chosen.connect(start_trial)
	title_screen.training_chosen.connect(start_training)
	title_screen.customize_chosen.connect(func() -> void:
		title_screen.close()
		_customize_from_title = true
		customize_menu.open())
	title_screen.chapter_chosen.connect(start_story)
	title_screen.continue_chosen.connect(_continue_slot)
	title_screen.new_game_chosen.connect(_new_game)
	customize_menu.begun.connect(_on_creation_begun)
	customize_menu.cancelled.connect(_on_creation_cancelled)
	results = TrialResults.new()
	add_child(results)
	results.retry_chosen.connect(_on_results_primary)
	results.title_chosen.connect(_restart.bind(Game.Mode.TITLE))

	var args := _user_args()
	if args.has("screenshot"):
		_screenshot(args["screenshot"], args.get("demo", "overview"), args.get("device", ""))
		return
	match Game.start_mode:
		Game.Mode.TITLE: show_title()
		Game.Mode.TRIAL: start_trial()
		Game.Mode.STORY: start_story(Game.story_chapter)
		_: start_training()


# --- Saves and character creation ------------------------------------------------

## Resumes a save: its character, then the first chapter it hasn't cleared. A
## character that was never finished goes back to creation.
func _continue_slot(slot: int) -> void:
	SaveSlots.activate(slot)
	if not bool(Profile.get_value(&"created")):
		_start_creation()
		return
	if story == null:
		story = Story.load_all()
	var next := story.resume_chapter()
	if next.is_empty():
		# Everything is cleared: pick a chapter to replay.
		show_title()
		title_screen.show_chapters()
		return
	start_story(next["id"])


## A fresh game in `slot` (the title already confirmed any overwrite).
func _new_game(slot: int) -> void:
	SaveSlots.create(slot)
	# A name to start from; the Identity tab changes it.
	Profile.set_value(&"name", Profile.random_name())
	_start_creation()


func _start_creation() -> void:
	title_screen.close()
	customize_menu.open_creation()


func _on_creation_begun() -> void:
	Profile.set_value(&"created", true)
	Game.save_records()
	if story == null:
		story = Story.load_all()
	start_story(story.chapters[0]["id"])


## Backing out of creation abandons the new game: the slot is cleared again.
func _on_creation_cancelled() -> void:
	SaveSlots.erase(SaveSlots.active)
	show_title()


# --- Modes ---------------------------------------------------------------------

func show_title() -> void:
	mode = Game.Mode.TITLE
	Game.tracking = false
	Game.save_records()
	hud.visible = false
	player.input_enabled = false
	player.camera_rig.begin_showcase(-1.1)
	title_screen.open()
	Music.play(&"title")


func start_training() -> void:
	mode = Game.Mode.TRAINING
	_leave_title()
	Music.play(&"calm")
	hud.show_banner("Hold %s and enter seals to weave a jutsu" % InputDevice.glyph(&"weave"))


## `waves` overrides the trial's waves (screenshots, tests).
func start_trial(waves: Array = []) -> void:
	mode = Game.Mode.TRIAL
	_leave_title()
	Music.play(&"battle")
	for dummy in find_children("*", "TrainingDummy", true, false):
		dummy.queue_free()
	director = TrialDirector.new()
	director.name = "TrialDirector"
	add_child(director)
	director.wave_started.connect(_on_wave_started)
	director.enemies_left_changed.connect(func(_n: int) -> void: _refresh_objective())
	director.finished.connect(_on_trial_finished)
	if not waves.is_empty():
		director.waves = waves
	director.start(player)


## Plays a story chapter. The chapter card shows first; `skip_card` starts
## the beats at once (tests).
func start_story(chapter_id: String, skip_card := false) -> void:
	if story == null:
		story = Story.load_all()
	var chapter := story.chapter(chapter_id)
	if chapter.is_empty():
		push_error("No story chapter '%s'" % chapter_id)
		start_training()
		return
	mode = Game.Mode.STORY
	_leave_title()
	Music.play(&"calm")
	_quick = skip_card
	if not chapter["dummies"]:
		for dummy in find_children("*", "TrainingDummy", true, false):
			dummy.free()
	use_island(chapter["island"])
	var at: Vector2 = chapter["player_at"]
	player.global_position = Vector3(at.x, 0.1, at.y)
	set_time_of_day(chapter["time"])
	set_weather(chapter["weather"])
	dialogue = DialogueBox.new()
	add_child(dialogue)
	chapter_card = ChapterCard.new()
	add_child(chapter_card)
	story_director = StoryDirector.new()
	story_director.name = "StoryDirector"
	add_child(story_director)
	story_director.setup(player, hud, dialogue, self, story)
	story_director.fight_lost.connect(_on_story_fight_lost)
	story_director.chapter_finished.connect(_on_chapter_finished)
	player.input_enabled = false
	if not skip_card:
		# You arrive by summoning: hidden until the seal flares.
		player.visible = false
		chapter_card.show_chapter(chapter["number"], chapter["title"],
			"%s  ·  %s" % [chapter["location"], chapter["time"]])
		await chapter_card.finished
		if not is_inside_tree():
			return
		await _teleport_in()
	if is_inside_tree():
		story_director.start(chapter, demo_start_beat)


## Replaces the training ground with a story island.
func use_island(island_id: String) -> void:
	for path in ["Ground", "Scenery"]:
		var old := get_node_or_null(path)
		if old:
			remove_child(old)
			old.queue_free()
	if island:
		remove_child(island)
		island.queue_free()
	for light in lantern_lights:
		if is_instance_valid(light):
			light.queue_free()
	lantern_lights.clear()
	island = Island.new()
	add_child(island)
	island.build(island_id)


func _teleport_fx() -> TeleportFx:
	var fx := TeleportFx.new()
	var nature := int(Profile.get_value(&"affinity"))
	fx.color = Element.color(nature).lightened(0.2)
	add_child(fx)
	fx.global_position = player.global_position
	return fx


## White flash, the seal flares, and you're standing on the island.
func _teleport_in() -> void:
	var fx := _teleport_fx()
	flash_screen(1.0, 0.0, 0.9)
	player.visible = true
	fx.arrive()
	await get_tree().create_timer(0.7).timeout


## The seal builds under you, a white flash, and you're gone.
func _teleport_out() -> void:
	var fx := _teleport_fx()
	fx.depart()
	await fx.peaked
	flash_screen(0.0, 1.0, 0.25)
	await get_tree().create_timer(0.3).timeout
	player.visible = false
	fx.queue_free()
	flash_screen(1.0, 0.0, 1.0)


## Fades a full-screen white flash from `from` to `to` opacity.
func flash_screen(from: float, to: float, seconds: float) -> void:
	if _flash == null:
		var layer := CanvasLayer.new()
		layer.layer = 13
		add_child(layer)
		_flash = ColorRect.new()
		_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_flash)
	_flash.color = Color(1, 1, 1, from)
	var tw := _flash.create_tween()
	tw.tween_property(_flash, "color:a", to, seconds)


func flash_alpha() -> float:
	return _flash.color.a if _flash else 0.0


func _on_story_fight_lost() -> void:
	await get_tree().create_timer(1.4).timeout
	if is_inside_tree():
		results.show_panel("敗", false, "物語", "DEFEATED", "Catch your breath. The fight starts again from the beginning.",
			"", false, "Retry fight", "Title screen")


func _on_chapter_finished(chapter: Dictionary) -> void:
	var next := story.next_chapter(chapter["id"])
	await get_tree().create_timer(1.0 if _quick else 0.8).timeout
	if not is_inside_tree():
		return
	if not _quick:
		await _teleport_out()
		if not is_inside_tree():
			return
	var body := "Next:  %s %s" % [Story.numeral(next["number"]), next["title"]] if not next.is_empty() \
		else "The end. Thank you for playing."
	results.show_panel("完", true, "第%s章" % Story.numeral(chapter["number"]), "CHAPTER COMPLETE",
		"%s %s" % [Story.numeral(chapter["number"]), chapter["title"]], body, false,
		"Next chapter" if not next.is_empty() else "Play it again", "Title screen")


func _on_results_primary() -> void:
	match mode:
		Game.Mode.TRIAL:
			_restart(Game.Mode.TRIAL)
		Game.Mode.STORY:
			var chapter := story_director.chapter
			if story_director.running:
				results.close()
				if DisplayServer.get_name() != "headless":
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				story_director.retry()
			elif get_tree().current_scene == self:
				var next := story.next_chapter(chapter["id"])
				Game.start_story(next["id"] if not next.is_empty() else chapter["id"])


## Relights the world for a story time of day.
func set_time_of_day(time: String) -> void:
	if not TIMES.has(time):
		return
	_mood = time
	_relight()
	if TIMES[time]["lanterns"] and lantern_lights.is_empty():
		for node in lanterns():
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.7, 0.38)
			light.light_energy = 2.2
			light.omni_range = 7.0
			light.position = Vector3(0, 1.3, 0)
			node.add_child(light)
			lantern_lights.append(light)


## Lights the world for the time of day and the weather together, from
## scratch each time (so changing either twice never stacks up).
func _relight() -> void:
	var env := ($WorldEnvironment as WorldEnvironment).environment
	var sky := Skies.key_for(_mood, weather)
	# A storm at night keeps the night sky, darker.
	var dim := 0.6 if sky == "night" and weather in ["rain", "storm", "snow"] else 1.0
	Skies.apply(env, $Sun as DirectionalLight3D, sky, float(TIMES[_mood]["yaw"]), dim)
	env.fog_density = _base_fog * float(WEATHER_FOG.get(weather, 1.0))
	apply_graphics()


## Lights the world for the graphics quality setting (and the time of day).
func apply_graphics() -> void:
	Graphics.apply(($WorldEnvironment as WorldEnvironment).environment, $Sun as DirectionalLight3D, _mood)
	if is_instance_valid(_grain):
		_grain.queue_free()
	_grain = Graphics.grain_layer()
	if _grain:
		add_child(_grain)


## The lantern props: the island's, or the training ground's.
func lanterns() -> Array[Node3D]:
	if island:
		return island.lanterns
	var out: Array[Node3D] = []
	var scenery := get_node_or_null("Scenery")
	if scenery:
		for node in scenery.get_children():
			if node.name.begins_with("Lantern"):
				out.append(node)
	return out


## Rain, storm (rain with lightning), snow or falling leaves around the player.
func set_weather(kind: String) -> void:
	weather = kind
	if weather_particles:
		weather_particles.queue_free()
		weather_particles = null
	Sfx.stop_loop(&"weather")
	if kind == "none" or not ["rain", "storm", "snow", "leaves"].has(kind):
		weather = "none"
		_relight()
		return
	var p := CPUParticles3D.new()
	p.name = "Weather"
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.position = Vector3(0, 10, 0)
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	p.mesh = quad
	_relight()
	match kind:
		"rain", "storm":
			quad.size = Vector2(0.018, 0.7)
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			p.amount = 1400
			p.lifetime = 0.55
			p.emission_box_extents = Vector3(16, 1, 16)
			p.direction = Vector3(0.08, -1, 0)
			p.spread = 2.0
			p.initial_velocity_min = 26.0
			p.initial_velocity_max = 32.0
			p.gravity = Vector3(0, -10, 0)
			p.color = Color(0.78, 0.84, 0.95, 0.4)
			Sfx.start_loop(&"weather", &"rain_loop", -5.0)
		"snow":
			quad.size = Vector2(0.06, 0.06)
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			p.amount = 900
			p.lifetime = 7.0
			p.emission_box_extents = Vector3(18, 2, 18)
			p.direction = Vector3(0.3, -1, 0.1)
			p.spread = 25.0
			p.initial_velocity_min = 1.2
			p.initial_velocity_max = 2.2
			p.gravity = Vector3(0, -0.4, 0)
			p.color = Color(1, 1, 1, 0.9)
			Sfx.start_loop(&"weather", &"wind_loop", -9.0)
		"leaves":
			quad.size = Vector2(0.09, 0.06)
			p.amount = 160
			p.lifetime = 8.0
			p.emission_box_extents = Vector3(16, 2, 16)
			p.direction = Vector3(1, -0.6, 0.3)
			p.spread = 35.0
			p.initial_velocity_min = 1.0
			p.initial_velocity_max = 2.2
			p.gravity = Vector3(0.3, -0.5, 0)
			p.angular_velocity_min = -220.0
			p.angular_velocity_max = 220.0
			var g := Gradient.new()
			g.set_color(0, Color(0.85, 0.35, 0.12))
			g.set_color(1, Color(0.95, 0.7, 0.2))
			p.color_initial_ramp = g
			Sfx.start_loop(&"weather", &"wind_loop", -12.0)
	player.add_child(p)
	weather_particles = p
	_next_flash = randf_range(4.0, 8.0)


func _flash_lightning() -> void:
	var sun := $Sun as DirectionalLight3D
	var env := ($WorldEnvironment as WorldEnvironment).environment
	var energy := sun.light_energy
	var ambient := env.ambient_light_energy
	sun.light_energy = energy + 2.5
	env.ambient_light_energy = ambient + 1.2
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sun, "light_energy", energy, 0.35).set_delay(0.08)
	tw.tween_property(env, "ambient_light_energy", ambient, 0.35).set_delay(0.08)
	# The clouds light up too.
	var sky := Skies.material(env)
	if sky:
		sky.set_shader_parameter(&"flash", 1.0)
		tw.tween_method(func(v: float) -> void: sky.set_shader_parameter(&"flash", v), 1.0, 0.0, 0.35).set_delay(0.08)
	await get_tree().create_timer(randf_range(0.4, 1.4)).timeout
	Sfx.play(&"thunder", -2.0, 0.1)


func _exit_tree() -> void:
	Sfx.stop_loop(&"weather")


func _leave_title() -> void:
	title_screen.close()
	Game.tracking = true
	hud.visible = true
	player.input_enabled = true
	if player.camera_rig.in_showcase():
		player.camera_rig.end_showcase()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_customize_closed() -> void:
	hud.visible = true
	if _customize_from_title:
		_customize_from_title = false
		show_title()


func _on_wave_started(index: int, _total: int, element: int) -> void:
	hud.show_banner("Wave %d · %s" % [index + 1, Element.display_name(element)], &"cast", element)
	_refresh_objective()


## The nature that beats `element`, or Element.NONE.
static func weakness_of(element: int) -> int:
	for e: int in Element.BEATS:
		if Element.BEATS[e] == element:
			return e
	return Element.NONE


func _refresh_objective() -> void:
	if director == null or not director.running:
		return
	var element := director.current_element()
	var parts := PackedStringArray([Game.format_time(director.elapsed),
		"Wave %d/%d · %s" % [director.wave + 1, director.waves.size(), Element.display_name(element)]])
	var weak := weakness_of(element)
	if weak != Element.NONE:
		parts.append("weak to %s" % Element.display_name(weak))
	if director.alive.size() > 0:
		parts.append("%d left" % director.alive.size())
	hud.set_objective("  ·  ".join(parts))


func _process(delta: float) -> void:
	if director and director.running:
		_refresh_objective()
	if weather == "storm":
		_next_flash -= delta
		if _next_flash <= 0.0:
			_next_flash = randf_range(7.0, 15.0)
			_flash_lightning()


func _on_trial_finished(won: bool, seconds: float, new_record: bool) -> void:
	hud.set_objective("")
	hud.show_banner("Trial complete!" if won else "Defeated", &"cast" if won else &"fail")
	player.input_enabled = false
	Music.stop()
	await get_tree().create_timer(1.6).timeout
	if is_inside_tree():
		results.show_result(won, seconds, new_record, director.waves_cleared, director.waves.size())


func _restart(to: Game.Mode) -> void:
	# Only the real game scene reloads (tests host this scene as a child).
	if get_tree().current_scene == self:
		Game.restart(to)


func _physics_process(_delta: float) -> void:
	if player.global_position.y < KILL_PLANE_Y:
		player.global_position = Vector3(0, 1, 4)
		player.velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	# Clicking back into the window re-captures the mouse after alt-tab.
	if event is InputEventMouseButton and event.pressed and not get_tree().paused \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


static func _user_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var kv := arg.trim_prefix("--").split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


## Fake saves for screenshots, in a folder of their own (slot 2 left empty).
func _demo_slots() -> void:
	SaveSlots.root = "user://demo_saves"
	if story == null:
		story = Story.load_all()
	var saves := [[1, "Kaze of the Ash Valley", "gale", Element.WIND, 4, 5400.0],
		[3, "Rin of the Stone Bridge", "stonewright", Element.EARTH, 9, 31200.0]]
	for save: Array in saves:
		DirAccess.make_dir_recursive_absolute(SaveSlots.slot_dir(save[0]))
		var profile := ConfigFile.new()
		profile.set_value("profile", "name", save[1])
		profile.set_value("profile", "clan", save[2])
		profile.set_value("profile", "affinity", save[3])
		profile.set_value("profile", "created", true)
		profile.save(SaveSlots.profile_path(save[0]))
		var records := ConfigFile.new()
		for i in int(save[4]):
			records.set_value("story", story.chapters[i]["id"], true)
		records.set_value("meta", "playtime", save[5])
		records.save(SaveSlots.records_path(save[0]))
	SaveSlots.active = 1
	Profile.set_value(&"created", true)
	Profile.set_value(&"name", "Kaze of the Ash Valley")


func _screenshot(path: String, demo: String, device: String) -> void:
	# Screenshots must not read or write the player's saved profile.
	Profile.persist = false
	Profile.load_from_disk()
	Game.persist = false
	Game.load_records()
	# --quality=standard|high|cinematic, for comparing the presets (not saved).
	var quality: String = _user_args().get("quality", "")
	if quality in Graphics.LEVELS:
		Settings._values[&"graphics_quality"] = quality
		apply_graphics()
	if device == "gamepad":
		InputDevice.current = Binding.Device.GAMEPAD
		InputDevice.device_changed.emit(InputDevice.current)
	await _frames(20)
	match demo:
		"weave":
			player.toggle_lock()
			await _frames(30)
			Input.action_press(&"weave")
			await _frames(2)
			for seal in [Seal.TIGER, Seal.SNAKE]:
				player.weaver.add_seal(seal)
			await _frames(4)
		"cast":
			player.toggle_lock()
			await _frames(30)
			player.caster.cast(JutsuRegistry.get_jutsu(&"sunfall_orb"), player.lock_target)
			player.caster.cast(JutsuRegistry.get_jutsu(&"ember_volley"), player.lock_target)
			# Count physics steps: slow software rendering must not let the
			# projectiles land before the shot is taken.
			for i in 12:
				await get_tree().physics_frame
		"kunai":
			for i in 3:
				player.throw_kunai()
				for f in 22:
					await get_tree().physics_frame
			player.throw_kunai()
			for f in 5:
				await get_tree().physics_frame
		"menu":
			pause_menu.open()
			await _frames(4)
		"title":
			show_title()
			await _frames(40)
		"trial":
			start_trial([{"element": Element.LIGHTNING, "enemies": [&"chunin", &"genin"]}])
			for f in 150:
				await get_tree().physics_frame
			for e in director.alive:
				e.set_physics_process(false)
			var weaver := director.alive[0]
			weaver._start_weave(weaver.jutsu_list[0])
			weaver._weave_index = 2
			weaver._seal_label.text = Seal.kanji(weaver._weave.seals[0]) + Seal.kanji(weaver._weave.seals[1])
			weaver._update_animator()
			player.toggle_lock()
			await _frames(40)
		"results":
			hud.visible = false
			results.show_result(true, 312.4, true, 5, 5)
			await _frames(10)
		"story":
			start_story("ch1_graduation", true)
			await _frames(40)
			dialogue.advance()
			dialogue.advance()
			await _frames(60)
		"story_boss", "night":
			start_story("ch5_kagerou", true)
			await _frames(5)
			if demo == "story_boss":
				var beats: Array = story_director.chapter["beats"]
				story_director.beat_index = beats.find_custom(func(b: Dictionary) -> bool: return b["do"] == "boss") - 1
				dialogue.visible = false
				story_director._next()
				for f in 90:
					await get_tree().physics_frame
				story_director.boss.take_hit(story_director.boss.stats.max_health * 0.25, Element.WATER, player)
				for f in 30:
					await get_tree().physics_frame
				player.toggle_lock()
			await _frames(40)
		"story_menu":
			show_title()
			title_screen.show_chapters()
			await _frames(20)
		"title_saves", "slots_load", "slots_new", "confirm_overwrite":
			_demo_slots()
			show_title()
			match demo:
				"slots_load": title_screen.show_slots(false)
				"slots_new": title_screen.show_slots(true)
				"confirm_overwrite":
					title_screen.show_slots(true)
					await _frames(2)
					title_screen._slot_pressed(1, true)
			await _frames(30)
		"creation", "creation_eyes", "creation_identity", "creation_jutsu":
			SaveSlots.root = "user://demo_saves"
			Profile.set_value(&"clan", "gale")
			Profile.set_value(&"affinity", Element.WIND)
			Profile.set_value(&"eye_art", "seal_eye" if demo != "creation_jutsu" else "")
			customize_menu.open_creation()
			customize_menu._select_tab({"creation": CustomizeMenu.T_CLAN, "creation_eyes": CustomizeMenu.T_EYES,
				"creation_identity": CustomizeMenu.T_IDENTITY, "creation_jutsu": CustomizeMenu.T_JUTSU}[demo])
			await _frames(40)
		_ when demo.begins_with("anim:"):
			# Five rigs frozen in one clip: --demo=anim:sprint:0.3 (clip, seconds).
			var parts := demo.split(":")
			var clip := StringName(parts[1])
			var at := float(parts[2]) if parts.size() > 2 else 0.3
			hud.visible = false
			player.visible = false
			var rigs := CharacterModel.roster().filter(func(e: Dictionary) -> bool:
				return e["path"] != CharacterModel.PLACEHOLDER_MODEL)
			var models: Array[CharacterModel] = []
			for i in mini(rigs.size(), 5):
				var m := CharacterModel.new()
				m.use_profile = false
				m.model_path = rigs[i]["path"]
				add_child(m)
				m.position = Vector3((i - 2) * 1.1, 0.0, -3.0)
				m.rotation.y = float(_user_args().get("yaw", "2.4"))
				models.append(m)
			await _frames(5)
			for m in models:
				var a := m.animator
				a.set_process(false)
				a.speed_ratio = {&"sprint": 1.7, &"run": 0.75, &"walk": 0.2}.get(clip, 0.0)
				if a.clips and a.has_clip(clip):
					a.clips.play(clip)
					a.clips.seek(at, true)
					a.clips.speed_scale = 0.0
			var cam := Camera3D.new()
			add_child(cam)
			cam.position = Vector3(0.0, 1.05, 1.1)
			cam.look_at(Vector3(0.0, 0.85, -3.0))
			cam.current = true
			await _frames(20)
		_ when demo.begins_with("ult:"):
			# An ultimate partway through: --demo=ult:hearthfall:0.6,2.2 (seconds
			# after it starts; earlier times also saved as <path>_<t>.png).
			var parts := demo.split(":")
			var u := Ultimates.get_ultimate(parts[1])
			var nature: int = u["element_id"] if u["element_id"] != Element.NONE else Element.FIRE
			Profile.set_value(&"affinity", nature)
			Profile.set_value(&"ultimate", parts[1])
			player.caster.affinity = nature
			for i in 3:
				var e := EnemyShinobi.new()
				e.rank = &"genin"
				e.element = [Element.WIND, Element.EARTH, Element.WATER][i]
				add_child(e)
				e.global_position = player.global_position + Vector3(-2.5 + 2.5 * i, 0.1, -9.0 - absf(i - 1) * 1.5)
			for f in 40:
				await get_tree().physics_frame
			player.toggle_lock()
			player.ult_charge = Ultimates.MAX_CHARGE
			player.try_ultimate()
			var fps := float(_user_args().get("fps", "60"))
			var times := parts[2].split(",") if parts.size() > 2 else PackedStringArray(["1.0"])
			var done := 0
			for i in times.size():
				var target := ceili(float(times[i]) * fps) + 1
				await _frames(target - done)
				done = target
				if i < times.size() - 1:
					get_viewport().get_texture().get_image().save_png(path.replace(".png", "_%s.png" % times[i]))
		"trailer":
			# The 50-second teaser (see TrailerDirector; record with --write-movie).
			await TrailerDirector.run(self).play()
		_ when demo.begins_with("eye:"):
			# An eye art opening: --demo=eye:hawk_eye:0.9,1.4[:awakened] (seconds
			# after it starts; earlier times also saved as <path>_<t>.png).
			var parts := demo.split(":")
			for clan in Perks.clans():
				if (clan["eye_arts"] as Array).has(parts[1]):
					Profile.set_value(&"clan", clan["id"])
					break
			Profile.set_value(&"eye_art", parts[1])
			if parts.size() > 3 and parts[3] == "awakened":
				Game.mark_chapter_done(Perks.awaken_after())
			var e := EnemyShinobi.new()
			e.rank = &"genin"
			add_child(e)
			e.global_position = player.global_position + Vector3(0.0, 0.1, -9.0)
			for f in 40:
				await get_tree().physics_frame
			player.stats.chakra = player.stats.max_chakra
			EyeArtMode.reset_seen()
			player.eye_mode.try_open()
			var fps := float(_user_args().get("fps", "60"))
			var times := parts[2].split(",") if parts.size() > 2 else PackedStringArray(["1.0"])
			var done := 0
			for i in times.size():
				var target := ceili(float(times[i]) * fps) + 1
				await _frames(target - done)
				done = target
				if i < times.size() - 1:
					get_viewport().get_texture().get_image().save_png(path.replace(".png", "_%s.png" % times[i]))
		"menu_jutsu", "menu_graphics", "menu_accessibility":
			pause_menu.open()
			pause_menu._select_tab({"menu_jutsu": PauseMenu.TAB_JUTSU, "menu_graphics": PauseMenu.TAB_GRAPHICS,
				"menu_accessibility": PauseMenu.TAB_ACCESSIBILITY}[demo])
			await _frames(10)
		_ when demo.begins_with("menu_skills"):
			# The Skills tab partway through a save: --demo=menu_skills[:<tree>]
			Game.add_xp(SkillTrees.xp_for_level(14) + 120)
			for id: String in ["iron_hide", "iron_hide", "light_feet", "rooted_stance", "rooted_stance", "wind_step",
					"keen_eye", "gathering_storm", "deep_well", "sharp_seals", "quiet_flow"]:
				SkillTrees.learn(id)
			pause_menu.open()
			pause_menu._select_tab(PauseMenu.TAB_SKILLS)
			var tree := demo.trim_prefix("menu_skills").trim_prefix(":")
			if tree == "eye":
				# A shinobi with an eye art, a few ranks in.
				Profile.set_value(&"clan", "hearth")
				Profile.set_value(&"eye_art", str(Perks.clan("hearth")["eye_arts"][0]))
				for id: String in ["steady_gaze", "steady_gaze", "quick_return"]:
					SkillTrees.learn(id)
			if tree != "tab":
				pause_menu.open_skills(tree if tree != "" else "body")
			await _frames(40)
		"chapter_card":
			start_story("ch3_vault")
			await _frames(12)
		_ when demo.begins_with("island:"):
			# An island from the air: --demo=island:old_dam
			hud.visible = false
			player.visible = false
			use_island(demo.trim_prefix("island:"))
			set_time_of_day("day")
			var cam := Camera3D.new()
			add_child(cam)
			cam.far = 3000.0
			cam.position = Vector3(62, 58, 78)
			cam.look_at(Vector3(0, 0, -6))
			cam.current = true
			await _frames(30)
		_ when demo.begins_with("scene:"):
			# A cutscene some seconds in: --demo=scene:ch1_graduation:0:5.5
			# (the chapter, the beat's position in it, seconds into the scene).
			var parts := demo.split(":")
			demo_start_beat = int(parts[2])
			start_story(parts[1], true)
			# Frames at --fps=N (match --fixed-fps), 60 by default.
			var fps := float(_user_args().get("fps", "60"))
			# "2,5.5,8" saves the earlier times as <path>_<t>.png as well.
			var times := parts[3].split(",")
			var done := 0
			for i in times.size():
				var target := ceili(float(times[i]) * fps) + 1
				await _frames(target - done)
				done = target
				if i < times.size() - 1:
					get_viewport().get_texture().get_image().save_png(path.replace(".png", "_%s.png" % times[i]))
		_ when demo.begins_with("shore:"):
			# An island seen across the water from just offshore: --demo=shore:emberwood
			hud.visible = false
			player.visible = false
			use_island(demo.trim_prefix("shore:"))
			set_time_of_day("dusk")
			var cam := Camera3D.new()
			add_child(cam)
			cam.far = 3000.0
			var from := Vector3(0, island.water_level + 2.5, float(island.preset["coast"]) + 22.0)
			cam.position = from
			cam.look_at(Vector3(0, island.water_level + 6.0, 0))
			cam.current = true
			await _frames(30)
		_ when demo.begins_with("vfx:"):
			# A jutsu mid-flight or mid-blast: --demo=vfx:ember_volley:12
			# (the number is physics frames after casting).
			var parts := demo.split(":")
			var jutsu := JutsuRegistry.get_jutsu(StringName(parts[1]))
			var wait := int(parts[2]) if parts.size() > 2 else 10
			player.toggle_lock()
			await _frames(30)
			_side_camera()
			player.stats.chakra = player.stats.max_chakra
			player.caster.cast(jutsu, player.lock_target)
			for f in wait:
				await get_tree().physics_frame
		"vfx_strike", "vfx_strike_back", "vfx_charge", "vfx_dash":
			player.toggle_lock()
			await _frames(30)
			if demo != "vfx_strike_back":
				_side_camera()
			match demo:
				"vfx_strike", "vfx_strike_back":
					player.global_position = player.lock_target.global_position + Vector3(0, 0, 1.6)
					await _frames(2)
					player._strike()
					for f in 3:
						await get_tree().physics_frame
				"vfx_charge":
					Input.action_press(&"charge_chakra")
					for f in 50:
						await get_tree().physics_frame
				"vfx_dash":
					player._start_dash()
					for f in 8:
						await get_tree().physics_frame
		"vfx_puff":
			var e := EnemyShinobi.new()
			e.element = Element.FIRE
			e.position = player.global_position + Vector3(0, 0, -5)
			add_child(e)
			player.toggle_lock()
			for f in 60:
				await get_tree().physics_frame
			e.take_hit(9999.0, Element.WATER, player)
			for f in 8:
				await get_tree().physics_frame
		"teleport", "teleport_night":
			# The summoning seal at full strength, mid-departure.
			start_story("ch4_pass" if demo == "teleport_night" else "ch7_wood", true)
			await _frames(20)
			dialogue.visible = false
			var fx := _teleport_fx()
			fx.strength = 1.0
			fx._sparks.emitting = true
			player.camera_rig.begin_showcase(-0.6)
			await _frames(50)
		_ when demo.begins_with("chapter:"):
			# Any chapter's opening scene: --demo=chapter:ch8_dam
			start_story(demo.trim_prefix("chapter:"), true)
			await _frames(60)
		"customize", "customize_colours", "customize_gear":
			if demo == "customize_gear":
				Profile.set_value(&"headband", "hachigane")
				Profile.set_value(&"mask", true)
			if demo == "customize_colours":
				var slots := player.model.styler.slots
				Profile.set_tint("hair" if slots.has("hair") else "body", Color("9e2430"))
				if slots.has("outfit"):
					Profile.set_tint("outfit", Color("2c3a6e"))
			customize_menu.open()
			customize_menu._select_tab({"customize": 0, "customize_colours": 1, "customize_gear": 2}[demo])
			await _frames(40)
		"portrait", "portrait_weave", "portrait_guard", "portrait_charge":
			hud.visible = false
			# Freeze the controller so the character keeps facing the camera,
			# and set the pose directly.
			player.set_physics_process(false)
			var poses := {"portrait_weave": HumanoidPoser.Pose.WEAVE, "portrait_guard": HumanoidPoser.Pose.GUARD,
				"portrait_charge": HumanoidPoser.Pose.CHARGE}
			if player.animator:
				player.animator.pose = poses.get(demo, HumanoidPoser.Pose.LOCOMOTION)
			# Swing the camera round to look at the character's front.
			var rig := player.camera_rig
			rig.spring.spring_length = 2.3
			rig.follow_height = 1.15
			rig.yaw = player.rotation.y + PI - 0.35
			rig.pitch = deg_to_rad(-6.0)
			rig.snap()
			await _frames(45)
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	if err != OK:
		push_error("Could not save screenshot to %s (error %d)" % [path, err])
	Input.action_release(&"weave")
	get_tree().quit(0 if err == OK else 1)


## A camera off to the side, framing the player and what they're locked on
## to (effect screenshots).
func _side_camera() -> void:
	var a := player.global_position
	var b: Vector3 = player.lock_target.global_position if is_instance_valid(player.lock_target) else a + Vector3(0, 0, -8)
	var mid := (a + b) * 0.5 + Vector3.UP * 1.0
	var side := (b - a).cross(Vector3.UP).normalized()
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 50
	cam.position = mid + side * a.distance_to(b) * 0.95 + Vector3.UP * 1.2
	cam.look_at(mid)
	cam.current = true


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
