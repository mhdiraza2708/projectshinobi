class_name DefaultBindings
extends RefCounted
## The single source of truth for every rebindable action.
##
## Every action MUST ship with at least one keyboard/mouse binding and one
## gamepad binding; tests/unit/test_bindings.gd enforces this.
##
## "contexts" say when an action is live. Actions only conflict with each other
## when they share a context, which is how the seal inputs can reuse WASD and
## the face buttons: while weaving, movement/jump/attack are locked out.

const CONTEXT_FIELD := &"field"
const CONTEXT_WEAVING := &"weaving"

const STICK_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"look_up", &"look_down", &"look_left", &"look_right",
]


static func table() -> Dictionary:
	return {
		# --- Movement -------------------------------------------------------
		&"move_forward": _a("Move Forward", "Movement", [
			Binding.key(KEY_W), Binding.joy_axis(JOY_AXIS_LEFT_Y, -1.0)]),
		&"move_back": _a("Move Back", "Movement", [
			Binding.key(KEY_S), Binding.joy_axis(JOY_AXIS_LEFT_Y, 1.0)]),
		&"move_left": _a("Move Left", "Movement", [
			Binding.key(KEY_A), Binding.joy_axis(JOY_AXIS_LEFT_X, -1.0)]),
		&"move_right": _a("Move Right", "Movement", [
			Binding.key(KEY_D), Binding.joy_axis(JOY_AXIS_LEFT_X, 1.0)]),
		# Arrow keys give keyboard-only players a camera without a mouse.
		&"look_up": _a("Camera Up", "Movement", [
			Binding.key(KEY_UP), Binding.joy_axis(JOY_AXIS_RIGHT_Y, -1.0)]),
		&"look_down": _a("Camera Down", "Movement", [
			Binding.key(KEY_DOWN), Binding.joy_axis(JOY_AXIS_RIGHT_Y, 1.0)]),
		&"look_left": _a("Camera Left", "Movement", [
			Binding.key(KEY_LEFT), Binding.joy_axis(JOY_AXIS_RIGHT_X, -1.0)]),
		&"look_right": _a("Camera Right", "Movement", [
			Binding.key(KEY_RIGHT), Binding.joy_axis(JOY_AXIS_RIGHT_X, 1.0)]),
		&"jump": _a("Jump / Chakra Jump", "Movement", [
			Binding.key(KEY_SPACE), Binding.joy_button(JOY_BUTTON_A)]),
		&"evade": _a("Dash (tap) / Sprint (hold)", "Movement", [
			Binding.key(KEY_SHIFT), Binding.joy_button(JOY_BUTTON_B)]),

		# --- Combat ---------------------------------------------------------
		&"attack": _a("Strike", "Combat", [
			Binding.mouse(MOUSE_BUTTON_LEFT), Binding.key(KEY_K), Binding.joy_button(JOY_BUTTON_X)]),
		&"throw_tool": _a("Throw Kunai", "Combat", [
			Binding.key(KEY_Q), Binding.joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)]),
		&"guard": _a("Guard", "Combat", [
			Binding.key(KEY_E), Binding.joy_button(JOY_BUTTON_RIGHT_SHOULDER)]),
		&"charge_chakra": _a("Charge Chakra (hold)", "Combat", [
			Binding.key(KEY_R), Binding.joy_button(JOY_BUTTON_Y)]),
		&"lock_on": _a("Lock On", "Combat", [
			Binding.key(KEY_TAB), Binding.mouse(MOUSE_BUTTON_MIDDLE),
			Binding.joy_button(JOY_BUTTON_RIGHT_STICK)]),

		# --- Jutsu ----------------------------------------------------------
		&"weave": _a("Weave Seals", "Jutsu", [
			Binding.mouse(MOUSE_BUTTON_RIGHT), Binding.key(KEY_F),
			Binding.joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)], [CONTEXT_FIELD, CONTEXT_WEAVING]),
		&"quick_cast_1": _a("Quick Cast 1", "Jutsu", [
			Binding.key(KEY_1), Binding.joy_button(JOY_BUTTON_DPAD_UP)]),
		&"quick_cast_2": _a("Quick Cast 2", "Jutsu", [
			Binding.key(KEY_2), Binding.joy_button(JOY_BUTTON_DPAD_RIGHT)]),
		&"quick_cast_3": _a("Quick Cast 3", "Jutsu", [
			Binding.key(KEY_3), Binding.joy_button(JOY_BUTTON_DPAD_DOWN)]),
		&"quick_cast_4": _a("Quick Cast 4", "Jutsu", [
			Binding.key(KEY_4), Binding.joy_button(JOY_BUTTON_DPAD_LEFT)]),

		# --- Seal weaving (only live while Weave is held/toggled) ------------
		# The four seal directions mirror the gamepad face-button diamond
		# (S = bottom, D = right, A = left, W = top) so muscle memory carries
		# over between devices. The D-pad duplicates them so the whole weave
		# can be done with the left hand alone (LT + D-pad + LB).
		&"seal_down": _a("Seal: Bottom", "Seal Weaving", [
			Binding.key(KEY_S), Binding.joy_button(JOY_BUTTON_A),
			Binding.joy_button(JOY_BUTTON_DPAD_DOWN)], [CONTEXT_WEAVING]),
		&"seal_right": _a("Seal: Right", "Seal Weaving", [
			Binding.key(KEY_D), Binding.joy_button(JOY_BUTTON_B),
			Binding.joy_button(JOY_BUTTON_DPAD_RIGHT)], [CONTEXT_WEAVING]),
		&"seal_left": _a("Seal: Left", "Seal Weaving", [
			Binding.key(KEY_A), Binding.joy_button(JOY_BUTTON_X),
			Binding.joy_button(JOY_BUTTON_DPAD_LEFT)], [CONTEXT_WEAVING]),
		&"seal_up": _a("Seal: Top", "Seal Weaving", [
			Binding.key(KEY_W), Binding.joy_button(JOY_BUTTON_Y),
			Binding.joy_button(JOY_BUTTON_DPAD_UP)], [CONTEXT_WEAVING]),
		&"seal_layer_1": _a("Seal Bank II (hold)", "Seal Weaving", [
			Binding.key(KEY_SHIFT), Binding.joy_button(JOY_BUTTON_LEFT_SHOULDER)], [CONTEXT_WEAVING]),
		&"seal_layer_2": _a("Seal Bank III (hold)", "Seal Weaving", [
			Binding.key(KEY_SPACE), Binding.joy_button(JOY_BUTTON_RIGHT_SHOULDER)], [CONTEXT_WEAVING]),

		# --- Menu -----------------------------------------------------------
		&"pause": _a("Pause / Settings", "Menu", [
			Binding.key(KEY_ESCAPE), Binding.joy_button(JOY_BUTTON_START)],
			[CONTEXT_FIELD, CONTEXT_WEAVING]),
	}


## Built-in UI actions get gamepad buttons too; Godot's defaults for
## ui_accept/ui_cancel are keyboard-only, which would strand controller players
## in menus.
static func ui_extras() -> Dictionary:
	return {
		&"ui_accept": [Binding.joy_button(JOY_BUTTON_A)],
		&"ui_cancel": [Binding.joy_button(JOY_BUTTON_B)],
	}


static func _a(label: String, group: String, events: Array, contexts: Array = [CONTEXT_FIELD]) -> Dictionary:
	return {"label": label, "group": group, "events": events, "contexts": contexts}
