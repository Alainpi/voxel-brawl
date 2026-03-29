# LimbSystem Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add LimbSystem to Player and Dummy — structural integrity meter, broken (floppy) limbs, detached limb ragdolls, and full death collapse.

**Architecture:** LimbSystem is a Node child of Player/Dummy that owns all ragdoll logic. DamageManager routes hits through it after take_hit(). VoxelSegment.detach() skips its standalone spawn when a LimbSystem meta is set, deferring chain ragdoll to LimbSystem. Broken limbs use a StaticBody3D shoulder anchor updated each physics tick to track the animated bone.

**Tech Stack:** Godot 4.3+, GDScript, RigidBody3D, PinJoint3D, StaticBody3D (shoulder anchor)

---

### Task 1: VoxelSegment prep

**Files:**
- Modify: `scripts/voxel_segment.gd`

- [ ] **Step 1: Add `is_broken` flag**

After `var is_detached: bool = false` (line 28), add:

```gdscript
var is_broken: bool = false
```

- [ ] **Step 2: Remove `if is_detached: return` from `rebuild_mesh()`**

Current (lines 124–127):
```gdscript
func rebuild_mesh() -> void:
	_pending_rebuild = false
	if is_detached:
		return
```

Replace with:
```gdscript
func rebuild_mesh() -> void:
	_pending_rebuild = false
```

Detached/broken segments reparented onto RigidBody3D must still rebuild when hit.

- [ ] **Step 3: Skip standalone spawn in `detach()` when LimbSystem is managing this segment**

In `detach()`, after `emit_signal("detached", self)` and before the existing RigidBody3D spawn block, add an early return:

```gdscript
func detach() -> void:
	if is_detached:
		return
	is_detached = true

	for child in get_children():
		if child is Area3D:
			child.collision_layer = 0

	emit_signal("detached", self)

	# LimbSystem handles ragdoll when present — skip standalone spawn
	if get_meta("limb_system", null) != null:
		return

	if voxel_data.is_empty():
		return  # nothing left to launch

	var rb := RigidBody3D.new()
	# ... rest of existing spawn code unchanged
```

- [ ] **Step 4: Commit**

```bash
git add scripts/voxel_segment.gd
git commit -m "feat: prep VoxelSegment for LimbSystem — is_broken flag, rebuild after ragdoll, skip standalone spawn"
```

---

### Task 2: DamageManager + weapon `weapon_type` plumbing

**Files:**
- Modify: `scripts/damage_manager.gd`
- Modify: `scripts/weapon_melee.gd`
- Modify: `scripts/weapon_bat.gd`
- Modify: `scripts/weapon_katana.gd`

- [ ] **Step 1: Add `weapon_type` param to `DamageManager.process_hit()` and call `on_hit()`**

Replace the entire function:

```gdscript
func process_hit(segment: VoxelSegment, hit_pos_local: Vector3, radius: float, damage: float, weapon_type: int = WeaponBase.WeaponType.SHARP) -> void:
	if multiplayer.is_server():
		segment.take_hit(hit_pos_local, radius, damage)
		var limb_system = segment.get_meta("limb_system", null)
		if limb_system != null:
			limb_system.on_hit(segment, hit_pos_local, damage, weapon_type)
```

- [ ] **Step 2: Pass `weapon_type` in `WeaponMelee._apply_hit()`**

```gdscript
func _apply_hit(seg: VoxelSegment, local_hit: Vector3) -> void:
	DamageManager.process_hit(seg, local_hit, voxel_radius, damage, weapon_type)
```

- [ ] **Step 3: Pass `weapon_type` in `WeaponBat._apply_hit()`**

```gdscript
func _apply_hit(seg: VoxelSegment, local_hit: Vector3) -> void:
	DamageManager.process_hit(seg, local_hit, voxel_radius, damage, weapon_type)
```

- [ ] **Step 4: Pass `weapon_type` in `WeaponKatana._apply_hit()`**

```gdscript
func _apply_hit(seg: VoxelSegment, local_hit: Vector3) -> void:
	DamageManager.process_hit(seg, local_hit, voxel_radius, damage, weapon_type)
```

- [ ] **Step 5: Run the game, verify no errors and combat still works**

Hit the dummy — voxels should carve normally. No script errors.

- [ ] **Step 6: Commit**

```bash
git add scripts/damage_manager.gd scripts/weapon_melee.gd scripts/weapon_bat.gd scripts/weapon_katana.gd
git commit -m "feat: thread weapon_type through DamageManager to LimbSystem"
```

---

### Task 3: LimbSystem core — hierarchy, integrity tracking, `on_hit`

**Files:**
- Create: `scripts/limb_system.gd`

