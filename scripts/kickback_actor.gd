class_name KickbackActor
extends Node3D
## A fighter: a humanoid with a Kickback active-ragdoll rig attached at
## runtime, dressed from a fighter spec, carrying real physics weapons.
##
## Shared by the player and every opponent. Subclasses drive `move_dir`,
## `face_dir` and call `attack()` / `set_guard()`; this class owns the rig, the
## animation layer the rig chases, the weapon grips and the wound model.
##
## Nothing about combat is a hitbox animation: attacks are animation targets
## the physics hand chases, the weapon is a free body spring-pulled to that
## hand, and damage/knockback are computed from the weapon's measured contact
## velocity, mass, damage channel and the armour actually struck.

signal landed_hit(target_name: String, profile_name: String)
signal died(actor: KickbackActor)
signal wounded(actor: KickbackActor, info: Dictionary)
signal yielded_signal(actor: KickbackActor)
signal weapon_dropped(actor: KickbackActor, w: PhysicsWeapon)
signal weapon_taken(actor: KickbackActor, w: PhysicsWeapon)

const WALK_SPEED := 2.5
const SPRINT_SPEED := 4.6
const TURN_SPEED := 10.0
const FOOTSTEP_DISTANCE := 1.35
const FIGHTER_SCENE := preload("res://assets/models/characters/fighter/fighter.glb")

const LOOPING := ["Idle", "Walk", "Jog", "Sprint", "Sword_Idle", "Crouch_Idle", "Walk_Formal", "Idle_Talking",
	"Sitting_Idle", "Shield_Idle", "Idle_FoldArms", "Zombie_Idle", "Zombie_Walk", "Guard_High", "Guard_Mid",
	"Guard_Low", "Guard_Longsword", "Guard_Spear", "Stance_Idle", "Stance_Idle_2", "Walk_Guard", "Walk_Back",
	"Strafe_L", "Strafe_R", "Idle_Wounded", "Walk_Wounded", "Cheer", "Stance_Sword", "Stance_Blunt",
	"Stance_Dagger", "Stance_Shield", "Guard_Shield", "Guard_Longsword_High", "Guard_Spear_High", "Guard_Low",
	"Guard_Side_L", "Guard_Side_R", "Guard_Longsword_Low", "Guard_Longsword_Side_L", "Guard_Longsword_Side_R"]
## Speed (m/s) the guarded gait clips were authored for (melee_anims.locomotion).
const GAIT_SPEED := 1.6

## Which RagdollTuning preset to build the rig with.
@export var tuning_preset := "stand"
@export var carries_weapon := true

## PLAN.md Phase 6 health, now fed by the wound model.
@export var max_health := 100.0
var health := 100.0

## The fighter spec (Armory.roll_fighter). Assign before entering the tree.
var spec: Dictionary = {}

var kickback_character: KickbackCharacter
var anim: AnimationPlayer
var skeleton: Skeleton3D
var model: Node3D
var weapon: PhysicsWeapon
var shield: PhysicsWeapon
## Kept for the tests/HUD that still ask for "the sword".
var sword: PhysicsWeapon:
	get:
		return weapon

## Desired planar movement direction (world), set by subclasses.
var move_dir := Vector3.ZERO
## Where the fighter wants to face while fighting (zero = along move_dir).
var face_dir := Vector3.ZERO
var move_speed := WALK_SPEED
var sprinting := false
var worn_weight := 0.0
var bleed := 0.0
var kills := 0
## False while a fighter is still waiting to join (marching in, holding by the
## gate): his weapon collides but wounds no one.
var weapons_live := true
## Out of the fight on his knees, weapon dropped. Still alive — striking him
## now kills him, and a kill is a debt the Hollow collects.
var yielded := false
## Not yet in the fight (waiting at the gate): relaxed stance and gait.
var relaxed := false
var last_attacker: KickbackActor

var _dead := false
var _controller: ActiveRagdollController
var _rig_builder: PhysicsRigBuilder
var _flinch_timer := 0.0
var _attack_timer := 0.0
var _attack_move: Dictionary = {}
## Increments with every attack, so a weapon can score one blow per target
## per swing (see WeaponContactEvaluator.ContactLog).
var attack_serial := 0
var _attack_anim := ""
var balance: ActiveBalance
var grip: WeaponGrip
var striker: BodyStriker
## Set while reaching for a weapon on the ground (see pick_up()).
var _pickup_target: PhysicsWeapon
var _pickup_t := 0.0
var _pickup_best := 9.0
## Regional wounds (see InjurySystem) and their live consequences.
var injuries := InjurySystem.new()
var injury_speed := 1.0
var injury_attack_rate := 1.0
var _injury_tick := 0.0
var _guarding := false
var _guard_anim := "Sword_Block"
var _downed := false
var _step_distance := 0.0
var _combo := 0
var _stance_anim := "Sword_Idle"
var _rng := RandomNumberGenerator.new()
var _anim_speed := 1.0
var _blood: ShaderMaterial
var _wounds: Array = []  # [{body: RigidBody3D, local: Vector3, r: float}]


