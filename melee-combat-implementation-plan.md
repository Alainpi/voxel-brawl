# Melee Combat Overhaul — Implementation Plan

*Directional Stance System + Bone-Attached Sweep Detection*

**Status:** Planning
**Depends on:** 14-segment character (complete), weapon animations (in progress)
**Replaces:** Current single-frame AABB shape query in `WeaponMelee._do_hit()`

---

## 1. Problem Summary

The current melee system fires a single-frame shape query at a hardcoded timer delay after the attack button is pressed. The query uses the weapon mesh's rest-pose AABB, which has no relationship to where the weapon visually is during the swing. This causes five interrelated issues:

- Hits miss when timing is even slightly off (single-frame snapshot)
- The hit delay timer is disconnected from the actual animation state
- The AABB represents the weapon at rest, not mid-swing
- No way to target specific body parts (legs vs head vs arms)
- No persistent hit window across the swing arc

Full issue description: `melee_weapon_issues.md`

---

## 2. Solution Overview

A three-part hybrid system:

1. **Directional Stance Selector** (inspired by For Honor) — scroll wheel cycles through attack stances that determine swing height/direction. Each stance maps to a distinct animation.
2. **Bone-Attached Area3D with Animation-Driven Activation** — the weapon hitbox lives on the hand bone and the AnimationPlayer controls when it's "live," eliminating timing mismatches.
3. **Per-Frame Blade-Tip Sweep Raycast** — during the active window, the weapon's tip position is tracked frame-to-frame and a shape sweep detects which VoxelSegment(s) the blade passed through, giving precise hit points for voxel destruction.

---

## 3. Stance System Design

### 3a. Stances Per Weapon Type

**Blunt weapons (Fists, Bat) — 3 stances:**

| Stance | Scroll Position | Target Zone | Animation Arc |
|--------|----------------|-------------|---------------|
| Low | Bottom | Legs, lower body | Low horizontal sweep or rising diagonal |
| Mid | Middle (default) | Torso, arms | Horizontal swing at chest height |
| High | Top | Head, upper torso | Overhead smash or high diagonal |

**Sharp weapons (Katana) — 4 stances:**

| Stance | Scroll Position | Target Zone | Animation Arc |
|--------|----------------|-------------|---------------|
| Low | Bottom | Legs, lower body | Low sweeping slash |
| Mid | Middle (default) | Torso, arms | Horizontal slash at chest height |
| High | Top | Head, upper torso | Overhead diagonal slash |
| Thrust | Beyond High (wraps) | Single point, center mass | Forward stab along facing direction |

Scroll wraps: Low → Mid → High → (Thrust if sharp) → Low.

### 3b. Input Handling

