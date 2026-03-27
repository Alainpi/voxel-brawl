# Animation Integration — Design Spec

**Date:** 2026-03-26
**Status:** Approved
**Scope:** Step 2 of melee combat overhaul (implementation plan: `melee-combat-implementation-plan.md`)
**Goal:** Wire the stance selector to stance-specific attack animations. No hitbox or hit detection changes — purely animation selection and the `_is_attacking` flag that guards locomotion.

---

## 1. Scope

Step 2 is purely code — no editor work, no new scenes, no new scripts.

**Out of scope for this step:**
- Method call tracks (`_enable_hitbox` / `_disable_hitbox`) in AnimationPlayer — deferred to Step 3
- Area3D hitbox setup — Step 3
- Changes to hit detection logic in `weapon_melee.gd` — Step 3
- Changes to any weapon script — none required

---

## 2. Animation Naming Convention

All stance-specific attack animations follow this pattern:

```
{weapon_prefix}_{stance_lowercase}
```

| Weapon | Prefix | Animations |
|--------|--------|-----------|
| Fists | `punch` | `punch_low`, `punch_mid`, `punch_high` |
| Bat | `bat` | `bat_low`, `bat_mid`, `bat_high` |
| Katana | `katana` | `katana_low`, `katana_mid`, `katana_high`, `katana_thrust` |
| Revolver / Shotgun | — | `holding-right-shoot` (special case, unchanged) |

These names must match exactly what is present in the imported `player_rig.glb` AnimationPlayer. Verify all 10 names in Godot's AnimationPlayer panel before running.

The weapon's existing `attack_anim` field already holds the correct prefix (`"punch"`, `"bat"`, `"katana"`). No weapon files change.

---

## 3. Changes to `player.gd`

### 3a. New field

```gdscript
var _is_attacking: bool = false
```

### 3b. `play_attack_anim()` — updated

Old behavior: mapped a handful of hardcoded short names to full animation names with dashes.

New behavior: builds the animation name from weapon prefix + current stance for melee; keeps the `"shoot"` special case unchanged.

```gdscript
func play_attack_anim(anim_name: String) -> void:
    var mapped: String
    if anim_name == "shoot":
        mapped = "holding-right-shoot"
    else:
        var stance_key := StanceManager.Stance.find_key(stance_manager.current_stance()).to_lower()
        mapped = anim_name + "_" + stance_key
    _is_attacking = true
    anim_player.stop()
    anim_player.play(mapped)
```

`StanceManager.Stance.find_key(stance)` returns the enum key name as a string (`"LOW"`, `"MID"`, etc.). `.to_lower()` converts it to `"low"`, `"mid"`, etc.

### 3c. `_update_animation()` — updated guard

Old:
```gdscript
if anim_player.is_playing() and cur in ["punch-right", "holding-right-shoot", "bat-swing", "katana-slash"]:
    return
```

New:
```gdscript
if _is_attacking:
    return
```

The `cur` variable is no longer needed for this check and can be removed if it has no other use.

### 3d. `_on_anim_finished()` — new handler

```gdscript
func _on_anim_finished(_anim_name: String) -> void:
    _is_attacking = false
```

Connected in `_ready()`:
```gdscript
anim_player.animation_finished.connect(_on_anim_finished)
```

`animation_finished` only fires for non-looping animations. Since idle, walk, and hold animations are set to loop in the Godot import settings, only attack animations trigger this signal. No additional filtering needed.

---

## 4. What Does NOT Change

- `weapon_melee.gd` — `_attack()` still calls `_player.play_attack_anim(attack_anim)` unchanged
- `weapon_fists.gd`, `weapon_bat.gd`, `weapon_katana.gd` — no edits
- `weapon_ranged.gd`, `weapon_revolver.gd`, `weapon_shotgun.gd` — no edits
- `stance_manager.gd` — no edits
- `hud_stance_indicator.gd`, `hud.gd` — no edits
- Old animation names (`punch-right`, `bat-swing`, `katana-slash`) remain in the AnimationPlayer but are no longer called during attacks. They can be left in place.

---

## 5. Success Criteria

- Equip fists, scroll to LOW, attack → `punch_low` plays
- Equip fists, scroll to HIGH, attack → `punch_high` plays
- Equip bat at default MID, attack → `bat_mid` plays
- Equip katana, scroll to THRUST, attack → `katana_thrust` plays
- Equip revolver, shoot → `holding-right-shoot` plays, unchanged
- Switching weapons resets stance to MID → attacking immediately after equip plays the `_mid` variant
- Locomotion resumes after attack animation finishes (`_is_attacking` clears correctly)
- No errors in Output panel for any of the above