- [ ] **Step 1: Create `scripts/limb_system.gd`**

```gdscript
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
var _broken_anchors: Array = []

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
func on_hit(seg: VoxelSegment, hit_pos_local: Vector3, damage: float, weapon_type: int) -> void:
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
	if seg_name in ["torso_top", "head_bottom", "head_top"] and not _is_dead:
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

func _spawn_broken_ragdoll(_root_seg_name: String) -> void:
	pass  # implemented in Task 5

func _spawn_detached_ragdoll(_root_seg_name: String) -> void:
	pass  # implemented in Task 6

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
```

- [ ] **Step 2: Run the game, verify no errors**

Open Godot, run the scene. LimbSystem is defined but not yet connected — no visible change, no errors expected.

- [ ] **Step 3: Commit**

```bash
git add scripts/limb_system.gd
git commit -m "feat: LimbSystem core — hierarchy dict, integrity drain, on_hit, stub ragdoll methods"
```

---

### Task 4: Player + Dummy integration

**Files:**
- Modify: `scripts/player.gd`
- Modify: `scripts/dummy.gd`

- [ ] **Step 1: Update `player.gd` `_build_voxel_body()` — remove old detached signal, wire LimbSystem**

In `_build_voxel_body()`, remove this line:
```gdscript
		seg.detached.connect(_on_player_segment_detached.bind(seg_name))
```

Then, just before the `if _weapon_anchor:` block at the end of `_build_voxel_body()`, add:
```gdscript
	var limb_system := LimbSystem.new()
	limb_system.name = "LimbSystem"
	add_child(limb_system)
	for seg_name in segments:
		segments[seg_name].set_meta("limb_system", limb_system)
	limb_system.initialize(segments)
	limb_system.leg_lost.connect(_on_leg_lost)
	limb_system.died.connect(_die)
```

- [ ] **Step 2: Replace `_on_player_segment_detached` with `_on_leg_lost` in `player.gd`**

Remove the old function:
```gdscript
func _on_player_segment_detached(_seg: VoxelSegment, seg_name: String) -> void:
	if seg_name in ["torso_top", "head_bottom", "head_top"] and not _is_dead:
		_die()
	elif seg_name in ["leg_r_upper", "leg_l_upper"]:
		_legs_lost += 2
		print("Player lost a full leg! Speed heavily reduced.")
	elif seg_name in ["leg_r_fore", "leg_l_fore"]:
		_legs_lost += 1
		print("Player lost a lower leg! Speed reduced.")
```

Add the new function:
```gdscript
func _on_leg_lost(seg_name: String) -> void:
	if seg_name in ["leg_r_upper", "leg_l_upper"]:
		_legs_lost += 2
	elif seg_name in ["leg_r_fore", "leg_l_fore"]:
		_legs_lost += 1
```

- [ ] **Step 3: Update `dummy.gd` `_build_dummy()` — same pattern**

Remove:
```gdscript
		seg.detached.connect(_on_segment_detached.bind(seg_name))
```

Just before `if anim_player:` at the end of `_build_dummy()`, add:
```gdscript
	var limb_system := LimbSystem.new()
	limb_system.name = "LimbSystem"
	add_child(limb_system)
	for seg_name in segments:
		segments[seg_name].set_meta("limb_system", limb_system)
	limb_system.initialize(segments)
	limb_system.died.connect(_die)
```

Remove the old `_on_segment_detached` function from `dummy.gd`:
```gdscript
func _on_segment_detached(_seg: VoxelSegment, seg_name: String) -> void:
	if seg_name in ["torso_bottom", "torso_top", "head_bottom", "head_top"] and not _is_dead:
		_die()
```

- [ ] **Step 4: Clean up old LimbSystem on dummy reset**

In `_build_dummy()`, just after `_is_dead = false` and before `segments.clear()`, add:
```gdscript
	var old_ls := get_node_or_null("LimbSystem")
	if old_ls != null:
		old_ls.queue_free()
```

- [ ] **Step 5: Run the game — verify segments still appear and combat still works**

Open Godot, run the scene. Dummy and player should look identical to before. Hit the dummy — voxels carve. No console errors. Check Output panel carefully.

- [ ] **Step 6: Commit**

```bash
git add scripts/player.gd scripts/dummy.gd
git commit -m "feat: integrate LimbSystem into Player and Dummy — wire segments, signals, leg_lost"
```

---

### Task 5: Broken ragdoll — floppy attached limb

**Files:**
- Modify: `scripts/limb_system.gd`

- [ ] **Step 1: Replace the stub `_spawn_broken_ragdoll()` with the full implementation**

