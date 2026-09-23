class_name PhysicsWeapon
extends RigidBody3D
## Any hand-held weapon or shield, as a real physics body (evolved from the
## original PhysicsSword).
##
## The weapon is a free RigidBody3D, velocity-spring-pulled toward its
## wielder's hand rig body every step — the same technique Kickback's
## SpringResolver uses to drive ragdoll bones — so it has real momentum: it
## lags a fast swing, follows through, and a heavy mace is visibly harder to
## bring round than a dagger. Spring authority scales with the weapon's mass
## and length for exactly that reason.
##
## Everything physical comes from WeaponCatalog (measured by the Blender
## generator): mass, centre of mass, tip, and one collision box per striking
## part — `edge`, `point`, `head`, `haft`, `guard`, `shield`. A contact reports
## which box touched, so a mace's head crushes, its haft only knocks, an axe's
## edge cuts and a spear's point pierces.
##
## Hit detection runs inside _integrate_forces off the live contact list (see
## the note preserved from PhysicsSword: the contact_monitor signals are a step
## stale and measured zero hits on real swings). Every body contact goes
## through WeaponContactEvaluator: touching is not striking.

signal landed_hit(target_name: String, profile_name: String)

const REFERENCE_HZ := 60.0
const LINEAR_STIFFNESS := 85.0
const ANGULAR_STIFFNESS := 60.0
const SPRING_WEIGHT := 0.55
const STUCK_STIFFNESS_SCALE := 0.12
const STUCK_DURATION := 0.35
const CLASH_SPEED := 3.0
const CLASH_COOLDOWN := 0.25
const STICK_SPEED := 14.0
const SWISH_SPEED := 5.0
const SWISH_COOLDOWN := 0.45
## Reference mass/length the spring constants were tuned against (the old
## arming sword): lighter weapons track the hand more tightly than this.
const REF_MASS := 1.2
const REF_LENGTH := 0.95

var def: Dictionary = {}
var weapon_id := ""
var wielder: KickbackActor
var grip_body: RigidBody3D
var grip_offset := Transform3D.IDENTITY
var tip_local := Vector3(0, 0, -0.9)
var is_shield := false
## Extra authority multiplier the actor can raise briefly (guard snaps) or
## lower (disarmed / stunned).
var control := 1.0

var _shape_parts: Array[String] = []
var _lin_weight := SPRING_WEIGHT
var _ang_weight := SPRING_WEIGHT
var _stuck_timer := 0.0
var _swish_cooldown := 0.0
var _clash_cooldown := 0.0
var _trail: SwordTrail
var _contacts := WeaponContactEvaluator.ContactLog.new()
## The evaluator's last verdict on a body contact (for tests and debugging).
var last_verdict: Dictionary = {}
## Diagnostics: tally of evaluator verdicts ("phase:part:reason" -> count)
## across all weapons while debug_stats is on (gameplay_test turns it on).
static var debug_stats := false
static var verdict_stats: Dictionary = {}
## Body contacts seen with other fighters (diagnostics).
var touches := 0


static func create(id: String) -> PhysicsWeapon:
	var w := PhysicsWeapon.new()
	w.weapon_id = id
	w.def = WeaponCatalog.get_def(id)
	w.name = "Weapon_" + id
	w._build()
	return w


func _build() -> void:
	is_shield = def.get("class", "") == "shield"
	mass = float(def.get("mass", 1.2))
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = WeaponCatalog.v3(def.get("com", [0, 0, -0.2]))
	tip_local = WeaponCatalog.v3(def.get("tip", [0, 0, -0.9]))
	collision_layer = 2
	collision_mask = 1 | 2 | 8
	var mat := PhysicsMaterial.new()
	mat.friction = 0.6
	mat.bounce = 0.05
	physics_material_override = mat
	for b in def.get("boxes", []):
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = WeaponCatalog.v3(b["size"]).abs().max(Vector3(0.012, 0.012, 0.012))
		cs.shape = box
		cs.position = WeaponCatalog.v3(b["center"])
		add_child(cs)
		_shape_parts.append(String(b.get("part", "edge")))
	var scene := WeaponCatalog.mesh_scene(weapon_id)
	if scene:
		var mesh := scene.instantiate()
		add_child(mesh)
		WeaponLook.dress(mesh)
	var length := float(def.get("length", REF_LENGTH))
	var m_ratio := sqrt(REF_MASS / maxf(mass, 0.2))
	var l_ratio := sqrt(REF_LENGTH / maxf(length, 0.3))
	_lin_weight = SPRING_WEIGHT * clampf(m_ratio, 0.55, 1.15)
	_ang_weight = SPRING_WEIGHT * clampf(m_ratio * l_ratio, 0.4, 1.15)


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 6
	can_sleep = false
	top_level = true
	if not is_shield:
		_trail = SwordTrail.new()
		_trail.source = self
		_trail.tip_local = tip_local
		_trail.base_local = tip_local * 0.45
		add_child(_trail)


