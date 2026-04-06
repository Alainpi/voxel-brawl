# scripts/hud.gd
extends CanvasLayer

@onready var ammo_label: Label = $AmmoLabel
@onready var reload_label: Label = $ReloadLabel
@onready var weapon_label: Label = $WeaponLabel
@onready var stance_indicator: HudStanceIndicator = $HudStanceIndicator
@onready var pickup_prompt: Label = $PickupPrompt

var _crosshair: Control

func _ready() -> void:
	reload_label.visible = false
	update_ammo(6, 6)

	_crosshair = load("res://scripts/crosshair.gd").new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

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
