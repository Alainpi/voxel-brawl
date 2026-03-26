# Stance Manager + HUD Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a scroll-wheel stance selector for melee weapons with a HUD indicator — no combat changes, pure UI/input layer.

**Architecture:** StanceManager is a child Node of Player that holds stance state and emits `stance_changed`. Player routes scroll input to it and forwards updates to the HUD. HudStanceIndicator is a VBoxContainer scene that shows/hides rows per available stances and highlights the active one.

**Tech Stack:** Godot 4.3+, GDScript. No test framework — verification is done by launching the scene and checking behavior in-engine.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `scripts/weapon_base.gd` | Modify | Add `WeaponType` enum + `weapon_type` var |
| `scripts/weapon_fists.gd` | Modify | Set `weapon_type = BLUNT` |
| `scripts/weapon_bat.gd` | Modify | Set `weapon_type = BLUNT` |
| `scripts/weapon_katana.gd` | Modify | Set `weapon_type = SHARP` |
| `scripts/weapon_revolver.gd` | Modify | Set `weapon_type = RANGED` |
| `scripts/weapon_shotgun.gd` | Modify | Set `weapon_type = RANGED` |
| `scripts/stance_manager.gd` | Create | Stance enum, state, signal, cycle/setup logic |
| `scenes/player.tscn` | Modify (editor) | Add StanceManager node as child of Player |
| `scripts/player.gd` | Modify | Add onready, scroll input, stance update, signal handler |
| `scripts/hud_stance_indicator.gd` | Create | Row show/hide + highlight logic |
| `scenes/hud_stance_indicator.tscn` | Create (editor) | VBoxContainer with 4 rows |
| `scenes/test_scene.tscn` | Modify (editor) | Instance HudStanceIndicator under HUD node |
| `scripts/hud.gd` | Modify | Add onready + update_stance pass-through |

---

## Task 1: Add WeaponType to WeaponBase and all weapon scripts

**Files:**
- Modify: `voxel-brawl/scripts/weapon_base.gd`
- Modify: `voxel-brawl/scripts/weapon_fists.gd`
- Modify: `voxel-brawl/scripts/weapon_bat.gd`
- Modify: `voxel-brawl/scripts/weapon_katana.gd`
- Modify: `voxel-brawl/scripts/weapon_revolver.gd`
- Modify: `voxel-brawl/scripts/weapon_shotgun.gd`

- [ ] **Step 1: Add WeaponType enum to weapon_base.gd**

Add after the existing `var _player: Player` line:

```gdscript
enum WeaponType { BLUNT, SHARP, RANGED }
var weapon_type: WeaponType = WeaponType.BLUNT
```

Full file after edit:
```gdscript
# scripts/weapon_base.gd
class_name WeaponBase
extends Node3D

var _player: Player

enum WeaponType { BLUNT, SHARP, RANGED }
var weapon_type: WeaponType = WeaponType.BLUNT

func _ready() -> void:
	_configure()
	_player = get_node("../../../../")

func _configure() -> void:
	pass
```

- [ ] **Step 2: Set weapon_type in weapon_fists.gd**

Add `weapon_type = WeaponType.BLUNT` as first line of `_configure()`:

```gdscript
func _configure() -> void:
	weapon_type = WeaponType.BLUNT
	damage = 8.0
	voxel_radius = 2.0
	reach = 0.5
	hit_sphere_radius = 0.8
	cooldown = 0.35
	attack_anim = "punch"
```

- [ ] **Step 3: Set weapon_type in weapon_bat.gd**

Add `weapon_type = WeaponType.BLUNT` as first line of `_configure()`:

```gdscript
func _configure() -> void:
	weapon_type = WeaponType.BLUNT
	damage = 22.0
	voxel_radius = 2.8
	reach = 0.9
	hit_sphere_radius = 1.1
	cooldown = 0.65
	attack_anim = "bat"
```

- [ ] **Step 4: Set weapon_type in weapon_katana.gd**

Add `weapon_type = WeaponType.SHARP` as first line of `_configure()`:

