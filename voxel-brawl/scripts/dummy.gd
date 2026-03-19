# scripts/dummy.gd
class_name Dummy
extends Node3D

signal died

var segments: Dictionary = {}
var _is_dead: bool = false

# [vox_path, local_offset, root_axis]
# root_axis: direction in vox local space toward the attachment end.
# Vector3i.ZERO = never detaches (torso).
# Tune root_axis if limbs sever from the wrong end.
const SEGMENT_CONFIG := {
	"torso": ["res://assets/voxels/torso.vox", Vector3(-0.4, 2.2, -0.3), Vector3i.ZERO],
	"head":  ["res://assets/voxels/head.vox",  Vector3(-0.3, 2.8, -0.3), Vector3i(0, -1, 0)],
	"arm_l": ["res://assets/voxels/arm_l.vox", Vector3(-0.8, 2.2, -0.2), Vector3i(0, 1, 0)],
	"arm_r": ["res://assets/voxels/arm_r.vox", Vector3(0.4,  2.2, -0.2), Vector3i(0, 1, 0)],
	"leg_l": ["res://assets/voxels/leg_l.vox", Vector3(-0.4, 1.0, -0.2), Vector3i(0, 1, 0)],
	"leg_r": ["res://assets/voxels/leg_r.vox", Vector3(0.0,  1.0, -0.2), Vector3i(0, 1, 0)],
}

func _ready() -> void:
	_build_dummy()

func _process(_delta: float) -> void:
	if FovOverlay.instance != null:
		visible = FovOverlay.instance.is_visible_xz(
			Vector2(global_position.x, global_position.z)
		)

func _build_dummy() -> void:
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

func _die() -> void:
	_is_dead = true
	emit_signal("died")
	for node in get_tree().get_nodes_in_group("detached_limb"):
		node.queue_free()
	await get_tree().create_timer(1.5).timeout
	reset()

func reset() -> void:
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	_build_dummy()
