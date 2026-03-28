# Limb System Design — Structural Integrity, Ragdoll, Cascade Detachment

**Date:** 2026-03-28
**Status:** Approved

---

## Overview

A `LimbSystem` node on each character owns segment hierarchy, structural integrity tracking, and ragdoll spawning. VoxelSegment stays focused on voxels and mesh. DamageManager routes hits through LimbSystem after applying voxel damage.

---

## Architecture

```
Player / Brawler (CharacterBody3D)
├── ... (existing nodes)
├── LimbSystem (Node — script: limb_system.gd)
└── [BoneAttachment3D nodes → VoxelSegment nodes]
```

### Data flow per hit

1. Weapon calls `DamageManager.process_hit(seg, hit_pos_local, radius, damage, weapon_type)`
2. DamageManager calls `seg.take_hit()` — voxel destruction + connectivity check (existing)
3. DamageManager calls `seg.get_meta("limb_system").on_hit(seg, hit_pos_local, damage, weapon_type)`
4. LimbSystem updates structural integrity and checks thresholds
5. If VoxelSegment's connectivity check independently fires `detached` signal, LimbSystem handles cascade and ragdoll spawning

---

## Segment Hierarchy

Defined as a static dictionary in LimbSystem. Each entry: `segment_name → { parent, children, max_hp }`.

```
torso_bottom   parent: none (root — never detaches)
  torso_top    parent: torso_bottom
    head_bottom  parent: torso_top
      head_top   parent: head_bottom
    arm_r_upper  parent: torso_top
      arm_r_fore   parent: arm_r_upper
        hand_r     parent: arm_r_fore
    arm_l_upper  parent: torso_top
      arm_l_fore   parent: arm_l_upper
        hand_l     parent: arm_l_fore
  leg_r_upper  parent: torso_bottom
    leg_r_fore   parent: leg_r_upper
  leg_l_upper  parent: torso_bottom
    leg_l_fore   parent: leg_l_upper
```

### segment_max_hp (tunable starting values)

| Segment | max_hp |
|---|---|
| arm_r/l_upper, leg_r/l_upper | 120 |
| arm_r/l_fore, leg_r/l_fore | 80 |
| hand_r/l | 50 |
| head_bottom / head_top | 60 |
| torso_bottom / torso_top | — (no detach) |

---

## Structural Integrity Meter

Each segment has `structural_integrity: float = 1.0` tracked in LimbSystem.

### Drain formula (per hit)

```
proximity_weight = clamp(1.0 / (1.0 + distance_to_joint * FALLOFF), 0.1, 1.0)
blunt_multiplier = 2.0 if weapon_type == BLUNT else 1.0
drain = (damage / segment_max_hp) * proximity_weight * blunt_multiplier
structural_integrity -= drain
```

- `distance_to_joint` — distance in segment local space from `hit_pos_local` to the average position of `_root_voxels_cached` (the attachment row, already computed by VoxelSegment)
- `FALLOFF` — tunable constant, start at 3.0
- `BLUNT_MULTIPLIER` — 2.0 (blunt weapons drain integrity twice as fast)

### Thresholds — two separate outcomes, not sequential

| Threshold | Condition | Outcome |
|---|---|---|
| `BREAK_THRESHOLD = 0.5` | integrity < 0.5 AND weapon_type == BLUNT | BROKEN — limb ragdolls while attached |
| `DETACH_THRESHOLD = 0.0` | integrity <= 0.0, any weapon | DETACH — limb severs and flies off |

A BROKEN segment can become DETACHED if integrity continues draining to 0. BROKEN alone does not force detachment.

The existing connectivity check in VoxelSegment (`root_ratio <= 0.3`) remains active and can independently trigger detachment regardless of integrity.

---

## Ragdoll Implementation