```gdscript
func _configure() -> void:
	weapon_type = WeaponType.SHARP
	damage = 45.0
	voxel_radius = 0.7
	reach = 1.0
	hit_sphere_radius = 1.0
	cooldown = 0.3
	attack_anim = "katana"
```

- [ ] **Step 5: Set weapon_type in weapon_revolver.gd**

Add `weapon_type = WeaponType.RANGED` as first line of `_configure()`:

```gdscript
func _configure() -> void:
	weapon_type = WeaponType.RANGED
	damage = 35.0
	voxel_radius = 1.5
	fire_rate = 0.55
	max_ammo = 6
	reload_time = 1.5
```

- [ ] **Step 6: Set weapon_type in weapon_shotgun.gd**

Add `weapon_type = WeaponType.RANGED` as first line of `_configure()`:

```gdscript
func _configure() -> void:
	weapon_type = WeaponType.RANGED
	damage = 12.0
	voxel_radius = 1.2
	fire_rate = 0.9
	max_ammo = 2
	reload_time = 2.0
```

- [ ] **Step 7: Verify — open Godot, check Output panel for parse errors**

Open the project in Godot 4. The Output panel (bottom of editor) should be silent — no "Parse Error" or "Identifier not found" messages. If errors appear, fix before continuing.

- [ ] **Step 8: Commit**

```bash
git add voxel-brawl/scripts/weapon_base.gd voxel-brawl/scripts/weapon_fists.gd voxel-brawl/scripts/weapon_bat.gd voxel-brawl/scripts/weapon_katana.gd voxel-brawl/scripts/weapon_revolver.gd voxel-brawl/scripts/weapon_shotgun.gd
git commit -m "feat: add WeaponType enum to WeaponBase, set type in all weapon scripts"
```

---

## Task 2: Create StanceManager script

**Files:**
- Create: `voxel-brawl/scripts/stance_manager.gd`

- [ ] **Step 1: Create the script**

```gdscript
# scripts/stance_manager.gd
class_name StanceManager
extends Node

enum Stance { LOW, MID, HIGH, THRUST }

signal stance_changed(stance: Stance)

var _stances: Array[Stance] = []
var _index: int = 0

## Called by Player on weapon equip. Resets stance to MID.
## stances must always contain Stance.MID.
func setup(stances: Array[Stance]) -> void:
	assert(stances.has(Stance.MID), "StanceManager.setup: array must contain Stance.MID")
	_stances = stances
	_index = _stances.find(Stance.MID)

## Called by Player on scroll input. Wraps around the available stances.
func cycle(direction: int) -> void:
	if _stances.is_empty():
		return
	_index = (_index + direction) % _stances.size()
	if _index < 0:
		_index += _stances.size()
	stance_changed.emit(current_stance())

## Returns the active Stance. Falls back to MID if stances not yet set up.
func current_stance() -> Stance:
	if _stances.is_empty():
		return Stance.MID
	return _stances[_index]

## Returns a copy of the available stances (safe to pass to HUD).
func current_stances() -> Array[Stance]:
	return _stances.duplicate()
```

- [ ] **Step 2: Verify — check Output panel for parse errors**

Save the file. Godot will parse it automatically. Output panel should be clean.

- [ ] **Step 3: Commit**

```bash
git add voxel-brawl/scripts/stance_manager.gd voxel-brawl/scripts/stance_manager.gd.uid
git commit -m "feat: add StanceManager node script"
```

---

## Task 3: Add StanceManager node to player.tscn (Godot editor)

**Files:**
- Modify: `voxel-brawl/scenes/player.tscn` (editor step)

- [ ] **Step 1: Open player.tscn in the Godot editor**

In the FileSystem panel, navigate to `scenes/player.tscn` and double-click to open it.

- [ ] **Step 2: Add the StanceManager node**

In the Scene panel (node tree), click the root `Player` node to select it. Then click the **Add Child Node** button (the + icon, or press Ctrl+A). In the search box type `Node` and select the plain **Node** type (not Node2D or Node3D). Click **Create**.

