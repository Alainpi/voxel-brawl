# Blade-Tip Sweep Raycast Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `area_entered`-driven hit detection with per-frame blade-tip raycasts that deliver exact voxel contact points.

**Architecture:** Two `Marker3D` nodes (`BladeTip`, `BladeBase`) are created procedurally per weapon via a `_create_sweep_markers()` virtual. Each physics frame during the active window, two raycasts sweep from the previous frame's positions to the current, calling `_apply_hit` with the exact intersection point. The `Area3D` is retained as a visual gate (its `CollisionShape3D` children toggle disabled/enabled) but no longer detects overlaps.

**Tech Stack:** Godot 4.3, GDScript, `PhysicsDirectSpaceState3D.intersect_ray`

---

## File Map

| File | Status | Responsibility |
|------|--------|---------------|
| `scripts/weapon_melee.gd` | Modify | Add `_hitbox_active` flag, `_blade_tip`/`_blade_base` Marker3Ds, prev-pos tracking, `_create_sweep_markers()` virtual, `_sweep_check()`, sweep in `_physics_process`, remove `area_entered` path |
| `scripts/weapon_bat.gd` | Modify | Override `_create_sweep_markers()` with bat-specific marker positions |
| `scripts/weapon_katana.gd` | Modify | Override `_create_sweep_markers()` with katana-specific marker positions |
| `scripts/weapon_fists.gd` | Modify | Override `_create_sweep_markers()` with fists-specific marker positions |

---

## Task 1: Add `_hitbox_active` flag; update `_enable_hitbox` / `_disable_hitbox`

**Files:**
- Modify: `scripts/weapon_melee.gd`

This is a safe first step — it adds the flag and wires it into the existing enable/disable methods without touching hit detection yet. All existing hits continue working via `area_entered`.

- [ ] **Step 1: Add `_hitbox_active` var after the existing private vars block**

Open `scripts/weapon_melee.gd`. After line:
```gdscript
var _own_segment_set: Dictionary = {}  # VoxelSegment -> true, lazy-populated on first use
```
Add:
```gdscript
var _hitbox_active := false
```

- [ ] **Step 2: Update `_enable_hitbox()` to set flag and reset prev-positions**

Replace the existing `_enable_hitbox()`:
```gdscript
func _enable_hitbox() -> void:
	for child in _hit_area.get_children():
		if child is CollisionShape3D:
			child.disabled = false
```
With:
```gdscript
func _enable_hitbox() -> void:
	for child in _hit_area.get_children():
		if child is CollisionShape3D:
			child.disabled = false
	_hitbox_active = true
	_prev_tip_pos = Vector3.INF
	_prev_base_pos = Vector3.INF
```

Note: `_prev_tip_pos` and `_prev_base_pos` don't exist yet — they are declared in Task 2. This file won't parse until Task 2 is complete. Do Tasks 1 and 2 in the same session without running between them.

- [ ] **Step 3: Update `_disable_hitbox()` to clear flag and reset prev-positions**

Replace the existing `_disable_hitbox()`:
```gdscript
func _disable_hitbox() -> void:
	for child in _hit_area.get_children():
		if child is CollisionShape3D:
			child.disabled = true
```
With:
```gdscript
func _disable_hitbox() -> void:
	for child in _hit_area.get_children():
		if child is CollisionShape3D:
			child.disabled = true
	_hitbox_active = false
	_prev_tip_pos = Vector3.INF
	_prev_base_pos = Vector3.INF
```

---

## Task 2: Add marker vars, `_create_sweep_markers()` virtual, update `_ready()`

**Files:**
- Modify: `scripts/weapon_melee.gd`

Completes the parse errors from Task 1 and adds the marker infrastructure. After this task the game runs and Remote panel shows `BladeTip` / `BladeBase` nodes under each weapon at the weapon root (origin).

- [ ] **Step 1: Add marker and prev-position vars after `_hitbox_active`**

After:
```gdscript
var _hitbox_active := false
```
Add:
```gdscript
var _blade_tip: Marker3D = null
var _blade_base: Marker3D = null
var _prev_tip_pos := Vector3.INF
var _prev_base_pos := Vector3.INF
```

- [ ] **Step 2: Update `_ready()` to call `_create_sweep_markers()`**

Replace:
```gdscript
func _ready() -> void:
	super()
	_create_hitarea()
```
With:
```gdscript
func _ready() -> void:
	super()
	_create_hitarea()
	_create_sweep_markers()
```

- [ ] **Step 3: Add `_create_sweep_markers()` virtual after `_create_hitarea()`**

