# Bare Steel

A physics-driven medieval tournament melee in the spirit of [Half Sword](https://store.steampowered.com/app/2397300/Half_Sword/),
built with Godot 4.7 and Jolt physics. Climb a seventeen-bout ladder from a
vagrant's scrap in the mud to a 1v6 Grand Melee; die, and descend into the
Hollow to face the men you killed. Characters are **active ragdolls**: the
body is a real physics rig that chases an animated pose, so a solid hit
overpowers it and the character staggers, goes down, and picks itself back up —
no canned knockdown animations. Every blade is a real `RigidBody3D` that deals
damage from its own measured contact speed.

## Play in the browser

**https://xollonox.github.io/Game/**

### Controls

| Input | Action |
|---|---|
| `W` `A` `S` `D`, or the on-screen joystick | Move (camera-relative; squared up to an opponent you move in a guarded gait) |
| `Space` / left click, or CUT | Cut — the movement you hold picks the line: forward = from above (Oberhau), sideways = level (Mittelhau), back = rising (Unterhau) |
| `F` / middle click, or THRUST | Thrust |
| `C` / right mouse (hold), or GUARD | Guard |
| `X` | Step back out of range |
| `G` (hold, when badly hurt) | Yield: lose the bout, keep your life (-10 renown) |
| `Shift` | Sprint (cut while sprinting = heavy blow) |
| `Q` / `E`, middle-drag, touch drag | Turn the camera; `Tab` toggles lock-on |
| Mouse wheel | Zoom |
| `Esc` | Pause (settings, leave) |

## The run

- **Tournament ladder** (`scripts/tournament.gd`): 17 bouts across seven ranks — Vagrant, Peasant, Militiaman, Soldier, Veteran, Man-at-Arms, Knight — escalating opponent skill, equipment and numbers: duels, 2v1, free-for-all melees where the fighters kill each other too, gauntlets where they come through the gate one by one, and a 1v6 Grand Melee. A bout director hands out attack tokens so groups circle and wait their turn instead of piling on.
- **Progression**: renown and coin per bout. The weapons of the fallen go into your pack; a spare of one you already carry is sold on the spot. Persistent in `user://run.cfg`.
- **The Armourer's Tent** (after every win and from the hall): buy, sell and wear weapons and armour. There are 23 armour pieces over nine slots (body, mail, plate, head, neck, arms, hands, legs, feet) and all nine weapons, including the shield. Finer stock unlocks as your rank rises. Mail and plate must go over a gambeson, a shield needs a one-handed weapon, and the armourer buys back at half price. Keyboard: arrows and Enter, `Q`/`E` to switch tabs, `Esc` to leave. Every control is also a touch button.
- **Mercy**: a beaten opponent may yield — kneel and drop his weapon. That wins the bout, and a man you spare owes the Hollow nothing; strike him anyway and he is one more soul waiting below. Low-born fighters yield readily, knights rarely.
- **Death and the Hollow** (`scenes/hollow.tscn`): death offers *Descend into the Hollow*, *Begin a New Life* or *Return to the Hall*. The Hollow is a drowned ruin of the yard where the shades of the men you killed come for you. Lay them to rest and you climb back to the living; fall there and your name is forgotten.

## Fighters, armour and weapons

- **Characters** (`tools/blender/build_fighter.py`): Quaternius Universal Base Characters human (CC0) with face, hair and beard, UAL1 + UAL2 clips retargeted in world space, and an original IK-authored melee library (`melee_anims.py`) — stances, guards, cuts, thrusts, guarded gaits, flinches, stagger, evade and get-ups per weapon family, built from HEMA body mechanics.
- **Wardrobe** (`wardrobe.py`, `helmets.py`): shirt, tunic, hose, shoes, boots, gambeson, haubergeon, mail coif, brigandine, full harness and six helmets generated around the body; covered skin zones are hidden.
- **Wound model** (`KickbackActor.receive_weapon_hit`): cut / pierce / blunt channels against layered armour coverage (`scripts/armory.gd`), momentum knock scaled by worn weight, bleeding, sparks on steel.
- **Arsenal** (`tools/blender/build_weapons.py`): arming sword, longsword, falchion, rondel dagger, bearded axe, flanged mace, cudgel, war spear, heater shield — each with measured mass, centre of mass and per-part collision boxes, driven as a real body by `PhysicsWeapon`.

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

The kit, the arsenal and the fighter are all produced without the Blender GUI
(Blender 5.2 LTS). The fighter build expects the CC0 Quaternius packs unpacked
under `$ASSET_SRC` (default `/opt/src`, see `assets/CREDITS.md` for sources):

```bash
blender -b --python tools/blender/build_world_kit.py -- --out /data/kit
blender -b --python tools/blender/build_weapons.py -- --out assets/models/weapons/arsenal
blender -b --python tools/blender/build_fighter.py -- --out assets/models/characters/fighter
blender -b --python tools/blender/preview.py -- in.glb out.png --action Cut_Oberhau --frame 15 --weapon assets/models/weapons/arsenal/arming_sword.glb
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
xvfb-run -a godot --path . res://tests/gameplay_test.tscn -- --bout=4 --shots=/tmp/g   # bot plays a bout
xvfb-run -a godot --path . res://tests/gameplay_test.tscn -- --hollow                   # bot in the Hollow
xvfb-run -a godot --path . res://tests/fighter_gallery.tscn -- --shots=/tmp/gallery     # one fighter per rank
xvfb-run -a godot --path . res://tests/flow_test.tscn                                  # full run loop: win, shop, spoils, die, Hollow, return, run over
xvfb-run -a godot --path . res://tests/shop_test.tscn                                  # shop/inventory rules + tent screenshots
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
