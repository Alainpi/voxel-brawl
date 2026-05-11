# Health System Tuning Reference

---

## How the death pool works

Each segment has a weight. Damage to a segment converts lost voxels into weighted HP damage:

```
lost_fraction  = 1.0 - (current_voxels / total_voxels)
segment_damage = weight × lost_fraction
total_damage   = sum of segment_damage across all segments
HP             = max(0, MAX_HP - total_damage)
```

Weights intentionally exceed MAX_HP so a single critical segment (head=100, torso=100) alone can kill.
Limbs stack toward death: both arms=80, both legs=80, both hands=40.

A segment that **detaches** contributes its full weight immediately (lost_fraction = 1.0).

---

## Segment Weights — `WEIGHTS` dict (`health_system.gd`, lines 5–13)

Higher weight = that segment contributes more toward death when damaged or severed.

| Segment(s) | Default weight | Notes |
|---|---|---|
| `torso_bottom` | `60` | Lower torso — heaviest single limb |
| `torso_top` | `40` | Upper torso |
| `head_bottom` | `50` | Combined head = 100 → lethal alone |
| `head_top` | `50` | |
| `arm_r/l_upper` | `25` each | |
| `arm_r/l_fore` | `15` each | Both arms combined = 80 |
| `hand_r/l` | `20` each | Both hands combined = 40 |
| `leg_r/l_upper` | `25` each | |
| `leg_r/l_fore` | `15` each | Both legs combined = 80 |

**Total weight budget: 400.** Raise a segment's weight to make it more lethal when destroyed; lower it to make it less critical.

---

## Death Threshold — `MAX_HP` (`health_system.gd`, line 17)

```gdscript
const MAX_HP := 100.0
```

The HP value at which `died` fires. Since total weights sum to 400, a player dies when roughly 25% of their combined weighted voxel mass is destroyed. Raise MAX_HP to require more total damage before death; lower it to make everyone more fragile.

---

## Silhouette Color Thresholds — `_fraction_to_color()` (`hud.gd`, lines 61–67)

Controls the 4-step ramp on the body silhouette. `f` is each segment's health fraction (0.0–1.0), factoring in both voxel loss and structural integrity.

| Condition | Color | Meaning |
|---|---|---|
| `f <= 0.0` | Gray `(0.32, 0.32, 0.32)` | Severed / detached |
| `is_broken == true` | Bright red `(0.90, 0.08, 0.08)` | Broken — ragdolling but still attached |
| `f < 0.25` | Red `(0.85, 0.10, 0.10)` | Critical damage |
| `f < 0.50` | Orange `(0.90, 0.50, 0.10)` | Moderate damage |
| `f < 0.75` | Lighter green `(0.45, 0.85, 0.15)` | Minor damage |
| `f >= 0.75` | Green `(0.20, 0.78, 0.20)` | Healthy |

Adjust the threshold values (`0.25`, `0.50`, `0.75`) to shift where the color transitions happen. Adjust the Color values to change the hue/brightness of each state.

> **Note:** `f` is capped by `limb_system.get_integrity(seg_name)` when a LimbSystem is present, so a blunt-damaged arm with low integrity shows orange/red even if most voxels are intact.

---

## HP Bar Color — `_ready()` (`hud.gd`, lines 17–19)

```gdscript
var fill := StyleBoxFlat.new()
fill.bg_color = Color(0.2, 0.8, 0.2)
_hp_bar.add_theme_stylebox_override("fill", fill)
```

Change `fill.bg_color` to restyle the bar. To add a background/border, also override the `"background"` stylebox on `_hp_bar`.