- [ ] **Step 3: Rename and attach script**

- Rename the new node to exactly `StanceManager` (F2 to rename)
- With `StanceManager` selected, go to the Inspector panel
- Click the Script field dropdown → **Load** → navigate to `scripts/stance_manager.gd`
- The Inspector should now show the StanceManager script properties

- [ ] **Step 4: Save the scene**

Ctrl+S to save `player.tscn`.

- [ ] **Step 5: Verify — launch the scene, check Output**

Press F5 (Run Project). The game should launch without errors. The Output panel should not show any "Node not found" errors. Press Escape to stop.

- [ ] **Step 6: Commit**

```bash
git add voxel-brawl/scenes/player.tscn
git commit -m "feat: add StanceManager node to player.tscn"
```

---

## Task 4: Wire StanceManager into player.gd

**Files:**
- Modify: `voxel-brawl/scripts/player.gd`

- [ ] **Step 1: Add the @onready reference**

After the existing `@onready var fists: WeaponFists = ...` block (around line 28), add:

```gdscript
@onready var stance_manager: StanceManager = $StanceManager
```

- [ ] **Step 2: Replace scroll weapon-switching with stance cycling**

In `_input()`, find and remove these two lines (currently lines 111–113):

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

- [ ] **Step 3: Add _update_stance_for_weapon**

Add this new method anywhere after `_equip_weapon()`:

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
			hud.update_stance(StanceManager.Stance.MID, [])
		else:
			hud.update_stance(stance_manager.current_stance(), stance_manager.current_stances())
```

- [ ] **Step 4: Add _on_stance_changed handler**

Add this method after `_update_stance_for_weapon`:

```gdscript
func _on_stance_changed(stance: StanceManager.Stance) -> void:
	var hud := get_node_or_null("/root/test_scene/hud")
	if hud:
		hud.update_stance(stance, stance_manager.current_stances())
```

- [ ] **Step 5: Call _update_stance_for_weapon at end of _equip_weapon()**

`_equip_weapon()` currently ends with (around line 234):

```gdscript
	var hud := get_node_or_null("/root/test_scene/hud")
	if hud:
		var names := {fists: "Fists", revolver: "Revolver", bat: "Bat", katana: "Katana", shotgun: "Shotgun"}
		hud.set_weapon_name(names.get(weapon, ""))
```

Add one line at the very end of the function (after the `if hud:` block, not inside it):

```gdscript
	_update_stance_for_weapon(weapon)
```

- [ ] **Step 6: Connect the signal in _ready()**

In `_ready()`, after the existing signal connections (`revolver.ammo_changed.connect(...)`, `shotgun.ammo_changed.connect(...)`), add:

```gdscript
	stance_manager.stance_changed.connect(_on_stance_changed)
```

- [ ] **Step 7: Verify — launch scene, test scroll with fists**

Press F5. The game should launch without errors. Press 1 to equip fists (default). Scroll the mouse wheel up and down. Check the Output panel — you should see no errors. The `stance_changed` signal is firing but the HUD doesn't have `update_stance` yet, so `hud.update_stance()` will print an error ("method not found"). That's expected — it will be fixed in Task 7.

If you see errors OTHER than `update_stance` not found, fix them before continuing.

- [ ] **Step 8: Commit**

```bash
git add voxel-brawl/scripts/player.gd
git commit -m "feat: wire StanceManager into player — scroll cycles stance, equip resets to MID"
```

---

## Task 5: Create HudStanceIndicator script

**Files:**
- Create: `voxel-brawl/scripts/hud_stance_indicator.gd`

- [ ] **Step 1: Create the script**

```gdscript
# scripts/hud_stance_indicator.gd
class_name HudStanceIndicator
extends VBoxContainer

# Colors for active vs inactive rows
const COLOR_ACTIVE := Color(1.0, 0.85, 0.1, 1.0)    # bright yellow
const COLOR_INACTIVE := Color(0.6, 0.6, 0.6, 0.35)   # dim grey, translucent