func _ready() -> void:
	_rng.randomize()
	if spec.is_empty():
		spec = Armory.roll_fighter(1, _rng)
	worn_weight = Armory.worn_weight(spec.get("garments", []))
	# Armour burden: every 10 kg costs ~6 % speed, never more than a third.
	var burden := clampf(1.0 - worn_weight * 0.006, 0.68, 1.0)
	move_speed = WALK_SPEED * burden
	max_health = 100.0 * float(spec.get("vitality", 1.0))
	health = max_health

	model = get_node_or_null("Model")
	if model == null:
		model = FIGHTER_SCENE.instantiate()
		model.name = "Model"
		add_child(model)
	var s := float(spec.get("scale", 1.0))
	model.scale = Vector3.ONE * s
	FighterLook.apply(model, spec)
	if not spec.get("shade", false):
		_blood = ShaderMaterial.new()
		_blood.shader = preload("res://assets/shaders/wound_overlay.gdshader")
		_blood.set_shader_parameter("count", 0)

	skeleton = KickbackSetup.find_skeleton(model)
	if not skeleton:
		push_error("%s: no Skeleton3D found under Model" % name)
		return
	anim = _find_animation_player(model)
	_prepare_animations()
	_stance_anim = spec.get("stance_override", _stance_for_weapon())
	if spec.get("shade", false):
		_stance_anim = "Zombie_Idle"
		move_speed *= 0.8
	# Pose the skeleton BEFORE building the rig: PhysicsRigBuilder samples bone
	# global transforms in its _ready(), and a fresh glTF skeleton is still at its
	# rest (T) pose — the rig would be built arms-out and snap on the first frame.
	if anim and anim.has_animation(_stance_anim):
		anim.play(_stance_anim)
		anim.advance(0.0)

	var bone_mapping := SkeletonDetector.detect_humanoid_bones(skeleton)
	var profile := SkeletonDetector.create_profile_from_skeleton(skeleton, bone_mapping)
	BodyAnatomy.apply(profile)
	# Explicit RagdollTuning, never null: KickbackCharacter._ready() calls
	# configure(profile, tuning) with whatever is passed, and null silently
	# disables every later hit (see PLAN.md, Phase 2 bug note).
	var tuning := _make_tuning()
	var nodes := KickbackSetup.add_active_rig(self, skeleton, profile, tuning)
	kickback_character = nodes.back() as KickbackCharacter
	_rig_builder = nodes[0] as PhysicsRigBuilder
	_controller = kickback_character.get_active_controller()
	if _controller:
		_controller.hit_absorbed.connect(_on_hit_absorbed)
		_controller.stagger_started.connect(_on_stagger_started)
		_controller.stagger_finished.connect(_on_stagger_finished)
		_controller.ragdoll_started.connect(_on_ragdoll_started)
		_controller.recovery_started.connect(_on_recovery_started)
		_controller.recovery_finished.connect(_on_recovery_finished)
	if anim:
		anim.play.call_deferred(_stance_anim)
		# No two fighters breathe in step.
		anim.seek.call_deferred(_rng.randf() * 2.0, true)

	# Bodies are built in PhysicsRigBuilder._ready(), a frame after add.
	while _rig_builder.get_bodies().is_empty():
		await get_tree().process_frame
	for body: RigidBody3D in _rig_builder.get_bodies().values():
		body.set_meta(&"kickback_actor", self)
		# Heavier armour = heavier limbs: harder to knock about.
		body.mass *= 1.0 + worn_weight / 90.0

	if carries_weapon:
		_spawn_weapons()
	balance = ActiveBalance.new()
	balance.name = "Balance"
	add_child(balance)
	balance.setup(self, _controller)
	grip = WeaponGrip.new()
	grip.name = "Grip"
	add_child(grip)
	grip.setup(self)
	striker = BodyStriker.new()
	striker.name = "Striker"
	add_child(striker)
	striker.setup(self)
	_register_held_mass()


func _prepare_animations() -> void:
	if not anim:
		return
	for lib_name in anim.get_animation_library_list():
		var lib := anim.get_animation_library(lib_name)
		for a_name in lib.get_animation_list():
			var a := lib.get_animation(a_name)
			var n := String(a_name)
			# Gait cycles are "<Stance>_Walk/_Back/_StrafeL/_StrafeR" (melee_anims
			# locomotion()); a bare ends_with("_Back") also caught GetUp_Back and
			# Stagger_Back, which then looped (a get-up that restarts mid-rise).
			var gait := n.ends_with("_Walk") or n.ends_with("_Back") or n.ends_with("_StrafeL") or n.ends_with("_StrafeR")
			var loops := n in LOOPING or (gait and not n.begins_with("GetUp") and not n in ["Stagger_Back", "Evade_Back"])
			a.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE


func _stance_for_weapon() -> String:
	var wid: String = spec.get("weapon", "")
	var family: String = WeaponCatalog.get_def(wid).get("attacks", "sword") if wid != "" else "none"
	for cand in AttackLibrary.stance_candidates(family, spec.get("shield", false)):
		if anim and anim.has_animation(cand):
			return cand
	return "Sword_Idle"


