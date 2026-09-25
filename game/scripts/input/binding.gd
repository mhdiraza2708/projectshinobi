class_name Binding
extends RefCounted
## A single input binding stored as a plain Dictionary so it can be saved to a
## ConfigFile, compared, and converted to/from Godot InputEvents.
##
## Shapes:
##   {"type": "key",        "code": <physical Key>}
##   {"type": "mouse",      "code": <MouseButton>}
##   {"type": "joy_button", "code": <JoyButton>}
##   {"type": "joy_axis",   "code": <JoyAxis>, "dir": -1 or 1}

enum Device { KEYBOARD_MOUSE, GAMEPAD }

const TYPE_KEY := "key"
const TYPE_MOUSE := "mouse"
const TYPE_JOY_BUTTON := "joy_button"
const TYPE_JOY_AXIS := "joy_axis"

## Minimum stick/trigger deflection that counts as a deliberate input when
## capturing a new binding.
const AXIS_CAPTURE_THRESHOLD := 0.6

# Face-button names by *position* (bottom, right, left, top), which is how
# Godot/SDL report them regardless of the printed label.
const _BUTTON_LABELS := {
	"xbox": {
		JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
		JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Menu",
		JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
		JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	},
	"playstation": {
		JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle",
		JOY_BUTTON_BACK: "Create", JOY_BUTTON_GUIDE: "PS", JOY_BUTTON_START: "Options",
		JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
		JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1",
	},
	"nintendo": {
		JOY_BUTTON_A: "B", JOY_BUTTON_B: "A", JOY_BUTTON_X: "Y", JOY_BUTTON_Y: "X",
		JOY_BUTTON_BACK: "-", JOY_BUTTON_GUIDE: "Home", JOY_BUTTON_START: "+",
		JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
		JOY_BUTTON_LEFT_SHOULDER: "L", JOY_BUTTON_RIGHT_SHOULDER: "R",
	},
}

const _DPAD_LABELS := {
	JOY_BUTTON_DPAD_UP: "D-Pad Up", JOY_BUTTON_DPAD_DOWN: "D-Pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-Pad Left", JOY_BUTTON_DPAD_RIGHT: "D-Pad Right",
}

const _TRIGGER_LABELS := {
	"xbox": ["LT", "RT"],
	"playstation": ["L2", "R2"],
	"nintendo": ["ZL", "ZR"],
}


static func key(physical_keycode: Key) -> Dictionary:
	return {"type": TYPE_KEY, "code": physical_keycode}


static func mouse(button: MouseButton) -> Dictionary:
	return {"type": TYPE_MOUSE, "code": button}


static func joy_button(button: JoyButton) -> Dictionary:
	return {"type": TYPE_JOY_BUTTON, "code": button}


static func joy_axis(axis: JoyAxis, direction: float) -> Dictionary:
	return {"type": TYPE_JOY_AXIS, "code": axis, "dir": 1 if direction >= 0.0 else -1}


static func is_valid(binding: Dictionary) -> bool:
	if not binding.has("type") or not binding.has("code"):
		return false
	match binding["type"]:
		TYPE_KEY, TYPE_MOUSE, TYPE_JOY_BUTTON:
			return true
		TYPE_JOY_AXIS:
			return binding.has("dir") and absi(int(binding["dir"])) == 1
	return false


static func device_of(binding: Dictionary) -> Device:
	match binding.get("type", ""):
		TYPE_JOY_BUTTON, TYPE_JOY_AXIS:
			return Device.GAMEPAD
	return Device.KEYBOARD_MOUSE


static func equals(a: Dictionary, b: Dictionary) -> bool:
	if a.get("type") != b.get("type") or int(a.get("code", -1)) != int(b.get("code", -2)):
		return false
	if a.get("type") == TYPE_JOY_AXIS:
		return int(a.get("dir", 0)) == int(b.get("dir", 0))
	return true


static func to_event(binding: Dictionary) -> InputEvent:
	match binding.get("type", ""):
		TYPE_KEY:
			var e := InputEventKey.new()
			e.physical_keycode = int(binding["code"]) as Key
			return e
		TYPE_MOUSE:
			var e := InputEventMouseButton.new()
			e.button_index = int(binding["code"]) as MouseButton
			return e
		TYPE_JOY_BUTTON:
			var e := InputEventJoypadButton.new()
			e.button_index = int(binding["code"]) as JoyButton
			return e
		TYPE_JOY_AXIS:
			var e := InputEventJoypadMotion.new()
			e.axis = int(binding["code"]) as JoyAxis
			e.axis_value = float(binding["dir"])
			return e
	return null


## Converts a live event into a binding. Returns {} for events that cannot or
## should not be bound (mouse motion, key echoes, small stick wobble...).
static func from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var k := event as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		if code == KEY_NONE:
			return {}
		return key(code)
	if event is InputEventMouseButton:
		return mouse((event as InputEventMouseButton).button_index)
	if event is InputEventJoypadButton:
		return joy_button((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		if absf(m.axis_value) < AXIS_CAPTURE_THRESHOLD:
			return {}
		return joy_axis(m.axis, m.axis_value)
	return {}


## Human-readable label, e.g. "Space", "RMB", "LT", "Cross".
static func label(binding: Dictionary, gamepad_family: String = "xbox") -> String:
	var family := gamepad_family if _BUTTON_LABELS.has(gamepad_family) else "xbox"
	var code := int(binding.get("code", -1))
	match binding.get("type", ""):
		TYPE_KEY:
			var keycode := code
			if DisplayServer.get_name() != "headless":
				# Show what is printed on *this* player's keyboard layout.
				keycode = DisplayServer.keyboard_get_keycode_from_physical(code as Key)
			return OS.get_keycode_string(keycode)
		TYPE_MOUSE:
			match code:
				MOUSE_BUTTON_LEFT: return "LMB"
				MOUSE_BUTTON_RIGHT: return "RMB"
				MOUSE_BUTTON_MIDDLE: return "MMB"
				MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
				MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
				MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
				MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
			return "Mouse %d" % code
		TYPE_JOY_BUTTON:
			if _DPAD_LABELS.has(code):
				return _DPAD_LABELS[code]
			var names: Dictionary = _BUTTON_LABELS[family]
			return names.get(code, "Button %d" % code)
		TYPE_JOY_AXIS:
			var dir := int(binding.get("dir", 1))
			match code:
				JOY_AXIS_TRIGGER_LEFT: return _TRIGGER_LABELS[family][0]
				JOY_AXIS_TRIGGER_RIGHT: return _TRIGGER_LABELS[family][1]
				JOY_AXIS_LEFT_X: return "L-Stick Right" if dir > 0 else "L-Stick Left"
				JOY_AXIS_LEFT_Y: return "L-Stick Down" if dir > 0 else "L-Stick Up"
				JOY_AXIS_RIGHT_X: return "R-Stick Right" if dir > 0 else "R-Stick Left"
				JOY_AXIS_RIGHT_Y: return "R-Stick Down" if dir > 0 else "R-Stick Up"
			return "Axis %d%s" % [code, "+" if dir > 0 else "-"]
	return "Unbound"
