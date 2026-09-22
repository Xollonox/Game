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
- [ ] Build a biped rig: `Skeleton3D` + `RigidBody3D` per major bone (pelvis, spine, head, upper/lower arm ×2, hand ×2, upper/lower leg ×2, foot ×2), connected with Jolt joints (`JoltGeneric6DOFJoint3D` or equivalent) with realistic angular limits per joint (elbows/knees are hinges, not full 6DOF).
- [ ] Implement the "animated target chase" loop: each physics tick, read the bone transform from the animated skeleton, compute the delta to the corresponding physical bone, apply a corrective joint-motor torque scaled by a per-joint stiffness/damping pair.
- [ ] Tune stiffness low enough that a solid hit overpowers the motors (ragdoll goes limp) but high enough that idle/walk looks controlled, not jittery.
- [ ] Implement recovery: once the ragdoll's velocity settles below a threshold for N frames, blend the character back toward a "getting up" animation.
- [ ] Milestone check: character can stand, walk a patrol path, take a shove, fall, and get back up — **before any weapon work starts** (per research.md's recommended build order).

## Phase 3 — Physics-driven weapon
- [ ] Sword `RigidBody3D` joined to the hand bone via a driven joint; target transform for the joint is computed from mouse-delta (or right-stick) input each frame, translated into a wrist/hand target position+orientation.
- [ ] Add mass/inertia tuning so heavy swings actually take a windup and follow-through (i.e. the sword doesn't teleport-track the cursor).
- [ ] Contact damage computed from relative velocity at the contact point, weighted by edge alignment (dot product of blade edge normal vs. impact velocity direction) — not a flat "on hit" number.
- [ ] Getting the blade stuck (in a target or the ground) when velocity/angle crosses a threshold, requiring a tug to free it.
- [ ] Milestone check: on the *static test dummy* (no ragdoll yet), swings feel weighted and a fast edge-on hit clearly registers differently than a flat/pommel bump.

## Phase 4 — Combine ragdoll + weapon
- [ ] Attach the Phase 3 weapon system to the Phase 2 active-ragdoll's hand.
- [ ] Validate that a solid weapon impact can overpower the recipient's joint motors exactly like an unarmed shove did in Phase 2.
- [ ] Add a simple health/stagger model driven by impact force + hit location (head/torso hits weighted higher), not a generic HP bar tick.

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
