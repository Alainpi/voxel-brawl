# scripts/brawler.gd
class_name Brawler
extends CharacterBody3D

signal died

const SPEED        := 3.0
const GRAVITY      := 9.8
const CHASE_RANGE  := 15.0
const ATTACK_RANGE := 1.8
const ATTACK_COOLDOWN := 1.5
const CRAWL_SPEED  := 1.2

# [vox_path, bone_name, position_offset, attach_rot_x, attach_rot_z, scale, root_axis, seg_rot_x, seg_rot_y, bone_vox_path]
# bone_vox_path: authored bone .vox loaded lazily when flesh drops below BONE_REVEAL_THRESHOLD (Option A)
const SEGMENT_CONFIG := {
	"torso_bottom": ["res://assets/voxels/torso_bottom.vox", "torso_bottom", Vector3(-1.0,  0.0, -0.4), -90, 0, Vector3(1,1,1),  Vector3i.ZERO,    0,   0,   "res://assets/voxels/spine_bottom.vox"],
	"torso_top":    ["res://assets/voxels/torso_top.vox",    "torso_top",    Vector3(-1.0,  0.0, -0.4), -90, 0, Vector3(1,1,1),  Vector3i(0,-1,0), 0,   0,   "res://assets/voxels/spine_top.vox"],
	"head_bottom":  ["res://assets/voxels/head_bottom.vox",  "head_bottom",  Vector3(-0.9,  0.0,  0.8), -90, 0, Vector3(1,1,-1), Vector3i(0,-1,0), 0,   0,   "res://assets/voxels/skull_bottom.vox"],
	"head_top":     ["res://assets/voxels/head_top.vox",     "head_top",     Vector3(-0.9,  0.0,  0.8), -90, 0, Vector3(1,1,-1), Vector3i(0,-1,0), 0,   0,   "res://assets/voxels/skull_top.vox"],
	"arm_r_upper":  ["res://assets/voxels/arm_r_upper.vox",  "arm_r_upper",  Vector3(-0.44, 1.65, 0.3), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  180, 0,   "res://assets/voxels/humerus_r.vox"],
	"arm_r_fore":   ["res://assets/voxels/arm_r_fore.vox",   "arm_r_fore",   Vector3(-0.44, 0.0, -0.4), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  0,   0,   "res://assets/voxels/radius_r.vox"],
	"hand_r":       ["res://assets/voxels/hand_r.vox",       "hand_r",       Vector3( 0.2,  0.7, -0.4), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  180, 180, "res://assets/voxels/metacarpal_r.vox"],
	"arm_l_upper":  ["res://assets/voxels/arm_l_upper.vox",  "arm_l_upper",  Vector3(-0.44, 1.65, 0.3), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  180, 0,   "res://assets/voxels/humerus_l.vox"],
	"arm_l_fore":   ["res://assets/voxels/arm_l_fore.vox",   "arm_l_fore",   Vector3(-0.44, 0.0, -0.4), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  0,   0,   "res://assets/voxels/radius_l.vox"],
	"hand_l":       ["res://assets/voxels/hand_l.vox",       "hand_l",       Vector3( 0.2,  0.7, -0.4), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  180, 180, "res://assets/voxels/metacarpal_l.vox"],
	"leg_r_upper":  ["res://assets/voxels/leg_r_upper.vox",  "leg_r_upper",  Vector3(-0.35, 0.0, -0.5), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  0,   0,   "res://assets/voxels/femur_r.vox"],
	"leg_r_fore":   ["res://assets/voxels/leg_r_fore.vox",   "leg_r_fore",   Vector3(-0.35, 0.0, -0.5), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  0,   0,   "res://assets/voxels/tibia_r.vox"],
	"leg_l_upper":  ["res://assets/voxels/leg_l_upper.vox",  "leg_l_upper",  Vector3(-0.45, 0.0, -0.3), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  0,   0,   "res://assets/voxels/femur_l.vox"],
	"leg_l_fore":   ["res://assets/voxels/leg_l_fore.vox",   "leg_l_fore",   Vector3(-0.45, 0.0, -0.3), -90, 0, Vector3(1,1,1),  Vector3i(0,1,0),  0,   0,   "res://assets/voxels/tibia_l.vox"],
}

enum State { IDLE, CHASE, ATTACK, DEAD }

var segments: Dictionary = {}
var _state: State = State.IDLE
var _is_dead: bool = false
var _is_attacking: bool = false
var _attack_timer: float = 0.0
var _lost_legs: Dictionary = {}
var _player: CharacterBody3D = null
var _attachments: Array = []
var _fists: WeaponFists = null
var _limb_system: LimbSystem = null
var _health_system: HealthSystem = null

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var anim_player: AnimationPlayer = $PlayerModel.find_child("AnimationPlayer", true, false) as AnimationPlayer

func _ready() -> void:
	call_deferred("_build_body")
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
	_update_animation()
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

func _update_animation() -> void:
	if _is_attacking or anim_player == null:
		return
	var moving := velocity.length_squared() > 0.01
	var target := "walk" if moving else "idle"
	if anim_player.current_animation != target:
		anim_player.play(target)

func _move_toward_player() -> void:
	nav_agent.target_position = _player.global_position
	var next_pos := nav_agent.get_next_path_position()
	var to_next := next_pos - global_position
	to_next.y = 0.0
	if to_next.length_squared() < 0.04:
		to_next = _player.global_position - global_position
		to_next.y = 0.0
	if to_next.length_squared() < 0.001:
		return
	var dir := to_next.normalized()
	var leg_mult := _leg_loss_speed_multiplier()
	var speed := CRAWL_SPEED if leg_mult < 0.0 else SPEED * leg_mult
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

