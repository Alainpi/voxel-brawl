# Animation Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the stance selector to stance-specific attack animations — each melee attack plays the animation matching the current stance.

**Architecture:** Only `player.gd` changes. `play_attack_anim()` builds the animation name from the weapon's prefix and the current stance (`"bat" + "_" + "low"` → `"bat_low"`). An `_is_attacking` bool replaces the old hardcoded animation-name guard in `_update_animation()`, and is cleared by connecting to `anim_player.animation_finished`.

**Tech Stack:** Godot 4.3, GDScript. No test framework — verification is done by running the scene.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `voxel-brawl/scripts/player.gd` | Modify | All changes live here — `_is_attacking` field, updated `play_attack_anim()`, updated `_update_animation()` guard, new `_on_anim_finished()` handler, reset in `_equip_weapon()` |

No other files change.

---

## Task 1: Verify animation names in Godot's AnimationPlayer

**Files:**
- No code changes — editor verification only

Before touching any code, confirm that all 10 stance animation names exist in the project exactly as the code will request them. A single typo will produce a silent `push_error` and no animation.

- [ ] **Step 1: Open the AnimationPlayer in Godot**

In Godot's FileSystem panel, open `voxel-brawl/scenes/player.tscn`. Select the `PlayerModel` node in the Scene panel, then find its `AnimationPlayer` child. Click it. The Animation panel at the bottom of the editor will show all available animations.

- [ ] **Step 2: Verify all 10 names are present**

Confirm each of the following names appears in the list exactly — no dashes, no spaces, no capitalization differences:

```
punch_low
punch_mid
punch_high
bat_low
bat_mid
bat_high
katana_low
katana_mid
katana_high
katana_thrust
```

If any name is missing or mismatched, fix the Blender export and re-import before continuing. Do not proceed until all 10 are confirmed.

---

## Task 2: Implement all `player.gd` changes

**Files:**
- Modify: `voxel-brawl/scripts/player.gd:53-57` (add field)
- Modify: `voxel-brawl/scripts/player.gd:102-106` (connect signal in `_ready`)
- Modify: `voxel-brawl/scripts/player.gd:206-210` (update `_update_animation` guard)
- Modify: `voxel-brawl/scripts/player.gd:224-225` (reset flag in `_equip_weapon`)
- Modify: `voxel-brawl/scripts/player.gd:280-291` (rewrite `play_attack_anim`)
- Add: new `_on_anim_finished()` method after `play_attack_anim`

- [ ] **Step 1: Add the `_is_attacking` field**

Find the var block around line 52 (near `_is_dead`, `_legs_lost`, `_current_weapon`):

```gdscript
var segments: Dictionary = {}
var _is_dead: bool = false
var _legs_lost: int = 0
var _weapon_anchor: Node3D = null

var _current_weapon: Node = null
```

Add `_is_attacking` on a new line after `_current_weapon`:

```gdscript
var segments: Dictionary = {}
var _is_dead: bool = false
var _legs_lost: int = 0
var _weapon_anchor: Node3D = null

var _current_weapon: Node = null
var _is_attacking: bool = false
```

- [ ] **Step 2: Connect `animation_finished` signal in `_ready()`**

In `_ready()`, find the existing signal connections (around line 102):

```gdscript
	revolver.ammo_changed.connect(_on_ammo_changed)
	shotgun.ammo_changed.connect(_on_ammo_changed)
	_equip_weapon.call_deferred(fists)
	stance_manager.stance_changed.connect(_on_stance_changed)
```

Add the new connection on the line after `stance_manager.stance_changed.connect(...)`:

```gdscript
	revolver.ammo_changed.connect(_on_ammo_changed)
	shotgun.ammo_changed.connect(_on_ammo_changed)
	_equip_weapon.call_deferred(fists)
	stance_manager.stance_changed.connect(_on_stance_changed)
	anim_player.animation_finished.connect(_on_anim_finished)
```

- [ ] **Step 3: Update the `_update_animation()` attack guard**

Find `_update_animation()` around line 206. Replace these three lines:

```gdscript
	var cur := anim_player.current_animation
	if anim_player.is_playing() and cur in ["punch-right", "holding-right-shoot", "bat-swing", "katana-slash"]:
		return
```

With:

```gdscript
	if _is_attacking:
		return
```

The `cur` variable is only used by the removed guard, so it is removed along with it. The rest of `_update_animation()` is unchanged.

Full function after edit:

```gdscript
func _update_animation(_dir: Vector3) -> void:
	if _is_attacking:
		return
	if _current_weapon == revolver or _current_weapon == shotgun:
		anim_player.play("holding-right")
	elif _current_weapon == bat:
		anim_player.play("bat-hold")
	elif _current_weapon == katana:
		anim_player.play("katana-hold")
	else:
		var speed_h := Vector2(velocity.x, velocity.z).length()
		if speed_h > 0.1:
			anim_player.play("walk")
		else:
			anim_player.play("idle")
```

