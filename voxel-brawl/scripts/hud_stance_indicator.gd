# scripts/hud_stance_indicator.gd
class_name HudStanceIndicator
extends VBoxContainer

# Colors for active vs inactive rows
const COLOR_ACTIVE := Color(1.0, 0.85, 0.1, 1.0)    # bright yellow
const COLOR_INACTIVE := Color(0.6, 0.6, 0.6, 0.35)   # dim grey, translucent

@onready var row_thrust: HBoxContainer = $Row_THRUST
@onready var row_high: HBoxContainer = $Row_HIGH
@onready var row_mid: HBoxContainer = $Row_MID
@onready var row_low: HBoxContainer = $Row_LOW

# Maps each Stance value to its corresponding row node
var _row_map: Dictionary = {}

func _ready() -> void:
	_row_map = {
		StanceManager.Stance.THRUST: row_thrust,
		StanceManager.Stance.HIGH:   row_high,
		StanceManager.Stance.MID:    row_mid,
		StanceManager.Stance.LOW:    row_low,
	}

## Called by hud.gd whenever stance changes or weapon is switched.
## stance: the currently active stance
## available: the stances valid for the current weapon (empty = ranged, hide indicator)
func update(stance: StanceManager.Stance, available: Array[StanceManager.Stance]) -> void:
	visible = not available.is_empty()
	if not visible:
		return

	for s in _row_map:
		var row: HBoxContainer = _row_map[s]
		var in_available: bool = available.has(s)
		row.visible = in_available
		if in_available:
			var bar: ColorRect = row.get_node("Bar")
			var label: Label = row.get_node("Label")
			var is_active: bool = (s == stance)
			bar.color = COLOR_ACTIVE if is_active else COLOR_INACTIVE
			label.modulate = Color(1, 1, 1, 1.0) if is_active else Color(1, 1, 1, 0.4)
