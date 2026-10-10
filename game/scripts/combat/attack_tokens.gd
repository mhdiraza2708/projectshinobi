class_name AttackTokens
extends RefCounted
## Turn-taking for hostile fighters that share a target. A crowd that all
## throws, weaves and swings in the same second is a wall of damage nobody
## can read; with tokens two at most attack at once, only one of them up
## close, and their starts are spread out so each tell can be seen on its own.
## Everyone else keeps circling until a turn frees up.
##
## A fighter asks `may_attack(self, melee)` before starting an attack. It
## needs `team` and `target`, and implements `is_attacking()`,
## `is_closing_in()` and `since_attack_began()` (see EnemyShinobi).

## Fighters with an attack under way (weaving, aiming, winding up) at once.
const MAX_ATTACKERS := 2
## Of those, how many are in on the target with a blow (running in or winding up).
const MAX_MELEE := 1
## Seconds between one fighter starting an attack and the next being allowed to.
const START_GAP := 0.6


## Whether `fighter` may begin an attack on its target now. `melee` is a blow
## up close rather than something thrown or woven. Bosses always may (but
## still take a turn from the others); allies and practice clones are not
## limited.
static func may_attack(fighter: Node, melee: bool) -> bool:
	if not fighter.is_inside_tree() or fighter.get(&"drill") == true:
		return true
	if fighter.has_method(&"is_ally") and fighter.is_ally():
		return true
	var attacking := 0
	var closing := 0
	var latest := INF
	for node in fighter.get_tree().get_nodes_in_group(fighter.get(&"team")):
		if node == fighter or not node.has_method(&"is_attacking") or node.get(&"target") != fighter.get(&"target"):
			continue
		if node.is_attacking():
			attacking += 1
		if node.is_closing_in():
			closing += 1
		latest = minf(latest, node.since_attack_began())
	if fighter.has_method(&"is_boss") and fighter.is_boss():
		return true
	if attacking >= MAX_ATTACKERS or (melee and closing >= MAX_MELEE):
		return false
	return latest >= START_GAP
