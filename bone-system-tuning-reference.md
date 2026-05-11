# Bone System Tuning Reference

All tuning constants live in the `# --- TUNING ---` block at the top of `scripts/voxel_segment.gd`.

---

## How the bone reveal works

Every VoxelSegment starts as pure flesh (all voxels at `voxel_hp = 1.0`, authored flesh colors). A bone `.vox` file is registered in the segment config but not loaded at spawn — zero cost until triggered.

When a segment's **flesh fraction** drops below `BONE_REVEAL_THRESHOLD`:

1. The paired bone `.vox` is parsed via `VoxelLoader.load_vox()`
2. For every bone position that still has flesh: the flesh voxel is **overwritten** with the bone color and hardened to `BONE_HP`. It still counts toward the flesh HP pool — carving through bone still kills.
3. For bone positions where flesh was already carved away: a **net-new voxel** is added into the empty space. This is purely visual/tactile — it does not contribute to the HP pool.
4. The mesh rebuilds once. From here the segment has a mix of flesh surface and exposed bone interior.

Bone voxels are **immune to the damage tint** — they hold their authored off-white/yellow color regardless of nearby hits.

---

## Bone Reveal Threshold — `BONE_REVEAL_THRESHOLD` (line ~8)

```gdscript
const BONE_REVEAL_THRESHOLD: float = 0.85
```

Flesh fraction below which bone loads. Compares `flesh_voxel_count / total_voxel_count`.

| Value | Effect |
|---|---|
| `0.95` | Bone appears after just a few hits — very early reveal |
| `0.85` | Default — bone loads after ~15% of flesh is gone |
| `0.60` | Bone loads only after heavy damage — feel must-earn the reveal |
| `0.30` | Bone barely visible before segment is nearly destroyed |

**Tip:** Lower values delay the reveal, making it feel more earned. Higher values show bone early, which reads better at fast combat pace. 0.85 is a good baseline.

---

## Bone Voxel Durability — `BONE_HP` (line ~9)

```gdscript
const BONE_HP := 3.0
```

Hits required to destroy one bone voxel. Flesh voxels are always `1.0`. This constant applies to both replaced-flesh bone voxels (overwritten at load) and net-new bone voxels (added into carved gaps).

| Value | Effect |
|---|---|
| `1.0` | Bone is no harder than flesh — reveal is purely visual |
| `2.0` | Bone takes 2× as long to carve through |
| `3.0` | Default — bone feels noticeably tougher, crunchy when chipping |
| `5.0+` | Bone is very difficult to destroy — almost a second health pool |

**Note:** `BONE_HP` does not extend the HP pool — HealthSystem reads `flesh_voxel_count / total_voxel_count`. Bone just makes carving slower and more satisfying.

---

## Damage Tint — `DAMAGE_COLOR` and `DAMAGE_TINT_RATIO` (lines ~12–13)

```gdscript
const DAMAGE_COLOR := Color(0.12, 0.04, 0.04)
const DAMAGE_TINT_RATIO := 0.5
```

On every hit, flesh voxels within the tint radius are lerped toward `DAMAGE_COLOR`. Bone voxels are **excluded** from tinting and keep their authored color.

**`DAMAGE_COLOR`** — the target color of the tint. Default is very dark maroon (dried blood).

| Example | Color |
|---|---|
| `Color(0.12, 0.04, 0.04)` | Default — dark maroon |
| `Color(0.20, 0.05, 0.05)` | Slightly brighter red |
| `Color(0.05, 0.05, 0.05)` | Near-black — charred look |

**`DAMAGE_TINT_RATIO`** — lerp strength, `0.0`–`1.0`.

| Value | Effect |
|---|---|
| `0.0` | No tint at all |
| `0.3` | Subtle darkening around craters |
| `0.5` | Default — clear wound ring |
| `0.8` | Heavy tinting, wound area goes almost fully dark |

---

## Tint Radius — `DAMAGE_TINT_RADIUS_MULT` (line ~14)

```gdscript
const DAMAGE_TINT_RADIUS_MULT := 2.0
```

Tint applies to flesh voxels within `hit_radius × DAMAGE_TINT_RADIUS_MULT`. Larger values spread the wound discoloration further.

| Value | Effect |
|---|---|
| `1.0` | Tint exactly matches the damage radius — tight wound ring |
| `2.0` | Default — tint ring twice as wide as the crater |
| `3.0` | Wide bruising effect around each hit |

---

## Debris Physics Budget — `DEBRIS_MAX_PHYSICS` (line ~17)

```gdscript
const DEBRIS_MAX_PHYSICS := 8
```

Maximum number of `RigidBody3D` cube physics objects spawned per hit. The closest voxels to the impact point get physics; the rest go to `GPUParticles3D`. Raise this for heavier physical impacts; lower it to save physics budget in dense fights.

| Value | Effect |
|---|---|
| `3` | Minimal physics — mostly GPU particles |
| `8` | Default — good balance |
| `15` | Heavy hit feels weighty; more physics bodies in the world |

**Note:** Each `RigidBody3D` cube persists until `DebrisPool` recycles it. Keep this reasonable when 8 players are fighting simultaneously (~40–64 physics cubes active at peak at the default).

---

## Cluster Debris Threshold — `CHUNK_MIN_VOXELS` (line ~16)

```gdscript
const CHUNK_MIN_VOXELS := 8
```

When a connectivity check finds voxels disconnected from the limb root, clusters with fewer than this many voxels become GPU particles instead of a rigid chunk. Larger clusters become a `RigidBody3D` mesh chunk.

| Value | Effect |
|---|---|
| `4` | Small slivers still become flying rigid chunks |
| `8` | Default — most small fragments become particles |
| `16` | Only large severed pieces become rigid — lighter on physics |

---

## Bone Asset Mapping — `PLAYER_SEGMENT_CONFIG` / `SEGMENT_CONFIG` (index `[9]`)

Bone `.vox` paths are the 10th element `cfg[9]` in each segment's config array in `player.gd`, `brawler.gd`, and `dummy.gd`. All 14 flesh segments have a paired bone file:

| Flesh segment | Bone file |
|---|---|
| `torso_bottom` | `spine_bottom.vox` |
| `torso_top` | `spine_top.vox` |
| `head_bottom` | `skull_bottom.vox` |
| `head_top` | `skull_top.vox` |
| `arm_r_upper` | `humerus_r.vox` |
| `arm_r_fore` | `radius_r.vox` |
| `hand_r` | `metacarpal_r.vox` |
| `arm_l_upper` | `humerus_l.vox` |
| `arm_l_fore` | `radius_l.vox` |
| `hand_l` | `metacarpal_l.vox` |
| `leg_r_upper` | `femur_r.vox` |
| `leg_r_fore` | `tibia_r.vox` |
| `leg_l_upper` | `femur_l.vox` |
| `leg_l_fore` | `tibia_l.vox` |

To disable bone reveal on a specific segment, set its `cfg[9]` to `""`.
