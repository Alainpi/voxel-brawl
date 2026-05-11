# scripts/weapon_shotgun.gd
# Close-range spread weapon. Fires multiple pellets per shot — can hit multiple limbs.
class_name WeaponShotgun
extends WeaponRanged

const PELLET_COUNT := 6

@export var spread_near: float = 0.5           # scatter radius in world units at the aim plane (v1: only this is used)
# v2 placeholders — reserved for distance-based falloff; not wired in v1.
@export var spread_far: float  = 0.1           # scatter radius at max range
@export var spread_falloff_dist: float = 12.0  # distance (world units) where radius fully tightens

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

	# Scatter each pellet at the aim plane (world-space XZ) so spread maps to actual
	# body-part coverage rather than amplifying through the top-down camera angle.
	# spread_near is the scatter radius in world units.
	var cam_origin: Vector3 = _player.get_camera_ray()["origin"]
	for i in range(PELLET_COUNT):
		var r     := randf_range(0.0, spread_near)
		var theta := randf_range(0.0, TAU)
		var scatter := Vector3(cos(theta) * r, 0.0, sin(theta) * r)
		var pellet_dir := (mouse_world + scatter - cam_origin).normalized()
		_fire_ray(pellet_dir)
