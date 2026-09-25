class_name Element
extends RefCounted
## Chakra natures and the advantage cycle between them.
## Each nature beats exactly one other and loses to exactly one other:
##   fire > wind > lightning > earth > water > fire

enum { NONE, FIRE, WIND, LIGHTNING, EARTH, WATER }

const NAMES: PackedStringArray = ["none", "fire", "wind", "lightning", "earth", "water"]
const BEATS := {FIRE: WIND, WIND: LIGHTNING, LIGHTNING: EARTH, EARTH: WATER, WATER: FIRE}
## Kanji stamped on element seals in the UI (always shown with the name too).
const KANJI: PackedStringArray = ["無", "火", "風", "雷", "土", "水"]

const ADVANTAGE_MULTIPLIER := 1.5
const DISADVANTAGE_MULTIPLIER := 0.75

# Colours are never the only signal: the HUD always prints the nature name.
const COLORS := {
	NONE: Color(0.72, 0.85, 1.0),
	FIRE: Color(1.0, 0.42, 0.12),
	WIND: Color(0.55, 1.0, 0.7),
	LIGHTNING: Color(1.0, 0.95, 0.4),
	EARTH: Color(0.72, 0.52, 0.3),
	WATER: Color(0.2, 0.55, 1.0),
}


static func from_name(element_name: String) -> int:
	return NAMES.find(element_name.strip_edges().to_lower())


static func display_name(element: int) -> String:
	return NAMES[element].capitalize() if element >= 0 and element < NAMES.size() else "?"


static func kanji(element: int) -> String:
	return KANJI[element] if element >= 0 and element < KANJI.size() else "?"


static func color(element: int) -> Color:
	return COLORS.get(element, COLORS[NONE])


## Damage multiplier for an `attacker`-natured hit landing on a
## `defender`-natured target.
static func multiplier(attacker: int, defender: int) -> float:
	if BEATS.get(attacker, -1) == defender:
		return ADVANTAGE_MULTIPLIER
	if BEATS.get(defender, -1) == attacker:
		return DISADVANTAGE_MULTIPLIER
	return 1.0
