# MVP Cube Movement Design

## Goal

Minimum functioning game: player controls a cube moving around a flat plane with an isometric-style camera.

## Architecture

Single scene (`main.tscn`) with one script (`player.gd`). No sub-scenes.

## Scene Tree

```
main (Node3D)
  WorldEnvironment
  DirectionalLight3D
  StaticBody3D "Ground"
    MeshInstance3D  (BoxMesh, large flat)
    CollisionShape3D (BoxShape3D)
  CharacterBody3D "Player"
    MeshInstance3D  (BoxMesh, 1x1x1)
    CollisionShape3D (BoxShape3D)
    Camera3D        (fixed isometric offset, looks at player origin)
  player.gd (attached to CharacterBody3D)
```

## Camera

Fixed isometric-style: positioned at offset `Vector3(10, 10, 10)` relative to player, `look_at` player position. Moves with player (child node), does not rotate on input.

## Player Script

- Input: WASD / arrow keys → move along XZ plane
- Gravity applied each frame so cube rests on ground
- `move_and_slide()` for collision resolution
- Speed: 5 m/s

## Files to Create

- `main.tscn`
- `player.gd`
- Update `project.godot` to set `main.tscn` as the main scene
