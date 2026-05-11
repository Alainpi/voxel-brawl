# scripts/hud.gd
extends CanvasLayer

@onready var ammo_label: Label = $AmmoLabel
@onready var reload_label: Label = $ReloadLabel
@onready var weapon_label: Label = $WeaponLabel
@onready var stance_indicator: HudStanceIndicator = $HudStanceIndicator
@onready var pickup_prompt: Label = $PickupPrompt
@onready var _hp_bar: ProgressBar = $HpBar

var _crosshair: Control
var _silhouette_rects: Dictionary = {}   # seg_name → ColorRect

func _ready() -> void:
	reload_label.visible = false
	update_ammo(6, 6)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.2, 0.8, 0.2)
	_hp_bar.add_theme_stylebox_override("fill", fill)

	_crosshair = load("res://scripts/crosshair.gd").new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

	# Populate silhouette rect references from scene nodes
	var sil := $BodySilhouette
	for seg_name in ["head_top", "head_bottom", "arm_l_upper", "torso_top", "arm_r_upper",
			"arm_l_fore", "torso_bottom", "arm_r_fore", "hand_l", "leg_l_upper",
			"leg_r_upper", "hand_r", "leg_l_fore", "leg_r_fore"]:
		var rect := sil.get_node_or_null(seg_name)
		if rect is ColorRect:
			_silhouette_rects[seg_name] = rect

func recoil(kick: float = 16.0, recovery: float = 0.188) -> void:
	_crosshair.recoil(kick, recovery)

func update_ammo(current: int, max_ammo: int) -> void:
	ammo_label.text = "%d / %d" % [current, max_ammo]
	reload_label.visible = (current == 0)

func set_weapon_name(weapon_name: String) -> void:
	weapon_label.text = "[%s]" % weapon_name.to_upper()

func update_stance(stance: StanceManager.Stance, available: Array[StanceManager.Stance]) -> void:
	stance_indicator.update(stance, available)

func show_pickup_prompt(weapon_name: String) -> void:
	pickup_prompt.text = "F — pick up %s" % weapon_name
	pickup_prompt.visible = true

func hide_pickup_prompt() -> void:
	pickup_prompt.visible = false

func update_health(current: float, maximum: float) -> void:
	_hp_bar.max_value = maximum
	_hp_bar.value = current

func update_body_silhouette(health_system: HealthSystem) -> void:
	for seg_name in _silhouette_rects:
		var frac    := health_system.get_segment_health_fraction(seg_name)
		var broken  := health_system.get_segment_is_broken(seg_name)
		_silhouette_rects[seg_name].color = _fraction_to_color(frac, broken)

func _fraction_to_color(f: float, is_broken: bool) -> Color:
	if f <= 0.0:   return Color(0.32, 0.32, 0.32)  # grey          — severed/gone
	if is_broken:  return Color(0.90, 0.08, 0.08)  # bright red    — broken/ragdolling
	if f < 0.25:   return Color(0.85, 0.10, 0.10)  # red           — critical
	if f < 0.50:   return Color(0.90, 0.50, 0.10)  # orange        — damaged
	if f < 0.75:   return Color(0.45, 0.85, 0.15)  # lighter green — minor damage
	return         Color(0.20, 0.78, 0.20)          # green         — healthy
