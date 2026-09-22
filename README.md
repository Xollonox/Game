# Bare Steel

A physics-driven medieval melee game in the spirit of [Half Sword](https://store.steampowered.com/app/2397300/Half_Sword/),
built with Godot 4.7 and Jolt physics. Characters are **active ragdolls**: the
body is a real physics rig that chases an animated pose, so a solid hit
overpowers it and the character staggers, goes down, and picks itself back up —
no canned knockdown animations. Every blade is a real `RigidBody3D` that deals
damage from its own measured contact speed.

## Play in the browser

**https://xollonox.github.io/Game/**

### Controls

| Input | Action |
|---|---|
| `W` `A` `S` `D`, or the on-screen joystick | Move (camera-relative) |
| `Shift` | Sprint |
| `Space` / left click, or the on-screen SWING button | Sword swing — a real physics blade, not a hitscan |
| Right-drag, `Q` / `E`, or a touch drag on the right side of the screen | Orbit the camera |
| Mouse wheel | Zoom the camera |
| `Esc` | Pause (settings, restart, leave) |
| `R` after death | Rise again |
| `1` / `2` / `3` | Debug: hit yourself light / heavy / crushing |

On a touchscreen, a virtual joystick and swing button appear automatically —
see `scripts/touch_controls.gd`.

## The world

The fighting ground is built at runtime from a **48-piece modular kit** that is
generated headlessly in Blender (`tools/blender/build_world_kit.py`) — stone
walls, a gatehouse landmark, corner towers, timber viewing stands, a shed,
fences, palisade, plus barrels, carts, cages, weapon racks, training dummies,
braziers, banners and terrain dressing (mud, puddles, rubble, rocks, grass).
A village silhouette and fog layers sit beyond the wall for depth.

World pieces share one PBR material per kit slot (`scripts/world_materials.gd`)
and are merged into a handful of draw calls at load (`WorldBuilder._batch_static`),
which is what keeps the browser build inside its frame budget.

## Running from source

Install Godot 4.7+ (`./install-godot.sh`, or see [INSTALLATION.md](INSTALLATION.md)), then:

```bash
godot project.godot          # open in the editor
godot --headless --path .    # run headless
```

## Rebuilding the world kit (headless Blender)

The kit, the fixed weapons and the armoured character are all produced without
the Blender GUI:

```bash
blender -b --python tools/blender/build_world_kit.py -- --out /data/kit
```

Each piece exports as its own GLB with metre scale, base-centre pivot, named
material slots (`M_Stone`, `M_Wood`, `M_Roof`…) and box-projected UVs; LODs are
emitted for the heaviest silhouettes. Godot then applies the shared PBR
materials per slot name.

## Tests

All tests are scenes under `tests/` and run headlessly (vision tests need a GL
context, so they run under Xvfb):

```bash
godot --headless --path . res://tests/bench.tscn                 # frame/physics/draw budget
xvfb-run -a godot --path . res://tests/vision_test.tscn -- --shots=/tmp/vision
xvfb-run -a godot --path . res://tests/world_vision_test.tscn -- --shots=/tmp/world
xvfb-run -a godot --path . res://tests/gameplay_test.tscn -- --noblood
```

`bench.tscn` takes `--noworld` to isolate the world's cost, `gameplay_test.tscn`
runs an autonomous bot duel, and `world_vision_test.tscn` captures the menu and
composed arena angles for visual review.

## Re-exporting the web build

The playable build in `docs/` is committed so GitHub Pages needs no toolchain in
CI. After changing the game, re-export and commit it:

```bash
godot --headless --import
godot --headless --export-release "Web" docs/index.html
```

Thread support is deliberately **off** in the export preset: Godot's threaded
web build needs `SharedArrayBuffer`, which requires COOP/COEP headers that
GitHub Pages cannot set. The single-threaded build runs there without them.

## Project layout

| Path | What's in it |
|---|---|
| `scenes/` | `menu.tscn` (main menu), `arena.tscn` (the duel), `player.tscn`, `dummy.tscn` |
| `scripts/` | `world_builder.gd` (procedural yard), `world_materials.gd`, `hud.gd`, `ui_theme.gd`, `menu.gd`, `arena.gd`, `kickback_actor.gd`, `physics_sword.gd` |
| `tools/blender/` | Headless Blender pipelines (`kit_lib.py`, `build_world_kit.py`) |
| `assets/models/world/kit/` | The 48 generated GLB pieces |
| `assets/textures/world/` | CC0 PBR texture sets (Poly Haven, ambientCG) |
| `assets/fonts/`, `assets/audio/` | OFL fonts, CC0 music/ambience/UI sounds |
| `tests/` | Bench, vision, world-vision and gameplay-bot tests |
| `docs/` | Exported web build served by GitHub Pages |
| `assets/CREDITS.md` | Full provenance for every third-party asset |

## Licensing

Project code is unlicensed so far (TBD). Every third-party asset and addon is
CC0, OFL or MIT, tracked with its source in [`assets/CREDITS.md`](assets/CREDITS.md).
