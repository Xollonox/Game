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
