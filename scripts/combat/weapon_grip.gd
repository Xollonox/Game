class_name WeaponGrip
extends Node
## How firmly a fighter holds his weapon, what makes him lose it, and the
## second hand on two-handed weapons.
##
## Grip strength = base (one hand 1.0, two hands 1.6) × arm function (wounds)
## × state (a staggering man grips worse; a falling one lets go) × intent
## (a committed attack clenches, an idle guard is looser).
##
## A trained man does not let go of his weapon because it was parried, bound,
## knocked or because he fell over: only a CRITICAL blow tears it loose —
## a broken or severed weapon arm, a crushing hit on the hand or forearm, or a
## crushing blow that also throws him off his feet (see
## KickbackActor.receive_weapon_hit). Everything else is absorbed by the hand
## spring: a bound blade is pushed aside, a heavy parry jars the arm and the
## blade lags, but the fist stays closed. The weapon then flies on with its
## own momentum as an ordinary rigid body.
##
## Grip strength only scales how far a critical shock throws the weapon.
##
## Two-handed weapons: the primary hand drives the weapon's spring; the
## secondary hand is not welded — Kickback's arm IK pulls it toward the
## weapon's GripSecondary marker on the *actual* weapon every step, so when
## a bind twists the blade the off hand follows (or slips) instead of the
## weapon snapping back to the animation.

## A blow on the weapon arm at least this severe (trauma + flesh / 2, the
## same measure InjurySystem uses) is critical even without a fracture.
const CRITICAL_ARM_BLOW := 26.0

var actor: KickbackActor
var _second_hand_on := false


func setup(a: KickbackActor) -> void:
	actor = a


func strength() -> float:
	var w := actor.weapon
	if not is_instance_valid(w) or not w.is_held():
		return 0.0
	var two := int(w.def.get("hands", 1)) == 2
	var base := 1.6 if two else 1.0
	var arm := actor.injuries.arm_function("r")
	if two:
		arm = arm * 0.65 + actor.injuries.arm_function("l") * 0.35
	var st := actor.get_state_name()
	var state_k := 1.0 if st == "NORMAL" else 0.6
	var intent_k := 1.15 if actor.is_swinging() else 1.0
	return base * lerpf(0.12, 1.0, arm) * state_k * intent_k


## A blow landing on the weapon arm. Disarms only when it is critical:
## [param fractured] / [param severed] this blow, or [param severity]
## (trauma + flesh / 2) past CRITICAL_ARM_BLOW. [param dir] is where the
## weapon is thrown. Returns true if the weapon was lost.
func arm_blow(severity: float, dir: Vector3, fractured := false, severed := false) -> bool:
	var w := actor.weapon
	if not is_instance_valid(w) or not w.is_held():
		return false
	if not (fractured or severed or severity >= CRITICAL_ARM_BLOW):
		return false
	# A weaker hand lets the weapon fly further.
	var throw := clampf(severity / 8.0, 1.0, 5.0) / maxf(strength(), 0.5)
	disarm(dir.normalized() * throw)
	return true


func disarm(impulse := Vector3.ZERO) -> void:
	var w := actor.weapon
	if not is_instance_valid(w):
		return
	actor.drop_weapon(impulse)


func _physics_process(_delta: float) -> void:
	if not actor or actor.is_dead():
		return
	var w := actor.weapon
	if not is_instance_valid(w) or not w.is_held():
		_release_second_hand()
		return
	_track_second_hand(w)


func _track_second_hand(w: PhysicsWeapon) -> void:
	var markers: Dictionary = w.def.get("markers", {})
	if int(w.def.get("hands", 1)) != 2 or not markers.has("GripSecondary") or is_instance_valid(actor.shield):
		_release_second_hand()
		return
	var ik := actor.arm_ik()
	if not ik:
		return
	var target: Vector3 = w.global_transform * WeaponCatalog.v3(markers["GripSecondary"])
	var weight := lerpf(0.35, 0.85, actor.injuries.arm_function("l"))
	ik.begin_reach("L", target, weight)
	_second_hand_on = true


func _release_second_hand() -> void:
	if _second_hand_on:
		var ik := actor.arm_ik()
		if ik:
			ik.end_reach("L")
		_second_hand_on = false
