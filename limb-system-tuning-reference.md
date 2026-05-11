# Limb System Tuning Reference

All values live in `scripts/limb_system.gd`.

---

## Structural Integrity — Named Constants (lines 8–12)

These control when limbs break or sever.

| Constant | Default | Effect |
|---|---|---|
| `BREAK_THRESHOLD` | `0.5` | Integrity level that triggers the BROKEN state (floppy ragdoll while still attached). Only fires on BLUNT hits. Raise to make arms go floppy earlier; lower to require more punishment. |
| `DETACH_THRESHOLD` | `0.0` | Integrity level that triggers DETACH (limb severs). Fires on any weapon type. Raise above 0 to allow severing before integrity fully drains. |
| `FALLOFF` | `3.0` | How quickly the proximity weight drops as the hit moves away from the attachment joint. Higher = only hits very close to the joint drain integrity quickly; lower = hits anywhere on the limb drain it equally fast. |
| `BLUNT_MULTIPLIER` | `2.0` | How much faster blunt weapons drain integrity vs sharp. `2.0` = bat drains twice as fast as katana for the same damage value. |
| `DEATH_VOXEL_THRESHOLD` | `0.2` | Fraction of combined torso + head voxels remaining that triggers death ragdoll. `0.2` = dies when 80% of torso/head voxels are destroyed. |

### How integrity drains per hit

```
proximity_weight = clamp(1.0 / (1.0 + distance_to_joint × FALLOFF), 0.1, 1.0)
drain = (damage / segment_max_hp) × proximity_weight × blunt_multiplier
integrity -= drain
```

---

## Per-Segment Max HP — `HIERARCHY` dict (lines 16–31)

Each non-torso segment has a `max_hp` entry. Higher max_hp = more hits required to sever.
Torso segments (`torso_bottom`, `torso_top`) use `max_hp: 0.0` — they never detach via integrity.

| Segment(s) | Default max_hp |
|---|---|
| `arm_r/l_upper`, `leg_r/l_upper` | `120.0` |
| `arm_r/l_fore`, `leg_r/l_fore` | `80.0` |
| `hand_r/l` | `50.0` |
| `head_bottom`, `head_top` | `60.0` |
| `torso_bottom`, `torso_top` | `0.0` (indestructible) |

Edit inline in the `HIERARCHY` dictionary — each entry has a `"max_hp"` key.

---

## RigidBody3D Mass — `_get_mass()` (line 400)

Controls how heavy each segment feels when ragdolling. Heavier segments resist impulses more.

| Segment group | Default mass |
|---|---|
| `torso_bottom`, `torso_top` | `3.0` |
| `head_bottom`, `head_top` | `1.0` |
| All limb segments | `0.8` |

---

## Detach Impulse — `_spawn_detached_ragdoll()` (lines 264–268)

Applied to the root RB of a freshly severed chain. The rest of the chain follows via PinJoint3D.

```gdscript
apply_central_impulse(Vector3(randf_range(-3, 3), randf_range(2, 5), randf_range(-3, 3)))
apply_torque_impulse(Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)))
```

| Parameter | Effect |
|---|---|
| XZ range `(-3, 3)` in `central_impulse` | Horizontal scatter — wider range = more sideways spray |
| Y range `(2, 5)` in `central_impulse` | Upward pop on sever — raise max to make limbs fly higher |
| All ranges in `torque_impulse` | Spin rate on detach — higher = limbs tumble faster |

**Broken → detached transition** (line 195) uses identical impulse values and is edited separately, two lines above the same section.

---

## PinJoint3D Stiffness — `_make_pin_joint()` (line 391)

Currently uses Godot defaults (no explicit params set). Add these calls inside `_make_pin_joint` to tune how stiff or rubbery the joints feel:

```gdscript
joint.set_param(PinJoint3D.PARAM_BIAS, 0.3)          # 0–1: how aggressively the joint corrects position error each frame
joint.set_param(PinJoint3D.PARAM_DAMPING, 1.0)       # 0+: resistance to oscillation / wobble
joint.set_param(PinJoint3D.PARAM_IMPULSE_CLAMP, 0.0) # 0 = no limit; raise to cap max constraint force
```

Higher `PARAM_BIAS` = stiffer joints (less drooping). Lower = more rubbery/stretchy.
Higher `PARAM_DAMPING` = less oscillation after impact.

---

## Additional RigidBody3D Physics (not currently set — add in spawning functions)

Applied per-RB in `_spawn_broken_ragdoll`, `_spawn_detached_ragdoll`, or `_spawn_death_ragdoll` after `var rb := RigidBody3D.new()`:

```gdscript
rb.linear_damp  = 0.5   # air resistance on translation — slows flying limbs
rb.angular_damp = 1.0   # air resistance on rotation — slows tumbling
rb.gravity_scale = 1.0  # 0 = floats, 2 = falls twice as fast
```

These apply to every RB in the spawning function where they're added. Add them to all three functions for consistent behaviour, or only the one you want to affect (broken, detached, or death).
