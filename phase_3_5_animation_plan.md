# Phase 3.5 Animation Plan

Authoring plan for the full animation rework in Phase 3.5. Companion to GDD §Phase 3.5 and `architecture.md`. Updated 2026-04-26.

All planning decisions resolved 2026-04-26 — see §11. **Milestone 1 complete 2026-05-10** — see §10 for milestone status. Authoring proceeds against Milestone 2 next.

---

## 1. Goal

Replace every existing baked animation and add the new states required for Phase 3.5 (mobility, cover, injury locomotion, hit reacts, equip, polish), authored against Godot 4.6's `AnimationTree` + `SkeletonModifier3D` IK pipeline so the result reads as smoother and more tailored than a pure-keyframe pipeline could deliver, with random variation where it matters.

## 2. Driving principle: IK-first authoring

Every clip is authored "naive" in the places runtime IK will refine. If a thing will be solved at runtime, the keyframe must leave room for the solver — not fight it.

What runtime IK handles (so don't bake it tightly):

- **Foot height and ground conformance** — foot IK raycasts per-leg from a target offset and adjusts `leg_*_upper` / `leg_*_fore` rotation. Author feet planting on flat Y=0.
- **Head aim and look-at** — `LookAtModifier3D` on `head_bottom` → `head_top`. Author idle/walk/run with the head pointing straight forward, neutral.
- **Torso aim twist (ranged)** — spine-aim modifier rotates `torso_top` toward the camera/aim direction. Author ranged hold poses facing forward.
- **Off-hand placement on two-handed grips** — IK targets a `Marker3D` on the weapon. Author `hand_l` relaxed in two-handed katana keyframes; the solver pulls it to the hilt.
- **Recoil** — additive layer, intensity-driven. Never bake into shoot clips.
- **Breathing** — additive idle layer, always running.

What stays keyframed (because runtime cannot infer it):

- Attack swing paths and timing
- Locomotion gait, weight shift, pelvis bob
- Stance silhouette
- Hit react direction and recoil shape
- Equip / holster motion paths
- Death collapse lead-in (hands off to ragdoll after this clip)

## 3. Godot-side architecture (the target your clips slot into)

This is what AnimationTree will look like once authored — included so authoring decisions can be made against it. Implementation work is separate from animation work, but the shape is fixed enough to author against.

```
AnimationTree (root)
└── Output
    └── Add (recoil)                ← additive; Marker3D-driven for ranged
        └── Add (hit_react)         ← additive; pulse on damage events
            └── Add (lean)          ← additive; -1..+1 from input
                └── Add (breathe)   ← additive; always-on, low amplitude
                    └── BlendTree (base body)
                        ├── BlendSpace2D (locomotion)         ← speed × strafe
                        │     populated with: idle/walk/run × dir + crouch + prone
                        ├── State machine (injury overlay)    ← swaps locomotion source
                        │     hobble_fore_*, hobble_full_*, crawl_legs_lost
                        ├── Add (upper-body stance hold)      ← additive over locomotion
                        │     hold_bat_*, hold_katana_*, hold_pistol, hold_shotgun
                        └── OneShot (attacks / equip / hits / death)
                              fires on signal, returns to base when done

SkeletonModifier3D stack on Skeleton3D (in evaluation order):
  1. AnimationTree output (base pose this frame)
  2. SpineAimModifier (custom)         ← ranged only, intensity = is_aiming
  3. LookAtModifier3D (head_bottom)    ← always on, blend = head_look_intensity
  4. LookAtModifier3D (head_top)       ← finer aim
  5. FootIK (custom, per leg)          ← always on for grounded states; off in jump/fall/crawl
  6. ArmIK (off-hand only, two-handed) ← intensity = is_two_handed_weapon
  7. PhysicalBoneSimulator3D           ← off until death; takes over fully on death
```

Authoring contract: **clips provide the base pose at layer 1.** Layers 2–6 modify it. Layer 7 replaces it.

## 4. Rig recap

14-segment dismemberment skeleton. Bone names exact, case-sensitive. From `limb_system.gd:32–46` and `player.gd:31–46`:

```
torso_bottom (root, never detaches)
├── torso_top
│   ├── head_bottom
│   │   └── head_top
│   ├── arm_r_upper
│   │   └── arm_r_fore
│   │       └── hand_r
│   └── arm_l_upper
│       └── arm_l_fore
│           └── hand_l
├── leg_r_upper
│   └── leg_r_fore
└── leg_l_upper
    └── leg_l_fore
```

**Rest pose is fixed.** Don't change shoulder droop, hip width, or limb lengths — `PLAYER_SEGMENT_CONFIG` offsets and PinJoint3D ragdoll calibration depend on the current rest. If a posing change feels needed, raise it before authoring; it cascades into Phase 2 calibration.

**No new bones in the export skeleton.** Use any control rig you want for authoring (Rigify, custom IK chains, foot rollers, root bone, weapon master), but bake to the 14 deform bones before export. Two valid workflows in §8.

## 5. Animation inventory

Columns:

- **Name** — Blender Action name = Godot animation name
- **Frames** — total length at 30fps; `~` means tunable, `loop` means cyclic
- **Layer** — `base` (full skeleton) / `additive` (delta from rest, partial skeleton)
- **IK-aware** — bones runtime IK will modify on this clip; keep them neutral in keys
- **Notes** — pose markers, transitions, special handling

### Group A — Base locomotion (in-place, root at origin)

| Name | Frames | Layer | IK-aware | Notes |
|---|---|---|---|---|
| `idle_a` | ~120 loop | base | head, feet | Subtle weight shift L→R over cycle |
| `idle_b` | ~120 loop | base | head, feet | Different fidget — weapon adjust or shoulder roll |
| `idle_c` | ~120 loop | base | head, feet | Different fidget — head tilt scan or breath emphasis |
| `walk` | ~26 loop | base | head, feet | One full gait cycle; feet plant flat. SPEED=5.0 m/s (effectively a jog). |
| `run` | ~18 loop | base | head, feet | Tighter cadence, larger pelvis bob, exaggerated arm swing. SPRINT_MULT=1.6 → run = 8.0 m/s. |
| `walk_back` | ~32 loop | base | head, feet | Shorter stride, weight back |
| `strafe_l` | ~30 loop | base | head, feet | Crossover step OK if it reads natural |
| `strafe_r` | ~30 loop | base | head, feet | Mirror of `strafe_l` — author both, don't trust glTF mirror |

**Resolved:** SPEED 5.0, SPRINT_MULT 1.6 → run is 8.0 m/s, 60% faster than walk. Run authored as a separate ~18-frame cycle (vs. ~26 for walk) — playing walk faster reads as "sped-up walk," not "running." `BlendSpace2D` interpolates between them on a speed axis.

### Group B — Crouch / prone / lean (greenfield)

| Name | Frames | Layer | IK-aware | Notes |
|---|---|---|---|---|
| `crouch_idle` | ~120 loop | base | head, feet | Lower pelvis ~30%, knees out |
| `crouch_walk_fwd` | ~36 loop | base | head, feet | Slower cadence than walk |
| `crouch_walk_back` | ~38 loop | base | head, feet | |
| `crouch_strafe_l` | ~36 loop | base | head, feet | |
| `crouch_strafe_r` | ~36 loop | base | head, feet | |
| `prone_idle` | ~120 loop | base | head, hands | Feet IK off; arms support upper body |
| `prone_crawl_fwd` | ~48 loop | base | head, hands | Asymmetric arm pull + leg push |
| `prone_crawl_back` | ~48 loop | base | head, hands | |
| `prone_turn_l` | ~30 loop | base | head, hands | In-place yaw |
| `prone_turn_r` | ~30 loop | base | head, hands | |
| `stand_to_crouch` | 8 | base | feet | Transition; non-loop |
| `crouch_to_stand` | 8 | base | feet | |
| `crouch_to_prone` | 12 | base | hands, feet | |
| `prone_to_crouch` | 12 | base | hands, feet | |
| `lean_l` | 1 (pose) | additive | none | Single-pose additive — no time component, AnimationTree blends to it |
| `lean_r` | 1 (pose) | additive | none | |

**Notes on lean:** lean is a static pose delta (~15° spine roll + slight head counter-tilt + foot weight shift). Author as a 1-frame action; `AnimationNodeAdd2` interpolates intensity at runtime.

**Notes on prone:** disable foot IK on prone states; feet trail naturally and shouldn't try to plant. **Hand IK is runtime** for `prone_crawl_fwd` / `prone_crawl_back` — author hand_l and hand_r relaxed (not baked into specific plant positions); the hand IK solver raycasts and adjusts during play. This requires a hand-plant solver implementation (per-arm chain: `arm_*_upper → arm_*_fore → hand_*` with target = ground raycast hit). Wire alongside foot IK in Milestone 2.

### Group C — Injury locomotion (deferred from Phase 3)

Maps to `_leg_loss_speed_multiplier()` tiers in `player.gd:531–545`. Side asymmetry matters — author both sides explicitly, don't mirror at runtime.

| Name | Frames | Layer | IK-aware | Notes |
|---|---|---|---|---|
| `hobble_fore_r` | ~36 loop | base | head, feet | Right foreleg lost; favor left foot, drag/skip on right |
| `hobble_fore_l` | ~36 loop | base | head, feet | Mirror in concept, author independently |
| `hobble_full_r` | ~30 loop | base | head, left foot | Right full leg gone; one-legged hop on left, right stump trails |
| `hobble_full_l` | ~30 loop | base | head, right foot | |
| `crawl_legs_lost` | ~60 loop | base | head, hands | Both legs lost or 2× upper-equivalents; arm-pull only, legs trail limp |

Foot IK plan per state:

- `hobble_fore_*` — both feet IK active; expect the lost-side fore segment to be missing (bone deleted by limb system) so IK target compensates lower
- `hobble_full_*` — IK only on remaining leg; lost side has no foot to plant
- `crawl_legs_lost` — feet IK off entirely; **hand IK on** (same solver as prone-crawl). Author hands relaxed; runtime drives plant positions against the ground.

### Group D — Stance / weapon hold poses (additive over locomotion)

All authored as upper-body deltas — torso_top, both arms, both hands. **Do not key legs or pelvis** in these clips. Single-frame poses are acceptable; AnimationTree blends to them.

| Name | Frames | Layer | IK-aware | Notes |
|---|---|---|---|---|
| `hold_unarmed` | 1 | additive | hand_l (off-hand future use) | Baseline; mostly null |
| `hold_bat_low` | 1 | additive | none on R, hand_l off | Bat low, dragging-by-hip silhouette |
| `hold_bat_mid` | 1 | additive | none on R, hand_l off | Bat at chest |
| `hold_bat_high` | 1 | additive | none on R, hand_l off | Bat over shoulder |
| `hold_katana_low` | 1 | additive | hand_l (two-handed) | Two-handed grip; leave `hand_l` relaxed for IK |
| `hold_katana_mid` | 1 | additive | hand_l | |
| `hold_katana_high` | 1 | additive | hand_l | Overhead |
| `hold_katana_thrust` | 1 | additive | hand_l | Stance facing forward |
| `hold_pistol` | 1 | additive | torso aim, head aim | One-handed, off-hand at side |
| `hold_shotgun` | 1 | additive | torso aim, head aim, hand_l | Two-handed; off-hand on forend |

**Note on katana off-hand:** every katana hold pose authored with `hand_l` deliberately *unposed* relative to the weapon. Runtime arm IK will solve `arm_l_upper → arm_l_fore → hand_l` to a `Marker3D` on the katana mesh. Trust the solver; don't hand-place.

### Group E — Melee attacks

Hit-frame timing constraint per weapon (30 fps), driven by current `weapon_melee.gd` constants. The swing arc must reach hitbox-active pose by these frames so timer values stay correct without script changes:

| Weapon | `hit_enable_delay` | Hit-active frame | Swing-active duration | End frame guideline |
|---|---|---|---|---|
| Bat | 0.20s | frame 6 | 1.0s (frames 6–36) | recovery to ~frame 50 |
| Katana | 0.53s | frame 16 | 1.0s (frames 16–46) | recovery to ~frame 60 |
| Katana thrust | 0.53s | frame 16 | 1.0s (frames 16–46) | shorter follow-through, ~frame 50 |
| Fists | 0.08s | frame 2–3 | 1.0s (frames 3–33) | recovery to ~frame 40 |

Add Pose Markers at hit-active and swing-end frames in every melee Action: `hit_active`, `hit_end`. They don't transfer through glTF, but make per-anim review and timing audits trivial.

| Name | Frames | Layer | IK-aware | Notes |
|---|---|---|---|---|
| `atk_bat_low_a` | ~50 | base | head, feet | Hit at frame 6; horizontal sweep |
| `atk_bat_low_b` | ~50 | base | head, feet | Hit at frame 6; different wind-up + follow-through |
| `atk_bat_mid_a` | ~50 | base | head, feet | |
| `atk_bat_mid_b` | ~50 | base | head, feet | |
| `atk_bat_high_a` | ~50 | base | head, feet | Overhead |
| `atk_bat_high_b` | ~50 | base | head, feet | |
| `atk_katana_low_a` | ~60 | base | head, feet, hand_l | Hit at frame 16 |
| `atk_katana_low_b` | ~60 | base | head, feet, hand_l | |
| `atk_katana_mid_a` | ~60 | base | head, feet, hand_l | |
| `atk_katana_mid_b` | ~60 | base | head, feet, hand_l | |
| `atk_katana_high_a` | ~60 | base | head, feet, hand_l | |
| `atk_katana_high_b` | ~60 | base | head, feet, hand_l | |
| `atk_katana_thrust_a` | ~50 | base | head, feet, hand_l | Linear thrust path |
| `atk_katana_thrust_b` | ~50 | base | head, feet, hand_l | |
| `atk_punch_low_r` | ~40 | base | head, feet | Right-hand jab at frame 3 |
| `atk_punch_low_l` | ~40 | base | head, feet | Left-hand jab at frame 3; off-hand attacks land via separate hitarea (already in `weapon_fists.gd`) |
| `atk_punch_mid_r` | ~40 | base | head, feet | |
| `atk_punch_mid_l` | ~40 | base | head, feet | |
| `atk_punch_high_r` | ~40 | base | head, feet | Hook / uppercut |
| `atk_punch_high_l` | ~40 | base | head, feet | |

**Variation principle:** `_a` and `_b` variants share total length and hit frame. Vary the wind-up arc and follow-through. AnimationTree's `AnimationNodeBlendTree` with a random selector picks between them per swing.

**Resolved:** 6 punch clips total (R/L per stance, no stylistic alternates). Hand alternation provides the silhouette variety that `_a/_b` would otherwise add. If unarmed combat reads repetitively in playtesting, add 6 more variants in a later milestone — don't pre-emptively author 12.

### Group F — Ranged

| Name | Frames | Layer | IK-aware | Notes |
|---|---|---|---|---|
| `aim_pistol_idle` | ~120 loop | base | torso aim, head aim | Subtle breath sway baked light; modifier handles aim |
| `aim_shotgun_idle` | ~120 loop | base | torso aim, head aim, hand_l | Two-handed |
| `shoot_pistol` | ~12 | base | torso aim, head aim | Trigger pull only — no recoil baked |
| `shoot_shotgun` | ~12 | base | torso aim, head aim, hand_l | Trigger pull only |
| `pump_shotgun` | ~24 | base | torso aim, head aim, hand_l | Off-hand pump-action; deferred from Phase 3 |
| `reload_pistol` | ~45 | base | head | Speed-loader (matches existing `reload_time = 1.5s` in `weapon_revolver.gd`) |
| `reload_shotgun` | ~75 | base | head | Per-shell loading; loop the per-shell segment for `max_ammo` repeats |
| `recoil_pistol` | ~10 | additive | none | Spine + arms kick back; intensity-driven |
| `recoil_shotgun` | ~12 | additive | none | Heavier kick |

**Resolved:** Revolver fan-fire is **out of 3.5 scope.** Author when the relevant power-up card lands in Phase 5 (Game Modes + Cards) — wiring it into the base mechanic now would either sit unused or contradict the card design.

### Group G — Equip / swap / drop

Currently weapon swap is instant — feels teleporty. **MVP scope:** equip + drop only; holster animations skipped. Players notice the weapon coming out far more than the weapon going away. Add holsters later if swap reads as too snappy on the "from" side.

| Name | Frames | Layer | IK-aware | Notes |
|---|---|---|---|---|
| `equip_melee` | ~24 | base | none | Reach to hip, draw |
| `equip_ranged` | ~24 | base | none | Reach to back/holster, draw |
| `equip_fists` | ~12 | base | none | Quick to-stance, no weapon |
| `drop_weapon` | ~18 | base | none | Played by `_disable_arm_side()` before world pickup spawns |

### Group H — Hit reacts (additive overlays)

Brief additive deltas that pulse on damage events. Authored as 6–10 frame clips with Influence ramping up then back to zero — but the ramp is in Godot (`AnimationNodeOneShot` fade), so the Blender clip is just the peak motion.

| Name | Frames | Layer | IK-aware | Notes |
|---|---|---|---|---|
| `hit_torso_front` | ~10 | additive | none | Spine flexion + head jerk back |
| `hit_torso_back` | ~10 | additive | none | Spine extension + head jerk forward |
| `hit_head` | ~10 | additive | none | Head whip; spine follows lightly |
| `hit_arm_r` | ~8 | additive | none | Arm recoil only |
| `hit_arm_l` | ~8 | additive | none | |
| `hit_leg_r` | ~8 | additive | feet | Subtle limp; foot IK still active |
| `hit_leg_l` | ~8 | additive | feet | |
| `stagger_heavy` | ~30 | base | head, feet | Full-body — replaces base, not additive. Used for big hits or pre-death. |

### Group I — Jump / fall / land

| Name | Frames | Layer | IK-aware | Notes |
|---|---|---|---|---|
| `jump_start` | ~10 | base | feet | Crouch + push-off |
| `jump_air` | ~30 loop | base | head | Foot IK off; legs tucked or trailing |
| `land_soft` | ~12 | base | feet | Small-fall recovery |
| `land_hard` | ~24 | base | feet | Big-fall recovery — knees bent deep, hands forward |

### Group J — Death and idle layers

| Name | Frames | Layer | IK-aware | Notes |
|---|---|---|---|---|
| `death_collapse` | ~10 | base | none | Brief animated lead-in; on last frame, `PhysicalBoneSimulator3D` takes over with current pose as initial state |
| `breathe_idle` | ~120 loop | additive | none | Always-on layer over every grounded base; small chest/shoulder rise |

## 6. Total clip count

- Group A: 8
- Group B: 16
- Group C: 5
- Group D: 11
- Group E: 20
- Group F: 9
- Group G: 4
- Group H: 8
- Group I: 4
- Group J: 2

**Total: 87 clips** (vs. 14 currently). Roughly 14 are existing-and-redo, 73 are new.

## 7. Blender authoring rules

### Frame rate
- 30 fps. Match `animation/fps=30` in `player_rig.glb.import`.
- Start at frame 1, end at the last meaningful pose.

### Cyclic loops
- For looping clips, frame 1 must equal final frame numerically (copy keys).
- Don't rely on Blender's cyclic F-curve modifier — it doesn't bake into glTF output.

### In-place authoring
- Pelvis (`torso_bottom`) does not translate forward in any locomotion clip. World motion comes from CharacterBody3D in `player.gd`.
- Pelvis can bob vertically and side-to-side per gait — that motion *is* what sells the locomotion.

### IK-aware authoring (recap of §2)
- Listed per-clip in the inventory tables. For any "IK-aware" bone on a given clip:
  - Don't tightly key the rotation toward a specific target.
  - Provide neutral or near-neutral pose; runtime modifier blends a delta on top.
  - Test in Godot with the modifier disabled to confirm the baseline still reads.

### Additive clips
- Authored normally in Blender — the "additive" property is set in Godot's AnimationTree (`AnimationNodeAdd2`), not in the action format.
- Keep deltas small and meaningful (e.g., `lean_r` ≈ 15° spine roll, no leg motion).

### Pose markers
- Add Pose Markers in the Action editor at `hit_active`, `hit_end`, and any other timing-significant frames.
- These don't export to glTF but make per-clip review and timing audits possible without scrubbing.

### Variation
- Attack `_a` / `_b` variants share total length and hit frame; vary wind-up + follow-through only.
- Idle variants ~3–5s each, one obvious fidget per variant at staggered times.

### Naming
- snake_case. Action name in Blender = animation name in Godot.
- Group prefixes per inventory: `idle_`, `walk_`, `run_`, `crouch_`, `prone_`, `hobble_`, `crawl_`, `hold_`, `atk_`, `aim_`, `shoot_`, `reload_`, `recoil_`, `pump_`, `equip_`, `holster_`, `drop_`, `hit_`, `stagger_`, `jump_`, `land_`, `death_`, `breathe_`, `lean_`.

## 8. IK control rig handling

Use whatever control rig accelerates authoring (Rigify, custom IK, foot rollers, root, weapon master), but **the exported skeleton must contain only the 14 deform bones** with no constraints.

Two valid workflows:

**Workflow A — bake-and-export.** Build IK rig in the same armature using Bone Constraints. Before export: select all deform bones → `Object → Animation → Bake Action` with Visual Keying ON, Clear Constraints ON, Only Selected Bones ON. Export the baked action.

**Workflow B — separate control armature.** Control rig lives in its own armature with constraints driving the deform armature via Copy Transforms. Bake before export same as A.

Either way, the deform skeleton in the .glb has no IK constraints — Godot does IK at runtime on the deform bones.

## 9. Export checklist (glTF 2.0)

- Apply all transforms in object mode (Ctrl+A → All Transforms) on every armature and mesh
- File → Export → glTF 2.0 (.glb)
- Format: `glTF Binary (.glb)`
- Include → Selected Objects: armature + skinned mesh
- Animation → enabled
  - Mode: `Actions` (each action exports as a named track — names carry through to Godot)
  - Always Sample Animations: ON
  - Group by NLA Track: OFF (we want individual actions)
- Skinning: ON, Bone Influences = 4
- Apply Modifiers: ON
- Triangulate: optional (Godot triangulates on import)

After export, in Godot: re-import `player_rig.glb`. New animations appear in the AnimationPlayer tracks list. AnimationTree references them by name.

## 10. Suggested authoring order

Each tier validates the previous tier's foundations. Don't jump ahead.

### Milestone 1 — locomotion baseline ✅ COMPLETE (2026-05-10)
- ✅ Authored Group A in full — 8 locomotion clips (`idle_a`, `idle_b`, `idle_c`, `walk` @ 30f, `run` @ 22f, `walk_back` @ 32f, `strafe_l`, `strafe_r`) plus `breathe_idle` additive
- ✅ AnimationTree + BlendSpace2D wired across `scenes/player.tscn`, `scenes/brawler.tscn`, `scenes/dummy.tscn` — handoff brief at `phase_3_5_m1_godot_wiring_brief.md`
- ✅ Idle randomization wired — state machine cycles between `idle_a`/`b`/`c` with random end-of-clip transitions
- ✅ Foot IK, breathe additive (always-on), and `LookAtModifier3D` × 2 (head_bottom + head_top) implemented
- ✅ Validation passed — locomotion blends cleanly, IK works on staircase test scene, head tracks camera, breath visible at idle, no regressions in Phase 2/3 dismemberment
- **Known follow-up:** Godot's glTF importer defaults imported animations to `LOOP_NONE`. Runtime fix in `anim_tree_setup.gd` sets `loop_mode = LOOP_LINEAR` on the 9 M1 clips by name. Plan to refactor to a global iterator (with an explicit non-loop exclusion list for one-shots) before M3 attacks land — at ~80 more clips, the curated list becomes brittle.

### Milestone 2 — gait edge cases
- Author Group B (crouch, prone, lean) and Group C (injury locomotion)
- Validates the in-place + foot-IK approach across edge gaits including foot-IK-off states (prone, crawl)
- **Implements hand-plant IK solver** alongside foot IK — required for `prone_crawl_fwd/back` and `crawl_legs_lost`. Per-arm chain (`arm_*_upper → arm_*_fore → hand_*`) targets ground raycast hit. Same architecture as foot IK, applied to arms.
- Lean additive validates the additive layer pipeline

### Milestone 3 — stance hold poses
- Author Group D as upper-body additives
- Validates the additive overlay for combat — every locomotion variant should now be able to play with any weapon hold pose layered over it

### Milestone 4 — melee combat
- Author Group E `_a` variants only across all weapons + stances
- Playtest against dummies; tune timing if hit feel is off
- Author `_b` variants only after `_a` set is validated

### Milestone 5 — ranged
- Author Group F
- Wire spine-aim modifier, recoil additive, off-hand IK for shotgun/pump

### Milestone 6 — reactions and transitions
- Author Group H (hit reacts), Group G (equip/swap/drop)

### Milestone 7 — air states and death
- Author Group I (jump/fall/land), Group J (death, breathe)

## 11. Resolved decisions (locked 2026-04-26)

All eight open questions from initial planning are resolved. Recorded here so future authoring sessions don't relitigate.

1. **Run cadence — separate run cycle.** Walk authored at ~26f, run at ~18f. Validated against SPEED 5.0 / SPRINT_MULT 1.6 (run = 8.0 m/s).
2. **Punch variants — 6 clips (R/L per stance).** Hand alternation provides silhouette variety. Revisit if unarmed combat reads repetitively in playtest.
3. **Hand IK on prone-crawl — runtime IK.** Build hand-plant solver per-arm; author hands relaxed in keys.
4. **Hand IK on `crawl_legs_lost` — runtime IK.** Same solver as #3.
5. **Revolver fan-fire — out of 3.5 scope.** Author when the relevant card lands in Phase 5.
6. **Reload pistol — speed-loader, ~45f.** Matches existing `reload_time = 1.5s`.
7. **Equip/holster — MVP only.** `equip_melee`, `equip_ranged`, `equip_fists`, `drop_weapon`. No holster clips. Add later if swap feels snappy.
8. **Stagger — full-body base clip.** `stagger_heavy` is a tactical interrupt, not a flinch. Gate behind a damage-threshold trigger.

## 12. References

- GDD: `Voxel_Brawl_Game_Design_Document_v2.md` §Phase 3.5 (animation rework section)
- Architecture: `architecture.md` §7 (Limb System), §8 (Weapon System), §16 (Signal Map)
- Current animation triggering: `player.gd:394–406` (`play_attack_anim`), `player.gd:259/261` (locomotion play)
- Stance system: `player.gd:355` (`_update_stance_for_weapon`), `weapon_melee.gd` stance keys
- Hit-window timing constants: each `weapon_*.gd`'s `hit_enable_delay` and `hit_window_duration`
- Leg-loss tier mapping: `player.gd:531–545` (`_leg_loss_speed_multiplier`)
