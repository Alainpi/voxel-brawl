# Weapon Pickup System — Design Spec
**Date:** 2026-04-05
**Status:** Approved

---

## Overview

Decouple weapons from the player scene, introduce a 3-slot inventory, and add a world pickup/drop flow. The system must support three future game mode scenarios without the player needing to know which mode is active:

- **Always fists** — default, no configuration needed
- **Loadout mode** — game mode calls `player.give_weapon(id)` at spawn with a list of IDs
- **World pickup mode** — `WeaponPickup` nodes placed in levels; player collects them via cursor + F key

---

## 1. Weapon Scenes

**Location:** `scenes/weapons/`  
**Files:** `fists.tscn`, `bat.tscn`, `katana.tscn`, `revolver.tscn`, `shotgun.tscn`

Each weapon is extracted from `player.tscn`'s `WeaponHolder` children into its own scene. Node structure is identical to the current in-player nodes. Scripts are unchanged.

Example structures:

```
Bat (Node3D) [weapon_bat.gd]
  MeshInstance3D
  AudioStreamPlayer3D

Revolver (Node3D) [weapon_revolver.gd]
  MeshInstance3D
  Muzzle (Node3D)
  MuzzleFlash (GPUParticles3D)
  AudioShot (AudioStreamPlayer3D)
```

`WeaponBase._ready()` currently resolves `_player` via `get_node("../../../../")`. This fragile path is removed. Instead, `player.gd` sets `weapon._player = self` explicitly after instancing each weapon.

`player.tscn`: all weapon children under `WeaponHolder` are removed. The holder becomes an empty container populated at runtime.

---

## 2. WeaponRegistry (Autoload)

**File:** `scripts/weapon_registry.gd`  
**Registered as:** `WeaponRegistry`

Single source of truth for all weapon metadata. Does not instantiate anything — purely a data lookup.

```gdscript
enum Slot { FISTS = 0, MELEE = 1, RANGED = 2 }

var _data: Dictionary = {
    &"fists":    { scene = preload("…/fists.tscn"),    mesh = null,                       display_name = "Fists",    slot = Slot.FISTS,  pickup_rotation = Vector3.ZERO        },
    &"bat":      { scene = preload("…/bat.tscn"),      mesh = preload("…/Bat.obj"),       display_name = "Bat",      slot = Slot.MELEE,  pickup_rotation = Vector3(90, 0, 0)   },
    &"katana":   { scene = preload("…/katana.tscn"),   mesh = preload("…/Katana.obj"),    display_name = "Katana",   slot = Slot.MELEE,  pickup_rotation = Vector3(90, 0, 0)   },
    &"revolver": { scene = preload("…/revolver.tscn"), mesh = preload("…/Revolver.obj"),  display_name = "Revolver", slot = Slot.RANGED, pickup_rotation = Vector3(90, 0, 0)   },
    &"shotgun":  { scene = preload("…/shotgun.tscn"),  mesh = preload("…/Shotgun.obj"),   display_name = "Shotgun",  slot = Slot.RANGED, pickup_rotation = Vector3(90, 0, 0)   },
}

func get_scene(id: StringName) -> PackedScene
func get_mesh(id: StringName) -> ArrayMesh      # null for fists
func get_display_name(id: StringName) -> String
func get_slot(id: StringName) -> Slot
func has(id: StringName) -> bool
```

`Slot` lives in WeaponRegistry (game-rule concern), not `WeaponBase`. `WeaponBase.WeaponType` (BLUNT/SHARP/RANGED) is a combat-behavior concern and stays on `WeaponBase`.

---

## 3. Player Inventory

**File:** `scripts/player.gd` (refactor)

### Slots

```gdscript
const SLOT_FISTS  = 0
const SLOT_MELEE  = 1
const SLOT_RANGED = 2

var _inventory: Array[WeaponBase] = [null, null, null]
var _current_slot: int = 0
```

Slot 0 is always fists — set in `_ready()`, never cleared.

### Key Bindings

| Key | Action |
|-----|--------|
| 1   | `_equip_slot(SLOT_FISTS)` |
| 2   | `_equip_slot(SLOT_MELEE)` — no-op if slot empty |
| 3   | `_equip_slot(SLOT_RANGED)` — no-op if slot empty |
| F   | Pick up highlighted weapon |
| G   | `_drop_weapon(_current_slot)` — no-op on fists slot |

### Methods

