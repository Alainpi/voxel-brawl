# Weapon Pickup System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decouple weapons from player.tscn into their own scenes, add a WeaponRegistry autoload, give the player a 3-slot inventory (fists/melee/ranged), and implement world pickups with cursor-highlight + F-to-grab + G-to-drop.

**Architecture:** WeaponRegistry autoload maps string IDs to PackedScenes and metadata. Player holds a 3-slot inventory array; weapons are instanced at runtime into WeaponHolder. WeaponPickup is a StaticBody3D on physics layer 3 that the player detects via a per-frame camera raycast.

**Tech Stack:** Godot 4.3, GDScript, Jolt physics. No external dependencies.

---

## File Map

| Action | Path |
|--------|------|
| Create | `scripts/weapon_registry.gd` |
| Create | `scripts/weapon_pickup.gd` |
| Create | `scenes/weapons/fists.tscn` |
| Create | `scenes/weapons/bat.tscn` |
| Create | `scenes/weapons/katana.tscn` |
| Create | `scenes/weapons/revolver.tscn` |
| Create | `scenes/weapons/shotgun.tscn` |
| Create | `scenes/weapons/weapon_pickup.tscn` |
| Create | `assets/materials/pickup_highlight.tres` |
| Modify | `scripts/weapon_base.gd` |
| Modify | `scripts/player.gd` |
| Modify | `scenes/player.tscn` |
| Modify | `hud.tscn` |
| Modify | `scripts/hud.gd` |
| Modify | `project.godot` |

---

## Task 1: Project config — input actions + physics layer

**Files:**
- Modify: `project.godot`

- [ ] **Step 1: Add `pickup_weapon` (F) and `drop_weapon` (G) input actions and layer 3 name**

In `project.godot`, locate the `[input]` section. Add these entries. Also remove `switch_weapon_4` and `switch_weapon_5` (no longer used). Add layer 3 name in `[layer_names]`.

Replace this block:
```
switch_weapon_4={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":52,"key_label":0,"unicode":52,"location":0,"echo":false,"script":null)
]
}
switch_weapon_5={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":53,"key_label":0,"unicode":53,"location":0,"echo":false,"script":null)
]
}

[layer_names]

3d_physics/layer_1="world"
3d_physics/layer_2="voxel_segments"
```

With:
```
pickup_weapon={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":70,"key_label":0,"unicode":70,"location":0,"echo":false,"script":null)
]
}
drop_weapon={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":71,"key_label":0,"unicode":71,"location":0,"echo":false,"script":null)
]
}

[layer_names]

3d_physics/layer_1="world"
3d_physics/layer_2="voxel_segments"
3d_physics/layer_3="weapon_pickups"
```

- [ ] **Step 2: Commit**

```bash
git add project.godot
git commit -m "feat: add pickup_weapon/drop_weapon input actions, weapon_pickups physics layer"
```

---

## Task 2: Weapon scenes

**Files:**
- Create: `scenes/weapons/fists.tscn`
- Create: `scenes/weapons/bat.tscn`
- Create: `scenes/weapons/katana.tscn`
- Create: `scenes/weapons/revolver.tscn`
- Create: `scenes/weapons/shotgun.tscn`

These scenes extract the weapon nodes from `player.tscn`'s WeaponHolder. All transforms, meshes, and child nodes are preserved exactly. Godot will assign UIDs when it imports the files.

- [ ] **Step 1: Create `scenes/weapons/fists.tscn`**

```
[gd_scene format=3]

[ext_resource type="Script" uid="uid://clkorr8nx3hjc" path="res://scripts/weapon_fists.gd" id="1_fists"]

[node name="Fists" type="Node3D"]
script = ExtResource("1_fists")

[node name="AudioStreamPlayer3D" type="AudioStreamPlayer3D" parent="."]
```

- [ ] **Step 2: Create `scenes/weapons/bat.tscn`**

