# scripts/crosshair.gd
# Full-screen Control that draws a dynamic crosshair via _draw().
extends Control

const GAP     := 8.0    # Distance from center to inner end of each arm
const LENGTH  := 12.0   # Length of each arm
const THICK   := 2.0    # Line thickness
const COLOR   := Color(1.0, 1.0, 1.0, 0.85)
const DOT_R   := 1.5    # Center dot radius

const RECOIL_SPREAD := 16.0  # Default pixels added to gap on fire
const DECAY         := 14.0  # Default decay rate

var _spread := 0.0
var _decay_rate := DECAY

func _process(delta: float) -> void:
	if _spread > 0.05:
		_spread = lerpf(_spread, 0.0, _decay_rate * delta)
	elif _spread > 0.0:
		_spread = 0.0
	queue_redraw()  # Always redraw — crosshair must follow mouse every frame

func _draw() -> void:
	var c := get_local_mouse_position()
	var g := GAP + _spread

	# Top arm
	draw_line(c + Vector2(0, -g - LENGTH), c + Vector2(0, -g), COLOR, THICK, true)
	# Bottom arm
	draw_line(c + Vector2(0,  g),          c + Vector2(0,  g + LENGTH), COLOR, THICK, true)
	# Left arm
	draw_line(c + Vector2(-g - LENGTH, 0), c + Vector2(-g, 0), COLOR, THICK, true)
	# Right arm
	draw_line(c + Vector2(g, 0),           c + Vector2(g + LENGTH, 0), COLOR, THICK, true)
	# Center dot
	draw_circle(c, DOT_R, COLOR)

# kick: pixels added to gap. recovery: seconds to settle back to zero.
func recoil(kick: float = RECOIL_SPREAD, recovery: float = 0.188) -> void:
	_spread = maxf(_spread, kick)
	_decay_rate = 2.6 / maxf(recovery, 0.05)
	queue_redraw()
