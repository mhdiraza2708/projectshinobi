extends Node
## Tracks which input device the player last touched so prompts can show the
## right glyphs, and wraps controller vibration. Autoloaded as `InputDevice`.

signal device_changed(device: Binding.Device)

## Mouse movement smaller than this (pixels) doesn't flip prompts back to
## keyboard, so a bumped desk doesn't fight a controller player.
const MOUSE_SWITCH_THRESHOLD := 6.0
const STICK_SWITCH_THRESHOLD := 0.4

var current: Binding.Device = Binding.Device.KEYBOARD_MOUSE
var gamepad_family := "xbox"
var active_joypad := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		_on_joy_connection_changed(pads[0], true)


func _input(event: InputEvent) -> void:
	var device := current
	if event is InputEventKey or event is InputEventMouseButton:
		device = Binding.Device.KEYBOARD_MOUSE
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() >= MOUSE_SWITCH_THRESHOLD:
			device = Binding.Device.KEYBOARD_MOUSE
	elif event is InputEventJoypadButton:
		device = Binding.Device.GAMEPAD
		active_joypad = event.device
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) >= STICK_SWITCH_THRESHOLD:
			device = Binding.Device.GAMEPAD
			active_joypad = event.device
	if device != current:
		current = device
		if device == Binding.Device.GAMEPAD:
			gamepad_family = family_for(Input.get_joy_name(active_joypad))
		device_changed.emit(current)


## Label of the first binding for `action` on the active device, e.g. "LT".
func glyph(action: StringName) -> String:
	return glyph_for_device(action, current)


func glyph_for_device(action: StringName, device: Binding.Device) -> String:
	var list := Settings.get_bindings_for_device(action, device)
	if list.is_empty():
		return "—"
	return Binding.label(list[0], gamepad_family)


func rumble(weak: float, strong: float, duration: float) -> void:
	if current != Binding.Device.GAMEPAD or not Settings.get_value(&"vibration"):
		return
	Input.start_joy_vibration(active_joypad, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)


static func family_for(joy_name: String) -> String:
	var n := joy_name.to_lower()
	for token in ["playstation", "dualsense", "dualshock", "ps4", "ps5", "sony"]:
		if n.contains(token):
			return "playstation"
	for token in ["nintendo", "switch", "pro controller", "joy-con"]:
		if n.contains(token):
			return "nintendo"
	return "xbox"


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		active_joypad = device
		gamepad_family = family_for(Input.get_joy_name(device))
		if current == Binding.Device.GAMEPAD:
			device_changed.emit(current)
