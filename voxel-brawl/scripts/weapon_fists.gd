# scripts/weapon_fists.gd
class_name WeaponFists
extends WeaponMelee

func _configure() -> void:
	weapon_type = WeaponType.BLUNT
	damage = 8.0
	voxel_radius = 2.0
	reach = 0.5
	cooldown = 0.35
	attack_anim = "punch"
	var s := SphereShape3D.new()
	s.radius = 0.3
	hit_shape = s
	hit_shape_offset = Vector3(0, 0, -0.3)   # forward from weapon root
	hit_enable_delay = 0.08
	hit_window_duration = 0.12
	max_hits = 1
