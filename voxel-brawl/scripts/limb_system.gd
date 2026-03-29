# scripts/limb_system.gd
# Owns segment hierarchy, structural integrity tracking, and ragdoll spawning.
# Added as a child of Player or Dummy after building the voxel body.
# Call initialize(segments) once all VoxelSegments are ready.
class_name LimbSystem
extends Node

const BREAK_THRESHOLD  := 0.5   # integrity < this + BLUNT hit → BROKEN (floppy ragdoll)
const DETACH_THRESHOLD := 0.0   # integrity <= this, any weapon → DETACH (severs)
const FALLOFF          := 3.0   # proximity weight drop-off rate from attachment joint
const BLUNT_MULTIPLIER := 2.0   # blunt weapons drain integrity twice as fast
const DEATH_VOXEL_THRESHOLD := 0.2  # fraction of torso+head voxels remaining → death

# Hierarchy: seg_name → { parent: String, children: Array[String], max_hp: float }
# Torso segments have max_hp 0.0 — they never detach via integrity.
const HIERARCHY: Dictionary = {
	"torso_bottom": { "parent": "",             "children": ["torso_top", "leg_r_upper", "leg_l_upper"], "max_hp": 0.0 },
	"torso_top":    { "parent": "torso_bottom", "children": ["head_bottom", "arm_r_upper", "arm_l_upper"], "max_hp": 0.0 },
	"head_bottom":  { "parent": "torso_top",    "children": ["head_top"],   "max_hp": 60.0 },
	"head_top":     { "parent": "head_bottom",  "children": [],             "max_hp": 60.0 },
	"arm_r_upper":  { "parent": "torso_top",    "children": ["arm_r_fore"], "max_hp": 120.0 },
	"arm_r_fore":   { "parent": "arm_r_upper",  "children": ["hand_r"],     "max_hp": 80.0 },
	"hand_r":       { "parent": "arm_r_fore",   "children": [],             "max_hp": 50.0 },
	"arm_l_upper":  { "parent": "torso_top",    "children": ["arm_l_fore"], "max_hp": 120.0 },
	"arm_l_fore":   { "parent": "arm_l_upper",  "children": ["hand_l"],     "max_hp": 80.0 },
	"hand_l":       { "parent": "arm_l_fore",   "children": [],             "max_hp": 50.0 },
	"leg_r_upper":  { "parent": "torso_bottom", "children": ["leg_r_fore"], "max_hp": 120.0 },
	"leg_r_fore":   { "parent": "leg_r_upper",  "children": [],             "max_hp": 80.0 },
	"leg_l_upper":  { "parent": "torso_bottom", "children": ["leg_l_fore"], "max_hp": 120.0 },
	"leg_l_fore":   { "parent": "leg_l_upper",  "children": [],             "max_hp": 80.0 },
}

var segments: Dictionary = {}   # seg_name (String) → VoxelSegment
var _integrity: Dictionary = {} # seg_name → float (1.0 = intact)
var _is_dead: bool = false

# Each entry: { "anchor": StaticBody3D, "bone_attach": Node3D, "root_seg": String }
var _broken_anchors: Array[Dictionary] = []

signal leg_lost(seg_name: String)
signal died

# Called by owner (Player/Dummy) after all VoxelSegments are built.
func initialize(seg_dict: Dictionary) -> void:
	segments = seg_dict
	_integrity.clear()
	for seg_name in HIERARCHY:
		_integrity[seg_name] = 1.0
	for seg_name in segments:
		var seg: VoxelSegment = segments[seg_name]
		seg.detached.connect(_on_segment_detached.bind(seg_name))

