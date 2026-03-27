# VOXEL BRAWL

## Game Design & Development Plan
*Multiplayer Voxel Combat with Power-Up Cards*

**Target: Playable Prototype in 1–3 Months**
Platforms: Windows & macOS | Players: Up to 8 | Online (Direct IP)

*v3.1 — Updated with 14-bone hierarchy, hand segments, cascade detachment system, and segment state machine (BROKEN/DETACHED)*

---

## 1. Game Vision & Elevator Pitch

Voxel Brawl is a multiplayer voxel-based arena combat game for up to 8 players. Think Paint the Town Red's satisfying voxel dismemberment meets the stackable power-up card system from Rounds, viewed from a top-down perspective with fog-of-war vision — like Minecraft Dungeons meets Darkwood's tension. Players fight through multiple game modes — from free-for-all brawls to co-op NPC wave survival — using scavenged weapons, environmental hazards, and increasingly wild power-up card combinations.

The core appeal: every hit feels crunchy because voxel chunks fly off characters, limbs detach, and the arena gets painted with blocky carnage. The fog-of-war means you can't see around corners — enemies can ambush you from behind walls, and the tension of not knowing what's lurking just out of sight keeps every moment dangerous. The card system means no two matches play the same way.

---

## 2. Recommended Engine: Godot 4

After weighing your experience level, budget (free tools only), and cross-platform needs (Windows + Mac), Godot 4 is the strongest choice. Here's why:

| Criteria | Godot 4 | Unity | Unreal 5 |
|---|---|---|---|
| Price | 100% free, MIT license | Free tier, runtime fee | Free until $1M revenue |
| Language | GDScript (Python-like) | C# | C++ / Blueprints |
| Learning Curve | Gentle, great docs | Moderate | Steep |
| Cross-Platform | Win + Mac + Linux | Win + Mac + Linux | Win + Mac (limited) |
| Networking | Built-in ENet + scenes | Netcode for GameObjects | Replication system |
| Voxel Suitability | Good (SurfaceTool + MeshInstance3D) | Good (mesh API) | Overkill for this style |
| Community | Growing fast | Largest | Large but AAA-focused |

Godot 4 wins on simplicity, cost, and having built-in multiplayer primitives. GDScript reads almost like Python, which is ideal for your experience level. Its scene-based architecture also maps perfectly to spawning players, weapons, and NPCs.

---

## 3. Complete Free Tool Stack

### 3a. Programming & Engine

| Tool | Purpose | Why This One |
|---|---|---|
| Godot 4.3+ | Game engine | Free, cross-platform, built-in networking |
| VS Code | Code editor (optional) | godot-tools extension for GDScript |
| Git + GitHub | Version control | Track changes, collaborate, free private repos |

### 3b. 3D Modeling & Voxel Art

> **[UPDATED]** Because this game uses runtime voxel destruction (Paint the Town Red style), the art pipeline uses two parallel tracks that merge in Godot, rather than a single linear chain.

**Track 1 — Voxel Data (character appearance):** MagicaVoxel → Godot directly

Design characters in MagicaVoxel. Export .vox files (or convert to JSON). Load as raw voxel grid data in Godot. The visible character mesh is generated at runtime using SurfaceTool, which enables per-voxel destruction. Do NOT export baked OBJ meshes for destructible characters.

**Track 2 — Skeleton & Animations:** Blender → Godot (.glb export)

Build the armature (skeleton) and all animations in Blender — walk, run, attack swings, idle, stumble, death. Export as glTF 2.0 (.glb). In Godot, the runtime-generated voxel meshes attach to skeleton bones so the character animates properly. Each body segment (head, torso, arms, legs) maps to a bone.

| Tool | Purpose | Why This One |
|---|---|---|
| MagicaVoxel | Character voxel data + non-destructible model creation | Free, intuitive. Export .vox for character data, OBJ for static props |
| Blender | Rigging, animation, skeleton creation | Industry standard, free. Export armatures + anims as .glb for Godot |
| Goxel | Alternative voxel editor | Open source, runs everywhere, good for quick iteration |
| Blockbench | Weapons, items, non-destructible props | Free, designed for block-style models. Can also rig simple bone setups |

**Pipeline summary for destructible characters:** Design look in MagicaVoxel → Build skeleton + animations in Blender → Both merge in Godot (voxel data attaches to skeleton bones) → Mesh is generated at runtime by SurfaceTool.

**Pipeline for static props / weapons / environment:** Model in MagicaVoxel or Blockbench → Export OBJ → (Optional) UV/rig in Blender → Export .glb → Import into Godot as regular MeshInstance3D.

### 3c. Audio & Music

| Tool | Purpose | Why This One |
|---|---|---|
| Audacity | Sound effects editing | Free, record and edit punches/impacts/splats |
| sfxr / jsfxr | Retro sound effects | Generate 8-bit style hits, explosions, power-ups in seconds |
| LMMS | Music composition | Free DAW for creating cartoon-style background tracks |
| Freesound.org | Sound library | Creative Commons sound effects library |

### 3d. Textures & 2D Art

| Tool | Purpose | Why This One |
|---|---|---|
| GIMP | Texture painting, UI art | Free Photoshop alternative, great for palettes/textures |
| Aseprite* | Card art, pixel UI | $20 or free if you compile from source (open source) |
| Lospec Palette | Color palettes | Free curated palettes — pick one for your cartoon style |

---

## 4. Game Modes — Design Breakdown

### Mode 1: Free-For-All Deathmatch

