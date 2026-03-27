# Melee Weapon Hit Detection — Issue Brief

## Current System

Each weapon script (`WeaponBat`, `WeaponKatana`, `WeaponFists`) extends `WeaponMelee`, which on button press:
1. Starts the attack animation
2. Waits a fixed `hit_delay` timer
3. Fires a single-frame shape query using the weapon mesh's AABB bounding box
4. Deals damage to any `VoxelSegment` Area3D found inside that box

---

## Problems

### 1. Single-frame snapshot detection
The hit check runs once at a fixed delay after the button press. If the enemy isn't inside the weapon's AABB at that exact frame — because of minor positional differences, timing variance, or latency — the hit is missed entirely. There is no sweep or window of opportunity.

### 2. Hit delay is a guess
`hit_delay` is a hardcoded timer meant to approximate when the animation peaks. It has no connection to the actual animation state. If the animation runs slower than expected (e.g. due to frame drops) the hit fires before the weapon makes visual contact. If the player moves between press and detection, the weapon and the hit sphere are in different positions.

### 3. Mesh AABB is unreliable
The weapon mesh AABB in local space doesn't map cleanly to a world-space box during a swing — the mesh doesn't physically move through the scene during the animation. The weapon node's transform stays fixed; only the skeleton/animation moves the visual mesh. So the AABB represents the weapon at rest pose, not mid-swing.

### 4. Isometric targeting mismatch
In a top-down isometric game, the player aims by rotating toward the mouse cursor on the ground plane. The melee swing should arc in front of the player relative to the cursor, but currently the hit sphere is placed purely based on player facing direction with no awareness of distance to target or cursor position. A player standing slightly off-axis from an enemy will miss even when the weapon looks like it connects visually.

### 5. No persistent hit window
After the first swing registers a hit, subsequent swings within the same cooldown cycle may not register because the collision check fires once. There is no continuous detection during the swing arc.

---

## Things to Research

- **Area3D activation window** — attach an `Area3D` hitbox directly to the weapon bone, enable it only during the attack animation frames (via AnimationPlayer track or signal), disable after. Godot handles the physics overlap continuously while it's active. This is how most action games handle melee.

- **AnimationPlayer method tracks** — Godot supports calling methods at specific keyframes in an animation. Could fire `_do_hit()` at the exact frame the weapon connects, eliminating the delay timer entirely.

- **ShapeCast3D sweep** — `ShapeCast3D` sweeps a shape along a vector each physics frame. Attaching one to the weapon bone and checking it during the attack animation frames would catch hits across the full swing arc rather than at a single moment.

- **Isometric melee conventions** — research how top-down games (Hotline Miami, Enter the Gungeon, Nuclear Throne) handle melee hit registration. Common pattern: short-range arc check in front of player using an angular cone/sector rather than a sphere or box.

- **Continuous detection during animation** — rather than a one-shot timer, poll for hits every physics frame while an `_is_attacking` flag is true, then clear the flag when the animation finishes. Prevents the missed-frame problem.