```gdscript
func _spawn_broken_ragdoll(root_seg_name: String) -> void:
	var chain := _chain_downward(root_seg_name)
	var rbs: Dictionary = {}  # seg_name → RigidBody3D

	# Cache the root segment's BoneAttachment3D parent BEFORE any reparenting
	var root_seg: VoxelSegment = segments.get(root_seg_name)
	var root_bone_attach: Node3D = null
	if root_seg != null and root_seg.get_parent() is BoneAttachment3D:
		root_bone_attach = root_seg.get_parent()

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

	# Connect adjacent segments in chain with PinJoint3D
	for seg_name in chain:
		if not rbs.has(seg_name):
			continue
		var parent_name: String = HIERARCHY[seg_name]["parent"]
		if parent_name.is_empty() or not rbs.has(parent_name):
			continue
		var seg: VoxelSegment = segments.get(seg_name)
		if seg == null:
			continue
		_make_pin_joint(_joint_world_pos(seg), rbs[parent_name], rbs[seg_name])

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
```

- [ ] **Step 2: In-game test — broken arm with bat**

Run the game. Equip bat. Hit the dummy's arm near the shoulder repeatedly (~5–8 hits). Expect: arm droops and flops from the shoulder while the dummy's idle animation continues.

If BREAK_THRESHOLD triggers too quickly (after 1–2 hits), lower `BREAK_THRESHOLD` to 0.35. If it never triggers, increase `BLUNT_MULTIPLIER` to 3.0 or lower `HIERARCHY["arm_r_upper"]["max_hp"]` to 80.

- [ ] **Step 3: Commit**

```bash
git add scripts/limb_system.gd
git commit -m "feat: broken ragdoll — floppy limb chain with shoulder anchor"
```

---

### Task 6: Detached ragdoll — cascade severing

**Files:**
- Modify: `scripts/limb_system.gd`

- [ ] **Step 1: Replace the stub `_spawn_detached_ragdoll()` with the full implementation**

```gdscript
func _spawn_detached_ragdoll(root_seg_name: String) -> void:
	var root_seg: VoxelSegment = segments.get(root_seg_name)

	# Transition: was BROKEN, now DETACHED — remove shoulder anchor, apply impulse
	if root_seg != null and root_seg.is_broken:
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
	var rbs: Dictionary = {}  # seg_name → RigidBody3D

	for seg_name in chain:
		var seg: VoxelSegment = segments.get(seg_name)
		if seg == null or seg.is_detached:
			continue
		# Mark descendants as detached so their connectivity checks don't re-fire
		if seg_name != root_seg_name:
			seg.is_detached = true
			for child in seg.get_children():
				if child is Area3D:
					(child as Area3D).collision_layer = 0

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

	# Connect adjacent segments in chain with PinJoint3D
	for seg_name in chain:
		if not rbs.has(seg_name):
			continue
		var parent_name: String = HIERARCHY[seg_name]["parent"]
		if parent_name.is_empty() or not rbs.has(parent_name):
			continue
		var seg: VoxelSegment = segments.get(seg_name)
		if seg == null:
			continue
		_make_pin_joint(_joint_world_pos(seg), rbs[parent_name], rbs[seg_name])

	# Apply outward impulse to the root — chain tumbles together
	if rbs.has(root_seg_name):
		rbs[root_seg_name].apply_central_impulse(
			Vector3(randf_range(-3, 3), randf_range(2, 5), randf_range(-3, 3))
		)
		rbs[root_seg_name].apply_torque_impulse(
			Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))
		)
```

- [ ] **Step 2: In-game test — arm severed by katana**

Equip katana, use thrust stance. Hit the dummy's arm shoulder area with multiple thrusts. Expect: arm (upper + fore + hand as a connected floppy chain) flies off. Remaining body continues animating.

- [ ] **Step 3: In-game test — broken then severed**

Equip bat, break the arm (droops). Switch to katana, thrust into the broken arm. Expect: broken arm flies off, shoulder anchor disappears cleanly (arm no longer tracked by any anchor).

- [ ] **Step 4: Commit**

```bash
git add scripts/limb_system.gd
git commit -m "feat: detached ragdoll — cascade chain sever with impulse, broken-to-detached transition"
```

---

### Task 7: Death ragdoll — full body collapse

**Files:**
- Modify: `scripts/limb_system.gd`
- Modify: `scripts/player.gd`

- [ ] **Step 1: Replace the stub `_spawn_death_ragdoll()` with the full implementation**

