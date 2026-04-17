# Death + Respawn Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the player dies, the voxel body ragdolls, weapons drop as pickups, and after 5 seconds the player respawns at a random spawn point with a freshly rebuilt body and fists only.

**Architecture:** `Player._die()` triggers the existing ragdoll (`_limb_system.die()`), drops weapons, disables the collision shape, and starts a 5-second timer. `Player._respawn()` cleans up the ragdoll pieces, teleports to a random `Marker3D` in the `"spawn_point"` group, frees the old voxel body, and calls `_build_voxel_body()` to rebuild from scratch. Spawn points are four `Marker3D` nodes added to `test_scene.tscn`.

**Tech Stack:** Godot 4.3+, GDScript

---

## Files

| File | Change |
|---|---|
| `scripts/player.gd` | Add `_attachments` tracking, rewrite `_die()`, add `_respawn()` |
| `scenes/test_scene.tscn` | Append four `Marker3D` spawn point nodes |

---

## Task 1: Track BoneAttachment3D nodes in Player

`_respawn()` needs to free the BoneAttachment3D nodes created by `_build_voxel_body()`. Player currently doesn't track them (unlike Brawler). This task adds that tracking.

**Files:**
- Modify: `scripts/player.gd`

- [ ] **Step 1: Add `_attachments` array to Player's instance variables**

In `scripts/player.gd`, find the instance variable block (around line 47):

```gdscript
var segments: Dictionary = {}
var _is_dead: bool = false
var _legs_lost: int = 0
var _weapon_anchor: Node3D = null
var _limb_system: LimbSystem = null
var _health_system: HealthSystem = null
```

Replace with:

```gdscript
var segments: Dictionary = {}
var _is_dead: bool = false
var _legs_lost: int = 0
var _weapon_anchor: Node3D = null
var _limb_system: LimbSystem = null
var _health_system: HealthSystem = null
var _attachments: Array = []
```

- [ ] **Step 2: Append each BoneAttachment3D to `_attachments` inside `_build_voxel_body()`**

In `scripts/player.gd`, inside `_build_voxel_body()`, find:

```gdscript
		var attach := BoneAttachment3D.new()
		attach.bone_name = bone_name
		attach.bone_idx = bone_idx
		attach.rotation_degrees = Vector3(cfg[3], 0.0, cfg[4])
		skeleton.add_child(attach)
```

Replace with:

```gdscript
		var attach := BoneAttachment3D.new()
		attach.bone_name = bone_name
		attach.bone_idx = bone_idx
		attach.rotation_degrees = Vector3(cfg[3], 0.0, cfg[4])
		skeleton.add_child(attach)
		_attachments.append(attach)
```

- [ ] **Step 3: Run the game — verify the body still builds correctly**

Launch `scenes/test_scene.tscn` in Godot. The player should appear with the full voxel body and all weapons working as before. Nothing should have changed visually.

- [ ] **Step 4: Commit**

```bash
git add scripts/player.gd
git commit -m "feat: track BoneAttachment3D nodes in Player._attachments"
```

---

## Task 2: Add spawn points to test_scene.tscn

Four `Marker3D` nodes placed at the corners of the main arena room, each in the `"spawn_point"` group. The respawn logic reads `global_position` at runtime, so positions can be tuned in the editor without any code change.

**Files:**
- Modify: `scenes/test_scene.tscn`

- [ ] **Step 1: Append spawn point nodes to the end of `scenes/test_scene.tscn`**

Open `scenes/test_scene.tscn`. At the very end of the file (after the last `[node ...]` block), append:

```
[node name="SpawnPoint1" type="Marker3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 5, 0, 5)
groups = ["spawn_point"]

[node name="SpawnPoint2" type="Marker3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -5, 0, 5)
groups = ["spawn_point"]

[node name="SpawnPoint3" type="Marker3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 5, 0, -5)
groups = ["spawn_point"]

[node name="SpawnPoint4" type="Marker3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -5, 0, -5)
groups = ["spawn_point"]
```

- [ ] **Step 2: Reload the scene in Godot and verify the spawn points appear**

Open `scenes/test_scene.tscn` in the Godot editor. In the Scene dock, four `SpawnPoint` nodes should appear as children of the root. Select one and confirm its group is `"spawn_point"` in the Node → Groups panel.

