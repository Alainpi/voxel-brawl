# Area3D Hitbox Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-frame AABB hit query in `WeaponMelee` with an Area3D hitbox that activates for a configurable time window during the swing, collecting overlapping VoxelSegment areas with per-swing dedup and a per-weapon hit cap.

**Architecture:** Each weapon creates its own `Area3D` child node programmatically in `_ready()`. The hitbox is disabled by default and enabled/disabled by two consecutive timers started in `_attack()`. `area_entered` signal collects and deduplicates VoxelSegment hits, applying damage immediately on first contact per segment.

**Tech Stack:** Godot 4.3, GDScript. No test framework — verification is manual in Godot editor and in-game.

---

## Files Modified

| File | Change |
|------|--------|
| `scripts/weapon_melee.gd` | Full rewrite of hit detection logic — remove `_do_hit()`, add Area3D hitbox system |
| `scripts/weapon_fists.gd` | Update `_configure()` — set hitbox shape vars, remove `hit_sphere_radius` |
| `scripts/weapon_bat.gd` | Same |
| `scripts/weapon_katana.gd` | Same |

No `.tscn` files, `player.gd`, or `weapon_base.gd` are touched.

---

## Task 1: Rewrite `weapon_melee.gd`

**Files:**
- Modify: `scripts/weapon_melee.gd`

This is a full replacement of the file's hit detection logic. Read the current file first, then apply the complete new version.

- [ ] **Step 1.1: Read the current file**

Read `scripts/weapon_melee.gd` in full before editing. Confirm it contains `_do_hit()`, `hit_delay`, and `hit_sphere_radius` — the three things being removed.

- [ ] **Step 1.2: Replace the file contents**

Write the complete new `weapon_melee.gd`:

```gdscript
# scripts/weapon_melee.gd
# Melee weapon base — Area3D overlap hit detection with timer-driven activation window.
# Subclasses override _configure() for stats and _apply_hit() for damage behaviour.
class_name WeaponMelee
extends WeaponBase

var damage := 10.0
var voxel_radius := 2.0
var reach := 0.5
var cooldown := 0.4
var attack_anim := "punch"

var hit_enable_delay := 0.1      # seconds from attack start until hitbox activates
var hit_window_duration := 0.15  # how long the hitbox stays active
var max_hits := 1                # max segments hit per swing; subclasses override
var hit_shape: Shape3D = null    # set by subclass in _configure()
var hit_shape_offset: Vector3 = Vector3.ZERO

var _cooldown_timer := 0.0
var _hit_area: Area3D = null
var _hit_segments: Array[VoxelSegment] = []

@onready var audio: AudioStreamPlayer3D = $AudioStreamPlayer3D

# _create_hitarea() must come after super() — hit_shape and hit_shape_offset are
# populated by _configure() inside super(), before _create_hitarea() runs.
func _ready() -> void:
	super()
	_create_hitarea()

# Virtual — override in subclasses to build composite hitbox shapes (e.g. axe with
# multiple blades). Call super() first to get _hit_area created and area_entered
# connected, then add additional CollisionShape3D children to _hit_area.
# If overriding without calling super(), you must create _hit_area and connect
# area_entered yourself.
# IMPORTANT: set hit_shape in _configure() for super() to build the primary shape.
# If hit_shape is null, super() skips the primary CollisionShape3D.
func _create_hitarea() -> void:
	_hit_area = Area3D.new()
	_hit_area.collision_layer = 0
	_hit_area.collision_mask = 2   # matches VoxelSegment area layer
	_hit_area.monitorable = false  # other areas cannot detect this hitbox; only this hitbox detects them
	if hit_shape:
		var col := CollisionShape3D.new()
		col.shape = hit_shape
		col.position = hit_shape_offset
		col.disabled = true
		_hit_area.add_child(col)
	add_child(_hit_area)
	_hit_area.area_entered.connect(_on_hit_area_entered)

func _enable_hitbox() -> void:
	for child in _hit_area.get_children():
		if child is CollisionShape3D:
			child.disabled = false

func _disable_hitbox() -> void:
	for child in _hit_area.get_children():
		if child is CollisionShape3D:
			child.disabled = true

func _physics_process(delta: float) -> void:
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	if Input.is_action_just_pressed("attack") and _cooldown_timer <= 0.0:
		_attack()

func _attack() -> void:
	_cooldown_timer = cooldown
	_hit_segments.clear()
	_player.play_attack_anim(attack_anim)
	await get_tree().create_timer(hit_enable_delay).timeout
	if not is_instance_valid(self) or not _player._is_attacking:
		return   # node freed, or interrupted by death / weapon swap
	_enable_hitbox()
	await get_tree().create_timer(hit_window_duration).timeout
	if is_instance_valid(self):
		_disable_hitbox()

func _on_hit_area_entered(area: Area3D) -> void:
	# Filter order: reject non-segments first so environmental areas don't consume hit slots.
	if not area.has_meta("voxel_segment"):
		return
	var seg: VoxelSegment = area.get_meta("voxel_segment")
	if seg in _hit_segments:
		return
	if _hit_segments.size() >= max_hits:
		return
	_hit_segments.append(seg)
	# local_hit uses Area3D origin as approximation — Step 4 replaces with blade-tip sweep.
	var local_hit := seg.to_local(_hit_area.global_position)
	_apply_hit(seg, local_hit)
	if _hit_segments.size() == 1:   # feedback fires once per swing on first hit
		if audio.stream:
			audio.play()
		_player.trigger_hit_shake()
		_player.trigger_crosshair_recoil()

# Override in subclasses to implement weapon-specific damage behaviour.
func _apply_hit(seg: VoxelSegment, local_hit: Vector3) -> void:
	DamageManager.process_hit(seg, local_hit, voxel_radius, damage)
```

