class_name Enemy
extends KickbackActor
## A sword-carrying opponent: closes distance, commits to a swing, then backs
## off while it recovers (PLAN.md Phase 5).
##
## Deliberately a four-state machine rather than anything that plans. The fight
## is interesting because the *physics* is unpredictable — an enemy that gets
## staggered mid-windup drops its swing and has to re-approach, and that falls
## out of the rig, not out of the AI. Sophistication here would mostly be hidden
## behind that.
##
## Nothing about the swing is scripted damage: the enemy plays the same
## "Sword_Attack" clip the player does, and its blade deals whatever its own
## measured contact speed earns, through the same PhysicsSword path.

enum State { IDLE, APPROACH, WINDUP, RECOVER }

## Beyond this the enemy ignores the target entirely.
@export var aggro_range := 15.0
## Distance it wants to be at before committing to a swing.
@export var strike_range := 1.75
## Held back to just outside strike range so it doesn't walk into its own blade.
@export var spacing := 1.4
## Seconds between spotting the target in range and actually swinging — this is
## the entire "difficulty" knob, and what keeps several enemies from swinging in
## perfect unison.
@export var windup := 0.6
## Seconds of backing off after a swing, during which it won't attack again.
@export var recover_time := 1.45

## How close two enemies get before they start pushing apart. Without this they
## all take the same straight line to the target, arrive as one clump, and
## spend the fight hitting each other instead of the player.
const SEPARATION_RADIUS := 2.4
const SEPARATION_WEIGHT := 1.35

var target: KickbackActor

var _state := State.IDLE
var _timer := 0.0
var _strafe := 1.0
var _peers: Array[Enemy] = []
## Staggered opening: without it every opponent commits on the same frame and
## the fight opens as a pile-on, which reads as unfair and looks like a scrum
## rather than a duel. Each fighter waits a beat of their own before engaging,
## so the fight escalates instead of starting at full pressure. Set once in
## _ready() and never re-armed, or the fighters would keep pausing mid-duel.
var _engage_delay := 0.0


func _ready() -> void:
	super._ready()
	# Each enemy gets its own cadence, so a group reads as several fighters
	# rather than one fighter rendered three times.
	windup *= randf_range(0.75, 1.4)
	recover_time *= randf_range(0.8, 1.3)
	_strafe = 1.0 if randf() < 0.5 else -1.0
	_engage_delay = randf_range(0.5, 2.8)


func _physics_process(delta: float) -> void:
	_tick_ai(delta)
	super._physics_process(delta)


func _tick_ai(delta: float) -> void:
	_timer = maxf(0.0, _timer - delta)

	# Hold back through the opening beat, then join the fight for good.
	if _engage_delay > 0.0:
		_engage_delay = maxf(0.0, _engage_delay - delta)
		move_dir = Vector3.ZERO
		_state = State.IDLE
		return

	# While down or getting up the rig owns the body; queuing intent through
	# that would make it lurch the instant it stands. A dead fighter (its own,
	# or its target's) ends the engagement entirely.
	if is_dead() or is_downed() or not target or target.is_dead() or target.is_downed():
		move_dir = Vector3.ZERO
		_state = State.IDLE
		return

	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	if dist < 0.01 or dist > aggro_range:
		move_dir = Vector3.ZERO
		_state = State.IDLE
		return

	var dir := to_target / dist

	match _state:
		State.IDLE, State.APPROACH:
			if dist > strike_range:
				move_dir = (dir + _separation() * SEPARATION_WEIGHT).normalized()
				_state = State.APPROACH
			else:
				move_dir = Vector3.ZERO
				_state = State.WINDUP
				_timer = windup

		State.WINDUP:
			# Face the target and circle slightly — standing perfectly still
			# through the windup reads as the enemy having frozen.
			move_dir = dir.cross(Vector3.UP) * _strafe * 0.35
			if _timer <= 0.0:
				if dist <= strike_range + 0.6 and swing():
					_state = State.RECOVER
					_timer = recover_time
				else:
					# Target moved out of reach during the windup — re-close
					# rather than swinging at nothing.
					_state = State.APPROACH

		State.RECOVER:
			# Give ground while the swing plays out, so a duel has rhythm
			# instead of both fighters standing chest-to-chest.
			move_dir = -dir * 0.6 if dist < strike_range + spacing else Vector3.ZERO
			if _timer <= 0.0:
				_state = State.APPROACH
				_strafe = 1.0 if randf() < 0.5 else -1.0


## Unit-ish push away from nearby enemies, strongest when nearly overlapping.
## Peers are cached on first use rather than looked up per frame: the group
## contents don't change during a fight, and this runs for every enemy every
## physics tick.
func _separation() -> Vector3:
	if _peers.is_empty():
		for node in get_tree().get_nodes_in_group("hittable"):
			if node is Enemy and node != self:
				_peers.append(node)

	var push := Vector3.ZERO
	for other in _peers:
		var away := global_position - other.global_position
		away.y = 0.0
		var d := away.length()
		if d > 0.01 and d < SEPARATION_RADIUS:
			push += (away / d) * (1.0 - d / SEPARATION_RADIUS)
	return push
