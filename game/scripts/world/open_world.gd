class_name OpenWorld
extends Node
## Free roam across the archipelago (Archipelago): you run between islands
## over the sea, the story waits at a pillar of light where the next chapter
## happens, and people around the islands ask for help (Quests). Talk with
## Interact (T / X beside someone). Your place in the world is saved with
## the slot.
##
## Side quests play out right here: gather quests scatter what you're
## looking for around the island, defeat quests start when you reach the
## spot, a duel turns the quest giver into your opponent, and a delivery is
## done when you reach whoever it's for. A chapter is played where its
## pillar stands (the game scene's start_story_in_world).

signal chapter_requested(chapter_id: String)

## Where a new game stands: Emberwood, just outside the Academy yard.
const START := Vector2(0.0, 14.0)
## Within this distance you can talk to someone (or begin a chapter).
const TALK_RANGE := 3.2
const BEACON_RANGE := 5.0
## A defeat quest's fight starts when you come this close to its spot.
const FIGHT_TRIGGER := 22.0
const PICKUP_RANGE := 1.6
## How often your place is saved (seconds).
const SAVE_EVERY := 3.0
## A whole day in free roam, in real seconds, and where each part of it
## starts (fractions of the day): a short dawn and dusk, a long day, a night.
const DAY_LENGTH := 1440.0
const PHASES := [[0.0, "dawn"], [0.1, "day"], [0.55, "dusk"], [0.66, "night"]]
## A new game starts mid-morning.
const START_CLOCK := 0.2
## Seconds a change of the time of day takes to ease in.
const DAWNING := 10.0
## Each island's mark on the location card.
const ISLAND_KANJI := {
	"emberwood": "燠", "ashen_pass": "灰", "autumn_wood": "楓",
	"old_dam": "堰", "frozen_road": "凍", "five_winds": "風",
}
## Music for the open sea and for the night (an island's own is
## Music.island_theme). An island's music reaches this much further out than
## its name card, so it doesn't flicker at the shore.
const SEA_TRACK := &"sea"
const NIGHT_TRACK := &"night"
const SHORE_HOLD := 14.0

var player: Player
var hud: Hud
var story: Story
var archipelago: Archipelago
## "islands" (the sea of islands) or "continent" (ContinentWorld); chosen in
## _ready from the setting unless the owner has set it first.
var layout := ""
var tracker: QuestTracker
var dialogue: DialogueBox
## A chapter or quest fight in progress (free roam pauses its quests).
var busy := false
## Nothing is checked (islands, water, pickups) until start() has put you
## where you were: until then you stand at the origin, on Emberwood.
var placed := false

var _givers: Dictionary = {}       # who -> StoryNpc (one figure per person)
var _pickups: Dictionary = {}      # quest id -> Array[WorldPickup]
var _beacon: QuestBeacon
var _fight: TrialDirector
var _fight_quest := ""
var _duelist: EnemyShinobi
var _interact: Dictionary = {}     # {kind, id, node}
var _island := ""
var _music_island := ""
var _fights := 0                   # quest fights begun (they take turns at the battle themes)
var _save_left := SAVE_EVERY
var _ripple_left := 0.0
## Seconds into the day (saved with the slot).
var clock := START_CLOCK * DAY_LENGTH


func setup(p: Player, h: Hud, s: Story) -> void:
	player = p
	hud = h
	story = s
	story.add_cast(Quests.people())
	clock = float(Game.record("world", "clock", START_CLOCK * DAY_LENGTH))


## The part of the day it is at `at` seconds (default: now).
func phase(at := -1.0) -> String:
	var k := fposmod((clock if at < 0.0 else at) / DAY_LENGTH, 1.0)
	var out: String = PHASES[0][1]
	for p: Array in PHASES:
		if k >= float(p[0]):
			out = p[1]
	return out


## The music for a place at a time of day: night beats everything, then the
## open sea, then the island's own theme. `island` is "" out at sea.
static func track_for(island: String, day_phase: String) -> StringName:
	if day_phase == "night":
		return NIGHT_TRACK
	return SEA_TRACK if island == "" else Music.island_theme(island)


