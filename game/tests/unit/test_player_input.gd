extends TestCase
## End-to-end: real input actions -> player state machine -> seal weaver ->
## jutsu caster, inside the real training-ground scene. These are the same
## actions a keyboard or controller press produces, so they cover both devices.

const Scene := preload("res://scenes/training_ground.tscn")

var player: Player


func before_each() -> void:
	var scene := Scene.instantiate()
	root.add_child(scene)
	player = scene.player


func after_each() -> void:
	for action: StringName in DefaultBindings.table():
		Input.action_release(action)
	root.get_tree().paused = false


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await physics_frames(1)
	Input.action_release(action)
	await physics_frames(1)


func _settle() -> void:
	await physics_frames(10)
	assert_true(player.is_on_floor(), "player spawned on the ground")


func test_hold_weave_tiger_ox_casts_ember_volley() -> void:
	await _settle()
	var chakra := player.stats.chakra
	Input.action_press(&"weave")
	await physics_frames(2)
	assert_eq(player.state, Player.State.WEAVING)
	await _tap(&"seal_left")    # Tiger
	await _tap(&"seal_right")   # Ox
	assert_eq(player.weaver.sequence, [Seal.TIGER, Seal.OX] as Array[int])
	Input.action_release(&"weave")
	await physics_frames(2)
	assert_eq(player.state, Player.State.FREE)
	assert_true(player.caster.cooldown_left(&"ember_volley") > 0.0, "Ember Volley was cast")
	var cost := player.caster.cost_of(JutsuRegistry.get_jutsu(&"ember_volley"))
	assert_true(player.stats.chakra < chakra - cost * 0.9, "chakra spent")


func test_bank_modifiers_select_upper_seals() -> void:
	await _settle()
	Input.action_press(&"weave")
	await physics_frames(2)
	await _tap(&"seal_left")               # Tiger (bank I)
	Input.action_press(&"seal_layer_1")   # hold bank II
	await physics_frames(1)
	await _tap(&"seal_right")              # Snake
	await _tap(&"seal_left")               # Horse
	await _tap(&"seal_down")               # Dragon
	Input.action_release(&"seal_layer_1")
	Input.action_press(&"seal_layer_2")   # bank III
	await physics_frames(1)
	await _tap(&"seal_up")                 # Boar
	Input.action_release(&"seal_layer_2")
	assert_eq(player.weaver.sequence,
		[Seal.TIGER, Seal.SNAKE, Seal.HORSE, Seal.DRAGON, Seal.BOAR] as Array[int])


func test_face_buttons_do_not_trigger_field_actions_while_weaving() -> void:
	await _settle()
	Input.action_press(&"weave")
	await physics_frames(2)
	# On a pad, A is both Jump and the bottom seal; on keyboard Space is both
	# Jump and bank III. Neither may jump while weaving.
	Input.action_press(&"jump")
	Input.action_press(&"seal_down")
	await physics_frames(3)
	assert_true(player.is_on_floor(), "no jump while weaving")
	assert_eq(player.weaver.sequence, [Seal.RAT] as Array[int])


func test_toggle_mode_needs_no_holding() -> void:
	Settings.set_value(&"weave_mode", "toggle")
	await _settle()
	await _tap(&"weave")
	assert_eq(player.state, Player.State.WEAVING, "stays weaving after release")
	await _tap(&"seal_down")  # Rat = Chakra Bolt
	await _tap(&"weave")
	assert_eq(player.state, Player.State.FREE)
	assert_true(player.caster.cooldown_left(&"chakra_bolt") > 0.0, "Chakra Bolt was cast")


func test_quick_cast_weaves_automatically() -> void:
	await _settle()
	await _tap(&"quick_cast_2")  # Ember Volley by default
	assert_eq(player.state, Player.State.AUTO_WEAVING)
	await physics_frames(60)
	assert_eq(player.state, Player.State.FREE)
	assert_true(player.caster.cooldown_left(&"ember_volley") > 0.0)


func test_quick_cast_refuses_without_chakra() -> void:
	await _settle()
	player.stats.chakra = 0.0
	player.stats.chakra_regen = 0.0
	var messages: Array[String] = []
	player.feedback.connect(func(t: String, _k: StringName) -> void: messages.append(t))
	await _tap(&"quick_cast_2")
	assert_eq(player.state, Player.State.FREE)
	assert_true(messages.any(func(m: String) -> bool: return m.contains("chakra")), "told why")


func test_seal_timeout_breaks_sequence() -> void:
	await _settle()
	Input.action_press(&"weave")
	await physics_frames(2)
	await _tap(&"seal_down")
	await physics_frames(ceili(SealWeaver.BASE_TIMEOUT * 60.0) + 5)
	assert_true(player.weaver.sequence.is_empty())
	assert_eq(player.state, Player.State.WEAVING)


func test_big_hit_interrupts_weaving() -> void:
	await _settle()
	Input.action_press(&"weave")
	await physics_frames(2)
	await _tap(&"seal_down")
	player.take_hit(25.0, Element.NONE, null)
	await physics_frames(1)
	assert_eq(player.state, Player.State.FREE)


func test_dash_and_guard() -> void:
	await _settle()
	Input.action_press(&"evade")
	var saw_iframes := false
	for i in 5:
		await physics_frames(1)
		saw_iframes = saw_iframes or player.stats.is_invulnerable
	Input.action_release(&"evade")
	assert_eq(player.state, Player.State.DASHING)
	assert_true(saw_iframes, "i-frames at dash start")
	await physics_frames(20)
	assert_eq(player.state, Player.State.FREE)
	assert_false(player.stats.is_invulnerable)
	Input.action_press(&"guard")
	await physics_frames(2)
	assert_eq(player.state, Player.State.GUARDING)
	assert_near(player.take_hit(10.0, Element.NONE, null), 10.0 * player.guard_damage_multiplier)
	Input.action_release(&"guard")
	await physics_frames(2)
	assert_near(player.stats.guard_multiplier, 1.0)


func test_lock_on_picks_dummy_and_strike_damages_it() -> void:
	await _settle()
	await _tap(&"lock_on")
	assert_true(player.lock_target is TrainingDummy, "locked on a dummy")
	var dummy := player.lock_target as TrainingDummy
	player.global_position = dummy.global_position + Vector3(0, 0, 1.4)
	await physics_frames(2)
	await _tap(&"attack")
	assert_true(dummy.stats.health < dummy.stats.max_health, "strike connected")


func test_pause_menu_pauses_and_resumes() -> void:
	await _settle()
	var menu := (player.get_parent() as Node).get("pause_menu") as PauseMenu
	var ev := InputEventAction.new()
	ev.action = &"pause"
	ev.pressed = true
	menu._unhandled_input(ev)
	assert_true(menu.is_open())
	assert_true(root.get_tree().paused)
	menu.close()
	assert_false(root.get_tree().paused)
