# Adding Weapons — Reference

How to add a new weapon to Voxel Brawl and place it in the world.

---

## Overview of the weapon pipeline

```
weapon_*.gd       — stats, hitbox, damage behaviour
weapon_*.tscn     — scene: mesh, audio, particles
weapon_registry.gd — metadata lookup (autoload)
weapon_pickup.tscn — world pickup node (generic, reused for all weapons)
```

Every weapon needs all four pieces. The pickup system and inventory work automatically once the registry entry exists.

---

## Step 1 — Create the weapon script

Create `scripts/weapon_<name>.gd`. Extend `WeaponMelee` or `WeaponRanged`.

### Melee weapon

```gdscript
class_name WeaponHammer
extends WeaponMelee

func _configure() -> void:
    weapon_type = WeaponType.BLUNT   # BLUNT / SHARP (affects damage type)
    damage = 65.0
    voxel_radius = 3.5               # world-unit radius of voxel destruction
    reach = 0.9
    cooldown = 0.9                   # seconds between attacks
    attack_anim = "bat"              # animation prefix — must match GLB anim names

    var s := CapsuleShape3D.new()
    s.radius = 0.3
    s.height = 1.2
    hit_shape = s
    hit_shape_offset = Vector3(-0.35, 0.35, 1.5)   # tweak in Remote panel
    hit_shape_rotation = Vector3(90, 0, 0)
    hit_shape_scale = Vector3(1.0, 1.0, 1.0)
    hit_enable_delay = 0.2    # seconds after swing start before hitbox activates
    hit_window_duration = 1.0 # how long the hitbox stays active
    max_hits = 10             # max segments hit per swing

# Optional — override for non-standard damage (default calls DamageManager.process_hit)
func _apply_hit(seg: VoxelSegment, local_hit: Vector3) -> void:
    DamageManager.process_hit(seg, local_hit, voxel_radius, damage, weapon_type)
```

**Melee hitbox tuning:** `hit_shape_offset` is in the weapon node's local space. Play the game with the Remote panel open (Godot debugger → Remote → select the Area3D under the weapon) to visually confirm the hitbox lines up with the swing.

**Key melee vars:**

| Var | What it does |
|-----|-------------|
| `weapon_type` | `BLUNT` crushes/degrades limbs; `SHARP` slices cleanly, intended for severing |
| `damage` | HP per hit (limb HP is proportional to its voxel count) |
| `voxel_radius` | World-unit radius of voxels destroyed on impact |
| `hit_enable_delay` | Skip the backswing — set to when the weapon actually reaches the target |
| `hit_window_duration` | Keep at 1.0 unless you want a very narrow contact window |
| `max_hits` | 10 for area weapons (bat, hammer), 1 for precision thrusts |
| `attack_anim` | Prefix used to look up `<prefix>_low`, `<prefix>_mid`, `<prefix>_high` animations |

### Ranged weapon

```gdscript
class_name WeaponSMG
extends WeaponRanged

func _configure() -> void:
    weapon_type = WeaponType.RANGED
    damage = 15.0
    voxel_radius = 0.8
    fire_rate = 0.1           # seconds between shots (lower = faster)
    max_ammo = 30
    reload_time = 1.8
    tracer_color = Color(1.0, 0.5, 0.2, 1.0)   # bullet tracer color
    recoil_shake_strength = 0.15                 # camera shake per shot (0–1)
    recoil_kick_amount = 6.0                     # crosshair kick pixels
    recoil_recovery_time = 0.15                  # crosshair recovery seconds
```

For burst fire, spread, or multi-pellet patterns, override `_fire()` and call `_fire_ray(direction)` per pellet. See `weapon_shotgun.gd` for an example.

**Key ranged vars:**

| Var | What it does |
|-----|-------------|
| `damage` | HP per projectile hit |
| `voxel_radius` | World-unit radius of voxels destroyed per hit |
| `fire_rate` | Cooldown between shots in seconds |
| `max_ammo` | Shots before reload (dropped weapons always respawn full) |
| `tracer_color` | Color of the bullet tracer streak |
| `recoil_shake_strength` | Camera shake intensity per shot |

---

## Step 2 — Create the weapon scene

Create `scenes/weapons/<name>.tscn`. Structure depends on type:

**Melee:**
```
WeaponName (Node3D) [weapon_<name>.gd]
  MeshInstance3D
  AudioStreamPlayer3D
```

**Ranged:**
```
WeaponName (Node3D) [weapon_<name>.gd]
  MeshInstance3D
  AudioShot (AudioStreamPlayer3D)
  Muzzle (Node3D)              ← bullet ray origin; position at barrel tip
  MuzzleFlash (GPUParticles3D) ← optional
```

