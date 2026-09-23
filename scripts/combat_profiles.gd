class_name CombatProfiles
extends RefCounted
## Impact profiles for our melee combat.
##
## Kickback triggers stagger when the AVERAGE spring strength across the rig
## falls under RagdollTuning.stagger_threshold (0.70 by default). Since only
## `strength_spread` bones are weakened per hit, spread — not impulse — is what
## decides whether a hit visibly staggers: the stock Melee preset weakens 2 of
## 16 bones, so its average stays ~0.89 and every hit just gets absorbed.
## These profiles are spread-tuned so each tier actually reads on screen.


## Glancing blow: a flinch, no loss of footing.
static func light_swing() -> ImpactProfile:
	return _make(&"Light Swing", 14.0, 0.55, 0.0, 0.0, 0.85, 2, 0.35)


## Committed swing: overwhelms the springs across the upper body, so the
## character visibly loses balance and staggers, occasionally going down.
static func heavy_swing() -> ImpactProfile:
	return _make(&"Heavy Swing", 26.0, 0.85, 0.05, 0.25, 0.95, 7, 0.22)


## Full-force blow: near-certain full ragdoll, then get-up recovery.
static func crushing_blow() -> ImpactProfile:
	return _make(&"Crushing Blow", 42.0, 1.0, 0.25, 0.95, 1.0, 99, 0.15)


## Blade-tip speed (m/s) at/above which a physics-sword hit reads as that tier.
## Tuned against the actual "Sword_Attack" clip's measured hand speed (see the
## PR description) rather than guessed round numbers.
const HEAVY_SPEED := 3.0
const CRUSHING_SPEED := 5.5

## Hit-location weighting (PLAN.md Phase 4: "head/torso hits weighted higher,
## not a generic HP bar tick"): scales the effective speed used for the tier
## lookup, so a solid hit to the head reaches a heavier tier than the same
## blade speed landing on a limb.
const _LOCATION_WEIGHT := {
	&"Head": 1.6,
	&"Chest": 1.0, &"Spine": 1.0, &"Hips": 1.0,
}
const _DEFAULT_LOCATION_WEIGHT := 0.7


## Picks a profile for a physics-sword hit from its actual contact speed and
## where it landed, instead of a fixed distance-tier (see player.gd's old
## _resolve_swing raycast, which this replaces for weapon hits).
static func profile_for_impact(speed: float, rig_name: String) -> ImpactProfile:
	var effective := effective_speed(speed, rig_name)
	if effective >= CRUSHING_SPEED:
		return crushing_blow()
	elif effective >= HEAVY_SPEED:
		return heavy_swing()
	else:
		return light_swing()


## Blade speed after hit-location weighting — the number both the tier lookup
## and the feedback scaling read, so what you see matches what the rig felt.
static func effective_speed(speed: float, rig_name: String) -> float:
	var weight: float = _LOCATION_WEIGHT.get(StringName(rig_name), _DEFAULT_LOCATION_WEIGHT)
	return speed * weight


## Continuous 0..1 severity for the same hit, for feedback that shouldn't jump
## in three steps the way the profile tiers do: blood volume, shake, hit-stop
## length and audio pitch all scale off this. The tier boundaries sit at 0.5
## and 0.8 so the curve still lines up with which profile actually fired.
static func severity_for(speed: float, rig_name: String) -> float:
	var effective := effective_speed(speed, rig_name)
	if effective >= CRUSHING_SPEED:
		return clampf(0.8 + (effective - CRUSHING_SPEED) / 15.0, 0.8, 1.0)
	elif effective >= HEAVY_SPEED:
		return lerpf(0.5, 0.8, (effective - HEAVY_SPEED) / (CRUSHING_SPEED - HEAVY_SPEED))
	return lerpf(0.1, 0.5, clampf(effective / HEAVY_SPEED, 0.0, 1.0))


