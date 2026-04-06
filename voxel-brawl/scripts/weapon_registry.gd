# scripts/weapon_registry.gd
# Autoload singleton. Single source of truth for all weapon metadata.
# Registered as "WeaponRegistry" in project settings.
extends Node

enum Slot { FISTS = 0, MELEE = 1, RANGED = 2 }

var _data: Dictionary = {
	&"fists": {
		"scene": preload("res://scenes/weapons/fists.tscn"),
		"mesh": null,
		"display_name": "Fists",
		"slot": Slot.FISTS,
		"pickup_rotation": Vector3.ZERO,
	},
	&"bat": {
		"scene": preload("res://scenes/weapons/bat.tscn"),
		"mesh": preload("res://assets/models/Weapons/Bat.obj"),
		"display_name": "Bat",
		"slot": Slot.MELEE,
		"pickup_rotation": Vector3(90, 0, 0),
	},
	&"katana": {
		"scene": preload("res://scenes/weapons/katana.tscn"),
		"mesh": preload("res://assets/models/Weapons/Katana.obj"),
		"display_name": "Katana",
		"slot": Slot.MELEE,
		"pickup_rotation": Vector3(90, 0, 0),
	},
	&"revolver": {
		"scene": preload("res://scenes/weapons/revolver.tscn"),
		"mesh": preload("res://assets/models/Weapons/Revolver.obj"),
		"display_name": "Revolver",
		"slot": Slot.RANGED,
		"pickup_rotation": Vector3(90, 0, 0),
	},
	&"shotgun": {
		"scene": preload("res://scenes/weapons/shotgun.tscn"),
		"mesh": preload("res://assets/models/Weapons/Shotgun.obj"),
		"display_name": "Shotgun",
		"slot": Slot.RANGED,
		"pickup_rotation": Vector3(90, 0, 0),
	},
}

func get_scene(id: StringName) -> PackedScene:
	return _data[id]["scene"]

func get_mesh(id: StringName) -> Variant:  # ArrayMesh or null
	return _data[id]["mesh"]

func get_display_name(id: StringName) -> String:
	return _data[id]["display_name"]

func get_slot(id: StringName) -> Slot:
	return _data[id]["slot"]

func get_pickup_rotation(id: StringName) -> Vector3:
	return _data[id]["pickup_rotation"]

func has(id: StringName) -> bool:
	return _data.has(id)
