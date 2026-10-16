class_name StoryDirector
extends Node
## Plays one story chapter: its beats (dialogue, tasks, fights, bosses,
## entrances) in order, with a checkpoint at every fight so defeat retries
## that fight rather than the chapter.

signal beat_started(index: int, beat: Dictionary)
## A fight or boss beat was lost; `retry()` restarts it.
signal fight_lost
signal chapter_finished(chapter: Dictionary)

## What an ally shouts when they're beaten (recorded by make_voices.py).
const ALLY_RETREAT_LINE := "I'm hurt... Finish it without me!"

var story: Story
var chapter: Dictionary = {}
var player: Player
var hud: Hud
var dialogue: DialogueBox
## Where characters, enemies and effects are added.
var stage: Node3D
var npcs: Dictionary = {}
var beat_index := -1
var running := false
## The current task: {text, goal, count, jutsu} and progress.
var task: Dictionary = {}
var task_done := 0
var fight: TrialDirector
var boss: EnemyShinobi
var adds: Array[EnemyShinobi] = []
## Characters fighting on your side: who -> EnemyShinobi (team player).
var allies: Dictionary = {}
## Practice clones kept alive while a task needs them.
var drills: Array[EnemyShinobi] = []
## Seconds left in a "survive" beat (0 when none is running).
var survive_left := 0.0

## The character being walked to safety in an escort beat.
var escortee: EnemyShinobi
## The current escort / search beat, or {} when none is running.
var _escort: Dictionary = {}
var _escort_timer := 0.0
var _escort_spawned := 0
var _escort_marker: Node3D
var _search: Dictionary = {}
var _search_found: Array[bool] = []
var _search_ambush: Array[EnemyShinobi] = []
var _search_ping := 0.0

var _checkpoint := 0
var _task_hooks_ready := false
## who -> the ally beat that brought them, so a retry can bring them back.
var _ally_beats: Dictionary = {}
var _survive: Dictionary = {}
var _survive_spawned := 0
var _survive_timer := 0.0
## The cutscene playing, if any.
var cutscene: Cutscene
## Fights whose opening film has played (by beat), so a retry goes straight in.
var _films_seen: Dictionary = {}
var _slowed := false


func setup(p: Player, h: Hud, d: DialogueBox, where: Node3D, s: Story) -> void:
	player = p
	hud = h
	dialogue = d
	stage = where
	story = s
	dialogue.line_started.connect(_on_line)
	dialogue.finished.connect(_on_dialogue_finished)
	if not player.defeated.is_connected(_on_player_defeated):
		player.defeated.connect(_on_player_defeated)
	# A task's text names its buttons: picking up the other device rewrites it.
	InputDevice.device_changed.connect(_on_device_changed)


func _on_device_changed(_device: Binding.Device) -> void:
	if running and not task.is_empty() and current_beat() == task:
		_show_task()


## `at_beat` starts partway through (screenshots): the stage is set as it
## would be just before that beat.
func start(c: Dictionary, at_beat := 0) -> void:
	chapter = c
	running = true
	beat_index = -1
	var at: Vector2 = chapter["player_at"]
	player.global_position = Vector3(at.x, 0.1, at.y)
	player.velocity = Vector3.ZERO
	_hook_tasks()
	if at_beat > 0:
		await _stage_before(at_beat)
	beat_index = at_beat - 1
	_next()


## Applies what every beat before `index` does to the stage (who is standing
## where), without playing any of them.
func _stage_before(index: int) -> void:
	for i in index:
		var b: Dictionary = chapter["beats"][i]
		match b["do"]:
			"enter":
				add_npc(b["who"], b["at"], true)
			"exit", "boss":
				remove_npc(b["who"], false)
			"escort":
				add_npc(b["who"], b["to"], true)
			"scene":
				var quick := Cutscene.new(self)
				quick.skipping = true
				add_child(quick)
				quick.play(b["steps"])
				await quick.finished
				quick.queue_free()


func current_beat() -> Dictionary:
	return chapter["beats"][beat_index] if beat_index >= 0 and beat_index < chapter["beats"].size() else {}


