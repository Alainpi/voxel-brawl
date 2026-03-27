# scripts/weapon_katana.gd
# Precision blade. Thin slice, very high damage — can sever a limb in one clean hit.
# Causes bleed (ongoing voxel drain after the strike).
# TODO: implement bleed system (timed voxel drain on hit segment).
class_name WeaponKatana
extends WeaponMelee

func _configure() -> void:
	weapon_type = WeaponType.SHARP
	damage = 45.0
	voxel_radius = 0.7   # thin precise slice — surgical removal
	reach = 1.0
	cooldown = 0.3
	attack_anim = "katana"
	var s := BoxShape3D.new()
	s.size = Vector3(0.08, 0.08, 0.9)   # thin along X/Y, long along Z (mesh rotated 90° X)
	hit_shape = s
	hit_shape_offset = Vector3(-0.3, 0.35, -0.9)   # mesh center — tune in Remote tab
	hit_enable_delay = 0.1
	hit_window_duration = 0.15
	max_hits = 3

func _apply_hit(seg: VoxelSegment, local_hit: Vector3) -> void:
	# Sharp slice: thin cut but extreme damage forces immediate detach threshold check.
	# A single clean hit to an arm or leg should sever it.
	DamageManager.process_hit(seg, local_hit, voxel_radius, damage)
	# TODO: start bleed timer on seg — drain N voxels per second for 3s after hit.