## Crossfades to the music for where you stand and what time it is. It waits
## while a fight or chapter has the stage (they choose their own music).
func update_music() -> void:
	if busy or not placed or player == null or get_parent().get(&"mode") != Game.Mode.WORLD:
		return
	var reach := 18.0 + (SHORE_HOLD if _music_island != "" else 0.0)
	_music_island = archipelago.island_near(player.global_position, reach)
	Music.play(track_for(_music_island, phase()))


func _process(delta: float) -> void:
	# The day turns while you roam (not during a chapter or a conversation).
	if busy or get_parent().get(&"mode") != Game.Mode.WORLD or get_tree().paused:
		return
	var before := phase()
	clock = fposmod(clock + delta, DAY_LENGTH)
	var now := phase()
	if now != before and get_parent().has_method(&"transition_time"):
		get_parent().transition_time(now, DAWNING)


## Whether the world is the continent: the "World" setting, or --world=continent
## (or --world=islands) on the command line.
static func uses_continent() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--world="):
			return arg.trim_prefix("--world=") == "continent"
	return str(Settings.get_value(&"world_layout")) == "continent"


static var _land: ContinentLand


## Where a region stands in the chosen layout's space, before the world is
## built (demos set a saved position with it).
static func region_offset(id: String) -> Vector3:
	if not uses_continent():
		return Archipelago.offset_of(id)
	if _land == null:
		_land = ContinentLand.new()
	var c := _land.region_center(id)
	return Vector3(c.x, _land.pad_height(id), c.y)


func _ready() -> void:
	name = "OpenWorld"
	if layout == "":
		layout = "continent" if uses_continent() else "islands"
	archipelago = ContinentWorld.new() if layout == "continent" else Archipelago.new()
	archipelago.player = player
	get_parent().add_child.call_deferred(archipelago)
	tracker = QuestTracker.new()
	tracker.world = self
	add_child(tracker)
	dialogue = DialogueBox.new()
	add_child(dialogue)
	player.defeated.connect(_on_player_defeated)


## Builds the world around where you last stood and puts you there.
## `instant` builds every island at once (tests, screenshots).
func start(instant := false) -> void:
	if not archipelago.is_inside_tree():
		await get_tree().process_frame
	var at := saved_position()
	if instant:
		archipelago.build_now(at)
	else:
		await archipelago.build(at)
	await archipelago.ground_ready()
	if not is_inside_tree():
		return
	var ground := archipelago.to_global(at)
	ground.y = Combat.ground_height(player.get_world_3d(), ground + Vector3.UP * 30.0, ground.y)
	player.global_position = ground + Vector3.UP * 0.2
	player.velocity = Vector3.ZERO
	placed = true
	refresh()


## Where the slot last left you in this layout's space (the home clearing in
## a new game). Each layout keeps its own: a place on the islands means
## nothing on the continent.
func saved_position() -> Vector3:
	var saved: Variant = Game.record("world", position_key(), null)
	if saved is Vector3:
		return saved
	return archipelago.offset("emberwood") + Vector3(START.x, 0.0, START.y)


func position_key() -> String:
	return "position_continent" if layout == "continent" else "position"


## Back where you last stood safely (fell off the world).
func respawn() -> void:
	var at := saved_position()
	player.global_position = archipelago.to_global(at) + Vector3.UP * 0.5
	player.velocity = Vector3.ZERO


## Rebuilds the people, pickups and the story pillar from the quests' state.
func refresh() -> void:
	if archipelago.ready_islands < Archipelago.LAYOUT.size():
		return
	_place_people()
	for q in Quests.all():
		_place_pickups(q, Quests.status(q["id"]))
	_place_beacon()
	tracker.refresh()


