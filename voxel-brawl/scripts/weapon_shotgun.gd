# scripts/weapon_shotgun.gd
# Close-range spread weapon. Fires multiple pellets per shot — can hit multiple limbs.
class_name WeaponShotgun
extends WeaponRanged

const PELLET_COUNT := 6

@export var spread_near: float = 0.25          # half-angle radians at point-blank (v1: only this is used)
# v2 placeholders — reserved for distance-based falloff; not wired in v1.
@export var spread_far: float  = 0.08          # half-angle radians at max range
@export var spread_falloff_dist: float = 12.0  # distance (world units) where cone fully tightens

func _configure() -> void:
	weapon_type = WeaponType.RANGED
	damage = 12.0
	voxel_radius = 1.2
	fire_rate = 0.9
	max_ammo = 2
	reload_time = 2.0
	tracer_color = Color(1.0, 0.60, 0.0, 1.0)
	recoil_shake_strength = 0.60
	recoil_kick_amount = 28.0
	recoil_recovery_time = 0.40

func _fire() -> void:
	_ammo -= 1
	_cooldown = fire_rate
	ammo_changed.emit(_ammo, max_ammo)
	_player.play_attack_anim("shoot")
	_play_shot_effects()
	_apply_recoil()

	var mouse_world: Vector3 = _player.get_mouse_world_pos()
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

	# Each pellet gets an independent spread angle applied to both rays.
	# spread_near used for all pellets in v1; distance-based lerp to spread_far
	# can be tuned post-playtesting once the spread_falloff_dist feel is confirmed.
	for i in range(PELLET_COUNT):
		var angle := randf_range(-spread_near, spread_near)
		var spread_dir := aim_dir_h.rotated(Vector3.UP, angle)
		_fire_ray(spread_dir, angle)
