extends Node
## Player settings: accessibility/camera options and input rebinding.
## Persisted to user://settings.cfg. Autoloaded as `Settings`.

signal value_changed(key: StringName, value: Variant)
signal bindings_changed

const SAVE_PATH := "user://settings.cfg"

## Every option the settings menu exposes. Keep keys stable: they are the
## save-file format.
const DEFAULTS := {
	# "hold": keep Weave held while inputting seals, release to cast.
	# "toggle": press Weave to start, press again to cast (no holding needed).
	&"weave_mode": "hold",
	# Multiplier on the gap allowed between seals. 0 = no time limit.
	&"seal_timeout_scale": 1.0,
	# Show which jutsu the current seal sequence can still become.
	&"seal_hints": true,
	# Seconds per seal when a quick-cast slot weaves for you.
	&"auto_weave_seal_time": 0.16,
	&"mouse_sensitivity": 1.0,
	&"stick_sensitivity": 1.0,
	&"invert_y": false,
	&"stick_deadzone": 0.2,
	&"vibration": true,
	&"screen_shake": 1.0,
	&"ui_scale": 1.0,
}

const TRIGGER_DEADZONE := 0.35

var _values: Dictionary = {}
## action -> Array[Dictionary] for actions the player has rebound.
var _overrides: Dictionary = {}
## When false nothing touches disk (used by tests).
var persist := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_from_disk()


# --- Options -----------------------------------------------------------------

func get_value(key: StringName) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: StringName, value: Variant) -> void:
	assert(DEFAULTS.has(key), "Unknown setting: %s" % key)
	if _values.get(key) == value:
		return
	_values[key] = value
	_apply_value(key)
	value_changed.emit(key, value)
	save_to_disk()


func reset_values() -> void:
	_values = DEFAULTS.duplicate()
	for key: StringName in _values:
		_apply_value(key)
		value_changed.emit(key, _values[key])
	save_to_disk()


func _apply_value(key: StringName) -> void:
	match key:
		&"stick_deadzone":
			for action in DefaultBindings.STICK_ACTIONS:
				if InputMap.has_action(action):
					InputMap.action_set_deadzone(action, float(get_value(key)))
		&"ui_scale":
			if is_inside_tree():
				get_tree().root.content_scale_factor = float(get_value(key))


# --- Bindings ----------------------------------------------------------------

func get_bindings(action: StringName) -> Array:
	if _overrides.has(action):
		return _overrides[action].duplicate(true)
	var entry: Dictionary = DefaultBindings.table().get(action, {})
	return entry.get("events", []).duplicate(true)


func get_bindings_for_device(action: StringName, device: Binding.Device) -> Array:
	return get_bindings(action).filter(
		func(b: Dictionary) -> bool: return Binding.device_of(b) == device)


## Replaces the primary binding of `device` for `action`. If another action in
## a shared context already uses `binding`, the two swap so nothing is left
## silently double-bound. Returns the action that was swapped (or &"").
func set_binding(action: StringName, device: Binding.Device, binding: Dictionary) -> StringName:
	assert(Binding.is_valid(binding) and Binding.device_of(binding) == device)
	var table := DefaultBindings.table()
	assert(table.has(action), "Unknown action: %s" % action)

	var current := get_bindings(action)
	var slot := current.find_custom(
		func(b: Dictionary) -> bool: return Binding.device_of(b) == device)
	var old_binding: Dictionary = current[slot] if slot >= 0 else {}

	var swapped := &""
	var conflict := find_conflict(action, binding)
	if conflict != &"":
		var other := get_bindings(conflict)
		var idx := other.find_custom(func(b: Dictionary) -> bool: return Binding.equals(b, binding))
		if old_binding.is_empty():
			other.remove_at(idx)
		else:
			other[idx] = old_binding
		_overrides[conflict] = other
		swapped = conflict

	# Drop exact duplicates already on this action before inserting.
	current = current.filter(func(b: Dictionary) -> bool: return not Binding.equals(b, binding))
	slot = current.find_custom(func(b: Dictionary) -> bool: return Binding.device_of(b) == device)
	if slot >= 0:
		current[slot] = binding
	else:
		current.append(binding)
	_overrides[action] = current

	apply_bindings()
	save_to_disk()
	bindings_changed.emit()
	return swapped


## Returns another action that shares a context with `action` and already uses
## `binding`, or &"" if there is none.
func find_conflict(action: StringName, binding: Dictionary) -> StringName:
	var table := DefaultBindings.table()
	var contexts: Array = table[action]["contexts"]
	for other: StringName in table:
		if other == action:
			continue
		var shares_context := false
		for c in table[other]["contexts"]:
			if contexts.has(c):
				shares_context = true
		if not shares_context:
			continue
		for b in get_bindings(other):
			if Binding.equals(b, binding):
				return other
	return &""


func reset_bindings() -> void:
	_overrides.clear()
	apply_bindings()
	save_to_disk()
	bindings_changed.emit()


## Rebuilds the InputMap for every gameplay action from defaults + overrides.
func apply_bindings() -> void:
	var table := DefaultBindings.table()
	for action: StringName in table:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var deadzone := TRIGGER_DEADZONE
		if DefaultBindings.STICK_ACTIONS.has(action):
			deadzone = float(get_value(&"stick_deadzone"))
		InputMap.action_set_deadzone(action, deadzone)
		for b in get_bindings(action):
			var event := Binding.to_event(b)
			if event:
				InputMap.action_add_event(action, event)

	var extras := DefaultBindings.ui_extras()
	for action: StringName in extras:
		for b in extras[action]:
			var event := Binding.to_event(b)
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)


# --- Persistence -------------------------------------------------------------

func load_from_disk() -> void:
	_values = DEFAULTS.duplicate()
	_overrides.clear()
	if persist:
		var cfg := ConfigFile.new()
		if cfg.load(SAVE_PATH) == OK:
			for key: StringName in DEFAULTS:
				var saved: Variant = cfg.get_value("options", key, DEFAULTS[key])
				# Ignore values of the wrong type from older/corrupt saves.
				if typeof(saved) == typeof(DEFAULTS[key]):
					_values[key] = saved
			var table := DefaultBindings.table()
			for action in cfg.get_section_keys("bindings") if cfg.has_section("bindings") else []:
				var list: Variant = cfg.get_value("bindings", action)
				if table.has(StringName(action)) and list is Array \
						and list.all(func(b: Variant) -> bool: return b is Dictionary and Binding.is_valid(b)):
					_overrides[StringName(action)] = list
	apply_bindings()
	for key: StringName in _values:
		_apply_value(key)


func save_to_disk() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	for key: StringName in _values:
		cfg.set_value("options", key, _values[key])
	for action: StringName in _overrides:
		cfg.set_value("bindings", action, _overrides[action])
	cfg.save(SAVE_PATH)
