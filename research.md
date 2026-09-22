# Research: Building a "Half Sword"-style Physics Combat Game

## 1. What Half Sword actually is

[Half Sword](https://store.steampowered.com/app/2397300/Half_Sword/) (Half Sword Games) is a physics-driven medieval melee combat sim, currently in Steam Playtest. The things that make it distinctive, and that we need to reproduce:

- **The weapon is a physical object, not an animation.** There's no "swing animation" being played on hit-detection triggers. The sword is attached to the player's hand (via the arm) and follows mouse/stick input as a *target position*, with the actual sword pose reached through physics (spring/PD forces or joint drives). Damage comes from actual momentum + edge alignment at the moment of contact, not from a hitbox turning on during frame 12 of a clip.
- **The character is an active ragdoll.** The body is a full physics ragdoll (rigid bodies + joints) that is *driven* toward a target animated pose by motors/torques, rather than a kinematic skeleton. When it takes a big enough hit, the motors lose the fight against the impact and the body goes fully limp — that's why every knockdown looks different and slightly absurd.
- **Momentum and mass matter.** Swing speed builds from the actual arm/torso motion (players wind up before swinging), a heavy overhead swing carries more force than a flick, and getting a weapon stuck in an opponent (or the ground) is a real physical event, not a scripted "your weapon is now stuck" state.
- **Historical/HEMA-informed combat** — half-swording (gripping the blade for thrusts/leverage), thrusts, and grapples, with real armor mitigating some damage.
- The dev-side price of all this: physics-driven characters are much harder to keep stable and readable than animation-driven ones, so most of the engineering effort in a clone goes into taming the ragdoll, not into content.

## 2. Genre neighbors worth studying

| Game | Relevant technique |
|---|---|
| **Blade & Sorcery** | Physics weapon handling in VR, but same core idea: weapon position follows hand target via physics, not a swing animation. |
| **Mordhau / Chivalry 2** | "Real" combat feel (windup/release timing, directional attacks) but animation-driven, not physics-driven — good reference for *feel*, not for *implementation*. |
| **Gang Beasts / Human: Fall Flat** | The classic "floppy active ragdoll" locomotion approach (PD-controlled joints chasing a target pose) that Half Sword's body physics descends from. |
| **Sundered Passage / My Friend Pedro (2D)** | Cheaper 2D-esque ragdoll experiments if a full 3D active ragdoll turns out too heavy for a first prototype. |

## 3. Technical approach in Godot

Our project is already on **Godot 4.7.2** (verified installed in this environment). As of **Godot 4.6+, Jolt is the default 3D physics engine** (previously an optional plugin, `godot-jolt`). This matters a lot for us:

- Jolt's solver converges faster and is noticeably more stable for ragdolls than the legacy GodotPhysics/Bullet backends — ragdolls settle instead of jittering forever.
- Jolt ships extra joint nodes (`JoltGeneric6DOFJoint3D`, etc.) with breakable joints, soft limits, and per-joint solver iteration overrides — exactly the toolkit an active-ragdoll needs (breakable joints are how a weapon could realistically get "torn out of" a limb, for example).
- We should **not** reach for the older `R3X-G1L6AME5H/Godot-Active-Ragdolls` plugin (MIT-licensed, solid reference) as-is — it targets the old Bullet-only `Generic6DOFJoint`, and post-4.6 the built-in Jolt joints supersede it. It's still worth reading as a reference implementation of the "RigidBody3D + joint motor chasing an animated target" pattern, we just re-implement it on native Jolt joints.

### Active ragdoll pattern (confirmed via multiple independent sources)
1. Character has two skeletons/representations: an **animated** target skeleton (plays normal `AnimationPlayer` clips — idle, walk, swing windup) and a **physical** ragdoll made of `RigidBody3D` bones connected by joints.
2. Every physics frame, for each physical bone, compute the rotation/position delta to its corresponding animated-target bone and apply a corrective torque/force (a PD controller: proportional to the error, damped by angular velocity) via the joint motor.
3. As long as accumulated external force is below a threshold, the ragdoll tracks the animation almost exactly (looks fully animated). Once a big enough hit lands, the motor can't correct fast enough, and the body goes full ragdoll — then blends back to "recovering" once it settles.
4. Godot 4's `PhysicalBoneSimulator3D` + `PhysicalBone3D.linear/angular_damp` and the `PhysicalBone3D.get_simulate_physics()` toggle give a built-in (if limited) version of this blend; several devs report better results building the rig manually from `RigidBody3D` + Jolt joints for full control over motor strength per-joint.

### Weapon physics
- Sword is a `RigidBody3D` attached to the hand bone via a joint (or, simpler v1: a strong 6DOF joint with a target transform driven by input) rather than parented rigidly — this is what gives "the sword lags behind your hand" weight/momentum feel.
- Collision damage should be computed from **relative velocity at the contact point** (dot product of blade edge direction and impact velocity for "did it hit flat or edge") rather than a flat damage number — this is the single biggest "feel" contributor and the thing pure-animation games can't fake.

### Suggested build order (validated by the "active ragdoll" tutorials found)
Start with **the ragdoll and the weapon separately** before combining them:
1. Get a believable active-ragdoll biped standing/walking/falling over and recovering.
2. Get a sword that follows mouse/right-stick input on a *static, non-ragdoll* test dummy (mannequin) and validate the momentum/edge-alignment damage math against a punching-bag style target.
3. Only then merge: attach the weapon system to the active-ragdoll's hand.

## 4. Open-source / free asset sources (no paid packs)

All of the below are CC0 or otherwise free-for-commercial-use with no attribution required unless noted. This project should only pull from these categories.

### 3D weapon models
- **OpenGameArt — [3D Swords Pack](https://opengameart.org/content/3d-swords-pack)** — 9 low-poly swords, `.blend`/`.obj`/`.fbx`, CC0.
- **OpenGameArt — [CC0 - 3D Weapons](https://opengameart.org/content/cc0-3d-weapons)** — broader weapon set, CC0.
- **OpenGameArt — [Cethiel's Weapons 3D](https://opengameart.org/content/cethiels-weapons-3d)** — hand-painted-style RPG swords/shields, CC0.
- **Poly Haven — [Weapons models](https://polyhaven.com/models/weapons)** — CC0, no login required, high production value.
- **Kenney** — no dedicated melee/sword kit found (their weapon-shaped kit is the gun-focused *Blaster Kit*), but Kenney's general asset library (all CC0) is worth mining for armor/prop filler geometry.

### Character animation
- **[Universal Animation Library by Quaternius](https://quaternius.itch.io/universal-animation-library)** — 120+ animations on a Mixamo-compatible humanoid rig, explicitly built to work with Godot, free for personal/educational/commercial use. Includes combat motions plus locomotion/emotes — this is our primary animation source since it removes the Mixamo-export dance entirely.
- **kevdev — [Human Melee Animations](https://kevdev.itch.io/human-melee-animations)** — dedicated melee swing/parry/block set, itch.io, free tier.
- **Mixamo** (mixamo.com) — fallback/supplemental source if we need a specific motion the above don't cover; requires the manual FBX→Godot BoneMap workflow (a community plugin exists to automate re-targeting once one character is mapped).

### Sound effects (SFX)
- **OpenGameArt — [CC0 Sound Effects](https://opengameart.org/content/cc0-sound-effects)** and **[CC0 Sounds Library](https://opengameart.org/content/cc0-sounds-library)** — general CC0 SFX collections.
- **OpenGameArt — [Punches, hits, swords and squishes](https://opengameart.org/content/punches-hits-swords-and-squishes)** — exactly our impact-SFX category.
- **OpenGameArt — [Battle Sound Effects](https://opengameart.org/content/battle-sound-effects)** — clashes/battle ambience.
- **Freesound.org** — 500,000+ community sounds, filterable to CC0 specifically; good for one-off foley (armor jingle, cloth, grunts) once the above packs are exhausted.

### Licensing rule for this project
Every asset we vendor into the repo must be CC0 (preferred) or CC-BY (attribution tracked in an `ASSETS.md`/`CREDITS.md` file). No packs with NC (non-commercial) or ND (no-derivatives) clauses, since we don't know the eventual distribution intent of this project.

## 5. Risks / open questions

- **Active ragdoll stability is the highest-risk item.** Every source above stresses that tuning joint motor strength/damping per-joint is fiddly and it's easy to end up with an exploding or floppy-noodle character. Budget real iteration time here before touching content.
- **Godot doesn't have a built-in "IK hand follows mouse with physics" solution** — this is bespoke code (a `RigidBody3D` or joint-driven weapon with a target transform recomputed from camera/mouse delta each frame).
- **Performance**: full per-limb rigid-body ragdolls for the player *and* multiple enemies simultaneously is more expensive than animated enemies; may need to cap simultaneous full-ragdoll combatants or degrade distant enemies to animation-only.
- **Dismemberment/gore** (if wanted, à la Half Sword) is a separate, later-stage feature — needs either mesh-splitting or pre-cut/socket-swap character models — deliberately scoped out of the initial plan below.

Sources consulted are linked inline above.
