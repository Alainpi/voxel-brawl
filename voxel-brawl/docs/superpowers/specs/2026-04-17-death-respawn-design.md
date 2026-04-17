# Death + Respawn — Design Spec

**Date:** 2026-04-17
**Phase:** 2 (final remaining task)
**Status:** Approved

---

## Overview

When the player's HP reaches zero, the voxel body collapses into a ragdoll. After a 5-second delay the body is cleaned up, the player teleports to a random spawn point, and the voxel body is fully rebuilt. Weapons drop on death; player respawns with fists only.

---

## Ragdoll on Death

`_limb_system.die()` is already fully implemented in `LimbSystem._spawn_death_ragdoll()`. It converts every remaining attached segment into a `RigidBody3D` connected to adjacent segments with `PinJoint3D`, then gravity drives the collapse. The player CharacterBody3D node goes visually empty once the segments reparent to scene-root RigidBody3D nodes.

No new ragdoll code is required.

---

## Spawn Points

Four `Marker3D` nodes added to `test_scene.tscn` as children of the scene root, each in the `"spawn_point"` group:

| Node name    | Approximate position |
|---|---|
| SpawnPoint1  | (+5, 0, +5)          |
| SpawnPoint2  | (-5, 0, +5)          |
| SpawnPoint3  | (+5, 0, -5)          |
| SpawnPoint4  | (-5, 0, -5)          |

Positions are tunable in the editor at any time — the respawn logic reads `global_position` at runtime, so no code changes are needed when moving them.

---

## `Player._die()` Flow

1. Guard: `if _is_dead: return`. Set `_is_dead = true`, `_is_attacking = false`.
2. Drop melee and ranged slots via existing `_drop_weapon()` — weapons land in the world as pickups.
3. Disable `$CollisionShape3D` so the dead player doesn't block movement.
4. Call `_limb_system.die()` — ragdoll fires immediately.
5. Start a 5-second `SceneTreeTimer`; on timeout call `_respawn()`.

---

## `Player._respawn()` Flow

1. Free all nodes in the `"detached_limb"` group (ragdoll pieces).
2. Pick a random `Marker3D` from the `"spawn_point"` group; set `global_position` to it.
3. Re-enable `$CollisionShape3D`.
4. Reparent `weapon_holder` back to `camera` with identity transform, **before** freeing the body (the current `_weapon_anchor` is a child of the skeleton and is about to be freed).
5. Free all inventory weapons including fists; clear `_inventory` entries to `null`.
6. Free `LimbSystem`, `HealthSystem`, and all `_attachments` (BoneAttachment3D nodes tracked in the new `_attachments` array).
7. `await get_tree().process_frame` — lets `queue_free` propagate before rebuilding.
8. Reset state: `_legs_lost = 0`, `_is_attacking = false`, `_is_dead = false`.
9. Re-create fists: instantiate from `WeaponRegistry`, add to `weapon_holder`, store in `_inventory[SLOT_FISTS]`.
10. Call `_build_voxel_body()` — rebuilds all 14 segments, wires new LimbSystem and HealthSystem, reparents `weapon_holder` to new `_weapon_anchor`.
11. Call `_equip_slot(SLOT_FISTS)` — HUD weapon name, stance, and HP bar all update via their existing signal paths.

---

## Internal Change: `_attachments` Tracking

`_build_voxel_body()` in `Player` currently does not track the `BoneAttachment3D` nodes it creates (unlike `Brawler`, which has `_attachments: Array`). Add `_attachments: Array = []` to Player and append each `BoneAttachment3D` to it inside `_build_voxel_body()`. `_respawn()` iterates this array to free them before rebuilding.

---

## What Does Not Change

- HUD HP bar and body silhouette update automatically via `HealthSystem.hp_changed` signal, which fires in `HealthSystem.initialize()` on rebuild.
- Camera continues to follow `player.global_position` during the ragdoll window — no camera changes needed.
- Brawler death/respawn is unaffected (already implemented).
- Multiplayer readiness is preserved: `_respawn()` only runs on the multiplayer authority.

---

## Out of Scope

- Camera fade or spectator mode on death (Phase 5 polish).
- Kill feed / death announcements (Phase 5).
- Respawn invincibility frames (Phase 5).