## Quest figures step aside while a story mission plays (the story has its
## own Tobi, Chiyo or Renji on stage).
func set_people_visible(show: bool) -> void:
	for npc in _givers.values():
		if is_instance_valid(npc):
			(npc as Node3D).visible = show


## Who should be standing where: one figure per person, marked "!" when
## they have something for you.
func wanted_people() -> Dictionary:
	var out := {}
	for q in Quests.all():
		var st := Quests.status(q["id"])
		var who := str(q["giver"])
		var place := {"island": str(q["island"]), "at": q["giver_at"], "marker": ""}
		match st:
			Quests.AVAILABLE:
				place["marker"] = "!"
			Quests.ACTIVE:
				if q["type"] == "deliver":
					who = str(q["to"])
					place = {"island": str(q["to_island"]), "at": q["to_at"], "marker": "!"}
				elif q["type"] == "duel" and is_instance_valid(_duelist):
					continue
			_:
				continue
		if out.has(who) and out[who]["marker"] == "!":
			continue
		out[who] = place
	return out


func _place_people() -> void:
	var wanted := wanted_people()
	for who: String in _givers.keys():
		if not wanted.has(who) or not is_instance_valid(_givers[who]):
			if is_instance_valid(_givers[who]):
				_givers[who].queue_free()
			_givers.erase(who)
	for who: String in wanted:
		var place: Dictionary = wanted[who]
		var npc: StoryNpc = _givers.get(who)
		var spot := archipelago.on_island(place["island"], Vector2(place["at"][0], place["at"][1]))
		if npc == null:
			npc = _spawn_person(who, place["island"], Vector2(place["at"][0], place["at"][1]))
			_givers[who] = npc
		elif npc.global_position.distance_to(spot) > 1.0:
			npc.global_position = spot
		_mark(npc, place["marker"])


func _spawn_person(who: String, island: String, at: Vector2) -> StoryNpc:
	var info: Dictionary = story.characters.get(who, {})
	var npc := StoryNpc.new()
	npc.name = "Person_" + who
	npc.who = who
	npc.display_name = "%s %s" % [info.get("kanji", ""), info.get("name", who)]
	npc.element = info.get("element", Element.NONE)
	npc.style = info.get("style", {})
	npc.model_name = str(info.get("model", ""))
	npc.look_at_node = player
	npc.quiet = true
	archipelago.add_child(npc)
	npc.global_position = archipelago.on_island(island, at)
	return npc


## A quest mark over someone's head ("!" when they have something for you).
func _mark(npc: StoryNpc, marker: String) -> void:
	var tag: Label3D = npc.get_node_or_null(^"QuestMark")
	if marker == "":
		if tag:
			tag.queue_free()
		return
	if tag == null:
		tag = Label3D.new()
		tag.name = "QuestMark"
		tag.font = UiKit.font(&"display")
		tag.font_size = 96
		tag.outline_size = 14
		tag.outline_modulate = Color(UiKit.INK, 0.9)
		tag.modulate = UiKit.GOLD.lightened(0.2)
		tag.pixel_size = 0.01
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.position.y = 2.9
		npc.add_child(tag)
	tag.text = marker


func _place_pickups(q: Dictionary, st: String) -> void:
	var id: String = q["id"]
	var have: Array = _pickups.get(id, [])
	if q["type"] != "gather" or st != Quests.ACTIVE:
		for p in have:
			if is_instance_valid(p):
				p.queue_free()
		_pickups.erase(id)
		return
	if not have.is_empty():
		return
	var spots := gather_spots(q)
	var list: Array = []
	for i in range(Quests.progress(id), spots.size()):
		var p := WorldPickup.new()
		p.item = str(q["item"])
		p.quest = id
		archipelago.add_child(p)
		p.global_position = archipelago.on_island(str(q["island"]), spots[i]) + Vector3.UP * 0.6
		list.append(p)
	_pickups[id] = list


