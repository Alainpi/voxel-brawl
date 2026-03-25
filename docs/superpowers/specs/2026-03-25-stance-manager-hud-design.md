# Stance Manager + HUD Indicator — Design Spec

**Date:** 2026-03-25
**Status:** Approved
**Scope:** Step 1 of melee combat overhaul (implementation plan: `melee-combat-implementation-plan.md`)
**Goal:** Stance selection system with HUD feedback. No combat changes — scroll cycles stances, HUD reflects current stance. Foundation for Step 2 (animation wiring) and Step 3 (hit detection).

---

## 1. StanceManager

**File:** `scripts/stance_manager.gd`
**class_name:** `StanceManager`
**Node type:** Node (child of Player in `player.tscn`)
**Reference in player.gd:** `@onready var stance_manager: StanceManager = $StanceManager`

### Enum

```gdscript
enum Stance { LOW, MID, HIGH, THRUST }
```

### State

| Field | Type | Description |
|-------|------|-------------|
| `_stances` | `Array[Stance]` | Available stances for the current weapon. Set by `setup()`. Initialized to `[]`. |
| `_index` | `int` | Current stance index. Set by `setup()` using `_stances.find(Stance.MID)`. |

### Signal

```
stance_changed(stance: Stance)
```

Emitted on every `cycle()` call. No label parameter — `HudStanceIndicator` derives display strings from the enum directly. `label` is the human-readable string ("LOW", "MID", "HIGH", "THRUST").

### Methods

| Method | Caller | Description |
|--------|--------|-------------|
| `setup(stances: Array[Stance])` | Player on weapon equip | Sets `_stances`, resets `_index` to `_stances.find(Stance.MID)`. Arrays must always contain `Stance.MID`. Asserts this with `assert(stances.has(Stance.MID), "StanceManager.setup: array must contain Stance.MID")`. Does not emit. |
| `cycle(direction: int)` | Player on scroll input | Guards with `if _stances.is_empty(): return`. Advances index by `direction` (+1 or -1), wraps around, emits `stance_changed`. |
| `current_stance() → Stance` | Weapons (Step 2+) | Returns the active Stance enum value. Returns `Stance.MID` if `_stances` is empty. Note: in normal operation `_stances` is never empty when this is called — `setup()` always runs before `current_stance()` via `_update_stance_for_weapon`. The `HudStanceIndicator.update()` hides itself when `available` is empty, so any edge case is contained. |
| `current_stances() → Array[Stance]` | Player (for HUD wiring) | Returns a copy of `_stances` (`_stances.duplicate()`). Avoids exposing the internal array by reference. |

`current_label()` is not needed — the `stance_changed` signal already carries the label string. Do not add it.

---

## 2. WeaponBase Changes

**File:** `scripts/weapon_base.gd`

Add weapon type enum and variable:

```gdscript
enum WeaponType { BLUNT, SHARP, RANGED }
var weapon_type: WeaponType = WeaponType.BLUNT
```

The default is `BLUNT`. **Every weapon subclass must explicitly set `weapon_type` in `_configure()`** — do not rely on the default. Forgetting to set `RANGED` on a ranged weapon would silently trigger stance setup on equip.

Each concrete weapon sets `weapon_type` in `_configure()`:

| Weapon | `weapon_type` |
|--------|--------------|
| WeaponFists | BLUNT |
| WeaponBat | BLUNT |
| WeaponKatana | SHARP |
| WeaponRevolver | RANGED |
| WeaponShotgun | RANGED |

**WeaponRevolver and WeaponShotgun** must each add `weapon_type = WeaponType.RANGED` to their `_configure()` method. This is a required change in this step.

---

## 3. Stance Lists Per Weapon

Set by Player when equipping — not stored on the weapon itself. Arrays are always passed in ascending order `[LOW, MID, HIGH, ...]` so that `find(Stance.MID)` resolves to index 1 reliably.

| Weapon | Stances | Default |
|--------|---------|---------|
| Fists | LOW, MID, HIGH | MID (index 1) |
| Bat | LOW, MID, HIGH | MID (index 1) |
| Katana | LOW, MID, HIGH, THRUST | MID (index 1) |
| Revolver | — (ranged, no setup call) | — |
| Shotgun | — (ranged, no setup call) | — |

---

## 4. Player Changes

**File:** `scripts/player.gd`

### New onready

```gdscript
@onready var stance_manager: StanceManager = $StanceManager
```

### Scroll input (in `_input()`)

Remove:
```gdscript
elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
    _equip_weapon(revolver)
elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
    _equip_weapon(fists)
```

Replace with:
```gdscript
elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
    if _current_weapon is WeaponMelee:
        stance_manager.cycle(1)
elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
    if _current_weapon is WeaponMelee:
        stance_manager.cycle(-1)
```

Scroll is silently ignored for ranged weapons. The `is WeaponMelee` check covers all ranged weapons without additional conditions.

### Weapon equip (in `_equip_weapon()`)

Add `_update_stance_for_weapon(weapon)` as the **final line** of `_equip_weapon()`, after the existing `hud.set_weapon_name()` call:

