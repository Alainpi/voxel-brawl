# scripts/weapon_ranged.gd
class_name WeaponRanged
extends Node3D

const DAMAGE := 35.0
const VOXEL_RADIUS := 10.0
const FIRE_RATE := 0.5
const MAX_AMMO := 6
const RELOAD_TIME := 1.5

@onready var raycast: RayCast3D = $"../../RayCast3D"
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
	#audio_shot.stream = preload("res://assets/audio/revolver_shot.wav")
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
	muzzle_flash.restart()

	if not raycast.is_colliding():
		return

	var collider := raycast.get_collider()
	var area := collider as Area3D
	if area and area.has_meta("voxel_segment"):
		var seg: VoxelSegment = area.get_meta("voxel_segment")
		var hit_point := raycast.get_collision_point()
		var local_hit := seg.to_local(hit_point)
		DamageManager.process_hit(seg, local_hit, VOXEL_RADIUS, DAMAGE)
		_player.trigger_hit_shake()

func _start_reload() -> void:
	_reloading = true
	_reload_timer = RELOAD_TIME
