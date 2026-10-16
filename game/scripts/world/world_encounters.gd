class_name WorldEncounters
extends Node
## Life on the roads between the continent's places. While you roam the wilds,
## every few hundred metres something waits a little way ahead of you:
##
## - **ambush**: raiders lying in wait spring out as you pass (waves, as a camp);
## - **rescue**: raiders have a traveller cornered; save them and they tell you
##   of a place you have not found (it goes on your map);
## - **duelist**: a wandering shinobi bars the road and duels you;
## - **pilgrim**: someone resting by the way who knows of a place nearby;
## - **cache**: a dropped bundle of supplies (XP, wounds bound, chakra back).
##
## One at a time, never in a region or near a place, never during a chapter.
## Walk away from one you never reached and it goes. OpenWorld routes the
## fights (quest ids under PREFIX) back here.

const PREFIX := "road:"
const KINDS: Array[String] = ["ambush", "rescue", "duelist", "pilgrim", "cache"]
## How often each kind comes up, against the others.
const WEIGHTS := {"ambush": 3.0, "rescue": 2.0, "duelist": 1.5, "pilgrim": 1.5, "cache": 2.0}
const KANJI := {"ambush": "伏", "rescue": "助", "duelist": "流", "pilgrim": "巡", "cache": "包"}
## Metres travelled through the wilds between one encounter and the next.
const SPACING := Vector2(300.0, 500.0)
## How far ahead of you one appears.
const AHEAD := 60.0
## Walk this far from one you never reached and it goes.
const GIVE_UP := 170.0
## Kept this far from the places of interest and the regions' edges.
const SITE_CLEAR := 110.0
const REGION_CLEAR := 60.0
## How near you come before it begins.
const TRIGGER := {"ambush": 20.0, "rescue": 34.0, "duelist": 18.0, "pilgrim": 3.6, "cache": 2.4}
## Faster than this between two frames is travel, not walking.
const JUMP := 40.0

## Names for the wandering duelists (kanji, name).
const DUELISTS := [
	["流", "Drifting Blade"], ["孤", "Lone Fang"], ["影", "Roadside Shade"], ["嵐", "Storm Pilgrim"],
	["鬼", "Masterless Oni"], ["鴉", "Crow of the Pass"], ["霧", "Mist Walker"], ["狼", "Grey Wolf"],
]
const TAUNTS := [
	"This road has a toll, and I am it.",
	"I have walked a long way looking for someone worth crossing blades with.",
	"No village, no master, no reason. Draw.",
	"They say the academy's new blood is sharp. Show me.",
]
## Each nature's rival model (game/assets/characters/rivals).
const MODELS := {
	"fire": "fire_raider", "earth": "earth_stone_warden", "lightning": "lightning_storm_caller",
	"water": "water_tide_runner", "wind": "wind_gale_shinobi",
}

var world: OpenWorld
var sites: WorldSites

## The encounter waiting or under way: {kind, at (world), region, nodes, ...} or {}.
var current: Dictionary = {}

var _travelled := 0.0
var _next := 0.0
var _last := Vector3.INF
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "WorldEncounters"
	_rng.randomize()
	_next = _rng.randf_range(SPACING.x, SPACING.y)
	if world and world.player:
		world.player.defeated.connect(_on_player_defeated)


# --- Rewards -------------------------------------------------------------------------

static func xp_for(kind: String, tier: int) -> int:
	match kind:
		"ambush":
			return 70 + 20 * tier
		"rescue":
			return 100 + 25 * tier
		"duelist":
			return 150 + 35 * tier
		"pilgrim":
			return 30 + 5 * tier
		"cache":
			return 40 + 10 * tier
	return 0


## How many of each kind you have seen through.
func done_count(kind: String) -> int:
	return int((Game.record("world", "encounters", {}) as Dictionary).get(kind, 0))


func _count(kind: String) -> void:
	var tally: Dictionary = (Game.record("world", "encounters", {}) as Dictionary).duplicate()
	tally[kind] = int(tally.get(kind, 0)) + 1
	Game.set_record("world", "encounters", tally)


# --- Where -----------------------------------------------------------------------------

