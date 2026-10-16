class_name SealPoses
extends RefCounted
## What each of the twelve hand seals looks like: where the two wrists are,
## which way the fingers and thumbs point, how far each finger curls. They are
## read by HumanoidPoser while a character weaves; moving from one seal to the
## next is the poser's own blend.
##
## Frame (as the poser's): +x is the character's right, +y up, -z forward. Wrist
## positions are offsets from the middle of the shoulders in arm lengths
## (0, -0.32, -0.5 is the middle of the chest, a half arm out). `hand` is the
## way the fingers point and `thumb` the way the thumb points. `fin` is the
## curl of the index, middle, ring and little fingers (0 straight, about 1.2 a
## fist); `wrap` is how far the thumb folds across the palm (0 to 1).
##
## They are twelve readable, distinct shapes in the manner of the hand seals
## ninja imagery uses, not copies of any one artist's drawings.

const COUNT := 12

const HAND_LEN := 0.3
const CHEST := Vector3(0.0, -0.32, -0.5)

## index, middle, ring, little
const FLAT := [0.0, 0.0, 0.0, 0.0]
const FIST := [1.25, 1.25, 1.25, 1.25]
const SOFT := [0.35, 0.35, 0.35, 0.35]
const HOOK := [0.8, 0.8, 0.8, 0.8]


## The pose for `seal` (0-11) as the poser's target keys, or {} for none.
static func pose(seal: int) -> Dictionary:
	if seal < 0 or seal >= COUNT:
		return {}
	return _build(_table()[seal])


## Both hands' authored values -> the poser's flat keys.
static func _build(d: Dictionary) -> Dictionary:
	var out := {
		"seal_L": d["wl"], "seal_R": d["wr"],
		"hand_L": (d["fl"] as Vector3).normalized(), "hand_R": (d["fr"] as Vector3).normalized(),
		"thumb_L": (d["tl"] as Vector3).normalized(), "thumb_R": (d["tr"] as Vector3).normalized(),
		"wrap_L": float(d.get("wrapl", 0.3)), "wrap_R": float(d.get("wrapr", 0.3)),
		"pole_L": d.get("pl", Vector3(-1.0, -0.7, 0.4)), "pole_R": d.get("pr", Vector3(1.0, -0.7, 0.4)),
		"lean": float(d.get("lean", 0.06)),
		"spread_L": float(d.get("spl", 0.0)), "spread_R": float(d.get("spr", 0.0)),
	}
	for side in ["L", "R"]:
		var fin: Array = d["fin" + side.to_lower()]
		for i in 4:
			out["fin_%s_%d" % [side, i]] = float(fin[i])
	return out