```gdscript
# existing last lines of _equip_weapon():
    if hud:
        hud.set_weapon_name(names.get(weapon, ""))
    _update_stance_for_weapon(weapon)  # ADD THIS
```

`_equip_weapon` takes `weapon: Node`. `_update_stance_for_weapon` casts to `WeaponBase` internally to access `weapon_type` — do not change `_equip_weapon`'s parameter type.

```gdscript
func _update_stance_for_weapon(weapon: Node) -> void:
    if not weapon is WeaponBase:
        return
    var wb := weapon as WeaponBase
    match wb.weapon_type:
        WeaponBase.WeaponType.BLUNT:
            stance_manager.setup([StanceManager.Stance.LOW, StanceManager.Stance.MID, StanceManager.Stance.HIGH])
        WeaponBase.WeaponType.SHARP:
            stance_manager.setup([StanceManager.Stance.LOW, StanceManager.Stance.MID, StanceManager.Stance.HIGH, StanceManager.Stance.THRUST])
        WeaponBase.WeaponType.RANGED:
            pass  # no setup — scroll is no-op via WeaponMelee check
    # Always update HUD immediately on equip — setup() does not emit stance_changed
    var hud := get_node_or_null("/root/test_scene/hud")
    if hud:
        if wb.weapon_type == WeaponBase.WeaponType.RANGED:
            hud.update_stance(StanceManager.Stance.MID, [])  # hides the indicator
        else:
            hud.update_stance(stance_manager.current_stance(), stance_manager.current_stances())
```

### Signal connection (in `_ready()`)

```gdscript
stance_manager.stance_changed.connect(_on_stance_changed)
```

```gdscript
func _on_stance_changed(stance: StanceManager.Stance) -> void:
    var hud := get_node_or_null("/root/test_scene/hud")
    if hud:
        hud.update_stance(stance, stance_manager.current_stances())
```

### InputMap note

Before removing the scroll weapon-switch lines, verify that `switch_weapon_1` through `switch_weapon_5` are registered in `project.godot` InputMap. These are the only remaining weapon-switch bindings after scroll is repurposed.

---

## 5. HUD Stance Indicator

### Files

- `scenes/hud_stance_indicator.tscn`
- `scripts/hud_stance_indicator.gd` — script lives in `scripts/`, consistent with all other scripts in the project

### Script declaration

```gdscript
class_name HudStanceIndicator
extends VBoxContainer
```

`class_name HudStanceIndicator` is required so `hud.gd` can use the typed `@onready var stance_indicator: HudStanceIndicator`.

### Node structure

```
HudStanceIndicator (VBoxContainer, script: hud_stance_indicator.gd)
├── Row_THRUST (HBoxContainer)
│   ├── Bar (ColorRect)
│   └── Label ("THRUST")
├── Row_HIGH (HBoxContainer)
│   ├── Bar (ColorRect)
│   └── Label ("HIGH")
├── Row_MID (HBoxContainer)
│   ├── Bar (ColorRect)
│   └── Label ("MID")
└── Row_LOW (HBoxContainer)
    ├── Bar (ColorRect)
    └── Label ("LOW")
```

Rows are ordered HIGH → MID → LOW top-to-bottom (matches physical height — high stance is up, low is down). THRUST sits above HIGH and is hidden unless a SHARP weapon is equipped.

### Script interface

```gdscript
func update(stance: StanceManager.Stance, available: Array[StanceManager.Stance]) -> void
```

- Shows/hides rows based on `available`
- Active row: full opacity, bright highlight color
- Inactive rows: dimmed/translucent
- Entire indicator hidden (`visible = false`) when `available` is empty (ranged weapon equipped)
- Instant update, no animation (polish pass later)
- Display labels per row are derived from the enum: LOW → "LOW", MID → "MID", HIGH → "HIGH", THRUST → "THRUST"

### Integration

- `hud_stance_indicator.tscn` instanced as a child of the HUD node directly in `test_scene.tscn` (not in a separate hud.tscn — there is no hud.tscn in this project)
- `hud.gd` adds:
```gdscript
@onready var stance_indicator: HudStanceIndicator = $HudStanceIndicator
```
- `hud.gd` adds pass-through:
```gdscript
func update_stance(stance: StanceManager.Stance, available: Array[StanceManager.Stance]) -> void:
    stance_indicator.update(stance, available)
```

---

## 6. What This Step Does NOT Change

- No changes to `weapon_melee.gd` hit detection
- No method call tracks in animations yet (Step 2)
- No Area3D hitboxes (Step 3)
- `attack_anim` strings on weapons unchanged — Step 2 swaps these per stance
- Ranged weapons unchanged except adding `weapon_type = WeaponType.RANGED` to `_configure()`

---

## 7. Success Criteria

- Scrolling up/down cycles stance for Fists, Bat, Katana
- Scroll does nothing when Revolver or Shotgun is equipped
- HUD indicator shows correct stance highlighted
- THRUST row visible only when Katana is equipped
- Indicator hidden when ranged weapon is equipped
- Weapon switch resets stance to MID
- Existing combat behavior completely unchanged
