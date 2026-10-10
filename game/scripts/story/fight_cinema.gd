class_name FightCinema
extends RefCounted
## Short films that open and close fights: a boss's entrance (the camera
## circles where they appear, their name arrives as a card, a low angle, then
## over your shoulder), an ambush's opening (the camera sweeps round you as
## the enemies close in) and the slow-motion finish. They are Cutscene steps,
## so holding Pause skips them, and the same code plays under a StoryDirector
## (story fights) or a CutsceneStage (the open world's).
##
## Whoever the camera frames is named in `extra`: "boss" (the fighter), "player"
## is always there.

## Off while the test suite runs (the films take seconds): the film tests turn it on.
static var enabled := true

const BOSS_ENTRANCE_SECONDS := 6.6
const AMBUSH_SECONDS := 3.0
## The game's speed during a boss's last blow.
const FINISH_SPEED := 0.3
const FINISH_SECONDS := 0.65


static func shot(kind: String, on: Variant, seconds: float, extra := {}) -> Dictionary:
	var d: Array = Story.SHOTS[kind]
	var s := {"action": "cam", "async": false, "cam": kind, "seconds": seconds, "blend": 0.0, "fov": d[3],
		"dist": d[0], "height": d[1], "side": d[2], "radius": 5.0, "degrees": 90.0, "on": on}
	s.merge(extra, true)
	return s


static func title(text: String, sub: String, seconds: float, is_async := true) -> Dictionary:
	return {"action": "title", "async": is_async, "title": text, "sub": sub, "seconds": seconds}


static func sfx(sound: String) -> Dictionary:
	return {"action": "sfx", "async": false, "sound": sound}


static func fx(kind: String, color: Color, seconds := 0.0, size := 1.0, is_async := false, extra := {}) -> Dictionary:
	var s := {"action": "fx", "async": is_async, "fx": kind, "element": Element.NONE, "color": color, "seconds": seconds, "size": size}
	s.merge(extra, true)
	return s


## A boss's entrance: `name_card` is the kanji and name, `line` what is under it.
static func boss_entrance(name_card: String, line: String, color: Color) -> Array:
	return [
		sfx("wave_start"),
		fx("shake", color, 0.5, 0.7, true),
		shot("orbit", "boss", 2.6, {"radius": 8.0, "height": 2.6, "degrees": 55.0, "fov": 55.0}),
		title(name_card, line, 2.8),
		shot("low", "boss", 2.4, {"blend": 0.5}),
		fx("flash", color.lightened(0.3), 0.25, 1.0),
		shot("over", "boss", 1.6, {"from": Story.PLAYER, "side": 1.0, "blend": 0.3}),
	]


## An ambush closing in: the camera sweeps round the player under the card.
static func ambush(text: String, line: String, color: Color) -> Array:
	return [
		sfx("wave_start"),
		title(text, line, 2.4),
		shot("orbit", Story.PLAYER, AMBUSH_SECONDS, {"radius": 5.2, "height": 1.9, "degrees": 110.0, "fov": 58.0}),
	]


## The last blow, seen from beside the fallen.
static func finish(color: Color) -> Array:
	return [
		fx("flash", color.lightened(0.4), 0.2, 1.0, true),
		shot("orbit", "boss", FINISH_SECONDS, {"radius": 4.6, "height": 1.5, "degrees": 75.0, "fov": 46.0}),
	]


## Plays `steps` under `host` (a StoryDirector or CutsceneStage) and returns
## when they end (or are skipped). `extra` names more actors: id -> Node3D.
static func play(host: Node, steps: Array, extra := {}) -> void:
	if not enabled or not bool(Settings.get_value(&"fight_cutscenes")):
		return
	var cs := Cutscene.new(host)
	cs.extra = extra
	cs.film = true
	host.add_child(cs)
	cs.play(steps)
	await cs.finished
	if is_instance_valid(cs):
		cs.queue_free()