Insert this method immediately after the closing `}` of `_create_hitarea()`:
```gdscript
# Virtual — override in subclasses to place BladeTip and BladeBase at weapon-specific
# local positions. Call super() first so _blade_tip and _blade_base are created before
# you set their positions.
func _create_sweep_markers() -> void:
	_blade_tip = Marker3D.new()
	_blade_tip.name = "BladeTip"
	add_child(_blade_tip)
	_blade_base = Marker3D.new()
	_blade_base.name = "BladeBase"
	add_child(_blade_base)
```

- [ ] **Step 4: Run the game (F5) and verify markers appear in Remote panel**

In Godot: Run → play scene. Open the Remote tab in the Scene dock. Navigate to any player → WeaponHolder → [active weapon]. You should see `BladeTip` and `BladeBase` as children of the weapon node, both at position `(0, 0, 0)`.

Expected: two Marker3D nodes visible in Remote for each weapon. No errors in Output.

- [ ] **Step 5: Commit**

```
git add scripts/weapon_melee.gd
git commit -m "feat: add _hitbox_active flag and BladeTip/BladeBase Marker3D infrastructure"
```

---

## Task 3: Add `_create_sweep_markers()` overrides to weapon subclasses

**Files:**
- Modify: `scripts/weapon_bat.gd`
- Modify: `scripts/weapon_katana.gd`
- Modify: `scripts/weapon_fists.gd`

After this task, Remote panel shows markers at weapon-specific positions rather than the root. Positions are starting values — tune in Remote after Task 4 is complete.

- [ ] **Step 1: Add override to `weapon_bat.gd`**

Add after `_apply_hit()`:
```gdscript
func _create_sweep_markers() -> void:
	super()
	_blade_tip.position = Vector3(-0.35, 0.35, -1.2)   # far end of barrel
	_blade_base.position = Vector3(-0.35, 0.35, -0.4)  # handle-barrel junction
```

- [ ] **Step 2: Add override to `weapon_katana.gd`**

Add after `_apply_hit()`:
```gdscript
func _create_sweep_markers() -> void:
	super()
	_blade_tip.position = Vector3(-0.3, 0.35, -1.6)    # blade tip
	_blade_base.position = Vector3(-0.3, 0.35, -0.5)   # blade-guard junction
```

- [ ] **Step 3: Add override to `weapon_fists.gd`**

Add after `_create_hitarea()`:
```gdscript
func _create_sweep_markers() -> void:
	super()
	_blade_tip.position = Vector3(0.0, 0.0, -0.4)      # right knuckles
	_blade_base.position = Vector3(0.0, 0.0, -0.1)     # right wrist
```

- [ ] **Step 4: Run the game and verify marker positions**

Run → Remote panel → navigate to each weapon. Verify:
- Bat: BladeTip at `(-0.35, 0.35, -1.2)`, BladeBase at `(-0.35, 0.35, -0.4)`
- Katana: BladeTip at `(-0.3, 0.35, -1.6)`, BladeBase at `(-0.3, 0.35, -0.5)`
- Fists: BladeTip at `(0, 0, -0.4)`, BladeBase at `(0, 0, -0.1)`

No errors in Output. Hits still register via `area_entered` (unchanged).

- [ ] **Step 5: Commit**

```
git add scripts/weapon_bat.gd scripts/weapon_katana.gd scripts/weapon_fists.gd
git commit -m "feat: add _create_sweep_markers() overrides with initial positions for bat, katana, fists"
```

---

## Task 4: Implement `_sweep_check()` and update `_physics_process()`

**Files:**
- Modify: `scripts/weapon_melee.gd`

After this task, hits register via both the sweep AND `area_entered` (temporarily). Deduplication in `_hit_segments` prevents double damage — the same segment can only be hit once per swing regardless of which path fires first. The key observable change: voxel craters now appear at the blade contact point rather than the weapon root.

- [ ] **Step 1: Observe current (broken) behavior before changing anything**

Run the game. Equip the katana. Swing at a dummy. Note where the voxel crater appears — it should be somewhere near the weapon's root position (handle area), not where the blade visually connects. This is the bug we are fixing.

- [ ] **Step 2: Add sweep logic to `_physics_process()`**

Replace the existing `_physics_process()`:
```gdscript
func _physics_process(delta: float) -> void:
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	if Input.is_action_just_pressed("attack") and _cooldown_timer <= 0.0:
		_attack()
```
With:
```gdscript
func _physics_process(delta: float) -> void:
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	if Input.is_action_just_pressed("attack") and _cooldown_timer <= 0.0:
		_attack()

	if _hitbox_active:
		var tip_now := _blade_tip.global_position
		var base_now := _blade_base.global_position
		if _prev_tip_pos != Vector3.INF:
			_sweep_check(_prev_tip_pos, tip_now)
			_sweep_check(_prev_base_pos, base_now)
		_prev_tip_pos = tip_now
		_prev_base_pos = base_now
```

