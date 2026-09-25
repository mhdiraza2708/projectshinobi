class_name Stats
extends Node
## Health, chakra, and timed modifiers for anything that can fight.

signal health_changed(current: float, maximum: float)
signal chakra_changed(current: float, maximum: float)
## `multiplier` is the elemental multiplier that was applied (1.0 = neutral).
signal damaged(amount: float, element: int, multiplier: float)
signal healed(amount: float)
signal died
signal modifier_changed(stat: StringName, magnitude: float, time_left: float)

@export var max_health := 100.0
@export var max_chakra := 100.0
## Passive regeneration per second.
@export var chakra_regen := 3.0
## Regeneration per second while charging.
@export var charge_regen := 35.0
## The target's own nature, used for elemental matchups when it is hit.
@export var affinity := Element.NONE

var health: float
var chakra: float
var is_charging := false
var is_invulnerable := false
## Damage multiplier from guarding (1.0 = not guarding).
var guard_multiplier := 1.0

# stat -> {"magnitude": float, "time": float}
var _modifiers: Dictionary = {}


func _ready() -> void:
	health = max_health
	chakra = max_chakra


func _process(delta: float) -> void:
	var regen := charge_regen if is_charging else chakra_regen
	if chakra < max_chakra and regen > 0.0:
		chakra = minf(max_chakra, chakra + regen * delta)
		chakra_changed.emit(chakra, max_chakra)
	for stat: StringName in _modifiers.keys():
		var m: Dictionary = _modifiers[stat]
		m["time"] -= delta
		if m["time"] <= 0.0:
			_modifiers.erase(stat)
			modifier_changed.emit(stat, 0.0, 0.0)


func is_dead() -> bool:
	return health <= 0.0


func spend_chakra(amount: float) -> bool:
	if amount > chakra:
		return false
	chakra -= amount
	chakra_changed.emit(chakra, max_chakra)
	return true


## Applies a hit and returns the damage actually dealt.
func take_damage(amount: float, element: int = Element.NONE) -> float:
	if is_dead() or is_invulnerable or amount <= 0.0:
		return 0.0
	var mult := Element.multiplier(element, affinity)
	var dealt := amount * mult * guard_multiplier * (1.0 - modifier(&"damage_reduction"))
	health = maxf(0.0, health - dealt)
	damaged.emit(dealt, element, mult)
	health_changed.emit(health, max_health)
	if is_dead():
		died.emit()
	return dealt


func heal(amount: float) -> void:
	if is_dead() or amount <= 0.0:
		return
	var before := health
	health = minf(max_health, health + amount)
	healed.emit(health - before)
	health_changed.emit(health, max_health)


func restore() -> void:
	health = max_health
	chakra = max_chakra
	_modifiers.clear()
	health_changed.emit(health, max_health)
	chakra_changed.emit(chakra, max_chakra)


## Adds a timed modifier. Re-applying the same stat refreshes it and keeps the
## stronger magnitude rather than stacking.
func add_modifier(stat: StringName, magnitude: float, duration: float) -> void:
	var existing: Dictionary = _modifiers.get(stat, {"magnitude": 0.0, "time": 0.0})
	_modifiers[stat] = {
		"magnitude": maxf(existing["magnitude"], magnitude),
		"time": maxf(existing["time"], duration),
	}
	modifier_changed.emit(stat, _modifiers[stat]["magnitude"], _modifiers[stat]["time"])


func modifier(stat: StringName) -> float:
	return _modifiers[stat]["magnitude"] if _modifiers.has(stat) else 0.0


func modifier_time_left(stat: StringName) -> float:
	return _modifiers[stat]["time"] if _modifiers.has(stat) else 0.0
