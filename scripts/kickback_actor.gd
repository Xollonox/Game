class_name KickbackActor
extends Node3D
## A humanoid with a Kickback active-ragdoll rig attached at runtime, plus the
## animation wiring that makes its reactions read on screen.
##
## Shared by the player and the training dummies. Subclasses drive `move_dir`
## and call `swing()`; this class owns the rig, the animation state machine and
## the stagger/ragdoll/recovery signal handling.

signal landed_hit(target_name: String, profile_name: String)
signal died(actor: KickbackActor)

const IDLE_ANIM := "Sword_Idle"
const WALK_ANIM := "Walk"
const WALK_SPEED := 1.8
const TURN_SPEED := 10.0
const SWORD_SCENE := preload("res://scenes/sword.tscn")

@onready var model: Node3D = $Model

## Which RagdollTuning preset to build the rig with. Set before the node enters
## the tree. See `_make_tuning()` for the supported names.
@export var tuning_preset := "stand"
## Spawns a physics sword and grip-follows it to this actor's Hand_R bone.
@export var carries_sword := true

## PLAN.md Phase 6: a readout-grade health model. Damage is keyed off the
## impact profile that actually fired, so what drains the bar is the same tier
## the rig visibly reacted with.
@export var max_health := 100.0
const PROFILE_DAMAGE := {&"Light Swing": 8.0, &"Heavy Swing": 20.0, &"Crushing Blow": 40.0}

var health := 100.0

var _dead := false

var kickback_character: KickbackCharacter
var anim: AnimationPlayer
var skeleton: Skeleton3D
var sword: PhysicsSword

## Desired planar movement direction, set by subclasses each physics frame.
var move_dir := Vector3.ZERO

var _controller: ActiveRagdollController
var _rig_builder: PhysicsRigBuilder
var _flinch_timer := 0.0
var _attack_timer := 0.0
var _downed := false


func _ready() -> void:
	health = max_health
	skeleton = KickbackSetup.find_skeleton(model)
	if not skeleton:
		push_error("%s: no Skeleton3D found under Model" % name)
		return
	anim = _find_animation_player(model)
	# Pose the skeleton BEFORE building the rig. PhysicsRigBuilder samples bone
	# global transforms in its _ready(), and a freshly instanced glTF skeleton is
	# still at its identity pose then — the bodies would be built ~0.7 m low (hips
	# at the skeleton origin instead of standing height) and the character would
	# start the game already collapsed. advance(0.0) forces the first frame of the
	# idle clip onto the skeleton synchronously.
	if anim and anim.has_animation(IDLE_ANIM):
		anim.play(IDLE_ANIM)
		anim.advance(0.0)

	# The null-profile fallback is a hardcoded Mixamo-only bone map; our rig uses
	# Blender Rigify DEF- names, so auto-detection has to be invoked explicitly.
	var bone_mapping := SkeletonDetector.detect_humanoid_bones(skeleton)
	var profile := SkeletonDetector.create_profile_from_skeleton(skeleton, bone_mapping)

	# Pass an explicit RagdollTuning, not null: ActiveRagdollController._ready()
	# fills in a sensible default, but KickbackCharacter._ready() then calls
	# configure(profile, tuning) with whatever we pass here, overwriting that
	# default back to null and silently disabling every later hit.
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
		anim.play.call_deferred(IDLE_ANIM)

	# Tag every rig body with the actor that owns it, so anything that gets a
	# RigidBody3D from a physics contact (e.g. the sword) can find its way back
	# to "who did I hit" and "where" (bodies are named after their rig_name).
	# The bodies don't exist yet here: PhysicsRigBuilder builds them in its own
	# _ready(), which — like any child added at runtime — doesn't run until a
	# later frame, so get_bodies() is still empty the instant add_active_rig()
	# returns.
	while _rig_builder.get_bodies().is_empty():
		await get_tree().process_frame
	for body: RigidBody3D in _rig_builder.get_bodies().values():
		body.set_meta(&"kickback_actor", self)

	if carries_sword:
		_spawn_sword()


## Spawns the blade as a sibling, not a child: it's a free RigidBody3D that
## spring-follows the hand, so parenting it under an actor that itself moves
## would double-apply that motion.
func _spawn_sword() -> void:
	sword = SWORD_SCENE.instantiate()
	# Safe to add directly rather than deferred — the wait above already put us
	# past the parent's own _ready() traversal.
	get_parent().add_child(sword)
	sword.attach_to(self)
	sword.landed_hit.connect(
		func(target_name: String, profile_name: String) -> void:
			landed_hit.emit(target_name, profile_name))


