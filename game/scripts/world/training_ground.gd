extends Node3D
## The game scene. It starts in the mode Game.start_mode names: the title
## screen, free training with dummies, or the Trial of the Five Natures.
##
## Automated screenshots (used for review/CI artifacts):
##   godot --path game --rendering-driver opengl3 -- --screenshot=out.png [--demo=NAME] [--device=gamepad]
## NAME is one of: overview (default), weave, cast, kunai, menu, customize,
## customize_colours, customize_gear, title, trial, results, story,
## story_boss, story_menu, chapter_card, night, and the close-up character
## views portrait, portrait_weave, portrait_guard, portrait_charge.

const KILL_PLANE_Y := -20.0
## Lighting per story time of day ("day" is the scene as authored).
const TIMES := {
	"dawn": {"top": Color(0.3, 0.36, 0.62), "horizon": Color(0.96, 0.7, 0.55), "sun": Color(1.0, 0.76, 0.58),
		"energy": 1.0, "elevation": 12.0, "yaw": 70.0, "ambient": Color(0.78, 0.68, 0.7), "lanterns": false},
	"dusk": {"top": Color(0.2, 0.18, 0.4), "horizon": Color(0.98, 0.5, 0.3), "sun": Color(1.0, 0.56, 0.36),
		"energy": 0.9, "elevation": 8.0, "yaw": -110.0, "ambient": Color(0.62, 0.5, 0.56), "lanterns": true},
	"night": {"top": Color(0.015, 0.02, 0.06), "horizon": Color(0.09, 0.11, 0.2), "sun": Color(0.55, 0.65, 0.95),
		"energy": 0.35, "elevation": 42.0, "yaw": 30.0, "ambient": Color(0.33, 0.38, 0.58), "lanterns": true},
}

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
## "none", "rain", "storm", "snow" or "leaves".
var weather := "none"
var weather_particles: CPUParticles3D
var _next_flash := 0.0

var _customize_from_title := false

@onready var player: Player = $Player


func _ready() -> void:
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


# --- Modes ---------------------------------------------------------------------

func show_title() -> void:
	mode = Game.Mode.TITLE
	hud.visible = false
	player.input_enabled = false
	player.camera_rig.begin_showcase(-1.1)
	title_screen.open()


func start_training() -> void:
	mode = Game.Mode.TRAINING
	_leave_title()
	hud.show_banner("Hold %s and enter seals to weave a jutsu" % InputDevice.glyph(&"weave"))


## `waves` overrides the trial's waves (screenshots, tests).
func start_trial(waves: Array = []) -> void:
	mode = Game.Mode.TRIAL
	_leave_title()
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
	if not chapter["dummies"]:
		for dummy in find_children("*", "TrainingDummy", true, false):
			dummy.free()
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
		chapter_card.show_chapter(chapter["number"], chapter["title"],
			"%s  ·  %s" % [chapter["location"], chapter["time"]])
		await chapter_card.finished
	if is_inside_tree():
		story_director.start(chapter)


func _on_story_fight_lost() -> void:
	await get_tree().create_timer(1.4).timeout
	if is_inside_tree():
		results.show_panel("敗", false, "物語", "DEFEATED", "Catch your breath. The fight starts again from the beginning.",
			"", false, "Retry fight", "Title screen")


func _on_chapter_finished(chapter: Dictionary) -> void:
	var next := story.next_chapter(chapter["id"])
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	var body := "Next:  %s %s" % [Story.numeral(next["number"]), next["title"]] if not next.is_empty() \
		else "End of Part One. Thank you for playing."
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


## Relights the arena for a story time of day ("day" leaves it as authored).
func set_time_of_day(time: String) -> void:
	if not TIMES.has(time):
		return
	var t: Dictionary = TIMES[time]
	var world := $WorldEnvironment as WorldEnvironment
	world.environment = world.environment.duplicate(true)
	var env := world.environment
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	sky.sky_top_color = t["top"]
	sky.sky_horizon_color = t["horizon"]
	sky.ground_horizon_color = t["horizon"]
	sky.ground_bottom_color = Color(t["horizon"]).darkened(0.8)
	env.ambient_light_color = t["ambient"]
	env.fog_light_color = t["horizon"]
	var sun := $Sun as DirectionalLight3D
	sun.light_color = t["sun"]
	sun.light_energy = t["energy"]
	sun.rotation_degrees = Vector3(-float(t["elevation"]), float(t["yaw"]), 0.0)
	if t["lanterns"] and lantern_lights.is_empty():
		for node in $Scenery.get_children():
			if node.name.begins_with("Lantern"):
				var light := OmniLight3D.new()
				light.light_color = Color(1.0, 0.7, 0.38)
				light.light_energy = 2.2
				light.omni_range = 7.0
				light.position = Vector3(0, 1.3, 0)
				node.add_child(light)
				lantern_lights.append(light)


## Rain, storm (rain with lightning), snow or falling leaves around the player.
func set_weather(kind: String) -> void:
	weather = kind
	if weather_particles:
		weather_particles.queue_free()
		weather_particles = null
	Sfx.stop_loop(&"weather")
	if kind == "none" or not ["rain", "storm", "snow", "leaves"].has(kind):
		weather = "none"
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
	var world := $WorldEnvironment as WorldEnvironment
	world.environment = world.environment.duplicate(true)
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
			world.environment.fog_density *= 4.0
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
			world.environment.fog_density *= 3.0
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
	await get_tree().create_timer(randf_range(0.4, 1.4)).timeout
	Sfx.play(&"thunder", -2.0, 0.1)


func _exit_tree() -> void:
	Sfx.stop_loop(&"weather")


func _leave_title() -> void:
	title_screen.close()
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


func _screenshot(path: String, demo: String, device: String) -> void:
	# Screenshots must not read or write the player's saved profile.
	Profile.persist = false
	Profile.load_from_disk()
	Game.persist = false
	Game.load_records()
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
		"chapter_card":
			start_story("ch3_vault")
			await _frames(12)
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


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
