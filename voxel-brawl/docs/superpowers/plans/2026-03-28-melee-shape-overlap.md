# Melee Shape Overlap Hit Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken per-frame raycast sweep in `WeaponMelee` with a per-frame shape overlap query that reliably detects hits anywhere the weapon's collision shape contacts a target segment area.

**Architecture:** Each physics tick during the active hit window, `_shape_overlap_check()` calls `space.intersect_shape()` for every `CollisionShape3D` child of `_hit_area`, using each shape's current `global_transform`. Hits are processed identically to before: self-hit guard, per-swing dedup, `_apply_hit()` dispatch. Hit position is approximated as the shape center converted to segment-local space.

**Tech Stack:** Godot 4.6, GDScript, `PhysicsDirectSpaceState3D.intersect_shape()`, `PhysicsShapeQueryParameters3D`

**Spec:** `docs/superpowers/specs/2026-03-28-melee-shape-overlap-design.md`

---

## File Map

| File | Change |
|---|---|
| `scripts/weapon_melee.gd` | Remove sweep vars/methods; add `_shape_overlap_check()`; simplify enable/disable; remove `_create_sweep_markers()` virtual |
| `scripts/weapon_katana.gd` | Remove `_create_sweep_markers()` override |
| `scripts/weapon_bat.gd` | Remove `_create_sweep_markers()` override |
| `scripts/weapon_fists.gd` | Remove `_create_sweep_markers()` override; remove `left.disabled = true` |

---

## Task 1: Rewrite `weapon_melee.gd`

**Files:**
- Modify: `scripts/weapon_melee.gd`

- [ ] **Step 1: Replace the file contents**

Write `scripts/weapon_melee.gd` in full:

```gdscript
# scripts/weapon_melee.gd
# Melee weapon base — per-frame shape overlap hit detection with timer-driven activation window.
# Subclasses override _configure() for stats, _apply_hit() for damage behaviour,
# _create_hitarea() for composite collision shape setup.
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
var hit_shape: Shape3D = null            # set by subclass in _configure()
var hit_shape_offset: Vector3 = Vector3.ZERO
var hit_shape_rotation: Vector3 = Vector3.ZERO  # degrees — e.g. Vector3(90,0,0) to align capsule
var hit_shape_scale: Vector3 = Vector3.ONE

var _cooldown_timer := 0.0
var _hit_area: Area3D = null
var _hit_segments: Array[VoxelSegment] = []
var _own_segment_set: Dictionary = {}  # VoxelSegment -> true, lazy-populated on first use

var _hitbox_active := false

@onready var audio: AudioStreamPlayer3D = $AudioStreamPlayer3D

# _create_hitarea() must come after super() — hit_shape and hit_shape_offset are
# populated by _configure() inside super(), before _create_hitarea() runs.
func _ready() -> void:
	super()
	_create_hitarea()

# Virtual — override in subclasses to build composite hitbox shapes (e.g. WeaponFists
# adds a second CollisionShape3D for the left fist). Call super() first to get
# _hit_area created and the primary shape added.
# IMPORTANT: set hit_shape in _configure() for super() to build the primary shape.
# If hit_shape is null, super() skips the primary CollisionShape3D.
func _create_hitarea() -> void:
	_hit_area = Area3D.new()
	_hit_area.collision_layer = 0
	_hit_area.collision_mask = 2
	_hit_area.monitoring = false
	_hit_area.monitorable = false
	if hit_shape:
		var col := CollisionShape3D.new()
		col.shape = hit_shape
		col.position = hit_shape_offset
		col.rotation_degrees = hit_shape_rotation
		col.scale = hit_shape_scale
		_hit_area.add_child(col)
	add_child(_hit_area)
	# area_entered not connected — shape overlap query is the sole hit mechanism

func _enable_hitbox() -> void:
	_hitbox_active = true

func _disable_hitbox() -> void:
	_hitbox_active = false
	_hit_segments.clear()

func _physics_process(delta: float) -> void:
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	if Input.is_action_just_pressed("attack") and _cooldown_timer <= 0.0:
		_attack()
	if _hitbox_active:
		_shape_overlap_check()

# Each physics tick during the active window: query every CollisionShape3D in
# _hit_area against layer-2 areas. Fires _apply_hit() for the first max_hits
# unique, non-own segments found.
func _shape_overlap_check() -> void:
	if _hit_segments.size() >= max_hits:
		return
	var space := get_world_3d().direct_space_state
	for child in _hit_area.get_children():
		if not child is CollisionShape3D:
			continue
		var col := child as CollisionShape3D
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = col.shape
		params.transform = col.global_transform
		params.collision_mask = 2
		params.collide_with_areas = true
		params.collide_with_bodies = false
		var hits := space.intersect_shape(params, max_hits - _hit_segments.size())
		for hit_dict in hits:
			if _hit_segments.size() >= max_hits:
				return
			var area := hit_dict.collider as Area3D
			if area == null or not area.has_meta("voxel_segment"):
				continue
			var seg: VoxelSegment = area.get_meta("voxel_segment")
			if _own_segment_set.is_empty() and not _player.segments.is_empty():
				for s: VoxelSegment in _player.segments.values():
					_own_segment_set[s] = true
			if seg in _own_segment_set:
				continue
			if seg in _hit_segments:
				continue
			_hit_segments.append(seg)
			var local_hit := seg.to_local(col.global_transform.origin)
			_apply_hit(seg, local_hit)
			if _hit_segments.size() == 1:
				if audio.stream:
					audio.play()
				_player.trigger_hit_shake()
				_player.trigger_crosshair_recoil()

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

# Override in subclasses to implement weapon-specific damage behaviour.
func _apply_hit(seg: VoxelSegment, local_hit: Vector3) -> void:
	DamageManager.process_hit(seg, local_hit, voxel_radius, damage)
```