func _next() -> void:
	if not running:
		return
	beat_index += 1
	var beats: Array = chapter["beats"]
	if beat_index >= beats.size():
		_finish()
		return
	var b: Dictionary = beats[beat_index]
	beat_started.emit(beat_index, b)
	_score(b["do"], b)
	match b["do"]:
		"enter":
			add_npc(b["who"], b["at"])
			_next.call_deferred()
		"exit":
			remove_npc(b["who"])
			_next.call_deferred()
		"scene":
			_play_scene(b)
		"ally":
			_spawn_ally(b)
			_next.call_deferred()
		"survive":
			_checkpoint = beat_index
			_begin_play()
			_start_survive(b)
		"say":
			_begin_talk(b)
			dialogue.play(b["lines"], story)
		"task":
			_begin_play()
			task = b
			task_done = 0
			_show_task()
			hud.show_banner(Story.format(b["text"]))
			for pair: Array in b["enemies"]:
				_spawn_drill(pair)
		"fight":
			_checkpoint = beat_index
			_begin_play()
			_start_fight(b)
		"escort":
			_checkpoint = beat_index
			_begin_play()
			_start_escort(b)
		"search":
			_checkpoint = beat_index
			_begin_play()
			_start_search(b)
		"boss":
			_checkpoint = beat_index
			_begin_play()
			_start_boss(b)
		"wait":
			_begin_play()
			await get_tree().create_timer(b["seconds"], false).timeout
			_next()
		"banner":
			hud.show_banner(Story.format(b["text"]), &"cast")
			_next.call_deferred()


## Music follows the beat: a battle theme for fights (missions take turns:
## the first gets "battle", the second "battle2"...), the boss theme for
## bosses (or the one the beat names), and for talking and lessons the beat's
## own "music", else the mission's, else the island's theme. Entrances,
## banners and waits keep what's playing.
func _score(kind: String, beat := {}) -> void:
	match kind:
		"fight", "survive", "escort":
			Music.play(Music.battle_for(int(chapter.get("number", 1)) - 1))
		"boss":
			var theme := str(beat.get("music", ""))
			Music.play(StringName(theme) if theme != "" else &"boss")
		"say", "task":
			var named := str(beat.get("music", chapter.get("music", "")))
			Music.play(StringName(named) if named != "" else Music.island_theme(str(chapter.get("island", ""))))
		# Scenes set their own music (or keep what's playing).


# --- Talking ---------------------------------------------------------------------

## Puts a story character on stage at `at` ([x, z]), facing you; `quiet`
## skips the puff of smoke, `from` starts them somewhere else ([x, y, z]).
func add_npc(who: String, at: Vector2, quiet := false, from: Variant = null) -> StoryNpc:
	if npcs.has(who) and is_instance_valid(npcs[who]):
		npcs[who].queue_free()
	# An ally stepping back into the conversation stops fighting.
	var ally: EnemyShinobi = allies.get(who)
	if is_instance_valid(ally):
		ally.leave()
	allies.erase(who)
	_ally_beats.erase(who)
	var info: Dictionary = story.characters[who]
	var npc := StoryNpc.new()
	npc.name = "Npc_" + who
	npc.who = who
	npc.display_name = "%s %s" % [info["kanji"], info["name"]]
	npc.element = info["element"]
	npc.style = info["style"]
	npc.model_name = info["model"]
	npc.look_at_node = player
	npc.quiet = quiet
	npc.position = from if from is Vector3 else Vector3(at.x, 0.0, at.y)
	stage.add_child(npc)
	npcs[who] = npc
	if cutscene:
		npc.show_tag(false)
	return npc


## Takes a character off stage (in a puff of smoke unless `puff` is false),
## including an ally who's fighting.
func remove_npc(who: String, puff := true) -> void:
	var npc: StoryNpc = npcs.get(who)
	if is_instance_valid(npc):
		if puff:
			npc.vanish()
		else:
			npc.queue_free()
	npcs.erase(who)
	var ally: EnemyShinobi = allies.get(who)
	if is_instance_valid(ally):
		ally.leave()
	allies.erase(who)
	_ally_beats.erase(who)


