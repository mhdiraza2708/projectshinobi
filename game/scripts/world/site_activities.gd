class_name SiteActivities
extends Node
## What there is to do at the continent's places of interest, for OpenWorld:
## a camp's fire draws you into a fight, a shrine can be attuned to (rest,
## and travel to it from the map), a ruin holds a relic, and a village's
## board offers a contract to clear a camp.

const CAMP_TRIGGER := 24.0
const LAIR_TRIGGER := 30.0
const RELIC_RANGE := 2.4
const SHRINE_RANGE := 3.6
const BOARD_RANGE := 3.6
## How far a contract's camp may be from the board that offers it.
const CONTRACT_REACH := 1100.0
## The mark each kind has on the location card and the map.
const KANJI := {"camp": "賊", "shrine": "社", "village": "村", "ruin": "跡", "lair": "賞"}
## What the fighters of a region use.
const REGION_ELEMENTS := {
	"emberwood": ["fire", "earth"], "autumn_wood": ["wind", "earth"], "ashen_pass": ["fire", "lightning"],
	"old_dam": ["water", "earth"], "frozen_road": ["water", "wind"], "five_winds": ["wind", "lightning"],
}
## Camp waves by danger (0-2): [rank, count] pairs per wave.
const WAVES := [
	[[["genin", 3]], [["genin", 2], ["chunin", 1]]],
	[[["genin", 2], ["chunin", 2]], [["chunin", 3]]],
	[[["chunin", 3]], [["chunin", 2], ["jonin", 1]]],
]
const PREFIX := "site:"

var world: OpenWorld
var sites: WorldSites


## A camp's waves, in the shape quests use: [[[rank, element], ...], ...].
## Danger sets who is there; the story tier adds a wave and a veteran.
static func camp_waves(site: Dictionary, tier: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site["seed"])
	var elements: Array = REGION_ELEMENTS.get(str(site["region"]), ["fire", "earth"])
	var out: Array = []
	var plan: Array = (WAVES[clampi(int(site["danger"]), 0, 2)] as Array).duplicate(true)
	if tier >= 3:
		plan.append([["chunin", 2], ["jonin", 1]])
	if tier >= 5:
		plan.append([["jonin", 2]])
	for wave: Array in plan:
		var w: Array = []
		for pair: Array in wave:
			for i in int(pair[1]):
				w.append([pair[0], elements[rng.randi() % elements.size()]])
		out.append(w)
	return out


static func camp_xp(site: Dictionary, tier: int) -> int:
	return 120 + 40 * int(site["danger"]) + 25 * tier


static func bounty_xp(b: Dictionary, tier: int) -> int:
	return 250 + 100 * int(b["danger"]) + 40 * tier


static func relic_xp(site: Dictionary, tier: int) -> int:
	return 70 + 20 * int(site["danger"]) + 10 * tier


static func shrine_xp(site: Dictionary) -> int:
	return 60 + 20 * int(site["danger"])


# --- Finding places ---------------------------------------------------------------

func on_found(site: Dictionary) -> void:
	var kind := str(site["kind"])
	world.tracker.show_location(str(site["name"]), KANJI.get(kind, ""))
	var hint := ""
	match kind:
		"camp":
			hint = "  ·  raiders hold it"
		"shrine":
			hint = "  ·  attune to it to rest and travel here"
		"village":
			hint = "  ·  its notice board has work"
		"ruin":
			hint = "  ·  something lies among the stones"
		"lair":
			hint = "  ·  a wanted shinobi holds it"
	world.hud.show_banner("Found %s%s" % [site["name"], hint], &"info")


# --- The loop (OpenWorld calls it each physics frame while you roam) --------------------

func check() -> void:
	if sites == null or world.busy:
		return
	var pos := world.player.global_position
	var camp := sites.nearest(pos, ["camp"], "fire", CAMP_TRIGGER)
	if not camp.is_empty() and not sites.is_done(camp["site"]["id"]):
		start_camp(camp["site"], camp["node"])
		return
	var lair := sites.nearest(pos, ["lair"], "den", LAIR_TRIGGER)
	if not lair.is_empty() and not sites.is_done(lair["site"]["id"]):
		start_lair(lair["site"], lair["node"])
		return
	var relic := sites.nearest(pos + Vector3.UP * 0.6, ["ruin"], "relic", RELIC_RANGE)
	if not relic.is_empty() and not sites.is_done(relic["site"]["id"]):
		take_relic(relic["site"])


## What to offer for pressing Interact here: {kind, id, prompt} or {}.
func interact_for(pos: Vector3) -> Dictionary:
	if sites == null:
		return {}
	var shrine := sites.nearest(pos, ["shrine"], "interact", SHRINE_RANGE)
	if not shrine.is_empty():
		var s: Dictionary = shrine["site"]
		var attuned := sites.is_done(s["id"])
		return {"kind": "shrine", "id": s["id"], "prompt": ("Pray at  %s" if attuned else "Attune to  %s") % s["name"]}
	var board := sites.nearest(pos, ["village"], "board", BOARD_RANGE)
	if not board.is_empty():
		var s: Dictionary = board["site"]
		var prompt := "Read the notice board"
		if contract() == "":
			prompt = "Take a contract  (notice board)"
		return {"kind": "board", "id": s["id"], "prompt": prompt}
	return {}


