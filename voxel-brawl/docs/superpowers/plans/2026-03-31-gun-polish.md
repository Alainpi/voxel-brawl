# Gun Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add barrel-origin raycasting, bullet tracers, shotgun scatter fix, and per-weapon screen shake + crosshair kick to make guns feel satisfying to shoot.

**Architecture:** `BulletTracer` is a self-contained node spawned per shot. `WeaponRanged` gains a `$Muzzle` Node3D reference used as ray origin and tracer spawn point. Recoil params are exported vars on each weapon, passed through `Player.trigger_hit_shake()` and `trigger_crosshair_recoil()` to `Crosshair`. Shotgun gets per-pellet spread applied to both the wall-check ray AND the voxel targeting ray.

**Tech Stack:** Godot 4 GDScript, StandardMaterial3D + BoxMesh (tracer), Tween (tracer fade + crosshair decay), PhysicsRayQueryParameters3D.

---

## File Map

| File | Action | What changes |
|------|--------|-------------|
| `scripts/crosshair.gd` | Modify | `recoil()` accepts `kick` + `recovery` params; `_decay_rate` becomes instance var |
| `scripts/hud.gd` | Modify | `recoil()` passes `kick` + `recovery` through to crosshair |
| `scripts/player.gd` | Modify | Camera shake implementation; `trigger_hit_shake(strength)` and `trigger_crosshair_recoil(kick, recovery)` updated signatures |
| `scripts/bullet_tracer.gd` | **Create** | Self-contained tracer node with static `spawn()` factory |
| `scripts/weapon_ranged.gd` | Modify | `$Muzzle` onready, recoil exported vars, `_apply_recoil()`, `_fire_ray()` spread_angle param, barrel-origin ray, tracer spawn, updated `_play_shot_effects()` |
| `scripts/weapon_shotgun.gd` | Modify | Spread exported vars, scatter fix in `_fire()`, recoil vars in `_configure()` |
| `scripts/weapon_revolver.gd` | Modify | Recoil vars + tracer color in `_configure()` |
| `scenes/player.tscn` | Modify | Add `Muzzle` Node3D to Revolver + Shotgun; add `MuzzleFlash` GPUParticles3D to Shotgun |

---

## Task 1: Parameterize crosshair recoil

**Files:**
- Modify: `scripts/crosshair.gd`
- Modify: `scripts/hud.gd`

- [ ] **Step 1: Update `crosshair.gd` — add `_decay_rate` instance var and parameterize `recoil()`**

Replace lines 11–12 and 14 and 16–21 and 38–40 in `scripts/crosshair.gd` with the full updated file:

```gdscript
# scripts/crosshair.gd
# Full-screen Control that draws a dynamic crosshair via _draw().
extends Control

const GAP     := 8.0    # Distance from center to inner end of each arm
const LENGTH  := 12.0   # Length of each arm
const THICK   := 2.0    # Line thickness
const COLOR   := Color(1.0, 1.0, 1.0, 0.85)
const DOT_R   := 1.5    # Center dot radius

const RECOIL_SPREAD := 16.0  # Default pixels added to gap on fire
const DECAY         := 14.0  # Default decay rate

var _spread := 0.0
var _decay_rate := DECAY

func _process(delta: float) -> void:
	if _spread > 0.05:
		_spread = lerpf(_spread, 0.0, _decay_rate * delta)
	elif _spread > 0.0:
		_spread = 0.0
	queue_redraw()  # Always redraw — crosshair must follow mouse every frame

func _draw() -> void:
	var c := get_local_mouse_position()
	var g := GAP + _spread

	# Top arm
	draw_line(c + Vector2(0, -g - LENGTH), c + Vector2(0, -g), COLOR, THICK, true)
	# Bottom arm
	draw_line(c + Vector2(0,  g),          c + Vector2(0,  g + LENGTH), COLOR, THICK, true)
	# Left arm
	draw_line(c + Vector2(-g - LENGTH, 0), c + Vector2(-g, 0), COLOR, THICK, true)
	# Right arm
	draw_line(c + Vector2(g, 0),           c + Vector2(g + LENGTH, 0), COLOR, THICK, true)
	# Center dot
	draw_circle(c, DOT_R, COLOR)

# kick: pixels added to gap. recovery: seconds to settle back to zero.
func recoil(kick: float = RECOIL_SPREAD, recovery: float = 0.188) -> void:
	_spread = maxf(_spread, kick)
	_decay_rate = 2.6 / maxf(recovery, 0.05)
	queue_redraw()
```