## Where a gather quest's items lie: the same places every time, on dry,
## walkable ground away from the clearing.
func gather_spots(q: Dictionary) -> Array[Vector2]:
	var island: Island = archipelago.islands.get(str(q["island"]))
	var out: Array[Vector2] = []
	if island == null:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(q["id"]))
	var coast := float(island.preset["coast"])
	var tries := 400
	while out.size() < int(q["count"]) and tries > 0:
		tries -= 1
		var r := rng.randf_range(float(island.preset["clearing"]) + 4.0, coast - 14.0)
		var a := rng.randf() * TAU
		var p := Vector2(cos(a) * r, sin(a) * r)
		if island.height_at(p.x, p.y) < island.water_level + 0.8 or island._slope(p.x, p.y) > 0.35:
			continue
		if out.any(func(o: Vector2) -> bool: return o.distance_to(p) < 12.0):
			continue
		out.append(p)
	return out


## The pillar of light where the next chapter begins.
func _place_beacon() -> void:
	var c := Quests.main_chapter(story)
	if c.is_empty():
		if is_instance_valid(_beacon):
			_beacon.queue_free()
		return
	if not is_instance_valid(_beacon):
		_beacon = QuestBeacon.new()
		archipelago.add_child(_beacon)
	if _beacon.chapter_id != c["id"]:
		# A new mission: it waits until you've stepped away from where the
		# last one ended, so the story never starts again under your feet.
		_beacon.armed = _beacon.chapter_id == ""
	_beacon.chapter_id = c["id"]
	_beacon.label = mission_title(c)
	var at: Vector2 = c["player_at"]
	_beacon.global_position = archipelago.on_island(str(c["island"]), at)


## "第二章 The Ashen Trail" for a chapter of the story.
static func _chapter_name(part: Dictionary) -> String:
	return "第%s章 %s" % [Story.numeral(int(part.get("number", 1))), part.get("title", "")]


## "Mission 2/3: Ash on the Wind".
func mission_title(c: Dictionary) -> String:
	return "Mission %d/%d: %s" % [story.mission_index(c), story.missions_in(c["part"]).size(), c["title"]]


# --- Where things are (for the tracker) -----------------------------------------

## What the tracked quest wants: {title, kanji, text, at (world) or null}.
func objective() -> Dictionary:
	var id := Quests.tracked()
	if id == Quests.MAIN:
		var c := Quests.main_chapter(story)
		if c.is_empty():
			return {"title": "The story is told", "kanji": "完", "text": "Every chapter is cleared. Explore, and help who you can.", "at": null}
		var part := story.part(c["part"])
		var where := Island.display_name(str(c["island"]))
		var text := str(c["objective"]) if c["objective"] != "" else "Go to the pillar of light on %s" % where
		return {"title": "%s  ·  %s" % [_chapter_name(part), mission_title(c)], "kanji": str(part.get("kanji", "章")),
			"text": text, "at": _beacon.global_position if is_instance_valid(_beacon) else null}
	var q := Quests.quest(id)
	var text := str(q["objective"])
	var counter := Quests.counter(id)
	if counter != "":
		text += "  (%s)" % counter
	var at: Variant = null
	match str(q["type"]):
		"gather":
			at = _nearest_pickup(id)
		"defeat", "duel":
			at = archipelago.on_island(str(q["island"]), Vector2(q["at"][0], q["at"][1]))
		"deliver":
			at = archipelago.on_island(str(q["to_island"]), Vector2(q["to_at"][0], q["to_at"][1]))
	return {"title": str(q["name"]), "kanji": str(q["kanji"]), "text": text, "at": at}


func _nearest_pickup(id: String) -> Variant:
	var best: Variant = null
	var best_d := INF
	for p in _pickups.get(id, []):
		if is_instance_valid(p):
			var d := (p as Node3D).global_position.distance_to(player.global_position)
			if d < best_d:
				best_d = d
				best = (p as Node3D).global_position
	return best


