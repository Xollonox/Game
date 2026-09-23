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

const WALK_SPEED := 2.5
const SPRINT_SPEED := 4.6
const TURN_SPEED := 10.0
const FOOTSTEP_DISTANCE := 1.35
const FIGHTER_SCENE := preload("res://assets/models/characters/fighter/fighter.glb")

const LOOPING := ["Idle", "Walk", "Jog", "Sprint", "Sword_Idle", "Crouch_Idle", "Walk_Formal", "Idle_Talking",
	"Sitting_Idle", "Shield_Idle", "Idle_FoldArms", "Zombie_Idle", "Zombie_Walk", "Guard_High", "Guard_Mid",
	"Guard_Low", "Guard_Longsword", "Guard_Spear", "Stance_Idle", "Stance_Idle_2", "Walk_Guard", "Walk_Back",
	"Strafe_L", "Strafe_R", "Idle_Wounded", "Walk_Wounded", "Cheer", "Stance_Sword", "Stance_Blunt",
	"Stance_Dagger", "Stance_Shield", "Guard_Shield", "Guard_Longsword_High", "Guard_Spear_High"]
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
var last_attacker: KickbackActor

var _dead := false
var _controller: ActiveRagdollController
var _rig_builder: PhysicsRigBuilder
var _flinch_timer := 0.0
var _attack_timer := 0.0
var _attack_move: Dictionary = {}
var _guarding := false
var _guard_anim := "Sword_Block"
var _downed := false
var _step_distance := 0.0
var _combo := 0
var _stance_anim := "Sword_Idle"
var _rng := RandomNumberGenerator.new()
var _anim_speed := 1.0


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


func _prepare_animations() -> void:
	if not anim:
		return
	for lib_name in anim.get_animation_library_list():
		var lib := anim.get_animation_library(lib_name)
		for a_name in lib.get_animation_list():
			var a := lib.get_animation(a_name)
			var n := String(a_name)
			var loops := n in LOOPING or n.ends_with("_Walk") or n.ends_with("_Back") or n.ends_with("_StrafeL") \
				or n.ends_with("_StrafeR")
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
	if bleed > 0.0 and not _dead:
		health -= bleed * delta
		bleed = maxf(0.0, bleed - delta * 0.35)
		if health <= 0.0:
			health = 0.0
			_die()
	if _downed:
		return

	var moving := move_dir.length_squared() > 0.01
	var speed := move_speed * (SPRINT_SPEED / WALK_SPEED if sprinting else 1.0) * _gait_scale()
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
	var wid: String = spec.get("weapon", "")
	var wdef := WeaponCatalog.get_def(wid)
	var family: String = wdef.get("attacks", "sword")
	var move: Dictionary = AttackLibrary.pick(family, kind, _combo, context, anim, _rng)
	if move.is_empty():
		return false
	_combo += 1
	_guarding = false
	var handling := float(wdef.get("handling", 1.0)) * float(spec.get("ai", {}).get("cadence", 1.0) if context.get("ai", false) else 1.0)
	var burden := clampf(1.0 - worn_weight * 0.004, 0.8, 1.0)
	var rate := float(move.get("speed", 1.0)) * handling * burden
	_anim_speed = rate
	anim.speed_scale = 1.0
	anim.play(move["anim"], 0.12, rate)
	var dur := anim.get_animation(move["anim"]).length
	_attack_timer = float(move.get("commit", 0.8)) * dur / rate
	_attack_move = move
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


func set_guard(on: bool) -> void:
	if _dead:
		return
	if on and not _guarding:
		var wid: String = spec.get("weapon", "")
		var fam: String = WeaponCatalog.get_def(wid).get("attacks", "sword")
		_guard_anim = AttackLibrary.guard_anim(fam, spec.get("shield", false), anim)
	_guarding = on


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