**`give_weapon(id: StringName)`** — public API called by both loadout mode and pickup collection.
1. Look up slot type from `WeaponRegistry.get_slot(id)`
2. If slot is occupied: call `_drop_weapon(slot)` first (spawns pickup at player's feet)
3. Instance the weapon scene, set `_player = self`, add to `WeaponHolder`
4. Store in `_inventory[slot]`
5. Equip the new slot

**`_equip_slot(idx: int)`** — internal slot switch.
1. Hide and disable `_current_weapon` (if not null)
2. Set `_current_weapon = _inventory[idx]`, `_current_slot = idx`
3. Show and enable new weapon (if not null)
4. Fire HUD weapon name + stance updates
5. Pressing a key for an empty slot (2 or 3 with no weapon) is silently ignored

**`_drop_weapon(slot: int)`**
1. No-op if `slot == SLOT_FISTS`
2. Spawn `WeaponPickup` at player position + small forward offset at floor level; set `weapon_id`
3. Free the weapon node from `WeaponHolder`
4. Clear `_inventory[slot] = null`
5. If dropped slot was active: `_equip_slot(SLOT_FISTS)`

`_equip_weapon(node)` is removed and replaced entirely by `_equip_slot(idx)`. `_update_animation()` and `_update_stance_for_weapon()` are unchanged functionally — they operate on `_current_weapon` which is always a typed `WeaponBase`.

---

## 4. WeaponPickup Scene

**File:** `scenes/weapons/weapon_pickup.tscn`  
**Script:** `scripts/weapon_pickup.gd`

```
WeaponPickup (StaticBody3D) [weapon_pickup.gd]
  CollisionShape3D  (BoxShape3D ~0.3×0.1×0.8 — generic bounding box for raycast)
  MeshInstance3D
```

`StaticBody3D` as root gives the raycast something to hit. Proximity is enforced entirely by the raycast max distance — no `Area3D` needed. The dedicated physics layer (layer 3) ensures the ray doesn't hit player bodies or voxel segments.

### weapon_pickup.gd

```gdscript
@export var weapon_id: StringName = &""

_ready():
  var m := WeaponRegistry.get_mesh(weapon_id)
  if m:
    $MeshInstance3D.mesh = m
  # ground rotation: all pickups lie flat. Default is rotation_degrees = Vector3(90, 0, 0)
  # which lays the weapon on its side along the floor. WeaponRegistry stores an optional
  # pickup_rotation: Vector3 per weapon to override this for weapons with unusual geometry.

highlight(on: bool):
  $MeshInstance3D.material_overlay = highlight_material if on else null

get_weapon_id() -> StringName:
  return weapon_id
```

`highlight_material` is a simple emissive `StandardMaterial3D` stored as a preloaded resource (`assets/materials/pickup_highlight.tres`).

Both world-placed pickups (editor-placed, `weapon_id` set in inspector) and dropped weapons (spawned at runtime by `_drop_weapon`) use the same scene.

---

## 5. Highlight & Pickup Loop

Runs in `player.gd`'s `_process()`:

```
var _highlighted_pickup: WeaponPickup = null

_process():
  cast ray from camera origin, forward direction, max 3m
  collision mask = pickup layer only

  if ray hits WeaponPickup node:
    if node != _highlighted_pickup:
      if _highlighted_pickup: _highlighted_pickup.highlight(false)
      node.highlight(true)
      _highlighted_pickup = node
    hud.show_pickup_prompt(WeaponRegistry.get_display_name(node.weapon_id))
  else:
    if _highlighted_pickup:
      _highlighted_pickup.highlight(false)
      _highlighted_pickup = null
    hud.hide_pickup_prompt()
```

**F key pressed:**
```
if _highlighted_pickup:
  give_weapon(_highlighted_pickup.get_weapon_id())
  _highlighted_pickup.queue_free()
  _highlighted_pickup = null
```

---

## 6. Physics Layer Assignment

| Layer | Purpose |
|-------|---------|
| 1     | World geometry (walls, floors) — existing |
| 2     | Voxel segments — existing |
| 3     | Weapon pickups — new |

`WeaponPickup` node: collision layer = 3, mask = none.  
Pickup raycast in player: mask = layer 3 only.

---

## 7. HUD Changes

`hud.gd` needs two new methods:

- `show_pickup_prompt(weapon_name: String)` — displays "F — pick up \<weapon_name\>" in a corner prompt
- `hide_pickup_prompt()` — hides it

No other HUD changes required. `set_weapon_name()` continues to work as-is since `give_weapon()` calls `_equip_slot()` which calls the existing HUD update path.

---

## 8. Out of Scope

- Weapon rarity / loot tables (Phase 4+)
- Ammo persistence on dropped weapons (dropped weapons respawn with full ammo for now)
- Two-handed weapon slot rules (Phase 3 dismemberment concern)
- Multiplayer pickup authority (`@rpc` wiring deferred to Phase 4 — `give_weapon()` is the correct RPC boundary when the time comes)
