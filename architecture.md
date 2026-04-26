# Voxel Brawl — Architecture Reference

> Current as of: 2026-04-26  
> Engine: Godot 4.6.1-stable  
> Purpose: Guide future feature work to stay compatible with existing systems.  
> **Does not describe planned or future states.**

---

## Table of Contents

1. [Project Layout](#1-project-layout)
2. [Active Scene Structure](#2-active-scene-structure)
3. [Character Body Architecture](#3-character-body-architecture)
4. [Voxel System](#4-voxel-system)
5. [Damage Pipeline](#5-damage-pipeline)
6. [Health System](#6-health-system)
7. [Limb System](#7-limb-system)
8. [Weapon System](#8-weapon-system)
9. [Inventory & Pickup System](#9-inventory--pickup-system)
10. [HUD System](#10-hud-system)
11. [Camera System](#11-camera-system)
12. [FOV / Visibility System](#12-fov--visibility-system)
13. [Debris & Effects](#13-debris--effects)
14. [Autoloads & Singletons](#14-autoloads--singletons)
15. [Physics Layers](#15-physics-layers)
16. [Signal Map](#16-signal-map)
17. [Death & Respawn](#17-death--respawn)

---

## 1. Project Layout

```
voxel-brawl/
├── assets/
│   ├── maps/               # Map piece scenes (.tscn)
│   ├── materials/          # pickup_highlight.tres
│   ├── models/
│   │   ├── player_rig.glb  # 14-bone skeleton + animations
│   │   └── Weapons/        # Bat.obj, Katana.obj, Revolver.obj, Shotgun.obj
│   └── voxels/             # 28 .vox files (14 flesh + 14 bone segments)
├── docs/
│   └── architecture.md     # this file
├── scenes/
│   ├── dummy.tscn
│   ├── brawler.tscn
│   ├── player.tscn
│   ├── test_scene.tscn     # main playable scene
│   ├── debris_pool.tscn
│   └── weapons/
│       ├── fists.tscn
│       ├── bat.tscn
│       ├── katana.tscn
│       ├── revolver.tscn
│       ├── shotgun.tscn
│       └── weapon_pickup.tscn
├── scripts/                # all .gd files (see each section below)
├── shaders/
│   └── fov_world.gdshader
└── hud.tscn
```

---

## 2. Active Scene Structure

**Main playable scene:** `scenes/test_scene.tscn` (script: `scripts/main.gd`)

```
test_scene (Node3D)         ← main.gd
├── DirectionalLight3D
├── DirectionalLight3D2
├── DebrisPool (Node)        ← debris_pool.gd (static instance var)
├── Dummy (Node3D)           ← dummy.gd
├── Player (CharacterBody3D) ← player.gd
├── Brawler (CharacterBody3D)← brawler.gd
├── hud (CanvasLayer)        ← hud.gd
├── WeaponPickupBat          ← weapon_pickup.gd (collision layer 3)
├── WeaponPickupRevolver     ← weapon_pickup.gd (collision layer 3)
├── SpawnPoint1 (Marker3D)   ← group "spawn_point", position (+5, 0, +5)
├── SpawnPoint2 (Marker3D)   ← group "spawn_point", position (−5, 0, +5)
├── SpawnPoint3 (Marker3D)   ← group "spawn_point", position (+5, 0, −5)
├── SpawnPoint4 (Marker3D)   ← group "spawn_point", position (−5, 0, −5)
└── [map pieces — StaticBody3D tiles with collision layer 1]
```

`main.gd` only connects `died` signals from Dummy and Brawler for debug output. No gameplay logic lives there.

The HUD is found by Player at runtime via:
```gdscript
_hud = get_node_or_null("/root/test_scene/hud")
```
This path is hardcoded — any scene rename breaks the HUD link.

---

## 3. Character Body Architecture

All three damageable characters (Player, Dummy, Brawler) share the same runtime body-building pattern. They each instance `assets/models/player_rig.glb` as `PlayerModel` and call a `_build_*` method deferred from `_ready()`.

### Shared scene structure at editor time

| Scene | Root type | Script |
|---|---|---|
| `scenes/player.tscn` | CharacterBody3D | `scripts/player.gd` |
| `scenes/brawler.tscn` | CharacterBody3D | `scripts/brawler.gd` |
| `scenes/dummy.tscn` | Node3D | `scripts/dummy.gd` |

All three embed the same `player_rig.glb` as `PlayerModel` with scale `(−0.4, 0.4, −0.4)` (the X/Z negation rotates 180° around Y).

### What `_build_*` constructs at runtime

For each of the 14 segment names in `SEGMENT_CONFIG` / `PLAYER_SEGMENT_CONFIG`:

```
Skeleton3D
└── BoneAttachment3D   rotation_degrees.x = -90 (MV coordinate fix)
    └── VoxelSegment   position/scale/rotation from config
        └── Area3D     collision_layer=2, mask=0
            └── CollisionShape3D (BoxShape3D sized to segment AABB)
```

After all segments are built:
- `LimbSystem` node added as child of the character
- `HealthSystem` node added as child of the character
- Every VoxelSegment gets two metadata tags:
  - `seg.set_meta("limb_system", _limb_system)`
  - `seg.set_meta("health_system", _health_system)`

**Player-only additions:**
- A `WeaponAnchor` Node3D is attached to the `hand_r` BoneAttachment3D
- `WeaponHolder` (which lives under Camera3D in the scene) is reparented to `WeaponAnchor` at runtime
- Weapon node transforms are baked into their visual children; Area3D and Marker3D children are left in clean hand-bone space
- `_attachments: Array = []` tracks every `BoneAttachment3D` created by `_build_voxel_body()` so they can be freed during respawn (mirrors the Brawler pattern)

**Brawler-only additions:**
- A `WeaponFists` node is parented to the `hand_r` BoneAttachment3D
- Has a `NavigationAgent3D` for pathfinding

### SEGMENT_CONFIG format

Each entry is a 10-element array:
```
[vox_path, bone_name, position_offset, attach_rot_x, attach_rot_z,
 scale, root_axis, seg_rot_x, seg_rot_y, bone_vox_path]
```

- `root_axis`: `Vector3i` pointing toward the attachment joint. `Vector3i.ZERO` = torso (never detaches).
- Head segments use `scale = Vector3(1, 1, -1)` to fix Z-axis flip from the rig orientation.
- `bone_vox_path` (`cfg[9]`): path to the paired bone `.vox` file, loaded lazily when flesh damage crosses `BONE_REVEAL_THRESHOLD`. Set to `""` to disable bone reveal for a specific segment.

---

## 4. Voxel System

**Scripts:** `scripts/voxel_loader.gd`, `scripts/voxel_segment.gd`

### VoxelLoader

Static class. Called once per segment during body build:
```gdscript
VoxelLoader.load_vox(path) → Dictionary  # Vector3i → Color
```
Parses MagicaVoxel binary format. Coordinate remap: MV `(x, y, z)` → Godot `Vector3i(x, z, y)`.

### VoxelSegment

`class_name VoxelSegment extends Node3D`

The fundamental unit of the body. Each segment holds a live voxel dictionary and owns its mesh.

**Key tuning constants** (grouped at top of file under `# --- TUNING ---`):
| Constant | Default | Meaning |
|---|---|---|
| `BONE_REVEAL_THRESHOLD` | 0.85 | Flesh fraction below which the bone `.vox` loads |
| `BONE_HP` | 3.0 | Hits required to destroy one bone voxel (flesh = 1.0) |
| `DAMAGE_COLOR` | dark maroon | Tint target applied to flesh voxels near a hit |
| `DAMAGE_TINT_RATIO` | 0.5 | Lerp strength toward DAMAGE_COLOR (0 = none, 1 = full) |
| `DAMAGE_TINT_RADIUS_MULT` | 2.0 | Tint radius = hit radius × this multiplier |
| `CHUNK_MIN_VOXELS` | 8 | Min cluster size to spawn as a rigid chunk (smaller → GPU particles) |
| `DEBRIS_MAX_PHYSICS` | 8 | Max RigidBody3D cubes spawned per hit |

**Key state variables:**
| Variable | Type | Meaning |
|---|---|---|
| `voxel_data` | `Dictionary` (Vector3i→Color) | All currently-alive voxels (flesh + bone after reveal) |
| `voxel_hp` | `Dictionary` (Vector3i→float) | Per-voxel HP |
| `total_voxel_count` | `int` | Flesh count at load time; never changes; used for HP fractions |
| `current_voxel_count` | `int` | Total live voxel count including bone |
| `flesh_voxel_count` | `int` | Live flesh voxels only; decremented on removal; used by HealthSystem |
| `bone_voxel_count` | `int` | Net-new bone voxels added into carved gaps (no HP contribution) |
| `_bone_vox_path` | `String` | Path to paired bone `.vox`; set from `cfg[9]` at build time |
| `_bone_loaded` | `bool` | Whether bone voxels have been merged in for this segment |
| `_bone_voxels` | `Dictionary` | Set of ALL bone positions (both replaced-flesh and net-new); used to skip damage tinting |
| `_bone_over_flesh` | `Dictionary` | Subset of `_bone_voxels` where bone replaced existing flesh; these positions still decrement `flesh_voxel_count` when destroyed |
| `root_axis` | `Vector3i` | Direction toward attachment joint |
| `is_detached` | `bool` | Segment has been severed |
| `is_broken` | `bool` | Segment is in floppy ragdoll state |
| `_root_voxels_cached` | `Array[Vector3i]` | The attachment row, cached at load |

**`_init_voxel_hp()`:** All voxels start as flesh at `voxel_hp = 1.0`. No interior detection. Sets `flesh_voxel_count = voxel_data.size()`, clears bone tracking state.

**`take_hit(center_local, radius_voxels, damage)`:**
1. Iterates all voxels in `radius_world = radius_voxels * VOXEL_SIZE`
2. Drains `voxel_hp`; collects voxels at zero in `actually_removed`
3. Tints flesh voxels (not bone) in a wider ring (`DAMAGE_TINT_RADIUS_MULT ×` radius) with `DAMAGE_COLOR` at `DAMAGE_TINT_RATIO` strength
4. Calls `_spawn_debris_from()` for removed voxels; decrements `flesh_voxel_count` or `bone_voxel_count` per removed position
5. Calls `_check_connectivity()` — flood-fill from root; disconnected clusters become debris or rigid chunks
6. Checks bone reveal threshold: if `flesh_voxel_count / total_voxel_count < BONE_REVEAL_THRESHOLD`, calls `_load_bone_voxels()`
7. Deferred `rebuild_mesh()`

**`_load_bone_voxels()`:** Fires once per segment lifetime. Parses the bone `.vox` via `VoxelLoader`. For each bone position:
- If flesh still present: overwrites with bone color + `BONE_HP`; marks in both `_bone_voxels` and `_bone_over_flesh` (still counts as flesh for HP).
- If empty (flesh already carved): adds net-new bone voxel; marks in `_bone_voxels` only; increments `bone_voxel_count` (no HP contribution).

Sets `_bone_loaded = true`; deferred `rebuild_mesh()`.

**Detachment trigger:** When fewer than 30% of the original `_root_voxels_cached` remain, the segment calls `detach()`.

**`detach()`:** Sets `is_detached = true`, disables Area3D layer, emits `detached` signal. If a `limb_system` meta tag is present, LimbSystem handles the ragdoll. Otherwise VoxelSegment launches its own RigidBody3D.

**DDA raycast:** `dda_raycast(local_origin, local_dir)` — used by ranged weapons for precise voxel targeting. Returns `{hit: bool, voxel: Vector3i}`.

---

## 5. Damage Pipeline

**Script:** `scripts/damage_manager.gd` (Autoload: `DamageManager`)

All damage in the game routes through one function:

```gdscript
DamageManager.process_hit(
    segment: VoxelSegment,
    hit_pos_local: Vector3,
    radius: float,
    damage: float,
    weapon_type: WeaponBase.WeaponType = SHARP
)
```

Execution order inside `process_hit`:
1. `segment.take_hit(hit_pos_local, radius, damage)` — removes voxels, spawns debris
2. `limb_system.on_hit(segment, hit_pos_local, damage, weapon_type)` — drains integrity, checks break/detach
3. `health_system.on_hit(segment)` — recomputes HP, emits `hp_changed` / `died`

The `multiplayer.is_server()` guard wraps all of this — a no-op in single-player but the intended multiplayer hook point.

### Melee hit detection path

1. `WeaponMelee._attack()` starts a timer
2. After `hit_enable_delay` seconds, `_enable_hitbox()` sets `_hitbox_active = true`
3. Each physics tick: `_shape_overlap_check()` queries `intersect_shape()` against layer 2
4. Scale-strip fix applied to query transform: strips the PlayerModel's 0.4× inherited scale so shape dimensions work at face value
5. Hits capped at `max_hits` unique VoxelSegment results; own segments filtered via `_own_segment_set`
6. For each new hit: `_apply_hit(seg, local_hit)` → `DamageManager.process_hit(...)`
7. After `hit_window_duration` seconds, `_disable_hitbox()`

### Ranged hit detection path

1. `WeaponRanged._fire()` fires from `Muzzle.global_position`
2. Two rays fired from `cam_origin` (NOT muzzle) along camera direction:
   - Ray 1: layer 1 (walls/static) — `collide_with_bodies = true`
   - Ray 2: layer 2 (voxels) — `collide_with_areas = true`
3. Closer of the two hits wins
4. On voxel hit: DDA raycast (`seg.dda_raycast`) from the hit position finds the exact voxel
5. `_apply_hit(seg, voxel_center)` → `DamageManager.process_hit(...)`

**Shotgun:** Overrides `_fire()`, calls `_fire_ray(pellet_dir)` 6 times with per-pellet scatter. Scatter is computed as a random offset in world-space XZ at the aim plane, radius `spread_near = 0.5` world units.

---

## 6. Health System

**Script:** `scripts/health_system.gd` (`class_name HealthSystem`)

Added as a child node of any damageable character at runtime.

### Concept: Weighted Death Pool

There is no global "HP bar filled from hits". Instead, each segment carries a weight. HP is computed as:

```
HP = MAX_HP - sum(weight[seg] * loss_fraction[seg])  for all segments
```

`MAX_HP = 100.0`. Weights intentionally exceed MAX_HP — this means a single lethal segment (head, torso) can kill alone.

### Segment weights

| Segment | Weight | Notes |
|---|---|---|
| `torso_bottom` | 60 | |
| `torso_top` | 40 | torso total = 100 |
| `head_bottom` | 50 | |
| `head_top` | 50 | head total = 100 |
| `arm_r_upper` | 25 | |
| `arm_r_fore` | 15 | right arm total = 40 |
| `arm_l_upper` | 25 | |
| `arm_l_fore` | 15 | left arm total = 40 |
| `hand_r` | 20 | |
| `hand_l` | 20 | |
| `leg_r_upper` | 25 | |
| `leg_r_fore` | 15 | right leg total = 40 |
| `leg_l_upper` | 25 | |
| `leg_l_fore` | 15 | left leg total = 40 |

### How HP is calculated

`_compute_hp()`:
- For each segment in WEIGHTS:
  - If segment is detached: contributes full weight as damage
  - Otherwise: `loss = 1.0 - (flesh_voxel_count / total_voxel_count)`; `damage += weight * loss`
- `HP = max(0, MAX_HP - damage)`

**Note:** HP reads `flesh_voxel_count`, not `current_voxel_count`. Bone voxels added by the reveal system do not inflate the health pool. Net-new bone voxels (added into carved gaps) have no HP contribution at all. Replaced-flesh bone voxels (bone that overwrote surviving flesh) retain their original flesh HP contribution and decrement `flesh_voxel_count` when destroyed.

### How HealthSystem is updated

- `on_hit(seg)` — called by DamageManager after every hit; calls `_refresh()`
- `_on_segment_detached(seg, seg_name)` — connected to every VoxelSegment's `detached` signal at init; marks `_detached[seg_name] = true`, calls `_refresh()`
- `_refresh()` — recomputes HP, emits `hp_changed(current, MAX_HP)`, and if HP hits zero emits `died`

### HUD queries

- `get_segment_health_fraction(seg_name) → float` — returns `(flesh_voxel_count / total_voxel_count)` clamped against `limb_system.get_integrity()` if available. Returns 0.0 for detached segments.
- `get_segment_is_broken(seg_name) → bool` — returns `seg.is_broken and not seg.is_detached`

### Silhouette color logic (in `hud.gd`)

| Condition | Color |
|---|---|
| fraction ≤ 0.0 (severed) | grey `(0.32, 0.32, 0.32)` |
| `is_broken` | bright red `(0.90, 0.08, 0.08)` |
| fraction < 0.25 | red `(0.85, 0.10, 0.10)` |
| fraction < 0.50 | orange `(0.90, 0.50, 0.10)` |
| fraction < 0.75 | lighter green `(0.45, 0.85, 0.15)` |
| fraction ≥ 0.75 | green `(0.20, 0.78, 0.20)` |

---

## 7. Limb System

**Script:** `scripts/limb_system.gd` (`class_name LimbSystem`)

Added as a child node of any damageable character at runtime.

### Responsibilities
- Tracks `_integrity[seg_name]` (float 0–1) for each segment
- Triggers BROKEN (floppy ragdoll, still attached) and DETACHED (severed) state transitions
- Owns and manages all RigidBody3D and PinJoint3D ragdoll nodes
- Emits `leg_lost(seg_name)` when a leg segment detaches
- Emits `segment_broken(seg_name)` once per segment that newly enters BROKEN state (including cascade descendants)

### Constants

| Constant | Value | Meaning |
|---|---|---|
| `BREAK_THRESHOLD_DEFAULT` | 0.5 | Default integrity below which BLUNT hit → BROKEN |
| `DETACH_THRESHOLD_DEFAULT` | 0.0 | Default integrity at or below which → DETACH |
| `FALLOFF` | 3.0 | Proximity weight drop-off rate from joint |
| `BLUNT_MULTIPLIER` | 2.0 | Blunt weapons drain integrity 2× faster |

Per-segment overrides (absent entries fall back to defaults):

| Segment | Break threshold | Detach threshold | Rationale |
|---|---|---|---|
| `head_top`, `head_bottom` | 0.7 | 0.2 | Skull cracks early on blunt; harder to outright sever |
| `hand_r`, `hand_l` | 0.8 | 0.5 | Hands break and detach easily — fragile, high-value target |
| All others | 0.5 (default) | 0.0 (default) | Limb must be fully spent to come off |

Helpers `_break_threshold(seg_name)` and `_detach_threshold(seg_name)` do the lookup with fallback. An `assert` in `initialize()` enforces `break > detach` for every segment.

### Hierarchy definition

```
torso_bottom
├── torso_top (indestructible, max_hp=0)
│   ├── head_bottom (max_hp=60)
│   │   └── head_top (max_hp=60)
│   ├── arm_r_upper (max_hp=120)
│   │   └── arm_r_fore (max_hp=80)
│   │       └── hand_r (max_hp=50)
│   └── arm_l_upper (max_hp=120)
│       └── arm_l_fore (max_hp=80)
│           └── hand_l (max_hp=50)
├── leg_r_upper (max_hp=120)
│   └── leg_r_fore (max_hp=80)
└── leg_l_upper (max_hp=120)
    └── leg_l_fore (max_hp=80)
```

Torso segments (`max_hp=0`) never break or detach via integrity.

### Integrity drain formula

On each hit to a segment:
```
integrity -= (damage / max_hp) * proximity * blunt_multiplier
proximity = clamp(1 / (1 + dist_to_joint * FALLOFF), 0.1, 1.0)
```
where `dist_to_joint` is the distance from the hit position to the average of the cached root voxels.

### State transitions

- **BROKEN:** `integrity < BREAK_THRESHOLD` AND weapon is BLUNT AND segment not already broken  
  → `_spawn_broken_ragdoll(seg_name)`: the segment AND every descendant in `_chain_downward(seg_name)` are reparented to fresh RigidBody3D nodes connected by PinJoint3D; each gets `is_broken = true`. A StaticBody3D "shoulder anchor" is created at the root segment's BoneAttachment3D position and pinned to the root RB; `_physics_process` updates the anchor's `global_position` from the BoneAttachment3D each tick so the rigid chain dangles from the still-animated parent bone.  
  **Cascade:** `_spawn_broken_ragdoll(root_seg_name)` walks `_chain_downward(root_seg_name)` and breaks the root + every descendant in one pass. Breaking a forearm therefore also breaks the hand below it (both go floppy from the elbow); the upper arm above stays cleanly animated. The cascade is downward-only.  
  **Signal:** `segment_broken(seg_name: String)` fires once per segment that newly transitions to BROKEN, immediately after `seg.is_broken = true` is set in the chain loop. Segments already broken or detached are skipped (the existing `seg.is_detached or seg.is_broken` guard). Listeners do not need to re-implement the cascade rule — they receive one emission per affected segment.

- **DETACHED:** `integrity <= _detach_threshold(seg_name)` (any weapon type)  
  → `seg.detach()` → `_spawn_detached_ragdoll(seg_name)`: removes shoulder anchor, applies outward impulse; the entire chain below the root tumbles freely.  
  **Logical cascade:** `_spawn_detached_ragdoll` sets a `_cascading` guard flag, then calls `seg.detach()` on every descendant in the chain. This fires the `detached` signal for each descendant so all listeners (HealthSystem, future slot-disable logic) are notified. `_on_segment_detached` short-circuits ragdoll rebuild and `leg_lost` while `_cascading` is true — the outer call owns the ragdoll. Result: one tumbling physics chunk, correct signal propagation, no recursion.

- **DEATH:** `LimbSystem.die()` called  
  → `_spawn_death_ragdoll()`: builds full-body RigidBody3D chain with PinJoint3D hierarchy; gravity drives the collapse.

---

## 8. Weapon System

### Inheritance hierarchy

```
WeaponBase (Node3D)
├── WeaponMelee
│   ├── WeaponBat
│   ├── WeaponKatana
│   └── WeaponFists
└── WeaponRanged
    ├── WeaponRevolver
    └── WeaponShotgun
```

**Scripts:** `weapon_base.gd`, `weapon_melee.gd`, `weapon_ranged.gd`, `weapon_bat.gd`, `weapon_katana.gd`, `weapon_fists.gd`, `weapon_revolver.gd`, `weapon_shotgun.gd`

### WeaponBase

```gdscript
var _player       # duck-typed: Player or Brawler
var weapon_id: StringName
enum WeaponType { BLUNT, SHARP, RANGED }
var weapon_type: WeaponType
```

Calls `_configure()` (virtual) in `_ready()`. `_player` must be set externally before `add_child`.

### WeaponMelee — controllable variables

All set in the subclass's `_configure()` override:

| Variable | Type | Default | What it controls |
|---|---|---|---|
| `damage` | float | 10.0 | Voxel HP drained per hit |
| `voxel_radius` | float | 2.0 | Sphere radius (in voxels) of destruction |
| `cooldown` | float | 0.4 | Seconds between attacks |
| `attack_anim` | String | "punch" | Animation prefix (combined with stance suffix) |
| `hit_enable_delay` | float | 0.1 | Seconds after swing start before hitbox activates |
| `hit_window_duration` | float | 0.15 | Seconds hitbox stays active |
| `max_hits` | int | 1 | Max segments hit per swing |
| `hit_shape` | Shape3D | null | Collision shape used for overlap query |
| `hit_shape_offset` | Vector3 | ZERO | Local offset of shape in weapon space |
| `hit_shape_rotation` | Vector3 | ZERO | Degrees (e.g. `(90,0,0)` to align capsule) |
| `hit_shape_scale` | Vector3 | ONE | Scale multiplier for the shape |
| `weapon_type` | WeaponType | BLUNT | BLUNT drains integrity 2×; SHARP does not |
| `is_player_controlled` | bool | true | If false, only `request_attack()` triggers attacks |

### Current melee weapon stats

| Weapon | Shape | Damage | Voxel radius | Delay | Window | Max hits |
|---|---|---|---|---|---|---|
| Bat | CapsuleShape3D r=0.25 h=1.0 | 50 | 2.8 | 0.2s | 1.0s | 10 |
| Katana | BoxShape3D (0.05×0.6×0.05) | 45 (55 on thrust) | 1.0 | 0.53s | 1.0s | 10 (1 on thrust) |
| Fists | Two SphereShape3D | 15 per fist | 1.0 | 0.05s | 0.3s | 3 |

**Katana thrust stance:** When `StanceManager.current_stance() == THRUST`, damage increases to 55 and `max_hits` drops to 1 before `super()` is called.

### WeaponRanged — controllable variables

| Variable | Type | Default | What it controls |
|---|---|---|---|
| `damage` | float | 25.0 | Voxels HP drained per hit |
| `voxel_radius` | float | 1.5 | Sphere radius of destruction |
| `fire_rate` | float | 0.5 | Cooldown between shots |
| `max_ammo` | int | 6 | Magazine capacity |
| `reload_time` | float | 1.5 | Seconds to reload |
| `tracer_color` | Color | yellow | Color of the bullet tracer streak |
| `recoil_shake_strength` | float | 0.2 | Camera shake magnitude (0–1) |
| `recoil_kick_amount` | float | 12.0 | Crosshair gap expansion on fire |
| `recoil_recovery_time` | float | 0.25 | Seconds for crosshair to settle |

### Current ranged weapon stats

| Weapon | Damage | Voxel radius | Fire rate | Ammo | Reload |
|---|---|---|---|---|---|
| Revolver | 35 | 1.5 | 0.55s | 6 | 1.5s |
| Shotgun | 12 per pellet (×6) | 1.2 | 0.9s | 2 | 2.0s |

### Scene node structure per weapon type

**Melee scene (e.g. bat.tscn):**
```
Bat (Node3D)          ← WeaponBat script
├── MeshInstance3D    ← visual mesh
└── AudioStreamPlayer3D
```
The hitbox Area3D is created at runtime by `_create_hitarea()`, not in the scene.

**Ranged scene (e.g. revolver.tscn):**
```
Revolver (Node3D)     ← WeaponRevolver script
├── AudioShot (AudioStreamPlayer3D)
├── MuzzleFlash (GPUParticles3D)
├── Muzzle (Node3D)   ← origin for bullet tracer start point
└── MeshInstance3D
```

**Fists scene:**
```
Fists (Node3D)        ← WeaponFists script
└── AudioStreamPlayer3D
```
WeaponFists overrides `_create_hitarea()` to build two SphereShape3D hitboxes (left and right fist).

### Animation name building

Melee animations follow the pattern: `{attack_anim}_{stance_key}`

Examples: `bat_low`, `bat_mid`, `bat_high`, `katana_thrust`, `punch_low`

Ranged shooting plays: `holding_right_shoot`

`play_attack_anim()` sets `_is_attacking = true`; it resets to false on `animation_finished`.

---

## 9. Inventory & Pickup System

**Scripts:** `scripts/weapon_registry.gd` (Autoload: `WeaponRegistry`), `scripts/weapon_pickup.gd`

### Inventory slots

```gdscript
const SLOT_FISTS  = 0   # always occupied; cannot be dropped
const SLOT_MELEE  = 1   # bat, katana
const SLOT_RANGED = 2   # revolver, shotgun
var _inventory: Array[WeaponBase] = [null, null, null]
```

Keys `1`, `2`, `3` switch slots. `G` drops current weapon into world.

### WeaponRegistry

Single source of truth for all weapon metadata. Keys are `StringName` IDs: `&"fists"`, `&"bat"`, `&"katana"`, `&"revolver"`, `&"shotgun"`.

Per-weapon data:
| Field | Type | Purpose |
|---|---|---|
| `scene` | PackedScene | Instanced by `give_weapon()` |
| `mesh` | ArrayMesh or null | Applied to WeaponPickup |
| `display_name` | String | Shown in HUD |
| `slot` | Slot enum | Determines which inventory slot |
| `pickup_rotation` | Vector3 | Applied to pickup mesh node |
| `pickup_scale` | float | Applied to pickup mesh node |

### WeaponBase hand-side fields

Two fields on `WeaponBase` gate pickup eligibility:

| Field | Type | Default | Meaning |
|---|---|---|---|
| `held_side` | `StringName` | `&"r"` | Which hand mounts this weapon. All current prototype weapons use `&"r"`. |
| `requires_both_hands` | `bool` | `false` | If true, both hands must be intact. No prototype weapon sets this yet. |

### `give_weapon(id: StringName)` flow

1. Look up slot from WeaponRegistry
2. **Gate:** if slot ≠ SLOT_FISTS, probe `held_side` / `requires_both_hands` from a temporary (un-parented) instance. If `_hand_usable[held_side] == false`, or if `requires_both_hands` and either hand is disabled, refuse the pickup (weapon stays in world).
3. Drop existing weapon in that slot if occupied (`_drop_weapon`)
4. Instance scene, set `_player`, `weapon_id`
5. Add to WeaponHolder; hide and disable physics until equipped
6. If ranged: connect `ammo_changed` signal
7. Call `_equip_slot(slot)`

### WeaponPickup scene

```
WeaponPickup (StaticBody3D)   ← weapon_pickup.gd
├── CollisionShape3D          ← BoxShape3D (collision layer 3, mask 0)
└── MeshInstance3D            ← mesh/scale/rotation set from WeaponRegistry in _ready()
```

Player detects pickups via a raycast from camera (mask = layer 3, 20m). Hovering highlights via `material_overlay`. Press `F` to collect.

---

## 10. HUD System

**Scripts:** `scripts/hud.gd`, `scripts/hud_stance_indicator.gd`, `scripts/crosshair.gd`  
**Scene:** `hud.tscn` (CanvasLayer)

```
CanvasLayer (hud.gd)
├── WeaponLabel         ← bottom-left; shows "[FISTS]" etc.
├── AmmoLabel           ← bottom-right; shows "6 / 6"
├── ReloadLabel         ← bottom-right; shows "[R] RELOAD" when ammo=0
├── PickupPrompt        ← center; shows "F — pick up [weapon]" on hover
├── HpBar               ← ProgressBar, bottom-left above silhouette
├── BodySilhouette      ← Control with 14 named ColorRect children
│   ├── head_top, head_bottom
│   ├── torso_top, torso_bottom
│   ├── arm_l_upper, arm_l_fore, hand_l
│   ├── arm_r_upper, arm_r_fore, hand_r
│   ├── leg_l_upper, leg_l_fore
│   └── leg_r_upper, leg_r_fore
├── HudStanceIndicator  ← hud_stance_indicator.gd
│   ├── Row_THRUST (HBoxContainer)
│   ├── Row_HIGH   (HBoxContainer)
│   ├── Row_MID    (HBoxContainer)
│   └── Row_LOW    (HBoxContainer)
└── [Crosshair — Control added at runtime from crosshair.gd]
```

### HUD public API

| Method | Called from | What it does |
|---|---|---|
| `update_health(current, maximum)` | Player._on_hp_changed | Sets HpBar value |
| `update_body_silhouette(health_system)` | Player._on_hp_changed | Colors all 14 rects |
| `update_ammo(current, max)` | Player._on_ammo_changed | Updates AmmoLabel/ReloadLabel |
| `set_weapon_name(name)` | Player._equip_slot | Updates WeaponLabel |
| `update_stance(stance, available)` | Player._on_stance_changed | Delegates to HudStanceIndicator |
| `show_pickup_prompt(name)` | Player._update_pickup_highlight | Shows PickupPrompt |
| `hide_pickup_prompt()` | Player._update_pickup_highlight | Hides PickupPrompt |
| `recoil(kick, recovery)` | Player.trigger_crosshair_recoil | Delegates to Crosshair |

**The HUD is only wired to the Player, not to Dummy or Brawler.** Brawler and Dummy are NPCs and do not need HUD integration. When multiplayer is added, each human player will need their own HUD — the hardcoded path `"/root/test_scene/hud"` will need to be replaced with per-player HUD references at that point.

### HudStanceIndicator

Only visible when a melee weapon is equipped (`available` array is non-empty). Hides rows for stances not available on the current weapon (e.g. THRUST row hidden for bat). Active stance row shown in yellow, inactive in dim grey.

### Crosshair

Canvas-space `_draw()` control. Four arms + center dot. Gap expands on fire (`recoil()`) and decays back. `DECAY_CURVE / recovery_time` sets the decay rate.

### Stance system

**Script:** `scripts/stance_manager.gd` (`class_name StanceManager`)  
Lives as a child node of Player (`scenes/player.tscn`).

```gdscript
enum Stance { LOW, MID, HIGH, THRUST }
signal stance_changed(stance: Stance)
```

- `setup(stances)` — called on weapon equip; must include `MID`; resets to `MID`
- `cycle(direction)` — called by scroll wheel input; wraps around available stances
- Available stances per weapon:
  - Bat: `[LOW, MID, HIGH]`
  - Katana: `[LOW, MID, HIGH, THRUST]`
  - Fists: `[LOW, MID, HIGH]`
  - Ranged: not set up (scroll is no-op)

---

## 11. Camera System

**Relevant code in:** `scripts/player.gd`

The `CameraPivot` node has `top_level = true` — it follows the player's **position** only, not rotation. This decouples camera yaw from player facing.

| Constant | Value | Meaning |
|---|---|---|
| `CAM_HEIGHT` | 11 | Camera Y offset from pivot |
| `CAM_Z_OFFSET` | 10 | Camera Z offset from pivot |
| `CAM_PITCH` | -45° | Camera X tilt (top-down angle) |
| `CAM_DEFAULT_YAW` | 90° | Starting camera Y rotation |
| `CAM_FOLLOW_SPEED` | 8.0 | Lerp factor for position follow |
| `CAM_ROT_SENS` | 0.005 rad/px | Orbit sensitivity |
| `CAM_ROT_FRICTION` | 3.0 | Decay rate after orbit release |

**Mouse aim:** Player faces the mouse cursor projected onto the `y=0` plane each physics tick via `get_mouse_world_pos()`.

**Screen shake:** `_shake_strength` float. Set via `trigger_hit_shake(strength)`. Decays at rate 18.0/s.

**Camera orbit:** Middle-mouse drag rotates `CameraPivot` around Y. Velocity persists after release and decays via friction (inertia glide).

---

## 12. FOV / Visibility System

**Scripts:** `scripts/fov_overlay.gd` (`class_name FovOverlay`), `shaders/fov_world.gdshader`

Created and owned by Player. A full-screen quad with a `ShaderMaterial` is added to the scene. FovOverlay (a child Node of Player) updates the shader parameters each frame.

| Constant | Value |
|---|---|
| `RAY_COUNT` | 96 |
| `VISION_RADIUS` | 12.0 world units |
| `FOV_ANGLE` | 120° total cone |
| `PROXIMITY_RADIUS` | 3.0 world units (always visible around player) |

The shader reads the depth buffer to reconstruct world XZ per pixel, then runs a Jordan curve test against the 128-point polygon uploaded by FovOverlay. This is height-agnostic — walls, pillars, and floor all occlude correctly.

**Entity visibility:** Brawler and Dummy each check `FovOverlay.instance.is_visible_xz(xz)` in `_process()` / `_physics_process()` and set their own `visible` flag. The static `instance` var is set by FovOverlay at `_ready()`.

---

## 13. Debris & Effects

**Script:** `scripts/debris_pool.gd` (`class_name DebrisPool`)  
**Lives in scene as:** `test_scene/DebrisPool`  
**Access pattern:** `DebrisPool.instance` (static var set in `_ready()`)

### Pool sizes

| Resource | Count | Lifetime |
|---|---|---|
| RigidBody3D cubes | 80 | 3.0s, then frozen and hidden |
| GPUParticles3D | 1 (reused) | 0.6s burst |
| Decal blood stains | 60 | 20.0s |

The cube pool is ring-buffered (cursor wraps). Oldest cube is recycled without cleanup. On expiry, a blood-stain Decal is placed at the cube's resting position.

### `spawn_cube(world_pos, color, impulse)`
- Takes next cube in ring
- Unfreezes it, applies impulse
- Bone/grey voxels become dark maroon; colored voxels become bright red
- Timer auto-freezes and hides after 3s, places stain decal

### `spawn_particles(world_pos)`
- Moves the single GPUParticles3D and calls `restart()`

### BulletTracer

**Script:** `scripts/bullet_tracer.gd` (`class_name BulletTracer`)  
Not pooled — self-deletes via tween. Call: `BulletTracer.spawn(from, to, color, parent)`.

The streak is a 1.5m box mesh that travels at 80 m/s from muzzle to impact, then fades in 0.1s. It is parented to `get_tree().root` so it outlives the weapon node.

---

## 14. Autoloads & Singletons

| Name | Type | Script | Registered in project settings? |
|---|---|---|---|
| `DamageManager` | Node (autoload) | `scripts/damage_manager.gd` | Yes |
| `WeaponRegistry` | Node (autoload) | `scripts/weapon_registry.gd` | Yes |
| `DebrisPool` | Scene node with static `instance` var | `scripts/debris_pool.gd` | No — placed in scene |
| `FovOverlay` | Node child of Player with static `instance` var | `scripts/fov_overlay.gd` | No — created by Player._ready() |

**DamageManager** and **WeaponRegistry** are true autoloads (accessible globally by name).

**DebrisPool.instance** and **FovOverlay.instance** are static vars. They are valid only while those nodes are in the scene tree. Code that uses them guards with `is_instance_valid()`.

---

## 15. Physics Layers

| Layer # | Bitmask | Used by | Purpose |
|---|---|---|---|
| 1 | 1 | Static level geometry | Wall raycast (ranged weapons), FOV visibility rays |
| 2 | 2 | VoxelSegment Area3D | Melee overlap detection, ranged voxel raycast |
| 3 | 4 | WeaponPickup StaticBody3D | Pickup highlight raycast from Player |

Layer 4+ currently unused.

**Key rules:**
- VoxelSegment Area3Ds are on layer 2 with mask 0 — they receive hits but do not query anything themselves
- Melee HitArea uses mask 2 with `collide_with_areas = true, collide_with_bodies = false`
- Ranged wall ray uses mask 1 with `collide_with_bodies = true`
- Ranged voxel ray uses mask 2 with `collide_with_areas = true`
- Pickup raycast uses mask 4 with `collide_with_areas = false`

When a segment detaches, its Area3D `collision_layer` is set to 0 so it stops receiving hits.

---

## 16. Signal Map

### Player signals (received)

| Signal | Source | Handler | Effect |
|---|---|---|---|
| `stance_changed(stance)` | StanceManager | `_on_stance_changed` | HUD.update_stance |
| `animation_finished(name)` | AnimationPlayer | `_on_anim_finished` | clears `_is_attacking` |
| `ammo_changed(cur, max)` | WeaponRanged | `_on_ammo_changed` | HUD.update_ammo |
| `hp_changed(cur, max)` | HealthSystem | `_on_hp_changed` | HUD.update_health + update_body_silhouette |
| `died` | HealthSystem | `_die()` | sets `_is_dead`, drops weapons, starts ragdoll + 5s timer |
| `leg_lost(seg_name)` | LimbSystem | `_on_leg_lost` | records seg in `_lost_legs` → speed multiplier |
| `segment_broken(seg_name)` | LimbSystem | `_on_segment_broken` | disables weapon slot for that arm side; drops held weapon |
| `detached(seg)` | VoxelSegment (arm/hand segs) | `_on_arm_segment_detached` | same effect as segment_broken — idempotent |
| `timeout` | SceneTreeTimer (5s) | `_respawn()` | rebuilds body, teleports to spawn point |

### Brawler signals (emitted)

| Signal | When | Receiver |
|---|---|---|
| `died` | `_die()` called | main.gd (debug print) |

### Dummy signals (emitted)

| Signal | When | Receiver |
|---|---|---|
| `died` | `_die()` called | main.gd (debug print) |

### LimbSystem signals (emitted)

| Signal | When | Receiver |
|---|---|---|
| `leg_lost(seg_name)` | A leg segment detaches (root only — cascade descendants suppressed by `_cascading` guard) | Player / Brawler `_on_leg_lost` |
| `segment_broken(seg_name)` | Each segment in `_spawn_broken_ragdoll`'s chain loop, after `is_broken = true`. Fires once per newly-broken segment — one call for the root, one per cascade descendant. | Player `_on_segment_broken` |

### VoxelSegment → systems

| Signal | Connected to | On every segment |
|---|---|---|
| `detached(seg)` | `LimbSystem._on_segment_detached` | Yes, bound with seg_name |
| `detached(seg)` | `HealthSystem._on_segment_detached` | Yes, bound with seg_name |
| `detached(seg)` | `Player._on_arm_segment_detached` | Arm/hand segs only (`hand_r/l`, `arm_r/l_fore`, `arm_r/l_upper`), bound with seg_name. Fires for each segment in a cascade; handler is idempotent. VoxelSegment nodes are freed on respawn — connections auto-clean. |

### Full damage chain

```
Player/Brawler input
    ↓
WeaponMelee._attack() / WeaponRanged._fire()
    ↓
WeaponBase._apply_hit(seg, local_pos)
    ↓
DamageManager.process_hit(seg, pos, radius, damage, type)
    ├── VoxelSegment.take_hit() → debris + voxel removal + connectivity check
    │       └── [if root row destroyed] seg.detach()
    │               ├── LimbSystem._on_segment_detached → ragdoll
    │               └── HealthSystem._on_segment_detached → _refresh()
    ├── LimbSystem.on_hit() → integrity drain → break/detach checks
    └── HealthSystem.on_hit() → _refresh()
            ├── hp_changed → Player._on_hp_changed → HUD
            └── [if HP≤0] died → Player._die() → LimbSystem.die() → death ragdoll
```

---

## 17. Death & Respawn

**Relevant code in:** `scripts/player.gd`  
**Spawn points in:** `scenes/test_scene.tscn`

### Overview

When Player HP reaches zero, the voxel body ragdolls, held weapons drop as world pickups, and after 5 seconds the player teleports to a random spawn point with a freshly rebuilt body and fists only.

### Spawn points

Four `Marker3D` nodes in `test_scene.tscn`, each in the `"spawn_point"` group:

| Node | Position |
|---|---|
| SpawnPoint1 | (+5, 0, +5) |
| SpawnPoint2 | (−5, 0, +5) |
| SpawnPoint3 | (+5, 0, −5) |
| SpawnPoint4 | (−5, 0, −5) |

`_respawn()` queries the group at runtime: `get_tree().get_nodes_in_group("spawn_point")`. Positions can be tuned in the editor without any code changes.

**`.tscn` group syntax note:** In Godot 4, groups must be declared as a header attribute inside the `[node ...]` brackets — `[node name="..." type="..." parent="." groups=["spawn_point"]]` — not as a separate property line below the header (which is silently ignored by Godot).

### `_die()` flow

1. Guard: `if _is_dead: return`. Set `_is_dead = true`, `_is_attacking = false`, `velocity = Vector3.ZERO`.
2. Drop melee and ranged slots via `_drop_weapon()` — weapons land in the world as `WeaponPickup` nodes.
3. Disable `$CollisionShape3D` so the dead player doesn't block movement.
4. Call `_limb_system.die()` — `_spawn_death_ragdoll()` fires immediately (full-body RigidBody3D chain with PinJoint3D).
5. Start a 5-second `SceneTreeTimer`; on timeout call `_respawn()`.

### `_respawn()` flow

1. Free all nodes in the `"detached_limb"` group (ragdoll pieces from the death ragdoll).
2. Pick a random `Marker3D` from `"spawn_point"` group; set `global_position`.
3. Re-enable `$CollisionShape3D`.
4. Reparent `weapon_holder` back to `camera` with identity transform **before** freeing the skeleton (the current `_weapon_anchor` is a skeleton child and is about to be freed).
5. Free all inventory weapons (including fists). Disconnect `ammo_changed` before freeing ranged weapons. Clear `_inventory` entries to `null`.
6. Disconnect and free `LimbSystem` and `HealthSystem`. Explicitly disconnect `leg_lost`, `hp_changed`, and `died` signals before `queue_free` to prevent double-respawn on a second death.
7. Free all `_attachments` (BoneAttachment3D nodes) and clear the array.
8. `await get_tree().process_frame` — lets `queue_free` propagate before rebuilding.
9. Reset state: `_lost_legs.clear()`, `_hand_usable = {"r": true, "l": true}`, `_is_attacking = false`, `_current_slot = SLOT_FISTS`, `_weapon_anchor = null`, `segments.clear()`, `_is_dead = false`.
10. Re-create fists: instantiate from `WeaponRegistry`, set `_player` and `weapon_id`, add to `weapon_holder`, store in `_inventory[SLOT_FISTS]`.
11. Call `_build_voxel_body()` — rebuilds all 14 segments, wires new `LimbSystem` and `HealthSystem`, reparents `weapon_holder` to new `_weapon_anchor`.
12. Manually call `_on_hp_changed(_health_system._compute_hp(), HealthSystem.MAX_HP)` to force-refresh the HUD. This is necessary because `HealthSystem.initialize()` fires `hp_changed` during `_build_voxel_body()` before the signal is re-connected, so the HUD misses it.
13. Call `_equip_slot(SLOT_FISTS)` — HUD weapon name, stance, and HP bar all update via their existing signal paths.

### Signal cleanup pattern

Before calling `queue_free` on `LimbSystem` or `HealthSystem`, disconnect signals with `is_connected()` guards:

```gdscript
if _limb_system.leg_lost.is_connected(_on_leg_lost):
    _limb_system.leg_lost.disconnect(_on_leg_lost)
if _limb_system.segment_broken.is_connected(_on_segment_broken):
    _limb_system.segment_broken.disconnect(_on_segment_broken)
if _health_system.hp_changed.is_connected(_on_hp_changed):
    _health_system.hp_changed.disconnect(_on_hp_changed)
if _health_system.died.is_connected(_die):
    _health_system.died.disconnect(_die)
```

VoxelSegment `detached` connections to `Player._on_arm_segment_detached` do not need explicit disconnects — the VoxelSegment nodes are freed when `_attachments` are cleared, and Godot auto-disconnects signals from freed nodes.

Without this, the `died` signal fires again from the freed node on the second death, triggering a second `_respawn()` call.

---

*Document complete as of 2026-04-26.*
