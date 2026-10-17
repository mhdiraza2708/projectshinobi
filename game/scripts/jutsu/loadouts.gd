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


## Every starter keeps Shade Clones in this slot: on the first page, so it is
## always on the D-pad.
const CLONES_SLOT := 3
## The starters before they followed your nature (old saves stored these).
const LEGACY := [
	["Balanced", ["chakra_bolt", "ember_volley", "stone_bulwark", "mending_palm", "shade_clones", "focus_seal", "", ""]],
	["Assault", ["chakra_bolt", "ember_volley", "thunder_needle", "sunfall_orb", "crescent_cutter", "cinder_bloom",
		"focus_seal", "shade_clones"]],
	["Guardian", ["stone_bulwark", "granite_skin", "riptide_wall", "mending_palm", "gale_palm", "shade_clones",
		"chakra_bolt", "focus_seal"]],
]


## What a new save starts with, built round a chakra nature (yours by
## default): Balanced, Assault and Guardian, each led by that nature's own
## jutsu, with Shade Clones always in CLONES_SLOT.
static func starters(nature := -1) -> Array:
	if nature < 0:
		nature = int(Profile.get_value(&"affinity"))
	if nature == Element.NONE:
		nature = Element.FIRE
	var own := []
	var attack := []
	var guard := []
	var mine := JutsuRegistry.all().filter(func(j: JutsuDefinition) -> bool: return j.element == nature)
	mine.sort_custom(func(a: JutsuDefinition, b: JutsuDefinition) -> bool: return a.chakra_cost < b.chakra_cost)
	for j: JutsuDefinition in mine:
		own.append(String(j.id))
		if j.form in [JutsuDefinition.Form.PROJECTILE, JutsuDefinition.Form.AREA, JutsuDefinition.Form.RUSH]:
			attack.append(String(j.id))
		elif j.form in [JutsuDefinition.Form.WALL, JutsuDefinition.Form.BUFF, JutsuDefinition.Form.HEAL]:
			guard.append(String(j.id))
	var first := own.slice(0, 1)
	var second := own.slice(1, 2)
	return [
		_preset("Balanced", _bar(first + ["chakra_bolt"] + second, own + ["mending_palm", "focus_seal", "five_nature_seal"])),
		_preset("Assault", _bar(attack + ["chakra_bolt"], own + ["focus_seal", "five_nature_seal", "chakra_bolt", "mending_palm"])),
		_preset("Guardian", _bar(guard + ["mending_palm"] + attack, own + ["chakra_bolt", "focus_seal"])),
	]


## A bar of SLOTS: the first of `lead` before CLONES_SLOT, Shade Clones there,
## then the rest of `lead` and `tail`, each jutsu once, empty slots at the end.
static func _bar(lead: Array, tail: Array) -> Array:
	var order := []
	for id: String in lead + tail:
		if id != "" and id != "shade_clones" and not order.has(id) and JutsuRegistry.get_jutsu(StringName(id)) != null:
			order.append(id)
	order.insert(mini(CLONES_SLOT, order.size()), "shade_clones")
	order = order.slice(0, SLOTS)
	while order.size() < SLOTS:
		order.append("")
	return order


## Whether `list` is a set of starters nobody has changed (any nature's, or
## the old fixed ones): such a set follows your nature.
static func _is_stock(list: Array) -> bool:
	var sets: Array = [LEGACY.map(func(p: Array) -> Dictionary: return _preset(p[0], p[1]))]
	for nature in [Element.FIRE, Element.WIND, Element.LIGHTNING, Element.EARTH, Element.WATER]:
		sets.append(starters(nature))
	for stock: Array in sets:
		if stock.size() != list.size():
			continue
		var same := true
		for i in stock.size():
			var a: Dictionary = stock[i]
			var b: Dictionary = list[i]
			if str(b.get("name", "")) != a["name"] or b.get("slots", []) != a["slots"] or b.get("styles", []) != a["styles"]:
				same = false
				break
		if same:
			return true
	return false


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
	if not saved.is_empty() and _is_stock(list):
		# Untouched starters: they follow your nature as it changes.
		return starters()
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