func _physics_process(delta: float) -> void:
	_flinch_timer = maxf(0.0, _flinch_timer - delta)
	_attack_timer = maxf(0.0, _attack_timer - delta)

	# While down or getting up, physics owns the body — don't fight it.
	if _downed:
		return

	if move_dir.length_squared() > 0.01:
		var dir := move_dir.normalized()
		global_position += dir * WALK_SPEED * delta
		var target_yaw := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, TURN_SPEED * delta)

	_update_locomotion_anim()


func _update_locomotion_anim() -> void:
	if not anim or _flinch_timer > 0.0 or _attack_timer > 0.0:
		return
	var want := WALK_ANIM if move_dir.length_squared() > 0.01 else IDLE_ANIM
	if anim.current_animation != want:
		anim.play(want, 0.2)


## Plays the sword swing animation. Returns true if the swing started (i.e. the
## actor wasn't already mid-swing or on the ground).
func swing() -> bool:
	if _downed or _attack_timer > 0.0 or not anim:
		return false
	anim.play("Sword_Attack", 0.1)
	_attack_timer = 0.9
	return true


func is_swinging() -> bool:
	return _attack_timer > 0.0


func is_downed() -> bool:
	return _downed


## Routes a hit into the rig at [param rig_name] ("Chest", "Head", "Hand_R"...).
func receive_hit_at(rig_name: String, hit_dir: Vector3, profile: ImpactProfile) -> void:
	if _dead or not kickback_character or not _rig_builder:
		return
	var bodies: Dictionary = _rig_builder.get_bodies()
	var body: RigidBody3D = bodies.get(rig_name)
	if not body:
		return
	kickback_character.receive_hit(body, hit_dir, body.global_position, profile)
	_apply_hit_damage(profile)


func is_dead() -> bool:
	return _dead


## Phase 6 health: subtract the tier that fired; at zero the fighter stays down.
func _apply_hit_damage(profile: ImpactProfile) -> void:
	health = maxf(0.0, health - float(PROFILE_DAMAGE.get(profile.profile_name, 8.0)))
	if health <= 0.0:
		_die()


## Death reads through the rig, not a canned death animation: a guaranteed
## ragdoll dropped into persistent (limp) mode, so the body collapses and never
## stands back up.
func _die() -> void:
	_dead = true
	_downed = true
	if anim:
		anim.pause()
	if kickback_character:
		kickback_character.set_persistent(true)
		kickback_character.trigger_ragdoll()
	died.emit(self)


func get_state_name() -> String:
	return kickback_character.get_active_state_name() if kickback_character else "NONE"


## Returns the rig's RigidBody3D bones, keyed by rig_name ("Chest", "Hand_R"...).
## Used to grip-follow a weapon to a hand bone.
func get_rig_bodies() -> Dictionary:
	return _rig_builder.get_bodies() if _rig_builder else {}


func _on_hit_absorbed(rig_name: String, _strength: float) -> void:
	_flinch_timer = 0.45
	if anim:
		anim.play("Hit_Head" if "Head" in rig_name else "Hit_Chest", 0.1)


func _on_stagger_started(_hit_dir: Vector3) -> void:
	_flinch_timer = 0.6
	if anim:
		anim.play("Hit_Chest", 0.1)


func _on_stagger_finished() -> void:
	_flinch_timer = 0.0


func _on_ragdoll_started() -> void:
	_downed = true
	if anim:
		anim.pause()


func _on_recovery_started(_face_up: bool) -> void:
	_downed = true


func _on_recovery_finished() -> void:
	if _dead:
		# Persistent mode holds the ragdoll; never let a finished recovery
		# stand a corpse back up.
		_downed = true
		return
	_downed = false
	if anim:
		anim.play(IDLE_ANIM, 0.3)


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


## Our tuning.
##
## strip_root_motion MUST stay off for this character. It zeroes the root-motion
## bone's local X and Z, which strips horizontal drift on a Y-up rig — but this
## is a Blender/Rigify glTF rig whose root bone carries the Z-up -> Y-up
## rotation, so the hips' standing height lives in their LOCAL Z (pose.origin is
## (0.047, 0.109, 0.741), and only the root's basis rotates that into world Y).
## Stripping Z therefore deletes the character's height: every spring target
## lands ~0.74 m underground and the rig is dragged into a heap on the floor.
## It looks exactly like "springs too weak", but raising strength only pulls the
## body down harder. Our clips are in-place anyway (Quaternius ships root motion
## as separate *_RM variants), so there is nothing to strip.
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
