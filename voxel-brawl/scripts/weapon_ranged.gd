# scripts/weapon_ranged.gd
class_name WeaponRanged
extends Node3D

const DAMAGE := 25.0
const VOXEL_RADIUS := 1.5
const FIRE_RATE := 0.5
const MAX_AMMO := 6
const RELOAD_TIME := 1.5
const RAY_LENGTH := 100.0

@onready var audio_shot: AudioStreamPlayer3D = $AudioShot
@onready var muzzle_flash: GPUParticles3D = $MuzzleFlash

var _ammo := MAX_AMMO
var _cooldown := 0.0
var _reloading := false
var _reload_timer := 0.0
var _player: Player

signal ammo_changed(current, max_ammo)

func _ready() -> void:
	_player = get_node("../../../../")
	muzzle_flash.one_shot = true
	muzzle_flash.emitting = false

func _physics_process(delta: float) -> void:
	_cooldown = max(0.0, _cooldown - delta)

	if _reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_ammo = MAX_AMMO
			_reloading = false
			emit_signal("ammo_changed", _ammo, MAX_AMMO)
		return

	if Input.is_action_just_pressed("reload") and _ammo < MAX_AMMO:
		_start_reload()

	if Input.is_action_just_pressed("attack") and _cooldown <= 0.0 and _ammo > 0:
		_fire()
	elif Input.is_action_just_pressed("attack") and _ammo <= 0:
		_start_reload()

func _fire() -> void:
	_ammo -= 1
	_cooldown = FIRE_RATE
	emit_signal("ammo_changed", _ammo, MAX_AMMO)

	_player.play_attack_anim("shoot")
	if audio_shot.stream:
		audio_shot.play()
	muzzle_flash.global_position = _player.global_position + Vector3(0.0, 1.2, 0.0) \
		+ (-_player.global_transform.basis.z * 0.5)
	muzzle_flash.restart()

	var mouse_world := _player.get_mouse_world_pos()
	if mouse_world == Vector3.ZERO:
		return
	var aim_flat := Vector3(mouse_world.x - _player.global_position.x, 0.0, mouse_world.z - _player.global_position.z)
	if aim_flat.length_squared() < 0.001:
		return
	var aim_dir_h := aim_flat.normalized()
	var chest := _player.global_position + Vector3(0.0, 1.2, 0.0)
	var space := get_world_3d().direct_space_state

	# Ray 1 — horizontal wall check from chest (layer 1 = walls/static bodies only).
	# Determines whether a wall blocks the line of fire before reaching the target.
	var wall_params := PhysicsRayQueryParameters3D.create(
		chest,
		chest + aim_dir_h * RAY_LENGTH,
		1
	)
	wall_params.collide_with_areas = false
	wall_params.collide_with_bodies = true
	wall_params.exclude = [_player.get_rid()]
	var wall_hit := space.intersect_ray(wall_params)

	# Ray 2 — camera ray for precise voxel targeting (layer 2 = voxel areas only).
	# Follows the actual cursor angle so headshots/legshots are possible.
	var cam_ray := _player.get_camera_ray()
	var cam_origin: Vector3 = cam_ray["origin"]
	var cam_dir: Vector3 = cam_ray["dir"]
	var voxel_params := PhysicsRayQueryParameters3D.create(
		cam_origin,
		cam_origin + cam_dir * RAY_LENGTH,
		2
	)
	voxel_params.collide_with_areas = true
	voxel_params.collide_with_bodies = false
	var voxel_hit := space.intersect_ray(voxel_params)

	# Compare horizontal (XZ) distances from chest to decide which comes first.
	var wall_dist_h := INF
	if not wall_hit.is_empty():
		wall_dist_h = Vector2(wall_hit.position.x - chest.x, wall_hit.position.z - chest.z).length()

	var voxel_dist_h := INF
	if not voxel_hit.is_empty():
		voxel_dist_h = Vector2(voxel_hit.position.x - chest.x, voxel_hit.position.z - chest.z).length()

	if not wall_hit.is_empty() and wall_dist_h <= voxel_dist_h:
		# Wall is closer — bullet stops here
		_spawn_wall_impact(wall_hit.position, wall_hit.normal)
		_player.trigger_crosshair_recoil()
		return

	if voxel_hit.is_empty():
		return

	# Voxel is unobstructed — DDA using camera ray direction for height accuracy
	var area := voxel_hit.collider as Area3D
	if area and area.has_meta("voxel_segment"):
		var seg: VoxelSegment = area.get_meta("voxel_segment")
		var dda_start := seg.to_local(voxel_hit.position - cam_dir * 0.1)
		var dda_dir := (seg.global_transform.affine_inverse().basis * cam_dir).normalized()
		var dda_result := seg.dda_raycast(dda_start, dda_dir)
		if dda_result.hit:
			var voxel_center := (Vector3(dda_result.voxel) + Vector3(0.5, 0.5, 0.5)) * VoxelSegment.VOXEL_SIZE
			DamageManager.process_hit(seg, voxel_center, VOXEL_RADIUS, DAMAGE)
			_player.trigger_hit_shake()
			_player.trigger_crosshair_recoil()

func _spawn_wall_impact(pos: Vector3, normal: Vector3) -> void:
	var particles := GPUParticles3D.new()
	get_tree().root.add_child(particles)
	particles.global_position = pos

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 70.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0.0, -9.0, 0.0)
	mat.color = Color(0.75, 0.68, 0.55)  # Concrete dust
	# Bias spray along the wall normal so dust flies away from the surface
	mat.direction = Vector3(normal.x, maxf(normal.y, 0.3), normal.z).normalized()

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.05, 0.05)

	particles.process_material = mat
	particles.draw_pass_1 = mesh
	particles.amount = 10
	particles.lifetime = 0.2
	particles.one_shot = true
	particles.emitting = true

	get_tree().create_timer(0.4).timeout.connect(particles.queue_free)

func _start_reload() -> void:
	_reloading = true
	_reload_timer = RELOAD_TIME
