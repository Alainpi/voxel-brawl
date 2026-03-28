# scripts/weapon_katana.gd
# Precision blade. Thin slice, very high damage — can sever a limb in one clean hit.
# Causes bleed (ongoing voxel drain after the strike).
# TODO: implement bleed system (timed voxel drain on hit segment).
class_name WeaponKatana
extends WeaponMelee

func _configure() -> void:
	weapon_type = WeaponType.SHARP
	damage = 45.0
	voxel_radius = 1.0   # thin precise slice — surgical removal
	reach = 1.0
	cooldown = 0.3
	attack_anim = "katana"
	var s := BoxShape3D.new()
	s.size = Vector3(0.05, 0.6, 0.05)
	hit_shape = s
	hit_shape_offset = Vector3(-0.15, 0.2, 3.0)
	hit_shape_rotation = Vector3(90, 0, 0)
	hit_shape_scale = Vector3(5.0, 8.0, 5.0)
	hit_enable_delay = 0.53
	hit_window_duration = 1.0
	max_hits = 10

func _attack() -> void:
	if _player.stance_manager.current_stance() == StanceManager.Stance.THRUST:
		damage = 55.0
		max_hits = 1
	else:
		damage = 45.0
		max_hits = 10
	super()

func _apply_hit(seg: VoxelSegment, local_hit: Vector3) -> void:
	# Sharp slice: thin cut but extreme damage forces immediate detach threshold check.
	# A single clean hit to an arm or leg should sever it.
	DamageManager.process_hit(seg, local_hit, voxel_radius, damage, weapon_type)
	# TODO: start bleed timer on seg — drain N voxels per second for 3s after hit.
