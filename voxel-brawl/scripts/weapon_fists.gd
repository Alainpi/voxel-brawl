# scripts/weapon_fists.gd
class_name WeaponFists
extends WeaponMelee

func _configure() -> void:
	weapon_type = WeaponType.BLUNT
	damage = 8.0
	voxel_radius = 2.0
	reach = 0.5
	hit_sphere_radius = 0.8
	cooldown = 0.35
	attack_anim = "punch"