## Whether an encounter may stand at `at` (world space): dry, fairly level
## ground in the wilds, clear of the regions, the places, rivers and lakes.
func good_spot(at: Vector3) -> bool:
	var cw := world.archipelago as ContinentWorld
	if cw == null:
		return false
	var land := cw.continent.land
	var p := cw.to_local(at)
	if land.height_at(p.x, p.z) < ContinentLand.SEA_LEVEL + 2.0 or land.slope_at(p.x, p.z) > 0.25:
		return false
	if cw.island_near(at, REGION_CLEAR) != "":
		return false
	if land.rivers.query(p.x, p.z).x < 12.0:
		return false
	for lake: Dictionary in land.lakes:
		if Vector2(p.x, p.z).distance_to(lake["at"]) < float(lake["radius"]) + 10.0:
			return false
	for s: Dictionary in sites.plan.sites:
		if Vector2(p.x, p.z).distance_to(s["at"]) < SITE_CLEAR:
			return false
	return true


## The ground under `at` (world space), from the land itself (the same
## everywhere, built or not).
func ground(at: Vector3) -> Vector3:
	var cw := world.archipelago as ContinentWorld
	var p := cw.to_local(at)
	return cw.to_global(Vector3(p.x, cw.continent.land.height_at(p.x, p.z), p.z))


## A good spot about AHEAD metres along `heading` from `from`, or null.
func spot_ahead(from: Vector3, heading: Vector3) -> Variant:
	heading.y = 0.0
	if heading.length() < 0.01:
		heading = Vector3.FORWARD
	heading = heading.normalized()
	for reach: float in [AHEAD, AHEAD * 1.3, AHEAD * 0.8]:
		for turn: float in [0.0, 0.3, -0.3, 0.6, -0.6]:
			var at := from + heading.rotated(Vector3.UP, turn) * reach
			if good_spot(at):
				return ground(at)
	return null


func _region_of(at: Vector3) -> String:
	var cw := world.archipelago as ContinentWorld
	var p := cw.to_local(at)
	return str(cw.continent.land.nearest_region(p.x, p.z)["id"])


# --- The loop ---------------------------------------------------------------------------

func _roaming() -> bool:
	return world.placed and world.get_parent().get(&"mode") == Game.Mode.WORLD \
		and is_instance_valid(world.player) and not world.player.is_down()


func _physics_process(_delta: float) -> void:
	if world == null or sites == null or not is_instance_valid(world.player):
		return
	if not _roaming():
		# A chapter began (or you went down): anything not yet begun goes.
		if not current.is_empty() and not current.get("begun", false):
			clear()
		_last = Vector3.INF
		return
	var pos := world.player.global_position
	if current.is_empty():
		_walk(pos)
	else:
		_tick(pos)


## Counts the metres you cover in the wilds, and when it is time, puts
## something on the road ahead.
func _walk(pos: Vector3) -> void:
	var step := Vector3.ZERO if _last == Vector3.INF else pos - _last
	_last = pos
	step.y = 0.0
	if step.length() > JUMP or world.busy or world.archipelago.island_near(pos) != "":
		return
	_travelled += step.length()
	if _travelled < _next:
		return
	var at: Variant = spot_ahead(pos, step)
	if not at is Vector3:
		# Nowhere good just here: look again a little further on.
		_travelled = _next - 40.0
		return
	_travelled = 0.0
	_next = _rng.randf_range(SPACING.x, SPACING.y)
	begin(_pick_kind(), at)


func _pick_kind() -> String:
	var total := 0.0
	for k: String in KINDS:
		total += float(WEIGHTS[k])
	var roll := _rng.randf() * total
	var kind := KINDS[0]
	for k: String in KINDS:
		roll -= float(WEIGHTS[k])
		if roll <= 0.0:
			kind = k
			break
	# Someone who knows of a place, only while there are places to find.
	if kind == "pilgrim" and _unfound_near(world.player.global_position).is_empty():
		kind = "cache"
	return kind