## The wound model. Returns {profile, damage, struck, kind}.
func receive_weapon_hit(info: Dictionary) -> Dictionary:
	if _dead or not kickback_character or not _rig_builder:
		return {}
	var rig_name: String = info["rig_name"]
	var body: RigidBody3D = _rig_builder.get_bodies().get(rig_name)
	if not body:
		return {}
	var w: PhysicsWeapon = info["weapon"]
	var wdef: Dictionary = w.def if w else {}
	var kind: String = info["kind"]
	var speed: float = clampf(info["speed"], 0.0, 22.0)
	var wmass: float = info.get("mass", 1.2)
	var channel := float(wdef.get(kind, 0.6))
	if info.get("part", "") == "haft":
		channel = 0.35
		kind = "blunt"
	var loc := CombatProfiles.location_weight(rig_name)
	var prot := Armory.protection(spec.get("garments", []), rig_name, kind, _rng)
	# Guarding with a shield soaks blows landing on the shield arm side.
	var raw := 1.6 * speed * sqrt(wmass / 1.2) * channel * loc
	var dmg: float = raw * prot["remaining"]
	# Momentum knock: blunt weapons and heavy blows move even armoured men;
	# worn weight steadies them.
	var stability := 1.0 + worn_weight / 28.0
	var force := speed * wmass * float(wdef.get("stagger", 1.0)) * (1.25 if kind == "blunt" else 1.0) / stability
	if _guarding:
		force *= 0.7
	var profile := CombatProfiles.profile_for_force(force)
	var dir: Vector3 = info["dir"]
	kickback_character.receive_hit(body, dir, body.global_position, profile)
	last_attacker = info.get("attacker")

	var point: Vector3 = info.get("point", body.global_position)
	var hard: bool = prot["hard"] and prot["remaining"] < 0.35
	var sev := clampf(dmg / 38.0, 0.05, 1.0)
	if hard:
		CombatFX.armor_impact(point, dir, clampf(force / 20.0, 0.1, 1.0), String(prot["struck"]))
	if dmg >= 3.0:
		CombatFX.impact(point, dir, sev)
		CombatFX.play_wound(point, kind, sev)
		if kind == "cut" and prot["remaining"] > 0.5:
			bleed += dmg * 0.06
	elif not hard:
		CombatFX.play_hit(point, sev * 0.6)
	if hard or dmg < 3.0:
		CombatFX.shake_requested.emit(clampf(force / 25.0, 0.1, 0.6))
	var result := {"profile": String(profile.profile_name), "damage": dmg, "speed": speed, "part": info.get("part", ""), "struck": prot["struck"],
		"kind": kind, "rig_name": rig_name, "hard": hard}
	wounded.emit(self, result)
	_take_damage(dmg)
	if _dead and last_attacker and last_attacker != self:
		last_attacker.kills += 1
	return result


func _take_damage(dmg: float) -> void:
	health = maxf(0.0, health - dmg)
	if health <= 0.0 and not _dead:
		_die()


## Weapon-on-weapon contact: the blow deflects — the attack loses its drive
## for a beat instead of passing through the parry.
func on_weapon_clash(_other: PhysicsWeapon, intensity: float) -> void:
	if _attack_timer > 0.0 and intensity > 0.35:
		_attack_timer = minf(_attack_timer, 0.25)
		if weapon:
			weapon.control = 0.55
			get_tree().create_timer(0.22).timeout.connect(func(): if is_instance_valid(weapon): weapon.control = 1.0)


## Death reads through the rig: a guaranteed ragdoll into persistent (limp)
## mode, so the body collapses and never stands back up.
func _die() -> void:
	_dead = true
	_downed = true
	_guarding = false
	if anim:
		anim.pause()
	if kickback_character:
		kickback_character.set_persistent(true)
		kickback_character.trigger_ragdoll()
	# The grip goes slack: the weapon falls from a dead hand.
	for w in [weapon, shield]:
		if is_instance_valid(w):
			w.detach()
	died.emit(self)


func get_state_name() -> String:
	return kickback_character.get_active_state_name() if kickback_character else "NONE"


func get_rig_bodies() -> Dictionary:
	return _rig_builder.get_bodies() if _rig_builder else {}


func get_chest_position() -> Vector3:
	var b: RigidBody3D = get_rig_bodies().get("Chest")
	return b.global_position if b else global_position + Vector3.UP * 1.3


func _on_hit_absorbed(rig_name: String, _strength: float) -> void:
	if _attack_timer > 0.0:
		return
	_flinch_timer = 0.35
	if anim:
		anim.speed_scale = 1.0
		var a := "Hit_Head" if "Head" in rig_name else "Hit_Chest"
		if "_L" in rig_name and anim.has_animation("Flinch_L"):
			a = "Flinch_L"
		elif "_R" in rig_name and anim.has_animation("Flinch_R"):
			a = "Flinch_R"
		elif _rng.randf() < 0.5 and anim.has_animation("Flinch_L"):
			a = "Flinch_L" if _rng.randf() < 0.5 else "Flinch_R"
		anim.play(a, 0.08)


func _on_stagger_started(_hit_dir: Vector3) -> void:
	_flinch_timer = 0.7
	_attack_timer = 0.0
	_guarding = false
	if anim:
		anim.speed_scale = 1.0
		var opts := ["Hit_Knockback", "Stagger_Back", "Stagger_Back", "Hit_Chest"]
		var pick: String = opts[_rng.randi() % opts.size()]
		anim.play(pick if anim.has_animation(pick) else "Hit_Chest", 0.1)


func _on_stagger_finished() -> void:
	_flinch_timer = 0.0


func _on_ragdoll_started() -> void:
	_downed = true
	_attack_timer = 0.0
	_guarding = false
	if anim:
		anim.pause()


func _on_recovery_started(face_up: bool) -> void:
	_downed = true
	if anim and not _dead:
		var getup := AttackLibrary.getup_anim(face_up, anim, _rng)
		if getup != "":
			anim.speed_scale = 1.0
			anim.play(getup, 0.15)


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
	return t


static func _find_animation_player(root: Node) -> AnimationPlayer:
	for child in root.get_children():
		if child is AnimationPlayer:
			return child
		var found := _find_animation_player(child)
		if found:
			return found
	return null