# --- Loop ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not placed:
		return
	if player == null or busy and _fight == null and not is_instance_valid(_duelist):
		_interact = {}
		tracker.set_prompt("")
		if player:
			player.can_interact = false
		return
	_water_run(delta)
	_check_pickups()
	_check_fights()
	_find_interact()
	if not _interact.is_empty() and player.input_enabled and Input.is_action_just_pressed(&"interact"):
		_use_interact()
	_check_island()
	update_music()
	_save_left -= delta
	if _save_left <= 0.0:
		_save_left = SAVE_EVERY
		save_position()


## Your place in the world, kept with the slot.
func save_position() -> void:
	if player and archipelago.is_inside_tree():
		Game.set_record("world", position_key(), archipelago.to_local(player.global_position))
	Game.set_record("world", "clock", clock)


## Running on the sea: a faster sprint, and ripples where your feet land.
func _water_run(delta: float) -> void:
	var on_water := archipelago.on_water(player)
	player.surface_speed = Archipelago.WATER_SPRINT if on_water and player.is_sprinting() else 1.0
	if not on_water or Vector2(player.velocity.x, player.velocity.z).length() < 1.0:
		return
	_ripple_left -= delta
	if _ripple_left <= 0.0:
		_ripple_left = 0.12 if player.is_sprinting() else 0.22
		Vfx.shockwave(archipelago, player.global_position + Vector3.UP * 0.05, Color(0.85, 0.95, 1.0, 0.7), 0.9, 0.5)


func _check_pickups() -> void:
	for id: String in _pickups.keys():
		var list: Array = _pickups[id]
		for p in list.duplicate():
			if not is_instance_valid(p):
				list.erase(p)
				continue
			if (p as Node3D).global_position.distance_to(player.global_position + Vector3.UP * 0.6) < PICKUP_RANGE:
				list.erase(p)
				(p as WorldPickup).collect()
				var q := Quests.quest(id)
				Quests.set_progress(id, Quests.progress(id) + 1)
				var left := int(q["count"]) - Quests.progress(id)
				if left <= 0:
					_finish_quest(id, q.get("outro", []))
				else:
					hud.show_banner("%s  %d / %d" % [Quests.ITEMS[q["item"]]["name"].capitalize(), Quests.progress(id), int(q["count"])], &"info")
					tracker.refresh()


func _check_fights() -> void:
	if _fight or is_instance_valid(_duelist):
		return
	for q in Quests.with_status(Quests.ACTIVE):
		if not q["type"] in ["defeat", "duel"]:
			continue
		var spot := archipelago.on_island(str(q["island"]), Vector2(q["at"][0], q["at"][1]))
		if spot.distance_to(player.global_position) < FIGHT_TRIGGER:
			_start_fight(q, spot)
			return


func _find_interact() -> void:
	_interact = {}
	var prompt := ""
	var at_beacon := is_instance_valid(_beacon) and _beacon.global_position.distance_to(player.global_position) < BEACON_RANGE
	if is_instance_valid(_beacon) and not at_beacon:
		_beacon.armed = true
	if at_beacon and _beacon.armed and player.input_enabled and _fight == null:
		# Arriving is enough: the story picks up where you are.
		_beacon.armed = false
		tracker.set_prompt("")
		chapter_requested.emit(_beacon.chapter_id)
		return
	if at_beacon:
		_interact = {"kind": "chapter", "id": _beacon.chapter_id}
		prompt = "Begin  %s" % _beacon.label
	else:
		var best := TALK_RANGE
		for who: String in _givers:
			var npc: StoryNpc = _givers[who]
			if not is_instance_valid(npc):
				continue
			var d := npc.global_position.distance_to(player.global_position)
			if d < best:
				best = d
				_interact = {"kind": "talk", "id": who, "node": npc}
				prompt = "Talk to %s" % str(story.characters.get(who, {}).get("name", who))
	tracker.set_prompt(prompt)
	player.can_interact = not _interact.is_empty()


func _use_interact() -> void:
	var kind: String = _interact["kind"]
	var id: String = _interact["id"]
	_interact = {}
	tracker.set_prompt("")
	if kind == "chapter":
		chapter_requested.emit(id)
		return
	await talk_to(id)


