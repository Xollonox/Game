extends Node3D
## Player character: a Quaternius Rigify-rigged mesh with a Kickback
## active-ragdoll rig attached at runtime (see KickbackSetup.add_active_rig).
## Phase 2 of PLAN.md — get this standing/reacting believably before any
## weapon work starts.

@onready var model: Node3D = $Model

var kickback_character: KickbackCharacter


func _ready() -> void:
	var skeleton := KickbackSetup.find_skeleton(model)
	if not skeleton:
		push_error("Player: no Skeleton3D found under Model")
		return

	# ragdoll_profile defaults to a hardcoded Mixamo bone-name profile unless we
	# build one ourselves — our rig uses Blender Rigify DEF- names, so we run
	# the auto-detector explicitly rather than relying on the null fallback.
	var bone_mapping := SkeletonDetector.detect_humanoid_bones(skeleton)
	var profile := SkeletonDetector.create_profile_from_skeleton(skeleton, bone_mapping)

	# Pass an explicit RagdollTuning, not null: ActiveRagdollController's own
	# _ready() fills in a sensible default when tuning is null, but
	# KickbackCharacter._ready() then calls configure(profile, tuning) with
	# whatever we passed here, unconditionally overwriting that default with
	# null again if we don't supply our own.
	var tuning := RagdollTuning.create_default()
	var nodes := KickbackSetup.add_active_rig(self, skeleton, profile, tuning)
	kickback_character = nodes.back() as KickbackCharacter

	var active_controller := kickback_character.get_active_controller()
	if active_controller:
		active_controller.ragdoll_started.connect(_on_ragdoll_started)
		active_controller.recovery_finished.connect(_on_recovery_finished)

	print("Player ready: active ragdoll attached to skeleton with %d bones" % skeleton.get_bone_count())


## Route a hit at a specific rig body (e.g. "Chest", "Hand_R") into the active
## ragdoll. Phase 3's weapon system and Phase 5's enemy attacks both call this;
## for now it's exercised manually from the ragdoll_test.tscn debug HUD.
func apply_hit_to_bone(rig_name: String, hit_dir: Vector3, profile: ImpactProfile) -> void:
	if not kickback_character:
		return
	var rig_builder := get_node_or_null("PhysicsRigBuilder")
	if not rig_builder:
		return
	var bodies: Dictionary = rig_builder.get_bodies()
	var body: RigidBody3D = bodies.get(rig_name)
	if body:
		kickback_character.receive_hit(body, hit_dir, body.global_position, profile)


func _on_ragdoll_started() -> void:
	print("Player ragdolled")


func _on_recovery_finished() -> void:
	print("Player recovered")
