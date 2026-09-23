class_name Enemy
extends KickbackActor
## An AI fighter.
##
## Still deliberately simple: the fight is interesting because the *physics*
## is unpredictable. What this adds over the original four-state machine is the
## part that makes groups believable:
##
## * Targets are chosen, not assigned. Fighters on other teams are candidates;
##   a blow from anyone (including a supposed ally) can turn a fighter on them,
##   weighted by their "infighting" temperament. Free-for-all bouts put every
##   fighter on their own team.
## * Attack tokens. The bout director (arena) lets only a couple of fighters
##   press any one target at once; the rest circle at their preferred spacing,
##   feint in and out and wait for an opening — a ring of men, not a scrum.
## * Skill drives timing: better fighters guard against a swing they see
##   coming, pick thrusts against armour, and recover faster.

signal wants_token(e: Enemy)

enum State { WAIT, CIRCLE, APPROACH, WINDUP, RECOVER, GUARD, BACKOFF }

var team := 1
var target: KickbackActor
## Set by the arena: returns true if this fighter may press its target now.
var token_granted := func(_e: Enemy) -> bool: return true
var _state := State.WAIT
var _timer := 0.0
var _strafe := 1.0
var _engage_delay := 0.0
var _think := 0.0
var _grudge: KickbackActor
var _grudge_timer := 0.0
var _reach := 1.7
var _skill := 0.5
var _aggr := 0.6
var _spacing := 1.0


func _ready() -> void:
	await super._ready()
	var ai: Dictionary = spec.get("ai", {})
	_skill = float(ai.get("skill", 0.5))
	_aggr = float(ai.get("aggression", 0.6))
	_spacing = float(ai.get("spacing", 1.0))
	var wdef := WeaponCatalog.get_def(spec.get("weapon", ""))
	_reach = 0.75 + float(wdef.get("length", 0.9)) * 0.8
	_strafe = 1.0 if randf() < 0.5 else -1.0
	if _engage_delay <= 0.0:
		_engage_delay = randf_range(0.4, 1.6)
	wounded.connect(_on_wounded)


## Opening beat before this fighter joins (the director staggers entries).
func set_engage_delay(t: float) -> void:
	_engage_delay = t


func _physics_process(delta: float) -> void:
	_tick_ai(delta)
	super._physics_process(delta)