## Talking to someone does what matters most to them: a letter you carry for
## them, then a request they have, then a reminder of one you took.
func talk_to(who: String) -> void:
	for q in Quests.with_status(Quests.ACTIVE):
		if q["type"] == "deliver" and str(q["to"]) == who:
			await _talk(q.get("handover", []))
			_finish_quest(q["id"], [])
			return
	for q in Quests.with_status(Quests.AVAILABLE):
		if str(q["giver"]) == who:
			await _talk(q["intro"])
			if Quests.accept(q["id"]):
				hud.show_banner("Quest:  %s" % q["name"], &"info")
				Sfx.play(&"quest_accept")
				refresh()
				if q["type"] == "duel":
					_start_fight(q, archipelago.on_island(str(q["island"]), Vector2(q["at"][0], q["at"][1])))
			return
	for q in Quests.with_status(Quests.ACTIVE):
		if str(q["giver"]) == who:
			var counter := Quests.counter(q["id"])
			await _talk([{"who": who, "text": str(q["objective"]) + ("  (%s)" % counter if counter != "" else "") + "."}])
			return


## Plays lines in the dialogue box; the player stands still meanwhile.
func _talk(lines: Array) -> void:
	if lines.is_empty():
		return
	player.input_enabled = false
	busy = true
	dialogue.play(lines, story)
	await dialogue.finished
	if is_instance_valid(player):
		player.input_enabled = true
	busy = false


func _finish_quest(id: String, outro: Array) -> void:
	var q := Quests.quest(id)
	if not Quests.complete(id):
		return
	hud.show_banner("Quest complete:  %s   +%d XP" % [q["name"], int(q.get("xp", 0))], &"cast")
	Sfx.play(&"quest_done")
	refresh()
	await _talk(outro)


# --- Quest fights ----------------------------------------------------------------

func _start_fight(q: Dictionary, spot: Vector3) -> void:
	_fight_quest = q["id"]
	busy = true
	var battle := Music.battle_for(_fights)
	_fights += 1
	if q["type"] == "duel":
		var npc: StoryNpc = _givers.get(str(q["giver"]))
		var foe: Dictionary = q["foe"]
		var info: Dictionary = story.characters.get(str(q["giver"]), {})
		var e := EnemyShinobi.new()
		e.rank = StringName(str(foe.get("rank", "jonin")))
		e.element = Element.from_name(str(foe.get("element", "fire")))
		e.title_override = str(info.get("name", "Duelist"))
		e.kanji_override = str(info.get("kanji", ""))
		e.health_override = float(foe.get("health", 0.0))
		e.tier = _story_tier()
		e.style_override = info.get("style", {})
		e.model_path = CharacterModel.resolve_roster(str(info.get("model", "")))
		e.target = player
		archipelago.add_child(e)
		e.global_position = npc.global_position if is_instance_valid(npc) else spot + Vector3.UP * 0.2
		if is_instance_valid(npc):
			npc.queue_free()
		_givers.erase(str(q["giver"]))
		_duelist = e
		hud.show_boss(e, "%s  %s" % [e.kanji_override, e.title_override])
		hud.show_banner("Duel:  %s" % e.title_override, &"cast")
		Music.play(battle)
		e.defeated.connect(func(_x: EnemyShinobi) -> void:
			hud.hide_boss()
			_end_fight(true))
		return
	_fight = TrialDirector.new()
	_fight.tier = _story_tier()
	_fight.name = "QuestFight"
	_fight.record_id = ""
	_fight.announce = true
	_fight.center = spot
	_fight.arena_radius = 16.0
	var waves: Array = []
	for w: Array in q["waves"]:
		var ranks: Array = []
		var elements: Array = []
		for pair: Array in w:
			ranks.append(StringName(str(pair[0])))
			elements.append(Element.from_name(str(pair[1])))
		waves.append({"element": elements[0], "enemies": ranks, "elements": elements})
	_fight.waves = waves
	archipelago.add_child(_fight)
	_fight.wave_started.connect(func(index: int, total: int, _e: int) -> void:
		Quests.set_progress(_fight_quest, index)
		hud.show_banner("%s  ·  wave %d / %d" % [q["name"], index + 1, total], &"cast")
		tracker.refresh())
	_fight.finished.connect(func(won: bool, _s: float, _r: bool) -> void: _end_fight(won))
	Music.play(battle)
	_fight.start(player)