```
[gd_scene format=3]

[ext_resource type="Script" uid="uid://lmskr730xnbd" path="res://scripts/weapon_bat.gd" id="1_bat"]
[ext_resource type="ArrayMesh" uid="uid://b8wf2l20ep17i" path="res://assets/models/Weapons/Bat.obj" id="2_bat"]

[node name="Bat" type="Node3D"]
transform = Transform3D(-2, 0, -1.7484555e-07, 0, 2, 0, 1.7484555e-07, 0, -2, -1, -0.2, 1)
script = ExtResource("1_bat")

[node name="MeshInstance3D" type="MeshInstance3D" parent="."]
transform = Transform3D(0.2, 0, 0, 0, -8.742278e-09, 0.2, 0, -0.2, -8.742278e-09, -0.3, 0.4, 0.08)
mesh = ExtResource("2_bat")

[node name="AudioStreamPlayer3D" type="AudioStreamPlayer3D" parent="."]
```

- [ ] **Step 3: Create `scenes/weapons/katana.tscn`**

```
[gd_scene format=3]

[ext_resource type="Script" uid="uid://dwse7y3f3gwbr" path="res://scripts/weapon_katana.gd" id="1_katana"]
[ext_resource type="ArrayMesh" uid="uid://b6g60nh4cdtf8" path="res://assets/models/Weapons/Katana.obj" id="2_katana"]

[node name="Katana" type="Node3D"]
transform = Transform3D(2, -1.7484555e-07, -1.7484555e-07, -1.7484555e-07, -2, 0, -1.7484555e-07, 1.5285484e-14, -2, 0.45, 1.05, 1)
script = ExtResource("1_katana")

[node name="MeshInstance3D" type="MeshInstance3D" parent="."]
transform = Transform3D(0.2, 0, 0, 0, 0.2, 0, 0, 0, 0.2, -1.05, 0.15, -0.6)
mesh = ExtResource("2_katana")

[node name="AudioStreamPlayer3D" type="AudioStreamPlayer3D" parent="."]
```

- [ ] **Step 4: Create `scenes/weapons/revolver.tscn`**

```
[gd_scene format=3]

[ext_resource type="Script" uid="uid://cjg0e028qa28w" path="res://scripts/weapon_revolver.gd" id="1_rev"]
[ext_resource type="ArrayMesh" uid="uid://dgvoqqf33nkms" path="res://assets/models/Weapons/Revolver.obj" id="2_rev"]

[sub_resource type="ParticleProcessMaterial" id="PPM_rev"]
spread = 180.0
initial_velocity_min = 2.0
initial_velocity_max = 5.0
gravity = Vector3(0, 0, 0)
linear_accel_min = 1.9999977
linear_accel_max = 4.9999976
color = Color(1, 1, 0, 1)

[sub_resource type="StandardMaterial3D" id="SMat_rev"]
albedo_color = Color(1, 1, 0, 1)
emission_enabled = true
emission = Color(1, 0.8784314, 0, 1)
emission_energy_multiplier = 3.04

[sub_resource type="QuadMesh" id="QMesh_rev"]
material = SubResource("SMat_rev")

[node name="Revolver" type="Node3D"]
transform = Transform3D(2, 0, 0, 0, 2, 0, 0, 0, 2, 0.5, -2, -1.5)
script = ExtResource("1_rev")

[node name="AudioShot" type="AudioStreamPlayer3D" parent="."]

[node name="MuzzleFlash" type="GPUParticles3D" parent="."]
transform = Transform3D(0.5, 5.5879354e-09, 0, 0, 0.5000002, 0, 0, 0, 0.5000002, -1.1211715, 0.37002587, -4.3010073)
emitting = false
lifetime = 0.1
one_shot = true
process_material = SubResource("PPM_rev")
draw_pass_1 = SubResource("QMesh_rev")

[node name="Muzzle" type="Node3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2.5, 0)

[node name="MeshInstance3D" type="MeshInstance3D" parent="."]
transform = Transform3D(-8.742278e-09, 4.3711395e-09, -0.1, -0.1, 4.371139e-09, 8.742278e-09, 4.3711395e-09, 0.1, 4.371139e-09, -0.2, 1.7, 0)
mesh = ExtResource("2_rev")
```

- [ ] **Step 5: Create `scenes/weapons/shotgun.tscn`**

