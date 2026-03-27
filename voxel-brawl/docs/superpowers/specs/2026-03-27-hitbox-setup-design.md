# Step 3 Design: Area3D Hitbox Setup

**Date:** 2026-03-27
**Status:** Approved
**Implements:** Melee Combat Overhaul — Step 3
**Master plan:** `melee-combat-implementation-plan.md` §9 Step 3

---

## Problem

The current `WeaponMelee._do_hit()` fires a single-frame AABB shape query at a hardcoded `hit_delay` offset from attack start. The AABB is the weapon's rest-pose bounding box — unrelated to where the weapon is mid-swing. Result: hits miss or feel disconnected from the animation, audio and shake feedback are broken (unreachable code after `break`), and there is no meaningful hit window.

---

## Solution Overview

Replace `_do_hit()` and `hit_delay` with an **Area3D hitbox** on each weapon that is enabled for a configurable time window during the swing. The hitbox moves with the weapon (which already follows the hand bone via `WeaponHolder` reparenting). Overlapping VoxelSegment areas are collected and deduped per swing, with a per-weapon `max_hits` cap.

Hitbox timing uses two consecutive timers (Option A — programmatic), chosen over AnimationPlayer method call tracks because:
- The attack animations are in an imported `.glb`; Godot cannot write method call tracks back to `.glb`
- Damage values and timing will need tuning; frame-accurate tracks would need to be repositioned every iteration
- Method call tracks can be added as Step 6 polish once timing is dialed in

---

## Architecture

### Files changed

| File | Change |
|------|--------|
| `scripts/weapon_melee.gd` | Core changes — see below |
| `scripts/weapon_fists.gd` | Update `_configure()`: add hitbox vars, remove `hit_sphere_radius` |
| `scripts/weapon_bat.gd` | Same |
| `scripts/weapon_katana.gd` | Same |

No changes to `player.gd`, `weapon_base.gd`, or any `.tscn` file.

### Files removed (code only, no files deleted)

- `WeaponMelee.hit_delay`
- `WeaponMelee.hit_sphere_radius`
- `WeaponMelee._do_hit()`

---

## `weapon_melee.gd` Changes

### New vars

```gdscript
var hit_enable_delay := 0.1      # seconds from attack start until hitbox activates
var hit_window_duration := 0.15  # how long the hitbox stays active
var max_hits := 1                # max segments hit per swing; subclasses override
var hit_shape: Shape3D = null    # set by subclass in _configure()
var hit_shape_offset: Vector3 = Vector3.ZERO

var _hit_area: Area3D = null
var _hit_segments: Array[VoxelSegment] = []
```

### `_ready()` override

```gdscript
func _ready() -> void:
    super()          # WeaponBase._ready(): calls _configure(), sets _player
    _create_hitarea()
```

### `_create_hitarea()` — virtual, overridable

Default implementation handles single-shape weapons. Complex weapons (e.g. axe) override this to add multiple `CollisionShape3D` children.

```gdscript
func _create_hitarea() -> void:
    _hit_area = Area3D.new()
    _hit_area.collision_layer = 0
    _hit_area.collision_mask = 2   # matches VoxelSegment area layer
    _hit_area.monitorable = false
    if hit_shape:
        var col := CollisionShape3D.new()
        col.shape = hit_shape
        col.position = hit_shape_offset
        col.disabled = true
        _hit_area.add_child(col)
    add_child(_hit_area)
    _hit_area.area_entered.connect(_on_hit_area_entered)
```

### `_enable_hitbox()` / `_disable_hitbox()`

Iterates all `CollisionShape3D` children so composite hitboxes work without extra logic.

```gdscript
func _enable_hitbox() -> void:
    for child in _hit_area.get_children():
        if child is CollisionShape3D:
            child.disabled = false

func _disable_hitbox() -> void:
    for child in _hit_area.get_children():
        if child is CollisionShape3D:
            child.disabled = true
```

### `_attack()` — revised

```gdscript
func _attack() -> void:
    _cooldown_timer = cooldown
    _hit_segments.clear()
    _player.play_attack_anim(attack_anim)
    await get_tree().create_timer(hit_enable_delay).timeout
    if not _player._is_attacking:
        return   # interrupted by death or weapon swap
    _enable_hitbox()
    await get_tree().create_timer(hit_window_duration).timeout
    _disable_hitbox()
```

### `_on_hit_area_entered()`

Applies damage immediately on first overlap per segment. Audio and shake fire on the first hit only per swing.

```gdscript
func _on_hit_area_entered(area: Area3D) -> void:
    if _hit_segments.size() >= max_hits:
        return
    if not area.has_meta("voxel_segment"):
        return
    var seg: VoxelSegment = area.get_meta("voxel_segment")
    if seg in _hit_segments:
        return
    _hit_segments.append(seg)
    var local_hit := seg.to_local(_hit_area.global_position)
    _apply_hit(seg, local_hit)
    if _hit_segments.size() == 1:
        if audio.stream:
            audio.play()
        _player.trigger_hit_shake()
        _player.trigger_crosshair_recoil()
```

---

## Per-Weapon Configuration

### Starting values (tune in-game)

| Var | Fists | Bat | Katana |
|-----|-------|-----|--------|
| `hit_shape` | `SphereShape3D` r=0.3 | `CapsuleShape3D` r=0.15 h=0.8 | `BoxShape3D` 0.05×0.6×0.05 |
| `hit_shape_offset` | `Vector3(0, 0, -0.3)` | `Vector3(0, 0.4, 0)` | `Vector3(0, 0.3, 0)` |
| `hit_enable_delay` | 0.08 | 0.2 | 0.1 |
| `hit_window_duration` | 0.12 | 0.18 | 0.15 |
| `max_hits` | 1 | 2 | 3 |

Each subclass removes `hit_sphere_radius` from `_configure()`.

---

## Future Weapons — Complex Hitbox Shapes

Weapons with non-uniform geometry (axe, halberd, flail) override `_create_hitarea()` directly. The base `_enable_hitbox()` / `_disable_hitbox()` logic still works because it iterates children rather than holding a single shape reference.

Example for a double-bitted axe:

```gdscript
# weapon_axe.gd
func _create_hitarea() -> void:
    super()  # sets up _hit_area and connects area_entered
    # Add second shape for lower axe blade
    var beard := CollisionShape3D.new()
    var s := BoxShape3D.new()
    s.size = Vector3(0.4, 0.15, 0.05)
    beard.shape = s
    beard.position = Vector3(0, -0.2, 0)
    beard.disabled = true
    _hit_area.add_child(beard)
```

No other method changes needed — `_enable_hitbox()` / `_disable_hitbox()` pick up the new child automatically.

---

## Removals

### `weapon_melee.gd`
- `var hit_delay := 0.15`
- `var hit_sphere_radius := 0.8`
- `func _do_hit() -> void` (entire method)
- `await get_tree().create_timer(hit_delay).timeout` + `_do_hit()` call in `_attack()`

### Each subclass `_configure()`
- `hit_sphere_radius = ...` assignment

---

## Test Criteria

- Swinging any melee weapon and connecting with a VoxelSegment registers a hit
- The same segment is not hit twice in a single swing
- `max_hits` cap is respected (bat hits at most 2 segments, katana 3)
- Weapon swap or death during windup does not trigger the hitbox
- Audio and shake fire exactly once per swing that connects
- Misses produce no feedback
