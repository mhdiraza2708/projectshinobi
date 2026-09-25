extends Node3D
## The game scene. It starts in the mode Game.start_mode names: the title
## screen, free training with dummies, or the Trial of the Five Natures.
##
## Automated screenshots (used for review/CI artifacts):
##   godot --path game --rendering-driver opengl3 -- --screenshot=out.png [--demo=NAME] [--device=gamepad]
## NAME is one of: overview (default), weave, cast, kunai, menu, customize,
## customize_colours, customize_gear, title, trial, results, and the close-up
## character views portrait, portrait_weave, portrait_guard, portrait_charge.

const KILL_PLANE_Y := -20.0

var hud: Hud
var pause_menu: PauseMenu
var customize_menu: CustomizeMenu
var title_screen: TitleScreen
var results: TrialResults
var director: TrialDirector
var mode := Game.Mode.TRAINING

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
	results = TrialResults.new()
	add_child(results)
	results.retry_chosen.connect(_restart.bind(Game.Mode.TRIAL))
	results.title_chosen.connect(_restart.bind(Game.Mode.TITLE))

	var args := _user_args()
	if args.has("screenshot"):
		_screenshot(args["screenshot"], args.get("demo", "overview"), args.get("device", ""))
		return
	match Game.start_mode:
		Game.Mode.TITLE: show_title()
		Game.Mode.TRIAL: start_trial()
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


func _process(_delta: float) -> void:
	if director and director.running:
		_refresh_objective()


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
