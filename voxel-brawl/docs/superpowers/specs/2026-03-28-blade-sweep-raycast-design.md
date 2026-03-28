# Step 4 Design: Blade-Tip Sweep Raycast

**Date:** 2026-03-28
**Status:** Approved
**Implements:** Melee Combat Overhaul — Step 4
**Master plan:** `melee-combat-implementation-plan.md` §9 Step 4

---

## Problem

Step 3's `area_entered` hit detection is event-driven: it fires when physics overlaps are detected, which misses fast swings entirely. The `local_hit` passed to `_apply_hit` uses `_hit_area.global_position` (the weapon root) as a crude approximation — voxel craters appear at the handle, not where the blade contacts the target.

---

## Solution Overview

Replace `area_entered` as the hit mechanism with a **per-frame blade-tip sweep raycast** in `_physics_process`. During the active window, two raycasts are cast each frame — one from `BladeTip`'s previous position to its current, one for `BladeBase`. The exact raycast hit position becomes `local_hit`, giving precise voxel carving at the blade contact point.

The Area3D hitbox from Step 3 is retained as the **enable/disable gate** only: its CollisionShape3D children are toggled disabled/enabled to track the active window via `_hitbox_active`. The Area3D no longer detects overlaps (`monitoring = false`).

---

## Architecture

### Files changed

| File | Change |
|------|--------|
| `scripts/weapon_melee.gd` | Core changes — see below |
| `scripts/weapon_bat.gd` | Add `_create_sweep_markers()` override |
| `scripts/weapon_katana.gd` | Add `_create_sweep_markers()` override |
| `scripts/weapon_fists.gd` | Add `_create_sweep_markers()` override |

No changes to `player.gd`, `weapon_base.gd`, or any `.tscn` file.

---

## `weapon_melee.gd` Changes

### New vars

```gdscript
var _blade_tip: Marker3D = null
var _blade_base: Marker3D = null
var _prev_tip_pos := Vector3.INF
var _prev_base_pos := Vector3.INF
var _hitbox_active := false
```

`Vector3.INF` is the sentinel for "no previous position yet." The sweep skips the first frame of each activation so it never casts from a stale pre-attack position.

### `_ready()` update

```gdscript
func _ready() -> void:
    super()
    _create_hitarea()
    _create_sweep_markers()
```

`_create_sweep_markers()` runs after `_create_hitarea()` so `_hit_area` exists if a subclass needs it.

### `_create_sweep_markers()` — new virtual

Default implementation creates both Marker3D nodes at the weapon root origin. Subclasses override to set meaningful local positions.

```gdscript
func _create_sweep_markers() -> void:
    _blade_tip = Marker3D.new()
    _blade_tip.name = "BladeTip"
    add_child(_blade_tip)
    _blade_base = Marker3D.new()
    _blade_base.name = "BladeBase"
    add_child(_blade_base)
```

### `_enable_hitbox()` / `_disable_hitbox()` updates

```gdscript
func _enable_hitbox() -> void:
    for child in _hit_area.get_children():
        if child is CollisionShape3D:
            child.disabled = false
    _hitbox_active = true
    _prev_tip_pos = Vector3.INF
    _prev_base_pos = Vector3.INF

func _disable_hitbox() -> void:
    for child in _hit_area.get_children():
        if child is CollisionShape3D:
            child.disabled = true
    _hitbox_active = false
    _prev_tip_pos = Vector3.INF
    _prev_base_pos = Vector3.INF
```

Resetting prev-positions on both enable and disable ensures a clean slate every swing.

### `_physics_process()` update

```gdscript
func _physics_process(delta: float) -> void:
    _cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
    if Input.is_action_just_pressed("attack") and _cooldown_timer <= 0.0:
        _attack()

    if _hitbox_active:
        var tip_now := _blade_tip.global_position
        var base_now := _blade_base.global_position
        if _prev_tip_pos != Vector3.INF:
            _sweep_check(_prev_tip_pos, tip_now)
            _sweep_check(_prev_base_pos, base_now)
        _prev_tip_pos = tip_now
        _prev_base_pos = base_now
```

### `_sweep_check()` — new private method