> **Note on the 2.6 / recovery formula:** With lerpf and DECAY=14, spread decays to ~5% in 0.188s. `2.6 / recovery` reproduces that timing for arbitrary recovery values. Examples: recovery=0.25 → decay≈10.4 (~0.25s settle), recovery=0.40 → decay≈6.5 (~0.40s settle).

- [ ] **Step 2: Update `hud.gd` — pass `kick` and `recovery` through to crosshair**

Replace `hud.gd` `recoil()` (line 20–21):
```gdscript
func recoil(kick: float = 16.0, recovery: float = 0.188) -> void:
	_crosshair.recoil(kick, recovery)
```

- [ ] **Step 3: Run the game, equip revolver, fire — verify crosshair still kicks and recovers (behaviour unchanged since defaults match old values)**

- [ ] **Step 4: Commit**
```bash
git add scripts/crosshair.gd scripts/hud.gd
git commit -m "feat: parameterize crosshair recoil — kick amount and recovery time per call"
```

---

## Task 2: Camera shake + updated player trigger signatures

**Files:**
- Modify: `scripts/player.gd:136–148` (physics process camera follow) and `scripts/player.gd:275–282` (trigger methods)

- [ ] **Step 1: Add `_shake_strength` instance var to `player.gd`**

After the existing `const` block (around line 19), add:
```gdscript
var _shake_strength := 0.0
```

- [ ] **Step 2: Apply shake offset in `_physics_process` after the camera follow lerp**

The current camera follow block (lines 145–148):
```gdscript
	# Camera follows player with slight lag
	camera_pivot.global_position = camera_pivot.global_position.lerp(
		global_position, CAM_FOLLOW_SPEED * delta
	)
```

Replace with:
```gdscript
	# Camera follows player with slight lag
	camera_pivot.global_position = camera_pivot.global_position.lerp(
		global_position, CAM_FOLLOW_SPEED * delta
	)

	# Screen shake — small random XZ offset that decays quickly
	if _shake_strength > 0.005:
		var shake_offset := Vector3(
			randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)
		) * _shake_strength * 0.12
		camera_pivot.global_position += shake_offset
		_shake_strength = lerpf(_shake_strength, 0.0, 18.0 * delta)
	else:
		_shake_strength = 0.0
```

- [ ] **Step 3: Update `trigger_hit_shake()` and `trigger_crosshair_recoil()` signatures**

Replace lines 275–282 in `player.gd`:
```gdscript
# Called by weapons on fire — short camera jolt. strength: 0.0–1.0 scale.
func trigger_hit_shake(strength: float = 0.2) -> void:
	_shake_strength = maxf(_shake_strength, strength)

func trigger_crosshair_recoil(kick: float = 12.0, recovery: float = 0.25) -> void:
	var hud := get_node_or_null("/root/test_scene/hud")
	if hud:
		hud.recoil(kick, recovery)
```

- [ ] **Step 4: Run the game, fire revolver — verify a small camera jolt appears. Existing melee hits still work (callers pass no args, get defaults).**

- [ ] **Step 5: Commit**
```bash
git add scripts/player.gd
git commit -m "feat: implement camera shake on fire, parameterize trigger_hit_shake/recoil signatures"
```

---

## Task 3: BulletTracer

**Files:**
- Create: `scripts/bullet_tracer.gd`

- [ ] **Step 1: Create `scripts/bullet_tracer.gd`**