# Called by DamageManager after take_hit(). Drains integrity and checks thresholds.
func on_hit(seg: VoxelSegment, hit_pos_local: Vector3, damage: float, weapon_type: WeaponBase.WeaponType) -> void:
	var seg_name := _name_of(seg)
	if seg_name.is_empty() or not HIERARCHY.has(seg_name):
		return
	var max_hp: float = HIERARCHY[seg_name]["max_hp"]
	if max_hp <= 0.0:
		return  # torso — indestructible

	var dist := _dist_to_joint(seg, hit_pos_local)
	var prox := clampf(1.0 / (1.0 + dist * FALLOFF), 0.1, 1.0)
	var blunt_mult := BLUNT_MULTIPLIER if weapon_type == WeaponBase.WeaponType.BLUNT else 1.0
	_integrity[seg_name] = _integrity.get(seg_name, 1.0) - (damage / max_hp) * prox * blunt_mult

	var integrity: float = _integrity[seg_name]

	# BROKEN: floppy ragdoll while still attached (blunt only, not already broken)
	if weapon_type == WeaponBase.WeaponType.BLUNT and integrity < BREAK_THRESHOLD:
		if not seg.is_broken:
			_spawn_broken_ragdoll(seg_name)

	# DETACH: severs the segment (any weapon)
	if integrity <= DETACH_THRESHOLD and not seg.is_detached:
		seg.detach()

	_check_death_threshold()

func _check_death_threshold() -> void:
	if _is_dead:
		return
	const FATAL := ["torso_bottom", "torso_top", "head_bottom", "head_top"]
	var total_original := 0
	var total_current  := 0
	for seg_name in FATAL:
		var seg: VoxelSegment = segments.get(seg_name)
		if seg == null:
			continue
		total_original += seg.total_voxel_count
		total_current  += seg.current_voxel_count
	if total_original > 0 and float(total_current) / float(total_original) < DEATH_VOXEL_THRESHOLD:
		_die()

func _on_segment_detached(_seg: VoxelSegment, seg_name: String) -> void:
	# Fatal segments trigger full body collapse
	if seg_name in ["torso_bottom", "torso_top", "head_bottom", "head_top"] and not _is_dead:
		_die()
		return
	if not _is_dead:
		if seg_name in ["leg_r_upper", "leg_l_upper", "leg_r_fore", "leg_l_fore"]:
			emit_signal("leg_lost", seg_name)
		_spawn_detached_ragdoll(seg_name)

func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_spawn_death_ragdoll()
	emit_signal("died")

# --- Ragdoll primitives (implemented in Tasks 5–7) ---

func _spawn_broken_ragdoll(root_seg_name: String) -> void:
	var chain := _chain_downward(root_seg_name)
	var rbs: Dictionary = {}          # seg_name → RigidBody3D
	var joint_positions: Dictionary = {}  # seg_name → Vector3 (pre-cached before reparent)

	# Cache the root segment's BoneAttachment3D parent BEFORE any reparenting
	var root_seg: VoxelSegment = segments.get(root_seg_name)
	var root_bone_attach: Node3D = null
	if root_seg != null and root_seg.get_parent() is BoneAttachment3D:
		root_bone_attach = root_seg.get_parent()

	# Pre-cache joint world positions before reparenting changes the parent chain
	for seg_name in chain:
		var seg: VoxelSegment = segments.get(seg_name)
		if seg != null and not seg.is_detached and not seg.is_broken:
			joint_positions[seg_name] = _joint_world_pos(seg)

	for seg_name in chain:
		var seg: VoxelSegment = segments.get(seg_name)
		if seg == null or seg.is_detached or seg.is_broken:
			continue

		var rb := RigidBody3D.new()
		rb.mass = _get_mass(seg_name)
		rb.add_to_group("detached_limb")
		get_tree().root.add_child(rb)
		rb.global_transform = seg.global_transform

		rb.add_child(_make_box_col(seg))
		seg.reparent(rb, true)
		seg.is_broken = true
		rbs[seg_name] = rb

	if rbs.is_empty():
		return

	# Connect adjacent segments in chain with PinJoint3D using pre-cached positions
	for seg_name in chain:
		if not rbs.has(seg_name):
			continue
		var parent_name: String = HIERARCHY[seg_name]["parent"]
		if parent_name.is_empty() or not rbs.has(parent_name):
			continue
		if not joint_positions.has(seg_name):
			continue
		_make_pin_joint(joint_positions[seg_name], rbs[parent_name], rbs[seg_name])

	# Shoulder anchor: StaticBody3D pinned to root RB, position tracked to bone each tick
	if root_bone_attach != null and rbs.has(root_seg_name):
		var anchor := StaticBody3D.new()
		get_tree().root.add_child(anchor)
		anchor.global_position = root_bone_attach.global_position
		_make_pin_joint(root_bone_attach.global_position, anchor, rbs[root_seg_name])
		_broken_anchors.append({
			"anchor": anchor,
			"bone_attach": root_bone_attach,
			"root_seg": root_seg_name
		})