All three scenarios share the same primitive:
- Create a RigidBody3D at the segment's current global_transform
- Reparent the VoxelSegment node onto it (preserves `to_local()` for hit detection)
- Connect adjacent segments in the chain with PinJoint3D at the anatomical joint position (average world position of the child segment's root voxel row)

### BROKEN — floppy limb, still attached

1. Collect chain from triggering segment downward (e.g. arm_r_upper → arm_r_fore → hand_r)
2. Create RigidBody3D per segment; reparent VoxelSegment onto it
3. Connect segments with PinJoint3D at each inter-segment joint
4. Create a **shoulder anchor** (plain Node3D); LimbSystem updates its global_position every `_physics_process` to track the BoneAttachment3D's position
5. PinJoint3D at shoulder connects anchor → root segment's RigidBody3D
6. Set `seg.is_broken = true` on each segment in chain

Result: arm droops and flops from the shoulder joint while the character keeps moving.

### DETACHED — flies off as connected chain

Same as BROKEN, steps 1–3 only. No shoulder anchor. Apply outward impulse to the root segment's RigidBody3D. PinJoint3D between segments keeps the chain connected but floppy as it tumbles.

### DEATH — full body collapse

Triggered when the character's total remaining voxel count across torso/head segments drops below a threshold (e.g. 20% of combined original count), or when a fatal segment (torso_top, head_bottom, head_top) detaches.

1. All 14 segments get RigidBody3D + VoxelSegment reparented
2. Full hierarchy connected with PinJoint3D following the hierarchy definition
3. No anchors, no impulse — gravity only
4. CharacterBody3D movement disabled (`_is_dead = true`)
5. Mass: torso segments = 3.0, limb segments = 0.8, head = 1.0

### Destructibility after ragdoll

VoxelSegment nodes remain live on their RigidBody3D parents. `take_hit()` continues to work — `seg.to_local(hit_world)` is correct because VoxelSegment moves with the RigidBody3D. `rebuild_mesh()` must run for detached/broken segments.

When a VoxelSegment is reparented onto a RigidBody3D, its original BoneAttachment3D parent is left in place (now childless). The segment is no longer driven by bone animation — the RigidBody3D drives it instead. The segment's Area3D (for weapon hit detection) is a child of VoxelSegment and moves with it correctly.

For the BROKEN shoulder anchor: LimbSystem stores a reference to the triggering segment's original BoneAttachment3D. Each `_physics_process`, the anchor Node3D is moved to that BoneAttachment3D's current global_position so the PinJoint3D attachment point tracks the animated skeleton.

---

## Cascade Detachment

When any segment DETACHES (either via integrity or connectivity check), LimbSystem:
1. Walks the hierarchy downward from the detached segment
2. Calls `detach_ragdoll(seg)` on each descendant — each becomes part of the same connected RigidBody3D chain
3. Descendant segments do NOT individually check thresholds; they follow their parent

---

## Changes to Existing Files

### `damage_manager.gd`
- Add `weapon_type: int = WeaponBase.WeaponType.SHARP` parameter to `process_hit()`
- After `seg.take_hit()`, call `seg.get_meta("limb_system").on_hit(seg, hit_pos_local, damage, weapon_type)` if meta exists

### `weapon_melee.gd`
- Pass `weapon_type` to `DamageManager.process_hit()`

### `voxel_segment.gd`
- Add `is_broken: bool = false`
- Remove `if is_detached: return` guard from `rebuild_mesh()` — detached/broken segments must still rebuild when hit

### `player.gd` / `brawler.gd`
- Instantiate LimbSystem node, add as child
- After building each VoxelSegment: `seg.set_meta("limb_system", limb_system)`
- Move `_on_player_segment_detached()` consequence logic (legs lost, death) into LimbSystem

### New: `scripts/limb_system.gd`
- Static hierarchy + max_hp dict
- `structural_integrity: Dictionary` (seg_name → float)
- `on_hit(seg, hit_pos_local, damage, weapon_type)` — drain + threshold checks
- `_spawn_broken_ragdoll(root_seg_name)` — broken chain with shoulder anchor
- `_spawn_detached_ragdoll(root_seg_name)` — severed chain with impulse
- `_spawn_death_ragdoll()` — full body
- `_physics_process()` — update shoulder anchors for broken limbs
- Listens to each VoxelSegment's `detached` signal for connectivity-triggered detachments

---

## Tunable Constants (in limb_system.gd)

| Constant | Starting Value | Effect |
|---|---|---|
| `BREAK_THRESHOLD` | 0.5 | Integrity level that triggers BROKEN state |
| `DETACH_THRESHOLD` | 0.0 | Integrity level that triggers DETACH |
| `FALLOFF` | 3.0 | How quickly proximity weight drops with distance from joint |
| `BLUNT_MULTIPLIER` | 2.0 | How much faster blunt weapons drain integrity |
| `DEATH_VOXEL_THRESHOLD` | 0.2 | Fraction of torso/head voxels remaining that triggers death ragdoll |
