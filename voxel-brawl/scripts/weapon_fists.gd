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
	hit_shape_offset = Vector3(0, 0, -0.3)   # right fist — forward from weapon root
	hit_enable_delay = 0.08
	hit_window_duration = 1
	max_hits = 5

func _create_hitarea() -> void:
	super()   # builds _hit_area, adds right-fist sphere from hit_shape
	# Left fist — same shape, mirrored on X. Tune x_offset in-game via Remote tab.
	var left := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.3
	left.shape = s
	left.position = Vector3(-0.5, 0, -0.3)   # tune X until left knuckle aligns
	_hit_area.add_child(left)
