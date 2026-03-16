# scripts/hud.gd
extends CanvasLayer

@onready var ammo_label: Label = $AmmoLabel
@onready var reload_label: Label = $ReloadLabel
@onready var weapon_label: Label = $WeaponLabel

func _ready() -> void:
	reload_label.visible = false
	update_ammo(6, 6)

func update_ammo(current: int, max_ammo: int) -> void:
	ammo_label.text = "%d / %d" % [current, max_ammo]
	reload_label.visible = (current == 0)

func set_weapon_name(name: String) -> void:
	weapon_label.text = "[%s]" % name.to_upper()
