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
	var weight: float = _LOCATION_WEIGHT.get(StringName(rig_name), _DEFAULT_LOCATION_WEIGHT)
	var effective := speed * weight
	if effective >= CRUSHING_SPEED:
		return crushing_blow()
	elif effective >= HEAVY_SPEED:
		return heavy_swing()
	else:
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
