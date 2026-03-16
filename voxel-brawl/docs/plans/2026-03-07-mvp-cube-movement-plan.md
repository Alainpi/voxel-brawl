# MVP Cube Movement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a playable Godot 4 scene where the player moves a cube around a flat plane using WASD/arrow keys, viewed from a fixed isometric camera.

**Architecture:** Single `main.tscn` scene containing the ground, player cube, lighting, and camera. One GDScript `player.gd` attached to the CharacterBody3D handles movement and gravity. Camera is a child of the player so it follows automatically.

**Tech Stack:** Godot 4.6, GDScript, Jolt Physics, Forward Plus rendering

---

### Task 1: Create the player script

**Files:**
- Create: `player.gd`

**Step 1: Create `player.gd` at the project root**

```gdscript
extends CharacterBody3D

const SPEED = 5.0
const GRAVITY = -9.8

func _physics_process(delta: float) -> void:
	var direction := Vector3.ZERO
	direction.x = Input.get_axis("ui_left", "ui_right")
	direction.z = Input.get_axis("ui_up", "ui_down")

	if direction.length() > 0:
		direction = direction.normalized()

	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED
	velocity.y += GRAVITY * delta

	move_and_slide()
```

Notes:
- `ui_left/right/up/down` are built-in Godot actions mapped to WASD and arrow keys by default.
- `velocity.y += GRAVITY * delta` accumulates downward force each frame.
- `move_and_slide()` handles collision with the ground.

**Step 2: Commit**

```bash
git add player.gd
git commit -m "feat: add player movement script"
```

---

### Task 2: Create the main scene

**Files:**
- Create: `main.tscn`

**Step 1: Create `main.tscn`**

Godot `.tscn` files use a text resource format. Create the file with the following content exactly:

```
[gd_scene load_steps=6 format=3 uid="uid://main"]

[ext_resource type="Script" path="res://player.gd" id="1_player"]

[sub_resource type="BoxMesh" id="BoxMesh_ground"]
size = Vector3(40, 0.2, 40)

[sub_resource type="BoxShape3D" id="BoxShape3D_ground"]
size = Vector3(40, 0.2, 40)

[sub_resource type="BoxMesh" id="BoxMesh_player"]
size = Vector3(1, 1, 1)

[sub_resource type="BoxShape3D" id="BoxShape3D_player"]
size = Vector3(1, 1, 1)

[node name="Main" type="Node3D"]

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = null

[node name="DirectionalLight3D" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.707, -0.5, 0.5, 0, 0.707, 0.707, -0.707, -0.5, 0.5, 0, 10, 0)
shadow_enabled = true

[node name="Ground" type="StaticBody3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)

[node name="MeshInstance3D" type="MeshInstance3D" parent="Ground"]
mesh = SubResource("BoxMesh_ground")

[node name="CollisionShape3D" type="CollisionShape3D" parent="Ground"]
shape = SubResource("BoxShape3D_ground")

[node name="Player" type="CharacterBody3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0)
script = ExtResource("1_player")

[node name="MeshInstance3D" type="MeshInstance3D" parent="Player"]
mesh = SubResource("BoxMesh_player")

[node name="CollisionShape3D" type="CollisionShape3D" parent="Player"]
shape = SubResource("BoxShape3D_player")

[node name="Camera3D" type="Camera3D" parent="Player"]
transform = Transform3D(0.707, -0.408, 0.577, 0, 0.816, 0.577, -0.707, -0.408, 0.577, -10, 10, 10)
```

Notes:
- The ground is a 40x0.2x40 box at origin — wide flat surface.
- The player starts at Y=1 so it's above the ground and falls onto it.
- Camera is at local offset `(-10, 10, 10)` looking toward the player origin — isometric-style angle.
- The camera transform encodes a look_at from that offset position toward `(0,0,0)`.

**Step 2: Commit**

```bash
git add main.tscn
git commit -m "feat: add main scene with ground, player, and isometric camera"
```

---

### Task 3: Set main scene in project settings

**Files:**
- Modify: `project.godot`

**Step 1: Add the main scene entry to `project.godot`**

Open `project.godot` and add this line under the `[application]` section:

```ini
config/main_scene="res://main.tscn"
```

The `[application]` section should look like:

```ini
[application]

config/name="VoxelBrawl"
config/features=PackedStringArray("4.6", "Forward Plus")
config/icon="res://icon.svg"
config/main_scene="res://main.tscn"
```

**Step 2: Verify**

Open Godot editor (or press F5 to run). The game should launch showing the cube on a flat plane. Press WASD or arrow keys — the cube should move. Camera should follow at a fixed isometric angle.

Expected behavior:
- Cube sits on the ground (doesn't fall through)
- WASD / arrow keys move the cube in 4 directions
- Camera follows the cube from an isometric angle

**Step 3: Commit**

```bash
git add project.godot
git commit -m "feat: set main.tscn as main scene to complete MVP"
```