- [ ] **Step 3: Commit**

```bash
git add scenes/test_scene.tscn
git commit -m "feat: add four Marker3D spawn points to test_scene"
```

---

## Task 3: Rewrite `Player._die()` and add `Player._respawn()`

**Files:**
- Modify: `scripts/player.gd`

- [ ] **Step 1: Replace `_die()` with the new implementation**

In `scripts/player.gd`, find the existing `_die()`:

```gdscript
func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_is_attacking = false
	if _limb_system != null:
		_limb_system.die()
	print("Player died! (TODO: death/respawn)")
```

Replace with:

```gdscript
func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_is_attacking = false
	_drop_weapon(SLOT_MELEE)
	_drop_weapon(SLOT_RANGED)
	$CollisionShape3D.disabled = true
	if _limb_system != null:
		_limb_system.die()
	get_tree().create_timer(5.0).timeout.connect(_respawn)
```

- [ ] **Step 2: Add `_respawn()` at the end of `scripts/player.gd`**

Append after `_die()`:

```gdscript
func _respawn() -> void:
	# 1. Clean up ragdoll pieces
	for node in get_tree().get_nodes_in_group("detached_limb"):
		node.queue_free()

	# 2. Teleport to a random spawn point
	var spawn_points := get_tree().get_nodes_in_group("spawn_point")
	if spawn_points.size() > 0:
		var sp := spawn_points[randi() % spawn_points.size()] as Node3D
		global_position = sp.global_position

	# 3. Re-enable collision
	$CollisionShape3D.disabled = false

	# 4. Reparent weapon_holder back to camera before the body is torn down
	weapon_holder.reparent(camera, false)
	weapon_holder.transform = Transform3D.IDENTITY

	# 5. Free all inventory weapons (including fists)
	for i in range(_inventory.size()):
		var w := _inventory[i]
		if w == null:
			continue
		if w is WeaponRanged:
			(w as WeaponRanged).ammo_changed.disconnect(_on_ammo_changed)
		w.queue_free()
		_inventory[i] = null
	_current_weapon = null

	# 6. Tear down old body systems
	if _limb_system != null:
		_limb_system.queue_free()
		_limb_system = null
	if _health_system != null:
		_health_system.queue_free()
		_health_system = null
	for attach in _attachments:
		if is_instance_valid(attach):
			attach.queue_free()
	_attachments.clear()

	# 7. Wait one frame for queue_frees to propagate
	await get_tree().process_frame

	# 8. Reset state
	_legs_lost = 0
	_is_attacking = false
	_weapon_anchor = null
	_is_dead = false

	# 9. Re-create fists
	var fists_instance := WeaponRegistry.get_scene(&"fists").instantiate() as WeaponBase
	fists_instance._player = self
	fists_instance.weapon_id = &"fists"
	weapon_holder.add_child(fists_instance)
	_inventory[SLOT_FISTS] = fists_instance

	# 10. Rebuild the voxel body and equip fists
	_build_voxel_body()
	_equip_slot(SLOT_FISTS)
```

- [ ] **Step 3: Run the game and test death**

Launch `scenes/test_scene.tscn`. Let the brawler kill the player (or use `take_damage` in the debugger). Verify:

- Weapons in melee/ranged slots drop as world pickups at the player's position
- The body collapses into a ragdoll (segments fall with gravity)
- The player's CharacterBody3D goes visually empty (segments are in RigidBody3D nodes)

- [ ] **Step 4: Test the respawn**

Wait 5 seconds after death. Verify:

- Ragdoll pieces disappear
- Player teleports to one of the four spawn point positions
- Voxel body is fully rebuilt (all 14 segments visible)
- Player is holding fists, no melee or ranged slot
- HP bar in HUD resets to full (green)
- Body silhouette in HUD resets to full (all green)
- Player can move and attack again

- [ ] **Step 5: Test dying twice in a row**

Die once, wait for respawn, then die again. Verify the second respawn works cleanly — no leftover nodes, no errors in the Godot output panel.

- [ ] **Step 6: Commit**

```bash
git add scripts/player.gd
git commit -m "feat: player death ragdoll, weapon drop, and 5s respawn"
```
