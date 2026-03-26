# scripts/weapon_revolver.gd
# Slow, precise. High single-shot damage. 6 rounds, capable of headshot dismemberment.
class_name WeaponRevolver
extends WeaponRanged

func _configure() -> void:
	weapon_type = WeaponType.RANGED
	damage = 35.0
	voxel_radius = 1.5
	fire_rate = 0.55
	max_ammo = 6
	reload_time = 1.5