func _spawn_weapons() -> void:
	var wid: String = spec.get("weapon", "")
	if wid != "":
		weapon = PhysicsWeapon.create(wid)
		get_parent().add_child(weapon)
		weapon.attach_to(self, "R")
		weapon.landed_hit.connect(func(t: String, p: String) -> void: landed_hit.emit(t, p))
	if spec.get("shield", false):
		shield = PhysicsWeapon.create("heater_shield")
		get_parent().add_child(shield)
		shield.attach_to(self, "L")
		shield.apply_heraldry(Heraldry.texture_for(String(spec.get("name", name))))
		if weapon:
			weapon.ignore_weapon(shield)


## Rig bodies that strike in the current attack (fists, a kicking foot), or
## empty for weapon attacks.
func current_strikers() -> Array:
	return _attack_move.get("strikers", []) if _attack_timer > 0.0 or attack_phase() != "none" else []


## Kickback's arm IK (reach targets for the hands), or null.
func arm_ik() -> ArmIKSolver:
	return _controller._arm_ik if _controller else null


## Lets go of the main weapon (disarm, a fall): it flies on as an ordinary
## rigid body with [param impulse]. The fighter fights on bare-handed until
## he picks something up.
func drop_weapon(impulse := Vector3.ZERO) -> void:
	if not is_instance_valid(weapon):
		return
	var w := weapon
	weapon = null
	w.release(impulse)
	spec["weapon"] = ""
	_attack_timer = 0.0
	_stance_anim = _stance_for_weapon()
	_register_held_mass()
	weapon_dropped.emit(self, w)
	CombatFX.play_clash(w.global_position, 0.25, false)


func drop_shield() -> void:
	if not is_instance_valid(shield):
		return
	var s := shield
	shield = null
	s.release()
	spec["shield"] = false
	_stance_anim = _stance_for_weapon()
	_register_held_mass()


## Nearest free weapon within [param radius] (on the ground, nobody's hand).
func nearest_loose_weapon(radius: float) -> PhysicsWeapon:
	var best: PhysicsWeapon = null
	var bd := radius
	for n in get_tree().get_nodes_in_group(&"world_items"):
		var w := n as PhysicsWeapon
		if not w or w.is_held() or w.is_shield:
			continue
		var d := w.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = w
	return best


## Stoops and takes up [param w]: the pickup clip plays, the right hand
## reaches for the actual grip, and the weapon is drawn into the hand only
## once the hand has closed on it (no teleport, no pop).
func pick_up(w: PhysicsWeapon) -> bool:
	if not is_instance_valid(w) or w.is_held() or is_instance_valid(weapon) or _downed or _dead or _pickup_target:
		return false
	_pickup_target = w
	_pickup_t = 0.0
	_pickup_best = 9.0
	_attack_timer = 1.6
	_attack_move = {"move_scale": 0.7}
	var clip := "PickUp_Low" if anim and anim.has_animation("PickUp_Low") else "Interact"
	if anim and anim.has_animation(clip):
		anim.speed_scale = 1.0
		anim.play(clip, 0.2)
	return true


func _update_pickup(delta: float) -> void:
	if not _pickup_target:
		return
	var w := _pickup_target
	_pickup_t += delta
	var ik := arm_ik()
	if not is_instance_valid(w) or w.is_held() or _downed or _dead or _pickup_t > 2.2:
		if ik:
			ik.end_reach("R")
		_pickup_target = null
		return
	# The hand body's centre rides a few cm above the palm that closes on
	# the grip lying on the ground.
	var grip_pos := w.grip_world() + Vector3.UP * 0.05
	if ik:
		ik.begin_reach("R", grip_pos, clampf(_pickup_t / 0.35, 0.0, 1.0))
	var hand: RigidBody3D = get_rig_bodies().get("Hand_R")
	var hand_d := hand.global_position.distance_to(grip_pos) if hand else 9.0
	_pickup_best = minf(_pickup_best, hand_d)
	# Fingers close around a grip within a palm's span of the hand body.
	var close := hand_d < 0.22
	# Step in so the grip lies under the right hand as he bends: a little in
	# front of and to the right of the feet.
	var flat_to := Vector3(grip_pos.x - global_position.x, 0.0, grip_pos.z - global_position.z)
	if flat_to.length() > 0.05:
		face_dir = flat_to.normalized()
	var stand := grip_pos - face_dir * 0.42 - face_dir.cross(Vector3.UP) * -0.1
	var step := Vector3(stand.x - global_position.x, 0.0, stand.z - global_position.z)
	move_dir = step.normalized() * clampf(step.length() * 3.0, 0.0, 0.8) if step.length() > 0.06 else Vector3.ZERO
	if close or _pickup_t > 1.5:
		if _pickup_best > 0.3:
			# Out of reach after all: give up rather than yank it across.
			if ik:
				ik.end_reach("R")
			_pickup_target = null
			return
		weapon = w
		spec["weapon"] = w.weapon_id
		w.attach_to(self, "R", true)
		if is_instance_valid(shield):
			w.ignore_weapon(shield)
		_stance_anim = _stance_for_weapon()
		_register_held_mass()
		_apply_injury_effects()
		if ik:
			ik.end_reach("R")
		_pickup_target = null
		# Rise with it at the clip's own pace; the stance takes over after.
		_attack_timer = 0.3
		if anim and anim.current_animation.begins_with("PickUp"):
			_attack_timer = maxf(0.3, (anim.current_animation_length - anim.current_animation_position) / maxf(anim.speed_scale, 0.1))
		weapon_taken.emit(self, w)