func _play_scene(b: Dictionary) -> void:
	cutscene = Cutscene.new(self)
	add_child(cutscene)
	cutscene.play(b["steps"])
	await cutscene.finished
	if is_instance_valid(cutscene):
		cutscene.queue_free()
	cutscene = null
	_next()


func _begin_talk(b: Dictionary) -> void:
	player.input_enabled = false
	player._set_lock(null)
	hud.set_objective("")
	hud.visible = false
	var focus: StoryNpc = null
	for line: Dictionary in b["lines"]:
		if npcs.has(line["who"]):
			focus = npcs[line["who"]]
			break
	if focus:
		player._face_now(focus.global_position - player.global_position)
		player.camera_rig.begin_conversation(focus)


func _begin_play() -> void:
	player.camera_rig.end_conversation()
	player.input_enabled = true
	hud.visible = true


func _on_line(_index: int, line: Dictionary) -> void:
	var npc: StoryNpc = npcs.get(line["who"])
	if npc:
		npc.speak(line["mood"])
		# A cutscene points its own camera.
		if cutscene == null:
			player.camera_rig.begin_conversation(npc)


func _on_dialogue_finished() -> void:
	if running and current_beat().get("do") == "say":
		_next()


# --- Tasks -------------------------------------------------------------------------

func _hook_tasks() -> void:
	if _task_hooks_ready:
		return
	_task_hooks_ready = true
	player.hit_landed.connect(func(_victim: Node, kind: StringName) -> void:
		report(StringName("%s_hit" % kind)))
	player.caster.cast_succeeded.connect(func(j: JutsuDefinition) -> void:
		if j.id != &"kunai":
			report(&"cast", j.id))
	player.state_changed.connect(_on_player_state)
	player.lock_target_changed.connect(func(t: Node3D) -> void:
		if t:
			report(&"lock_on"))
	for dummy in stage.find_children("*", "TrainingDummy", true, false):
		(dummy as TrainingDummy).stats.damaged.connect(func(_a: float, _e: int, m: float) -> void:
			if m > 1.0:
				report(&"weak_hit"))
	# Breaking any enemy's weave counts for "interrupt" tasks.
	stage.child_entered_tree.connect(func(n: Node) -> void:
		if n is EnemyShinobi:
			(n as EnemyShinobi).interrupted.connect(func(by: Node) -> void:
				if by == player:
					report(&"interrupt")))


func _on_player_state(s: Player.State) -> void:
	match s:
		Player.State.GUARDING: report(&"guard")
		Player.State.DASHING: report(&"dash")
		Player.State.CHARGING: report(&"charge")


## Something task-worthy happened. Counts toward the current task if it
## matches its goal (and jutsu, when the task names one).
func report(goal: StringName, jutsu := &"") -> void:
	if task.is_empty() or current_beat() != task or StringName(task["goal"]) != goal:
		return
	if task["jutsu"] != &"" and task["jutsu"] != jutsu:
		return
	task_done += 1
	Sfx.ui(&"ui_select")
	_show_task()
	if task_done >= int(task["count"]):
		task = {}
		hud.set_objective("")
		hud.show_banner("Done!", &"info")
		for d in drills:
			if is_instance_valid(d):
				d.leave()
		drills.clear()
		await get_tree().create_timer(0.8, false).timeout
		_next()


func _show_task() -> void:
	var count := int(task["count"])
	var progress := "  (%d/%d)" % [task_done, count] if count > 1 else ""
	hud.set_objective("%s%s" % [Story.format(task["text"]), progress])


# --- Fights ------------------------------------------------------------------------

## Plays a film under the director, then gives the player and HUD back.
func _film(steps: Array, extra := {}) -> void:
	await FightCinema.play(self, steps, extra)
	if is_instance_valid(player):
		player.input_enabled = true
	if is_instance_valid(hud):
		hud.visible = true