func _tick_ai(delta: float) -> void:
	_timer = maxf(0.0, _timer - delta)
	_grudge_timer = maxf(0.0, _grudge_timer - delta)
	_think -= delta
	sprinting = false
	if is_dead() or is_downed():
		move_dir = Vector3.ZERO
		face_dir = Vector3.ZERO
		set_guard(false)
		return
	if _engage_delay > 0.0:
		_engage_delay -= delta
		move_dir = Vector3.ZERO
		if target:
			face_dir = _flat(target.global_position - global_position)
		return
	if _think <= 0.0:
		_think = 0.4
		_choose_target()
	if not target or target.is_dead():
		move_dir = Vector3.ZERO
		face_dir = Vector3.ZERO
		set_guard(false)
		_state = State.WAIT
		return

	var to_t := _flat(target.global_position - global_position)
	var dist := to_t.length()
	var dir := to_t / maxf(dist, 0.01)
	face_dir = dir
	var side := dir.cross(Vector3.UP) * _strafe
	var ring := _reach + 0.9 * _spacing
	var may_press: bool = token_granted.call(self)

	# Reactive defence: a swing coming in from our target.
	if _state in [State.CIRCLE, State.APPROACH, State.WINDUP] and target.is_swinging() and dist < _reach + 1.2:
		if randf() < _skill * 0.05:
			_state = State.GUARD if randf() < 0.65 else State.BACKOFF
			_timer = randf_range(0.35, 0.7)

	match _state:
		State.WAIT:
			_state = State.CIRCLE
		State.CIRCLE:
			# Hold at the ring, drifting round the target; step in when allowed.
			var radial := (dist - ring) * 1.2
			move_dir = (dir * clampf(radial, -0.8, 0.8) + side * 0.45 + _separation() * 1.2)
			if target.is_downed():
				move_dir += side * 0.3
			if may_press and _timer <= 0.0 and randf() < 0.02 + _aggr * 0.05:
				_state = State.APPROACH
			if randf() < 0.004:
				_strafe = -_strafe
		State.APPROACH:
			move_dir = dir + _separation() * 0.9
			sprinting = dist > 5.0 and _aggr > 0.6
			if not may_press:
				_state = State.CIRCLE
			elif dist <= _reach:
				_state = State.WINDUP
				_timer = lerpf(0.55, 0.12, _skill) * randf_range(0.8, 1.3)
		State.WINDUP:
			move_dir = side * 0.25 + dir * clampf(dist - _reach * 0.85, -0.5, 0.5)
			if _timer <= 0.0:
				if dist <= _reach + 0.5 and attack(_choose_attack(), {"ai": true}):
					_state = State.RECOVER
					_timer = lerpf(1.5, 0.6, _skill) * float(spec.get("ai", {}).get("cadence", 1.0))
				else:
					_state = State.APPROACH
		State.RECOVER:
			var back := dist < ring * 0.9
			move_dir = (-dir * 0.55 if back else Vector3.ZERO) + side * 0.35 + _separation()
			if _timer <= 0.0:
				# A skilled, aggressive fighter keeps pressure with a follow-up.
				if may_press and randf() < _aggr * _skill * 0.8 and dist < _reach + 0.6:
					_state = State.WINDUP
					_timer = 0.1
				else:
					_state = State.CIRCLE
					_timer = randf_range(0.3, 1.4) * (1.4 - _aggr)
					_strafe = 1.0 if randf() < 0.5 else -1.0
		State.GUARD:
			set_guard(true)
			move_dir = -dir * 0.2
			if _timer <= 0.0:
				set_guard(false)
				_state = State.WINDUP if may_press and randf() < _skill else State.CIRCLE
				_timer = 0.12
		State.BACKOFF:
			move_dir = -dir + side * 0.4
			if _timer <= 0.0:
				_state = State.CIRCLE
	if _state != State.GUARD and is_guarding():
		set_guard(false)
	move_dir = move_dir.limit_length(1.0)


## Armour-aware attack choice: thrusts against mail and plate, heavy blows
## with blunt weapons, cuts against cloth.
func _choose_attack() -> String:
	var fam: String = WeaponCatalog.get_def(spec.get("weapon", "")).get("attacks", "sword")
	var armoured := Armory.worn_weight(target.spec.get("garments", [])) > 14.0
	var r := randf()
	if fam == "spear":
		return "thrust"
	if armoured and _skill > 0.5 and r < 0.45:
		return "thrust" if fam != "blunt" else "heavy"
	if r < 0.12 + _aggr * 0.1:
		return "heavy"
	if r < 0.3:
		return "thrust"
	return "cut"


func _choose_target() -> void:
	if _grudge and _grudge_timer > 0.0 and not _grudge.is_dead():
		target = _grudge
		return
	var best: KickbackActor = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group("fighters"):
		var a := node as KickbackActor
		if a == null or a == self or a.is_dead():
			continue
		if a is Enemy and (a as Enemy).team == team:
			continue
		if not a is Enemy and team == 0:
			continue
		var d := global_position.distance_to(a.global_position)
		# Stickiness: keep the current target unless someone is much closer.
		var score := d - (1.5 if a == target else 0.0)
		if score < best_score:
			best_score = score
			best = a
	target = best


func _on_wounded(_me: KickbackActor, _info: Dictionary) -> void:
	var by := last_attacker
	if by == null or by == target:
		return
	var temper := float(spec.get("ai", {}).get("infighting", 0.3))
	var same_side := by is Enemy and (by as Enemy).team == team
	if not same_side or randf() < temper:
		_grudge = by
		_grudge_timer = randf_range(4.0, 9.0)
		target = by


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("fighters"):
		var other := node as KickbackActor
		if other == null or other == self or other.is_dead():
			continue
		var away := _flat(global_position - other.global_position)
		var d := away.length()
		if d > 0.01 and d < 2.2:
			push += (away / d) * (1.0 - d / 2.2)
	return push


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