@onready var row_thrust: HBoxContainer = $Row_THRUST
@onready var row_high: HBoxContainer = $Row_HIGH
@onready var row_mid: HBoxContainer = $Row_MID
@onready var row_low: HBoxContainer = $Row_LOW

# Maps each Stance value to its corresponding row node
var _row_map: Dictionary = {}

func _ready() -> void:
	_row_map = {
		StanceManager.Stance.THRUST: row_thrust,
		StanceManager.Stance.HIGH:   row_high,
		StanceManager.Stance.MID:    row_mid,
		StanceManager.Stance.LOW:    row_low,
	}

## Called by hud.gd whenever stance changes or weapon is switched.
## stance: the currently active stance
## available: the stances valid for the current weapon (empty = ranged, hide indicator)
func update(stance: StanceManager.Stance, available: Array[StanceManager.Stance]) -> void:
	visible = not available.is_empty()
	if not visible:
		return

	for s in _row_map:
		var row: HBoxContainer = _row_map[s]
		var in_available: bool = available.has(s)
		row.visible = in_available
		if in_available:
			var bar: ColorRect = row.get_node("Bar")
			var label: Label = row.get_node("Label")
			var is_active: bool = (s == stance)
			bar.color = COLOR_ACTIVE if is_active else COLOR_INACTIVE
			label.modulate = Color(1, 1, 1, 1.0) if is_active else Color(1, 1, 1, 0.4)
```

- [ ] **Step 2: Verify — check Output panel for parse errors**

Save the file. Output panel should be clean. If `StanceManager` isn't found, ensure `stance_manager.gd` is saved and in the same `scripts/` folder.

- [ ] **Step 3: Commit**

```bash
git add voxel-brawl/scripts/hud_stance_indicator.gd voxel-brawl/scripts/hud_stance_indicator.gd.uid
git commit -m "feat: add HudStanceIndicator script"
```

---

## Task 6: Create hud_stance_indicator.tscn (Godot editor)

**Files:**
- Create: `voxel-brawl/scenes/hud_stance_indicator.tscn` (editor step)

- [ ] **Step 1: Create a new scene**

In Godot: **Scene menu → New Scene**. In the Scene panel, click **Other Node**, search for `VBoxContainer`, select it. Click **Create**.

- [ ] **Step 2: Attach the script**

With the root `VBoxContainer` selected, click the Script field in the Inspector → **Load** → select `scripts/hud_stance_indicator.gd`. The node's name will update to show it has a script attached.

- [ ] **Step 3: Rename the root node**

Rename the root node to `HudStanceIndicator` (F2).

- [ ] **Step 4: Add the four rows**

Add four child nodes to `HudStanceIndicator`, each of type **HBoxContainer**, named exactly:
- `Row_THRUST`
- `Row_HIGH`
- `Row_MID`
- `Row_LOW`

Order in the tree must be top-to-bottom: Row_THRUST, Row_HIGH, Row_MID, Row_LOW (matching HIGH-at-top orientation in the HUD).

- [ ] **Step 5: Add Bar and Label to each row**

For each of the four rows, add two children:
1. A **ColorRect** named `Bar` — set its Custom Minimum Size to `(8, 18)` in the Inspector (a thin vertical bar)
2. A **Label** named `Label` — set its text to the stance name:
   - Row_THRUST → `"THRUST"`
   - Row_HIGH → `"HIGH"`
   - Row_MID → `"MID"`
   - Row_LOW → `"LOW"`

For the Label, in the Inspector set the font size to something readable but compact (e.g. 11pt). You can tune this visually later.

- [ ] **Step 6: Set VBoxContainer layout**

Select the root `HudStanceIndicator` node. In the Inspector, expand **Theme Overrides → Constants** and set **Separation** to 2 (tight rows). No other layout changes needed — positioning is handled by where it's placed in the HUD scene.

- [ ] **Step 7: Save the scene**

**Scene menu → Save Scene As** → navigate to `scenes/` → save as `hud_stance_indicator.tscn`.

- [ ] **Step 8: Commit**

```bash
git add voxel-brawl/scenes/hud_stance_indicator.tscn
git commit -m "feat: create HudStanceIndicator scene with 4 stance rows"
```

---

## Task 7: Wire HudStanceIndicator into HUD

**Files:**
- Modify: `voxel-brawl/scripts/hud.gd`
- Modify: `voxel-brawl/scenes/test_scene.tscn` (editor step)

- [ ] **Step 1: Update hud.gd**

Add one `@onready` and one method. The full updated file:

```gdscript
# scripts/hud.gd
extends CanvasLayer