func _start_fight(b: Dictionary) -> void:
	if not _films_seen.has(beat_index):
		_films_seen[beat_index] = true
		var waves: Array = b["waves"]
		await _film(FightCinema.ambush(str(b["text"]), "%d waves" % waves.size(), Color(1.0, 0.45, 0.3)))
		if not running:
			return
	fight = TrialDirector.new()
	fight.tier = _tier()
	fight.ground_at = _ground_at()
	fight.name = "StoryFight"
	fight.waves = b["waves"]
	fight.nonlethal = bool(b.get("nonlethal", false))
	fight.record_id = ""
	fight.announce = false
	add_child(fight)
	fight.enemies_left_changed.connect(func(left: int) -> void:
		hud.set_objective("%s  ·  %d left" % [b["text"], left] if left > 0 else b["text"]))
	fight.finished.connect(func(won: bool, _s: float, _r: bool) -> void:
		if won:
			_end_fight()
			_next())
	hud.show_banner(b["text"], &"cast")
	hud.set_objective(b["text"])
	Sfx.play(&"wave_start")
	fight.start(player)


## The terrain's height at (x, z) on this chapter's island, for placing
## fighters clear of its rocks (invalid when the stage has no island).
func _ground_at() -> Callable:
	var island: Variant = stage.get(&"island") if stage else null
	return (island as Island).height_at if island is Island else Callable()


## How far into the story this chapter's fighters are (EnemyTier): its part,
## so the world grows harder as the player's skill trees grow.
func _tier() -> int:
	return EnemyTier.of_part(int(chapter.get("part", 1)))


## A practice clone for a task; replaced if it falls before the task is done.
func _spawn_drill(pair: Array) -> void:
	var e := EnemyShinobi.new()
	e.rank = pair[0]
	e.element = pair[1]
	e.drill = true
	e.target = player
	e.position = _spawn_point(drills.size(), 2)
	e.defeated.connect(func(_x: EnemyShinobi) -> void:
		drills.erase(e)
		await get_tree().create_timer(1.0, false).timeout
		if running and not task.is_empty() and current_beat() == task:
			_spawn_drill(pair))
	drills.append(e)
	stage.add_child(e)


## A story character fighting on the player's side until they exit.
func _spawn_ally(b: Dictionary) -> void:
	var who: String = b["who"]
	var info: Dictionary = story.characters[who]
	var at: Vector2 = b["at"]
	var pos := Vector3(at.x, 0.2, at.y)
	var npc: StoryNpc = npcs.get(who)
	if npc:
		pos = npc.global_position + Vector3.UP * 0.2
		npc.vanish()
		npcs.erase(who)
	var ally := EnemyShinobi.new()
	ally.name = "Ally_" + who
	ally.team = &"player"
	ally.rank = b["rank"]
	ally.element = info["element"]
	ally.title_override = info["name"]
	ally.health_override = b["health"]
	ally.style_override = info["style"]
	ally.voice_id = who
	var chosen := CharacterModel.resolve_roster(info["model"])
	ally.model_path = chosen if chosen != "" else EnemyShinobi.pick_model(who)
	ally.position = pos
	ally.defeated.connect(func(_x: EnemyShinobi) -> void:
		allies.erase(who)
		hud.say(info["name"], ALLY_RETREAT_LINE, Element.color(info["element"]))
		Voice.speak(who, ALLY_RETREAT_LINE))
	stage.add_child(ally)
	# Allies hit softer than enemies of their rank: the player leads.
	ally.caster.power_scale *= 0.7
	allies[who] = ally
	_ally_beats[who] = b


func _start_survive(b: Dictionary) -> void:
	_survive = b
	survive_left = b["seconds"]
	_survive_spawned = 0
	_survive_timer = 0.0
	hud.show_banner(b["text"], &"cast")
	Sfx.play(&"wave_start")


func _process(delta: float) -> void:
	_tick_escort(delta)
	_tick_search(delta)
	if survive_left <= 0.0 or not running or player.is_down():
		return
	survive_left -= delta
	var alive := stage.find_children("*", "EnemyShinobi", true, false).filter(
		func(e: EnemyShinobi) -> bool: return not e.is_ally() and not e.is_defeated())
	hud.set_objective("%s  ·  %s" % [_survive["text"], Game.format_time(maxf(survive_left, 0.0))])
	_survive_timer -= delta
	if _survive_timer <= 0.0 and alive.size() < int(_survive["max_alive"]):
		_survive_timer = 1.6
		var pairs: Array = _survive["enemies"]
		var pair: Array = pairs[_survive_spawned % pairs.size()]
		var e := EnemyShinobi.new()
		e.rank = pair[0]
		e.element = pair[1]
		e.tier = _tier()
		e.nonlethal = bool(_survive.get("nonlethal", false))
		e.target = player
		e.position = _spawn_point(_survive_spawned % 3, 3)
		_survive_spawned += 1
		stage.add_child(e)
	if survive_left <= 0.0:
		survive_left = 0.0
		for e in alive:
			(e as EnemyShinobi).dismiss()
		hud.set_objective("")
		hud.show_banner("You held out!", &"cast")
		Sfx.play(&"victory", -4.0)
		_next()