```gdscript
# scripts/bullet_tracer.gd
# Self-contained streak tracer. Call BulletTracer.spawn() — node adds itself,
# fades out, and queue_frees. No pooling needed (short-lived, low frequency).
class_name BulletTracer
extends Node3D

const TRACER_THICKNESS := 0.03  # World-space diameter of the streak
const TRACER_FADE_TIME  := 0.12  # Seconds from full opacity to zero

var _mat := StandardMaterial3D.new()

func _ready() -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	# X=1.0 unit so scaling global_transform.basis.x by distance stretches it correctly.
	box.size = Vector3(1.0, TRACER_THICKNESS, TRACER_THICKNESS)
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.flags_transparent = true
	_mat.albedo_color = Color.WHITE  # overridden in spawn()
	mesh_instance.mesh = box
	mesh_instance.material_override = _mat
	add_child(mesh_instance)

# Spawns a tracer from `from` to `to` with the given color.
# `parent` should be get_tree().root so the tracer outlives the weapon.
static func spawn(from: Vector3, to: Vector3, color: Color, parent: Node) -> void:
	if from.is_equal_approx(to):
		return
	var dir := (to - from).normalized()
	var dist := from.distance_to(to)
	var mid := (from + to) * 0.5

	# Build a basis where the local X axis points along dir.
	var up := Vector3.UP if abs(dir.y) < 0.9 else Vector3.RIGHT
	var side := dir.cross(up).normalized()
	up = side.cross(dir).normalized()
	# Scale the X column by dist so the unit BoxMesh spans exactly from→to.
	var basis := Basis(dir * dist, up, side)

	var tracer := BulletTracer.new()
	parent.add_child(tracer)  # triggers _ready(), which creates _mat and mesh
	tracer.global_transform = Transform3D(basis, mid)
	tracer._mat.albedo_color = color

	var end_color := Color(color.r, color.g, color.b, 0.0)
	var tween := tracer.create_tween()
	tween.tween_property(tracer._mat, "albedo_color", end_color, TRACER_FADE_TIME)
	tween.tween_callback(tracer.queue_free)
```

- [ ] **Step 2: Open Godot, go to Script → Run (or use MCP editor tool) and verify `BulletTracer` class is visible with no parse errors.**

- [ ] **Step 3: Commit**
```bash
git add scripts/bullet_tracer.gd
git commit -m "feat: add BulletTracer — stretched BoxMesh streak with tween fade"
```

---

## Task 4: Update WeaponRanged — muzzle origin, recoil vars, tracer, spread_angle param

**Files:**
- Modify: `scripts/weapon_ranged.gd`

- [ ] **Step 1: Add `muzzle` onready, `tracer_color` export, and recoil exported vars**

Add after the existing var block (after line 19 `var _reload_timer := 0.0`):
```gdscript
@export var tracer_color := Color(1.0, 0.96, 0.63, 1.0)  # override in _configure()
@export var recoil_shake_strength := 0.2
@export var recoil_kick_amount    := 12.0
@export var recoil_recovery_time  := 0.25

@onready var muzzle: Node3D = $Muzzle
```

- [ ] **Step 2: Add `_apply_recoil()` method**

Add after the `_start_reload()` method at the end of the file:
```gdscript
func _apply_recoil() -> void:
	_player.trigger_hit_shake(recoil_shake_strength)
	_player.trigger_crosshair_recoil(recoil_kick_amount, recoil_recovery_time)
```

- [ ] **Step 3: Call `_apply_recoil()` in `_fire()` and remove old per-hit recoil calls**

Replace the entire `_fire()` method (lines 52–69):
```gdscript
func _fire() -> void:
	_ammo -= 1
	_cooldown = fire_rate
	ammo_changed.emit(_ammo, max_ammo)
	_player.play_attack_anim("shoot")
	_play_shot_effects()
	_apply_recoil()

	var mouse_world: Vector3 = _player.get_mouse_world_pos()
	if mouse_world == Vector3.ZERO:
		return
	var aim_flat := Vector3(
		mouse_world.x - _player.global_position.x,
		0.0,
		mouse_world.z - _player.global_position.z
	)
	if aim_flat.length_squared() < 0.001:
		return
	_fire_ray(aim_flat.normalized())
```

