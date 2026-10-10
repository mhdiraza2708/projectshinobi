class_name EnemyTier
extends RefCounted
## The world gets harder as the story goes on. A fighter's tier is its story
## part minus one: part 1's fighters are exactly their rank's table, and
## every part after makes them tougher (health, poise, harder to interrupt),
## hits harder, runs faster, thinks, seals and throws sooner, dodges and
## guards more, and reaches for stronger jutsu. The player keeps growing
## through the skill trees, so what stands against them has to keep up.
## Bosses scale the same way: their written health is multiplied.

## The last tier of the story: part 6.
const STORY_MAX := 5
## The most a fighter can be: the story's last tier plus a hard difficulty and
## New Game+ on top.
const MAX := 9
## Tiers each difficulty adds on top of the story's.
const DIFFICULTY := {"normal": 0, "hard": 2, "nightmare": 4}
## Tiers each New Game+ round adds.
const PER_ROUND := 3
# Each is the gain per tier, so part 6 is five times these.
const HEALTH := 0.14
const POWER := 0.09
const SPEED := 0.03
const POISE := 0.08
const INTERRUPT := 0.06
## Thinking, sealing, throwing and running in to fight up close.
const QUICKNESS := 0.05
## Jutsu come round sooner.
const JUTSU_RATE := 0.06
## The tell before a blow or a kunai shrinks the least: it has to stay
## readable.
const TELL := 0.03
## No tell shrinks below this (seconds), however high the tier.
const MIN_TELL := 0.3
const DODGE := 0.02
const GUARD := 0.025
const MAX_DODGE := 0.7
const MAX_GUARD := 0.6
## How much stronger a jutsu they will reach for.
const JUTSU_COST := 0.15


## The tier of a story part (1 = the first), plus what the difficulty and
## New Game+ add.
static func of_part(part: int) -> int:
	return clampi(clampi(part - 1, 0, STORY_MAX) + bonus(), 0, MAX)


## The tiers added by the difficulty setting and by New Game+ rounds.
static func bonus() -> int:
	return int(DIFFICULTY.get(str(Settings.get_value(&"difficulty")), 0)) + PER_ROUND * Game.ng_plus()


## What a tier multiplies a written health by.
static func health_mult(tier: int) -> float:
	return 1.0 + HEALTH * float(clampi(tier, 0, MAX))


## Makes a rank's table (EnemyShinobi.RANKS entry, a copy) `tier` harder.
static func apply(r: Dictionary, tier: int) -> void:
	var t := float(clampi(tier, 0, MAX))
	if t <= 0.0:
		return
	var quick := 1.0 - QUICKNESS * t
	r["health"] = float(r["health"]) * (1.0 + HEALTH * t)
	r["power"] = float(r["power"]) * (1.0 + POWER * t)
	r["melee"] = float(r["melee"]) * (1.0 + POWER * t)
	r["run"] = float(r["run"]) * (1.0 + SPEED * t)
	r["poise"] = float(r["poise"]) * (1.0 + POISE * t)
	r["interrupt"] = float(r["interrupt"]) * (1.0 + INTERRUPT * t)
	r["seal_time"] = float(r["seal_time"]) * quick
	r["think"] = (r["think"] as Vector2) * quick
	r["engage"] = (r["engage"] as Vector2) * quick
	r["kunai_cd"] = (r["kunai_cd"] as Vector2) * quick
	r["jutsu_cd"] = (r["jutsu_cd"] as Vector2) * (1.0 - JUTSU_RATE * t)
	r["windup"] = _tell(float(r["windup"]), t)
	r["aim"] = _tell(float(r["aim"]), t)
	r["dodge"] = minf(MAX_DODGE, float(r["dodge"]) + DODGE * t)
	r["guard"] = minf(MAX_GUARD, float(r["guard"]) + GUARD * t)
	r["max_cost"] = float(r["max_cost"]) * (1.0 + JUTSU_COST * t)


## A tell shortened by `t` tiers, but never below MIN_TELL (or below itself
## when it started shorter).
static func _tell(base: float, t: float) -> float:
	return maxf(minf(base, MIN_TELL), base * (1.0 - TELL * t))