- [ ] **Step 3: Add `_sweep_check()` after `_physics_process()`**

Insert this method immediately after `_physics_process()`:
```gdscript
func _sweep_check(from: Vector3, to: Vector3) -> void:
	if _hit_segments.size() >= max_hits:
		return
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 2)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result := space.intersect_ray(query)
	if not result or not result.collider is Area3D:
		return
	if not result.collider.has_meta("voxel_segment"):
		return
	var seg: VoxelSegment = result.collider.get_meta("voxel_segment")
	if _own_segment_set.is_empty() and not _player.segments.is_empty():
		for s: VoxelSegment in _player.segments.values():
			_own_segment_set[s] = true
	if seg in _own_segment_set:
		return
	if seg in _hit_segments:
		return
	_hit_segments.append(seg)
	var local_hit := seg.to_local(result.position)
	_apply_hit(seg, local_hit)
	if _hit_segments.size() == 1:
		if audio.stream:
			audio.play()
		_player.trigger_hit_shake()
		_player.trigger_crosshair_recoil()
```

- [ ] **Step 4: Run the game and verify craters appear at blade contact point**

Run → swing the katana at a dummy's torso. The voxel crater should now appear where the blade visually passes through the segment — not at the handle. Swing the bat at a leg — crater at the barrel end. Punch — crater at the knuckles.

Audio, screen shake, and crosshair recoil should fire once per connecting swing.

If a crater still appears at the wrong location, the marker positions need tuning. Open Remote panel during play, select BladeTip on the active weapon, and adjust its local position until it aligns with the visual blade end. Note the final values — update the override in the script.

- [ ] **Step 5: Commit**

```
git add scripts/weapon_melee.gd
git commit -m "feat: add per-frame blade-tip sweep raycast for precise voxel hit points"
```

---

## Task 5: Remove `area_entered` from hit path; clean up `_on_hit_area_entered`

**Files:**
- Modify: `scripts/weapon_melee.gd`

After this task, the sweep is the sole hit mechanism. `area_entered` is fully disconnected and `_on_hit_area_entered` is deleted.

- [ ] **Step 1: Update `_create_hitarea()` — remove signal connection, add `monitoring = false`**

Replace the existing `_create_hitarea()`:
```gdscript
func _create_hitarea() -> void:
	_hit_area = Area3D.new()
	_hit_area.collision_layer = 0
	_hit_area.collision_mask = 2
	_hit_area.monitorable = false
	if hit_shape:
		var col := CollisionShape3D.new()
		col.shape = hit_shape
		col.position = hit_shape_offset
		col.rotation_degrees = hit_shape_rotation
		col.scale = hit_shape_scale
		col.disabled = true
		_hit_area.add_child(col)
	add_child(_hit_area)
	_hit_area.area_entered.connect(_on_hit_area_entered)
```
With:
```gdscript
# Virtual — override in subclasses to build composite hitbox shapes (e.g. axe with
# multiple blades). Call super() first to get _hit_area created, then add additional
# CollisionShape3D children to _hit_area.
# IMPORTANT: set hit_shape in _configure() for super() to build the primary shape.
# If hit_shape is null, super() skips the primary CollisionShape3D.
func _create_hitarea() -> void:
	_hit_area = Area3D.new()
	_hit_area.collision_layer = 0
	_hit_area.collision_mask = 2
	_hit_area.monitoring = false      # sweep handles detection; Area3D is gate only
	_hit_area.monitorable = false
	if hit_shape:
		var col := CollisionShape3D.new()
		col.shape = hit_shape
		col.position = hit_shape_offset
		col.rotation_degrees = hit_shape_rotation
		col.scale = hit_shape_scale
		col.disabled = true
		_hit_area.add_child(col)
	add_child(_hit_area)
	# area_entered not connected — sweep is the sole hit mechanism
```

- [ ] **Step 2: Delete `_on_hit_area_entered()` entirely**

