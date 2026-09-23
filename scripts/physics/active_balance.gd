class_name ActiveBalance
extends Node
## The fighter's balance layer, between the animated pose and the ragdoll.
##
## Reads the controller's BalanceState every physics tick (centre of mass of
## every rig body *plus the held weapons*, the support polygon of the feet
## actually on the ground, and the capture point — where the body will come
## to rest if nothing else acts) and turns it into behaviour:
##
##   stable      capture point well inside the feet
##   correcting  near the edge: nothing scripted, the springs lean back
##   off_balance outside the feet: take a physical recovery step toward the
##               capture point (Kickback's foot-pinned stumble step, with the
##               drift set by how fast the body is actually leaving)
##   stumble     the controller is mid-stagger / stepping
##   down        ragdoll, recovering, or dead
##
## Injured legs shrink the tolerated margin and slow the correction, so a man
## with a cut thigh stumbles where a fresh one would only sway.

const STEP_MARGIN := -0.035  ## m outside the polygon before a step is taken
const STEP_HOLD := 0.06      ## s the capture point must stay out
const STEP_COOLDOWN := 0.45
const MAX_DRIFT := 2.8

var actor: KickbackActor
var state := "stable"
var margin := 0.0
var capture_point := Vector3.ZERO
var com := Vector3.ZERO
## 0..1 leg function (InjurySystem writes it); < 1 makes balance worse.
var leg_function := 1.0

var _out_time := 0.0
var _cooldown := 0.0
var _controller: ActiveRagdollController


func setup(a: KickbackActor, controller: ActiveRagdollController) -> void:
	actor = a
	_controller = controller


func _physics_process(delta: float) -> void:
	if not _controller or not actor:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	var bs := _controller.get_balance()
	margin = bs.margin
	capture_point = bs.xcom
	com = bs.com
	var cstate := _controller.get_state_name()
	if actor.is_dead() or actor.is_downed() or cstate in ["RAGDOLL", "GETTING UP", "PERSISTENT"]:
		state = "down"
		return
	if cstate == "STAGGER":
		state = "stumble"
		_out_time = 0.0
		return
	if not bs.has_support:
		state = "off_balance"
		return
	# An injured leg narrows what the body tolerates before it must step.
	var tolerance := STEP_MARGIN * lerpf(0.3, 1.0, leg_function)
	if margin > 0.06:
		state = "stable"
		_out_time = 0.0
	elif margin > tolerance:
		state = "correcting"
		_out_time = 0.0
	else:
		state = "off_balance"
		_out_time += delta
		if _out_time >= STEP_HOLD and _cooldown <= 0.0 and not actor.is_intentionally_moving():
			var dir := Vector3(bs.imbalance_dir.x, 0.0, bs.imbalance_dir.y)
			var out_speed := Vector2(bs.com_velocity.x, bs.com_velocity.z).length()
			var drift := clampf(out_speed * 1.6 + (-margin) * 3.0, 0.35, MAX_DRIFT) / lerpf(0.6, 1.0, leg_function)
			if dir.length_squared() > 0.01 and _controller.request_balance_step(dir.normalized(), drift):
				_cooldown = STEP_COOLDOWN
				_out_time = 0.0
				state = "stumble"