func _tick(pos: Vector3) -> void:
	var at: Vector3 = current["at"]
	var d := Vector2(pos.x - at.x, pos.z - at.z).length()
	if not current.get("begun", false):
		if d > GIVE_UP:
			clear()
		elif d < float(TRIGGER[current["kind"]]):
			_trigger()
		return
	if current["kind"] == "rescue":
		_tick_rescue()


# --- Beginning and ending --------------------------------------------------------------

## Puts an encounter of `kind` at `at` (world space, on the ground).
func begin(kind: String, at: Vector3) -> void:
	clear()
	current = {"kind": kind, "at": at, "region": _region_of(at), "nodes": [], "begun": false}
	match kind:
		"rescue":
			_set_rescue()
		"duelist":
			_set_duelist()
		"pilgrim":
			_set_pilgrim()
		"cache":
			_set_cache()


## Takes away whatever is on the road (nothing is paid).
func clear() -> void:
	for n: Variant in current.get("nodes", []):
		if is_instance_valid(n):
			if n is EnemyShinobi:
				(n as EnemyShinobi).leave()
			else:
				(n as Node).queue_free()
	if current.get("begun", false) and current["kind"] == "rescue":
		world.busy = false
	current = {}


func _trigger() -> void:
	current["begun"] = true
	match str(current["kind"]):
		"ambush":
			_start_ambush()
		"rescue":
			_start_rescue()
		"duelist":
			_start_duelist()
		"cache":
			_take_cache()
		"pilgrim":
			# The pilgrim waits to be spoken to (interact_for).
			current["begun"] = false


## OpenWorld: a fight under PREFIX ended.
func finish_fight(quest_id: String, won: bool) -> void:
	var kind := quest_id.trim_prefix(PREFIX)
	if current.get("kind", "") != kind:
		return
	if won:
		_pay(kind, "")
	clear()


func _pay(kind: String, note: String) -> void:
	var xp := xp_for(kind, world.story_tier())
	Game.add_xp(xp, "encounter")
	_count(kind)
	var what := {"ambush": "Ambush beaten", "rescue": "The traveller is safe", "duelist": "The duelist yields",
		"pilgrim": "A pilgrim's word", "cache": "Supplies"}
	world.hud.show_banner("%s   +%d XP%s" % [what[kind], xp, note], &"cast")
	Sfx.play(&"quest_done")


func _on_player_defeated() -> void:
	# The fight is lost: it does not wait for you (the road is long).
	if not current.is_empty() and current.get("begun", false):
		clear()


# --- Ambush ---------------------------------------------------------------------------

## The raiders' waves: [[[rank, element], ...], ...] (one wave, two late in the story).
func ambush_waves(tier: int) -> Array:
	var elements: Array = SiteActivities.REGION_ELEMENTS.get(str(current.get("region", "")), ["fire", "earth"])
	var plan: Array = [["genin", "genin", "genin"]]
	if tier >= 2:
		plan = [["genin", "genin", "chunin"]]
	if tier >= 3:
		plan.append(["chunin", "chunin"])
	if tier >= 5:
		plan[1] = ["chunin", "chunin", "jonin"]
	var out: Array = []
	for wave: Array in plan:
		var w: Array = []
		for rank: String in wave:
			w.append([rank, elements[_rng.randi() % elements.size()]])
		out.append(w)
	return out


func _start_ambush() -> void:
	var q := {"id": PREFIX + "ambush", "name": "Ambush on the road", "type": "defeat",
		"waves": ambush_waves(world.story_tier())}
	world.hud.show_banner("Ambush!  Raiders on the road", &"fail")
	world.start_fight(q, world.player.global_position)


# --- Rescue ---------------------------------------------------------------------------