- [ ] **Step 1.3: Verify prerequisites before running**

The new code calls `_player.trigger_hit_shake()` and `_player.trigger_crosshair_recoil()` for the first time at runtime — the old `_do_hit()` had a bug (`break` before `hit_any = true`) that made these unreachable. Confirm both methods exist on Player before running:

```bash
grep -n "func trigger_hit_shake\|func trigger_crosshair_recoil" scripts/player.gd
```

Expected: two matches. If missing, the game will error on first hit.

Then open the Godot editor, open `weapon_melee.gd` in the Script tab, and confirm:
- No red error markers in the gutter
- No errors in the Output panel on scene load

- [ ] **Step 1.4: Commit**

```bash
git add scripts/weapon_melee.gd
git commit -m "feat: replace _do_hit() with Area3D hitbox + timer window in WeaponMelee"
```

---

## Task 2: Update `weapon_fists.gd`

**Files:**
- Modify: `scripts/weapon_fists.gd`

- [ ] **Step 2.1: Read the current file**

Read `scripts/weapon_fists.gd`. Confirm it sets `hit_sphere_radius` — this is being removed.

- [ ] **Step 2.2: Replace the file contents**

```gdscript
# scripts/weapon_fists.gd
class_name WeaponFists
extends WeaponMelee

func _configure() -> void:
	weapon_type = WeaponType.BLUNT
	damage = 8.0
	voxel_radius = 2.0
	reach = 0.5
	cooldown = 0.35
	attack_anim = "punch"
	var s := SphereShape3D.new()
	s.radius = 0.3
	hit_shape = s
	hit_shape_offset = Vector3(0, 0, -0.3)   # forward from weapon root
	hit_enable_delay = 0.08
	hit_window_duration = 0.12
	max_hits = 1
```

- [ ] **Step 2.3: Verify in Godot**

Open the Godot editor, confirm no script errors. Run the game (`F5`), equip fists (key `1`), and swing (left click). Confirm:
- Attack animation plays
- No errors in Output

Hit detection against the dummy (or against a brawler NPC if in the test scene) can be confirmed visually — voxels should carve on contact.

- [ ] **Step 2.4: Commit**

```bash
git add scripts/weapon_fists.gd
git commit -m "feat: update WeaponFists _configure() with Area3D hitbox shape"
```

---

## Task 3: Update `weapon_bat.gd`

**Files:**
- Modify: `scripts/weapon_bat.gd`

- [ ] **Step 3.1: Read the current file**

Read `scripts/weapon_bat.gd`. Confirm it sets `hit_sphere_radius` and has `_apply_hit()`.

- [ ] **Step 3.2: Replace the file contents**

```gdscript
# scripts/weapon_bat.gd
# Blunt trauma weapon. Wide impact radius, high structural damage.
# Breaks bones and degrades limb function without clean severing.
# Does not cause bleed. TODO: implement bone degradation / limb disable system.
class_name WeaponBat
extends WeaponMelee

func _configure() -> void:
	weapon_type = WeaponType.BLUNT
	damage = 22.0
	voxel_radius = 2.8   # wide blunt impact area
	reach = 0.9
	cooldown = 0.65
	attack_anim = "bat"
	var s := CapsuleShape3D.new()
	s.radius = 0.15
	s.height = 0.8
	hit_shape = s
	hit_shape_offset = Vector3(0, 0.4, 0)   # offset toward barrel end
	hit_enable_delay = 0.2
	hit_window_duration = 0.18
	max_hits = 2

func _apply_hit(seg: VoxelSegment, local_hit: Vector3) -> void:
	# Blunt hit: large voxel removal simulates structural crushing.
	# High damage compresses the limb HP without triggering a clean sever —
	# the bat degrades the limb over multiple hits rather than slicing through.
	# TODO: reduce detach impulse force so limbs crumple rather than fly off cleanly.
	DamageManager.process_hit(seg, local_hit, voxel_radius, damage)
```