## Held weapons count toward the balance centre of mass.
func _register_held_mass() -> void:
	if not _controller:
		return
	_controller.extra_mass_bodies.clear()
	if is_instance_valid(weapon) and weapon.wielder == self:
		_controller.extra_mass_bodies["_weapon"] = weapon
	if is_instance_valid(shield) and shield.wielder == self:
		_controller.extra_mass_bodies["_shield"] = shield


## True while the fighter is deliberately walking or attacking: the balance
## layer does not fight intended motion with recovery steps.
func is_intentionally_moving() -> bool:
	# An attack's footwork (passing steps, lunges) is authored: the capture
	# point leaves the feet on purpose and the next step catches it.
	return move_dir.length_squared() > 0.04 or _attack_timer > 0.0 or attack_phase() != "none"


func _exit_tree() -> void:
	for w in [weapon, shield]:
		if is_instance_valid(w):
			w.queue_free()


## Anatomical grip frame, in the hand BONE's local space (which is also the
## hand rig body's local space: bodies are built at the bone global pose).
## Fist centre sits in front of the palm; the blade leaves the thumb side and
## the edge runs in line with the knuckles, so a cut lands edge-first. A
## shield's face turns out along the knuckles, top toward the thumb.
func grip_offset(side: String, for_shield := false) -> Transform3D:
	var sfx := "_r" if side == "R" else "_l"
	var hb := skeleton.find_bone("hand" + sfx)
	var mb := skeleton.find_bone("middle_01" + sfx)
	var ib := skeleton.find_bone("index_01" + sfx)
	var pb := skeleton.find_bone("pinky_01" + sfx)
	if hb < 0 or mb < 0 or ib < 0 or pb < 0:
		return Transform3D.IDENTITY
	var hand := skeleton.get_bone_global_rest(hb)
	var f := (skeleton.get_bone_global_rest(mb).origin - hand.origin).normalized()
	var t0 := skeleton.get_bone_global_rest(ib).origin - skeleton.get_bone_global_rest(pb).origin
	var t := (t0 - f * t0.dot(f)).normalized()
	var palm := (t.cross(f) if side == "R" else f.cross(t)).normalized()
	var center := hand.origin + f * 0.068 + palm * 0.028
	var basis: Basis
	if for_shield:
		var x := -f
		var z := -t
		basis = Basis(x, z.cross(x), z).orthonormalized()
		center += f * 0.02
	else:
		# Blade slightly canted forward from the thumb, like a real hammer grip.
		var blade := (t + f * 0.18).normalized()
		var z := -blade
		var y := (f - blade * f.dot(blade)).normalized()
		basis = Basis(y.cross(z), y, z).orthonormalized()
	var world_rest := Transform3D(basis, center)
	return hand.affine_inverse() * world_rest


func _physics_process(delta: float) -> void:
	_flinch_timer = maxf(0.0, _flinch_timer - delta)
	_attack_timer = maxf(0.0, _attack_timer - delta)
	if not _dead:
		var loss := injuries.tick(delta)
		if loss > 0.0:
			health -= loss
			_injury_tick += delta
			if _injury_tick > 0.25:
				_injury_tick = 0.0
				_apply_injury_effects()
			if health <= 0.0 or injuries.blood < 0.45:
				health = 0.0
				_die()
	if _downed:
		return
	_update_pickup(delta)

	var moving := move_dir.length_squared() > 0.01
	var speed := move_speed * (SPRINT_SPEED / WALK_SPEED if sprinting else 1.0) * _gait_scale() * injury_speed
	if _attack_timer > 0.0:
		speed *= float(_attack_move.get("move_scale", 0.45))
	if _guarding:
		speed *= 0.6
	if _flinch_timer > 0.0:
		speed *= 0.4
	if moving:
		var dir := move_dir.normalized()
		global_position += dir * speed * delta * clampf(move_dir.length(), 0.0, 1.0)
		_step_distance += speed * delta
		if _step_distance >= FOOTSTEP_DISTANCE:
			_step_distance = 0.0
			CombatFX.play_footstep(global_position, worn_weight)
	else:
		_step_distance = FOOTSTEP_DISTANCE * 0.6

	var want_face := face_dir if face_dir.length_squared() > 0.01 else (move_dir if moving else Vector3.ZERO)
	if want_face.length_squared() > 0.01:
		var target_yaw := atan2(want_face.x, want_face.z)
		var turn := TURN_SPEED * (0.35 if _attack_timer > 0.0 else 1.0) / (1.0 + worn_weight / 60.0)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn * delta, 0.0, 1.0))
	_update_locomotion_anim(moving)


## Squared up in a fight, a fighter moves in a guarded gait, not a stroll.
func _gait_scale() -> float:
	return 0.68 if face_dir.length_squared() > 0.01 and not sprinting else 1.0