func _set_rescue() -> void:
	var at: Vector3 = current["at"]
	var people := Quests.people().values().filter(func(p: Dictionary) -> bool: return str(p.get("model", "")) != "")
	var person: Dictionary = people[_rng.randi() % people.size()] if not people.is_empty() else {}
	var t := EnemyShinobi.new()
	t.name = "Traveller"
	t.team = &"player"
	t.rank = &"genin"
	t.element = Element.from_name(str(person.get("element", "earth")))
	t.title_override = "Traveller"
	t.health_override = 70.0 + 10.0 * world.story_tier()
	t.style_override = person.get("style", {})
	var chosen := CharacterModel.resolve_roster(str(person.get("model", "")))
	t.model_path = chosen if chosen != "" else EnemyShinobi.pick_model("traveller")
	t.hold = true
	world.archipelago.add_child(t)
	t.global_position = at + Vector3.UP * 0.2
	t.caster.power_scale *= 0.5
	_mark(t, KANJI["rescue"], UiKit.CRIMSON.lightened(0.25))
	current["traveller"] = t
	current["nodes"].append(t)
	var elements: Array = SiteActivities.REGION_ELEMENTS.get(str(current["region"]), ["fire", "earth"])
	var raiders: Array = []
	var count := 2 if world.story_tier() < 3 else 3
	for i in count:
		var e := EnemyShinobi.new()
		e.rank = &"chunin" if world.story_tier() >= 4 and i == 0 else &"genin"
		e.element = Element.from_name(str(elements[i % elements.size()]))
		e.tier = world.story_tier()
		e.target = t
		e.hold = true
		world.archipelago.add_child(e)
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / count + _rng.randf() * 0.5)
		e.global_position = ground(at + dir * 4.5) + Vector3.UP * 0.2
		raiders.append(e)
		current["nodes"].append(e)
	current["raiders"] = raiders
	world.hud.show_banner("Raiders have a traveller cornered on the road ahead", &"fail")


func _start_rescue() -> void:
	world.busy = true
	for n: Variant in current["nodes"]:
		if is_instance_valid(n):
			(n as EnemyShinobi).hold = false
	world.hud.show_banner("Save the traveller!", &"cast")
	Music.play(OpenWorld.CAMP_TRACK)


func _tick_rescue() -> void:
	var t: EnemyShinobi = current.get("traveller")
	if not current.get("fell", false) and (not is_instance_valid(t) or t.is_defeated()):
		current["fell"] = true
		world.hud.show_banner("The traveller has fallen", &"fail")
	for e: Variant in current["raiders"]:
		if is_instance_valid(e) and not (e as EnemyShinobi).is_defeated():
			return
	# Every raider is down.
	var saved := not bool(current.get("fell", false))
	var note := ""
	if saved:
		var site := _unfound_near(current["at"])
		if not site.is_empty():
			sites.set_state(site["id"], WorldSites.FOUND)
			note = "  ·  they tell you of %s (on your map)" % site["name"]
		_pay("rescue", note)
	world.busy = false
	world.update_music()
	clear()


# --- Duelist ---------------------------------------------------------------------------

## The wandering duelist, in the shape OpenWorld.start_bounty takes.
func duelist(tier: int) -> Dictionary:
	var pick: Array = DUELISTS[_rng.randi() % DUELISTS.size()]
	var elements: Array = SiteActivities.REGION_ELEMENTS.get(str(current.get("region", "")), ["fire", "earth"])
	var element := str(elements[_rng.randi() % elements.size()])
	var specials: Array = [{"kind": ["sweep", "chain", "quake"][_rng.randi() % 3], "every": 12, "damage": 10 + 2 * tier,
		"count": 3, "duration": 2.5}]
	return {"id": "road_duelist", "name": pick[1], "kanji": pick[0], "element": element, "model": MODELS[element],
		"health": 200.0 + 50.0 * tier, "danger": 0, "specials": specials, "taunt": TAUNTS[_rng.randi() % TAUNTS.size()]}


func _set_duelist() -> void:
	var b := duelist(world.story_tier())
	current["bounty"] = b
	# Standing in the road, waiting: a figure and their name.
	var npc := StoryNpc.new()
	npc.name = "Duelist"
	npc.who = "road_duelist"
	npc.display_name = "%s  %s" % [b["kanji"], b["name"]]
	npc.element = Element.from_name(str(b["element"]))
	npc.model_name = Bounties.model_path(b)
	npc.style = EnemyShinobi.RIVAL_STYLE.duplicate()
	npc.look_at_node = world.player
	npc.quiet = true
	world.archipelago.add_child(npc)
	npc.global_position = current["at"]
	_mark(npc, KANJI["duelist"], Element.color(npc.element))
	current["nodes"].append(npc)


