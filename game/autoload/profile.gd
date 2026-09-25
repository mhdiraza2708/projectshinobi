extends Node
## The player's character: which model, colours, gear, body and identity.
## Persisted to user://profile.cfg. Autoloaded as `Profile`.

signal changed(key: StringName)

const SAVE_PATH := "user://profile.cfg"

## Colour slots a model can expose (see CharacterStyler). A tint of
## Color.WHITE means "original colours".
const COLOR_SLOTS: PackedStringArray = ["hair", "eyes", "skin", "outfit", "lower", "shoes", "accessory", "body"]
const EXPRESSIONS: PackedStringArray = ["neutral", "angry", "happy", "relaxed", "sad"]
const HEADBANDS: PackedStringArray = ["none", "cloth", "hachigane"]
const BACK_ITEMS: PackedStringArray = ["none", "ninjato"]

const DEFAULTS := {
	# "" = automatic (your player.vrm if present, else the placeholder).
	&"model": "",
	&"name": "Nameless",
	&"affinity": Element.FIRE,
	&"height": 1.0,
	&"expression": "neutral",
	&"tints": {},
	&"headband": "cloth",
	&"headband_color": Color("b8321f"),
	&"mask": false,
	&"mask_color": Color("22222a"),
	&"scarf": true,
	&"scarf_color": Color("b8321f"),
	&"back": "ninjato",
	&"pouch": true,
	# Manual fit tweaks for gear on unusual head shapes.
	&"gear_scale": 1.0,
	&"gear_lift": 0.0,
}

## When false nothing touches disk (tests).
var persist := true
## Overridable so tests can round-trip without touching the real save.
var save_path := SAVE_PATH
var _values: Dictionary = {}


func _ready() -> void:
	load_from_disk()


func get_value(key: StringName) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: StringName, value: Variant) -> void:
	assert(DEFAULTS.has(key), "Unknown profile key: %s" % key)
	if typeof(value) != typeof(DEFAULTS[key]):
		push_error("Profile.%s expects %s" % [key, type_string(typeof(DEFAULTS[key]))])
		return
	_values[key] = value
	save_to_disk()
	changed.emit(key)


func tint(slot: String) -> Color:
	var tints: Dictionary = get_value(&"tints")
	return tints.get(slot, Color.WHITE)


func set_tint(slot: String, color: Color) -> void:
	var tints: Dictionary = (get_value(&"tints") as Dictionary).duplicate()
	if color == Color.WHITE:
		tints.erase(slot)
	else:
		tints[slot] = color
	set_value(&"tints", tints)


func reset() -> void:
	_values = DEFAULTS.duplicate(true)
	save_to_disk()
	changed.emit(&"")


func load_from_disk() -> void:
	_values = DEFAULTS.duplicate(true)
	if not persist:
		return
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	for key: StringName in DEFAULTS:
		var saved: Variant = cfg.get_value("profile", key, DEFAULTS[key])
		if typeof(saved) == typeof(DEFAULTS[key]):
			_values[key] = saved


func save_to_disk() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	for key: StringName in _values:
		cfg.set_value("profile", key, _values[key])
	cfg.save(save_path)


## A random ninja-style name, for players on a controller who'd rather not type.
static func random_name() -> String:
	var first := ["Kaze", "Hayate", "Rin", "Sora", "Akane", "Jin", "Mikoto", "Ren", "Tsubaki", "Kaito",
		"Yuzuki", "Shion", "Haru", "Kagero", "Suzu", "Raiden"]
	var clan := ["of the Hidden Reeds", "of the Ash Valley", "of the Silent Pines", "of the Crimson Gate",
		"of the Mist Terrace", "of the Stone Bridge", "of the Paper Lantern", "of the Nine Winds"]
	return "%s %s" % [first.pick_random(), clan.pick_random()]
