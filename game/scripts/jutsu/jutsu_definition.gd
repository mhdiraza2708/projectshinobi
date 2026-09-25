class_name JutsuDefinition
extends Resource
## One technique, loaded from res://data/jutsu/*.json.
##
## Adding a jutsu whose *form* already exists is a data-only change. A new
## kind of behaviour (clones, summons, sealing, genjutsu...) means adding a
## Form here and a matching effect in JutsuCaster.

enum Form { PROJECTILE, AREA, WALL, BUFF, HEAL }

const FORM_NAMES: PackedStringArray = ["projectile", "area", "wall", "buff", "heal"]
const RANKS: PackedStringArray = ["E", "D", "C", "B", "A", "S"]
const BUFF_STATS: PackedStringArray = ["move_speed", "damage_reduction", "attack_power"]

const REQUIRED_KEYS: PackedStringArray = ["id", "name", "rank", "element", "form", "seals", "chakra_cost"]
const OPTIONAL_KEYS: PackedStringArray = [
	"description", "cooldown", "power", "speed", "range", "radius", "duration", "buff_stat", "count",
]

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var rank := "C"
@export var element := Element.NONE
@export var form := Form.PROJECTILE
@export var seals: Array[int] = []
@export var chakra_cost := 10.0
@export var cooldown := 1.0
## Damage (projectile/area), heal amount (heal) or buff magnitude (buff).
@export var power := 10.0
## Projectile travel speed in m/s.
@export var speed := 20.0
## Projectile travel distance, or how far ahead an area/wall is placed.
@export var max_range := 20.0
## Projectile size, blast radius, or wall half-width.
@export var radius := 0.5
## Buff/wall lifetime in seconds.
@export var duration := 0.0
@export var buff_stat := ""
## Number of projectiles fired in a fan.
@export var count := 1
## Projectile look: &"orb" for chakra techniques, &"kunai" for thrown tools.
## Not read from JSON (tools are defined in code).
@export var visual := &"orb"
## How hard projectiles steer toward their target (rad/s).
@export var homing := 2.2


## Parses and validates one JSON entry. Problems are appended to `errors`
## (prefixed with the id when known); returns null if any were found.
static func from_dict(data: Dictionary, errors: Array[String]) -> JutsuDefinition:
	var start_errors := errors.size()
	var label := str(data.get("id", "<missing id>"))
	var err := func(msg: String) -> void: errors.append("%s: %s" % [label, msg])

	for key in REQUIRED_KEYS:
		if not data.has(key):
			err.call("missing required key '%s'" % key)
	for key in data:
		if not REQUIRED_KEYS.has(key) and not OPTIONAL_KEYS.has(key):
			err.call("unknown key '%s' (typo?)" % key)
	if errors.size() > start_errors:
		return null

	var j := JutsuDefinition.new()
	var id_str := str(data["id"])
	if id_str.is_empty() or id_str != id_str.to_snake_case():
		err.call("id must be non-empty snake_case")
	j.id = StringName(id_str)
	j.display_name = str(data["name"])
	if j.display_name.strip_edges().is_empty():
		err.call("name is empty")
	j.description = str(data.get("description", ""))

	j.rank = str(data["rank"]).to_upper()
	if not RANKS.has(j.rank):
		err.call("rank '%s' is not one of %s" % [data["rank"], RANKS])

	j.element = Element.from_name(str(data["element"]))
	if j.element < 0:
		err.call("unknown element '%s'" % data["element"])

	var form_index := FORM_NAMES.find(str(data["form"]).to_lower())
	if form_index < 0:
		err.call("unknown form '%s'" % data["form"])
	else:
		j.form = form_index as Form

	var raw_seals: Variant = data["seals"]
	if not raw_seals is Array or raw_seals.is_empty() or raw_seals.size() > SealWeaver.MAX_SEALS:
		err.call("seals must be a list of 1-%d seal names" % SealWeaver.MAX_SEALS)
	else:
		for s in raw_seals:
			var seal := Seal.from_name(str(s))
			if seal < 0:
				err.call("unknown seal '%s'" % s)
			j.seals.append(seal)

	j.chakra_cost = _num(data, "chakra_cost", 0.0, err)
	j.cooldown = _num(data, "cooldown", 0.5, err)
	j.power = _num(data, "power", 0.0, err)
	j.speed = _num(data, "speed", 20.0, err)
	j.max_range = _num(data, "range", 20.0, err)
	j.radius = _num(data, "radius", 0.5, err)
	j.duration = _num(data, "duration", 0.0, err)
	j.count = int(_num(data, "count", 1.0, err))
	j.buff_stat = str(data.get("buff_stat", ""))

	match j.form:
		Form.PROJECTILE:
			if j.power <= 0.0 or j.speed <= 0.0 or j.max_range <= 0.0 or j.radius <= 0.0:
				err.call("projectile needs power, speed, range and radius > 0")
			if j.count < 1 or j.count > 12:
				err.call("count must be 1-12")
		Form.AREA:
			if j.power <= 0.0 or j.radius <= 0.0:
				err.call("area needs power and radius > 0")
		Form.WALL:
			if j.duration <= 0.0 or j.radius <= 0.0:
				err.call("wall needs duration and radius > 0")
		Form.BUFF:
			if not BUFF_STATS.has(j.buff_stat):
				err.call("buff_stat must be one of %s" % BUFF_STATS)
			if j.duration <= 0.0 or j.power <= 0.0:
				err.call("buff needs duration and power > 0")
			if j.buff_stat == "damage_reduction" and j.power >= 1.0:
				err.call("damage_reduction must be < 1.0 (1.0 would be invulnerability)")
		Form.HEAL:
			if j.power <= 0.0:
				err.call("heal needs power > 0")

	return j if errors.size() == start_errors else null


static func _num(data: Dictionary, key: String, fallback: float, err: Callable) -> float:
	var v: Variant = data.get(key, fallback)
	if not (v is float or v is int):
		err.call("'%s' must be a number" % key)
		return fallback
	if float(v) < 0.0:
		err.call("'%s' must not be negative" % key)
		return fallback
	return float(v)


func seal_names() -> PackedStringArray:
	return Seal.sequence_to_names(seals)
