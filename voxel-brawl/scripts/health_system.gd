# scripts/health_system.gd
class_name HealthSystem
extends Node

const WEIGHTS: Dictionary = {
	"torso_bottom": 60, "torso_top":   40,
	"head_bottom":  50, "head_top":    50,
	"arm_r_upper":  25, "arm_r_fore":  15,
	"arm_l_upper":  25, "arm_l_fore":  15,
	"hand_r":       20, "hand_l":      20,
	"leg_r_upper":  25, "leg_r_fore":  15,
	"leg_l_upper":  25, "leg_l_fore":  15,
}
const MAX_HP := 100.0

signal hp_changed(current: float, maximum: float)
signal died

var _segments: Dictionary = {}   # seg_name → VoxelSegment
var _totals: Dictionary = {}     # seg_name → int (voxel count at initialize time)
var _detached: Dictionary = {}   # seg_name → bool
var _is_dead: bool = false

func initialize(seg_dict: Dictionary) -> void:
	_segments = seg_dict
	_detached.clear()
	for seg_name in WEIGHTS:
		_detached[seg_name] = false
		var seg: VoxelSegment = _segments.get(seg_name)
		if seg != null:
			_totals[seg_name] = seg.total_voxel_count
			seg.detached.connect(_on_segment_detached.bind(seg_name))

func on_hit(_seg: VoxelSegment) -> void:
	_refresh()

func get_segment_health_fraction(seg_name: String) -> float:
	if _detached.get(seg_name, false):
		return 0.0
	var seg: VoxelSegment = _segments.get(seg_name)
	if seg == null:
		return 1.0
	var total: int = _totals.get(seg_name, 1)
	if total == 0:
		return 1.0
	return float(seg.current_voxel_count) / float(total)

func _compute_hp() -> float:
	var damage := 0.0
	for seg_name in WEIGHTS:
		var weight := float(WEIGHTS[seg_name])
		if _detached.get(seg_name, false):
			damage += weight
		else:
			var seg: VoxelSegment = _segments.get(seg_name)
			if seg == null:
				continue
			var total: int = _totals.get(seg_name, 0)
			if total == 0:
				continue
			var lost := 1.0 - float(seg.current_voxel_count) / float(total)
			damage += weight * lost
	return maxf(0.0, MAX_HP - damage)

func _refresh() -> void:
	var hp := _compute_hp()
	emit_signal("hp_changed", hp, MAX_HP)
	if hp <= 0.0 and not _is_dead:
		_is_dead = true
		emit_signal("died")

func _on_segment_detached(_seg: VoxelSegment, seg_name: String) -> void:
	if WEIGHTS.has(seg_name):
		_detached[seg_name] = true
	_refresh()