**Things to set in the scene:**
- Root node: assign your weapon script. Set the transform (position/rotation/scale) so the weapon sits correctly in the player's hand — the weapon holder is attached to the right hand bone.
- `MeshInstance3D`: assign your weapon mesh (OBJ or imported GLB mesh).
- `Muzzle` (ranged only): position this node at the barrel tip in weapon-local space. The bullet tracer originates here.
- Root node scale is typically 2.0 (matching existing weapons). Adjust the MeshInstance3D transform to fit.

**Tip:** Use an existing weapon scene as a starting point. Duplicate `bat.tscn` for melee or `revolver.tscn` for ranged, rename it, and swap the script and mesh.

---

## Step 3 — Register in WeaponRegistry

Open `scripts/weapon_registry.gd`. Add an entry to `_data`:

```gdscript
&"hammer": {
    "scene": preload("res://scenes/weapons/hammer.tscn"),
    "mesh": preload("res://assets/models/Weapons/Hammer.obj"),
    "display_name": "Hammer",
    "slot": Slot.MELEE,           # Slot.FISTS / Slot.MELEE / Slot.RANGED
    "pickup_rotation": Vector3(90, 0, 0),   # how the pickup root is rotated on the ground
    "pickup_scale": 0.15,                   # scale of the mesh in the pickup node
},
```

**Slot rules:**
- `Slot.MELEE` — occupies the melee slot (key 2). Only one melee weapon at a time.
- `Slot.RANGED` — occupies the ranged slot (key 3). Only one ranged weapon at a time.
- `Slot.FISTS` — reserved for fists only, do not use.

**Pickup appearance tuning (`pickup_rotation` and `pickup_scale`):**

These control how the weapon looks lying on the ground as a pickup.

- `pickup_scale`: scales the mesh in the pickup. Start with `0.15` and adjust. Too big = use a smaller number. The mesh is the same OBJ used in the weapon scene but without the weapon holder's transform chain, so it will need independent scaling.
- `pickup_rotation`: rotates the entire pickup node (including collision box). `Vector3(90, 0, 0)` works for weapons whose OBJ is elongated along the Y axis (like the bat) — it lays them flat. Use `Vector3(0, 0, 0)` if the weapon looks wrong or ends up underground. Tune by running the game and observing.

---

## Step 4 — Place pickups in a map

In the Godot editor:

1. In the Scene panel, right-click on the scene root → **Instantiate Child Scene** → select `scenes/weapons/weapon_pickup.tscn`
2. Select the new node in the Inspector and set **Weapon Id** to the string key you used in the registry (e.g. `hammer`)
3. Move the node to the desired world position. Use y = 0.1 above the floor to avoid z-fighting.

No other setup needed. `weapon_pickup.gd._ready()` loads the mesh, scale, and rotation from the registry automatically.

**Tips:**
- Name the node descriptively: `WeaponPickupHammer_NorthRoom`
- Duplicate (Ctrl+D) an existing pickup node and change `weapon_id` to save time
- Multiple pickups of the same weapon on the same map is fine — they're fully independent
- If a weapon is picked up and then dropped, a new pickup spawns at the player's feet (same scene, same logic)

---

## Step 5 — Add animations (melee only)

Melee weapons use stance-based animation names built as `<attack_anim>_<stance>`:

| Stance | Suffix | Full name example |
|--------|--------|-------------------|
| Low    | `_low`  | `hammer_low` |
| Mid    | `_mid`  | `hammer_mid` |
| High   | `_high` | `hammer_high` |
| Thrust | `_thrust` | `hammer_thrust` (SHARP only) |

These animations must exist in `assets/models/player_rig.glb`. If you reuse an existing weapon's `attack_anim` prefix (e.g., `"bat"`), you get the bat animations for free.

If you add new animations: edit the rig in Blender, add the animation tracks named exactly as above, re-export to `player_rig.glb`.

---

## Checklist

```
[ ] scripts/weapon_<name>.gd created, extends WeaponMelee or WeaponRanged
[ ] _configure() sets all stats and hit_shape (melee) or fire stats (ranged)
[ ] scenes/weapons/<name>.tscn created with correct node structure
[ ] Muzzle node positioned at barrel tip (ranged only)
[ ] Entry added to weapon_registry.gd _data dictionary
[ ] Mesh .obj or .glb imported into assets/models/Weapons/
[ ] pickup_scale and pickup_rotation tuned by running the game
[ ] Animations exist in player_rig.glb for attack_anim prefix (melee only)
[ ] weapon_pickup.tscn instances placed in map with weapon_id set
```
