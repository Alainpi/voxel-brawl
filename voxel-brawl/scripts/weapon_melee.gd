# scripts/weapon_melee.gd
# Melee weapon base — per-frame shape overlap hit detection with timer-driven activation window.
# Subclasses override _configure() for stats, _apply_hit() for damage behaviour,
# _create_hitarea() for composite collision shape setup.
class_name WeaponMelee
extends WeaponBase

var damage := 10.0
var voxel_radius := 2.0
var reach := 0.5
var cooldown := 0.4
var attack_anim := "punch"

var hit_enable_delay := 0.1      # seconds from attack start until hitbox activates
var hit_window_duration := 0.15  # how long the hitbox stays active
var max_hits := 1                # max segments hit per swing; subclasses override
var hit_shape: Shape3D = null            # set by subclass in _configure()
var hit_shape_offset: Vector3 = Vector3.ZERO
var hit_shape_rotation: Vector3 = Vector3.ZERO  # degrees — e.g. Vector3(90,0,0) to align capsule
var hit_shape_scale: Vector3 = Vector3.ONE

var _cooldown_timer := 0.0
var _hit_area: Area3D = null
var _hit_segments: Array[VoxelSegment] = []
var _own_segment_set: Dictionary = {}  # VoxelSegment -> true, lazy-populated on first use

var _hitbox_active := false

@onready var audio: AudioStreamPlayer3D = $AudioStreamPlayer3D

# _create_hitarea() must come after super() — hit_shape and hit_shape_offset are
# populated by _configure() inside super(), before _create_hitarea() runs.
func _ready() -> void:
	super()
	_create_hitarea()

# Virtual — override in subclasses to build composite hitbox shapes (e.g. WeaponFists
# adds a second CollisionShape3D for the left fist). Call super() first to get
# _hit_area created and the primary shape added.
# IMPORTANT: set hit_shape in _configure() for super() to build the primary shape.
# If hit_shape is null, super() skips the primary CollisionShape3D.
func _create_hitarea() -> void:
	_hit_area = Area3D.new()
	_hit_area.collision_layer = 0
	_hit_area.collision_mask = 2
	_hit_area.monitoring = false
	_hit_area.monitorable = false
	if hit_shape:
		var col := CollisionShape3D.new()
		col.shape = hit_shape
		col.position = hit_shape_offset
		col.rotation_degrees = hit_shape_rotation
		col.scale = hit_shape_scale
		_hit_area.add_child(col)
	add_child(_hit_area)
	# area_entered not connected — shape overlap query is the sole hit mechanism

func _enable_hitbox() -> void:
	_hitbox_active = true

func _disable_hitbox() -> void:
	_hitbox_active = false
	_hit_segments.clear()

func _physics_process(delta: float) -> void:
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	if Input.is_action_just_pressed("attack") and _cooldown_timer <= 0.0:
		_attack()
	if _hitbox_active:
		_shape_overlap_check()

# Each physics tick during the active window: query every CollisionShape3D in
# _hit_area against layer-2 areas. Fires _apply_hit() for the first max_hits
# unique, non-own segments found.
func _shape_overlap_check() -> void:
	if _hit_segments.size() >= max_hits:
		return
	var space := get_world_3d().direct_space_state
	for child in _hit_area.get_children():
		if not child is CollisionShape3D:
			continue
		var col := child as CollisionShape3D
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = col.shape
		params.transform = col.global_transform
		params.collision_mask = 2
		params.collide_with_areas = true
		params.collide_with_bodies = false
		var hits := space.intersect_shape(params, max_hits - _hit_segments.size())
		for hit_dict in hits:
			if _hit_segments.size() >= max_hits:
				return
			var area := hit_dict.collider as Area3D
			if area == null or not area.has_meta("voxel_segment"):
				continue
			var seg: VoxelSegment = area.get_meta("voxel_segment")
			if _own_segment_set.is_empty() and not _player.segments.is_empty():
				for s: VoxelSegment in _player.segments.values():
					_own_segment_set[s] = true
			if seg in _own_segment_set:
				continue
			if seg in _hit_segments:
				continue
			_hit_segments.append(seg)
			var local_hit := seg.to_local(col.global_transform.origin)
			_apply_hit(seg, local_hit)
			if _hit_segments.size() == 1:
				if audio.stream:
					audio.play()
				_player.trigger_hit_shake()
				_player.trigger_crosshair_recoil()

func _attack() -> void:
	_cooldown_timer = cooldown
	_hit_segments.clear()
	_player.play_attack_anim(attack_anim)
	await get_tree().create_timer(hit_enable_delay).timeout
	if not is_instance_valid(self) or not _player._is_attacking:
		return   # node freed, or interrupted by death / weapon swap
	_enable_hitbox()
	await get_tree().create_timer(hit_window_duration).timeout
	if is_instance_valid(self):
		_disable_hitbox()

# Override in subclasses to implement weapon-specific damage behaviour.
func _apply_hit(seg: VoxelSegment, local_hit: Vector3) -> void:
	DamageManager.process_hit(seg, local_hit, voxel_radius, damage)