- `scroll_up` → advance stance one step higher
- `scroll_down` → advance stance one step lower
- Stance persists between swings (player doesn't need to re-select each attack)
- Weapon switch resets stance to Mid (the safest default)
- Remove scroll-to-switch-weapon (weapons switch via number keys or pickup only)

### 3c. HUD Indicator

A small widget near the crosshair showing the current stance. For blunt weapons: three horizontal bars stacked vertically (Low / Mid / High) with the active one highlighted. For sharp weapons: three bars plus a forward-pointing arrow icon for Thrust. The indicator should be subtle enough to not clutter the screen but readable at a glance.

Placement: offset slightly from the crosshair — bottom-right or directly below. Should not overlap the FOV overlay or health bar.

---

## 4. Animations Required

Each weapon needs a distinct attack animation per stance. The animation must physically move the weapon mesh through the correct height band so that the blade-tip sweep raycast hits the right body segments.

### 4a. Fists

| Animation Name | Stance | Description |
|---------------|--------|-------------|
| `punch_low` | Low | Low gut punch or uppercut from below |
| `punch_mid` | Mid | Straight jab at chest height (current punch anim, reuse or tweak) |
| `punch_high` | High | Overhead hook or high cross aimed at head |

### 4b. Bat

| Animation Name | Stance | Description |
|---------------|--------|-------------|
| `bat_low` | Low | Low sweeping swing at knee/shin height |
| `bat_mid` | Mid | Horizontal baseball swing at torso height (current bat anim base) |
| `bat_high` | High | Overhead slam coming down onto head/shoulders |

### 4c. Katana

| Animation Name | Stance | Description |
|---------------|--------|-------------|
| `katana_low` | Low | Low sweeping slash at leg height |
| `katana_mid` | Mid | Horizontal slash at torso height (current katana anim base) |
| `katana_high` | High | Diagonal slash from upper-left to lower-right (or overhead) |
| `katana_thrust` | Thrust | Forward stab, blade extends straight out along facing direction |

### 4d. Animation Requirements for Hit Detection

Each attack animation must include:

- **Method call track at swing start frame:** calls `_enable_hitbox()` on the weapon script
- **Method call track at swing end frame:** calls `_disable_hitbox()` on the weapon script
- The weapon mesh must physically move through the target height band during the active window (this is what makes the sweep raycast work)
- Keep the active window tight — roughly 3–6 frames at 30fps (0.1–0.2 seconds). Too long and hits feel sloppy, too short and they feel like the old system.

---

## 5. Hit Detection Implementation

### 5a. Bone-Attached Area3D (Activation Window)

**Setup per weapon:**

- Add a child `Area3D` node to each weapon's scene (under the weapon mesh node)
- The Area3D has a `CollisionShape3D` shaped to roughly match the weapon's damaging surface:
  - Bat: elongated capsule or box along the barrel length
  - Katana: thin box along the blade length
  - Fists: small sphere at each fist
- Set collision layer so it only detects VoxelSegment Area3Ds (mask = 2, matching existing segment collision)
- **Disabled by default** — `CollisionShape3D.disabled = true`

**Activation via AnimationPlayer:**

The method call tracks in each attack animation call:

```
_enable_hitbox()   # at swing start frame
_disable_hitbox()  # at swing end frame
```

These methods toggle `CollisionShape3D.disabled` and set an `_is_attacking` flag.

**Signal connections:**

While active, the Area3D's `area_entered` signal fires for each VoxelSegment Area3D it overlaps. These are collected into a `_hit_segments` array. The same segment is only counted once per swing (track by segment reference).

### 5b. Blade-Tip Sweep Raycast (Precision Hits)

This runs in parallel with the Area3D and provides the exact hit point for voxel destruction.

**Setup:**

- Add a `Marker3D` node called `BladeTip` at the end of each weapon mesh (the striking end of the bat, the tip of the katana blade, the knuckle point for fists)
- Add a second `Marker3D` called `BladeBase` partway up the weapon (where the blade meets the handle) — this allows sweeping a line segment rather than a single point for wider coverage

**Per-frame sweep during active window:**

```
# In _physics_process(), while _is_attacking:
var tip_now = blade_tip.global_position
var base_now = blade_base.global_position

if _prev_tip_pos != Vector3.INF:
    # Sweep from last frame to this frame
    _sweep_check(_prev_tip_pos, tip_now)
    _sweep_check(_prev_base_pos, base_now)

_prev_tip_pos = tip_now
_prev_base_pos = base_now
```

**Sweep check method:**

```
func _sweep_check(from: Vector3, to: Vector3) -> void:
    var space = get_world_3d().direct_space_state
    var query = PhysicsRayQueryParameters3D.create(from, to, 2)  # mask 2 = segments
    query.collide_with_areas = true
    query.collide_with_bodies = false
    var result = space.intersect_ray(query)
    if result and result.collider is Area3D:
        var area = result.collider as Area3D
        if area.has_meta("voxel_segment"):
            var seg = area.get_meta("voxel_segment") as VoxelSegment
            if seg not in _hit_segments:
                _hit_segments.append(seg)
                var local_hit = seg.to_local(result.position)
                _apply_hit(seg, local_hit)
```

This gives the exact world-space intersection point, converted to the segment's local space for precise voxel removal. The voxels that get carved are exactly where the blade tip traveled.

### 5c. Multi-Hit Behavior

The sweep naturally supports hitting multiple segments in a single swing. A horizontal katana slash that passes through `arm_r_upper` and then `torso_top` will register hits on both. Each segment is only hit once per swing (tracked in `_hit_segments`), but a single swing can damage multiple segments.

Per-weapon multi-hit policy:

- **Fists:** Single segment per punch (small hitbox, short reach)
- **Bat:** Up to 2 segments per swing (wide impact area)
- **Katana swings:** Up to 2–3 segments per slash (long blade, sweeping arc)
- **Katana thrust:** Single segment (narrow linear path, deep penetration)

Enforce by capping `_hit_segments.size()` per weapon if needed, but the natural physics should mostly self-regulate.

### 5d. Thrust-Specific Behavior (Katana)

The thrust stance is mechanically different from swings:

- Animation drives the blade straight forward rather than in an arc
- The sweep raycast traces a mostly linear path, so it hits a narrow area
- Deeper effective `voxel_radius` along the forward axis to simulate penetration (e.g. 1.5x normal radius in the forward direction, 0.5x laterally)
- Longer reach than swings (the blade extends further forward)
- Hits only one segment but with higher concentrated damage
- Visually: the blade punches a narrow hole straight through voxels rather than carving a wide groove

---

## 6. Code Changes

### 6a. New Files

| File | Purpose |
|------|---------|
| `scripts/stance_manager.gd` | Manages current stance per weapon type, handles scroll input, emits `stance_changed` signal |
| `scenes/hud_stance_indicator.tscn` + `scripts/hud_stance_indicator.gd` | HUD widget showing current stance |

### 6b. Modified Files

| File | Changes |
|------|---------|
| `scripts/weapon_melee.gd` | Replace `_do_hit()` entirely. Add `_enable_hitbox()`, `_disable_hitbox()`, `_physics_process` sweep logic, `_hit_segments` tracking. Add `blade_tip` / `blade_base` Marker3D references. Add stance-aware animation selection. |
| `scripts/weapon_bat.gd` | Update `_configure()` with per-stance animation names. Set multi-hit cap. Remove old `hit_delay` / `hit_sphere_radius`. |
| `scripts/weapon_katana.gd` | Same as bat, plus thrust-specific config (deeper voxel radius, single-hit cap, longer reach). |
| `scripts/weapon_fists.gd` | Same pattern, 3 stances, single-hit cap, shorter reach. |
| `scripts/weapon_base.gd` | Add `weapon_type` enum (BLUNT, SHARP) so stance_manager knows how many stances to offer. |
| `scripts/player.gd` | Remove scroll-wheel weapon switching. Route scroll input to `StanceManager`. Connect stance_changed to HUD. |
| `hud.tscn` / `scripts/hud.gd` | Add stance indicator widget. |
| Attack animation files (.glb) | Add method call tracks for `_enable_hitbox()` / `_disable_hitbox()` at correct frames. |

### 6c. Removed Code

- `WeaponMelee.hit_delay` timer — replaced by animation-driven activation
- `WeaponMelee._do_hit()` shape query — replaced by Area3D + sweep
- AABB-based hit shape construction from weapon mesh — no longer needed
- Scroll-wheel weapon switching in `player.gd`

---

## 7. Weapon Scene Setup

Each weapon `.tscn` needs the following node structure:

```
WeaponBat (Node3D, script: weapon_bat.gd)
├── MeshInstance3D (bat model)
├── AudioStreamPlayer3D
├── HitArea (Area3D, collision mask = 2)
│   └── HitShape (CollisionShape3D, disabled = true)
│       └── shape: CapsuleShape3D / BoxShape3D sized to weapon
├── BladeTip (Marker3D — at far striking end)
└── BladeBase (Marker3D — at handle/grip end)
```

For fists, BladeTip goes at the knuckles and BladeBase at the wrist. For katana, BladeTip is at the blade tip and BladeBase is where blade meets guard.

The HitArea and Markers move with the hand bone during animations because the weapon is a child of the BoneAttachment3D on the hand.

---

## 8. Damage Behavior Per Stance

### 8a. Swing Stances (Low / Mid / High) — All Weapons

| Property | Fists | Bat | Katana |
|----------|-------|-----|--------|
| Arc width | ~60° | ~90° | ~70° |
| voxel_radius | 1.5 | 2.8 | 0.7 |
| Damage | 8 | 22 | 45 |
| Multi-hit cap | 1 | 2 | 3 |
| Cooldown | 0.35s | 0.65s | 0.3s |
| Destruction feel | Small dent | Wide crushing crater | Thin surgical slice |

### 8b. Thrust Stance — Katana Only

| Property | Value |
|----------|-------|
| voxel_radius (forward) | 1.0 (deeper than slash) |
| voxel_radius (lateral) | 0.4 (narrower than slash) |
| Damage | 55 (higher than slash — focused force) |
| Multi-hit cap | 1 (single segment penetration) |
| Reach | 1.3 (longer than slash, 1.0) |
| Cooldown | 0.4s (slightly slower recovery than slash) |
| Destruction feel | Deep narrow puncture hole through voxels |

---

## 9. Implementation Order

### Step 1: Stance Manager + HUD (no combat changes yet)
- Implement `StanceManager` with scroll input and stance cycling
- Build HUD indicator widget
- Wire scroll input in `player.gd` (remove weapon switching from scroll)
- Test: scroll changes stance, HUD updates, no combat behavior changes

### Step 2: Animation Integration
- Add all stance-specific attack animations to the .glb rig
- Add method call tracks (`_enable_hitbox` / `_disable_hitbox`) in Godot's AnimationPlayer editor or in Blender
- Wire `play_attack_anim()` to select animation based on current stance
- Test: correct animation plays per stance, method calls fire at right frames

### Step 3: Area3D Hitbox Setup
- Add HitArea (Area3D + CollisionShape3D) to each weapon scene
- Implement `_enable_hitbox()` / `_disable_hitbox()` toggling
- Connect `area_entered` signal, collect hit segments during active window
- Remove old `_do_hit()` shape query and `hit_delay` timer
- Test: swings register hits through Area3D overlap, correct segments get damaged

### Step 4: Blade-Tip Sweep Raycast
- Add BladeTip / BladeBase Marker3D nodes to each weapon scene
- Implement per-frame sweep in `_physics_process` during active window
- Use sweep hit point for precise `local_hit` position in voxel destruction
- Test: hit points correspond to where blade visually connects, voxels carve at correct location

### Step 5: Thrust Implementation (Katana)
- Add katana_thrust animation with forward stab motion
- Implement thrust-specific damage config (deeper forward radius, narrower lateral radius, single-hit cap)
- Test: thrust punches a narrow deep hole, distinct from slash groove

### Step 6: Polish + Tuning
- Per-weapon screen shake intensity per stance
- Hit audio variation per stance (low thuds for leg hits, sharp cracks for head hits)
- Weapon trail VFX during active window (visual feedback for swing arc)
- Tune all damage values, voxel radii, cooldowns through playtesting
- Edge case testing: attacking while moving, hitting multiple enemies, hitting detached limbs mid-air

---

## 10. Animation Notes for Blender

Guidelines for creating the stance-specific attack animations:

- **Swing height matters mechanically.** A "low" animation must physically move the weapon mesh through the height band where leg segments exist (~0.0–0.6 units above ground). If the animation doesn't bring the weapon down there, the sweep raycast won't hit legs regardless of the stance label.
- **Keep active windows short.** The weapon should be in the "striking" part of the arc for 0.1–0.2 seconds. Windup and recovery can be longer, but the active damage frames should be tight.
- **Thrust is forward, not arcing.** The katana thrust should extend the blade straight forward from the hand, with minimal lateral movement. The animation should emphasize the lunge/extend motion.
- **Return to idle cleanly.** Each attack animation should blend smoothly back into the idle or walk pose. Avoid ending on a held pose — the player needs to be able to move immediately after the cooldown.
- **Bone names in method call tracks:** The AnimationPlayer tracks should call methods on the weapon node path. The exact path depends on how weapons are attached in the scene tree. Document the path once the first animation is wired up and keep it consistent across all weapons.
