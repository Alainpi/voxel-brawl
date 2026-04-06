# scripts/weapon_base.gd
# Base class for all weapons. Handles player reference and the _configure() hook.
# Subclasses set their stats by overriding _configure(), which runs before _ready() completes.
class_name WeaponBase
extends Node3D

var _player  # duck-typed: Player for player weapons, Brawler for NPC weapons
var weapon_id: StringName = &""  # set by Player.give_weapon() after instantiation

enum WeaponType { BLUNT, SHARP, RANGED }
var weapon_type: WeaponType = WeaponType.BLUNT

func _ready() -> void:
	_configure()
	# _player must be set externally via weapon._player = self after instantiation.
	# Do not fall back to get_node() — the weapon may be instanced into any holder.

# Override in each concrete weapon class to set stats.
func _configure() -> void:
	pass
