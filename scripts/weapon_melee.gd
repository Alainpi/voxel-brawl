# scripts/weapon_melee.gd
class_name WeaponMelee
extends Node3D

const DAMAGE := 15.0
const VOXEL_RADIUS := 5.0
const COOLDOWN := 0.4
const REACH := 1.2
const HIT_SPHERE_RADIUS := 0.4

@onready var audio: AudioStreamPlayer3D = $AudioStreamPlayer3D

var _cooldown_timer := 0.0
var _player: Player

func _ready() -> void:
	_player = get_node("../../../../")  # Player root
	#audio.stream = preload("res://assets/audio/punch_impact.wav")

func _physics_process(delta: float) -> void:
	_cooldown_timer = max(0.0, _cooldown_timer - delta)
	if Input.is_action_just_pressed("attack") and _cooldown_timer <= 0.0:
		_attack()

func _attack() -> void:
	_cooldown_timer = COOLDOWN
	_player.play_attack_anim("punch")

	var space := get_world_3d().direct_space_state
	var origin := global_position
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = SphereShape3D.new()
	(params.shape as SphereShape3D).radius = HIT_SPHERE_RADIUS
	params.transform = Transform3D(Basis.IDENTITY, origin + (-get_node("../..").global_transform.basis.z * REACH))
	params.collision_mask = 2  # Layer 2 = voxel segment colliders
	params.collide_with_areas = true
	params.collide_with_bodies = false

	var results := space.intersect_shape(params, 8)
	var hit_any := false

	for result in results:
		var area := result.collider as Area3D
		if area and area.has_meta("voxel_segment"):
			var seg: VoxelSegment = area.get_meta("voxel_segment")
			var local_hit := seg.to_local(params.transform.origin)
			DamageManager.process_hit(seg, local_hit, VOXEL_RADIUS, DAMAGE)
			hit_any = true

	if hit_any:
		if audio.stream:
			audio.play()
		_player.trigger_hit_shake()
