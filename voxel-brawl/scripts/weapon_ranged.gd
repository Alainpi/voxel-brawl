# scripts/weapon_ranged.gd
# Ranged weapon base — dual-ray hit detection, ammo, and reload.
# Subclasses override _configure() for stats, _apply_hit() for damage behaviour,
# and _fire() to change firing pattern (e.g. shotgun spread).
class_name WeaponRanged
extends WeaponBase

const RAY_LENGTH := 100.0

var damage := 25.0
var voxel_radius := 1.5
var fire_rate := 0.5
var max_ammo := 6
var reload_time := 1.5

var _ammo := 0
var _cooldown := 0.0
var _reloading := false
var _reload_timer := 0.0

@export var tracer_color := Color(1.0, 0.96, 0.63, 1.0)
@export var recoil_shake_strength := 0.2
@export var recoil_kick_amount    := 12.0
@export var recoil_recovery_time  := 0.25

@onready var muzzle: Node3D = $Muzzle

signal ammo_changed(current: int, max_ammo: int)

@onready var audio_shot: AudioStreamPlayer3D = $AudioShot
@onready var muzzle_flash: GPUParticles3D = $MuzzleFlash

func _ready() -> void:
	super._ready()  # calls _configure() then sets _player
	_ammo = max_ammo
	if muzzle_flash:
		muzzle_flash.one_shot = true
		muzzle_flash.emitting = false

func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)

	if _reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_ammo = max_ammo
			_reloading = false
			ammo_changed.emit(_ammo, max_ammo)
		return

	if Input.is_action_just_pressed("reload") and _ammo < max_ammo:
		_start_reload()

	if Input.is_action_just_pressed("attack") and _cooldown <= 0.0 and _ammo > 0:
		_fire()
	elif Input.is_action_just_pressed("attack") and _ammo <= 0:
		_start_reload()

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
	_fire_ray(aim_flat.normalized())

# Fires a single ray. Override _fire() and call this multiple times for spread weapons.
func _fire_ray(aim_dir_h: Vector3, spread_angle: float = 0.0) -> void:
	var muzzle_pos: Vector3 = muzzle.global_position
	var space := get_world_3d().direct_space_state

	# Ray 1 — horizontal wall check from muzzle (layer 1 = static bodies only)
	var wall_params := PhysicsRayQueryParameters3D.create(
		muzzle_pos, muzzle_pos + aim_dir_h * RAY_LENGTH, 1
	)
	wall_params.collide_with_areas = false
	wall_params.collide_with_bodies = true
	wall_params.exclude = [_player.get_rid()]
	var wall_hit := space.intersect_ray(wall_params)

	# Ray 2 — camera ray for precise voxel targeting (layer 2 = voxel areas only)
	# spread_angle rotates it horizontally to match per-pellet spread direction.
	var cam_ray: Dictionary = _player.get_camera_ray()
	var cam_origin: Vector3 = cam_ray["origin"]
	var cam_dir: Vector3 = cam_ray["dir"]
	if spread_angle != 0.0:
		cam_dir = cam_dir.rotated(Vector3.UP, spread_angle)
	var voxel_params := PhysicsRayQueryParameters3D.create(
		cam_origin, cam_origin + cam_dir * RAY_LENGTH, 2
	)
	voxel_params.collide_with_areas = true
	voxel_params.collide_with_bodies = false
	var voxel_hit := space.intersect_ray(voxel_params)

	var wall_dist_h := INF
	if not wall_hit.is_empty():
		wall_dist_h = Vector2(
			wall_hit.position.x - muzzle_pos.x,
			wall_hit.position.z - muzzle_pos.z
		).length()

	var voxel_dist_h := INF
	if not voxel_hit.is_empty():
		voxel_dist_h = Vector2(
			voxel_hit.position.x - muzzle_pos.x,
			voxel_hit.position.z - muzzle_pos.z
		).length()

	if not wall_hit.is_empty() and wall_dist_h <= voxel_dist_h:
		BulletTracer.spawn(muzzle_pos, wall_hit.position, tracer_color, get_tree().root)
		_on_wall_hit(wall_hit.position, wall_hit.normal)
		return

	if voxel_hit.is_empty():
		BulletTracer.spawn(
			muzzle_pos, cam_origin + cam_dir * RAY_LENGTH, tracer_color, get_tree().root
		)
		return

	BulletTracer.spawn(muzzle_pos, voxel_hit.position, tracer_color, get_tree().root)

	var area := voxel_hit.collider as Area3D
	if area and area.has_meta("voxel_segment"):
		var seg: VoxelSegment = area.get_meta("voxel_segment")
		var dda_start := seg.to_local(voxel_hit.position - cam_dir * 0.1)
		var dda_dir := (seg.global_transform.affine_inverse().basis * cam_dir).normalized()
		var dda_result := seg.dda_raycast(dda_start, dda_dir)
		if dda_result.hit:
			var voxel_center := (Vector3(dda_result.voxel) + Vector3(0.5, 0.5, 0.5)) * VoxelSegment.VOXEL_SIZE
			_apply_hit(seg, voxel_center)

# Override in subclasses for weapon-specific damage behaviour.
func _apply_hit(seg: VoxelSegment, voxel_center: Vector3) -> void:
	DamageManager.process_hit(seg, voxel_center, voxel_radius, damage)

# Override to customise wall impact (e.g. different sparks for different ammo types).
func _on_wall_hit(pos: Vector3, normal: Vector3) -> void:
	_spawn_wall_impact(pos, normal)

func _play_shot_effects() -> void:
	if audio_shot.stream:
		audio_shot.play()
	if muzzle_flash:
		muzzle_flash.global_position = muzzle.global_position
		muzzle_flash.restart()

func _spawn_wall_impact(pos: Vector3, normal: Vector3) -> void:
	var particles := GPUParticles3D.new()
	get_tree().root.add_child(particles)
	particles.global_position = pos
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(normal.x, maxf(normal.y, 0.3), normal.z).normalized()
	mat.spread = 70.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0.0, -9.0, 0.0)
	mat.color = Color(0.75, 0.68, 0.55)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.05, 0.05)
	particles.process_material = mat
	particles.draw_pass_1 = mesh
	particles.amount = 10
	particles.lifetime = 0.2
	particles.one_shot = true
	particles.emitting = true
	get_tree().create_timer(0.4).timeout.connect(particles.queue_free)

func _apply_recoil() -> void:
	_player.trigger_hit_shake(recoil_shake_strength)
	_player.trigger_crosshair_recoil(recoil_kick_amount, recoil_recovery_time)

func _start_reload() -> void:
	_reloading = true
	_reload_timer = reload_time
