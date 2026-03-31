# scripts/weapon_base.gd
# Base class for all weapons. Handles player reference and the _configure() hook.
# Subclasses set their stats by overriding _configure(), which runs before _ready() completes.
class_name WeaponBase
extends Node3D

var _player  # duck-typed: Player for player weapons, Brawler for NPC weapons

enum WeaponType { BLUNT, SHARP, RANGED }
var weapon_type: WeaponType = WeaponType.BLUNT

func _ready() -> void:
	_configure()
	if _player == null:
		_player = get_node("../../../../")

# Override in each concrete weapon class to set stats.
func _configure() -> void:
	pass