- [ ] **Step 4: Rewrite `_fire_ray()` — barrel origin, spread_angle param, tracer spawn, remove old recoil calls**

Replace the entire `_fire_ray()` method (lines 72–122):
```gdscript
# Fires a single ray from the muzzle.
# spread_angle: horizontal rotation in radians applied to the voxel ray (shotgun use).
func _fire_ray(aim_dir_h: Vector3, spread_angle: float = 0.0) -> void:
	var muzzle_pos: Vector3 = muzzle.global_position
	var space := get_world_3d().direct_space_state

	# Ray 1 — horizontal wall check from muzzle (layer 1 = static bodies only)
	var wall_params := PhysicsRayQueryParameters3D.create(
		muzzle_pos, muzzle_pos + aim_dir_h * RAY_LENGTH, 1
	)
	wall_params.collide_with_areas = false
	wall_params.collide_with_bodies = true
	wall_params.exclude = [_player.get_rid()]
	var wall_hit := space.intersect_ray(wall_params)

	# Ray 2 — camera ray for precise voxel targeting (layer 2 = voxel areas only)
	# spread_angle rotates it horizontally to match per-pellet spread direction.
	var cam_ray: Dictionary = _player.get_camera_ray()
	var cam_origin: Vector3 = cam_ray["origin"]
	var cam_dir: Vector3 = cam_ray["dir"]
	if spread_angle != 0.0:
		cam_dir = cam_dir.rotated(Vector3.UP, spread_angle)
	var voxel_params := PhysicsRayQueryParameters3D.create(
		cam_origin, cam_origin + cam_dir * RAY_LENGTH, 2
	)
	voxel_params.collide_with_areas = true
	voxel_params.collide_with_bodies = false
	var voxel_hit := space.intersect_ray(voxel_params)

	var wall_dist_h := INF
	if not wall_hit.is_empty():
		wall_dist_h = Vector2(
			wall_hit.position.x - muzzle_pos.x,
			wall_hit.position.z - muzzle_pos.z
		).length()

	var voxel_dist_h := INF
	if not voxel_hit.is_empty():
		voxel_dist_h = Vector2(
			voxel_hit.position.x - muzzle_pos.x,
			voxel_hit.position.z - muzzle_pos.z
		).length()

	if not wall_hit.is_empty() and wall_dist_h <= voxel_dist_h:
		BulletTracer.spawn(muzzle_pos, wall_hit.position, tracer_color, get_tree().root)
		_on_wall_hit(wall_hit.position, wall_hit.normal)
		return

	if voxel_hit.is_empty():
		BulletTracer.spawn(
			muzzle_pos, cam_origin + cam_dir * RAY_LENGTH, tracer_color, get_tree().root
		)
		return

	BulletTracer.spawn(muzzle_pos, voxel_hit.position, tracer_color, get_tree().root)

	var area := voxel_hit.collider as Area3D
	if area and area.has_meta("voxel_segment"):
		var seg: VoxelSegment = area.get_meta("voxel_segment")
		var dda_start := seg.to_local(voxel_hit.position - cam_dir * 0.1)
		var dda_dir := (seg.global_transform.affine_inverse().basis * cam_dir).normalized()
		var dda_result := seg.dda_raycast(dda_start, dda_dir)
		if dda_result.hit:
			var voxel_center := (Vector3(dda_result.voxel) + Vector3(0.5, 0.5, 0.5)) * VoxelSegment.VOXEL_SIZE
			_apply_hit(seg, voxel_center)
```

- [ ] **Step 5: Update `_play_shot_effects()` to use muzzle position**