- 8 players, timed rounds (3–5 minutes)
- Most kills wins. Respawn after 5 seconds.
- Weapons spawn on the map on timers
- Card system: Pick 1 of 3 random cards between each round
- Best of 5 rounds — cards stack across rounds

***This is your prototype mode. Build this first.***

### Mode 2: Team vs Team

- 4v4, same round structure as FFA
- Team with most total kills wins the round
- Card picks are individual — team coordination emerges naturally
- Variation: Capture-the-flag or king-of-the-hill objectives (post-prototype)

### Mode 3: Co-op Wave Survival

- 2–8 players vs NPC waves of increasing difficulty
- Waves get harder: more NPCs, tougher types, new attack patterns
- Card system: Everyone picks a card between waves
- Survive as long as possible — leaderboard tracks best wave reached
- NPCs drop weapons and health pickups

### Mode 4: Battle Royale

- 8 players, single life, shrinking arena
- Cards are found as floor loot (no between-round picking)
- Weapons scattered across a larger map
- Last player standing wins
- Shrinking zone forces encounters — simple circle that closes over time
- Build this mode last — it needs the most map/balance work

---

## 5. Camera & Field-of-Vision System [NEW]

> **[NEW]** The game uses a locked top-down isometric camera with a fog-of-war field-of-vision system. Players can only see what their character could realistically see — walls and obstacles block line of sight, creating tension, ambush opportunities, and tactical play.

### Camera Setup

- **Perspective:** Fixed top-down, angled slightly (~60° from horizontal) for depth — similar to Minecraft Dungeons or classic ARPGs
- **Rotation:** Camera does not rotate. Fixed orientation for all players ensures consistent map readability
- **Zoom:** Fixed zoom level tuned for arena readability. Character should be clearly visible but the arena should feel spacious
- **Control:** WASD moves the character; mouse aims/faces the character's direction. The camera follows the player smoothly with slight lag for juice

### Fog-of-War Vision System

The core mechanic: each player has a **circular vision radius** around their character. Within that radius, line-of-sight raycasting determines what's actually visible. Walls, pillars, and obstacles block vision realistically — you cannot see around corners or through walls.

**How it works:**

- **Vision radius:** A base circle (e.g. ~12 voxel-units radius) around the player defines the maximum possible vision range
- **Raycasting:** From the player's position, cast rays outward in all directions (e.g. 360 rays, one per degree). Each ray stops when it hits a wall or obstacle. The visible area is the union of all ray endpoints — this creates the organic, shadow-casting FOV shape
- **Outside FOV = completely invisible:** Enemies, other players, weapons, NPCs — anything outside your field of vision is fully hidden. No silhouettes, no hints. This is critical for ambush gameplay
- **Inside FOV = fully lit and visible:** Everything within line of sight renders normally

**Rendering approach (Godot 4):**

- Use a **shader on a full-screen overlay** or a **Light2D/Light3D cookie approach** to mask the non-visible area
- The FOV polygon is calculated each frame from raycasts and passed to the shader as a texture or mesh
- Non-visible areas render as solid black (or a very dark fog) — the world geometry is still there but completely obscured
- Alternatively, use Godot's **CanvasModulate** or a custom viewport shader that composites the FOV mask

**Performance notes:**

- 360 raycasts per frame is cheap in Godot's physics engine, especially in small arenas
- Only the local player's FOV needs to be calculated — other players' FOV is irrelevant to your rendering
- The FOV shape only needs recalculating when the player moves or when the environment changes (destructible walls crumbling)

### Vision Radius: Base + Card Modifiers

The vision radius uses a fixed base value that can be modified by specific cards:

- **Base radius:** ~12 units (tuned during playtesting — should feel generous enough to fight comfortably but restrictive enough that corners and corridors feel dangerous)
- **Card modifiers:** Certain cards can increase or decrease the radius (see Vision Cards in Section 8)
- **No other modifiers in v1:** Keep it simple for the prototype. Environmental lighting variations (dark rooms, lit rooms) can be added post-prototype

### Team Vision (Co-op / Team Modes)

In team-based modes (Team vs Team, Wave Survival), teammates share vision with a dimming effect:

- **Your own FOV:** Fully bright, normal rendering
- **Teammate FOV:** Visible but rendered darker/desaturated — you can see the area but it's clearly "their" vision, not yours
- **Outside all team FOV:** Completely black, fully hidden

This encourages sticking together while still rewarding scouting and flanking. Technically, each client receives teammate positions and computes their FOV polygons as secondary masks rendered at reduced brightness.

### Impact on Gameplay

The FOV system fundamentally changes how the game plays compared to a standard top-down brawler:

- **Ambushes are possible:** Hide behind a wall, wait for an enemy to walk past, strike from their blind spot
- **Corners are dangerous:** Rounding a corner into an unknown area creates genuine tension
- **Destructible walls affect vision:** Smashing through a wall doesn't just create a path — it opens a sightline. This makes the voxel destruction system serve a tactical purpose, not just a visual one
- **Ranged vs melee tradeoff deepens:** Ranged weapons are more valuable because you might spot enemies at the edge of your FOV before they see you
- **Wave survival becomes scarier:** NPCs spawning outside your vision and flooding in from the darkness sells the survival horror feel

### Technical Approach (Godot)

- Use `PhysicsDirectSpaceState3D.intersect_ray()` for raycasting against wall collision shapes
- Build the FOV polygon from ray endpoints each frame
- Render the FOV mask using either: (a) a viewport texture composited over the scene, or (b) a shader that reads the FOV polygon as vertex data
- For team vision: compute additional FOV polygons from teammate positions, composite at reduced opacity
- Destructible walls must update their collision shapes when voxels are removed, so FOV raycasts correctly pass through destroyed sections