## Around the player, in front of the camera, inside the arena.
func _spawn_point(index: int, count: int) -> Vector3:
	var look := player.camera_rig.flat_forward()
	var angle := (index - (count - 1) * 0.5) * deg_to_rad(40.0)
	var p := player.global_position + look.rotated(Vector3.UP, angle) * 10.0
	var flat := Vector2(p.x, p.z)
	if flat.length() > 19.0:
		flat = flat.normalized() * 19.0
	var at := Vector3(flat.x, 0.2, flat.y)
	# Not inside a rock or a prop: the clearing has them near its edge.
	return Combat.clear_spot(player.get_world_3d(), at, _ground_at()) if player.is_inside_tree() else at


func _start_boss(b: Dictionary) -> void:
	var info: Dictionary = story.characters[b["who"]]
	var npc: StoryNpc = npcs.get(b["who"])
	var at: Vector2 = b["at"]
	var pos := Vector3(at.x, 0.2, at.y)
	if npc:
		# The character steps out of the conversation and into the fight.
		pos = npc.global_position + Vector3.UP * 0.2
		npc.vanish()
		npcs.erase(b["who"])
	boss = EnemyShinobi.new()
	boss.name = "Boss_" + b["who"]
	boss.tier = _tier()
	boss.rank = b["rank"]
	boss.element = b["element"]
	boss.title_override = info["name"]
	boss.health_override = b["health"]
	boss.style_override = info["style"]
	boss.voice_id = b["who"]
	var chosen := CharacterModel.resolve_roster(info["model"])
	boss.model_path = chosen if chosen != "" else EnemyShinobi.pick_model(b["who"])
	boss.phases = b["phases"]
	boss.size = b["size"]
	boss.aura_color = b["aura"]
	boss.target = player
	boss.position = pos
	if b.get("rules", "") == "blades":
		boss.blades_only = true
		player.caster.blades_only = true
	boss.defeated.connect(_on_boss_defeated)
	boss.phase_reached.connect(_on_boss_phase.bind(b["who"]))
	stage.add_child(boss)
	if not (b["specials"] as Array).is_empty():
		var specials := BossSpecials.new()
		specials.boss = boss
		specials.specs = (b["specials"] as Array).duplicate(true)
		boss.add_child(specials)
	if not _films_seen.has(beat_index):
		# The entrance: the boss waits, unhittable, while the camera has them.
		_films_seen[beat_index] = true
		boss.hold = true
		var line := "%s  ·  %s" % [info.get("title", ""), Element.display_name(boss.element)]
		await _film(FightCinema.boss_entrance("%s  %s" % [info["kanji"], info["name"]], line, Element.color(boss.element)),
			{"boss": boss})
		if not running or not is_instance_valid(boss):
			return
		boss.hold = false
	hud.show_boss(boss, "%s %s" % [info["kanji"], info["name"]])
	hud.set_objective("Defeat %s" % info["name"] + ("  ·  blades only" if b.get("rules", "") == "blades" else ""))
	if b.get("rules", "") == "blades":
		hud.show_banner("Blades only: no jutsu", &"cast")
	Sfx.play(&"wave_start")
	if b["taunt"] != "":
		hud.say(info["name"], Story.format(b["taunt"]), Element.color(boss.element))
		Voice.speak(b["who"], b["taunt"])


