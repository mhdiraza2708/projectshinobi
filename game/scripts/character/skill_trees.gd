class_name SkillTrees
extends RefCounted
## Skill trees: three original paths (res://data/skill_trees.json) that turn
## experience into perks. Fights, chapters and trials give XP (Game.add_xp);
## every level is one skill point; a point buys one rank of a node whose
## prerequisites are learned and whose tier the tree has unlocked. A node's
## perks are the same named numbers clans and eye arts use (Perks), times
## its rank, so the game reads them wherever it already reads perks. Each
## tree ends in an ability: Second Wind, Twin Weave or Shadow Bloom. Ranks
## and XP live in the save slot (Game); points can be taken back for free.

const FILE := "res://data/skill_trees.json"
const COLUMNS := 3

## Second Wind: a blow that would defeat you leaves this much health, once,
## and comes back after this long without being hurt.
const SECOND_WIND_HEALTH := 0.3
const SECOND_WIND_RECHARGE := 30.0
const SECOND_WIND_SHIELD := 1.5
## Opening Flash: foes this close stagger when the eye opens.
const EYE_FLASH_RADIUS := 10.0
## Second Look: seconds added per hit, and the most one opening can gain.
const EYE_EXTEND_PER_HIT := 0.5
const EYE_EXTEND_MAX := 5.0
## Unclosing Eye: chakra a second to hold the eye open past its time.
const EYE_SUSTAIN_DRAIN := 6.0
## Counter Edge: a strike this soon after the guard takes a blow.
const COUNTER_WINDOW := 1.0
## Crescent Moon: the third cut's flying crescent, as a multiple of the cut.
const BLADE_WAVE_POWER := 2.2
const BLADE_WAVE_SPEED := 26.0
const BLADE_WAVE_RANGE := 18.0
## Twin Weave: each projectile jutsu fires an echo this much later, at this
## fraction of its power.
const TWIN_WEAVE_DELAY := 0.18
const TWIN_WEAVE_POWER := 0.5
## Shadow Bloom: a Shade Clone bursts for this much damage, this wide, when it
## fades or falls.
const SHADOW_BLOOM_POWER := 22.0
const SHADOW_BLOOM_RADIUS := 4.0

## Why a node can't be learned (can_learn's answers).
const OK := ""
const MAXED := "maxed"
const NO_POINTS := "no_points"
const NEEDS_NODE := "needs_node"
const NEEDS_POINTS := "needs_points"
const NEEDS_EYE := "needs_eye"

static var errors: Array[String] = []
static var _trees: Array[Dictionary] = []
static var _nodes: Dictionary = {}
static var _xp: Dictionary = {}
static var _levels: Dictionary = {}
static var _tier_points: Array = []
static var _loaded := false
static var _perks_cache: Variant = null


static func reload() -> void:
	errors = []
	_trees = []
	_nodes = {}
	_loaded = true
	_perks_cache = null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	if not parsed is Dictionary:
		errors.append("%s: not a JSON object" % FILE)
		return
	_xp = parsed.get("xp", {})
	_levels = parsed.get("levels", {"first": 100, "step": 30, "max": 50})
	_tier_points = parsed.get("tier_points", [0])
	for raw: Variant in parsed.get("trees", []):
		var tree: Dictionary = raw
		for key: String in ["id", "name", "kanji", "color", "blurb", "nodes"]:
			if not tree.has(key):
				errors.append("tree %s: missing %s" % [tree.get("id", "?"), key])
		if not Color.html_is_valid(str(tree.get("color", ""))):
			errors.append("tree %s: bad colour" % tree.get("id", "?"))
		var places := {}
		for n: Dictionary in tree.get("nodes", []):
			for key: String in ["id", "name", "kanji", "tier", "col", "ranks", "perks", "requires"]:
				if not n.has(key):
					errors.append("node %s: missing %s" % [n.get("id", "?"), key])
			if _nodes.has(n.get("id")):
				errors.append("node %s appears twice" % n["id"])
			n["tree"] = tree["id"]
			_nodes[n.get("id", "?")] = n
			var place := Vector2i(int(n.get("col", 0)), int(n.get("tier", 1)))
			if places.has(place):
				errors.append("node %s sits on %s" % [n["id"], places[place]])
			places[place] = n["id"]
			if int(n.get("tier", 0)) < 1 or int(n.get("tier", 0)) > _tier_points.size() \
					or int(n.get("col", -1)) < 0 or int(n.get("col", -1)) >= COLUMNS:
				errors.append("node %s: tier or column out of range" % n["id"])
			if int(n.get("ranks", 0)) < 1:
				errors.append("node %s: needs at least one rank" % n["id"])
			for key: String in n.get("perks", {}):
				if not Perks.PERK_TEXT.has(key) and not Perks.FLAG_TEXT.has(key):
					errors.append("node %s: unknown perk '%s'" % [n["id"], key])
		_trees.append(tree)
	for n: Dictionary in _nodes.values():
		for req: String in n.get("requires", []):
			if not _nodes.has(req):
				errors.append("node %s: requires unknown node '%s'" % [n["id"], req])
			elif _nodes[req]["tree"] != n["tree"] or int(_nodes[req]["tier"]) >= int(n["tier"]):
				errors.append("node %s: requires %s, which isn't below it in the same tree" % [n["id"], req])
		if int(n.get("tier", 1)) > 1 and (n.get("requires", []) as Array).is_empty():
			errors.append("node %s: only the first tier stands on its own" % n["id"])