---

## 6. Voxel Combat & Dismemberment System

> **[UPDATED]** This is the core of the game's feel, and the most technically demanding system. The goal is Paint the Town Red-style granular voxel destruction: every hit carves a unique shape out of the character, voxel cubes fly off, and limbs eventually detach when enough damage accumulates.

### Runtime Voxel Architecture [UPDATED]

**Characters are stored as voxel data, not static meshes.** Each body segment is a 3D array/Dictionary where each entry represents a colored voxel (or empty space). The visible mesh is generated at runtime using Godot's SurfaceTool, which builds geometry by creating a quad for every exposed voxel face. This is what enables per-voxel destruction — you can't carve chunks out of a pre-baked mesh.

### Character Construction

Each character is built from a voxel grid (e.g. 16x32x16 voxels for a humanoid). The model is divided into body segments, each with its own voxel grid attached to a skeleton bone in Godot:

- Head (detachable) — own voxel grid, attached to head bone
- Torso (core — when destroyed, character dies) — largest voxel grid
- Left Arm / Right Arm (can be severed) — own grids on arm bones
- Left Leg / Right Leg (severed = movement penalty) — own grids on leg bones

### How Voxel Data Works [UPDATED]

- **Storage:** Each body segment stores a Dictionary mapping Vector3i positions to color values. Example: `{Vector3i(0,0,0): Color.RED, Vector3i(1,0,0): Color.RED, ...}`
- **Mesh generation:** SurfaceTool iterates the voxel data. For each voxel, it checks all 6 neighbors — if a face is exposed (neighbor is empty or out of bounds), it creates a quad for that face with the voxel's color as vertex color.
- **On hit:** Calculate which voxels are within the hit radius. Remove them from the Dictionary. Regenerate the mesh for that body segment only. Spawn the removed voxels as visual debris.
- **Performance:** Only rebuild the mesh for the body segment that was hit. Batch all hits within 0.1 seconds into one rebuild. Each segment is small enough (~500–2000 voxels) that regeneration takes under 1ms.

### Damage Model

When a hit connects, the system does three things simultaneously:

- **Voxel destruction:** Remove voxels within the impact radius from the body segment's data. Rebuild that segment's mesh via SurfaceTool. Spawn removed voxels as debris (see particle tiers below).
- **Limb HP check:** Track remaining voxel count per body segment. When a limb drops below a threshold (e.g. 30% remaining voxels), it detaches as a separate physics object with its own remaining voxel grid — still destructible while flying through the air.
- **Gore painting:** Surfaces near the hit get "painted" with the character's color (decal system or vertex color painting on the arena floor/walls).

### Particle Debris Tiers [UPDATED]

Not every ejected voxel needs full physics simulation. Use a tiered approach for performance:

- **Tier 1 — Physics cubes (5–10 per hit):** The largest/nearest voxels become RigidBody3D nodes. They bounce, roll, and collide with the environment. These sell the impact.
- **Tier 2 — GPU particles (20–40 per hit):** Use GPUParticles3D with a small cube mesh and randomized velocities. They look like flying voxels but cost almost nothing. No collision.
- **Tier 3 — Color splash (unlimited):** Decals or vertex color paint at the hit point. Zero ongoing cost.

With 8 players and fast weapons, expect up to 100+ visual particles simultaneously. The tiered approach keeps actual physics bodies manageable (~40–80 active RigidBody3D cubes at peak) while the GPU particles handle the visual density.

### Technical Approach (Godot) [UPDATED]

- Each character = CharacterBody3D with Skeleton3D (imported from Blender .glb)
- Each body segment = a script-controlled node with its own voxel Dictionary + MeshInstance3D
- MeshInstance3D mesh is generated at runtime by SurfaceTool from the voxel data
- Voxel data loaded from MagicaVoxel .vox files (parsed in GDScript or pre-converted to JSON)
- On dismember: detach the body segment node, add RigidBody3D, apply force. The detached limb keeps its voxel grid and remains destructible
- Use object pooling for debris cubes — pre-spawn ~100 small cube RigidBody3Ds and reuse them
- Network sync: Only sync hit events (position + radius + damage). Each client removes voxels and rebuilds locally. Don't sync every particle or mesh rebuild.

### Visual Style & Shaders [UPDATED]

Voxel art requires a specific rendering approach for readability and style. Decide this early as it affects how materials are set up:

- **Flat shading:** No smooth normals. Each voxel face should have a hard edge. Set this in the SurfaceTool mesh generation (use face normals, not smooth normals).
- **Vertex colors:** Color comes from the voxel data itself, not UV-mapped textures. This simplifies the pipeline enormously — no texture painting needed.
- **Outline shader (optional):** A thin black outline shader improves character readability at distance, especially in 8-player chaos. Godot 4's visual shaders make this straightforward.
- **Unlit or cel-shaded:** Pick one and commit. Unlit is simplest, cel-shading adds depth. Both work well with the cartoon aesthetic.

### Estimated Scope: Runtime Voxel Engine [UPDATED]

The runtime voxel system is approximately 500–800 lines of core GDScript covering: voxel grid storage, SurfaceTool mesh generation, hit detection and voxel removal, debris spawning with tiered particles, and .vox file parsing. This is the hardest single system in the game. Prototype it first before touching anything else in the roadmap.

---

## 7. Weapons & Tools

Start with 8–10 weapons for the prototype, expandable later. Each weapon should feel distinct in range, speed, and dismemberment potential:

