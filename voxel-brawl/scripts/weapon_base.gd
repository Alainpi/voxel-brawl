# scripts/weapon_base.gd
# Base class for all weapons. Handles player reference and the _configure() hook.
# Subclasses set their stats by overriding _configure(), which runs before _ready() completes.
class_name WeaponBase
extends Node3D

var _player  # duck-typed: Player for player weapons, Brawler for NPC weapons
var weapon_id: StringName = &""  # set by Player.give_weapon() after instantiation

enum WeaponType { BLUNT, SHARP, RANGED }
var weapon_type: WeaponType = WeaponType.BLUNT

# Which hand this weapon mounts on. Default "r" — all current prototype weapons use right hand.
var held_side: StringName = &"r"
# Two-handed weapons require both hands intact. None in the prototype set, but gated in give_weapon.
var requires_both_hands: bool = false

func _ready() -> void:
	_configure()
	# _player must be set externally via weapon._player = self after instantiation.
	# Do not fall back to get_node() — the weapon may be instanced into any holder.

# Override in each concrete weapon class to set stats.
func _configure() -> void:
	pass
