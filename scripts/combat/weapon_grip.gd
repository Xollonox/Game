class_name WeaponGrip
extends Node
## How firmly a fighter holds his weapon, what makes him lose it, and the
## second hand on two-handed weapons.
##
## Grip strength = base (one hand 1.0, two hands 1.6) × arm function (wounds)
## × state (a staggering man grips worse; a falling one lets go) × intent
## (a committed attack clenches, an idle guard is looser).
##
## The load is the weapon's own strain (PhysicsWeapon.grip_strain — how far
## the hand must drag it back, leveraged by mass and length) plus sudden
## shocks (a hard parry, a blow landing on the weapon arm). Load above
## strength for a moment, or one shock far above it, tears the weapon loose:
## it flies on with its own momentum as an ordinary rigid body.
##
## Two-handed weapons: the primary hand drives the weapon's spring; the
## secondary hand is not welded — Kickback's arm IK pulls it toward the
## weapon's GripSecondary marker on the *actual* weapon every step, so when
## a bind twists the blade the off hand follows (or slips) instead of the
## weapon snapping back to the animation.

const HOLD_TIME := 0.14      ## s of overload before the grip gives
const SHOCK_FACTOR := 2.2    ## a single shock this far above strength disarms

var actor: KickbackActor
var _overload := 0.0
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
	var state_k := 1.0 if st == "NORMAL" else (0.55 if st == "STAGGER" else 0.0)
	var intent_k := 1.15 if actor.is_swinging() else 1.0
	return base * lerpf(0.12, 1.0, arm) * state_k * intent_k


## A sudden load on the weapon (a parry, a blow to the arm): disarms at once
## if it is far beyond what the hand can hold. [param dir] is where the
## weapon is thrown.
func shock(amount: float, dir: Vector3) -> bool:
	var w := actor.weapon
	if not is_instance_valid(w) or not w.is_held():
		return false
	if amount > strength() * SHOCK_FACTOR:
		disarm(dir * clampf(amount, 1.0, 6.0))
		return true
	return false


func disarm(impulse := Vector3.ZERO) -> void:
	var w := actor.weapon
	if not is_instance_valid(w):
		return
	actor.drop_weapon(impulse)


func _physics_process(delta: float) -> void:
	if not actor or actor.is_dead():
		return
	var w := actor.weapon
	if not is_instance_valid(w) or not w.is_held():
		_release_second_hand()
		_overload = 0.0
		return
	var s := strength()
	if s <= 0.0:
		return
	if w.grip_strain > s:
		_overload += delta
		if _overload >= HOLD_TIME:
			disarm(w.linear_velocity * w.mass * 0.25)
			return
	else:
		_overload = maxf(0.0, _overload - delta * 2.0)
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