### Melee Weapons

| Weapon | Damage | Speed | Range | Special |
|---|---|---|---|---|
| Fists | Low | Fast | Short | Always available, knockback |
| Baseball Bat | Medium | Medium | Medium | Home run hit sends enemies flying |
| Katana | High | Fast | Medium | Clean limb cuts, bleed effect |
| Sledgehammer | Very High | Slow | Medium | Area smash, massive voxel destruction |
| Chainsaw | DPS | Continuous | Short | Hold to shred — rapid voxel removal |

### Ranged Weapons

| Weapon | Damage | Fire Rate | Ammo | Special |
|---|---|---|---|---|
| Revolver | High | Slow | 6 shots | Precise, can headshot-dismember |
| Shotgun | Spread | Slow | 2 shells | Close range devastation, multi-limb hits |
| Grenade | Area | Thrown | 1 use | Explosion sends voxels everywhere |
| Crossbow | Medium | Medium | 5 bolts | Bolts pin limbs to walls |

### Environmental / Throwables

- Chairs, bottles, trash cans — grab and throw anything not bolted down
- Exploding barrels — shoot or throw for area damage
- Spike traps, swinging pendulums, crushers — map hazards that affect everyone

---

## 8. Power-Up Card System

The card system is your game's secret weapon for replayability. Cards stack, so wild combos emerge over multiple rounds. Here's the design:

### How Cards Work Per Mode

| Mode | Card Delivery | Details |
|---|---|---|
| FFA / Team | Pick between rounds | Choose 1 of 3 random cards. Cards persist + stack all game. |
| Wave Survival | Pick between waves | Same as above but shared card pool visible to team |
| Battle Royale | Floor loot | Find card pickups on the map. Auto-apply on pickup. |

### Starter Card List (34 Cards)

Cards are divided into tiers: Common (green), Rare (blue), Epic (purple), Legendary (gold).

**OFFENSIVE CARDS**

- Glass Cannon (Common) — +50% damage dealt, +50% damage taken
- Vampiric Strikes (Rare) — Heal 10% of melee damage dealt
- Explosive Fists (Rare) — Unarmed hits cause small explosions
- Ricochet Rounds (Epic) — Bullets bounce off walls once
- Berserker (Epic) — Deal more damage the lower your health
- Dismemberer (Legendary) — All hits have 2x limb damage
- Rapid Fire (Common) — +30% attack speed, -15% damage
- Critical Voxels (Rare) — 10% chance hits remove 3x voxels

**DEFENSIVE CARDS**

- Thick Skin (Common) — -20% damage taken
- Second Wind (Rare) — Revive once per round with 30% HP
- Iron Limbs (Rare) — Limbs take 50% more hits before dismemberment
- Dodge Roll (Common) — Double-tap direction to i-frame dodge
- Regeneration (Epic) — Slowly heal over time (1 HP/sec)
- Voxel Armor (Legendary) — Absorb first 3 hits completely
- Adrenaline Rush (Rare) — Move 30% faster for 3 sec after taking damage

**UTILITY CARDS**

- Magnetic (Common) — Weapons/pickups gravitate toward you
- Speed Demon (Common) — +25% movement speed
- Double Jump (Rare) — Exactly what it sounds like
- Scavenger (Common) — Killed enemies drop extra weapon ammo
- Teleport Strike (Epic) — Short-range teleport replaces dodge
- Ghost Limbs (Legendary) — Dismembered limbs still function as translucent ghosts
- Big Head Mode (Common) — All players get big heads. +50% headshot hitbox

**VISION CARDS [NEW]**

- Eagle Eye (Rare) — +40% vision radius
- Tunnel Vision (Common) — +60% vision radius in the direction you're facing, -30% behind you (FOV becomes a wide cone instead of a circle)
- Sixth Sense (Epic) — Brief silhouette flash of enemies within 2 units outside your FOV (gut instinct warning)
- Blackout (Legendary) — All OTHER players' vision radius reduced by 30% for the rest of the match. Stacks.

**CHAOS / FUN CARDS**

- Bouncy (Rare) — You bounce off surfaces like a rubber ball
- Tiny Terror (Epic) — Shrink to 50% size. Harder to hit, less knockback resistance
- Hot Potato (Rare) — Carry an invisible bomb. Pass it by hitting someone. Explodes in 10s
- Mirror Match (Epic) — Copy one random card from your last attacker
- Gravity Flip (Legendary) — Reverse gravity for 5 seconds on kill
- Friendly Fire (Common) — Your hits heal allies instead of damaging them (team mode only)

---

## 9. NPC System (Wave Survival + Battle Royale)

NPCs populate wave survival mode and can optionally appear in battle royale as hazards.

### NPC Types

| Type | Health | Speed | Attack | Behavior |
|---|---|---|---|---|
| Brawler | Low | Medium | Punches | Charges at nearest player |
| Bruiser | High | Slow | Heavy swings | Tanks hits, wide AoE attacks |
| Runner | Very Low | Fast | Quick jabs | Flanks, attacks from behind |
| Bomber | Low | Medium | Self-destruct | Charges then explodes into voxels |
| Sniper | Low | Static | Ranged shots | Stays at distance, shoots players |
| Tank | Very High | Very Slow | Ground pound | Mini-boss every 5 waves. Shockwave attack. |
| Swarm | Tiny | Fast | Nibbles | Spawn in packs of 10+, overwhelm |

### Wave Scaling

