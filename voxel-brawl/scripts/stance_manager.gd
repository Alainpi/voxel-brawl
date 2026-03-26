# scripts/stance_manager.gd
class_name StanceManager
extends Node

enum Stance { LOW, MID, HIGH, THRUST }

signal stance_changed(stance: Stance)

var _stances: Array[Stance] = []
var _index: int = 0

## Called by Player on weapon equip. Resets stance to MID.
## stances must always contain Stance.MID.
func setup(stances: Array[Stance]) -> void:
	assert(stances.has(Stance.MID), "StanceManager.setup: array must contain Stance.MID")
	_stances = stances
	_index = _stances.find(Stance.MID)

## Called by Player on scroll input. Wraps around the available stances.
func cycle(direction: int) -> void:
	if _stances.is_empty():
		return
	_index = (_index + direction) % _stances.size()
	if _index < 0:
		_index += _stances.size()
	stance_changed.emit(current_stance())

## Returns the active Stance. Falls back to MID if stances not yet set up.
func current_stance() -> Stance:
	if _stances.is_empty():
		return Stance.MID
	return _stances[_index]

## Returns a copy of the available stances (safe to pass to HUD).
func current_stances() -> Array[Stance]:
	return _stances.duplicate()
