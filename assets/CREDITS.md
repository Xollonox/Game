# Asset Credits & Licenses

Every asset in `assets/` must be tracked here with its source and license, per the rule in `research.md` §4. CC0 is preferred; nothing NC (non-commercial) or ND (no-derivatives) is allowed.

## Downloaded and vendored in this repo

### 3D Models — `assets/models/weapons/swords_pack/` (`fbx/`, `blend/`, `obj_mtl/`)
- **Source:** [3D Swords Pack](https://opengameart.org/content/3d-swords-pack) — OpenGameArt.org
- **License:** CC0 (public domain)
- **Contents:** 9 low-poly sword models, provided as `.fbx`, `.blend`, and `.obj`/`.mtl`
- **Attribution:** Not required (CC0), credited here anyway for provenance.

### SFX — `assets/sfx/battle/battle_sfx/`
- **Source:** [Battle Sound Effects](https://opengameart.org/content/battle-sound-effects) — OpenGameArt.org
- **License:** CC0 (the pack is multi-licensed CC-BY/CC-BY-SA/GPL/CC0 by the uploader; we use it under the **CC0** option specifically)
- **Contents:** `swish_2.wav`, `swish_3.wav`, `swish_4.wav`, `Bow.wav`
- **Attribution:** Not required under the CC0 option chosen.

### SFX — `assets/sfx/impacts/hits_punches/`
- **Source:** [37 hits/punches](https://opengameart.org/content/37-hitspunches) by Independent.nu — OpenGameArt.org
- **License:** CC0 (public domain)
- **Contents:** `hits/hit01.mp3.flac` through `hit37.mp3.flac` (37 impact sounds)
- **Attribution:** Not required (CC0), credited here anyway for provenance.

## Identified but NOT yet acquired (needs a manual step)

itch.io's "name your own price" pages (including $0/free CC0 items) require clicking through an interactive claim/checkout flow tied to an account — there is no anonymous direct-download URL, so these could not be fetched headlessly in this session. A human needs to visit and claim these once, after which they can be added under `assets/animations/`:

- **[Universal Animation Library](https://quaternius.itch.io/universal-animation-library) by Quaternius** — CC0, Mixamo-compatible humanoid rig, 120+ animations including combat, explicitly built to work with Godot. This is the primary recommended source for the active-ragdoll's animated target skeleton (see `research.md` §3, `PLAN.md` Phase 1).
- **[Human Melee Animations](https://kevdev.itch.io/human-melee-animations) by kevdev** — free tier, dedicated sword swing/parry/block set.

## Other sources identified in research (not yet pulled)

See `research.md` §4 for the full list, including Poly Haven weapon models, OpenGameArt's "CC0 - 3D Weapons" and "Cethiel's Weapons 3D", and Freesound.org for supplemental foley — pull from these only under the CC0/CC-BY rule above, and add an entry here for anything added.