func _on_boss_phase(phase: Dictionary, who: String) -> void:
	if phase["say"] != "":
		hud.say(story.speaker_name(who), Story.format(phase["say"]), Element.color(boss.element))
		Voice.speak(who, phase["say"])
	var summons: Array = phase["summon"]
	for i in summons.size():
		var e := EnemyShinobi.new()
		e.rank = summons[i][0]
		e.element = summons[i][1]
		e.tier = _tier()
		e.target = player
		var angle := TAU * float(i + 1) / float(summons.size() + 1)
		e.position = boss.global_position + Vector3(cos(angle), 0, sin(angle)) * 3.0 + Vector3.UP * 0.2
		adds.append(e)
		stage.add_child(e)


func _on_boss_defeated(fallen: EnemyShinobi) -> void:
	hud.hide_boss()
	_end_rules()
	# The boss's clones go with it.
	for a in adds:
		if is_instance_valid(a):
			a.dismiss()
	adds.clear()
	boss = null
	Sfx.play(&"victory", -4.0)
	if running and is_instance_valid(fallen) and Cutscene.active == null:
		# The last blow in slow motion, seen from beside them.
		var before := Engine.time_scale
		Engine.time_scale = FightCinema.FINISH_SPEED
		_slowed = true
		await _film(FightCinema.finish(Element.color(fallen.element)), {"boss": fallen})
		Engine.time_scale = before
		_slowed = false
	await get_tree().create_timer(1.2, false).timeout
	if running:
		_end_fight()
		_next()


func _end_fight() -> void:
	hud.set_objective("")
	if fight:
		fight.queue_free()
		fight = null


func _exit_tree() -> void:
	_end_rules()
	# Never leave the game in slow motion.
	if _slowed:
		Engine.time_scale = 1.0


func _on_player_defeated() -> void:
	if not running or beat_index != _checkpoint:
		return
	_lose_fight()


## The fight is lost (the player fell, or the one they were guarding did).
func _lose_fight() -> void:
	_end_rules()
	if fight:
		fight.running = false
	for e in stage.find_children("*", "EnemyShinobi", true, false):
		(e as EnemyShinobi).stand_down()
	hud.set_objective("")
	Music.stop()
	Voice.stop()
	fight_lost.emit()


## Clears the lost fight and starts it again with the player back on their feet.
func retry() -> void:
	for e in stage.find_children("*", "EnemyShinobi", true, false):
		if not (e as EnemyShinobi).is_ally():
			e.queue_free()
	adds.clear()
	boss = null
	survive_left = 0.0
	_clear_escort()
	_clear_search()
	hud.hide_boss()
	_end_fight()
	player.revive()
	# Allies come back to full strength (or return if they had retreated).
	for who: String in _ally_beats.keys():
		var ally: EnemyShinobi = allies.get(who)
		if is_instance_valid(ally) and not ally.is_defeated():
			ally.hunt = true
			ally.stats.restore()
		else:
			_spawn_ally(_ally_beats[who])
	var at: Vector2 = chapter["player_at"]
	player.global_position = Vector3(at.x, 0.1, at.y)
	beat_index = _checkpoint - 1
	_next()


## Gives the player their jutsu back after a duel to the old rules.
func _end_rules() -> void:
	if is_instance_valid(player) and player.caster:
		player.caster.blades_only = false


# --- Escort ------------------------------------------------------------------------

## A story character walks to the beat's goal; enemies go for them first.
## They fall, and the fight is lost; they arrive, and the beat is done.
func _start_escort(b: Dictionary) -> void:
	_clear_escort()
	_escort = b
	_escort_timer = 3.0
	_escort_spawned = 0
	var who: String = b["who"]
	var info: Dictionary = story.characters[who]
	var from: Vector2 = b["from"]
	var pos := Vector3(from.x, 0.2, from.y)
	var npc: StoryNpc = npcs.get(who)
	if npc:
		pos = npc.global_position + Vector3.UP * 0.2
		npc.vanish()
		npcs.erase(who)
	var goal: Vector2 = b["to"]
	var e := EnemyShinobi.new()
	e.name = "Escort_" + who
	e.team = &"player"
	e.rank = &"chunin"
	e.element = info["element"]
	e.title_override = info["name"]
	e.health_override = b["health"]
	e.style_override = info["style"]
	e.voice_id = who
	var chosen := CharacterModel.resolve_roster(info["model"])
	e.model_path = chosen if chosen != "" else EnemyShinobi.pick_model(who)
	e.position = pos
	e.escort_to = Vector3(goal.x, 0.2, goal.y)
	e.escort_leader = player
	e.escort_arrived.connect(_on_escort_arrived)
	e.defeated.connect(_on_escortee_down)
	stage.add_child(e)
	e.caster.power_scale *= 0.7
	escortee = e
	_escort_marker = _goal_marker(Vector3(goal.x, 0.0, goal.y), Element.color(info["element"]))
	hud.show_banner(Story.format(b["text"]), &"cast")
	Sfx.play(&"wave_start")