func _face_player() -> void:
	var dir := _player.global_position - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		look_at(global_position + dir, Vector3.UP)

func _do_attack() -> void:
	_attack_timer = ATTACK_COOLDOWN
	if _fists != null:
		_fists.request_attack()

# --- Player interface (called by WeaponMelee) ---

func play_attack_anim(_prefix: String) -> void:
	var stances := ["punch_low", "punch_mid", "punch_high"]
	var anim: String = stances[randi() % stances.size()]
	_is_attacking = true
	if anim_player:
		anim_player.stop()
		anim_player.play(anim)

func trigger_hit_shake() -> void:
	pass

func trigger_crosshair_recoil() -> void:
	pass

# --- Body building ---

func _build_body() -> void:
	_is_dead = false
	var old_ls := get_node_or_null("LimbSystem")
	if old_ls != null:
		old_ls.queue_free()
	var old_hs := get_node_or_null("HealthSystem")
	if old_hs != null:
		old_hs.queue_free()
	segments.clear()

	for attach in _attachments:
		if is_instance_valid(attach):
			attach.queue_free()
	_attachments.clear()

	var skeleton: Skeleton3D = $PlayerModel.find_child("Skeleton3D", true, false)
	if skeleton == null:
		push_error("Brawler: Skeleton3D not found in PlayerModel")
		return

	for mesh in $PlayerModel.find_children("*", "MeshInstance3D", true, false):
		mesh.visible = false

	for seg_name in SEGMENT_CONFIG:
		var cfg = SEGMENT_CONFIG[seg_name]
		var vox_path: String = cfg[0]
		var bone_name: String = cfg[1]

		var bone_idx := skeleton.find_bone(bone_name)
		if bone_idx == -1:
			push_warning("Brawler: bone not found: " + bone_name)
			continue

		var attach := BoneAttachment3D.new()
		attach.bone_name = bone_name
		attach.bone_idx = bone_idx
		attach.rotation_degrees = Vector3(cfg[3], 0.0, cfg[4])
		skeleton.add_child(attach)
		_attachments.append(attach)

		var seg := VoxelSegment.new()
		seg.name = "VoxelSegment_" + seg_name
		seg.root_axis = cfg[6]
		seg.position = cfg[2]
		seg.scale = cfg[5]
		seg.rotation_degrees = Vector3(cfg[7], cfg[8], 0.0)
		seg._bone_vox_path = cfg[9]
		attach.add_child(seg)
		seg.load_from_vox(vox_path)

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

		segments[seg_name] = seg

	_limb_system = LimbSystem.new()
	_limb_system.name = "LimbSystem"
	add_child(_limb_system)
	for seg_name in segments:
		segments[seg_name].set_meta("limb_system", _limb_system)
	_limb_system.initialize(segments)
	_limb_system.leg_lost.connect(_on_leg_lost)

	_health_system = HealthSystem.new()
	_health_system.name = "HealthSystem"
	add_child(_health_system)
	for seg_name in segments:
		segments[seg_name].set_meta("health_system", _health_system)
	_health_system.initialize(segments)
	_health_system.limb_system = _limb_system
	_health_system.died.connect(_die)

	if anim_player:
		anim_player.animation_finished.connect(_on_anim_finished)
		anim_player.play("idle")

	_setup_fists()

func _setup_fists() -> void:
	if is_instance_valid(_fists):
		_fists.queue_free()
	_fists = WeaponFists.new()
	_fists.name = "WeaponFists"
	_fists._player = self          # pre-set before add_child so WeaponBase._ready() skips path lookup
	_fists.is_player_controlled = false
	var audio := AudioStreamPlayer3D.new()
	audio.name = "AudioStreamPlayer3D"
	_fists.add_child(audio)        # must exist before _fists enters tree (@onready in WeaponMelee)
	# Parent to hand_r bone attachment so the hitbox follows the punch animation
	var hand_attach = segments["hand_r"].get_parent()
	hand_attach.add_child(_fists)

func _on_anim_finished(_anim_name: String) -> void:
	_is_attacking = false

func _on_leg_lost(seg_name: String) -> void:
	_lost_legs[seg_name] = true

func _leg_loss_speed_multiplier() -> float:
	var r_upper := _lost_legs.has("leg_r_upper")
	var l_upper := _lost_legs.has("leg_l_upper")
	var r_fore  := _lost_legs.has("leg_r_fore")
	var l_fore  := _lost_legs.has("leg_l_fore")
	if (r_upper and l_upper) or (r_upper and l_fore) or (l_upper and r_fore) or (r_fore and l_fore):
		return -1.0
	if r_upper or l_upper:
		return 0.5
	if r_fore or l_fore:
		return 0.75
	return 1.0

# --- Death & reset ---

func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_state = State.DEAD
	velocity = Vector3.ZERO
	if _limb_system != null:
		_limb_system.die()
	emit_signal("died")
	for node in get_tree().get_nodes_in_group("detached_limb"):
		node.queue_free()
	await get_tree().create_timer(1.5).timeout
	_reset()

func _reset() -> void:
	var old_ls := get_node_or_null("LimbSystem")
	if old_ls != null:
		old_ls.queue_free()
	var old_hs := get_node_or_null("HealthSystem")
	if old_hs != null:
		old_hs.queue_free()
	for attach in _attachments:
		if is_instance_valid(attach):
			attach.queue_free()
	_attachments.clear()
	segments.clear()
	if is_instance_valid(_fists):
		_fists.queue_free()
		_fists = null
	if anim_player and anim_player.animation_finished.is_connected(_on_anim_finished):
		anim_player.animation_finished.disconnect(_on_anim_finished)
	await get_tree().process_frame
	_lost_legs.clear()
	_is_attacking = false
	_is_dead = false
	_state = State.IDLE
	_build_body()