Replace `_play_shot_effects()` (lines 132–138):
```gdscript
func _play_shot_effects() -> void:
	if audio_shot.stream:
		audio_shot.play()
	if muzzle_flash:
		muzzle_flash.global_position = muzzle.global_position
		muzzle_flash.restart()
```

- [ ] **Step 6: Verify the file has no `chest` variable remaining (should be zero matches)**
```bash
grep -n "chest" "scripts/weapon_ranged.gd"
```
Expected: no output.

- [ ] **Step 7: Commit**
```bash
git add scripts/weapon_ranged.gd
git commit -m "feat: barrel-origin rays, per-weapon recoil vars, bullet tracer spawn in WeaponRanged"
```

---

## Task 5: Add Muzzle nodes + Shotgun MuzzleFlash to player.tscn

**Files:**
- Modify: `scenes/player.tscn`

The tscn already has the `ParticleProcessMaterial_dqkch` and `QuadMesh_qhqgy` sub-resources used by Revolver's MuzzleFlash. Shotgun's new MuzzleFlash reuses them.

> **Muzzle positions are starting estimates.** Tune them visually in Godot's Remote panel while running (move the Muzzle node until it sits at the barrel tip). The revolver Muzzle matches the existing MuzzleFlash transform.

- [ ] **Step 1: Add `Muzzle` Node3D under Revolver in `scenes/player.tscn`**

Insert after the MuzzleFlash node block (after line 66 `draw_pass_1 = SubResource("QuadMesh_qhqgy")`):
```
[node name="Muzzle" type="Node3D" parent="CameraPivot/Camera3D/WeaponHolder/Revolver" unique_id=1234567890]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -1.12, 0.37, -4.30)
```

- [ ] **Step 2: Add `Muzzle` Node3D and `MuzzleFlash` GPUParticles3D under Shotgun**

Insert after the Shotgun AudioShot node (after line 103 `[node name="AudioShot" ...`):
```
[node name="Muzzle" type="Node3D" parent="CameraPivot/Camera3D/WeaponHolder/Shotgun" unique_id=1234567891]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2.5, -0.5)

[node name="MuzzleFlash" type="GPUParticles3D" parent="CameraPivot/Camera3D/WeaponHolder/Shotgun" unique_id=1234567892]
transform = Transform3D(0.5, 0, 0, 0, 0.5, 0, 0, 0, 0.5, 0, 2.5, -0.5)
emitting = false
lifetime = 0.1
one_shot = true
process_material = SubResource("ParticleProcessMaterial_dqkch")
draw_pass_1 = SubResource("QuadMesh_qhqgy")
```

- [ ] **Step 3: Run the game, equip revolver, fire — verify tracer originates from near the barrel (not player torso). Equip shotgun, fire — verify MuzzleFlash appears.**

- [ ] **Step 4: Tune Muzzle positions if needed**

In Godot editor, run the scene and use the Remote panel to select `Muzzle` under Revolver or Shotgun. Adjust the `position` property until the node sits at the barrel tip. Save the scene after adjusting.

- [ ] **Step 5: Commit**
```bash
git add scenes/player.tscn
git commit -m "feat: add Muzzle Node3D to Revolver + Shotgun, MuzzleFlash to Shotgun"
```

---

## Task 6: Fix shotgun scatter + set per-weapon values

**Files:**
- Modify: `scripts/weapon_shotgun.gd`

- [ ] **Step 1: Replace `weapon_shotgun.gd` with the full updated file**