## Grip-follows the actor's hand on [param side] ("R"/"L"). The grip frame is
## anatomical (see KickbackActor.grip_frame): fist centre, blade out of the
## thumb side, edge in line with the knuckles.
func attach_to(actor: KickbackActor, side: String = "R") -> void:
	wielder = actor
	var bodies := actor.get_rig_bodies()
	grip_body = bodies.get("Hand_" + side)
	for body: RigidBody3D in bodies.values():
		add_collision_exception_with(body)
	grip_offset = actor.grip_offset(side, is_shield)
	if grip_body:
		global_transform = grip_body.global_transform * grip_offset


## Paints the bearer's arms onto the shield board (W_Paint surfaces).
func apply_heraldry(tex: Texture2D) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.8
	var nor := "res://assets/textures/world/wood_nor.jpg"
	if ResourceLoader.exists(nor):
		m.normal_enabled = true
		m.normal_texture = load(nor)
		m.normal_scale = 0.5
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src and src.resource_name.begins_with("W_Paint"):
				mi.set_surface_override_material(i, m)


func ignore_weapon(other: PhysicsWeapon) -> void:
	add_collision_exception_with(other)


func detach() -> void:
	grip_body = null
	wielder = null
	if _trail:
		_trail.queue_free()
		_trail = null


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var delta := state.get_step()
	_stuck_timer = maxf(0.0, _stuck_timer - delta)
	_swish_cooldown = maxf(0.0, _swish_cooldown - delta)
	_clash_cooldown = maxf(0.0, _clash_cooldown - delta)

	_check_hits(state)

	if _swish_cooldown <= 0.0 and not is_shield:
		var tip_speed := _point_velocity(state, state.transform * tip_local).length()
		if tip_speed >= SWISH_SPEED:
			_swish_cooldown = SWISH_COOLDOWN
			CombatFX.play_swish(state.transform.origin, (tip_speed - SWISH_SPEED) / 15.0 * (REF_MASS / mass))

	if not grip_body:
		return

	var target := grip_body.global_transform * grip_offset
	var k := control * (STUCK_STIFFNESS_SCALE if _stuck_timer > 0.0 else 1.0)
	var current := state.transform
	var pos_error := target.origin - current.origin
	state.linear_velocity = state.linear_velocity.lerp(pos_error * LINEAR_STIFFNESS, _fr_weight(_lin_weight * k, delta))

	var error_basis := target.basis.orthonormalized() * current.basis.orthonormalized().inverse()
	var q := error_basis.get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	var angle := 2.0 * acos(clampf(q.w, -1.0, 1.0))
	var axis := Vector3(q.x, q.y, q.z)
	var ang_target := Vector3.ZERO
	if axis.length_squared() > 0.0001 and angle > 0.001:
		ang_target = axis.normalized() * angle * ANGULAR_STIFFNESS
	state.angular_velocity = state.angular_velocity.lerp(ang_target, _fr_weight(_ang_weight * k, delta))


static func _fr_weight(weight: float, delta: float) -> float:
	return 1.0 - pow(1.0 - clampf(weight, 0.0, 1.0), delta * REFERENCE_HZ)


func _point_velocity(state: PhysicsDirectBodyState3D, world_point: Vector3) -> Vector3:
	var com_world := state.transform * center_of_mass
	return state.linear_velocity + state.angular_velocity.cross(world_point - com_world)


func get_tip_velocity() -> Vector3:
	var com_world := global_transform * center_of_mass
	return linear_velocity + angular_velocity.cross(global_transform * tip_local - com_world)