func use(kind: String, id: String) -> void:
	match kind:
		"shrine":
			attune(id)
		"board":
			read_board(id)


# --- Camps ----------------------------------------------------------------------

func start_camp(site: Dictionary, node: SiteNode) -> void:
	var tier := world.story_tier()
	var q := {
		"id": PREFIX + str(site["id"]), "name": str(site["name"]), "type": "defeat",
		"waves": camp_waves(site, tier),
	}
	world.hud.show_banner("%s  ·  they have seen you" % site["name"], &"fail")
	world.start_fight(q, node.spot("fire"))


## A wanted shinobi at their lair: they speak, then the duel begins.
func start_lair(site: Dictionary, node: SiteNode) -> void:
	world.busy = true
	await world.start_bounty(Bounties.get_bounty(str(site["bounty"])), node.spot("den"), PREFIX + str(site["id"]))


## A camp's or lair's fight is won: it is cleared for good, and pays (twice
## over when a contract named it).
func finish_fight(quest_id: String) -> void:
	var id := quest_id.trim_prefix(PREFIX)
	var site := sites.plan.site(id)
	if site.is_empty():
		return
	sites.set_state(id, WorldSites.DONE)
	var tier := world.story_tier()
	var lair := str(site["kind"]) == "lair"
	var xp := bounty_xp(Bounties.get_bounty(str(site["bounty"])), tier) if lair else camp_xp(site, tier)
	var note := ""
	if contract() == id:
		xp *= 2
		note = "  ·  contract fulfilled"
		Game.set_record("world", "contract", "")
		Game.set_record("world", "contracts_done", int(Game.record("world", "contracts_done", 0)) + 1)
	Game.add_xp(xp, "bounty" if lair else "camp")
	if lair:
		Game.set_record("world", "bounties", int(Game.record("world", "bounties", 0)) + 1)
		world.hud.show_banner("%s is finished   +%d XP%s" % [Bounties.get_bounty(str(site["bounty"]))["name"], xp, note], &"cast")
	else:
		world.hud.show_banner("%s cleared   +%d XP%s" % [site["name"], xp, note], &"cast")
	Sfx.play(&"quest_done")
	Game.save_records()


# --- Ruins and shrines ------------------------------------------------------------------

func take_relic(site: Dictionary) -> void:
	sites.set_state(site["id"], WorldSites.DONE)
	var xp := relic_xp(site, world.story_tier())
	Game.add_xp(xp, "relic")
	Game.set_record("world", "relics", int(Game.record("world", "relics", 0)) + 1)
	world.hud.show_banner("Relic found at %s   +%d XP   (%d taken)" % [site["name"], xp, int(Game.record("world", "relics", 0))], &"cast")
	Sfx.play(&"quest_done")
	Game.save_records()


func attune(id: String) -> void:
	var site := sites.plan.site(id)
	if site.is_empty():
		return
	world.player.stats.restore()
	Sfx.play(&"quest_accept")
	if sites.is_done(id):
		world.hud.show_banner("You rest at %s" % site["name"], &"info")
		return
	sites.set_state(id, WorldSites.DONE)
	var xp := shrine_xp(site)
	Game.add_xp(xp, "shrine")
	world.hud.show_banner("Attuned to %s   +%d XP  ·  travel here from the map" % [site["name"], xp], &"cast")
	Game.save_records()


# --- Contracts --------------------------------------------------------------------------

## The camp a contract names ("" for none).
func contract() -> String:
	return str(Game.record("world", "contract", ""))


## The nearest camp not yet cleared within reach of a board; every third
## contract is a wanted shinobi's lair instead (when one is left in reach).
func contract_target(board_site: Dictionary) -> Dictionary:
	var want_lair := int(Game.record("world", "contracts_done", 0)) % 3 == 2
	var kinds: Array = ["lair", "camp"] if want_lair else ["camp", "lair"]
	for kind: String in kinds:
		var best := {}
		var best_d := CONTRACT_REACH
		for s: Dictionary in sites.plan.of_kind(kind):
			if sites.is_done(s["id"]):
				continue
			var d := (s["at"] as Vector2).distance_to(board_site["at"])
			if d < best_d:
				best_d = d
				best = s
		if not best.is_empty():
			return best
	return {}


func _contract_line(s: Dictionary) -> String:
	if str(s["kind"]) == "lair":
		return "%s is held at %s near %s" % [Bounties.get_bounty(str(s["bounty"]))["name"], s["name"], Island.display_name(str(s["region"]))]
	return "clear %s near %s" % [s["name"], Island.display_name(str(s["region"]))]


func read_board(id: String) -> void:
	var board := sites.plan.site(id)
	var have := contract()
	if have != "":
		world.hud.show_banner("Contract:  %s" % _contract_line(sites.plan.site(have)), &"info")
		return
	var target := contract_target(board)
	if target.is_empty():
		world.hud.show_banner("The board is bare: nothing hereabouts is left to do", &"info")
		return
	Game.set_record("world", "contract", target["id"])
	sites.set_state(target["id"], WorldSites.FOUND)
	world.hud.show_banner("Contract:  %s   (double pay)" % _contract_line(target), &"cast")
	Sfx.play(&"quest_accept")
	Game.save_records()
