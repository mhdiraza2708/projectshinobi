extends Node3D
## Training ground: the M1 playable slice.
##
## Automated screenshots (used for review/CI artifacts):
##   godot --path game --rendering-driver opengl3 -- --screenshot=out.png [--demo=NAME] [--device=gamepad]
## NAME is one of: overview (default), weave, cast, menu, and the close-up
## character views portrait, portrait_weave, portrait_guard, portrait_charge.

const KILL_PLANE_Y := -20.0

var hud: Hud
var pause_menu: PauseMenu

@onready var player: Player = $Player


func _ready() -> void:
	hud = Hud.new()
	add_child(hud)
	hud.bind(player)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.bind(player)

	var args := _user_args()
	if args.has("screenshot"):
		_screenshot(args["screenshot"], args.get("demo", "overview"), args.get("device", ""))
		return
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_banner("Hold %s and enter seals to weave a jutsu" % InputDevice.glyph(&"weave"))


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
		"menu":
			pause_menu.open()
			await _frames(4)
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