## A tall soft pillar of light over a place to reach.
func _goal_marker(at: Vector3, colour: Color) -> Node3D:
	var pillar := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.4
	mesh.height = 14.0
	pillar.mesh = mesh
	pillar.material_override = Vfx.glow_material(colour.lightened(0.3), 1.2, 0.22)
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(pillar)
	pillar.global_position = Vector3(at.x, 7.0, at.z)
	return pillar


func _tick_escort(delta: float) -> void:
	if _escort.is_empty() or not running or player.is_down() or not is_instance_valid(escortee):
		return
	var goal: Vector3 = escortee.escort_to
	var left := Vector2(escortee.global_position.x - goal.x, escortee.global_position.z - goal.z).length()
	hud.set_objective("%s  ·  %d m to go" % [Story.format(_escort["text"]), ceili(left)])
	if _escort["enemies"].is_empty():
		return
	var alive := stage.find_children("*", "EnemyShinobi", true, false).filter(
		func(n: EnemyShinobi) -> bool: return not n.is_ally() and not n.is_defeated())
	_escort_timer -= delta
	if _escort_timer > 0.0 or alive.size() >= int(_escort["max_alive"]):
		return
	_escort_timer = 4.0
	var pairs: Array = _escort["enemies"]
	var pair: Array = pairs[_escort_spawned % pairs.size()]
	var e := EnemyShinobi.new()
	e.rank = pair[0]
	e.element = pair[1]
	e.tier = _tier()
	e.target = escortee
	# From the side of the road the escortee is walking toward.
	var ahead := (goal - escortee.global_position)
	ahead.y = 0.0
	var angle := randf_range(-1.1, 1.1)
	var dir := (ahead.normalized() if ahead.length() > 0.5 else Vector3.FORWARD).rotated(Vector3.UP, angle)
	var flat := Vector2(escortee.global_position.x, escortee.global_position.z) + Vector2(dir.x, dir.z) * 11.0
	if flat.length() > 19.0:
		flat = flat.normalized() * 19.0
	var at := Vector3(flat.x, 0.2, flat.y)
	e.position = Combat.clear_spot(player.get_world_3d(), at, _ground_at()) if player.is_inside_tree() else at
	_escort_spawned += 1
	stage.add_child(e)


func _on_escort_arrived() -> void:
	if _escort.is_empty() or not running:
		return
	var b := _escort
	var who: String = b["who"]
	var goal: Vector3 = escortee.escort_to
	_clear_escort()
	for n in stage.find_children("*", "EnemyShinobi", true, false):
		if not (n as EnemyShinobi).is_ally():
			(n as EnemyShinobi).dismiss()
	hud.set_objective("")
	hud.show_banner("Safe!", &"cast")
	Sfx.play(&"victory", -4.0)
	# They are on stage where they ended up, ready to talk.
	add_npc(who, Vector2(goal.x, goal.z), true)
	_next()


func _on_escortee_down(_who: EnemyShinobi) -> void:
	if _escort.is_empty() or not running:
		return
	var name_of := str(story.speaker_name(_escort["who"]))
	hud.show_banner("%s has fallen" % name_of, &"fail")
	if beat_index == _checkpoint:
		_lose_fight()


func _clear_escort() -> void:
	_escort = {}
	if is_instance_valid(escortee):
		escortee.escort_to = null
		escortee.leave()
	escortee = null
	if is_instance_valid(_escort_marker):
		_escort_marker.queue_free()
	_escort_marker = null


