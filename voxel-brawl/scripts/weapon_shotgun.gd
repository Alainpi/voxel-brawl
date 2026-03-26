# scripts/weapon_shotgun.gd
# Close-range spread weapon. Fires multiple pellets per shot — can hit multiple limbs.
class_name WeaponShotgun
extends WeaponRanged

const PELLET_COUNT := 6
const SPREAD_ANGLE := 0.18  # radians — half-cone width per pellet

func _configure() -> void:
	weapon_type = WeaponType.RANGED
	damage = 12.0   # per pellet — full spread at close range = 72 total
	voxel_radius = 1.2
	fire_rate = 0.9
	max_ammo = 2
	reload_time = 2.0

func _fire() -> void:
	_ammo -= 1
	_cooldown = fire_rate
	ammo_changed.emit(_ammo, max_ammo)
	_player.play_attack_anim("shoot")
	_play_shot_effects()

	var mouse_world := _player.get_mouse_world_pos()
	if mouse_world == Vector3.ZERO:
		return
	var aim_flat := Vector3(
		mouse_world.x - _player.global_position.x,
		0.0,
		mouse_world.z - _player.global_position.z
	)
	if aim_flat.length_squared() < 0.001:
		return
	var aim_dir_h := aim_flat.normalized()

	# Fire PELLET_COUNT rays with randomised spread around the aim direction.
	for i in range(PELLET_COUNT):
		var angle := randf_range(-SPREAD_ANGLE, SPREAD_ANGLE)
		var spread_dir := aim_dir_h.rotated(Vector3.UP, angle)
		_fire_ray(spread_dir)
