# Bare Steel — physics and combat architecture

How a blow travels from a key press to a wound, and why touching is not
striking. Every number below lives in code; this document says where.

## Pipeline

```
input / AI intent
  └─ KickbackActor.attack(kind, dir)          scripts/kickback_actor.gd
       └─ AttackLibrary move (clip + phases)  scripts/attack_library.gd
            └─ animation pose (Blender-authored, tools/blender/melee_anims.py)
                 └─ Kickback arm/foot IK overrides (secondary grip, pickup reach, stumble steps)
                      └─ ActiveBalance (capture point, recovery steps)   scripts/physics/active_balance.gd
                           └─ SpringResolver → 16 RigidBody3D bones (Jolt)  addons/kickback
                                └─ PhysicsWeapon (RigidBody3D spring-pulled to the hand)  scripts/physics_weapon.gd
                                     └─ contact → WeaponContactEvaluator   scripts/combat/weapon_contact_evaluator.gd
                                          └─ receive_weapon_hit → armour → InjurySystem   scripts/combat/injury_system.gd
                                               └─ consequences: springs, grip, gait, balance, blood
```

Player and AI share every layer. AI skill is timing, guard choice, spacing
and attack choice — never a damage multiplier.

## Valid-hit rules (WeaponContactEvaluator)

A weapon–body contact is scored from the live contact list inside
`PhysicsWeapon._integrate_forces`.

1. **Relative velocity at the contact point**
   `v_rel = (v_w + ω_w × (p − com_w)) − (v_t + ω_t × (p − com_t))`.
2. **Surface and direction** in the weapon frame measured in Blender
   (X = flat, Y = edge to edge, −Z = toward the point):
   - cut: `edge speed = |v_rel·Y| ≥ min_cut` and `≥ edge_align · |v_rel|`;
   - thrust: `axial = v_rel·(−Z) ≥ min_thrust` and `≥ thrust_align · |v_rel|`;
   - blunt (head, shield, fist, foot): `normal speed = |v_rel·n| ≥ min_blunt`;
   - flat of a blade → blunt × 0.45; scraping along the blade → blunt × 0.25;
     haft / guard / pommel → blunt × 0.35.
3. **Energy**: ½·m·(qualifying speed)² ≥ per-kind minimum.
4. **Intent**: the wielder's attack phase from the clip's normalized time
   (`AttackLibrary.DEFAULT_PHASES = [wind-up, strike, end of follow]`):
   prep 0, accel 0.6, active 1.0, follow 0.75, recovery 0. With no attack
   (dropped / flung weapons) a contact must carry ≥ 45 J.
5. **Contact lifetime** (`ContactLog`): only the first step of a contact is
   an impact; sustained contact is never rescored; a new impact needs 0.12 s
   of separation; one blow per man per swing (`attack_serial`).

Thresholds per class are in `CLASS_DEFAULTS`; any weapon can override them
in `WeaponCatalog.STATS`. There is no global minimum speed.

Damage from a valid blow: `raw = 2.6 · speed · √(m/1.2) · channel · quality`
where `speed` is the qualifying component, `channel` the weapon's cut /
pierce / blunt delivery and `quality` intent × alignment.

## Armour

`Armory.LAYERS` gives every garment `[slots, cut, pierce, blunt, cover,
weight…]`. For the struck rig body, each covering layer that the blow finds
(cover roll) multiplies what gets through by `(1 − protection)`:

- **flesh** = raw × remaining(kind) — plate ~0.05–0.1 for cuts, mail ~0.2;
- **trauma** = the blunt part of the blow × remaining(blunt) — plate turns
  the edge but the man inside still takes the blow.

Hard hits (plate/mail struck, <35 % through) spark and ring
(`CombatFX.armor_impact`).

## Regional injuries (InjurySystem)

17 regions (head, neck, chest, abdomen, pelvis, upper arm / forearm / hand
×2, thigh / shin / foot ×2), each with tissue, blunt trauma, bleed rate,
fracture and severed state; function = 1 − 0.75·tissue − 0.55·blunt
(fracture caps it at 0.25).

