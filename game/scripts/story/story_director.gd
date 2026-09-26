class_name StoryDirector
extends Node
## Plays one story chapter: its beats (dialogue, tasks, fights, bosses,
## entrances) in order, with a checkpoint at every fight so defeat retries
## that fight rather than the chapter.

signal beat_started(index: int, beat: Dictionary)
## A fight or boss beat was lost; `retry()` restarts it.
signal fight_lost
signal chapter_finished(chapter: Dictionary)

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

var _checkpoint := 0
var _task_hooks_ready := false
## who -> the ally beat that brought them, so a retry can bring them back.
var _ally_beats: Dictionary = {}
var _survive: Dictionary = {}
var _survive_spawned := 0
var _survive_timer := 0.0


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


func start(c: Dictionary) -> void:
	chapter = c
	running = true
	beat_index = -1
	var at: Vector2 = chapter["player_at"]
	player.global_position = Vector3(at.x, 0.1, at.y)
	player.velocity = Vector3.ZERO
	_hook_tasks()
	_next()


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
	match b["do"]:
		"enter":
			_enter_npc(b)
			_next.call_deferred()
		"exit":
			var npc: StoryNpc = npcs.get(b["who"])
			if npc:
				npc.vanish()
			npcs.erase(b["who"])
			var ally: EnemyShinobi = allies.get(b["who"])
			if is_instance_valid(ally):
				ally.leave()
			allies.erase(b["who"])
			_ally_beats.erase(b["who"])
			_next.call_deferred()
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


# --- Talking ---------------------------------------------------------------------

func _enter_npc(b: Dictionary) -> void:
	var who: String = b["who"]
	if npcs.has(who):
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
	var at: Vector2 = b["at"]
	npc.position = Vector3(at.x, 0.0, at.y)
	stage.add_child(npc)
	npcs[who] = npc


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

func _start_fight(b: Dictionary) -> void:
	fight = TrialDirector.new()
	fight.name = "StoryFight"
	fight.waves = b["waves"]
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
	var chosen := CharacterModel.resolve_roster(info["model"])
	ally.model_path = chosen if chosen != "" else EnemyShinobi.pick_model(who)
	ally.position = pos
	ally.defeated.connect(func(_x: EnemyShinobi) -> void:
		allies.erase(who)
		hud.say(info["name"], "I'm hurt... Finish it without me!", Element.color(info["element"])))
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
	return Vector3(flat.x, 0.2, flat.y)


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
	boss.rank = b["rank"]
	boss.element = b["element"]
	boss.title_override = info["name"]
	boss.health_override = b["health"]
	boss.style_override = info["style"]
	var chosen := CharacterModel.resolve_roster(info["model"])
	boss.model_path = chosen if chosen != "" else EnemyShinobi.pick_model(b["who"])
	boss.phases = b["phases"]
	boss.size = b["size"]
	boss.aura_color = b["aura"]
	boss.target = player
	boss.position = pos
	boss.defeated.connect(_on_boss_defeated)
	boss.phase_reached.connect(_on_boss_phase.bind(info["name"]))
	stage.add_child(boss)
	hud.show_boss(boss, "%s %s" % [info["kanji"], info["name"]])
	hud.set_objective("Defeat %s" % info["name"])
	Sfx.play(&"wave_start")
	if b["taunt"] != "":
		hud.say(info["name"], Story.format(b["taunt"]), Element.color(boss.element))


func _on_boss_phase(phase: Dictionary, speaker: String) -> void:
	if phase["say"] != "":
		hud.say(speaker, Story.format(phase["say"]), Element.color(boss.element))
	var summons: Array = phase["summon"]
	for i in summons.size():
		var e := EnemyShinobi.new()
		e.rank = summons[i][0]
		e.element = summons[i][1]
		e.target = player
		var angle := TAU * float(i + 1) / float(summons.size() + 1)
		e.position = boss.global_position + Vector3(cos(angle), 0, sin(angle)) * 3.0 + Vector3.UP * 0.2
		adds.append(e)
		stage.add_child(e)


func _on_boss_defeated(_e: EnemyShinobi) -> void:
	hud.hide_boss()
	# The boss's clones go with it.
	for a in adds:
		if is_instance_valid(a):
			a.dismiss()
	adds.clear()
	boss = null
	Sfx.play(&"victory", -4.0)
	await get_tree().create_timer(1.2, false).timeout
	if running:
		_end_fight()
		_next()


func _end_fight() -> void:
	hud.set_objective("")
	if fight:
		fight.queue_free()
		fight = null


func _on_player_defeated() -> void:
	if not running or beat_index != _checkpoint:
		return
	if fight:
		fight.running = false
	for e in stage.find_children("*", "EnemyShinobi", true, false):
		(e as EnemyShinobi).stand_down()
	hud.set_objective("")
	fight_lost.emit()


## Clears the lost fight and starts it again with the player back on their feet.
func retry() -> void:
	for e in stage.find_children("*", "EnemyShinobi", true, false):
		if not (e as EnemyShinobi).is_ally():
			e.queue_free()
	adds.clear()
	boss = null
	survive_left = 0.0
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


func _finish() -> void:
	running = false
	for who: String in allies:
		if is_instance_valid(allies[who]):
			allies[who].leave()
	allies.clear()
	_begin_play()
	player.input_enabled = false
	hud.set_objective("")
	Game.mark_chapter_done(chapter["id"])
	chapter_finished.emit(chapter)