## Location weighting for the wound model: head and torso blows are the
## dangerous ones, a cut hand is not a cut throat.
const _WOUND_WEIGHT := {
	&"Head": 1.9, &"Chest": 1.15, &"Spine": 1.05, &"Hips": 0.95,
	&"UpperArm_L": 0.6, &"UpperArm_R": 0.6, &"LowerArm_L": 0.45, &"LowerArm_R": 0.45,
	&"Hand_L": 0.3, &"Hand_R": 0.3, &"UpperLeg_L": 0.75, &"UpperLeg_R": 0.75,
	&"LowerLeg_L": 0.5, &"LowerLeg_R": 0.5, &"Foot_L": 0.3, &"Foot_R": 0.3,
}


static func location_weight(rig_name: String) -> float:
	return float(_WOUND_WEIGHT.get(StringName(rig_name), 0.7))


## Knock tier from delivered momentum (speed x mass x weapon stagger /
## target stability) — how hard the blow shoves the rig, independent of how
## much it wounds. An armoured man takes a sword cut without losing his feet;
## the same man is rocked by a mace.
const HEAVY_FORCE := 8.5
const CRUSHING_FORCE := 17.0


## Continuous profile for a blow that delivered [param force] (momentum units,
## see KickbackActor.receive_weapon_hit) to a man whose capture point sits
## [param margin] m inside his support polygon (negative = already off
## balance). No dice: the impulse, how much of the body is overpowered and
## whether he goes down all follow from how hard he was hit and how well he
## was standing. A weak blow bends him, a solid one moves torso and arm and
## makes him step, a huge one overpowers the rig.
static func profile_for_blow(force: float, margin: float) -> ImpactProfile:
	var f := maxf(force, 0.0)
	var impulse := _piecewise(f, [[0.0, 6.0], [4.0, 14.0], [HEAVY_FORCE, 26.0], [CRUSHING_FORCE, 42.0], [30.0, 55.0]])
	var spread := 1 if f < 3.0 else (2 if f < HEAVY_FORCE else (7 if f < CRUSHING_FORCE else 99))
	var reduction := _piecewise(f, [[0.0, 0.5], [HEAVY_FORCE, 0.9], [CRUSHING_FORCE, 1.0]])
	var steady := maxf(margin, 0.0)
	var down := f >= CRUSHING_FORCE * (1.0 + steady * 3.0) or (margin < -0.05 and f >= HEAVY_FORCE)
	var name := &"Light Swing" if f < HEAVY_FORCE else (&"Heavy Swing" if f < CRUSHING_FORCE else &"Crushing Blow")
	return _make(name, impulse, _piecewise(f, [[0.0, 0.5], [CRUSHING_FORCE, 1.0]]),
		0.0 if f < HEAVY_FORCE else 0.1, 1.0 if down else 0.0, reduction, spread,
		_piecewise(f, [[0.0, 0.4], [CRUSHING_FORCE, 0.15]]))


static func _piecewise(x: float, pts: Array) -> float:
	if x <= float(pts[0][0]):
		return float(pts[0][1])
	for i in range(1, pts.size()):
		if x <= float(pts[i][0]):
			var a: Array = pts[i - 1]
			var b: Array = pts[i]
			return lerpf(float(a[1]), float(b[1]), (x - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(pts[-1][1])


static func profile_for_force(force: float) -> ImpactProfile:
	if force >= CRUSHING_FORCE:
		return crushing_blow()
	elif force >= HEAVY_FORCE:
		return heavy_swing()
	return light_swing()


static func _make(pname: StringName, impulse: float, transfer: float, upward: float,
		ragdoll_prob: float, reduction: float, spread: int, recovery: float) -> ImpactProfile:
	var p := ImpactProfile.new()
	p.profile_name = pname
	p.base_impulse = impulse
	p.impulse_transfer_ratio = transfer
	p.upward_bias = upward
	p.ragdoll_probability = ragdoll_prob
	p.strength_reduction = reduction
	p.strength_spread = spread
	p.recovery_rate = recovery
	return p