func get_tip_position() -> Vector3:
	return global_transform * tip_local


## Blade axis in world space (pommel -> tip).
func blade_axis() -> Vector3:
	return (global_basis * tip_local).normalized()


func _check_hits(state: PhysicsDirectBodyState3D) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	# Per step: whether each man touched is a fresh impact, and whether he
	# has already been struck (several contact points count once).
	var fresh := {}
	var struck := {}
	for i in range(state.get_contact_count()):
		var body := state.get_contact_collider_object(i)
		var shape_idx := state.get_contact_local_shape(i)
		var part: String = _shape_parts[shape_idx] if shape_idx >= 0 and shape_idx < _shape_parts.size() else "edge"
		var point := state.get_contact_collider_position(i)
		var vel := _point_velocity(state, point)
		if body is PhysicsWeapon:
			_check_clash(point, body, vel, part)
			continue
		if not body is RigidBody3D or not body.has_meta(&"kickback_actor"):
			continue
		var target_actor: KickbackActor = body.get_meta(&"kickback_actor")
		if not target_actor or target_actor == wielder or target_actor.is_dead():
			continue
		var tid := target_actor.get_instance_id()
		touches += 1
		# Contact lifetime: only the first step of a contact is an impact.
		if not fresh.has(tid):
			fresh[tid] = _contacts.touch(tid, now)
		if not fresh[tid] or struck.has(tid):
			continue
		var serial := wielder.attack_serial if wielder else 0
		if _contacts.already_hit_this_swing(tid, serial):
			continue
		var v_rel := vel - WeaponContactEvaluator.point_velocity(body, point)
		var phase := "none"
		if wielder and wielder.weapons_live:
			phase = wielder.attack_phase()
		var verdict := WeaponContactEvaluator.evaluate(def, part, state.transform.basis, v_rel,
			state.get_contact_local_normal(i), mass, phase)
		last_verdict = verdict
		if debug_stats:
			var u := -1.0
			if wielder and wielder.anim and wielder.anim.current_animation_length > 0.0 and wielder.is_swinging():
				u = snappedf(wielder.anim.current_animation_position / wielder.anim.current_animation_length, 0.05)
			var key := "%s:%s:%s:u%.2f:v%d" % [phase, part, verdict["reason"], u, int(verdict["rel_speed"])]
			verdict_stats[key] = int(verdict_stats.get(key, 0)) + 1
		if not verdict["valid"]:
			continue
		struck[tid] = true
		_contacts.mark_swing(tid, serial)
		var info := {
			"rig_name": String(body.name), "dir": v_rel.normalized(), "speed": float(verdict["speed"]),
			"kind": verdict["kind"], "quality": float(verdict["quality"]), "energy": float(verdict["energy"]),
			"part": part, "weapon": self, "attacker": wielder, "point": point, "mass": mass,
		}
		var result: Dictionary = target_actor.receive_weapon_hit(info)
		landed_hit.emit(target_actor.name, String(result.get("profile", "")))
		if float(verdict["speed"]) >= STICK_SPEED and verdict["kind"] != "blunt":
			_stuck_timer = STUCK_DURATION


## Blade-on-blade / blade-on-shield contact. Only the lower instance id rings
## it (both weapons see the same contact on the same step).
func _check_clash(point: Vector3, other: PhysicsWeapon, vel: Vector3, part: String) -> void:
	if _clash_cooldown > 0.0 or get_instance_id() > other.get_instance_id():
		return
	var rel := (vel - other.get_tip_velocity()).length()
	if rel < CLASH_SPEED:
		return
	_clash_cooldown = CLASH_COOLDOWN
	other._clash_cooldown = CLASH_COOLDOWN
	var intensity := clampf(rel / 15.0, 0.0, 1.0)
	var wooden := other.is_shield or is_shield or part == "haft"
	CombatFX.play_clash(point, intensity, wooden)
	if not wooden:
		CombatFX.sparks(point, vel.normalized(), intensity)
	# A parried blow costs the attacker control for a beat — the blade
	# deflects rather than carrying on through.
	if other.wielder:
		other.wielder.on_weapon_clash(self, intensity)
	if wielder:
		wielder.on_weapon_clash(other, intensity)