```gdscript
func _spawn_death_ragdoll() -> void:
	var rbs: Dictionary = {}  # seg_name → RigidBody3D

	# Build or reuse RigidBody3D for every segment
	for seg_name in HIERARCHY:
		var seg: VoxelSegment = segments.get(seg_name)
		if seg == null:
			continue
		# Reuse existing RB if segment was already broken/detached
		if seg.get_parent() is RigidBody3D:
			rbs[seg_name] = seg.get_parent() as RigidBody3D
			continue
		if seg.is_detached:
			continue  # already flew off as its own RB — leave it

		var rb := RigidBody3D.new()
		rb.mass = _get_mass(seg_name)
		rb.add_to_group("detached_limb")
		get_tree().root.add_child(rb)
		rb.global_transform = seg.global_transform

		rb.add_child(_make_box_col(seg))
		seg.reparent(rb, true)
		seg.is_broken = true
		rbs[seg_name] = rb

	# Remove all shoulder anchors — body is now fully free
	for entry in _broken_anchors:
		if is_instance_valid(entry["anchor"]):
			(entry["anchor"] as Node3D).queue_free()
	_broken_anchors.clear()

	# Connect full hierarchy with PinJoint3D (gravity drives the collapse — no impulse)
	for seg_name in HIERARCHY:
		if not rbs.has(seg_name):
			continue
		var parent_name: String = HIERARCHY[seg_name]["parent"]
		if parent_name.is_empty() or not rbs.has(parent_name):
			continue
		var seg: VoxelSegment = segments.get(seg_name)
		if seg == null:
			continue
		_make_pin_joint(_joint_world_pos(seg), rbs[parent_name], rbs[seg_name])
```

- [ ] **Step 2: Lock out movement in `player.gd` `_physics_process` on death**

Add at the very top of `_physics_process`, after the `_cam_velocity` / `_cam_drag_x` camera update block (keep camera following even after death), but before movement input:

```gdscript
	if _is_dead:
		return
```

Place it after these lines:
```gdscript
	if _cam_rotating and delta > 0.0:
		_cam_velocity = _cam_drag_x * CAM_ROT_SENS / delta
	else:
		_cam_velocity = lerp(_cam_velocity, 0.0, CAM_ROT_FRICTION * delta)
	_cam_drag_x = 0.0
	camera_pivot.rotation.y += _cam_velocity * delta

	camera_pivot.global_position = camera_pivot.global_position.lerp(
		global_position, CAM_FOLLOW_SPEED * delta
	)

	if _is_dead:
		return
```

This keeps the camera following the collapsing ragdoll while stopping all player input.

- [ ] **Step 3: In-game test — death by voxel depletion**

Equip bat. Pound the dummy's torso until `DEATH_VOXEL_THRESHOLD` is reached (torso+head voxels drop to 20%). Expect: full body collapses — all segments fall as a connected pile. Dummy resets after 1.5 seconds.

- [ ] **Step 4: In-game test — death by fatal segment detach**

Equip katana, thrust stance. Hit dummy's head multiple times. When `head_bottom` detaches, expect: immediate full body collapse.

- [ ] **Step 5: In-game test — player death**

Get hit until player's head detaches (katana thrust from enemy is fastest way to test this — temporarily lower `HIERARCHY["head_bottom"]["max_hp"]` to 20 for testing). Expect: player collapses, movement locked, camera still pans to follow the body.

- [ ] **Step 6: Commit**

```bash
git add scripts/limb_system.gd scripts/player.gd
git commit -m "feat: death ragdoll — full body collapse on fatal segment loss or voxel depletion"
```

---

## Spec Coverage Check

| Spec Requirement | Task |
|---|---|
| LimbSystem node on each character | Task 4 |
| `segment_max_hp` per segment | Task 3 (HIERARCHY const) |
| Structural integrity drain formula (proximity, blunt multiplier) | Task 3 (`on_hit`) |
| `BREAK_THRESHOLD = 0.5`, BLUNT only → BROKEN ragdoll | Task 5 |
| `DETACH_THRESHOLD = 0.0`, any weapon → DETACH | Task 3 (`on_hit`) |
| BROKEN: floppy chain with shoulder anchor | Task 5 |
| DETACHED: chain with impulse, no anchor | Task 6 |
| BROKEN → DETACHED transition | Task 6 |
| Cascade: descendants follow parent detach | Task 6 (chain_downward) |
| DEATH: full body collapse on fatal segment | Task 7 |
| DEATH: voxel count threshold | Task 3 (`_check_death_threshold`) |
| VoxelSegment rebuild_mesh after ragdoll | Task 1 |
| `weapon_type` through DamageManager | Task 2 |
| `is_broken: bool` on VoxelSegment | Task 1 |
| Player movement lockout on death | Task 7 |
| LimbSystem.`leg_lost` → player speed penalty | Task 4 |
| `seg.set_meta("limb_system", ...)` | Task 4 |
