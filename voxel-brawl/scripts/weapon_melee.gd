# scripts/weapon_melee.gd
# Melee weapon base — sphere overlap hit detection.
# Subclasses override _configure() for stats and _apply_hit() for damage behaviour.
class_name WeaponMelee
extends WeaponBase

var damage := 10.0
var voxel_radius := 2.0
var reach := 0.5
var hit_sphere_radius := 0.8
var cooldown := 0.4
var attack_anim := "punch"

var _cooldown_timer := 0.0

@onready var audio: AudioStreamPlayer3D = $AudioStreamPlayer3D

func _physics_process(delta: float) -> void:
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	if Input.is_action_just_pressed("attack") and _cooldown_timer <= 0.0:
		_attack()

func _attack() -> void:
	_cooldown_timer = cooldown
	_player.play_attack_anim(attack_anim)
	await get_tree().create_timer(hit_delay).timeout
	_do_hit()

var hit_delay := 0.15  # seconds into swing when contact occurs — tune per weapon

func _do_hit() -> void:
	var space := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	params.collision_mask = 2
	params.collide_with_areas = true
	params.collide_with_bodies = false

	var mesh := find_child("*", false, false) as MeshInstance3D
	if mesh and mesh.mesh:
		var box := BoxShape3D.new()
		var aabb := mesh.get_aabb()
		box.size = aabb.size
		params.shape = box
		params.transform = mesh.global_transform * Transform3D(Basis.IDENTITY, aabb.get_center())
	else:
		# fallback if no mesh found
		var sphere := SphereShape3D.new()
		sphere.radius = hit_sphere_radius
		params.shape = sphere
		params.transform = Transform3D(Basis.IDENTITY,
			_player.global_position + Vector3(0, 1.2, 0) + (-_player.global_transform.basis.z * reach)
		)

	var results := space.intersect_shape(params, 8)
	var hit_any := false

	for result in results:
		var area := result.collider as Area3D
		if area and area.has_meta("voxel_segment"):
			var seg: VoxelSegment = area.get_meta("voxel_segment")
			var local_hit := seg.to_local(params.transform.origin)
			_apply_hit(seg, local_hit)
			break  # one hit per swing — remove if multi-hit is desired
			hit_any = true

	if hit_any:
		if audio.stream:
			audio.play()
		_player.trigger_hit_shake()
		_player.trigger_crosshair_recoil()

# Override in subclasses to implement weapon-specific damage behaviour.
func _apply_hit(seg: VoxelSegment, local_hit: Vector3) -> void:
	DamageManager.process_hit(seg, local_hit, voxel_radius, damage)
