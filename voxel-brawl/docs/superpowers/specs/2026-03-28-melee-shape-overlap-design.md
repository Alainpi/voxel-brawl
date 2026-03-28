# Melee Hit Detection — Per-Frame Shape Overlap Query

**Date:** 2026-03-28
**Status:** Approved
**Replaces:** Sweep raycast system (Step 4, `_blade_tip`/`_blade_base` approach)

---

## Problem

The per-frame raycast sweep (BladeTip → prev position) consistently failed to register hits unless the marker started inside the target. Root cause: a single 1D ray from two calibrated points is too sparse — per-frame displacement is small, the ray rarely crosses the area boundary, and exact marker positions must be reverse-engineered through a complex multi-flip transform chain.

---

## Solution

Replace the sweep with a **per-frame shape overlap query**: each physics tick during the active hit window, call `PhysicsDirectSpaceState3D.intersect_shape()` using the weapon's existing collision shape at its current global transform. The question becomes: *"is the weapon shape overlapping any segment area right now?"* — no marker calibration, no prev-position tracking, full mesh coverage.

---

## Architecture

### Changed: `weapon_melee.gd`

**Remove entirely:**
- `_blade_tip`, `_blade_base` (Marker3D vars)
- `_prev_tip_pos`, `_prev_base_pos` (Vector3 vars)
- `_create_sweep_markers()` virtual method and its `_ready()` call
- `_sweep_check()` method

**Simplify:**
- `_enable_hitbox()` → sets `_hitbox_active = true` only (no shape enable loop, no INF resets)
- `_disable_hitbox()` → sets `_hitbox_active = false` only

**Add:**
- `_shape_overlap_check()` — iterates every `CollisionShape3D` child of `_hit_area`, fires `intersect_shape()` for each, processes hits

**Update `_physics_process`:**
```
if _hitbox_active:
    _shape_overlap_check()
```

### `_shape_overlap_check()` logic

```
for each CollisionShape3D col in _hit_area.get_children():
    skip if disabled
    build PhysicsShapeQueryParameters3D:
        shape = col.shape
        transform = col.global_transform
        collision_mask = 2
        collide_with_areas = true
        collide_with_bodies = false
    hits = space.intersect_shape(params, max_hits - _hit_segments.size())
    for each hit:
        skip if not Area3D or no "voxel_segment" meta
        skip if own segment or already hit this swing
        append to _hit_segments
        local_hit = seg.to_local(col.global_transform.origin)
        _apply_hit(seg, local_hit)
        play audio + camera feedback on first hit
        return early if max_hits reached
```

**Hit position approximation:** `col.global_transform.origin` (center of the collision shape in world space) converted to segment-local space. This is the epicenter for voxel removal — the `voxel_radius` parameter handles spread, so sub-centimeter accuracy is not required.

### Changed: weapon subclasses

Remove `_create_sweep_markers()` overrides from:
- `weapon_katana.gd`
- `weapon_bat.gd`
- `weapon_fists.gd`

All other methods (`_configure()`, `_apply_hit()`, `_create_hitarea()`) are unchanged.

**WeaponFists benefit:** The composite hitarea (two `CollisionShape3D` children — right fist + left fist) is queried automatically by the loop. No special handling needed.

---

## Data Flow

```
attack input
  → _attack(): start cooldown, play anim, await hit_enable_delay
  → _enable_hitbox(): _hitbox_active = true
  → _physics_process() [each tick]:
      _shape_overlap_check()
        → intersect_shape() per CollisionShape3D
        → hit found → _apply_hit(seg, local_hit)
        → audio + feedback on first hit
  → [after hit_window_duration]: _disable_hitbox(): _hitbox_active = false
```

---

## What Stays the Same

- `hit_enable_delay`, `hit_window_duration`, `max_hits` tuning vars — unchanged
- `_hit_area` Area3D node and its CollisionShape3D children — unchanged (still built by `_create_hitarea()`)
- `_own_segment_set` self-hit guard — unchanged
- `_hit_segments` per-swing dedup — unchanged
- All `_apply_hit()` overrides in subclasses — unchanged
- `_attack()` coroutine — unchanged

---

## Limitations & Accepted Tradeoffs

- **Pass-through:** A weapon moving fast enough to completely skip over a thin segment in one physics frame (~16ms at 60Hz) would miss. At normal swing speeds and segment depths (≥0.28 units), this is not a practical concern.
- **Hit position accuracy:** The collision shape center is used as the voxel epicenter, not the exact surface contact point. Acceptable given `voxel_radius` creates a sphere of destruction anyway.
- **Bat marker Z direction:** Previous incorrect bat markers (-1.2, -0.4 — outside mesh) were temporarily applied. This spec supersedes those values; `_create_sweep_markers()` is removed entirely, making bat marker direction moot.

---

## Files Changed

| File | Change |
|---|---|
| `scripts/weapon_melee.gd` | Remove sweep vars/methods, add `_shape_overlap_check()`, simplify enable/disable |
| `scripts/weapon_katana.gd` | Remove `_create_sweep_markers()` |
| `scripts/weapon_bat.gd` | Remove `_create_sweep_markers()` |
| `scripts/weapon_fists.gd` | Remove `_create_sweep_markers()` |