| Region | Consequence |
|---|---|
| sword arm | springs capped (`SpringResolver.impairment`), weapon control ×0.3–1, attack rate, grip strength; <0.2 drops the weapon |
| shield arm | shield control; <0.15 drops the shield |
| legs | gait speed ×0.35–1, balance tolerance; a leg under 0.12 gives way |
| head | concussion stun (a balance stumble), a crushed skull kills |
| neck / torso | heavy bleeding, winded (slower attacks), lethal wounds kill |

`health` is systemic: the lethal share of each wound plus blood loss;
bleeding clots over time; losing 55 % of the blood is fatal.

## Active ragdoll and balance

Kickback 0.4 (vendored, MIT) drives 16 Jolt bodies with velocity springs
toward the animated pose. Bare Steel changes (all marked "Bare Steel" in the
source):

- `BalanceState` vendored from upstream's 0.6 branch: CoM of every rig body
  plus held weapons, support polygon of the feet actually on the ground
  (ray-tested — Kickback zeroes foot masks for IK), capture point
  `xcom = com + v/√(g/h)` and its margin to the polygon edge.
- `ActiveBalance`: stable / correcting / off_balance / stumble / down. When
  the capture point leaves the feet (and the fighter is not deliberately
  moving or attacking) it takes a real recovery step toward it
  (`request_balance_step`), re-stepping rather than falling while steps
  remain.
- Blows use `CombatProfiles.profile_for_blow(force, margin)`: impulse,
  spread and knockdown are continuous in delivered momentum; a knockdown
  happens when force beats the victim's balance margin — no dice.
- Get-up: the clip is timed to the strength ramp (smoothstep, not cubic)
  and held until recovery completes, then cross-faded to the stance.
- Joint limits corrected to anatomy in `BodyAnatomy` (hinge knees and
  elbows, limited wrists and neck).

## Weapon grip, parries, disarms, pickup

- `PhysicsWeapon` is a RigidBody3D pulled to the hand by a mass- and
  length-scaled spring; heavy weapons lag and overshoot.
- Markers from Blender (`markers` in each `<id>.json`): GripPrimary,
  GripSecondary, Pommel, Guard, EdgeStart/EdgeEnd, Tip, Head, Shaft.
- Two-handed weapons: the off hand is Kickback arm IK toward the *actual*
  weapon's GripSecondary each step (compliant, not welded).
- Weapon–weapon contact softens the hand spring (`soften`) and a sustained
  bind lowers it further, so parries physically change the blade's path.
- `WeaponGrip`: strength = hands × arm function × state × intent. Strain
  (how hard the hand must drag the weapon back, only while something
  resists it) above strength for 0.14 s, or a shock > 2.2 × strength (hard
  parry, blow to the weapon arm), tears it loose. Falls and death release
  weapons.
- Dropped weapons are ordinary rigid bodies in group `world_items`; the
  former wielder is ignored for 0.6 s, then they rest against him harmlessly.
- Pickup (player E / touch TAKE; AI when disarmed): the fighter steps in,
  plays `PickUp_Low`, arm IK reaches the grip, the weapon attaches only when
  the hand closes and is drawn in with a speed cap (no teleport); it ignores
  the ground until seated so the solver cannot pop it out of the floor.

## Unarmed

Punches (Jab, Cross, Hook) and kicks (`Kick_Front`, `Kick_Low`, authored in
`melee_anims.py`) strike with the fist or foot rig body: `BodyStriker`
sphere-queries the striking limb during accel/active/follow and scores the
contact through the same evaluator (fist 2.2 kg, foot 5.5 kg effective).
Anyone can kick (V / touch KICK); no attacks while stumbling.

## Collision layers

| Layer (bit) | Contents | Mask |
|---|---|---|
| 1 (1) | environment | — |
| 2 (2) | weapons, dropped weapons, armour items | env · weapons · ragdoll |
| 4 (8) | active-ragdoll bodies | env · weapons · 3 · ragdoll |
| 6 (32) | severed limbs | env · weapons · ragdoll · limbs |

A fighter's own bodies are collision exceptions for his weapons (and his
weapon for his shield). The root is a Node3D with no collider, so fighters
meet only through their ragdoll bodies — which never deal weapon damage.

## Tests