```gdscript
func _sweep_check(from: Vector3, to: Vector3) -> void:
    if _hit_segments.size() >= max_hits:
        return
    var space := get_world_3d().direct_space_state
    var query := PhysicsRayQueryParameters3D.create(from, to, 2)
    query.collide_with_areas = true
    query.collide_with_bodies = false
    var result := space.intersect_ray(query)
    if not result or not result.collider is Area3D:
        return
    if not result.collider.has_meta("voxel_segment"):
        return
    var seg: VoxelSegment = result.collider.get_meta("voxel_segment")
    if _own_segment_set.is_empty() and not _player.segments.is_empty():
        for s: VoxelSegment in _player.segments.values():
            _own_segment_set[s] = true
    if seg in _own_segment_set:
        return
    if seg in _hit_segments:
        return
    _hit_segments.append(seg)
    var local_hit := seg.to_local(result.position)
    _apply_hit(seg, local_hit)
    if _hit_segments.size() == 1:
        if audio.stream:
            audio.play()
        _player.trigger_hit_shake()
        _player.trigger_crosshair_recoil()
```

`max_hits` is checked before the raycast — no ray is cast once the cap is reached.

The lazy `_own_segment_set` population moves here from the removed `_on_hit_area_entered`.

### `_create_hitarea()` update

Remove the `area_entered` signal connection and set `monitoring = false`:

```gdscript
func _create_hitarea() -> void:
    _hit_area = Area3D.new()
    _hit_area.collision_layer = 0
    _hit_area.collision_mask = 2
    _hit_area.monitoring = false      # sweep handles detection; Area3D is gate only
    _hit_area.monitorable = false
    if hit_shape:
        var col := CollisionShape3D.new()
        col.shape = hit_shape
        col.position = hit_shape_offset
        col.rotation_degrees = hit_shape_rotation
        col.scale = hit_shape_scale
        col.disabled = true
        _hit_area.add_child(col)
    add_child(_hit_area)
    # area_entered no longer connected — sweep is the hit mechanism
```

### Removed

- `_on_hit_area_entered()` — entire method deleted
- `area_entered.connect(...)` call in `_create_hitarea()`

---

## Per-Weapon Marker Positions

Subclasses override `_create_sweep_markers()`. Positions are starting values; tune via Remote panel during play.

### `weapon_bat.gd`

```gdscript
func _create_sweep_markers() -> void:
    super()
    _blade_tip.position = Vector3(-0.35, 0.35, -1.2)   # far end of barrel
    _blade_base.position = Vector3(-0.35, 0.35, -0.4)  # handle-barrel junction
```

### `weapon_katana.gd`

```gdscript
func _create_sweep_markers() -> void:
    super()
    _blade_tip.position = Vector3(-0.3, 0.35, -1.6)    # blade tip
    _blade_base.position = Vector3(-0.3, 0.35, -0.5)   # blade-guard junction
```

### `weapon_fists.gd`

```gdscript
func _create_sweep_markers() -> void:
    super()
    _blade_tip.position = Vector3(0.0, 0.0, -0.4)      # right knuckles
    _blade_base.position = Vector3(0.0, 0.0, -0.1)     # right wrist
```

**Fists note:** Only the right fist is swept. The left-fist `CollisionShape3D` in `WeaponFists._create_hitarea()` is now inert (monitoring off, no signal). Clean up in Step 6.

---

## What the Area3D Is Now

The `_hit_area` node's only remaining job is holding `CollisionShape3D` children whose `disabled` state is toggled by `_enable_hitbox()` / `_disable_hitbox()`. These shapes serve as visual debug geometry in the Remote panel — they show the active window extent when the hitbox is live. `monitoring = false` and `monitorable = false` mean it costs nothing in the physics simulation.

---

## Test Criteria

- Swinging any melee weapon and connecting registers a hit at the visual blade contact point
- Voxel craters appear where the blade tip visually passes through the segment — not at the weapon root
- The same segment is not hit twice in a single swing
- `max_hits` cap respected per weapon (fists: 1, bat: 2, katana: 3)
- No hit registers when the attack misses (sweep raycasts find nothing)
- Weapon swap during windup does not trigger the sweep
- Player death during windup does not crash (existing `is_instance_valid` guards cover this)
- Audio and shake fire exactly once per swing that connects
- Non-segment areas (environment) on layer 2 do not register as hits (covered by `has_meta("voxel_segment")` check)
