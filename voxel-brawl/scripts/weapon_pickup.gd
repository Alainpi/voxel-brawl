# scripts/weapon_pickup.gd
# A weapon lying in the world. Player highlights it by looking at it (raycast)
# and presses F to collect it. weapon_id must be set before _ready() runs.
class_name WeaponPickup
extends StaticBody3D

@export var weapon_id: StringName = &""

@onready var _mesh: MeshInstance3D = $MeshInstance3D

static var _highlight_mat: StandardMaterial3D = preload("res://assets/materials/pickup_highlight.tres")

func _ready() -> void:
	if weapon_id == &"":
		return
	if not WeaponRegistry.has(weapon_id):
		push_error("WeaponPickup: unknown weapon_id '%s'" % weapon_id)
		return
	var m = WeaponRegistry.get_mesh(weapon_id)
	if m:
		_mesh.mesh = m
	rotation_degrees = WeaponRegistry.get_pickup_rotation(weapon_id)

func highlight(on: bool) -> void:
	_mesh.material_overlay = _highlight_mat if on else null