Remove the entire method — all lines from `func _on_hit_area_entered(area: Area3D) -> void:` through its closing `}`. The method is:
```gdscript
func _on_hit_area_entered(area: Area3D) -> void:
	# Filter order: reject non-segments first so environmental areas don't consume hit slots.
	if not area.has_meta("voxel_segment"):
		return
	var seg: VoxelSegment = area.get_meta("voxel_segment")
	# Lazy-populate own segment set (player builds segments deferred, so segments dict
	# may be empty when weapon _ready() fires — populate on first area_entered instead).
	if _own_segment_set.is_empty() and not _player.segments.is_empty():
		for s: VoxelSegment in _player.segments.values():
			_own_segment_set[s] = true
	if seg in _own_segment_set:   # O(1) hash lookup — no allocation
		return
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
```
Delete it completely. Do not leave an empty method shell.

- [ ] **Step 3: Run the game and verify hits still register via sweep only**

Run → swing all three weapons at a dummy. Verify:
- Hits register with correct crater position (blade contact point)
- Audio and shake fire once per connecting swing
- Missing swings produce no feedback
- No errors in Output

- [ ] **Step 4: Verify `max_hits` caps are respected**

Swing the bat through a dummy touching two segments — at most 2 should take damage. Swing the katana through multiple segments — at most 3. Punch — at most 1.

- [ ] **Step 5: Commit**

```
git add scripts/weapon_melee.gd
git commit -m "refactor: remove area_entered hit path; Area3D is now enable/disable gate only"
```

---

## Final State: `weapon_melee.gd`

For reference, the complete file after all tasks:

```gdscript
# scripts/weapon_melee.gd
# Melee weapon base — per-frame blade-tip sweep raycast hit detection with timer-driven activation window.
# Subclasses override _configure() for stats, _apply_hit() for damage behaviour,
# _create_sweep_markers() for BladeTip/BladeBase positions.
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
var hit_shape_rotation: Vector3 = Vector3.ZERO
var hit_shape_scale: Vector3 = Vector3.ONE

var _cooldown_timer := 0.0
var _hit_area: Area3D = null
var _hit_segments: Array[VoxelSegment] = []
var _own_segment_set: Dictionary = {}
var _hitbox_active := false
var _blade_tip: Marker3D = null
var _blade_base: Marker3D = null
var _prev_tip_pos := Vector3.INF
var _prev_base_pos := Vector3.INF

@onready var audio: AudioStreamPlayer3D = $AudioStreamPlayer3D

func _ready() -> void:
	super()
	_create_hitarea()
	_create_sweep_markers()

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
		col.disabled = true
		_hit_area.add_child(col)
	add_child(_hit_area)

func _create_sweep_markers() -> void:
	_blade_tip = Marker3D.new()
	_blade_tip.name = "BladeTip"
	add_child(_blade_tip)
	_blade_base = Marker3D.new()
	_blade_base.name = "BladeBase"
	add_child(_blade_base)

func _enable_hitbox() -> void:
	for child in _hit_area.get_children():
		if child is CollisionShape3D:
			child.disabled = false
	_hitbox_active = true
	_prev_tip_pos = Vector3.INF
	_prev_base_pos = Vector3.INF

func _disable_hitbox() -> void:
	for child in _hit_area.get_children():
		if child is CollisionShape3D:
			child.disabled = true
	_hitbox_active = false
	_prev_tip_pos = Vector3.INF
	_prev_base_pos = Vector3.INF

func _physics_process(delta: float) -> void:
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	if Input.is_action_just_pressed("attack") and _cooldown_timer <= 0.0:
		_attack()

	if _hitbox_active:
		var tip_now := _blade_tip.global_position
		var base_now := _blade_base.global_position
		if _prev_tip_pos != Vector3.INF:
			_sweep_check(_prev_tip_pos, tip_now)
			_sweep_check(_prev_base_pos, base_now)
		_prev_tip_pos = tip_now
		_prev_base_pos = base_now

func _sweep_check(from: Vector3, to: Vector3) -> void:
	if _hit_segments.size() >= max_hits:
		return
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 2)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result := space.intersect_ray(query)
	if not result or not result.collider is Area3D:
		return
	if not result.collider.has_meta("voxel_segment"):
		return
	var seg: VoxelSegment = result.collider.get_meta("voxel_segment")
	if _own_segment_set.is_empty() and not _player.segments.is_empty():
		for s: VoxelSegment in _player.segments.values():
			_own_segment_set[s] = true
	if seg in _own_segment_set:
		return
	if seg in _hit_segments:
		return
	_hit_segments.append(seg)
	var local_hit := seg.to_local(result.position)
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
		return
	_enable_hitbox()
	await get_tree().create_timer(hit_window_duration).timeout
	if is_instance_valid(self):
		_disable_hitbox()

func _apply_hit(seg: VoxelSegment, local_hit: Vector3) -> void:
	DamageManager.process_hit(seg, local_hit, voxel_radius, damage)
```