- Waves 1–5: Brawlers and Runners only. Learn the basics.
- Waves 6–10: Add Bruisers and Bombers. Introduce area threats.
- Waves 11–15: Snipers join. Players must manage range + melee.
- Wave 15+: Tank mini-bosses every 5 waves. Swarms between bosses.
- Enemy count scales with player count: base × (1 + 0.3 per extra player)

---

## 10. Networking Architecture

You're going with direct IP connect, which simplifies infrastructure. Here's how it works in Godot 4:

### Architecture: Authoritative Host

One player acts as the host (server + client). Other players connect via IP:port. The host is authoritative — it resolves all combat, spawns, and game state.

- Host creates an ENetMultiplayerPeer on a chosen port (default: 7000)
- Clients connect via the host's IP address + port
- Use Godot's MultiplayerSpawner for syncing player/NPC/weapon spawns
- Use MultiplayerSynchronizer for position, rotation, animation state
- RPCs (Remote Procedure Calls) for events: damage dealt, card picked, round state changes

### What to Sync vs. What to Keep Local

| Sync (Server → All Clients) | Local Only (Each Client) |
|---|---|
| Player positions + rotation | Particle effects (voxel chunks) |
| Damage events + dismemberment | Camera shake, screen flash |
| Weapon spawns + pickups | UI state, menu navigation |
| NPC positions + states | Sound effects (triggered by synced events) |
| Card picks + active effects | Gore decals (painted locally from synced hit data) |
| Round/wave state, scores | Post-processing, settings |
| Teammate positions (for shared FOV) | FOV calculation + rendering (computed locally per client) |

### Voxel Sync Strategy [UPDATED]

With runtime voxel destruction, syncing the voxel state efficiently is critical. The server does NOT send full voxel grids — instead it syncs hit events only:

- **Server sends:** Hit position (Vector3), hit radius (float), damage amount, target body segment ID
- **Each client receives the hit event and locally:** removes voxels within the radius, rebuilds the mesh for that body segment, spawns particle debris
- This means voxel states may differ very slightly between clients (floating point differences in radius checks), but this is invisible in practice
- Dismemberment events (limb detaches) are synced explicitly by the server since they affect gameplay

### Port Forwarding Note

For friends to connect over the internet, the host will need to port-forward (or use a tool like Hamachi / ZeroTier for virtual LAN). Document this in a simple setup guide for your friends.

### Multiplayer-First Code Pattern [UPDATED]

Even in Phase 1 (single-player prototype), structure code with `multiplayer.is_server()` checks from the start. This prevents a painful refactor when adding multiplayer in Phase 3. For example, damage calculations should always run on the server and broadcast results, even when the "server" is just the local player.

---

## 11. Development Roadmap (Prototype in 1–3 Months)

### Phase 0: Voxel Engine Prototype (Weeks 1–2) [UPDATED] ✅ COMPLETE

**Goal: A single destructible voxel character you can hit and carve.**

This is new — prototype the hardest system first before building anything else.

- ✅ Set up Godot project + Git repo
- ✅ Write the voxel grid data structure (Dictionary of Vector3i → Color)
- ✅ Implement SurfaceTool mesh generation from voxel data (flat shading, vertex colors)
- ✅ Load a test character from a MagicaVoxel .vox file
- ✅ Implement hit detection: click on character, remove voxels in a radius
- ✅ Spawn debris cubes (tiered: RigidBody3D for big chunks, GPUParticles3D for small ones)
- ✅ Rebuild mesh after voxel removal — verify performance is acceptable
- ✅ Test with a 16x32x16 character to validate the approach works

### Phase 1: Foundation (Weeks 3–5) ✅ COMPLETE

**Goal: A single character moving in a voxel arena with basic melee.**

- ✅ Create a simple flat arena (textured floor, walls)
- ✅ Build character skeleton + animations in Blender, export as .glb (walk, idle, punch, shoot)
- ⏭️ Attach runtime voxel meshes to skeleton bones in Godot — deferred to Phase 2; player currently uses static Blender mesh. Requires NPC enemies to be meaningful to implement and test.
- ✅ Implement WASD movement + mouse aim with fixed top-down camera
- ✅ Basic punch attack with collision detection
- ✅ Voxel chunk destruction on hit (using the Phase 0 system)
- ✅ Set up flat shading for visual style (outline shader deferred — optional)
- ✅ **[NEW]** Implement fog-of-war FOV system: raycast-based vision cone (120°, 12-unit radius) with wall occlusion, world-space depth-reconstruction shader, enemy visibility toggling
- ✅ **[NEW]** FOV shader/overlay: non-visible areas rendered as dark fog via full-screen spatial shader on D3D12/Vulkan

### Phase 2: Combat + Dismemberment (Weeks 6–8)

**Goal: Full dismemberment system + 4–5 weapons working + player mobility + destructible player.**

**Character Foundation (do first — everything else is tuned against this)**

Build the final character art now so that all destruction tuning, weapon positioning, and animation polish is based on a finalized foundation. The 14-bone hierarchy is modelled and rigged here; the code to support it is wired up in Phase 3.

*Flesh segments (visible, destructible):*
- Model 14 flesh .vox segments in MagicaVoxel matching the 14-bone hierarchy: torso_bottom, torso_top, head_bottom, head_top, arm_r_upper, arm_r_fore, **hand_r**, arm_l_upper, arm_l_fore, **hand_l**, leg_r_upper, leg_r_fore, leg_l_upper, leg_l_fore
- Export each as a .vox file — do NOT export as OBJ. Voxel data must remain raw for runtime destruction.
- Flesh segments should have a consistent skin color palette
- Hands (`hand_l`, `hand_r`) double as the weapon holder attachment points — losing a hand disables weapon equipping for that side (two-handed weapons require both hands intact)

