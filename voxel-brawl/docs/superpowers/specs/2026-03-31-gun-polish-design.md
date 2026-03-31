# Gun Polish — Design Spec
*2026-03-31*

## Scope

Four tightly related improvements to the ranged weapon system:

1. Muzzle nodes + barrel-origin raycasting
2. Tracer effect (stretched BoxMesh streak)
3. Shotgun scatter fix (near/far configurable cone, voxel ray gets spread)
4. Screen shake + crosshair kick (per-weapon, tweakable)

---

## 1. Muzzle Nodes + Barrel-Origin Raycasting

### Problem
`WeaponRanged._fire_ray()` hardcodes the wall-check ray origin as `_player.global_position + Vector3(0, 1.2, 0)` (chest height). MuzzleFlash is also manually offset by `basis.z * 0.5`. Neither tracks the actual barrel position.

### Solution
Add a `Muzzle` Node3D child to each ranged weapon in `player.tscn`, positioned at the tip of the barrel in local weapon space:

| Weapon   | Muzzle local position (approx) |
|----------|-------------------------------|
| Revolver | `(0, 0, -0.6)`                |
| Shotgun  | `(0, 0, -0.8)`                |

`WeaponRanged` adds:
```gdscript
@onready var muzzle: Node3D = $Muzzle
```

`_fire_ray()` replaces `chest` with `muzzle.global_position` for the wall-check ray origin.

`_play_shot_effects()` positions MuzzleFlash at `muzzle.global_position` instead of the manual offset.

Shotgun gains its own `MuzzleFlash` GPUParticles3D node (currently missing).

---

## 2. Tracer Effect

### BulletTracer — new script (`scripts/bullet_tracer.gd`)

A self-contained node (~40 lines) that renders a single streak and frees itself.

**Visual setup:**
- `MeshInstance3D` with a `BoxMesh`
- Thickness: `0.03` units (X and Y of BoxMesh size) — tunable const `TRACER_THICKNESS`
- `StandardMaterial3D`: `shading_mode = UNSHADED`, `flags_transparent = true`, `albedo_color` set from spawn call
- No shadows cast or received

**Lifetime:**
- Placed at midpoint between `from` and `to`
- X scale set to distance between `from` and `to`
- Rotated to look from `from` toward `to`
- `Tween` fades `albedo_color.a` from `1.0` → `0.0` over `TRACER_FADE_TIME = 0.12` seconds
- `queue_free()` on tween completion

**Static spawn method:**
```gdscript
static func spawn(from: Vector3, to: Vector3, color: Color, parent: Node) -> void
```
Adds instance to `parent` (caller passes `get_tree().root`).

**Per-weapon tracer colors:**
- Revolver: `Color(1.0, 0.96, 0.63, 1.0)` — bright yellow-white
- Shotgun: `Color(1.0, 0.60, 0.0, 1.0)` — orange

**Tracer spawn point:** `muzzle.global_position`. End point is the wall hit position, voxel hit position, or `muzzle.global_position + aim_dir * RAY_LENGTH` if nothing was hit.

**Shotgun:** one tracer per pellet, each using its own spread direction endpoint.

---

## 3. Shotgun Scatter Fix

### Problem
`WeaponShotgun._fire()` applies a random spread angle to the wall-check ray direction only. The voxel targeting ray in `_fire_ray()` always uses the raw camera ray — all pellets share the same voxel hit point.

### Solution

**New exported vars on `WeaponShotgun`:**
```gdscript
@export var spread_near: float = 0.25   # half-angle radians at point-blank
@export var spread_far: float = 0.08    # half-angle radians at max range
@export var spread_falloff_dist: float = 12.0  # distance where cone fully tightens
```

**Spread angle calculation per pellet:**
```
t = clamp(hit_dist / spread_falloff_dist, 0.0, 1.0)
spread_angle = lerp(spread_near, spread_far, t)
```
Since hit distance isn't known before firing, use a two-pass approach: compute the spread direction first, then pass it into `_fire_ray()` so the voxel ray uses the same direction.

**`_fire_ray()` signature change in `WeaponRanged`:**
```gdscript
func _fire_ray(aim_dir_h: Vector3, spread_dir: Vector3 = Vector3.ZERO) -> void
```
When `spread_dir` is non-zero, the voxel ray is reconstructed from `muzzle.global_position` along `spread_dir` (cast into 3D by preserving the camera ray's Y component scaled to the horizontal spread direction). When `spread_dir` is zero (revolver), behaviour is unchanged.

**Shotgun `_fire()` loop:**
```gdscript
for i in range(PELLET_COUNT):
    var angle := randf_range(-spread_angle_h, spread_angle_h)
    var spread_dir := aim_dir_h.rotated(Vector3.UP, angle)
    _fire_ray(spread_dir, spread_dir)
```
The spread angle used here is `spread_near` as a starting value; the lerp refines it after the first wall-check distance is known. For simplicity in v1, use `spread_near` uniformly — the distance-based lerp can be wired as a follow-up once it's confirmed feeling good.

---

## 4. Screen Shake + Crosshair Kick

### New exported vars on `WeaponRanged`
```gdscript
@export var recoil_shake_strength: float = 0.2
@export var recoil_kick_amount: float = 12.0
@export var recoil_recovery_time: float = 0.25
```

### Per-weapon defaults set in `_configure()`

| Weapon   | shake_strength | kick_amount | recovery_time |
|----------|---------------|-------------|---------------|
| Revolver | 0.35          | 18.0        | 0.25          |
| Shotgun  | 0.60          | 28.0        | 0.40          |

### Player method signature updates

Current signatures take no args:
```gdscript
func trigger_hit_shake() -> void
func trigger_crosshair_recoil() -> void
```

Updated to accept optional overrides:
```gdscript
func trigger_hit_shake(strength: float = 0.2) -> void
func trigger_crosshair_recoil(kick: float = 12.0, recovery: float = 0.25) -> void
```

Existing melee callers pass no args and get the defaults — no breakage.

### New `_apply_recoil()` in `WeaponRanged`
Called from `_fire()` (not `_fire_ray()` — recoil fires on trigger pull, not on hit):
```gdscript
func _apply_recoil() -> void:
    _player.trigger_hit_shake(recoil_shake_strength)
    _player.trigger_crosshair_recoil(recoil_kick_amount, recoil_recovery_time)
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/weapon_ranged.gd` | Add `muzzle` onready, replace `chest` origin, `_fire_ray()` spread_dir param, `_apply_recoil()`, updated `_play_shot_effects()` |
| `scripts/weapon_shotgun.gd` | Add spread exported vars, fix `_fire()` to pass spread_dir to `_fire_ray()` |
| `scripts/weapon_revolver.gd` | Add recoil vars to `_configure()` |
| `scripts/bullet_tracer.gd` | New file |
| `scripts/player.gd` | Update `trigger_hit_shake()` and `trigger_crosshair_recoil()` signatures |
| `scenes/player.tscn` | Add `Muzzle` Node3D to Revolver + Shotgun; add `MuzzleFlash` to Shotgun |

---

## Out of Scope

- Muzzle nodes for melee weapons (not applicable)
- Tracer pooling (tracers are short-lived and infrequent enough that `queue_free` is fine)
- Distance-based spread lerp in v1 (use `spread_near` uniformly, refine after playtesting)
- Audio polish (separate task)