```
[gd_scene format=3]

[ext_resource type="Script" uid="uid://d0k5d1j66nlsg" path="res://scripts/weapon_shotgun.gd" id="1_sg"]
[ext_resource type="ArrayMesh" uid="uid://myxw77h63uyf" path="res://assets/models/Weapons/Shotgun.obj" id="2_sg"]

[sub_resource type="ParticleProcessMaterial" id="PPM_sg"]
spread = 180.0
initial_velocity_min = 2.0
initial_velocity_max = 5.0
gravity = Vector3(0, 0, 0)
linear_accel_min = 1.9999977
linear_accel_max = 4.9999976
color = Color(1, 1, 0, 1)

[sub_resource type="StandardMaterial3D" id="SMat_sg"]
albedo_color = Color(1, 1, 0, 1)
emission_enabled = true
emission = Color(1, 0.8784314, 0, 1)
emission_energy_multiplier = 3.04

[sub_resource type="QuadMesh" id="QMesh_sg"]
material = SubResource("SMat_sg")

[node name="Shotgun" type="Node3D"]
transform = Transform3D(2, 0, 0, 0, 3, 0, 0, 0, 2, 0.5, -3.3, -1.5)
script = ExtResource("1_sg")

[node name="MeshInstance3D" type="MeshInstance3D" parent="."]
transform = Transform3D(1.9106854e-16, 4.371139e-09, 0.1, 0.1, -4.371139e-09, 0, 4.371139e-09, 0.1, -4.371139e-09, -0.15, 1.8, -0.35)
mesh = ExtResource("2_sg")

[node name="AudioShot" type="AudioStreamPlayer3D" parent="."]

[node name="Muzzle" type="Node3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 4.5, 0)

[node name="MuzzleFlash" type="GPUParticles3D" parent="."]
transform = Transform3D(0.5, 0, 0, 0, 0.5, 0, 0, 0, 0.5, 0, 2.5, -0.5)
emitting = false
lifetime = 0.1
one_shot = true
process_material = SubResource("PPM_sg")
draw_pass_1 = SubResource("QMesh_sg")
```

- [ ] **Step 6: Open Godot, let it import all 5 new scenes. Verify no errors in the Output panel.**

Expected: 5 scene files imported, no errors. Do not run the game yet.

- [ ] **Step 7: Commit**

```bash
git add scenes/weapons/
git commit -m "feat: extract weapon nodes into standalone scenes"
```

---

## Task 3: WeaponRegistry autoload

**Files:**
- Create: `scripts/weapon_registry.gd`
- Modify: `project.godot`

- [ ] **Step 1: Create `scripts/weapon_registry.gd`**

```gdscript
# scripts/weapon_registry.gd
# Autoload singleton. Single source of truth for all weapon metadata.
# Registered as "WeaponRegistry" in project settings.
extends Node

enum Slot { FISTS = 0, MELEE = 1, RANGED = 2 }

var _data: Dictionary = {
	&"fists": {
		"scene": preload("res://scenes/weapons/fists.tscn"),
		"mesh": null,
		"display_name": "Fists",
		"slot": Slot.FISTS,
		"pickup_rotation": Vector3.ZERO,
	},
	&"bat": {
		"scene": preload("res://scenes/weapons/bat.tscn"),
		"mesh": preload("res://assets/models/Weapons/Bat.obj"),
		"display_name": "Bat",
		"slot": Slot.MELEE,
		"pickup_rotation": Vector3(90, 0, 0),
	},
	&"katana": {
		"scene": preload("res://scenes/weapons/katana.tscn"),
		"mesh": preload("res://assets/models/Weapons/Katana.obj"),
		"display_name": "Katana",
		"slot": Slot.MELEE,
		"pickup_rotation": Vector3(90, 0, 0),
	},
	&"revolver": {
		"scene": preload("res://scenes/weapons/revolver.tscn"),
		"mesh": preload("res://assets/models/Weapons/Revolver.obj"),
		"display_name": "Revolver",
		"slot": Slot.RANGED,
		"pickup_rotation": Vector3(90, 0, 0),
	},
	&"shotgun": {
		"scene": preload("res://scenes/weapons/shotgun.tscn"),
		"mesh": preload("res://assets/models/Weapons/Shotgun.obj"),
		"display_name": "Shotgun",
		"slot": Slot.RANGED,
		"pickup_rotation": Vector3(90, 0, 0),
	},
}

func get_scene(id: StringName) -> PackedScene:
	return _data[id]["scene"]

func get_mesh(id: StringName):  # ArrayMesh or null
	return _data[id]["mesh"]

func get_display_name(id: StringName) -> String:
	return _data[id]["display_name"]

func get_slot(id: StringName) -> Slot:
	return _data[id]["slot"]

func get_pickup_rotation(id: StringName) -> Vector3:
	return _data[id]["pickup_rotation"]

func has(id: StringName) -> bool:
	return _data.has(id)
```