*Inner bone segments (hidden until flesh is carved away):*
- Model 14 matching bone .vox segments in MagicaVoxel — one per flesh segment, same shape but smaller, painted in a distinct bone color (off-white/yellow)
- These sit inside the flesh segments and become visible as voxels are removed
- Export each as a .vox file

*Blender rig:*
- Build a 14-bone skeleton in Blender matching the hierarchy below. Bone names must match exactly — they are used as keys in `PLAYER_SEGMENT_CONFIG`.
- The `weapon-right` and `weapon-left` attachment bones are replaced by the `hand_r` and `hand_l` bones — weapons attach directly to the hand bones
- Add all required animations: idle, walk, punch (melee attack), holding-right (ranged idle), holding-right-shoot (ranged fire), plus distinct animations for bat swing and katana slash
- Export as .glb

*Integration (Phase 2 — uses existing 6-segment code as placeholder):*
- Replace the current Kenney `character-a.glb` placeholder with the new rig in `player.tscn`
- Map the 6 main segments (torso_bottom, skull_top, arm_l_upper, arm_r_upper, leg_l_upper, leg_r_upper) to the existing 6-slot `PLAYER_SEGMENT_CONFIG` so the character works immediately with current code
- Full 12-segment wiring happens in Phase 3 once hierarchy propagation is implemented
- Verify the character animates and destructs correctly before continuing

**Combat & Dismemberment**

- Attach runtime voxel meshes to player skeleton bones via BoneAttachment3D (replaces static Blender mesh — player becomes destructible)
- Basic NPC enemy (Brawler) with chase AI using NavigationAgent3D
- Implement limb HP system based on remaining voxel count per body segment
- Limb detachment: detach body segment node, add RigidBody3D, apply force
- Detached limbs remain destructible (keep their voxel grid)
- **Visible weapon models:** move WeaponHolder to a BoneAttachment3D on the `weapon-right` bone so weapons appear in world space on the character; model each weapon in MagicaVoxel, export OBJ, attach as MeshInstance3D child of each weapon node
- Add 2 melee weapons (bat, katana) + 2 ranged (revolver, shotgun)
- Weapon pickup system (walk over to grab)
- Health bar UI
- Death + respawn logic

**Player Mobility & Cover Mechanics [NEW]**

- **Crouch** (hold C): reduces player capsule height by ~50%, slower movement, can move behind low cover
- **Prone** (double-tap C or hold X): fully flat, very slow crawl movement, smallest possible profile — useful for hiding behind very low obstacles
- **Lean left / right** (Q / E while near cover): peek around corners without exposing the full body; only the leaning portion of the player's hitbox extends past cover. Leaning is a hold, not a toggle.

**Barrel-Origin Ray Casting [NEW]**

- Each weapon model has a dedicated **Muzzle** node (Node3D at the tip of the barrel)
- All shot rays originate from the Muzzle world position rather than player chest
- Muzzle position naturally accounts for crouch/prone height changes and lean offset
- Combined with the two-ray system (horizontal wall-check + camera-ray voxel targeting), this gives fully realistic shot behaviour: crouching behind cover means the barrel is below the wall top and shots are physically blocked; leaning means the barrel clears the corner only when the lean is sufficient
- Headshots, legshots, and armshots remain possible because the camera ray still determines which exact voxel is hit once the wall-check passes

### Phase 3: Skeletal Destruction (Weeks 9–11)

**Goal: Wire up the 12-bone character art (built in Phase 2) fully in code for granular dismemberment.**

The art foundation — 14 flesh segments, 14 inner bone segments, and the 14-bone Blender rig — is already complete from Phase 2. Phase 3 is entirely code work: hierarchy propagation, upgrading character scripts from 6 to 14 segments, and tuning.

The core idea: each character has 14 individually destructible bone segments arranged in a parent-child hierarchy. Severing the connection between two bones severs everything below it in the chain — cut the elbow and the forearm flies off; cut the knee and the lower leg goes with it. No joint geometry is needed — the segment boundaries ARE the joints.

**14-Bone Hierarchy:**

```
torso_bottom (pelvis) — root, anchor, never detaches independently
 ├── torso_top (ribcage/spine)
 │    ├── head_bottom (jaw/neck)
 │    │    └── head_top (cranium)
 │    ├── arm_r_upper (humerus)
 │    │    └── arm_r_fore (radius/ulna — proximal end = elbow joint)
 │    │         └── hand_r  ← weapon holder, detachment = weapon disabled
 │    └── arm_l_upper
 │         └── arm_l_fore
 │              └── hand_l  ← weapon holder, detachment = weapon disabled
 ├── leg_r_upper (femur)
 │    └── leg_r_fore (tibia/fibula — proximal end = knee joint)
 └── leg_l_upper
      └── leg_l_fore
```

**Naming convention:**
- Flesh segments (outer character, built in Phase 2): `torso_bottom`, `torso_top`, `head_bottom`, `head_top`, `arm_r_upper`, `arm_r_fore`, `hand_r`, `arm_l_upper`, `arm_l_fore`, `hand_l`, `leg_r_upper`, `leg_r_fore`, `leg_l_upper`, `leg_l_fore`
- Inner bone segments (skeleton, built in Phase 3): `skull_bottom`, `skull_top`, `spine_bottom`, `spine_top`, `humerus_r`, `radius_r`, `metacarpal_r`, `humerus_l`, `radius_l`, `metacarpal_l`, `femur_r`, `tibia_r`, `femur_l`, `tibia_l`