func _spawn_detached_ragdoll(root_seg_name: String) -> void:
	var root_seg: VoxelSegment = segments.get(root_seg_name)

	# Transition: was BROKEN, now DETACHED — remove shoulder anchor, apply impulse
	if root_seg != null and root_seg.is_broken:
		# Mark entire chain as detached so integrity checks short-circuit
		for seg_name in _chain_downward(root_seg_name):
			var seg: VoxelSegment = segments.get(seg_name)
			if seg != null and seg.is_broken:
				seg.is_detached = true
		# Remove shoulder anchor for this chain
		for i in range(_broken_anchors.size() - 1, -1, -1):
			if _broken_anchors[i]["root_seg"] == root_seg_name:
				if is_instance_valid(_broken_anchors[i]["anchor"]):
					_broken_anchors[i]["anchor"].queue_free()
				_broken_anchors.remove_at(i)
				break
		if root_seg.get_parent() is RigidBody3D:
			var rb := root_seg.get_parent() as RigidBody3D
			rb.apply_central_impulse(Vector3(randf_range(-3, 3), randf_range(2, 5), randf_range(-3, 3)))
			rb.apply_torque_impulse(Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)))
		return

	# Fresh detach — build RigidBody3D chain for root and all descendants
	var chain := _chain_downward(root_seg_name)
	var rbs: Dictionary = {}           # seg_name → RigidBody3D (new or existing)
	var joint_positions: Dictionary = {}   # seg_name → Vector3

	# Pre-cache joint world positions; collect existing RBs for already-broken segs
	for seg_name in chain:
		var seg: VoxelSegment = segments.get(seg_name)
		if seg == null:
			continue
		if seg.is_detached and seg_name != root_seg_name:
			continue
		joint_positions[seg_name] = _joint_world_pos(seg)
		# Broken segs already own an RB — reuse it, don't create a duplicate
		if seg.is_broken and seg.get_parent() is RigidBody3D:
			rbs[seg_name] = seg.get_parent() as RigidBody3D

	for seg_name in chain:
		var seg: VoxelSegment = segments.get(seg_name)
		if seg == null:
			continue
		if seg.is_detached and seg_name != root_seg_name:
			continue
		# Mark descendants as detached so connectivity checks don't re-fire
		if seg_name != root_seg_name:
			seg.is_detached = true
			for child in seg.get_children():
				if child is Area3D:
					(child as Area3D).collision_layer = 0
		# Already-broken segments own existing RBs — free their anchor and skip new RB
		if seg.is_broken:
			for i in range(_broken_anchors.size() - 1, -1, -1):
				if _broken_anchors[i]["root_seg"] == seg_name:
					if is_instance_valid(_broken_anchors[i]["anchor"]):
						_broken_anchors[i]["anchor"].queue_free()
					_broken_anchors.remove_at(i)
					break
			continue  # rbs[seg_name] already set in pre-cache loop above

		var rb := RigidBody3D.new()
		rb.mass = _get_mass(seg_name)
		rb.add_to_group("detached_limb")
		get_tree().root.add_child(rb)
		rb.global_transform = seg.global_transform

		rb.add_child(_make_box_col(seg))
		seg.reparent(rb, true)
		rbs[seg_name] = rb

	if rbs.is_empty():
		return

	# Connect adjacent segments in chain with PinJoint3D using pre-cached positions
	for seg_name in chain:
		if not rbs.has(seg_name):
			continue
		var parent_name: String = HIERARCHY[seg_name]["parent"]
		if parent_name.is_empty() or not rbs.has(parent_name):
			continue
		if not joint_positions.has(seg_name):
			continue
		_make_pin_joint(joint_positions[seg_name], rbs[parent_name], rbs[seg_name])

	# Apply outward impulse to the root — chain tumbles together
	if rbs.has(root_seg_name):
		rbs[root_seg_name].apply_central_impulse(
			Vector3(randf_range(-3, 3), randf_range(2, 5), randf_range(-3, 3))
		)
		rbs[root_seg_name].apply_torque_impulse(
			Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))
		)