## How hard the world's fighters are: the furthest story part you have
## cleared a chapter of (EnemyTier), so side fights keep pace with the saga.
func _story_tier() -> int:
	var part := 1
	if story:
		for c: Dictionary in story.chapters:
			if Game.chapter_done(c["id"]):
				part = maxi(part, int(c["part"]))
	return EnemyTier.of_part(part)


func _end_fight(won: bool) -> void:
	var id := _fight_quest
	if is_instance_valid(_fight):
		_fight.queue_free()
	_fight = null
	_duelist = null
	_fight_quest = ""
	busy = false
	update_music()
	if won:
		_finish_quest(id, Quests.quest(id).get("outro", []))
	else:
		refresh()


## Beaten in the open: you come to where you fell, and the fight resets.
func _on_player_defeated() -> void:
	if get_parent().get(&"mode") != Game.Mode.WORLD:
		return
	if is_instance_valid(_fight):
		_fight.running = false
		for e in _fight.alive:
			if is_instance_valid(e):
				e.leave()
	if is_instance_valid(_duelist):
		_duelist.leave()
		hud.hide_boss()
	var was_fight := _fight_quest != ""
	_fight = null
	_duelist = null
	_fight_quest = ""
	busy = false
	await get_tree().create_timer(2.0, false).timeout
	if not is_instance_valid(player):
		return
	player.revive()
	hud.show_banner("You come to. %s" % ("The fight waits for you." if was_fight else ""), &"fail")
	update_music()
	refresh()


# --- Arriving somewhere -----------------------------------------------------------

func _check_island() -> void:
	var here := archipelago.island_near(player.global_position)
	if here == _island:
		return
	_island = here
	if here != "":
		var first := not discovered(here)
		discover(here)
		tracker.show_location(Island.display_name(here), ISLAND_KANJI.get(here, ""))
		if first and here != "emberwood":
			hud.show_banner("Discovered %s: you can travel here from the map" % Island.display_name(here), &"info")


## The island you're over or beside now ("" out at sea).
func current_island() -> String:
	return _island


## Islands you've set foot on (Emberwood, home, always).
func discovered(id: String) -> bool:
	return id == "emberwood" or (Game.record("world", "discovered", []) as Array).has(id)


func discover(id: String) -> void:
	var list: Array = (Game.record("world", "discovered", []) as Array).duplicate()
	if not list.has(id):
		list.append(id)
		Game.set_record("world", "discovered", list)


## Where travel to an island sets you down: by its clearing.
const TRAVEL_POINT := Vector2(0.0, 12.0)


## Whether travel is possible right now (not mid-fight or mid-chapter).
func can_travel() -> bool:
	return not busy and _fight == null and not is_instance_valid(_duelist) \
		and get_parent().get(&"mode") == Game.Mode.WORLD


## Travels to an island you've been to: the seal flares, a white flash, and
## you stand by its clearing.
func fast_travel(id: String) -> bool:
	if not discovered(id) or not can_travel():
		return false
	busy = true
	player.input_enabled = false
	var scene := get_parent()
	if scene.has_method(&"_teleport_out"):
		await scene._teleport_out()
	if not is_inside_tree():
		return false
	var at := archipelago.on_island(id, TRAVEL_POINT)
	player.global_position = at + Vector3.UP * 0.3
	player.velocity = Vector3.ZERO
	save_position()
	if scene.has_method(&"_teleport_in"):
		await scene._teleport_in()
	if is_instance_valid(player):
		player.input_enabled = true
	busy = false
	return true