**Cascade Detachment System:**

The hierarchy above encodes every detachment rule. Implementation: each VoxelSegment holds a reference to its parent and a list of children. When any segment detaches, iterate its children recursively and detach them all.

Key rules:
- **Elbow cut:** Katana hits `arm_r_fore` → `arm_r_fore` + `hand_r` detach. `arm_r_upper` stays. Only the forearm falls.
- **Shoulder cut:** Katana hits `arm_r_upper` → `arm_r_upper` + `arm_r_fore` + `hand_r` all detach. Full arm gone.
- **Knee cut:** Same pattern for legs — `leg_r_fore` detach only = lower leg gone. `leg_r_upper` detach = full leg gone.
- **No joint segments needed:** The segment boundary IS the joint. `arm_r_fore` starting at the elbow means the elbow is destroyed when that segment's HP hits zero.

**Segment State Machine:**

Each segment has three states, not two:

```
HEALTHY → (break_threshold) → BROKEN → (detach_threshold) → DETACHED
```

- **BROKEN:** Segment stays attached. For arm segments — the weapon held in that hand is disabled. Visually: inner bone voxel color shifts (purple-grey bruise). Implemented as a `structural_integrity` float on VoxelSegment, separate from voxel HP. Drops on blunt impact, does not regenerate.
- **DETACHED:** Standard cascade detach — node removed from skeleton, RigidBody3D applied, physics takes over.

This is how blunt-force bone-breaking works without detachment: bat hits `arm_r_upper` repeatedly → `structural_integrity` drops to zero → BROKEN state → player can't equip or swing weapons in right hand, but the arm stays attached. A further hit past `detach_threshold` causes full detachment with cascade.

**Code Changes Required:**

- Add hierarchy propagation to VoxelSegment: when a segment detaches, iterate `_children` array and call `detach()` recursively
- Add `structural_integrity` float and BROKEN state to VoxelSegment; emit `segment_broken` signal when threshold crossed
- Add weapon slot disable logic: player listens for `segment_broken` on `hand_r`/`hand_l`/arm segments and disables the corresponding weapon slot
- Update `PLAYER_SEGMENT_CONFIG` in `player.gd` from 6 slots to all 14, mapping each flesh + bone .vox pair to the correct bone
- Update Brawler and Dummy scripts from 6 segments to 14 with correct parent-child bone references
- Tune per-bone thresholds: skull top is fragile, pelvis is very tough; hands are fragile (small target, low HP)
- Update leg-loss crawl logic: losing a foreleg vs upper leg produces different speed penalties
- Wire inner bone segments: load bone .vox alongside flesh .vox per segment, render at lower opacity until flesh voxel count drops below a threshold

**Why this matters for gameplay:**

- Sword swings that clip the forearm sever only the forearm — half-dismemberment becomes possible
- Head split: a slash across the skull top produces a partial decapitation while the jaw/neck remains
- Players can still fight with severed upper arm (torso intact), but lose the arm entirely if the humerus goes
- Bleed-through destruction: carving flesh exposes the bone beneath, which then takes more hits to destroy
- Hand loss: losing `hand_r` prevents equipping any weapon in the right slot; losing both hands prevents two-handed weapons

**Weapon Polish (deferred from Phase 2):**

These weapon behaviours depend on the 14-bone system and are implemented here once the skeleton is in place:

