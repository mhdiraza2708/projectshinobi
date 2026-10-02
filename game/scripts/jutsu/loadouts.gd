class_name Loadouts
extends RefCounted
## Jutsu loadouts: named presets that fill the eight quick-cast slots. Each
## slot holds a jutsu and a cast style, "weave" (the seals are woven for you)
## or "instant" (no seals, at a chakra surcharge). Presets live in the save
## slot's Profile, can be created, renamed, copied and deleted, and are
## switched in the pause menu or with the preset keys.

const SLOTS := 8
## Slots shown at once on a gamepad (the D-pad has four directions).
const PAGE := 4
const MAX_PRESETS := 8
const MAX_NAME := 18
const WEAVE := "weave"
const INSTANT := "instant"
## Extra chakra an instant cast costs.
const INSTANT_SURCHARGE := 0.35


## What a new save starts with.
static func starters() -> Array:
	return [
		_preset("Balanced", ["chakra_bolt", "ember_volley", "stone_bulwark", "mending_palm",
			"shade_clones", "focus_seal", "", ""]),
		_preset("Assault", ["chakra_bolt", "ember_volley", "thunder_needle", "sunfall_orb",
			"crescent_cutter", "cinder_bloom", "focus_seal", "shade_clones"]),
		_preset("Guardian", ["stone_bulwark", "granite_skin", "riptide_wall", "mending_palm",
			"gale_palm", "shade_clones", "chakra_bolt", "focus_seal"]),
	]


static func _preset(preset_name: String, jutsu: Array) -> Dictionary:
	var styles := []
	styles.resize(SLOTS)
	styles.fill(WEAVE)
	return {"name": preset_name, "slots": jutsu, "styles": styles}


## Every preset (the starters until the player changes any).
static func all() -> Array:
	var saved: Array = Profile.get_value(&"loadouts")
	var list: Array = saved.duplicate(true) if not saved.is_empty() else starters()
	for p: Dictionary in list:
		_normalise(p)
	return list


## Keeps a preset well-formed: exactly SLOTS slots and styles, a name.
static func _normalise(p: Dictionary) -> void:
	var slots: Array = p.get("slots", [])
	var styles: Array = p.get("styles", [])
	slots.resize(SLOTS)
	styles.resize(SLOTS)
	for i in SLOTS:
		slots[i] = str(slots[i]) if slots[i] != null else ""
		styles[i] = INSTANT if styles[i] == INSTANT else WEAVE
	p["slots"] = slots
	p["styles"] = styles
	p["name"] = str(p.get("name", "Loadout")).strip_edges().left(MAX_NAME)
	if p["name"] == "":
		p["name"] = "Loadout"


static func index() -> int:
	return clampi(int(Profile.get_value(&"loadout")), 0, all().size() - 1)


static func active() -> Dictionary:
	return all()[index()]


static func jutsu_in(preset: Dictionary, slot: int) -> StringName:
	return StringName(preset["slots"][slot])


static func style_in(preset: Dictionary, slot: int) -> String:
	return preset["styles"][slot]


static func _store(list: Array, equipped: int) -> void:
	Profile.set_value(&"loadouts", list)
	Profile.set_value(&"loadout", clampi(equipped, 0, list.size() - 1))


static func equip(i: int) -> void:
	var list := all()
	_store(list, clampi(i, 0, list.size() - 1))


## The next (step 1) or previous (-1) preset's index, wrapping.
static func cycle(step: int) -> int:
	return wrapi(index() + step, 0, all().size())


## A new preset (a copy of the equipped one, or empty); returns its index, or
## -1 when there are already MAX_PRESETS.
static func add(preset_name := "", copy_active := true) -> int:
	var list := all()
	if list.size() >= MAX_PRESETS:
		return -1
	var p: Dictionary = list[index()].duplicate(true) if copy_active else _preset("", [])
	p["name"] = preset_name if preset_name != "" else "Loadout %d" % (list.size() + 1)
	_normalise(p)
	list.append(p)
	_store(list, list.size() - 1)
	return list.size() - 1


static func duplicate_preset(i: int) -> int:
	var list := all()
	if list.size() >= MAX_PRESETS:
		return -1
	var p: Dictionary = list[i].duplicate(true)
	p["name"] = "%s copy" % p["name"]
	_normalise(p)
	list.append(p)
	_store(list, list.size() - 1)
	return list.size() - 1


static func rename(i: int, new_name: String) -> void:
	var list := all()
	list[i]["name"] = new_name
	_normalise(list[i])
	_store(list, index())


## Deletes a preset (one always remains).
static func remove(i: int) -> void:
	var list := all()
	if list.size() <= 1:
		return
	list.remove_at(i)
	var equipped := index()
	if i < equipped or equipped >= list.size():
		equipped -= 1
	_store(list, equipped)


## Puts `jutsu_id` ("" clears) in a slot of the equipped (or given) preset.
## A jutsu sits in only one slot of a preset: it moves from where it was.
static func assign(slot: int, jutsu_id: StringName, preset := -1) -> void:
	if slot < 0 or slot >= SLOTS:
		return
	var list := all()
	var i := preset if preset >= 0 else index()
	if jutsu_id != &"":
		for s in SLOTS:
			if list[i]["slots"][s] == String(jutsu_id):
				list[i]["slots"][s] = ""
				list[i]["styles"][s] = WEAVE
	list[i]["slots"][slot] = String(jutsu_id)
	_store(list, index())


static func set_style(slot: int, style: String, preset := -1) -> void:
	var list := all()
	var i := preset if preset >= 0 else index()
	list[i]["styles"][slot] = INSTANT if style == INSTANT else WEAVE
	_store(list, index())


## The slot of the equipped preset holding `jutsu_id`, or -1.
static func slot_of(jutsu_id: StringName) -> int:
	return (active()["slots"] as Array).find(String(jutsu_id))