func _update_locomotion_anim(moving: bool) -> void:
	if not anim or _flinch_timer > 0.0 or _attack_timer > 0.0:
		return
	var want := _stance_anim
	var spd := 1.0
	if relaxed and not _guarding:
		want = "Idle" if not moving else "Walk"
		if moving:
			spd = move_speed / WALK_SPEED
		if anim.current_animation != want:
			anim.play(want, 0.35)
		anim.speed_scale = spd
		return
	if _guarding:
		want = _guard_anim
	elif moving:
		var fwd := global_basis.z
		var md := move_dir.normalized()
		var d := md.dot(fwd)
		var sp := move_dir.length() * move_speed * _gait_scale()
		if sprinting:
			want = "Sprint"
		elif spec.get("shade", false):
			want = "Zombie_Walk"
			spd = move_speed / WALK_SPEED
		elif face_dir.length_squared() > 0.01 and anim.has_animation(_stance_anim + "_Walk"):
			# Squared up to an opponent: fencing gait in the stance's own guard.
			var suffix := "_Walk"
			if d < -0.5:
				suffix = "_Back"
			elif absf(d) <= 0.5:
				suffix = "_StrafeR" if md.dot(global_basis.x) < 0.0 else "_StrafeL"
			want = _stance_anim + suffix
			spd = clampf(sp / GAIT_SPEED, 0.5, 1.6)
		else:
			want = "Walk"
			spd = move_speed / WALK_SPEED
			if d < -0.35:
				spd = -spd * 0.85
	if anim.current_animation != want or not is_equal_approx(anim.speed_scale, spd):
		if anim.current_animation != want:
			anim.play(want, 0.22)
		anim.speed_scale = spd


## Starts an attack of [param kind] ("cut", "thrust", "heavy", "any").
## Returns true if it started. The move is drawn from the weapon's attack
## family; consecutive cuts alternate sides like a real exchange.
func attack(kind: String = "cut", context: Dictionary = {}) -> bool:
	if _downed or _dead or _attack_timer > 0.0 or not anim:
		return false
	# No attacking while stumbling: the body is busy catching itself.
	if _controller and _controller.get_state_name() == "STAGGER":
		return false
	var wid: String = spec.get("weapon", "")
	var wdef := WeaponCatalog.get_def(wid) if wid != "" else {}
	var family: String = wdef.get("attacks", "sword") if wid != "" else "unarmed"
	if kind == "kick":
		family = "unarmed"  # anyone can kick, sword in hand or not
	var move: Dictionary = AttackLibrary.pick(family, kind, _combo, context, anim, _rng)
	if move.is_empty():
		return false
	_combo += 1
	_guarding = false
	var handling := float(wdef.get("handling", 1.0)) * float(spec.get("ai", {}).get("cadence", 1.0) if context.get("ai", false) else 1.0)
	var burden := clampf(1.0 - worn_weight * 0.004, 0.8, 1.0)
	var rate := float(move.get("speed", 1.0)) * handling * burden * injury_attack_rate
	_anim_speed = rate
	anim.speed_scale = 1.0
	anim.play(move["anim"], 0.12, rate)
	var dur := anim.get_animation(move["anim"]).length
	_attack_timer = float(move.get("commit", 0.8)) * dur / rate
	_attack_move = move
	_attack_anim = move["anim"]
	attack_serial += 1
	CombatFX.play_cloth(global_position + Vector3.UP, worn_weight)
	return true


## A quick step back out of range (AI back-off, player evade).
func evade() -> bool:
	if _downed or _dead or _attack_timer > 0.0 or not anim or not anim.has_animation("Evade_Back"):
		return false
	anim.speed_scale = 1.0
	anim.play("Evade_Back", 0.08)
	_attack_timer = 0.45
	_attack_move = {"move_scale": 1.6}
	return true


## Emote after a bout (raised fist, a nod to the stands).
func emote(a: String) -> void:
	if anim and anim.has_animation(a) and not _downed and not _dead:
		anim.speed_scale = 1.0
		anim.play(a, 0.3)
		_attack_timer = anim.get_animation(a).length


## Backwards-compatible name used by tests and older callers.
func swing() -> bool:
	return attack("cut")


## Holding a guard. [param threat] (a hostile weapon) moves the guard to
## where that blade actually is: high, low, or to the flank it is coming from.
func set_guard(on: bool, threat: PhysicsWeapon = null) -> void:
	if _dead:
		return
	if on:
		var wid: String = spec.get("weapon", "")
		var fam: String = WeaponCatalog.get_def(wid).get("attacks", "sword")
		var line := ""
		if threat and is_instance_valid(threat):
			var local := global_transform.affine_inverse() * threat.get_tip_position()
			if local.y < 0.95:
				line = "low"
			elif absf(local.x) > 0.45 and local.y < 1.55:
				# The actor faces +Z: positive local x is his left.
				line = "left" if local.x > 0.0 else "right"
			else:
				line = "high"
		_guard_anim = AttackLibrary.guard_anim(fam, spec.get("shield", false), anim, line)
	_guarding = on


## Where the current attack is: "prep" (wind-up), "accel" (bringing the
## weapon round), "active" (the part meant to land), "follow" (follow-through)
## or "recovery"; "none" when not attacking. Read from the playing clip's
## normalized time against the move's authored key times (AttackLibrary).
func attack_phase() -> String:
	if _attack_anim == "" or not anim or anim.current_animation != _attack_anim or _downed or _dead:
		return "none"
	var length := anim.current_animation_length
	if length <= 0.0:
		return "none"
	var u := anim.current_animation_position / length
	var ph: Array = _attack_move.get("phases", AttackLibrary.DEFAULT_PHASES)
	# ph = [wind-up peak, strike, end of follow-through]; the active window
	# opens halfway through the acceleration.
	if u < float(ph[0]):
		return "prep"
	if u < lerpf(float(ph[0]), float(ph[1]), 0.45):
		return "accel"
	if u < lerpf(float(ph[1]), float(ph[2]), 0.6):
		return "active"
	if u < float(ph[2]):
		return "follow"
	return "recovery"


