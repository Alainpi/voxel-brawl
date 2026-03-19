# scripts/brawler.gd
class_name Brawler
extends CharacterBody3D

signal died

const SPEED := 3.0
const GRAVITY := 9.8
const CHASE_RANGE := 15.0
const ATTACK_RANGE := 1.8
const ATTACK_COOLDOWN := 1.5
const ATTACK_DAMAGE := 20.0
const CRAWL_SPEED := 1.2

# [vox_path, local_offset, root_axis]
const SEGMENT_CONFIG := {
	"torso": ["res://assets/voxels/torso.vox", Vector3(-0.4, 2.2, -0.3), Vector3i.ZERO],
	"head":  ["res://assets/voxels/head.vox",  Vector3(-0.3, 2.8, -0.3), Vector3i(0, -1, 0)],
	"arm_l": ["res://assets/voxels/arm_l.vox", Vector3(-0.8, 2.2, -0.2), Vector3i(0, 1, 0)],
	"arm_r": ["res://assets/voxels/arm_r.vox", Vector3(0.4,  2.2, -0.2), Vector3i(0, 1, 0)],
	"leg_l": ["res://assets/voxels/leg_l.vox", Vector3(-0.4, 1.0, -0.2), Vector3i(0, 1, 0)],
	"leg_r": ["res://assets/voxels/leg_r.vox", Vector3(0.0,  1.0, -0.2), Vector3i(0, 1, 0)],
}

enum State { IDLE, CHASE, ATTACK, DEAD }

var segments: Dictionary = {}
var _state: State = State.IDLE
var _is_dead: bool = false
var _attack_timer: float = 0.0
var _legs_lost: int = 0
var _player: CharacterBody3D = null

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
	_build_segments()
	call_deferred("_find_player")

func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]

func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	_attack_timer = maxf(_attack_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if FovOverlay.instance != null:
		visible = FovOverlay.instance.is_visible_xz(
			Vector2(global_position.x, global_position.z)
		)

	_update_ai()
	move_and_slide()

func _update_ai() -> void:
	if _player == null:
		velocity.x = 0
		velocity.z = 0
		return

	var dist := global_position.distance_to(_player.global_position)

	match _state:
		State.IDLE:
			velocity.x = 0
			velocity.z = 0
			if dist < CHASE_RANGE:
				_state = State.CHASE

		State.CHASE:
			if dist > CHASE_RANGE * 1.2:
				_state = State.IDLE
				velocity.x = 0
				velocity.z = 0
			elif dist < ATTACK_RANGE:
				_state = State.ATTACK
				velocity.x = 0
				velocity.z = 0
			else:
				_move_toward_player()
				_face_player()

		State.ATTACK:
			velocity.x = 0
			velocity.z = 0
			_face_player()
			if dist > ATTACK_RANGE * 1.5:
				_state = State.CHASE
			elif _attack_timer <= 0.0:
				_do_attack()

func _move_toward_player() -> void:
	nav_agent.target_position = _player.global_position
	var next_pos := nav_agent.get_next_path_position()
	var to_next := next_pos - global_position
	to_next.y = 0.0
	# Fallback to direct movement if nav gives no useful direction (no nav mesh baked)
	if to_next.length_squared() < 0.04:
		to_next = _player.global_position - global_position
		to_next.y = 0.0
	if to_next.length_squared() < 0.001:
		return
	var dir := to_next.normalized()
	var speed := CRAWL_SPEED if _legs_lost >= 2 else (SPEED * 0.5 if _legs_lost == 1 else SPEED)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

func _face_player() -> void:
	var dir := _player.global_position - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		look_at(global_position + dir, Vector3.UP)

func _do_attack() -> void:
	_attack_timer = ATTACK_COOLDOWN
	if _player.has_method("take_damage"):
		_player.take_damage(ATTACK_DAMAGE)
	else:
		print("Brawler punches player for %.0f damage!" % ATTACK_DAMAGE)

func _build_segments() -> void:
	_is_dead = false
	segments.clear()

	for seg_name in SEGMENT_CONFIG:
		var cfg = SEGMENT_CONFIG[seg_name]
		var seg := VoxelSegment.new()
		seg.name = "VoxelSegment_" + seg_name
		seg.root_axis = cfg[2]
		seg.position = cfg[1]
		seg.rotation_degrees.x = 90
		add_child(seg)
		seg.load_from_vox(cfg[0])

		var area := Area3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		var aabb: AABB = seg.mesh_instance.get_aabb() if seg.mesh_instance.mesh else AABB()
		if aabb.size != Vector3.ZERO:
			shape.size = aabb.size
			col.position = aabb.get_center()
		else:
			shape.size = Vector3(0.4, 0.8, 0.4)
		col.shape = shape
		area.add_child(col)
		area.collision_layer = 2
		area.collision_mask = 0
		area.set_meta("voxel_segment", seg)
		seg.add_child(area)

		seg.detached.connect(_on_segment_detached.bind(seg_name))
		segments[seg_name] = seg

func _on_segment_detached(_seg: VoxelSegment, seg_name: String) -> void:
	if seg_name in ["torso", "head"] and not _is_dead:
		_die()
	elif seg_name in ["leg_l", "leg_r"]:
		_legs_lost += 1

func _die() -> void:
	_is_dead = true
	_state = State.DEAD
	velocity = Vector3.ZERO
	emit_signal("died")

	for node in get_tree().get_nodes_in_group("detached_limb"):
		node.queue_free()

	await get_tree().create_timer(1.5).timeout
	_reset()

func _reset() -> void:
	# Only free the voxel segments — CollisionShape3D and NavigationAgent3D stay
	for child in get_children():
		if child is VoxelSegment:
			child.queue_free()
	await get_tree().process_frame
	_legs_lost = 0
	_state = State.IDLE
	_build_segments()
