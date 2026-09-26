# Master Prompt — build a game the way Bare Steel was built

Attach this file to a new Claude Code session, fill in the **Your game** block,
attach your reference images, and send. Everything below the block is the
method, the rules and the asset sources that produced Bare Steel
(https://xollonox.github.io/Game/).

---

## Your game (fill this in)

```
Name:            [e.g. Neon Harbour]
ID:              [short lowercase id for folders/export, e.g. neon_harbour]
Genre:           [open-world crime / exploration / FPS / melee / survival / racing ...]
Camera:          [first-person / third-person / top-down]
Idea:            [2–6 sentences: who you play, where, what you do, what makes it special]
Feel:            [e.g. realistic and weighty / fast arcade / slow and eerie]
Setting & era:   [e.g. modern coastal city at night / 15th-century tournament / alien jungle]
Must-have:       [3–6 features you care about most]
Not wanted:      [things to avoid]
Platforms:       Web (GitHub Pages) + desktop + mobile
Reference images: attached — [one line on what each shows: mood, art style, UI, character, map]
```

**How to use the reference images:** match their mood, palette, lighting,
proportions and UI layout. Don't copy them, and never ship them as assets:
they are references only.

---

## Instructions to Claude

Build **[Name]** as described above, in Godot 4, working the way this document
describes. Start by writing `PLAN.md`: the systems in build order, each with
its test, plus a first list of assets and their sources. Then build it system
by system.

### Tech stack

| Part | Use | Why |
|---|---|---|
| Engine | **Godot 4.x** (MIT) with **Jolt Physics** | One project exports to web, desktop and mobile; GDScript |
| Web renderer | `gl_compatibility` for web and mobile, Forward+ on desktop | Runs in any browser |
| Active ragdoll (if bodies react to hits) | **Kickback** — https://github.com/blugart-dev/kickback (MIT) | Physical hit reactions and balance, Euphoria-style |
| Terrain (open worlds) | **Terrain3D** (MIT) | Large sculpted terrain with LODs |
| Vehicles (if any) | Godot `VehicleBody3D` | Built-in wheels, suspension and friction |
| 3D asset generation | **Headless Blender + Python scripts** in `tools/blender/` | Models, props and world kit rebuilt from code any time |
| Mocap conversion | `tools/mocap/` ASF/AMC → BVH, then a Blender retarget script | Real human motion on your own skeleton |
| Hosting | **GitHub Pages** via a GitHub Actions workflow publishing `docs/` | A free public link, updated on every merge |
| Tests | Headless test scenes: `xvfb-run -a godot --path . res://tests/<name>.tscn` | Every system is proven by a script |

### Non-negotiable rules

1. **Licenses:** only CC0, MIT, BSD, Apache, or CC-BY with credit. Never NC
   (non-commercial) or ND (no-derivatives). Never copy code whose license is
   unclear. Record **every** asset in `assets/CREDITS.md`: source URL,
   author, license and what was modified.
2. **Web must always work:** no native GDExtension at runtime; keep the web
   build under ~100 MB (1K textures, decimated meshes, Ogg audio).
3. **One system at a time**, each with an automated test scene that prints
   PASS/FAIL and exits non-zero on failure.
4. **Check visuals:** render screenshots after every visual change (Blender
   Cycles previews or Godot captures) and look at them before moving on.
5. **Fix root causes, no superficial tweaks.** A "flaky" test is a bug until
   proven otherwise.
6. **Commit coherent checkpoints**, one PR per feature; merging to `main`
   deploys the site.
7. **Scale from low-end to high-end:**
   - graphics presets Low / Medium / High / Ultra (render scale, shadows, MSAA, particles, post effects);
   - automatic resolution scaling tied to the frame rate;
   - physics interpolation on, so movement is smooth at any refresh rate;
   - animation that the physics chases runs on the physics tick.
8. **Controls:** keyboard and mouse, gamepad, and on-screen touch controls
   for mobile. Also a How-to-Play screen and a Settings screen (volumes,
   graphics, toggles).
9. **Persistence:** settings and progress saved to `user://`, which works on
   the web through IndexedDB.

### Build order (adapt to the genre)

1. **Project skeleton:** folders, autoloads (game state, audio, FX), the
   Pages workflow and a first web export. Ship a moving capsule on the live link on day one.
2. **Player controller:** movement, camera, input on every device, with a movement test.
3. **Core mechanic:** see "Genre modules" below.
4. **Damage and reactions:** health or a regional injury model, hit
   reactions (active ragdoll if physical), death flow.
5. **AI:** perception, then states (idle / patrol / chase / attack / flee /
   take cover), then group behaviour (how many may engage at once).
6. **World:** a script-generated kit (buildings, props, terrain dressing),
   LODs, culling, lighting, fog, sky.
7. **UI and loop:** HUD, menus, progression, save/load, shop or inventory if needed.
8. **Audio and FX:** impacts, footsteps, ambience, music, particles with quality budgets.
9. **Polish and performance pass:** profile on the web build, then fix the worst frame costs first.

### Genre modules

- **FPS:**
  - first-person camera with a weapon viewmodel;
  - hitscan and projectile weapons with recoil, spread, reload and ammo;
  - hit zones (head, body, limbs);
  - enemy AI that uses cover and flanks;
  - ragdoll on death.
- **Exploration:**
  - large terrain with world chunks streamed in;
  - day/night cycle and weather;
  - climbing, swimming and gliding;
  - points of interest, a map and a journal, collectibles.
- **GTA-style open world:**
  - a procedurally generated city in chunks;
  - walking, shooting and driving (`VehicleBody3D`), entering and leaving cars;
  - traffic and pedestrian AI on a road graph;
  - a wanted level with police response;
  - a mission system, a minimap.
  - Start with one district and one car, then grow.
- **Melee (how Bare Steel works):**
  - physics weapons pulled to the hand by a spring;
  - a contact evaluator (touching is not striking);
  - a regional injury model, grip and disarm only on critical hits;
  - motion-captured strikes, and an ultimate meter.

### Asset pipeline

- **Characters:** start from a CC0 base body. Generate clothing and armour
  with Blender scripts; split the body into zones so skin hidden under
  clothes can be removed.
- **Animations:**
  - start from CC0 libraries;
  - add real motion capture from CMU for realism;
  - retarget with world-space rotation deltas and aligned rest poses; ground the feet;
  - render frames of each clip to review before using it.
- **Props and world:** generate the kit with Blender scripts (walls,
  buildings, vehicles, props) and emit LODs for big pieces.
- **Textures:** CC0 PBR sets at 1K JPEG for the web.
- **Audio:** CC0 effects and music, re-encoded to Ogg Vorbis.

---

## Asset source catalog (license-checked)

| Source | What | License |
|---|---|---|
| Quaternius — https://quaternius.com / https://quaternius.itch.io | Universal Base Characters, Universal Animation Library 1 & 2, animated characters, props, vehicles | CC0 |
| Kenney — https://kenney.nl/assets | Models (city, castle, vehicles, nature), impact/RPG/UI sounds, UI packs | CC0 |
| Poly Haven — https://polyhaven.com | PBR textures, HDRI skies, some models | CC0 |
| ambientCG — https://ambientcg.com | PBR textures (fabric, metal, leather, ground) | CC0 |
| OpenGameArt — https://opengameart.org | Music, ambience, sound effects (check each item; use only CC0 / CC-BY) | Varies |
| CMU Graphics Lab Motion Capture Database — http://mocap.cs.cmu.edu | 2,500+ real mocap takes: boxing, kicks, sword, walks, runs, climbs | Free for any use including commercial; don't resell the raw data |
| Google Fonts — https://fonts.google.com | Display and body fonts | SIL OFL 1.1 |
| Kickback — https://github.com/blugart-dev/kickback | Active-ragdoll addon for Godot 4 / Jolt | MIT |
| Godot Asset Library — https://godotengine.org/asset-library | Addons (check each: prefer MIT) | Varies |

Not allowed: Mixamo raw files (Adobe terms restrict redistribution), any NC or
ND license, ripped game assets, and anything without a stated license.

### How Bare Steel used these (a model for `assets/CREDITS.md`)

- **Fighter:** Quaternius Universal Base Characters (body, eyes, hair) and
  UAL 1 & 2 (19 + 24 clips, retargeted).
- **Wardrobe and helmets:** original, generated by `wardrobe.py` / `helmets.py`.
- **Melee clips:** original, authored on an IK rig by `melee_anims.py`.
- **Mocap:** CMU subject 14 (boxing), 135 (front kicks), 141 (punch-kick
  combo), 144 (blocks), converted and retargeted into `mocap_anims.glb`.
- **Weapons:** original, lofted from cross-sections by `build_weapons.py`,
  which also measures mass, centre of mass and collision boxes.
- **World:** a 48-piece medieval kit generated by `build_world_kit.py`.
- **Textures:** Poly Haven (cobblestone, castle brick, planks, plaster,
  fabric, clay roof, thatch, dirt, mud) and ambientCG (grass, fabric,
  linen, wool, leather, chainmail, metal), downscaled to 1K.
- **Audio:**
  - Kenney Impact / RPG / UI sounds;
  - OpenGameArt crowd ambience, "The Old Tower Inn" and "Rejoicing" loops, fantasy wind bed;
  - an original synthesised drone.
- **Fonts:** Cinzel, Cinzel Decorative, EB Garamond, Grenze Gotisch (all OFL).
- **Physics:** Kickback (MIT), vendored with changes.

---

## Working style

- **Keep me updated:** a short progress note per step, a screenshot for
  visual changes, a PR link when a feature is done.
- **When I say it "feels rough" or "looks mid":** turn that into measurable
  targets (frame time, snap speed, hit counts), fix the cause and show before/after.
- **Big asks:** split them into one system per PR. Never leave the web build broken on `main`.
