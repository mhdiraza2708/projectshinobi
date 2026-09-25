class_name SealWeaver
extends RefCounted
## Pure state machine for weaving a seal sequence. Knows nothing about input
## devices or jutsu; the player controller feeds it seals and the caster turns
## the finished sequence into a technique.

signal started
signal seal_added(seal: int, sequence: Array[int])
## The gap between two seals exceeded the timing window; the sequence resets
## but weaving continues so the player can start over without re-pressing.
signal broken
signal finished(sequence: Array[int])
signal cancelled

## Seconds allowed between consecutive seals at timeout_scale 1.0.
const BASE_TIMEOUT := 1.1
const MAX_SEALS := 12

## 0 disables the timing window entirely (accessibility option).
var timeout_scale := 1.0
var is_weaving := false
var sequence: Array[int] = []

var _since_last_seal := 0.0


func begin() -> void:
	if is_weaving:
		return
	is_weaving = true
	sequence.clear()
	_since_last_seal = 0.0
	started.emit()


func add_seal(seal: int) -> bool:
	if not is_weaving or not Seal.is_valid(seal) or sequence.size() >= MAX_SEALS:
		return false
	sequence.append(seal)
	_since_last_seal = 0.0
	seal_added.emit(seal, sequence.duplicate())
	return true


func tick(delta: float) -> void:
	if not is_weaving or sequence.is_empty() or timeout_scale <= 0.0:
		return
	_since_last_seal += delta
	if _since_last_seal > BASE_TIMEOUT * timeout_scale:
		sequence.clear()
		_since_last_seal = 0.0
		broken.emit()


## Ends the weave and returns the sequence to cast (may be empty).
func finish() -> Array[int]:
	if not is_weaving:
		return []
	is_weaving = false
	var result := sequence.duplicate()
	sequence.clear()
	finished.emit(result)
	return result


func cancel() -> void:
	if not is_weaving:
		return
	is_weaving = false
	sequence.clear()
	cancelled.emit()


## 1.0 right after a seal, falling to 0.0 when the window closes. Always 1.0
## when there is no time limit or nothing to lose yet.
func window_remaining() -> float:
	if not is_weaving or sequence.is_empty() or timeout_scale <= 0.0:
		return 1.0
	return clampf(1.0 - _since_last_seal / (BASE_TIMEOUT * timeout_scale), 0.0, 1.0)