- [ ] **Step 4: Add `_is_attacking = false` as first line of `_equip_weapon()`**

Find `_equip_weapon()` around line 224:

```gdscript
func _equip_weapon(weapon: Node) -> void:
	fists.visible = (weapon == fists)
```

Add `_is_attacking = false` as the very first line:

```gdscript
func _equip_weapon(weapon: Node) -> void:
	_is_attacking = false
	fists.visible = (weapon == fists)
```

This ensures that switching weapons mid-attack immediately un-blocks locomotion on the next frame. Without it, `_update_animation()` would keep returning early until the old attack animation finished.

- [ ] **Step 5: Rewrite `play_attack_anim()`**

Find `play_attack_anim()` around line 280. Replace the entire function:

Old:
```gdscript
func play_attack_anim(anim_name: String) -> void:
	var mapped := anim_name
	if anim_name == "shoot":
		mapped = "holding-right-shoot"
	elif anim_name == "punch":
		mapped = "punch-right"
	elif anim_name == "bat":
		mapped = "bat-swing"
	elif anim_name == "katana":
		mapped = "katana-slash"
	anim_player.stop()
	anim_player.play(mapped)
```

New:
```gdscript
func play_attack_anim(anim_name: String) -> void:
	var mapped: String
	if anim_name == "shoot":
		mapped = "holding-right-shoot"
	else:
		var stance_key := StanceManager.Stance.find_key(stance_manager.current_stance()).to_lower()
		mapped = anim_name + "_" + stance_key
	if not anim_player.has_animation(mapped):
		push_error("play_attack_anim: animation not found: " + mapped)
		return
	_is_attacking = true
	anim_player.stop()
	anim_player.play(mapped)
```

How it works:
- `StanceManager.Stance.find_key(stance_manager.current_stance())` returns the enum key as a string: `"LOW"`, `"MID"`, `"HIGH"`, or `"THRUST"`
- `.to_lower()` converts to `"low"`, `"mid"`, etc.
- Combined with the weapon's `attack_anim` prefix: `"bat" + "_" + "low"` → `"bat_low"`
- `has_animation()` guards against missing names — prevents `_is_attacking` from getting stuck true when a name is wrong

- [ ] **Step 6: Add `_on_anim_finished()` handler**

Add this new method immediately after `play_attack_anim()`:

```gdscript
func _on_anim_finished(_anim_name: String) -> void:
	_is_attacking = false
```

`animation_finished` only fires for non-looping animations. `idle`, `walk`, `bat-hold`, `katana-hold`, and `holding-right` are all looping — they never trigger this signal. Only attack animations (non-looping) will clear the flag.

- [ ] **Step 7: Verify — launch and test all success criteria**

Press F5 to run the project. Test each item:

1. **Fists (press 1), scroll to LOW, left-click** → `punch_low` should play (watch the character's arm swing low)
2. **Fists, scroll to HIGH, left-click** → `punch_high` plays (high arc)
3. **Fists, scroll to MID (default), left-click** → `punch_mid` plays
4. **Bat (press 3), MID stance, left-click** → `bat_mid` plays
5. **Katana (press 4), scroll to THRUST, left-click** → `katana_thrust` plays (forward stab)
6. **Revolver (press 2), shoot** → `holding-right-shoot` plays, unchanged
7. **Switch weapon mid-swing** — equip fists, start an attack, immediately press 3 to switch to bat. Locomotion should resume immediately (not stay locked in fist-swing animation)
8. **Locomotion after attack** — equip fists, attack, wait for animation to finish. Player should return to idle/walk correctly
9. **Output panel** — zero errors during all of the above. If you see `play_attack_anim: animation not found:` in the output, there's a naming mismatch — check Task 1 verification against the actual animation names

- [ ] **Step 8: Commit**

```bash
git add voxel-brawl/scripts/player.gd
git commit -m "feat: wire stance to attack animations — play_attack_anim uses stance suffix, _is_attacking flag replaces hardcoded guard"
```

---

## Done

All success criteria from the spec should now pass:

- [ ] Equip fists, scroll to LOW, attack → `punch_low` plays
- [ ] Equip fists, scroll to HIGH, attack → `punch_high` plays
- [ ] Equip bat at default MID, attack → `bat_mid` plays
- [ ] Equip katana, scroll to THRUST, attack → `katana_thrust` plays
- [ ] Equip revolver, shoot → `holding-right-shoot` plays, unchanged
- [ ] Switching weapons resets stance to MID → next attack plays the `_mid` variant
- [ ] Switching weapons mid-attack → locomotion resumes immediately
- [ ] Locomotion resumes after attack animation finishes
- [ ] No errors in Output panel