- [ ] **Step 2: Verify Godot reports no script errors**

Open Godot editor (or check the Output panel if already open). The script should parse with no errors. Look for any red errors in the Output panel mentioning `weapon_melee.gd`. If errors appear, fix them before continuing.

---

## Task 2: Remove `_create_sweep_markers()` overrides from subclasses

**Files:**
- Modify: `scripts/weapon_katana.gd`
- Modify: `scripts/weapon_bat.gd`
- Modify: `scripts/weapon_fists.gd`

- [ ] **Step 1: Update `weapon_katana.gd`**

Remove the `_create_sweep_markers()` override entirely. Final file:

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
	hit_shape_offset = Vector3(-0.3, 0.35, -0.9)
	hit_shape_rotation = Vector3(90, 0, 0)
	hit_shape_scale = Vector3(1.0, 4.0, 1.0)
	hit_enable_delay = 0.0
	hit_window_duration = 0.4
	max_hits = 3

func _apply_hit(seg: VoxelSegment, local_hit: Vector3) -> void:
	# Sharp slice: thin cut but extreme damage forces immediate detach threshold check.
	# A single clean hit to an arm or leg should sever it.
	DamageManager.process_hit(seg, local_hit, voxel_radius, damage)
	# TODO: start bleed timer on seg — drain N voxels per second for 3s after hit.
```

- [ ] **Step 2: Update `weapon_bat.gd`**

Remove the `_create_sweep_markers()` override entirely. Final file:

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
	hit_shape_offset = Vector3(-0.35, 0.35, -0.6)
	hit_shape_rotation = Vector3(90, 0, 0)
	hit_shape_scale = Vector3(1.0, 2.0, 1.0)
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

- [ ] **Step 3: Update `weapon_fists.gd`**

Remove `_create_sweep_markers()` override and remove `left.disabled = true` (shape disabled state no longer matters for manual queries). Final file:

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
	hit_shape_offset = Vector3(0, 0, -0.3)   # right fist — forward from weapon root
	hit_enable_delay = 0.08
	hit_window_duration = 0.12
	max_hits = 1

func _create_hitarea() -> void:
	super()   # builds _hit_area, adds right-fist sphere from hit_shape
	# Left fist — same shape, mirrored on X. Tune x_offset in-game via Remote tab.
	var left := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.3
	left.shape = s
	left.position = Vector3(-0.5, 0, -0.3)   # tune X until left knuckle aligns
	_hit_area.add_child(left)
```

- [ ] **Step 4: Verify Godot reports no script errors**

Check Output panel in Godot editor. All four scripts (weapon_melee, weapon_katana, weapon_bat, weapon_fists) should parse cleanly. Fix any errors before continuing.

---

## Task 3: In-game verification and commit

**Files:** None (verification only, then commit)

- [ ] **Step 1: Run the test scene**

In Godot editor, press F5 (or play `scenes/test_scene.tscn`). Equip the katana (press the katana keybind — check `player.gd` `_input()` for the key, default is likely `4`).

- [ ] **Step 2: Verify katana hits register from any approach angle**

Walk the player toward the dummy until they are within melee range (~1–2 units). Press the attack button (left click or the attack action). The dummy should lose voxels on contact. Approach from different angles (front, side) and verify hits register without needing to pre-position the blade inside the dummy.

Expected: voxels fly off the dummy on each successful attack. The hit shake and crosshair recoil fire.

- [ ] **Step 3: Verify no self-hits**

Attack without any target nearby. Confirm no voxels are removed from the player character itself.

- [ ] **Step 4: Verify bat hits (switch to bat, repeat step 2)**

Switch to the bat weapon. Confirm it also hits reliably on contact. The bat has `hit_enable_delay = 0.2` and `hit_window_duration = 0.18` — if hits feel narrow, note it for timing tuning in Step 5 but do not adjust yet.

- [ ] **Step 5: Commit**

```bash
git add scripts/weapon_melee.gd scripts/weapon_katana.gd scripts/weapon_bat.gd scripts/weapon_fists.gd
git commit -m "$(cat <<'EOF'
feat: replace sweep raycast with per-frame shape overlap hit detection

Drops BladeTip/BladeBase marker calibration entirely. Each physics tick
during the active window, intersect_shape() queries the weapon's existing
CollisionShape3D against layer-2 segment areas — hits register anywhere
the weapon mesh makes contact.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Notes

**If hits don't register at all after this change:**
1. Open `_shape_overlap_check()` and add a temporary print: `if hits.size() > 0: print("[MELEE] shape hits:", hits.size())`. Run the game and attack. If nothing prints, the query is finding nothing — likely a collision layer mismatch. Verify segment areas have `collision_layer = 2` (value 2, bit 1) in `player.gd` and that `params.collision_mask = 2` matches.
2. If the print fires but hits aren't processed, add `print("[MELEE] collider:", hit_dict.collider, " meta:", hit_dict.collider.has_meta("voxel_segment") if hit_dict.collider else "null")` inside the hit loop to trace the filter path.

**If too many segments hit per swing (max_hits not respected):**
Check that `_hit_segments.clear()` is called at the start of `_attack()` (it is) and that `_disable_hitbox()` also clears `_hit_segments` (it does). The `max_hits` cap at the top of `_shape_overlap_check()` and the per-shape early return guard both apply.

**Bat timing:** `hit_enable_delay = 0.2` means the bat window opens 200ms into the animation. If the bat swing completes before the window opens, reduce this value. The window duration is `0.18s` — very narrow. Both values can be tuned in `weapon_bat.gd`'s `_configure()`.
