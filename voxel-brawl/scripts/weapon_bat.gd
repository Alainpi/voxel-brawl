# scripts/weapon_bat.gd
# Blunt trauma weapon. Wide impact radius, high structural damage.
# Breaks bones and degrades limb function without clean severing.
# Does not cause bleed. TODO: implement bone degradation / limb disable system.
class_name WeaponBat
extends WeaponMelee

func _configure() -> void:
	weapon_type = WeaponType.BLUNT
	damage = 22.0
	voxel_radius = 2.8   # wide blunt impact area
	reach = 0.9
	cooldown = 0.65
	attack_anim = "bat"
	var s := CapsuleShape3D.new()
	s.radius = 0.15
	s.height = 0.8
	hit_shape = s
	hit_shape_offset = Vector3(-0.35, 0.35, -0.6)
	hit_shape_rotation = Vector3(90, 0, 0)
	hit_shape_scale = Vector3(1.0, 2.0, 1.0)
	hit_enable_delay = 0.2
	hit_window_duration = 0.18
	max_hits = 2

func _apply_hit(seg: VoxelSegment, local_hit: Vector3) -> void:
	# Blunt hit: large voxel removal simulates structural crushing.
	# High damage compresses the limb HP without triggering a clean sever —
	# the bat degrades the limb over multiple hits rather than slicing through.
	# TODO: reduce detach impulse force so limbs crumple rather than fly off cleanly.
	DamageManager.process_hit(seg, local_hit, voxel_radius, damage)

func _create_sweep_markers() -> void:
	super()
	_blade_tip.position = Vector3(-0.35, 0.35, -1.2)   # far end of barrel
	_blade_base.position = Vector3(-0.35, 0.35, -0.4)  # handle-barrel junction
