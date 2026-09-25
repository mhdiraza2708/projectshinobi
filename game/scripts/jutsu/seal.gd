class_name Seal
extends RefCounted
## The twelve hand seals, named after the Chinese zodiac.
##
## A seal is input as (bank, direction):
##   bank 0 = no modifier, bank 1 = Bank II held, bank 2 = Bank III held
##   direction = bottom / right / left / top face input
## so seal index = bank * 4 + direction, and the zodiac order falls out of the
## grid below.
##
##              bottom   right    left     top
##   Bank I     Rat      Ox       Tiger    Hare
##   Bank II    Dragon   Snake    Horse    Ram
##   Bank III   Monkey   Bird     Dog      Boar

enum { RAT, OX, TIGER, HARE, DRAGON, SNAKE, HORSE, RAM, MONKEY, BIRD, DOG, BOAR }
enum Direction { BOTTOM, RIGHT, LEFT, TOP }

const COUNT := 12
const BANKS := 3
const NAMES: PackedStringArray = [
	"rat", "ox", "tiger", "hare", "dragon", "snake",
	"horse", "ram", "monkey", "bird", "dog", "boar",
]

## Input actions for each Direction, in Direction order.
const DIRECTION_ACTIONS: Array[StringName] = [&"seal_down", &"seal_right", &"seal_left", &"seal_up"]
## Modifier action for each bank (bank 0 has none).
const BANK_ACTIONS: Array[StringName] = [&"", &"seal_layer_1", &"seal_layer_2"]
const BANK_NAMES: PackedStringArray = ["I", "II", "III"]
## The zodiac (earthly branch) character for each seal, shown on talismans.
const KANJI: PackedStringArray = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]


static func from_input(bank: int, direction: int) -> int:
	return clampi(bank, 0, BANKS - 1) * 4 + clampi(direction, 0, 3)


static func bank_of(seal: int) -> int:
	return floori(seal / 4.0)


static func direction_of(seal: int) -> int:
	return seal % 4


static func is_valid(seal: int) -> bool:
	return seal >= 0 and seal < COUNT


static func from_name(seal_name: String) -> int:
	return NAMES.find(seal_name.strip_edges().to_lower())


static func display_name(seal: int) -> String:
	return NAMES[seal].capitalize() if is_valid(seal) else "?"


static func kanji(seal: int) -> String:
	return KANJI[seal] if is_valid(seal) else "?"


static func sequence_to_names(sequence: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for s in sequence:
		out.append(display_name(s))
	return out