static func _ensure() -> void:
	if not _loaded:
		reload()


static func trees() -> Array[Dictionary]:
	_ensure()
	return _trees


static func tree(id: String) -> Dictionary:
	for t in trees():
		if t["id"] == id:
			return t
	return {}


static func node(id: String) -> Dictionary:
	_ensure()
	return _nodes.get(id, {})


## Points a tier needs already spent in its tree.
static func tier_points(tier: int) -> int:
	_ensure()
	return int(_tier_points[clampi(tier - 1, 0, _tier_points.size() - 1)])


# --- Experience and levels ------------------------------------------------------

## XP for a reason ("genin", "boss", "chapter", "trial"...; 0 if unknown).
static func xp_for(reason: String) -> int:
	_ensure()
	return int(_xp.get(reason, 0))


## XP for defeating an enemy of this rank.
static func enemy_xp(rank: StringName, boss: bool) -> int:
	return xp_for("boss") if boss else xp_for(String(rank))


static func max_level() -> int:
	_ensure()
	return int(_levels.get("max", 50))


## XP from `level` to the next.
static func xp_to_next(level: int) -> int:
	_ensure()
	return int(_levels.get("first", 100)) + int(_levels.get("step", 30)) * (level - 1)


## Total XP that reaches `level` (level 1 is 0).
static func xp_for_level(level: int) -> int:
	var total := 0
	for l in range(1, level):
		total += xp_to_next(l)
	return total


static func level_for_xp(xp: int) -> int:
	var level := 1
	while level < max_level() and xp >= xp_for_level(level + 1):
		level += 1
	return level


static func level() -> int:
	return level_for_xp(Game.xp())


## How far through the current level (0..1; 1 at the cap).
static func level_progress() -> float:
	var l := level()
	if l >= max_level():
		return 1.0
	return float(Game.xp() - xp_for_level(l)) / float(xp_to_next(l))


## Awards the XP a reason is worth. Returns levels gained.
static func award(reason: String) -> int:
	return Game.add_xp(xp_for(reason), reason)


# --- Points and ranks -------------------------------------------------------------

static func rank(id: String) -> int:
	return int(Game.skill_ranks().get(id, 0))


static func points_total() -> int:
	return level() - 1


static func points_spent(tree_id := "") -> int:
	var spent := 0
	var ranks := Game.skill_ranks()
	for id: String in ranks:
		if tree_id == "" or node(id).get("tree", "") == tree_id:
			spent += int(ranks[id])
	return spent


static func points_free() -> int:
	return maxi(0, points_total() - points_spent())


## OK if `id` can take another rank now, otherwise why not.
static func can_learn(id: String) -> String:
	var n := node(id)
	if n.is_empty() or rank(id) >= int(n["ranks"]):
		return MAXED
	if bool(tree(str(n["tree"])).get("needs_eye_art", false)) and Perks.active_eye_art().is_empty():
		return NEEDS_EYE
	var reqs: Array = n["requires"]
	if not reqs.is_empty() and not reqs.any(func(r: String) -> bool: return rank(r) > 0):
		return NEEDS_NODE
	if points_spent(n["tree"]) < tier_points(int(n["tier"])):
		return NEEDS_POINTS
	if points_free() < 1:
		return NO_POINTS
	return OK


## Spends a point on `id`. Returns whether it was learned.
static func learn(id: String) -> bool:
	if can_learn(id) != OK:
		return false
	var ranks := Game.skill_ranks()
	ranks[id] = rank(id) + 1
	Game.set_skill_ranks(ranks)
	return true


## Takes every point back (one tree, or all of them).
static func reset(tree_id := "") -> void:
	var ranks := Game.skill_ranks()
	for id: String in ranks.keys():
		if tree_id == "" or node(id).get("tree", "") == tree_id:
			ranks.erase(id)
	Game.set_skill_ranks(ranks)


## Everything learned, as one perk dictionary (rank times each node's perks).
static func perks() -> Dictionary:
	if _perks_cache != null:
		return _perks_cache
	var total := {}
	var ranks := Game.skill_ranks()
	for id: String in ranks:
		var n := node(id)
		var r := mini(int(ranks[id]), int(n.get("ranks", 0)))
		for key: String in n.get("perks", {}):
			total[key] = float(total.get(key, 0.0)) + float(n["perks"][key]) * r
	_perks_cache = total
	return total


## A node's perks at a rank (for the menu: now and next).
static func perks_at(id: String, at_rank: int) -> Dictionary:
	var out := {}
	var n := node(id)
	for key: String in n.get("perks", {}):
		out[key] = float(n["perks"][key]) * at_rank
	return out


## Forget the cached perk totals (ranks or the save slot changed).
static func invalidate() -> void:
	_perks_cache = null