func is_guarding() -> bool:
	return _guarding


func is_swinging() -> bool:
	return _attack_timer > 0.0


func is_downed() -> bool:
	return _downed


func is_dead() -> bool:
	return _dead


## Legacy route (debug keys, vision test): an explicit profile at a rig slot.
func receive_hit_at(rig_name: String, hit_dir: Vector3, profile: ImpactProfile) -> void:
	if _dead or not kickback_character or not _rig_builder:
		return
	var body: RigidBody3D = _rig_builder.get_bodies().get(rig_name)
	if not body:
		return
	kickback_character.receive_hit(body, hit_dir, body.global_position, profile)
	var dmg: float = {&"Light Swing": 8.0, &"Heavy Swing": 20.0, &"Crushing Blow": 40.0}.get(profile.profile_name, 8.0)
	_take_damage(float(dmg))


## The wound model. Returns {profile, damage, struck, kind, region, ...}.
##
## A qualified blow (WeaponContactEvaluator) arrives with its qualifying
## speed, kind and quality. Armour decides what reaches flesh (cut / pierce
## against the layer struck) and what is transmitted anyway (blunt trauma
## through plate); InjurySystem turns that into a regional injury; the rig
## gets an impulse from the delivered momentum.
func receive_weapon_hit(info: Dictionary) -> Dictionary:
	if _dead or not kickback_character or not _rig_builder:
		return {}
	var rig_name: String = info["rig_name"]
	var body: RigidBody3D = _rig_builder.get_bodies().get(rig_name)
	if not body:
		return {}
	var w: PhysicsWeapon = info["weapon"]
	var wdef: Dictionary = w.def if w else info.get("def", {})
	var kind: String = info["kind"]
	var speed: float = clampf(info["speed"], 0.0, 22.0)
	var wmass: float = info.get("mass", 1.2)
	var quality := float(info.get("quality", 1.0))
	var channel := float(wdef.get(kind, 0.6))
	if info.get("part", "") == "haft":
		channel = 0.35
		kind = "blunt"
	var point: Vector3 = info.get("point", body.global_position)
	var region := InjurySystem.region_for(rig_name, body.to_local(point))
	var garments: Array = spec.get("garments", [])
	var prot := Armory.protection(garments, rig_name, kind, _rng)
	# The blow's wounding potential, independent of where it landed (the
	# region's anatomy decides what it means).
	var raw := 2.6 * speed * sqrt(wmass / 1.2) * channel * quality
	var flesh: float = raw * prot["remaining"]
	# Blunt trauma transmitted whatever the edge did: plate turns a cut but
	# the man inside still takes the blow.
	var blunt_prot := Armory.protection(garments, rig_name, "blunt", _rng)
	var trauma: float = 2.6 * speed * sqrt(wmass / 1.2) * maxf(float(wdef.get("blunt", 0.25)), 0.25) * quality \
		* float(blunt_prot["remaining"])
	if kind == "blunt":
		trauma = maxf(trauma, flesh)
	var inj := injuries.apply(region, kind, flesh if kind != "blunt" else flesh * 0.4, trauma)

	# Momentum knock: blunt weapons and heavy blows move even armoured men;
	# worn weight steadies them.
	var stability := 1.0 + worn_weight / 28.0
	var force := speed * wmass * float(wdef.get("stagger", 1.0)) * (1.25 if kind == "blunt" else 1.0) / stability
	if _guarding:
		force *= 0.7
	var margin := balance.margin if balance else 0.1
	var profile := CombatProfiles.profile_for_blow(force, margin)
	var dir: Vector3 = info["dir"]
	if _controller:
		# The stumble drift follows the delivered momentum.
		_controller.next_stumble_drift = clampf(force * 0.16, 0.3, 3.2)
	kickback_character.receive_hit(body, dir, point, profile)
	last_attacker = info.get("attacker")

	var hard: bool = prot["hard"] and prot["remaining"] < 0.35
	var sev := clampf(flesh / 30.0, 0.05, 1.0)
	if hard:
		CombatFX.armor_impact(point, dir, clampf(force / 20.0, 0.1, 1.0), String(prot["struck"]))
	if flesh >= 3.0 and kind != "blunt":
		CombatFX.impact(point, dir, sev)
		CombatFX.play_wound(point, kind, sev)
		_add_wound(body, point, clampf(0.04 + flesh / 220.0, 0.04, 0.16))
	elif not hard:
		CombatFX.play_hit(point, clampf(trauma / 30.0, 0.1, 0.8))
	if hard or flesh < 3.0:
		CombatFX.shake_requested.emit(clampf(force / 25.0, 0.1, 0.6))
	var systemic: float = inj["systemic"]
	var result := {"profile": String(profile.profile_name), "damage": systemic, "flesh": flesh, "trauma": trauma,
		"speed": speed, "part": info.get("part", ""), "struck": prot["struck"], "kind": kind, "rig_name": rig_name,
		"hard": hard, "region": region, "fractured": inj["fractured_now"], "lethal": inj["lethal"]}
	wounded.emit(self, result)
	if region in ["hand_r", "forearm_r", "upper_arm_r"] and grip:
		# A blow on the weapon arm jars the grip.
		grip.shock((trauma + flesh * 0.5) / 7.0, dir)
	_apply_injury_effects()
	if inj["lethal"]:
		_take_damage(health + 1.0)
	else:
		_take_damage(systemic)
	if _dead and last_attacker and last_attacker != self:
		last_attacker.kills += 1
	return result


