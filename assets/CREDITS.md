# Asset Credits & Licenses

Every asset in `assets/` must be tracked here with its source and license, per the rule in `research.md` §4. CC0 is preferred; nothing NC (non-commercial) or ND (no-derivatives) is allowed.

## Downloaded and vendored in this repo

### 3D Models — `assets/models/weapons/swords_pack/` (`fbx/`, `obj_mtl/`)
- **Source:** [3D Swords Pack](https://opengameart.org/content/3d-swords-pack) — OpenGameArt.org
- **License:** CC0 (public domain)
- **Contents:** 9 low-poly sword models, provided as `.fbx` and `.obj`/`.mtl`. The pack's `.blend` sources were dropped: Blender isn't installed in this environment (Godot's `.blend` importer shells out to a real Blender binary), and the `.fbx`/`.obj` exports are sufficient for the game.
- **Attribution:** Not required (CC0), credited here anyway for provenance.

### Character model + animations — `assets/models/characters/quaternius_universal/universal_character.glb`
- **Source:** [Universal Animation Library](https://store.godotengine.org/asset/quaternius/universal-animation-library/) by Quaternius — Godot Asset Store (official mirror; the itch.io page for the same asset has no anonymous download, see below)
- **License:** CC0 1.0 Universal (`LICENSE.txt` alongside the file is the pack's own license notice)
- **Contents:** One rigged humanoid character (Blender Rigify `DEF-` bone naming) with 120+ baked-in animation clips (locomotion, combat, reactions). This is the base mesh + skeleton the Phase 2 active-ragdoll rig (`scripts/player.gd`) attaches to.
- **Attribution:** Not required (CC0).

### Physics/animation addon — `addons/kickback/`
- **Source:** [blugart-dev/kickback](https://github.com/blugart-dev/kickback) (git commit at time of vendoring: see `git log` on this addon's introduction)
- **License:** MIT — full text at `addons/kickback/LICENSE`
- **What it is:** A Euphoria-style active-ragdoll plugin for Godot 4.7+ / Jolt Physics: builds a 16-`RigidBody3D` physics skeleton that tracks the animated pose via velocity springs, with stagger/full-ragdoll/recovery states, hit routing, and skeleton auto-detection (Mixamo, Rigify `DEF-`, UE5 Mannequin, generic rigs). This is the core of `PLAN.md` Phase 2 — we did not write an active-ragdoll solver from scratch; we integrated this one and fixed one real bug in it (see `scripts/player.gd`'s comment on `RagdollTuning`).
- **Not vendored:** the repo's own `addons/gut/` (its test framework) and `demo/`/`docs/`/`test/` folders — we only took the reusable `addons/kickback/` plugin itself.

### SFX — `assets/sfx/battle/battle_sfx/`
- **Source:** [Battle Sound Effects](https://opengameart.org/content/battle-sound-effects) — OpenGameArt.org
- **License:** CC0 (the pack is multi-licensed CC-BY/CC-BY-SA/GPL/CC0 by the uploader; we use it under the **CC0** option specifically)
- **Contents:** `swish_2.wav`, `swish_3.wav`, `swish_4.wav`, `Bow.wav`
- **Attribution:** Not required under the CC0 option chosen.

### SFX — `assets/sfx/impacts/hits_punches/`
- **Source:** [37 hits/punches](https://opengameart.org/content/37-hitspunches) by Independent.nu — OpenGameArt.org
- **License:** CC0 (public domain)
- **Contents:** `hits/hit01.ogg` through `hit37.ogg` (37 impact sounds). The pack ships these as `.flac` (misnamed `.mp3.flac`); Godot has no `.flac` importer at all (only `.wav`/`.ogg`/`.mp3`), so they were re-encoded to Ogg Vorbis with `ffmpeg` before vendoring — otherwise they'd sit in the repo unusable by the engine.
- **Attribution:** Not required (CC0), credited here anyway for provenance.

## Identified but NOT yet acquired (needs a manual step)

itch.io's "name your own price" pages (including $0/free CC0 items) require clicking through an interactive claim/checkout flow tied to an account — there is no anonymous direct-download URL, so these could not be fetched headlessly in this session. A human needs to visit and claim these once, after which they can be added under `assets/animations/`:

- **[Human Melee Animations](https://kevdev.itch.io/human-melee-animations) by kevdev** — free tier, dedicated sword swing/parry/block set. (The base Universal Animation Library equivalent was obtained instead via the Godot Asset Store direct download — see above — so this is now supplemental, not blocking.)

## Other sources identified in research (not yet pulled)

See `research.md` §4 for the full list, including Poly Haven weapon models, OpenGameArt's "CC0 - 3D Weapons" and "Cethiel's Weapons 3D", and Freesound.org for supplemental foley — pull from these only under the CC0/CC-BY rule above, and add an entry here for anything added.