func _spawn_death_ragdoll() -> void:
	pass  # implemented in Task 7

# --- Physics process: update shoulder anchors for broken limbs ---

func _physics_process(_delta: float) -> void:
	for i in range(_broken_anchors.size() - 1, -1, -1):
		var entry: Dictionary = _broken_anchors[i]
		if not is_instance_valid(entry["anchor"]) or not is_instance_valid(entry["bone_attach"]):
			_broken_anchors.remove_at(i)
			continue
		(entry["anchor"] as StaticBody3D).global_position = (entry["bone_attach"] as Node3D).global_position

# --- Shared helpers ---

func _name_of(seg: VoxelSegment) -> String:
	for seg_name in segments:
		if segments[seg_name] == seg:
			return seg_name
	return ""

func _dist_to_joint(seg: VoxelSegment, hit_pos_local: Vector3) -> float:
	if seg._root_voxels_cached.is_empty():
		return 0.0
	var sum := Vector3.ZERO
	for vp: Vector3i in seg._root_voxels_cached:
		sum += Vector3(vp) * VoxelSegment.VOXEL_SIZE
	return hit_pos_local.distance_to(sum / seg._root_voxels_cached.size())

# Returns all segment names from root_name downward (BFS, inclusive).
func _chain_downward(root_name: String) -> Array[String]:
	var chain: Array[String] = []
	var queue: Array[String] = [root_name]
	while not queue.is_empty():
		var cur := queue.pop_front()
		chain.append(cur)
		for child in HIERARCHY[cur]["children"]:
			queue.append(child)
	return chain

# Average world position of a segment's root (attachment) voxel row.
func _joint_world_pos(seg: VoxelSegment) -> Vector3:
	if seg._root_voxels_cached.is_empty():
		return seg.global_position
	var sum := Vector3.ZERO
	for vp: Vector3i in seg._root_voxels_cached:
		sum += seg.to_global(Vector3(vp) * VoxelSegment.VOXEL_SIZE)
	return sum / seg._root_voxels_cached.size()

func _make_box_col(seg: VoxelSegment) -> CollisionShape3D:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var raw := seg.mesh_instance.get_aabb().size if seg.mesh_instance.mesh else Vector3(0.3, 0.6, 0.3)
	box.size = raw.clamp(Vector3(0.05, 0.05, 0.05), Vector3(10.0, 10.0, 10.0))
	col.shape = box
	return col

func _make_pin_joint(world_pos: Vector3, body_a: PhysicsBody3D, body_b: PhysicsBody3D) -> PinJoint3D:
	var joint := PinJoint3D.new()
	get_tree().root.add_child(joint)
	joint.global_position = world_pos
	joint.node_a = joint.get_path_to(body_a)
	joint.node_b = joint.get_path_to(body_b)
	return joint

func _get_mass(seg_name: String) -> float:
	if seg_name in ["torso_bottom", "torso_top"]:
		return 3.0
	if seg_name in ["head_bottom", "head_top"]:
		return 1.0
	return 0.8