## Pushes the injury state into the body: spring strength per region, weapon
## control, gait, balance tolerance, concussion. Called after every wound and
## a few times a second while bleeding.
func _apply_injury_effects() -> void:
	if _controller and _controller._spring:
		_controller._spring.impairment = injuries.rig_impairment()
	var arm_r := injuries.arm_function("r")
	var arm_l := injuries.arm_function("l")
	if is_instance_valid(weapon) and weapon.wielder == self:
		weapon.control = lerpf(0.3, 1.0, arm_r)
	if is_instance_valid(shield) and shield.wielder == self:
		shield.control = lerpf(0.3, 1.0, arm_l)
	var legs := minf(injuries.leg_function("l"), injuries.leg_function("r"))
	if balance:
		balance.leg_function = legs
	injury_speed = lerpf(0.35, 1.0, (injuries.leg_function("l") + injuries.leg_function("r")) * 0.5) \
		* lerpf(0.75, 1.0, injuries.core_function())
	injury_attack_rate = lerpf(0.6, 1.0, arm_r) * lerpf(0.8, 1.0, injuries.core_function())
	bleed = injuries.total_bleed()
	if injuries.stun > 0.6 and _controller and _controller.get_state_name() == "NORMAL":
		# Concussion: the springs go slack for a moment.
		_controller.request_balance_step(-global_basis.z, 0.6)
	if arm_r < 0.2 and is_instance_valid(weapon):
		drop_weapon()  # the hand can no longer close
	if arm_l < 0.15 and is_instance_valid(shield):
		drop_shield()
	if legs < 0.12 and not _downed and kickback_character:
		# The leg gives way.
		kickback_character.trigger_ragdoll()


## Keeps a stain on the body where it was struck (see wound_overlay.gdshader).
func _add_wound(body: RigidBody3D, point: Vector3, radius: float) -> void:
	if _blood == null or not GameState.blood:
		return
	if _wounds.is_empty():
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.visible and not mi.name.begins_with("Hair") and mi.name != "Eyes" and mi.name != "Eyebrows":
				mi.material_overlay = _blood
	# A second blow near an old wound widens it rather than adding a new one.
	for w in _wounds:
		if w["body"] == body and (w["local"] as Vector3).distance_to(body.to_local(point)) < 0.08:
			w["r"] = minf(float(w["r"]) + radius * 0.4, 0.2)
			return
	_wounds.append({"body": body, "local": body.to_local(point), "r": radius})
	if _wounds.size() > 6:
		_wounds.pop_front()


func _process(_delta: float) -> void:
	if _wounds.is_empty() or _blood == null:
		return
	var arr: Array[Vector4] = []
	for w in _wounds:
		var b: RigidBody3D = w["body"]
		if not is_instance_valid(b):
			continue
		var p: Vector3 = b.to_global(w["local"])
		arr.append(Vector4(p.x, p.y, p.z, float(w["r"])))
	while arr.size() < 6:
		arr.append(Vector4.ZERO)
	_blood.set_shader_parameter("wounds", arr)
	_blood.set_shader_parameter("count", mini(_wounds.size(), 6))


func _take_damage(dmg: float) -> void:
	health = maxf(0.0, health - dmg)
	if health <= 0.0 and not _dead:
		_die()
	elif not yielded and not _dead and health < max_health * 0.22 and _wants_to_yield():
		yield_fight()


## Enemies decide for themselves (see Enemy); the player yields by choice.
func _wants_to_yield() -> bool:
	return false


func is_out() -> bool:
	return _dead or yielded


## Kneels, drops the weapon, and asks for mercy.
func yield_fight() -> void:
	if yielded or _dead:
		return
	yielded = true
	_guarding = false
	_attack_timer = 0.0
	weapons_live = false
	bleed *= 0.3
	# He throws down his weapon: it lies in the sand like any other.
	drop_weapon()
	drop_shield()
	if anim:
		anim.speed_scale = 1.0
		var kneel := "Crouch_Idle" if anim.has_animation("Crouch_Idle") else "Sitting_Idle"
		if anim.has_animation(kneel):
			anim.get_animation(kneel).loop_mode = Animation.LOOP_LINEAR
			anim.play(kneel, 0.4)
	_flinch_timer = 1e9
	yielded_signal.emit(self)


