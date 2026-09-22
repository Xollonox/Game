class_name PhysicsSword
extends RigidBody3D
## A physics-driven sword (PLAN.md Phase 3/4): a free RigidBody3D, not welded
## to the wielder's hand by a joint. Every physics tick it's velocity-spring-
## pulled toward the grip bone's transform — the exact technique Kickback's
## own SpringResolver uses to drive ragdoll bones toward an animated pose (see
## addons/kickback/spring_resolver.gd). Real mass and inertia mean a fast swing
## doesn't teleport-track the hand: the blade winds up and follows through.
##
## Contact damage comes from the blade's own physics velocity at the moment of
## impact (not a fixed "on hit" number), weighted by hit location. A hit hard
## enough counts as the blade "sticking": the grip spring goes slack for a
## moment, so pulling free takes a beat rather than snapping back instantly.
##
## Hit detection runs inside _integrate_forces, not the contact_monitor signals
## (body_entered/get_colliding_bodies): both are one physics step stale by the
## time a _physics_process callback can read them, and the constant spring
## micro-jitter here makes contact flicker in and out faster than that lag
## tolerates — a real swing was measured landing zero hits through it, despite
## the blade visibly staying in contact at high tip speed the whole time.
## PhysicsDirectBodyState3D's contact list is the live data for the exact step
## being solved, with no such lag.

signal landed_hit(target_name: String, profile_name: String)

const REFERENCE_HZ := 60.0
const LINEAR_STIFFNESS := 55.0
const ANGULAR_STIFFNESS := 40.0
const SPRING_WEIGHT := 0.4
const STUCK_STIFFNESS_SCALE := 0.12
const STUCK_DURATION := 0.35
const HIT_COOLDOWN := 0.4
## Below this tip speed (m/s) a touch doesn't even count as a graze.
const MIN_HIT_SPEED := 1.2
## Tip speed at/above which a hit "sticks" the blade instead of bouncing off.
## Above most ordinary connects (measured 6-9 m/s) so sticking reads as the
## exceptionally hard hits, not the routine ones.
const STICK_SPEED := 14.0

## Local-space offset from the hand bone's transform to where the grip should
## sit. sword_1.fbx ships ~10x oversized with its pivot mid-blade, not at the
## grip — see the PR description for the measured correction (scale 0.1,
## rotate -90° about Y so the blade points local -Z, then push the grip to the
## origin). Baked into the child MeshInstance's own transform in sword.tscn;
## this offset just seats the grip in the hand instead of the palm surface.
@export var grip_offset := Transform3D(Basis(), Vector3(0.02, 0.0, 0.06))
## Approximate blade tip in the RigidBody3D's own local space, used for tip
## (not center-of-mass) velocity — where the edge actually lands.
@export var tip_local := Vector3(0.0, -0.05, -0.66)

var wielder: KickbackActor
var grip_body: RigidBody3D

var _stuck_timer := 0.0
var _hit_cooldown := 0.0


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = false
	top_level = true


## Grip-follows [param actor]'s [param hand_rig_name] bone and excludes
## collision with the actor's own rig (so the blade doesn't snag its wielder).
func attach_to(actor: KickbackActor, hand_rig_name: String = "Hand_R") -> void:
	wielder = actor
	var bodies := actor.get_rig_bodies()
	grip_body = bodies.get(hand_rig_name)
	for body: RigidBody3D in bodies.values():
		add_collision_exception_with(body)
	if grip_body:
		global_transform = grip_body.global_transform * grip_offset


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var delta := state.get_step()
	_stuck_timer = maxf(0.0, _stuck_timer - delta)
	_hit_cooldown = maxf(0.0, _hit_cooldown - delta)

	# Check hits with the velocity that produced this step's contacts, before
	# it gets overwritten below by this tick's spring command.
	_check_hits(state)

	if not grip_body:
		return

	var target := grip_body.global_transform * grip_offset
	var stiffness_scale := STUCK_STIFFNESS_SCALE if _stuck_timer > 0.0 else 1.0
	var current := state.transform

	var pos_error := target.origin - current.origin
	var lin_target := pos_error * LINEAR_STIFFNESS
	state.linear_velocity = state.linear_velocity.lerp(lin_target, _fr_weight(SPRING_WEIGHT * stiffness_scale, delta))

	var error_basis := target.basis.orthonormalized() * current.basis.orthonormalized().inverse()
	var det := error_basis.determinant()
	if det > 0.001 or det < -0.001:
		var q := error_basis.get_rotation_quaternion()
		if q.w < 0.0:
			q = -q
		var angle := 2.0 * acos(clampf(q.w, -1.0, 1.0))
		var axis := Vector3(q.x, q.y, q.z)
		var ang_target := Vector3.ZERO
		if axis.length_squared() > 0.0001 and angle > 0.001:
			ang_target = axis.normalized() * angle * ANGULAR_STIFFNESS
		state.angular_velocity = state.angular_velocity.lerp(ang_target, _fr_weight(SPRING_WEIGHT * stiffness_scale, delta))


static func _fr_weight(weight: float, delta: float) -> float:
	return 1.0 - pow(1.0 - clampf(weight, 0.0, 1.0), delta * REFERENCE_HZ)


## Linear velocity at the blade tip (center-of-mass velocity plus the
## contribution from spin) — what actually lands on the target, not the same
## as the handle's velocity when the blade is swinging around the wrist.
## Reflects the result of the last completed physics step; for use outside
## _integrate_forces (HUD/debug). Hit detection uses _tip_velocity_from with
## the step's own pre-update state instead.
func get_tip_velocity() -> Vector3:
	return _tip_velocity_from(linear_velocity, angular_velocity, global_basis)


func _tip_velocity_from(lin: Vector3, ang: Vector3, basis: Basis) -> Vector3:
	var r := basis * tip_local
	return lin + ang.cross(r)


## Reads contacts straight off this step's PhysicsDirectBodyState3D — live for
## the exact step being solved, unlike the contact_monitor signals/polling
## (see the class doc comment for why those measured zero hits on a real swing).
func _check_hits(state: PhysicsDirectBodyState3D) -> void:
	if _hit_cooldown > 0.0:
		return
	var tip_vel := _tip_velocity_from(state.linear_velocity, state.angular_velocity, state.transform.basis)
	var speed := tip_vel.length()
	if speed < MIN_HIT_SPEED:
		return

	for i in range(state.get_contact_count()):
		var body := state.get_contact_collider_object(i)
		if not body is RigidBody3D or not body.has_meta(&"kickback_actor"):
			continue
		var target_actor: KickbackActor = body.get_meta(&"kickback_actor")
		if not target_actor or target_actor == wielder:
			continue

		_hit_cooldown = HIT_COOLDOWN
		var rig_name: String = body.name
		var profile := CombatProfiles.profile_for_impact(speed, rig_name)
		target_actor.receive_hit_at(rig_name, tip_vel / speed, profile)
		landed_hit.emit(target_actor.name, String(profile.profile_name))

		if speed >= STICK_SPEED:
			_stuck_timer = STUCK_DURATION
		return
