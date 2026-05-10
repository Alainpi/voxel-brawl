# scripts/dummy.gd
class_name Dummy
extends Node3D

signal died

var segments: Dictionary = {}
var _is_dead: bool = false
var _attachments: Array = []
var _limb_system: LimbSystem = null
var _health_system: HealthSystem = null
var _head_look_target: Marker3D = null  # tracks player; updated in _process

@onready var anim_player: AnimationPlayer = $PlayerModel.find_child("AnimationPlayer", true, false) as AnimationPlayer
@onready var anim_tree: AnimationTree = $PlayerModel.find_child("AnimationTree", true, false) as AnimationTree

# Mirrors PLAYER_SEGMENT_CONFIG from player.gd — same rig, same offsets
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

func _ready() -> void:
	_head_look_target = Marker3D.new()
	_head_look_target.name = "HeadLookTarget"
	add_child(_head_look_target)
	call_deferred("_build_dummy")

func _process(_delta: float) -> void:
	if FovOverlay.instance != null:
		visible = FovOverlay.instance.is_visible_xz(
			Vector2(global_position.x, global_position.z)
		)
	# Point dummy's head toward nearest player
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and _head_look_target != null:
		var p := players[0] as Node3D
		_head_look_target.global_position = p.global_position + Vector3.UP * 1.0

func _build_dummy() -> void:
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
		push_error("Dummy: Skeleton3D not found in PlayerModel")
		return

	for mesh in $PlayerModel.find_children("*", "MeshInstance3D", true, false):
		mesh.visible = false

	for seg_name in SEGMENT_CONFIG:
		var cfg = SEGMENT_CONFIG[seg_name]
		var vox_path: String = cfg[0]
		var bone_name: String = cfg[1]

		var bone_idx := skeleton.find_bone(bone_name)
		if bone_idx == -1:
			push_warning("Dummy: bone not found: " + bone_name)
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

	_health_system = HealthSystem.new()
	_health_system.name = "HealthSystem"
	add_child(_health_system)
	for seg_name in segments:
		segments[seg_name].set_meta("health_system", _health_system)
	_health_system.initialize(segments)
	_health_system.died.connect(_die)

	# AnimationTree — blend position stays at zero (idle + breathe)
	if anim_tree and anim_player:
		AnimTreeSetup.build_and_activate(anim_tree, anim_player)
		anim_tree.set("parameters/locomotion/blend_position", Vector2.ZERO)

	_setup_skeleton_modifiers(skeleton)


func _setup_skeleton_modifiers(skeleton: Skeleton3D) -> void:
	var look_path := skeleton.get_path_to(_head_look_target) if _head_look_target else NodePath("")

	var la_bottom := LookAtModifier3D.new()
	la_bottom.name = "LookAt_head_bottom"
	la_bottom.bone_name = "head_bottom"
	la_bottom.target_node = look_path
	la_bottom.forward_axis = SkeletonModifier3D.BONE_AXIS_MINUS_Z
	la_bottom.use_angle_limitation = true
	la_bottom.symmetry_limitation = true
	la_bottom.primary_limit_angle = deg_to_rad(60.0)
	la_bottom.secondary_limit_angle = deg_to_rad(40.0)
	skeleton.add_child(la_bottom)

	var la_top := LookAtModifier3D.new()
	la_top.name = "LookAt_head_top"
	la_top.bone_name = "head_top"
	la_top.target_node = look_path
	la_top.forward_axis = SkeletonModifier3D.BONE_AXIS_MINUS_Z
	la_top.use_angle_limitation = true
	la_top.symmetry_limitation = true
	la_top.primary_limit_angle = deg_to_rad(40.0)
	la_top.secondary_limit_angle = deg_to_rad(25.0)
	skeleton.add_child(la_top)

	# Dummy foot IK always active (always grounded)
	var foot_r := Marker3D.new()
	foot_r.name = "FootTargetR"
	add_child(foot_r)
	var foot_l := Marker3D.new()
	foot_l.name = "FootTargetL"
	add_child(foot_l)
	var ik_r := TwoBoneIK3D.new()
	ik_r.name = "FootIK_R"
	ik_r.setting_count = 1
	ik_r.set_root_bone_name(0, "leg_r_upper")
	ik_r.set_middle_bone_name(0, "leg_r_fore")
	ik_r.set_use_virtual_end(0, true)
	ik_r.set_pole_direction(0, SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_Z)
	ik_r.set_target_node(0, skeleton.get_path_to(foot_r))
	skeleton.add_child(ik_r)
	var ik_l := TwoBoneIK3D.new()
	ik_l.name = "FootIK_L"
	ik_l.setting_count = 1
	ik_l.set_root_bone_name(0, "leg_l_upper")
	ik_l.set_middle_bone_name(0, "leg_l_fore")
	ik_l.set_use_virtual_end(0, true)
	ik_l.set_pole_direction(0, SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_Z)
	ik_l.set_target_node(0, skeleton.get_path_to(foot_l))
	skeleton.add_child(ik_l)


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	if _limb_system != null:
		_limb_system.die()
	emit_signal("died")
	for node in get_tree().get_nodes_in_group("detached_limb"):
		node.queue_free()
	await get_tree().create_timer(1.5).timeout
	reset()

func reset() -> void:
	await get_tree().process_frame
	_build_dummy()