## Weapon-on-weapon contact. The blow is not cancelled by script: the
## physical collision already changed the blade's path, and the hand spring
## is softened for a moment so the deflection carries through instead of
## snapping back to the animation. A hard enough clash can tear the weapon
## out of a weak hand.
func on_weapon_clash(other: PhysicsWeapon, intensity: float) -> void:
	if is_instance_valid(weapon) and weapon.is_held():
		weapon.soften(lerpf(0.75, 0.3, intensity), 0.18 + intensity * 0.25)
		var shock := intensity * 2.4 * sqrt(other.mass / 1.2) if is_instance_valid(other) else intensity * 2.4
		var away := (weapon.global_position - other.global_position).normalized() if is_instance_valid(other) else Vector3.UP
		if grip and grip.shock(shock, away):
			return
	if _attack_timer > 0.0 and intensity > 0.45:
		# A hard parry ends the committed part of the attack sooner.
		_attack_timer = minf(_attack_timer, 0.3)


## Death reads through the rig: a guaranteed ragdoll into persistent (limp)
## mode, so the body collapses and never stands back up.
func _die() -> void:
	_dead = true
	_downed = true
	_guarding = false
	if anim:
		anim.pause()
	if kickback_character:
		# Persistent ragdoll IS the collapse. (A trigger_ragdoll() after it
		# would replace PERSISTENT with an ordinary RAGDOLL — and the dead
		# man would get back up.)
		kickback_character.set_persistent(true)
	# The grip goes slack: the weapon falls from a dead hand.
	drop_weapon()
	drop_shield()
	died.emit(self)


func get_state_name() -> String:
	return kickback_character.get_active_state_name() if kickback_character else "NONE"


func get_rig_bodies() -> Dictionary:
	return _rig_builder.get_bodies() if _rig_builder else {}


func get_chest_position() -> Vector3:
	var b: RigidBody3D = get_rig_bodies().get("Chest")
	return b.global_position if b else global_position + Vector3.UP * 1.3


## A blow the springs absorbed: the reaction is the rig itself (the struck
## region lost strength and was shoved), so no clip is played over it. The
## fighter only loses a beat of initiative.
func _on_hit_absorbed(_rig_name: String, _strength: float) -> void:
	if _attack_timer > 0.0:
		return
	_flinch_timer = 0.25


## Off balance: Kickback steps the feet toward the capture point and relaxes
## the upper body; the stance keeps playing underneath so the body fights to
## return to it rather than acting out a canned stagger.
func _on_stagger_started(_hit_dir: Vector3) -> void:
	_flinch_timer = 0.6
	_attack_timer = 0.0
	_guarding = false


func _on_stagger_finished() -> void:
	_flinch_timer = 0.0


func _on_ragdoll_started() -> void:
	_downed = true
	# A man knocked off his feet lets go of what is in his hands.
	if is_instance_valid(weapon):
		drop_weapon(weapon.linear_velocity * weapon.mass * 0.2)
	if is_instance_valid(shield):
		drop_shield()
	# Dust when the body meets the ground, a beat after the fall starts.
	get_tree().create_timer(0.45).timeout.connect(func():
		if is_instance_valid(self):
			CombatFX.dust(get_chest_position(), clampf(worn_weight / 30.0 + 0.4, 0.4, 1.0))
			CombatFX.play_footstep(get_chest_position(), worn_weight))
	_attack_timer = 0.0
	_guarding = false
	if anim:
		anim.pause()


func _on_recovery_started(face_up: bool) -> void:
	_downed = true
	if anim and not _dead:
		var getup := AttackLibrary.getup_anim(face_up, anim, _rng)
		if getup != "":
			# The clip is the springs' target while their strength ramps up: it
			# must last as long as the ramp, or the body is yanked into its last
			# frame once the springs are strong (the "get-up snap").
			var ramp := kickback_character.get_active_controller()._tuning.recovery_duration \
				if kickback_character and kickback_character.get_active_controller() else 2.5
			anim.speed_scale = clampf(anim.get_animation(getup).length / ramp, 0.4, 1.0)
			anim.play(getup, 0.15)
			# The clip holds its last frame until the controller reports the
			# recovery finished; the stance then cross-fades in (a queued clip
			# would cut to it with no blend).


func _on_recovery_finished() -> void:
	if _dead:
		_downed = true
		return
	_downed = false
	if anim:
		anim.speed_scale = 1.0
		anim.play(_stance_anim, 0.3)


func _make_tuning() -> RagdollTuning:
	match tuning_preset:
		"default":
			return RagdollTuning.create_default()
		"game":
			return RagdollTuning.create_game_default()
		"tank":
			return RagdollTuning.create_tank()
		"heavy":
			return RagdollTuning.create_heavy()
		_:
			return _stand_tuning()


## strip_root_motion MUST stay off for this character: the glTF root bone
## carries the Z-up -> Y-up rotation, so the hips' standing height lives in the
## root's LOCAL Z. Stripping it deletes the character's height and drags every
## spring target underground (it looks exactly like "springs too weak"). Our
## clips are in-place anyway.
static func _stand_tuning() -> RagdollTuning:
	var t := RagdollTuning.create_game_default()
	t.strip_root_motion = false
	BodyAnatomy.tune_balance(t)
	return t


static func _find_animation_player(root: Node) -> AnimationPlayer:
	for child in root.get_children():
		if child is AnimationPlayer:
			return child
		var found := _find_animation_player(child)
		if found:
			return found
	return null