func _start_duelist() -> void:
	var b: Dictionary = current["bounty"]
	for n: Variant in current["nodes"]:
		if is_instance_valid(n):
			(n as Node).queue_free()
	current["nodes"] = []
	world.hud.show_banner("%s bars the road" % b["name"], &"fail")
	world.busy = true
	await world.start_bounty(b, current["at"], PREFIX + "duelist")


# --- Pilgrim ---------------------------------------------------------------------------

func _set_pilgrim() -> void:
	var people := Quests.people().values().filter(func(p: Dictionary) -> bool: return str(p.get("model", "")) != "")
	var person: Dictionary = people[_rng.randi() % people.size()] if not people.is_empty() else {}
	var npc := StoryNpc.new()
	npc.name = "Pilgrim"
	npc.who = "pilgrim"
	npc.display_name = "巡  Pilgrim"
	npc.element = Element.from_name(str(person.get("element", "earth")))
	npc.style = person.get("style", {})
	npc.model_name = str(person.get("model", ""))
	npc.look_at_node = world.player
	npc.quiet = true
	world.archipelago.add_child(npc)
	npc.global_position = current["at"]
	_mark(npc, "?", UiKit.GOLD.lightened(0.2))
	current["pilgrim"] = npc
	current["nodes"].append(npc)


## What pressing Interact here would do: {kind, id, prompt} or {}.
func interact_for(pos: Vector3) -> Dictionary:
	if current.get("kind", "") != "pilgrim":
		return {}
	var npc: StoryNpc = current.get("pilgrim")
	if not is_instance_valid(npc) or npc.global_position.distance_to(pos) > float(TRIGGER["pilgrim"]):
		return {}
	return {"kind": "encounter", "id": "pilgrim", "prompt": "Talk to the pilgrim"}


func use(_id: String) -> void:
	if current.get("kind", "") != "pilgrim":
		return
	var npc: StoryNpc = current.get("pilgrim")
	var site := _unfound_near(current["at"])
	var note := ""
	if not site.is_empty():
		sites.set_state(site["id"], WorldSites.FOUND)
		note = "  ·  %s, that way (on your map)" % site["name"]
	if is_instance_valid(npc):
		npc.speak("")
	_pay("pilgrim", note)
	current["nodes"].erase(npc)
	current = {}
	if is_instance_valid(npc):
		await get_tree().create_timer(2.5, false).timeout
		if is_instance_valid(npc):
			npc.vanish()


## The nearest place you have not found from `at` (world space), or {}.
func _unfound_near(at: Vector3) -> Dictionary:
	var p := world.archipelago.to_local(at)
	var best := {}
	var best_d := INF
	for s: Dictionary in sites.plan.sites:
		if sites.is_found(s["id"]):
			continue
		var d := Vector2(p.x, p.z).distance_to(s["at"])
		if d < best_d:
			best_d = d
			best = s
	return best


# --- Cache -----------------------------------------------------------------------------

func _set_cache() -> void:
	var pickup := WorldPickup.new()
	pickup.item = "amber"
	world.archipelago.add_child(pickup)
	pickup.global_position = current["at"] + Vector3.UP * 0.6
	current["cache"] = pickup
	current["nodes"].append(pickup)


func _take_cache() -> void:
	var pickup: WorldPickup = current.get("cache")
	current["nodes"].erase(pickup)
	if is_instance_valid(pickup):
		pickup.collect()
	world.player.stats.restore()
	_pay("cache", "  ·  wounds bound, chakra full")
	current = {}


# --- Marks -----------------------------------------------------------------------------

## A sign over someone's head, seen from far off.
func _mark(node: Node3D, text: String, colour: Color) -> void:
	var tag := Label3D.new()
	tag.name = "EncounterMark"
	tag.font = UiKit.font(&"display")
	tag.font_size = 96
	tag.outline_size = 14
	tag.outline_modulate = Color(UiKit.INK, 0.9)
	tag.modulate = colour
	tag.pixel_size = 0.012
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.position.y = 3.0
	node.add_child(tag)