```bash
xvfb-run -a godot --path . res://tests/contact_test.tscn   # touching is not striking; valid cuts/thrusts/blows; punches, kicks; armour
xvfb-run -a godot --path . res://tests/balance_test.tscn   # weak/solid/huge blows, recovery steps, get-up, dead stay down
xvfb-run -a godot --path . res://tests/injury_test.tscn    # regional wounds and consequences, plate vs flesh
xvfb-run -a godot --path . res://tests/item_test.tscn      # disarm, drop, rest harmlessly, pickup without teleport, AI retrieval
```

## Blood (BleedingSource)

Every flesh wound attaches a `BleedingSource` to the struck rig body at the
exact contact point, facing out of the wound, so it rides the ragdoll. It
reads its region's bleed rate from the InjurySystem:

- the impact spray, thrown with the blow and off the surface;
- drops at a rate proportional to the bleed, and for arterial wounds (neck,
  thigh, a stump) heartbeat spurts that weaken with blood volume;
- each landing is ray-marched (five segments, ignoring the wounded man's own
  bodies) to the surface it hits — floor, wall, another body — and marked
  with a pooled splat when the blood gets there (`CombatFX.splat_at`, pooled
  quads: no depth decals needed on the Compatibility renderer, which is why
  antzGames' decal node was studied but not vendored).

Budgets: 14 active sources (6 on low quality), splats pooled (36) with a
lifetime. With Blood off (`GameState.blood` → `CombatFX.blood_enabled`) no
emitter, splat, overlay or gory cap is created; wounds still count.

## Dismemberment

`tools/blender/segments.py` cuts every skinned mesh of the fighter along
the limb segments (dominant bone weight per face, corner normals frozen so
the join is invisible): head, upper arm, forearm, hand, thigh, shin, foot per
side, core. `Dismemberment.qualifies` lets a zone go (neck, shoulder,
forearm, wrist, hip, knee) only to a sharp edge (cut ≥ 0.9) leading well
(quality ≥ 0.65) into flesh the armour let ≥ 60 % of the edge through (mail
and plate never do), with enough flesh damage for the zone into tissue
already badly cut — or one blow 1.6× the threshold.

On severing: the segments are hidden on the fighter; Kickback stops driving
the limb (`SpringResolver.severed`), its joint is removed and the fighter's
skeleton freezes those bones (`PhysicsRigSync.freeze_rigs`) so stump skin
never stretches after the flying limb; a `DetachedLimb` re-skins the same
segment meshes onto a copied skeleton that follows the freed bodies (own
layer 6, no longer a target, sleeps at rest, 10 at most); flesh-and-bone caps
close both faces; an arterial BleedingSource starts at the stump; held items
fall; a lost leg puts him down; a severed neck kills.

## Armour as equipment

`ArmourItem` is a real rigid body showing the garment's own meshes (from the
fighter model at rest, recentred; box collider; mass = worn weight). The
arena lays a few pieces for the current standing, plus a spare weapon, on a
bench on the fighters' side of the lists. `equip_armour` plays `Equip_Head`
/ `Equip_Body`, swaps out whatever filled the slot (it is set down as an
item), re-dresses the fighter and updates worn weight, gait and body mass;
mail and plate need a gambeson first. A crushing blow can knock a loose
helmet (kettle, cap, coif, hood) off as a flying item. The player's run
follows what he actually wears (`Shop.sync_from_garments`).

## Armour hits

Plate or mail turning a blow reflects the blade's velocity into the surface
and softens the hand for a moment: the edge visibly glances off instead of
the pose pushing it through.

## Tests (all)

```bash
xvfb-run -a godot --path . res://tests/contact_test.tscn
xvfb-run -a godot --path . res://tests/balance_test.tscn
xvfb-run -a godot --path . res://tests/injury_test.tscn
xvfb-run -a godot --path . res://tests/item_test.tscn
xvfb-run -a godot --path . res://tests/blood_test.tscn
xvfb-run -a godot --path . res://tests/sever_test.tscn
xvfb-run -a godot --path . res://tests/armour_test.tscn
```

## Known limits

- The authored front kick lands lower than keyed (knee height), and the
  get-up's hand push-off still peaks near 8 m/s.
- Fights run longer than before touch damage was removed; AI spacing and
  attack animation reach are the next tuning pass.
- NPCs retrieve weapons but do not yet pick armour up.