# --- Search ------------------------------------------------------------------------

## Find every marked place by walking the ground: no pin, only "cold, warm,
## hot", a glow close by, and an ambush at each if the beat has one.
func _start_search(b: Dictionary) -> void:
	_clear_search()
	_search = b
	_search_found.clear()
	for i in (b["spots"] as Array).size():
		_search_found.append(false)
	_search_ping = 0.0
	hud.show_banner(Story.format(b["text"]), &"cast")
	Sfx.play(&"wave_start")


func _tick_search(delta: float) -> void:
	if _search.is_empty() or not running or player.is_down():
		return
	var spots: Array = _search["spots"]
	var total := spots.size()
	var found := _search_found.count(true)
	_search_ambush.assign(_search_ambush.filter(func(e: EnemyShinobi) -> bool: return is_instance_valid(e) and not e.is_defeated()))
	if not _search_ambush.is_empty():
		hud.set_objective("%s  ·  ambush: %d left" % [Story.format(_search["text"]), _search_ambush.size()])
		return
	if found >= total:
		_finish_search()
		return
	var here := Vector2(player.global_position.x, player.global_position.z)
	var nearest := INF
	var nearest_i := -1
	for i in total:
		if _search_found[i]:
			continue
		var d := here.distance_to(spots[i])
		if d < nearest:
			nearest = d
			nearest_i = i
	if nearest <= float(_search["radius"]):
		_search_found[nearest_i] = true
		found += 1
		var spot: Vector2 = spots[nearest_i]
		var colour := Color(0.95, 0.85, 0.5)
		Vfx.ground_mark(stage, Vector3(spot.x, 0.0, spot.y), colour, float(_search["radius"]) + 1.0, 2.0)
		Vfx.flash(stage, Vector3(spot.x, 1.0, spot.y), colour, 3.0, 0.3)
		Sfx.ui(&"ui_select")
		hud.show_banner("Found! (%d/%d)" % [found, total], &"cast")
		_spawn_ambush(spot)
		return
	_search_ping -= delta
	if nearest < 14.0 and _search_ping <= 0.0:
		_search_ping = 1.4
		var at: Vector2 = spots[nearest_i]
		Vfx.ground_mark(stage, Vector3(at.x, 0.0, at.y), Color(0.95, 0.85, 0.5, 0.6), float(_search["radius"]), 1.2)
	var heat := "hot" if nearest < 14.0 else ("warm" if nearest < 32.0 else "cold")
	hud.set_objective("%s  (%d/%d)  ·  %s" % [Story.format(_search["text"]), found, total, heat])


func _spawn_ambush(spot: Vector2) -> void:
	var pairs: Array = _search["enemies"]
	for i in pairs.size():
		var e := EnemyShinobi.new()
		e.rank = pairs[i][0]
		e.element = pairs[i][1]
		e.tier = _tier()
		e.target = player
		var angle := TAU * float(i) / float(maxi(pairs.size(), 1)) + 0.6
		var at := Vector3(spot.x + cos(angle) * 6.0, 0.2, spot.y + sin(angle) * 6.0)
		e.position = Combat.clear_spot(player.get_world_3d(), at, _ground_at()) if player.is_inside_tree() else at
		_search_ambush.append(e)
		stage.add_child(e)


func _finish_search() -> void:
	_search = {}
	hud.set_objective("")
	hud.show_banner("Everything found!", &"cast")
	Sfx.play(&"victory", -4.0)
	_next()


func _clear_search() -> void:
	_search = {}
	_search_found.clear()
	for e in _search_ambush:
		if is_instance_valid(e):
			e.queue_free()
	_search_ambush.clear()


func _finish() -> void:
	running = false
	for who: String in allies:
		if is_instance_valid(allies[who]):
			allies[who].leave()
	allies.clear()
	_begin_play()
	player.input_enabled = false
	hud.set_objective("")
	Music.stop(2.5)
	# A chapter's first clear is worth far more than a replay.
	SkillTrees.award("chapter_replay" if Game.chapter_done(chapter["id"]) else "chapter")
	Game.mark_chapter_done(chapter["id"])
	chapter_finished.emit(chapter)