- **Bat — bone degradation:** Blunt hits reduce `structural_integrity` per bone segment without clean severing. A heavily battered arm enters BROKEN state (unusable, can't hold weapon, no attack) but stays attached. When `structural_integrity` hits zero the limb hangs limp. A further hit past `detach_threshold` causes full cascade detachment.
- **Katana — bleed:** Sharp hits start a timed voxel drain on the struck segment (e.g. lose N voxels/sec for 3 seconds). Stacks on repeated hits. Implement as a timer + drain coroutine on VoxelSegment, triggered from `WeaponKatana._apply_hit()`.
- **Katana — forced sever:** A single clean katana hit to an arm or leg at full damage should push the segment past its detach threshold immediately, regardless of remaining voxel count. Add a `force_detach` flag to `DamageManager.process_hit()`.
- **Attack animations per weapon:** Add distinct attack animations in Blender for bat swing, katana slash, and shotgun pump. Map them in `play_attack_anim()` once animations are exported.
- **Weapon-specific hit feedback:** Distinct audio, screen shake intensity, and particle colour per weapon type (e.g. red splatter for katana, grey dust for bat).

### Phase 4: Multiplayer (Weeks 12–14)

**Goal: 2+ players connected and fighting in the same arena.**

- Set up ENet host/client architecture
- Sync player movement, rotation, animation
- Sync damage events (hit position + radius) — clients rebuild voxel meshes locally
- Sync dismemberment events explicitly
- MultiplayerSpawner for players + weapons
- Basic lobby: host starts game, clients see player list
- Test with friends using port forwarding or ZeroTier
- Fix desyncs and rubberbanding (interpolation + server reconciliation)
- **[NEW]** FOV in multiplayer: each client computes own FOV locally; teammate FOV rendered dimmed in team modes

### Phase 5: Game Modes + Cards (Weeks 15–17)

**Goal: FFA Deathmatch fully playable with card system.**

- Round system: timed rounds, score tracking, round transitions
- Card pick screen between rounds (choose 1 of 3)
- Implement 10–15 starter cards with stacking logic
- Kill feed UI, scoreboard, round announcements
- Add 2–3 more weapons + environmental throwables
- Basic sound effects (hits, explosions, pickups, card selection)
- Win condition + end-of-match screen

***After Phase 5, you have a playable prototype! From there, add wave survival, team mode, more cards, more maps, and eventually battle royale.***

---

## 15. Stretch Goals

Features worth building eventually but not required for the prototype. Prioritise only after Phase 5 ships.

### Procedural Voxel Generation from Mesh

Rather than hand-modelling flesh voxels in MagicaVoxel, generate them at runtime by voxelising the Blender mesh geometry directly:

- For each bone mesh (from the .glb skeleton), sample a 3D voxel grid using raycasting or signed-distance-field (SDF) evaluation to determine which grid cells are inside the mesh
- Fill those cells with voxels coloured to match the character's skin/material
- Result: the flesh wrapping each bone segment is generated automatically from the Blender model — no manual MagicaVoxel work required
- Benefits: change a character's proportions in Blender and the voxel body updates automatically; supports arbitrary body shapes and player-created characters
- Complexity: requires implementing a mesh-to-voxel converter in GDScript or a preprocess step — non-trivial but well-documented algorithm

### Other Stretch Goals

- **Dynamic wound deformation** — hit voxels deform and discolour gradually rather than instantly disappearing; blood pooling fills carved craters
- **Physics-accurate ragdolls** — on death, swap CharacterBody3D for a fully ragdolled version using Jolt's articulated body system
- **Procedural NPC variety** — randomise voxel segment dimensions per NPC so no two brawlers look identical
- **Destructible environment voxels** — walls and floor tiles use the same VoxelSegment system; bullets and explosions carve the arena itself

---

## 12. Map Design Guidelines

Start with one arena, designed for 8-player FFA. **The fog-of-war system makes map layout critically important** — every wall, corridor, and corner creates potential ambush points and blind spots.

- Medium size: big enough that 8 players aren't constantly on top of each other, small enough that you're never more than 10 seconds from a fight
- **[UPDATED]** Multiple height levels are less important with a top-down camera. Focus instead on interesting floor layouts: corridors, rooms, open plazas, and chokepoints
- Weapon spawn points: 6–8 spots spread evenly. Best weapons in risky/exposed locations
- Environmental hazards: at least 2 (e.g. a crusher + a spike pit)
- Cover: destructible voxel walls that crumble when hit enough. **Destroying walls now serves a dual purpose: creating paths AND opening sightlines through the FOV system**
- Aesthetic: pick a theme (bar fight, rooftop, construction site, disco) and commit. One consistent palette
- **[NEW]** Design for FOV tension: include blind corners, L-shaped corridors, and rooms with multiple entry points. Open areas should feel exposed and risky. Tight corridors should feel claustrophobic — you can't see what's around the bend
- **[NEW]** Avoid long straight hallways where players with ranged weapons can dominate — the FOV radius caps how far you can see anyway, but sightlines should still feel varied
- **[NEW]** Consider "ambush architecture": small alcoves or side rooms where players can hide just outside a main corridor's FOV

---

## 13. Recommended Learning Path

Given your experience level (some tutorials/small projects), here's the order to learn things. Updated to front-load the voxel engine work:

1. Godot 4 official "Your First 3D Game" tutorial (~2 hours, covers movement, enemies, signals)
2. **[NEW]** Godot SurfaceTool documentation — understand how to generate meshes from code
3. MagicaVoxel basics (YouTube: "MagicaVoxel Character Tutorial", ~1 hour)
4. **[NEW]** Parse a .vox file in GDScript — community resources exist for the format spec
5. Godot multiplayer official docs ("High-level Multiplayer" guide)
6. Blender → Godot pipeline (rigging, export as .glb, import into Godot)
7. Search YouTube for "Godot voxel destruction" — several community tutorials exist on breaking meshes into chunks
8. **[NEW]** Godot 2D fog-of-war / raycasting tutorials — the FOV technique is well-documented in the roguelike/top-down game community. Search "Godot fog of war raycast" or "Godot line of sight shadow casting"

---

## 14. Key Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Voxel mesh rebuild performance | Frame drops during heavy combat | Only rebuild hit segment. Batch rebuilds per frame. Profile early in Phase 0. |
| Voxel chunk performance | Lag with 8 players + particles | Tiered debris: RigidBody3D for big chunks, GPUParticles3D for small. Pool + reuse. Cap ~50 physics bodies. |
| Network desync | Players see different states | Server-authoritative. Sync hit events, not voxel data. Interpolate on client. |
| Scope creep | Never finish prototype | Build voxel engine first (Phase 0). Then FFA mode. Ship that. Add modes incrementally. |
| Card balance | Broken combos ruin fun | Playtest weekly with friends. Nerf/buff. It's meant to be chaotic. |
| Port forwarding hassle | Friends can't connect | Document setup. Consider ZeroTier as backup (virtual LAN). |
| Blender pipeline complexity | Animation import issues | Use .glb format only. Test one animation round-trip early. Keep rig simple (6–8 bones). |
| FOV feels too restrictive or too generous | Gameplay is frustrating or tension is lost | Tune the base radius during playtesting. Start generous (~12 units) and tighten. Make it a config variable. |
| FOV + destructible walls edge cases | Destroyed wall sections don't update FOV correctly | Ensure wall collision shapes update when voxels are removed. Test early in Phase 1. |

---

**Next Steps:** Download Godot 4.3+, MagicaVoxel, and Blender. Complete Godot's first 3D game tutorial. Then start Phase 0 — build a destructible voxel character before anything else. When you're ready, come back and we'll work through each phase together — code architecture, GDScript patterns, shader setup, whatever you need.