- [ ] **Step 3.3: Verify in Godot**

Run the game, equip bat (key `3`), swing at a target. Confirm:
- Attack animation plays
- No errors in Output

- [ ] **Step 3.4: Commit**

```bash
git add scripts/weapon_bat.gd
git commit -m "feat: update WeaponBat _configure() with Area3D hitbox shape"
```

---

## Task 4: Update `weapon_katana.gd`

**Files:**
- Modify: `scripts/weapon_katana.gd`

- [ ] **Step 4.1: Read the current file**

Read `scripts/weapon_katana.gd`. Confirm it sets `hit_sphere_radius` and has `_apply_hit()`.

- [ ] **Step 4.2: Replace the file contents**

```gdscript
# scripts/weapon_katana.gd
# Precision blade. Thin slice, very high damage — can sever a limb in one clean hit.
# Causes bleed (ongoing voxel drain after the strike).
# TODO: implement bleed system (timed voxel drain on hit segment).
class_name WeaponKatana
extends WeaponMelee

func _configure() -> void:
	weapon_type = WeaponType.SHARP
	damage = 45.0
	voxel_radius = 0.7   # thin precise slice — surgical removal
	reach = 1.0
	cooldown = 0.3
	attack_anim = "katana"
	var s := BoxShape3D.new()
	s.size = Vector3(0.05, 0.6, 0.05)
	hit_shape = s
	hit_shape_offset = Vector3(0, 0.3, 0)   # offset toward blade tip
	hit_enable_delay = 0.1
	hit_window_duration = 0.15
	max_hits = 3

func _apply_hit(seg: VoxelSegment, local_hit: Vector3) -> void:
	# Sharp slice: thin cut but extreme damage forces immediate detach threshold check.
	# A single clean hit to an arm or leg should sever it.
	DamageManager.process_hit(seg, local_hit, voxel_radius, damage)
	# TODO: start bleed timer on seg — drain N voxels per second for 3s after hit.
```

- [ ] **Step 4.3: Verify in Godot**

Run the game, equip katana (key `4`), swing at a target. Confirm:
- Attack animation plays
- No errors in Output

- [ ] **Step 4.4: Commit**

```bash
git add scripts/weapon_katana.gd
git commit -m "feat: update WeaponKatana _configure() with Area3D hitbox shape"
```

---

## Task 5: Full Verification

**No files modified — testing only.**

Run the game and verify all test criteria from the spec.

- [ ] **Step 5.1: Verify hits register**

Equip each weapon (fists `1`, bat `3`, katana `4`). Swing into the dummy or a brawler. Confirm:
- Voxels carve on contact for all three weapons
- Hit audio plays on contact
- No errors in Output

- [ ] **Step 5.2: Verify dedup — same segment not hit twice per swing**

Stand close to the dummy so the hitbox overlaps a segment for the full window. Swing once. Confirm the same segment is only damaged once per swing (voxel count should drop once, not continuously during the window).

- [ ] **Step 5.3: Verify max_hits cap**

With the katana (max_hits = 3): swing through an arm and torso. At most 3 segments should register damage per swing. With the bat (max_hits = 2): at most 2 segments per swing.

With fists (max_hits = 1): only one segment should register per punch even if the hitbox overlaps multiple.

- [ ] **Step 5.4: Verify interrupt on weapon swap**

Start swinging (left click), immediately switch weapons before the hit window opens. Confirm:
- No hit registers
- No errors in Output (the `is_instance_valid(self) or not _player._is_attacking` guard handles this)

- [ ] **Step 5.5: Verify misses produce no feedback**

Swing in open air with no targets nearby. Confirm:
- No audio plays
- No screen shake

- [ ] **Step 5.6: Known limitation — note crater position**

Observe that voxel craters appear at the weapon's root position (handle), not at the blade tip. This is expected — Step 4 (blade-tip sweep raycast) fixes this. No action needed.

- [ ] **Step 5.7: Commit verification note**

```bash
git commit --allow-empty -m "test: Step 3 hitbox verified — hits, dedup, max_hits cap, interrupt, miss all pass"
```

---

## Timing Tuning Reference

If hit detection feels off after verification, adjust these vars in each weapon's `_configure()`:

| Var | Effect |
|-----|--------|
| `hit_enable_delay` | Higher = hitbox opens later in the swing. Increase if hits register during windup. |
| `hit_window_duration` | Higher = wider hit window. Increase if hits miss on fast swings. |
| `hit_shape_offset` | Shift along weapon's local axes to move hitbox toward striking surface. |
| `hit_shape` dimensions | Larger = more forgiving detection, less precise. |

All values are in seconds (timers) or Godot units (shape). Starting values in the spec are approximate — expect tuning.