- [ ] **Step 2: Register as autoload in `project.godot`**

Add to `project.godot` under the `[autoload]` section (create the section if it doesn't exist, right before `[input]`):

```
[autoload]

WeaponRegistry="*res://scripts/weapon_registry.gd"
```

The `*` prefix tells Godot this is a Node-based autoload (not just a script).

- [ ] **Step 3: Open Godot and run the scene. Verify in Output that no errors appear about WeaponRegistry.**

Expected: scene runs normally, no errors. WeaponRegistry is accessible as a singleton.

- [ ] **Step 4: Commit**

```bash
git add scripts/weapon_registry.gd project.godot
git commit -m "feat: add WeaponRegistry autoload with 5 weapons"
```

---

## Task 4: WeaponBase — add weapon_id, remove fragile _player path

**Files:**
- Modify: `scripts/weapon_base.gd`

- [ ] **Step 1: Update `scripts/weapon_base.gd`**

Replace the entire file with:

```gdscript
# scripts/weapon_base.gd
# Base class for all weapons. Handles player reference and the _configure() hook.
# Subclasses set their stats by overriding _configure(), which runs before _ready() completes.
class_name WeaponBase
extends Node3D

var _player  # duck-typed: Player for player weapons, Brawler for NPC weapons
var weapon_id: StringName = &""  # set by Player.give_weapon() after instantiation

enum WeaponType { BLUNT, SHARP, RANGED }
var weapon_type: WeaponType = WeaponType.BLUNT

func _ready() -> void:
	_configure()
	# _player must be set externally via weapon._player = self after instantiation.
	# Do not fall back to get_node() — the weapon may be instanced into any holder.

# Override in each concrete weapon class to set stats.
func _configure() -> void:
	pass
```

- [ ] **Step 2: Run the scene. Verify no new errors from weapon scripts.**

Expected: scene runs, player starts with no weapon visible (we haven't wired the inventory yet — that's Task 7). No null-reference errors in Output from WeaponBase.

- [ ] **Step 3: Commit**

```bash
git add scripts/weapon_base.gd
git commit -m "feat: add weapon_id to WeaponBase, remove fragile get_node path for _player"
```

---

## Task 5: Pickup highlight material

**Files:**
- Create: `assets/materials/pickup_highlight.tres`

- [ ] **Step 1: Create the `assets/materials/` directory and write `pickup_highlight.tres`**

```
[gd_resource type="StandardMaterial3D" format=3]

[resource]
albedo_color = Color(1, 1, 1, 1)
emission_enabled = true
emission = Color(0.9, 0.85, 0.1, 1)
emission_energy_multiplier = 2.5
```

This creates a yellow-gold emissive overlay. When applied as `material_overlay` on a MeshInstance3D it tints the mesh without replacing its material.

- [ ] **Step 2: Open Godot, let it import the .tres. Verify no import errors.**

- [ ] **Step 3: Commit**

```bash
git add assets/materials/pickup_highlight.tres
git commit -m "feat: add pickup highlight emissive material"
```

---

## Task 6: WeaponPickup scene + script

**Files:**
- Create: `scripts/weapon_pickup.gd`
- Create: `scenes/weapons/weapon_pickup.tscn`

- [ ] **Step 1: Create `scripts/weapon_pickup.gd`**

```gdscript
# scripts/weapon_pickup.gd
# A weapon lying in the world. Player highlights it by looking at it (raycast)
# and presses F to collect it. weapon_id must be set before _ready() runs.
class_name WeaponPickup
extends StaticBody3D

@export var weapon_id: StringName = &""

@onready var _mesh: MeshInstance3D = $MeshInstance3D

static var _highlight_mat: StandardMaterial3D = preload("res://assets/materials/pickup_highlight.tres")

func _ready() -> void:
	if weapon_id == &"":
		return
	var m = WeaponRegistry.get_mesh(weapon_id)
	if m:
		_mesh.mesh = m
	rotation_degrees = WeaponRegistry.get_pickup_rotation(weapon_id)

func highlight(on: bool) -> void:
	_mesh.material_overlay = _highlight_mat if on else null
```

- [ ] **Step 2: Create `scenes/weapons/weapon_pickup.tscn`**

```
[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/weapon_pickup.gd" id="1_pickup"]

[sub_resource type="BoxShape3D" id="BoxShape3D_pickup"]
size = Vector3(0.3, 0.1, 0.8)

[node name="WeaponPickup" type="StaticBody3D"]
collision_layer = 4
collision_mask = 0
script = ExtResource("1_pickup")

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("BoxShape3D_pickup")

[node name="MeshInstance3D" type="MeshInstance3D" parent="."]
```

`collision_layer = 4` is bit 2 = physics layer 3 ("weapon_pickups"). `collision_mask = 0` means the pickup doesn't collide with anything — it only exists to be raycasted against.

- [ ] **Step 3: Open Godot, let it import. Place a `weapon_pickup.tscn` instance in `test_scene.tscn` via the editor, set `weapon_id = "bat"` in the Inspector, and run the scene.**

Expected: a bat mesh appears lying on the ground. No errors in Output.

- [ ] **Step 4: Remove the test pickup from test_scene.tscn (undo or delete the instance).**

- [ ] **Step 5: Commit**

```bash
git add scripts/weapon_pickup.gd scenes/weapons/weapon_pickup.tscn
git commit -m "feat: add WeaponPickup scene with highlight support"
```

---

## Task 7: Player inventory refactor

**Files:**
- Modify: `scripts/player.gd`
- Modify: `scenes/player.tscn`

This is the biggest task. Do player.gd and player.tscn together — they must stay consistent.

- [ ] **Step 1: Update `scenes/player.tscn` — remove all weapon children from WeaponHolder**

Replace the entire file with the following. This removes all 5 weapon nodes and their ext_resource entries, leaving WeaponHolder empty:

```
[gd_scene format=3 uid="uid://usaygrv80ckp"]

[ext_resource type="PackedScene" uid="uid://bcb2r0fxa2poa" path="res://assets/models/player_rig.glb" id="1_y4r1p"]
[ext_resource type="Script" uid="uid://do60ev5tlenm" path="res://scripts/stance_manager.gd" id="11_d2wvv"]

[sub_resource type="CapsuleShape3D" id="CapsuleShape3D_g2els"]

[node name="Player" type="CharacterBody3D" unique_id=1553557232]

[node name="CollisionShape3D" type="CollisionShape3D" parent="." unique_id=133137851]
transform = Transform3D(0.3, 0, 0, 0, 1.8, 0, 0, 0, 0.3, 0, 0.7, 0)
shape = SubResource("CapsuleShape3D_g2els")

[node name="CameraPivot" type="Node3D" parent="." unique_id=928250975]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.5, 0)

[node name="Camera3D" type="Camera3D" parent="CameraPivot" unique_id=927387085]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 2, 1, 1.5)

[node name="WeaponHolder" type="Node3D" parent="CameraPivot/Camera3D" unique_id=1518021452]

[node name="RayCast3D" type="RayCast3D" parent="CameraPivot/Camera3D" unique_id=1883128150]
target_position = Vector3(0, 0, -50)
collision_mask = 2
collide_with_areas = true

[node name="PlayerModel" parent="." unique_id=2138265789 instance=ExtResource("1_y4r1p")]
transform = Transform3D(-0.4, 0, -3.4969112e-08, 0, 0.4, 0, 3.4969112e-08, 0, -0.4, 0, 0, 0)

[node name="StanceManager" type="Node" parent="." unique_id=1472633680]
script = ExtResource("11_d2wvv")
```

- [ ] **Step 2: Update `scripts/player.gd` — replace hardcoded weapon @onready vars with inventory**

Remove these 5 lines from the top of player.gd:
```gdscript
@onready var fists: WeaponFists = $CameraPivot/Camera3D/WeaponHolder/Fists
@onready var revolver: WeaponRevolver = $CameraPivot/Camera3D/WeaponHolder/Revolver
@onready var bat: WeaponBat = $CameraPivot/Camera3D/WeaponHolder/Bat
@onready var katana: WeaponKatana = $CameraPivot/Camera3D/WeaponHolder/Katana
@onready var shotgun: WeaponShotgun = $CameraPivot/Camera3D/WeaponHolder/Shotgun
```

Add these after `var _current_weapon: Node = null`:
```gdscript
const SLOT_FISTS  = 0
const SLOT_MELEE  = 1
const SLOT_RANGED = 2

var _inventory: Array = [null, null, null]
var _current_slot: int = 0
var _highlighted_pickup = null  # WeaponPickup or null

var _pickup_scene: PackedScene = preload("res://scenes/weapons/weapon_pickup.tscn")
```

- [ ] **Step 3: Update `_ready()` in player.gd — replace weapon signal connections with inventory init**

Remove:
```gdscript
revolver.ammo_changed.connect(_on_ammo_changed)
shotgun.ammo_changed.connect(_on_ammo_changed)
_equip_weapon.call_deferred(fists)
```

Add in their place:
```gdscript
var fists_instance := WeaponRegistry.get_scene(&"fists").instantiate() as WeaponBase
fists_instance._player = self
fists_instance.weapon_id = &"fists"
weapon_holder.add_child(fists_instance)
_inventory[SLOT_FISTS] = fists_instance
_equip_slot.call_deferred(SLOT_FISTS)
```

- [ ] **Step 4: Update `_input()` in player.gd — replace switch_weapon_1-5 with 1-3 + F/G**

Replace:
```gdscript
if event.is_action_pressed("switch_weapon_1"):
	_equip_weapon(fists)
if event.is_action_pressed("switch_weapon_2"):
	_equip_weapon(revolver)
if event.is_action_pressed("switch_weapon_3"):
	_equip_weapon(bat)
if event.is_action_pressed("switch_weapon_4"):
	_equip_weapon(katana)
if event.is_action_pressed("switch_weapon_5"):
	_equip_weapon(shotgun)
```

With:
```gdscript
if event.is_action_pressed("switch_weapon_1"):
	_equip_slot(SLOT_FISTS)
if event.is_action_pressed("switch_weapon_2"):
	_equip_slot(SLOT_MELEE)
if event.is_action_pressed("switch_weapon_3"):
	_equip_slot(SLOT_RANGED)
if event.is_action_pressed("drop_weapon"):
	_drop_weapon(_current_slot)
```

- [ ] **Step 5: Update `_update_animation()` in player.gd — replace identity checks with type checks**

Replace:
```gdscript
if _current_weapon == revolver or _current_weapon == shotgun:
	anim_player.play("holding_right")
elif _current_weapon == bat:
	anim_player.play("bat-hold")
elif _current_weapon == katana:
	anim_player.play("katana-hold")
```

With:
```gdscript
if _current_weapon is WeaponRanged:
	anim_player.play("holding_right")
elif _current_weapon is WeaponBat:
	anim_player.play("bat-hold")
elif _current_weapon is WeaponKatana:
	anim_player.play("katana-hold")
```

- [ ] **Step 6: Replace `_equip_weapon()` with `_equip_slot()`, `give_weapon()`, and `_drop_weapon()` in player.gd**

Remove the entire `_equip_weapon(weapon: Node)` function:
```gdscript
func _equip_weapon(weapon: Node) -> void:
	_is_attacking = false
	fists.visible = (weapon == fists)
	revolver.visible = (weapon == revolver)
	bat.visible = (weapon == bat)
	katana.visible = (weapon == katana)
	shotgun.visible = (weapon == shotgun)
	fists.set_physics_process(weapon == fists)
	revolver.set_physics_process(weapon == revolver)
	bat.set_physics_process(weapon == bat)
	katana.set_physics_process(weapon == katana)
	shotgun.set_physics_process(weapon == shotgun)
	_current_weapon = weapon
	var hud := get_node_or_null("/root/test_scene/hud")
	if hud:
		var names := {fists: "Fists", revolver: "Revolver", bat: "Bat", katana: "Katana", shotgun: "Shotgun"}
		hud.set_weapon_name(names.get(weapon, ""))
	_update_stance_for_weapon(weapon)
```

Add these three functions in its place:

```gdscript
func _equip_slot(idx: int) -> void:
	if idx != SLOT_FISTS and _inventory[idx] == null:
		return
	_is_attacking = false
	if _current_weapon != null:
		_current_weapon.visible = false
		_current_weapon.set_physics_process(false)
	_current_slot = idx
	_current_weapon = _inventory[idx]
	if _current_weapon != null:
		_current_weapon.visible = true
		_current_weapon.set_physics_process(true)
	var hud := get_node_or_null("/root/test_scene/hud")
	if hud and _current_weapon != null:
		var wb := _current_weapon as WeaponBase
		hud.set_weapon_name(WeaponRegistry.get_display_name(wb.weapon_id))
	_update_stance_for_weapon(_current_weapon)

func give_weapon(id: StringName) -> void:
	if not WeaponRegistry.has(id):
		push_error("give_weapon: unknown weapon id: " + id)
		return
	var slot := WeaponRegistry.get_slot(id)
	if _inventory[slot] != null:
		_drop_weapon(slot)
	var instance := WeaponRegistry.get_scene(id).instantiate() as WeaponBase
	instance._player = self
	instance.weapon_id = id
	if instance is WeaponRanged:
		(instance as WeaponRanged).ammo_changed.connect(_on_ammo_changed)
	weapon_holder.add_child(instance)
	instance.visible = false
	instance.set_physics_process(false)
	_inventory[slot] = instance
	_equip_slot(slot)

func _drop_weapon(slot: int) -> void:
	if slot == SLOT_FISTS:
		return
	var weapon: WeaponBase = _inventory[slot]
	if weapon == null:
		return
	var pickup = _pickup_scene.instantiate()
	pickup.weapon_id = weapon.weapon_id
	get_tree().current_scene.add_child(pickup)
	var forward := -global_transform.basis.z
	pickup.global_position = global_position + forward * 1.0
	pickup.global_position.y = 0.1
	weapon.queue_free()
	_inventory[slot] = null
	if _current_slot == slot:
		_equip_slot(SLOT_FISTS)
```

- [ ] **Step 7: Run the scene. Verify the player starts with fists visible and functional.**

Expected:
- Player spawns holding fists (visible fist punch animations work)
- Keys 1/2/3: 1 = fists, 2 = no-op (no melee yet), 3 = no-op (no ranged yet)
- G key: no-op (fists slot immune)
- No errors in Output

- [ ] **Step 8: Commit**

```bash
git add scripts/player.gd scenes/player.tscn
git commit -m "feat: replace hardcoded weapon refs with 3-slot inventory system"
```

---

## Task 8: HUD pickup prompt

**Files:**
- Modify: `hud.tscn`
- Modify: `scripts/hud.gd`

- [ ] **Step 1: Add `PickupPrompt` label to `hud.tscn`**

Add this node at the end of `hud.tscn` (before the closing):

```
[node name="PickupPrompt" type="Label" parent="." unique_id=1234567999]
visible = false
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -80.0
offset_top = 30.0
offset_right = 80.0
offset_bottom = 50.0
grow_horizontal = 2
grow_vertical = 2
horizontal_alignment = 1
text = "F — pick up"
```

This places the prompt just below center screen.

- [ ] **Step 2: Add `@onready` ref and two methods to `scripts/hud.gd`**

Add to the `@onready` block at the top:
```gdscript
@onready var pickup_prompt: Label = $PickupPrompt
```

Add at the bottom of the file:
```gdscript
func show_pickup_prompt(weapon_name: String) -> void:
	pickup_prompt.text = "F — pick up %s" % weapon_name
	pickup_prompt.visible = true

func hide_pickup_prompt() -> void:
	pickup_prompt.visible = false
```

- [ ] **Step 3: Run the scene. Verify no errors about missing PickupPrompt node.**

Expected: scene runs normally. Prompt is invisible by default. No errors.

- [ ] **Step 4: Commit**

```bash
git add hud.tscn scripts/hud.gd
git commit -m "feat: add pickup prompt label to HUD"
```

---

## Task 9: Pickup raycast + full pickup/drop flow

**Files:**
- Modify: `scripts/player.gd`

- [ ] **Step 1: Add `_update_pickup_highlight()` to `player.gd`**

Add this method after `_drop_weapon()`:

```gdscript
func _update_pickup_highlight() -> void:
	var space := get_world_3d().direct_space_state
	var cam_origin := camera.global_position
	var cam_forward := -camera.global_transform.basis.z
	var params := PhysicsRayQueryParameters3D.create(
		cam_origin,
		cam_origin + cam_forward * 3.0,
		4  # layer 3 only (weapon_pickups)
	)
	params.collide_with_areas = false
	var result := space.intersect_ray(params)
	var hud := get_node_or_null("/root/test_scene/hud")
	if result and result.collider is WeaponPickup:
		var pickup := result.collider as WeaponPickup
		if pickup != _highlighted_pickup:
			if _highlighted_pickup:
				_highlighted_pickup.highlight(false)
			pickup.highlight(true)
			_highlighted_pickup = pickup
		if hud:
			hud.show_pickup_prompt(WeaponRegistry.get_display_name(pickup.weapon_id))
	else:
		if _highlighted_pickup:
			_highlighted_pickup.highlight(false)
			_highlighted_pickup = null
		if hud:
			hud.hide_pickup_prompt()
```

- [ ] **Step 2: Call `_update_pickup_highlight()` from `_physics_process()`**

At the end of `_physics_process()`, add (before any `return` for `_is_dead` — wait, `_is_dead` returns early, so add this call before the `if _is_dead: return` block, or as the last line after it since pickup highlighting should work even if dead... actually add it right before `move_and_slide()` is called, so it only runs when alive):

Find:
```gdscript
	move_and_slide()
	_update_animation(dir)
```

Replace with:
```gdscript
	move_and_slide()
	_update_animation(dir)
	_update_pickup_highlight()
```

- [ ] **Step 3: Add F key pickup handler to `_input()`**

Add after the `drop_weapon` action check:
```gdscript
if event.is_action_pressed("pickup_weapon"):
	if _highlighted_pickup != null:
		give_weapon(_highlighted_pickup.weapon_id)
		_highlighted_pickup.queue_free()
		_highlighted_pickup = null
		var hud := get_node_or_null("/root/test_scene/hud")
		if hud:
			hud.hide_pickup_prompt()
```

- [ ] **Step 4: Place test pickups in test_scene.tscn and run a full flow test**

In the Godot editor, add 2 `weapon_pickup.tscn` instances to `test_scene.tscn`:
- Instance 1: set `weapon_id = "bat"`, place it somewhere reachable
- Instance 2: set `weapon_id = "revolver"`, place it elsewhere

Run the scene and verify:
1. Walking up to the bat pickup and pointing cursor at it → bat mesh highlights gold, "F — pick up Bat" appears
2. Pressing F → bat picked up, player switches to bat, melee animations work, bat visible in hand, prompt disappears
3. Key 2 → bat equipped, key 1 → fists
4. Pointing at revolver pickup and pressing F → revolver picked up in ranged slot, player switches to revolver, ammo HUD updates
5. Key 3 → revolver, key 1 → fists, key 2 → bat
6. Pressing G while holding bat → bat drops at feet as a pickup, player falls back to fists, slot 2 becomes empty
7. Walking over dropped bat → it highlights, press F → picked up again

- [ ] **Step 5: Commit**

```bash
git add scripts/player.gd
git commit -m "feat: pickup raycast highlight + F-to-grab + G-to-drop complete"
```

---

## Task 10: Cleanup test pickups + final commit

**Files:**
- Modify: `scenes/test_scene.tscn` (remove any test pickups added in Task 9 Step 4, unless you want to keep them for playtesting)

- [ ] **Step 1: Remove test pickup instances from test_scene.tscn if desired, or adjust their positions for a good playtest layout**

- [ ] **Step 2: Final commit**

```bash
git add scenes/test_scene.tscn
git commit -m "chore: clean up test pickup placement in test_scene"
```
