# Plan: Half Sword-style Physics Combat Prototype

Based on `research.md`. Scope is a **vertical slice**: one active-ragdoll player, one physics-driven sword, one dummy/enemy to hit, in one small arena. Dismemberment, multiplayer, and progression are explicitly out of scope for this plan.

Engine: Godot 4.7.2 (installed), Jolt physics (default in 4.7).

## Phase 0 — Project groundwork (done / ongoing)
- [x] Godot 4.7.2 installed and verified runnable.
- [x] Base project skeleton (`project.godot`, `scenes/`, `scripts/`, `assets/`).
- [ ] Confirm Jolt is active in Project Settings → Physics → 3D → Physics Engine (should default to Jolt on 4.7; verify, don't assume).
- [ ] Set up `assets/` subfolders: `assets/models/`, `assets/animations/`, `assets/sfx/`, `assets/sfx/CREDITS.md` (attribution ledger even for CC0, so provenance isn't lost).

## Phase 1 — Asset acquisition
- [ ] Pull down a CC0 low-poly sword model (OpenGameArt "3D Swords Pack" or "CC0 - 3D Weapons") — need at least one usable `.glb`/`.fbx`/`.obj` importable into Godot.
- [ ] Pull down the Quaternius "Universal Animation Library" (Mixamo-rig-compatible, Godot-friendly) for base locomotion (idle/walk/fall/get-up).
- [ ] Pull down a melee-specific animation source (kevdev "Human Melee Animations") for windup/swing/block reference poses — these drive the *animated target* skeleton that the active ragdoll chases.
- [ ] Pull down CC0 impact/clash SFX from OpenGameArt ("Punches, hits, swords and squishes", "Battle Sound Effects").
- [ ] Record every source + license in `assets/CREDITS.md` as it's added.

## Phase 2 — Active ragdoll character (highest-risk item first)

**Revised approach:** rather than hand-rolling the joint-motor/PD-controller system
described below (still accurate as a fallback plan), we integrated
[blugart-dev/kickback](https://github.com/blugart-dev/kickback) (MIT, Godot 4.7+,
Jolt-based) — see `assets/CREDITS.md`. It implements exactly this pattern (16
`RigidBody3D` bones tracking an animated pose via velocity springs, with
stagger/ragdoll/recovery states and hit routing) already, including a `melee`
impact profile. Original from-scratch plan, kept for context:
~~Build a biped rig: `Skeleton3D` + `RigidBody3D` per major bone (pelvis, spine,
head, upper/lower arm ×2, hand ×2, upper/lower leg ×2, foot ×2), connected with
Jolt joints, with per-joint stiffness/damping chasing an animated target pose.~~

- [x] Rigged base character acquired: Quaternius's CC0 "Universal Animation Library"
  character (Blender Rigify `DEF-` bone naming, 120+ baked animations) —
  `assets/models/characters/quaternius_universal/universal_character.glb`.
- [x] Kickback addon vendored into `addons/kickback/`, Jolt Physics + collision
  layer names configured in `project.godot`.
- [x] `scenes/player.tscn` + `scripts/player.gd`: instances the character,
  auto-detects its Rigify bones via `SkeletonDetector`, and attaches the active
  ragdoll rig at runtime via `KickbackSetup.add_active_rig()`.
- [x] `scenes/ragdoll_test.tscn`: ground plane + light + player, set as
  `run/main_scene` for headless verification.
- [x] Milestone check (**passed**, verified via `godot --headless` runs):
  character stands stably under gravity for 7+ real seconds with `state=NORMAL`
  (springs holding the idle pose, no drift/explosion), and a `melee` impact
  profile hit applied via `receive_hit()` is absorbed cleanly with no errors.
  Found and fixed one real addon bug in the process (see below).
- [x] Walking (camera-relative WASD, or the touch joystick) and a hit strong
  enough to trigger stagger/full ragdoll + get-up recovery are verified —
  see `scripts/kickback_actor.gd`, `scripts/combat_profiles.gd`.

**Bug found & fixed (ours, not upstream-reported yet):** `KickbackSetup.add_active_rig(..., tuning)`
called with `tuning=null` leaves `ActiveRagdollController._tuning` null after
setup, even though `ActiveRagdollController._ready()`'s own `_ensure_config()`
had just filled in a sensible default — `KickbackCharacter._ready()`'s later
`configure(profile, tuning)` call unconditionally overwrites `_tuning` with
whatever we passed, with no null fallback (unlike `_ensure_config()`). Any hit
call (`receive_hit`/`apply_hit`) then warns "called before configure()" and
no-ops. Workaround used here: always pass an explicit `RagdollTuning.create_default()`
instead of `null` (see `scripts/player.gd`). Worth upstreaming as a one-line fix
to `active_ragdoll_controller.gd`'s `configure()`.

## Phase 3 — Physics-driven weapon

**Revised approach, same reasoning as Phase 2:** rather than a driven joint
with a separate mouse-delta-to-wrist-target input mapping (still accurate as
a fallback plan, kept below for context), the sword (`scripts/physics_sword.gd`,
`scenes/sword.tscn`) is a free `RigidBody3D` that velocity-spring-follows the
active-ragdoll rig's own `Hand_R` bone every physics tick — the exact
technique Kickback's `SpringResolver` already uses to drive ragdoll bones
toward an animated pose. Since `Hand_R` is itself a real physics body already
being driven through the existing "Sword_Attack" animation, the sword
inherits real windup/follow-through for free, with no separate input-mapping
system needed. Original plan, kept for context:
~~Sword `RigidBody3D` joined to the hand bone via a driven joint; target
transform for the joint is computed from mouse-delta (or right-stick) input
each frame, translated into a wrist/hand target position+orientation.~~

- [x] Sword grip-follows the rig's `Hand_R` bone (spring, not a rigid joint) — `scripts/physics_sword.gd`.
- [x] Mass/inertia tuning so heavy swings take a windup and follow-through: the blade is a real `RigidBody3D` with its own mass, lerped toward the grip target rather than locked to it, so it lags a fast swing and doesn't teleport-track.
- [x] Contact damage computed from the blade tip's actual measured linear velocity at the moment of contact (`get_tip_velocity()`, using `_integrate_forces`'s live per-step contact list — see the class doc comment for why the contact_monitor signals/polling measured zero hits on a real swing), not a flat "on hit" number. Edge-alignment weighting (blade-normal dot impact direction) was not added on top of this — full contact-velocity tiering already reads clearly; edge alignment is deferred as a feel-polish pass, not core to the vertical slice.
- [x] Getting the blade "stuck": a hit past `STICK_SPEED` slackens the grip spring for `STUCK_DURATION`, so pulling free takes a beat instead of snapping back instantly.
- [x] Milestone check (verified headless): a swing at real contact velocity (~8-30 m/s measured, well above the light/heavy/crushing tier thresholds) reads clearly differently by speed and hit location — see Phase 4's milestone check, which subsumes this one once the ragdoll was attached.

## Phase 4 — Combine ragdoll + weapon
- [x] Attach the Phase 3 weapon system to the Phase 2 active-ragdoll's hand — `player.gd` spawns and attaches the sword in `_ready()`.
- [x] Validated headless: a physics-sword swing at measured contact velocity overpowers the recipient's joint motors exactly like an unarmed shove did in Phase 2 — `NORMAL → STAGGER → RAGDOLL → GETTING UP → NORMAL`, driven entirely by the blade's own contact speed, not a scripted trigger.
- [x] Health/stagger model driven by impact force + hit location (head/torso hits weighted higher) — `CombatProfiles.profile_for_impact()` scales the tier lookup by a per-rig_name location weight before picking light/heavy/crushing, replacing the old fixed-distance-tier raycast.

## Phase 5 — Encounter content
- [ ] One enemy using the same active-ragdoll rig, driven by a minimal state machine (approach, windup swing, recover) rather than full AI planning.
- [ ] One small arena blockout (flat ground + a couple of props) — no need for custom art yet, greybox is fine.
- [ ] Wire in SFX from Phase 1 (clash on weapon-weapon contact, impact on weapon-body contact, footsteps/grunts from the animation packs if bundled).

## Phase 6 — Feel pass / polish (only after Phase 5 works end-to-end)
- [ ] Camera feel (shake/impact frames on big hits).
- [ ] Basic UI (health readout, restart-on-death).
- [ ] Pass on joint tuning across all limbs now that real combat data exists (this always needs a second pass once real content stresses it).

## Explicit non-goals for this plan
- Dismemberment / mesh-cutting.
- Multiplayer/co-op.
- Armor damage modeling, inventory, progression systems.
- Full HEMA-accurate move list (half-swording grips, specific historical techniques) — physics-first combat, not animation-list combat, is the whole point; specific techniques can be layered on once the core loop works.

## Definition of done for this plan
A single player character can walk into a small arena as an active ragdoll, swing a physically-simulated sword with weighted momentum, land a hit on an enemy dummy that reacts believably (stagger or ragdoll-out depending on force), and recover — with placeholder-but-real (not silent/no-op) CC0 art, animation, and sound in place, all license-tracked in `assets/CREDITS.md`.