```gdscript
# scripts/weapon_shotgun.gd
# Close-range spread weapon. Fires multiple pellets per shot — can hit multiple limbs.
class_name WeaponShotgun
extends WeaponRanged

const PELLET_COUNT := 6

@export var spread_near: float = 0.25          # half-angle radians at point-blank
@export var spread_far: float  = 0.08          # half-angle radians at max range
@export var spread_falloff_dist: float = 12.0  # distance (world units) where cone fully tightens

func _configure() -> void:
	weapon_type = WeaponType.RANGED
	damage = 12.0
	voxel_radius = 1.2
	fire_rate = 0.9
	max_ammo = 2
	reload_time = 2.0
	tracer_color = Color(1.0, 0.60, 0.0, 1.0)
	recoil_shake_strength = 0.60
	recoil_kick_amount = 28.0
	recoil_recovery_time = 0.40

func _fire() -> void:
	_ammo -= 1
	_cooldown = fire_rate
	ammo_changed.emit(_ammo, max_ammo)
	_player.play_attack_anim("shoot")
	_play_shot_effects()
	_apply_recoil()

	var mouse_world: Vector3 = _player.get_mouse_world_pos()
	if mouse_world == Vector3.ZERO:
		return
	var aim_flat := Vector3(
		mouse_world.x - _player.global_position.x,
		0.0,
		mouse_world.z - _player.global_position.z
	)
	if aim_flat.length_squared() < 0.001:
		return
	var aim_dir_h := aim_flat.normalized()

	# Each pellet gets an independent spread angle applied to both rays.
	# spread_near is used for all pellets in v1; distance-based lerp to spread_far
	# can be tuned post-playtesting once the spread_falloff_dist feel is confirmed.
	for i in range(PELLET_COUNT):
		var angle := randf_range(-spread_near, spread_near)
		var spread_dir := aim_dir_h.rotated(Vector3.UP, angle)
		_fire_ray(spread_dir, angle)
```

- [ ] **Step 2: Run the game, equip shotgun, fire at a dummy at close range — verify 6 distinct orange tracers fan out from the barrel in a visible cone. Fire at a wall — verify pellets hit different wall positions instead of all clustering at the same spot.**

- [ ] **Step 3: Commit**
```bash
git add scripts/weapon_shotgun.gd
git commit -m "fix: shotgun voxel ray now spreads per-pellet; add recoil + tracer color"
```

---

## Task 7: Wire revolver recoil + tracer color

**Files:**
- Modify: `scripts/weapon_revolver.gd`

- [ ] **Step 1: Replace `weapon_revolver.gd` with the full updated file**

```gdscript
# scripts/weapon_revolver.gd
# Slow, precise. High single-shot damage. 6 rounds, capable of headshot dismemberment.
class_name WeaponRevolver
extends WeaponRanged

func _configure() -> void:
	weapon_type = WeaponType.RANGED
	damage = 35.0
	voxel_radius = 1.5
	fire_rate = 0.55
	max_ammo = 6
	reload_time = 1.5
	tracer_color = Color(1.0, 0.96, 0.63, 1.0)
	recoil_shake_strength = 0.35
	recoil_kick_amount = 18.0
	recoil_recovery_time = 0.25
```

- [ ] **Step 2: Run the game, equip revolver, fire — verify yellow-white tracer, crosshair kick, and camera jolt. Fire shotgun — verify wider orange tracer cone, stronger kick, slower crosshair recovery.**

- [ ] **Step 3: Commit**
```bash
git add scripts/weapon_revolver.gd
git commit -m "feat: revolver recoil vars and tracer color in _configure()"
```

---

## Tuning Reference

After implementation, adjust these if the feel is off:

| Feel | Variable | Location |
|------|----------|----------|
| Tracers too thick / thin | `TRACER_THICKNESS` | `bullet_tracer.gd:6` |
| Tracers linger too long | `TRACER_FADE_TIME` | `bullet_tracer.gd:7` |
| Camera shake too strong | `recoil_shake_strength` | weapon `_configure()` |
| Camera shake duration | `18.0` (decay constant) | `player.gd` in shake block |
| Crosshair kick distance | `recoil_kick_amount` | weapon `_configure()` |
| Crosshair recovery speed | `recoil_recovery_time` | weapon `_configure()` |
| Shotgun cone too wide / tight | `spread_near` | `weapon_shotgun.gd` exported var |
| Muzzle flash position | `Muzzle` node position | `scenes/player.tscn` (tune in Remote panel) |