@onready var ammo_label: Label = $AmmoLabel
@onready var reload_label: Label = $ReloadLabel
@onready var weapon_label: Label = $WeaponLabel
@onready var stance_indicator: HudStanceIndicator = $HudStanceIndicator

var _crosshair: Control

func _ready() -> void:
	reload_label.visible = false
	update_ammo(6, 6)

	_crosshair = load("res://scripts/crosshair.gd").new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

func recoil() -> void:
	_crosshair.recoil()

func update_ammo(current: int, max_ammo: int) -> void:
	ammo_label.text = "%d / %d" % [current, max_ammo]
	reload_label.visible = (current == 0)

func set_weapon_name(weapon_name: String) -> void:
	weapon_label.text = "[%s]" % weapon_name.to_upper()

func update_stance(stance: StanceManager.Stance, available: Array[StanceManager.Stance]) -> void:
	stance_indicator.update(stance, available)
```

- [ ] **Step 2: Instance HudStanceIndicator in test_scene.tscn**

Open `scenes/test_scene.tscn` in the Godot editor. In the Scene panel, find the `hud` node (CanvasLayer). Select it. Then drag `scenes/hud_stance_indicator.tscn` from the FileSystem panel onto the `hud` node to instance it as a child. Alternatively: right-click the `hud` node → **Instantiate Child Scene** → select `hud_stance_indicator.tscn`.

The child will appear as `HudStanceIndicator` under `hud`.

- [ ] **Step 3: Position the indicator**

Select the `HudStanceIndicator` node. In the Layout/Transform section of the Inspector, position it near the crosshair — a good starting point is bottom-right of center. Set **Anchor Preset** to "Center" first, then offset manually. Suggested offset: `(30, 20)` from center (slightly right and below the crosshair). You can fine-tune this visually in-game.

- [ ] **Step 4: Save test_scene.tscn**

Ctrl+S.

- [ ] **Step 5: Verify — launch and test all success criteria**

Press F5. Verify each item:

1. **Fists (press 1):** scroll up/down → HUD indicator visible, MID highlighted by default, LOW/HIGH cycle correctly. THRUST row should NOT appear.
2. **Bat (press 3):** same as fists — three rows, no THRUST.
3. **Katana (press 4):** four rows visible including THRUST. Scroll cycles through LOW → MID → HIGH → THRUST → LOW.
4. **Revolver (press 2):** HUD indicator hidden entirely.
5. **Shotgun (press 5):** HUD indicator hidden entirely.
6. **Switch from Katana to Fists:** indicator resets to MID, THRUST row disappears.
7. **Attack (left click):** combat behavior unchanged — hit detection still works, no errors.
8. **Output panel:** zero errors during all of the above.

- [ ] **Step 6: Commit**

```bash
git add voxel-brawl/scripts/hud.gd voxel-brawl/scenes/test_scene.tscn
git commit -m "feat: wire HudStanceIndicator into HUD — stance system Step 1 complete"
```

---

## Done

All 7 success criteria from the spec should now pass:

- [x] Scroll cycles stance for Fists, Bat, Katana
- [x] Scroll does nothing for Revolver, Shotgun
- [x] HUD shows correct stance highlighted
- [x] THRUST row visible only for Katana
- [x] Indicator hidden when ranged weapon equipped
- [x] Weapon switch resets stance to MID and updates HUD immediately
- [x] Existing combat behavior unchanged