static func _table() -> Array[Dictionary]:
	var up := Vector3(0, 0.85, -0.35)
	var fwd := Vector3(0, 0.1, -1)
	var close := CHEST
	return [
		# 0 Rat: the left hand closes round two raised fingers of the right.
		{"wl": close + Vector3(-0.03, -0.12, -0.02), "wr": close + Vector3(0.03, -0.13, 0.03),
			"fl": Vector3(1, 0.15, -0.35), "fr": Vector3(-0.05, 1, -0.15), "tl": Vector3(0, 1, 0.2), "tr": Vector3(0, 0, 1),
			"finl": [1.0, 1.05, 1.1, 1.15], "finr": [0.0, 0.0, 1.4, 1.4], "wrapl": 0.5, "wrapr": 0.8, "spl": 0.0, "spr": -0.3},
		# 1 Ox: two flat hands stacked, the right over the left, fingers together.
		{"wl": close + Vector3(-0.02, -0.08, 0.0), "wr": close + Vector3(0.12, -0.02, 0.0),
			"fl": Vector3(1, 0, -0.2), "fr": Vector3(-1, 0, -0.2), "tl": Vector3(0, 0, 1), "tr": Vector3(0, 0, 1),
			"finl": FLAT, "finr": FLAT, "wrapl": 0.3, "wrapr": 0.3, "spl": 0.0, "spr": 0.0},
		# 2 Tiger: palms together, index and middle straight up and together, ring
		# and little folded, thumbs over them.
		{"wl": close + Vector3(-0.05, 0.0, 0.0), "wr": close + Vector3(0.05, 0.0, 0.0),
			"fl": Vector3(0, 1, -0.2), "fr": Vector3(0, 1, -0.2), "tl": Vector3(0, 0, 1), "tr": Vector3(0, 0, 1),
			"finl": [0.0, 0.0, 1.4, 1.4], "finr": [0.0, 0.0, 1.4, 1.4], "wrapl": 0.9, "wrapr": 0.9, "spl": -0.3, "spr": -0.3},
		# 3 Hare: two hands each with index and middle in a V, the other fingers folded.
		{"wl": close + Vector3(-0.09, 0.04, 0.0), "wr": close + Vector3(0.09, 0.04, 0.0),
			"fl": Vector3(-0.25, 0.9, -0.3), "fr": Vector3(0.25, 0.9, -0.3), "tl": Vector3(0.2, 0, 1), "tr": Vector3(-0.2, 0, 1),
			"finl": [0.0, 0.0, 1.3, 1.3], "finr": [0.0, 0.0, 1.3, 1.3], "wrapl": 0.9, "wrapr": 0.9, "spl": 1.0, "spr": 1.0},
		# 4 Dragon: a diamond window, the fingertips meeting above and the
		# thumbs below.
		{"wl": close + Vector3(-0.1, -0.06, 0.0), "wr": close + Vector3(0.1, -0.06, 0.0),
			"fl": Vector3(0.28, 0.9, -0.3), "fr": Vector3(-0.28, 0.9, -0.3), "tl": Vector3(0.6, -0.7, -0.2), "tr": Vector3(-0.6, -0.7, -0.2),
			"finl": [0.15, 0.25, 0.35, 0.45], "finr": [0.15, 0.25, 0.35, 0.45], "wrapl": -0.7, "wrapr": -0.7, "spl": -0.2, "spr": -0.2},
		# 5 Snake: hands clasped with the fingers laced deep between each other,
		# thumbs up.
		{"wl": close + Vector3(-0.09, -0.1, 0.02), "wr": close + Vector3(0.09, -0.1, 0.02),
			"fl": Vector3(1, 0.25, -0.35), "fr": Vector3(-1, 0.25, -0.35), "tl": Vector3(0, 1, 0), "tr": Vector3(0, 1, 0),
			"finl": [0.85, 0.9, 0.95, 1.0], "finr": [0.85, 0.9, 0.95, 1.0], "wrapl": -0.9, "wrapr": -0.9, "spl": 0.4, "spr": 0.4},
		# 6 Horse: palms together, only the index fingers straight up (a steeple),
		# the rest folded, thumbs tucked.
		{"wl": close + Vector3(-0.05, -0.04, 0.0), "wr": close + Vector3(0.05, -0.04, 0.0),
			"fl": Vector3(0, 1, -0.15), "fr": Vector3(0, 1, -0.15), "tl": Vector3(0, 0, 1), "tr": Vector3(0, 0, 1),
			"finl": [0.0, 1.4, 1.4, 1.4], "finr": [0.0, 1.4, 1.4, 1.4], "wrapl": 0.7, "wrapr": 0.7, "spl": 0.0, "spr": 0.0},
		# 7 Ram: hands apart at the chest, palms facing, fingers straight and fanned wide.
		{"wl": close + Vector3(-0.11, -0.02, 0.0), "wr": close + Vector3(0.11, -0.02, 0.0),
			"fl": Vector3(0.1, 0.9, -0.45), "fr": Vector3(-0.1, 0.9, -0.45), "tl": Vector3(0.3, 0.2, -0.9), "tr": Vector3(-0.3, 0.2, -0.9),
			"finl": [0.1, 0.05, 0.05, 0.1], "finr": [0.1, 0.05, 0.05, 0.1], "wrapl": -0.5, "wrapr": -0.5, "spl": 1.0, "spr": 1.0},
		# 8 Monkey: the left palm up and flat, two fingers of the right hand pressed to it.
		{"wl": close + Vector3(-0.12, -0.06, -0.1), "wr": close + Vector3(0.04, 0.12, -0.1),
			"fl": Vector3(1, 0.05, -0.35), "fr": Vector3(-0.15, -0.9, -0.35), "tl": Vector3(0, 0, -1), "tr": Vector3(0, 0, 1),
			"finl": FLAT, "finr": [0.0, 0.0, 1.4, 1.4], "wrapl": 0.0, "wrapr": 0.8, "spl": 0.0, "spr": 0.3},
		# 9 Bird: wrists crossed, thumbs hooked, hands flat and spread up and out
		# like wings, palms out.
		{"wl": close + Vector3(0.02, -0.02, 0.0), "wr": close + Vector3(-0.02, -0.02, 0.0),
			"fl": Vector3(-0.65, 0.75, -0.2), "fr": Vector3(0.65, 0.75, -0.2), "tl": Vector3(0.6, -0.2, 0.3), "tr": Vector3(-0.6, -0.2, 0.3),
			"finl": FLAT, "finr": FLAT, "wrapl": -0.6, "wrapr": -0.6, "spl": 0.9, "spr": 0.9},
		# 10 Dog: the left hand an L (index and thumb out), the right laid flat across it.
		{"wl": close + Vector3(-0.04, -0.1, 0.0), "wr": close + Vector3(0.1, -0.03, 0.0),
			"fl": Vector3(0.2, 0.9, -0.4), "fr": Vector3(-1, 0, -0.1), "tl": Vector3(-0.8, 0.3, 0.2), "tr": Vector3(0, 0, 1),
			"finl": [0.0, 1.3, 1.3, 1.3], "finr": FLAT, "wrapl": -1.0, "wrapr": 0.2, "spl": 0.0, "spr": 0.0},
		# 11 Boar: horns, the index and little fingers up on both hands, the middle
		# and ring folded under the thumbs.
		{"wl": close + Vector3(-0.08, -0.02, 0.0), "wr": close + Vector3(0.08, -0.02, 0.0),
			"fl": Vector3(0.05, 1, -0.25), "fr": Vector3(-0.05, 1, -0.25), "tl": Vector3(1, 0, 0), "tr": Vector3(-1, 0, 0),
			"finl": [0.0, 1.4, 1.4, 0.0], "finr": [0.0, 1.4, 1.4, 0.0], "wrapl": 0.9, "wrapr": 0.9, "spl": 0.9, "spr": 0.9},
	]
