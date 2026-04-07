# scripts/hud.gd
extends CanvasLayer

@onready var ammo_label: Label = $AmmoLabel
@onready var reload_label: Label = $ReloadLabel
@onready var weapon_label: Label = $WeaponLabel
@onready var stance_indicator: HudStanceIndicator = $HudStanceIndicator
@onready var pickup_prompt: Label = $PickupPrompt

var _crosshair: Control
var _hp_bar: ProgressBar = null
var _silhouette_rects: Dictionary = {}   # region_name → ColorRect

const SILHOUETTE_REGIONS: Dictionary = {
	"head":   ["head_bottom", "head_top"],
	"chest":  ["torso_bottom", "torso_top"],
	"arm_l":  ["arm_l_upper", "arm_l_fore"],
	"arm_r":  ["arm_r_upper", "arm_r_fore"],
	"hand_l": ["hand_l"],
	"hand_r": ["hand_r"],
	"leg_l":  ["leg_l_upper", "leg_l_fore"],
	"leg_r":  ["leg_r_upper", "leg_r_fore"],
}

func _ready() -> void:
	reload_label.visible = false
	update_ammo(6, 6)

	_crosshair = load("res://scripts/crosshair.gd").new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

	_hp_bar = ProgressBar.new()
	_hp_bar.name = "HpBar"
	_hp_bar.min_value = 0.0
	_hp_bar.max_value = 100.0
	_hp_bar.value = 100.0
	_hp_bar.show_percentage = false
	add_child(_hp_bar)
	_hp_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hp_bar.position = Vector2(16.0, -36.0)
	_hp_bar.size = Vector2(200.0, 20.0)

	var sil := _build_silhouette()
	add_child(sil)
	sil.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	sil.position = Vector2(16.0, -136.0)

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
	if _hp_bar == null:
		return
	_hp_bar.max_value = maximum
	_hp_bar.value = current

func update_body_silhouette(health_system: HealthSystem) -> void:
	for region_name in SILHOUETTE_REGIONS:
		var segs: Array = SILHOUETTE_REGIONS[region_name]
		var total_frac := 0.0
		for seg_name in segs:
			total_frac += health_system.get_segment_health_fraction(seg_name)
		var avg_frac := total_frac / float(segs.size())
		var rect: ColorRect = _silhouette_rects.get(region_name)
		if rect != null:
			rect.color = _fraction_to_color(avg_frac)

func _build_silhouette() -> Control:
	var c := Control.new()
	c.name = "BodySilhouette"
	c.custom_minimum_size = Vector2(60.0, 90.0)
	c.size = Vector2(60.0, 90.0)
	# [region_name, x, y, width, height]
	var layout := [
		["head",    20,  0, 20, 20],
		["chest",    8, 22, 44, 28],
		["arm_l",    0, 22,  8, 28],
		["arm_r",   52, 22,  8, 28],
		["hand_l",   0, 52,  8, 12],
		["hand_r",  52, 52,  8, 12],
		["leg_l",   10, 52, 17, 38],
		["leg_r",   33, 52, 17, 38],
	]
	for entry in layout:
		var r := ColorRect.new()
		r.name = entry[0]
		r.position = Vector2(float(entry[1]), float(entry[2]))
		r.size = Vector2(float(entry[3]), float(entry[4]))
		r.color = Color(0.2, 0.8, 0.2)
		c.add_child(r)
		_silhouette_rects[entry[0]] = r
	return c

func _fraction_to_color(f: float) -> Color:
	if f <= 0.0:  return Color(0.3, 0.3, 0.3)   # grey  — gone
	if f < 0.25:  return Color(0.8, 0.1, 0.1)   # red   — critical
	if f < 0.50:  return Color(0.9, 0.5, 0.1)   # orange
	if f < 0.75:  return Color(0.9, 0.8, 0.1)   # yellow
	return        Color(0.2, 0.8, 0.2)           # green — healthy
