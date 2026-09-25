class_name Dismemberment
extends RefCounted
## Anatomical severing.
##
## Six sever zones per side — neck, shoulder (upper arm), forearm, wrist,
## hip (thigh), knee (shin). A zone only gives way to a *qualified* cut:
## a sharp edge (cut channel ≥ 0.9) leading well (quality ≥ 0.65) into flesh
## that is exposed or only cloth-covered (≥ 60 % of the edge got through —
## mail and plate never let it), carrying enough flesh damage for that zone,
## into tissue already badly cut — or one tremendous blow of 1.6× that.
##
## When a zone goes:
##   1. the segment meshes of the limb are hidden on the fighter
##      (tools/blender/segments.py cut every mesh along these lines)
##   2. Kickback stops driving the limb's bodies and its joint is removed —
##      the bodies fly on with their own momentum plus the strike's impulse
##   3. a DetachedLimb shows the same segment meshes on a copied skeleton that
##      follows those bodies (no duplicate: the fighter no longer shows them)
##   4. flesh-and-bone caps close both cut faces
##   5. an arterial BleedingSource starts at the stump, a lesser one on the limb
##   6. the injury model marks the region and everything below it severed;
##      held items in that hand fall; a lost leg drops the man
## Detached limbs stop taking part in fights: their bodies lose the
## fighter tag (no wounds through them) and move to their own layer.

const DETACHED_LAYER := 1 << 5  # layer 6

## region -> [segments removed, rig at the cut, rig it was joined to, flesh threshold]
const ZONES := {
	"neck": [["head"], "Head", "Chest", 24.0],
	"upper_arm_l": [["upperarm_l", "forearm_l", "hand_l"], "UpperArm_L", "Chest", 24.0],
	"upper_arm_r": [["upperarm_r", "forearm_r", "hand_r"], "UpperArm_R", "Chest", 24.0],
	"forearm_l": [["forearm_l", "hand_l"], "LowerArm_L", "UpperArm_L", 17.0],
	"forearm_r": [["forearm_r", "hand_r"], "LowerArm_R", "UpperArm_R", 17.0],
	"hand_l": [["hand_l"], "Hand_L", "LowerArm_L", 11.0],
	"hand_r": [["hand_r"], "Hand_R", "LowerArm_R", 11.0],
	"thigh_l": [["thigh_l", "shin_l", "foot_l"], "UpperLeg_L", "Hips", 34.0],
	"thigh_r": [["thigh_r", "shin_r", "foot_r"], "UpperLeg_R", "Hips", 34.0],
	"shin_l": [["shin_l", "foot_l"], "LowerLeg_L", "UpperLeg_L", 26.0],
	"shin_r": [["shin_r", "foot_r"], "LowerLeg_R", "UpperLeg_R", 26.0],
}
## Injury regions below each zone (all severed with it).
const BELOW := {
	"neck": ["neck", "head"],
	"upper_arm_l": ["upper_arm_l", "forearm_l", "hand_l"], "upper_arm_r": ["upper_arm_r", "forearm_r", "hand_r"],
	"forearm_l": ["forearm_l", "hand_l"], "forearm_r": ["forearm_r", "hand_r"],
	"hand_l": ["hand_l"], "hand_r": ["hand_r"],
	"thigh_l": ["thigh_l", "shin_l", "foot_l"], "thigh_r": ["thigh_r", "shin_r", "foot_r"],
	"shin_l": ["shin_l", "foot_l"], "shin_r": ["shin_r", "foot_r"],
}
## Rig bodies below each cut rig (carried away with it).
const CHAINS := {
	"Head": ["Head"],
	"UpperArm_L": ["UpperArm_L", "LowerArm_L", "Hand_L"], "UpperArm_R": ["UpperArm_R", "LowerArm_R", "Hand_R"],
	"LowerArm_L": ["LowerArm_L", "Hand_L"], "LowerArm_R": ["LowerArm_R", "Hand_R"],
	"Hand_L": ["Hand_L"], "Hand_R": ["Hand_R"],
	"UpperLeg_L": ["UpperLeg_L", "LowerLeg_L", "Foot_L"], "UpperLeg_R": ["UpperLeg_R", "LowerLeg_R", "Foot_R"],
	"LowerLeg_L": ["LowerLeg_L", "Foot_L"], "LowerLeg_R": ["LowerLeg_R", "Foot_R"],
}
const MAX_LIMBS := 10
static var _limbs: Array = []


## Would this blow sever [param region]? [param through] is the share of the
## edge that reached flesh (armour), [param tissue_before] the region's cut
## damage before this blow (0..1+).
static func qualifies(region: String, kind: String, flesh: float, quality: float, wdef: Dictionary,
		through: float, tissue_before: float) -> bool:
	if not ZONES.has(region) or kind != "cut":
		return false
	if float(wdef.get("cut", 0.0)) < 0.9 or quality < 0.65 or through < 0.6:
		return false
	var thr: float = ZONES[region][3]
	return (flesh >= thr and tissue_before >= 0.5) or flesh >= thr * 1.6


## Cuts [param region] off [param actor]. [param point]/[param dir]/[param
## impulse] describe the blow that did it.
static func sever(actor: KickbackActor, region: String, point: Vector3, dir: Vector3, impulse: float) -> void:
	var z: Array = ZONES[region]
	var segs: Array = z[0]
	var cut_rig: String = z[1]
	var parent_rig: String = z[2]
	var bodies := actor.get_rig_bodies()
	var cut_body: RigidBody3D = bodies.get(cut_rig)
	var parent_body: RigidBody3D = bodies.get(parent_rig)
	if not cut_body or not parent_body:
		return
	var chain: Array = CHAINS[cut_rig]
	var controller := actor.kickback_character.get_active_controller() if actor.kickback_character else null
	var spring: SpringResolver = controller._spring if controller else null
	var builder: PhysicsRigBuilder = actor._rig_builder

	# 1. Joint location (the cut face) and the limb's outward axis.
	var joint_info: Dictionary = builder.get_joints().get(cut_rig, {})
	var joint_pos: Vector3 = parent_body.global_transform * (joint_info.get("anchor_parent", Vector3.ZERO) as Vector3) \
		if joint_info.has("anchor_parent") else cut_body.global_position
	var axis := (cut_body.global_position - joint_pos).normalized()
	if axis.length_squared() < 0.01:
		axis = dir.normalized()

	# 2. Detached visual (before hiding: copy what is shown now).
	var limb := DetachedLimb.create(actor, segs, chain, cut_rig)

	# 3. Hide the segments on the fighter; remember so re-dressing keeps them hidden.
	var sev: Array = actor.model.get_meta(&"severed", [])
	for sname in segs:
		if not sname in sev:
			sev.append(sname)
	actor.model.set_meta(&"severed", sev)
	for node in actor.model.find_children("*", "MeshInstance3D", true, false):
		if String(node.get_meta(&"segment", "core")) in segs:
			(node as MeshInstance3D).visible = false

	# 4. Physics: stop driving the limb, cut its joint, let it fly. The
	# fighter's own skeleton keeps those bones where they were cut.
	var sync: PhysicsRigSync = controller._rig_sync if controller else null
	if sync:
		sync.freeze_rigs(chain)
	if spring:
		for r in chain:
			spring.severed[r] = true
	var j: Generic6DOFJoint3D = joint_info.get("joint")
	if is_instance_valid(j):
		j.queue_free()
	builder.get_joints().erase(cut_rig)
	for r in chain:
		var b: RigidBody3D = bodies.get(r)
		if not b:
			continue
		b.remove_meta(&"kickback_actor")
		b.collision_layer = DETACHED_LAYER
		b.collision_mask = 1 | 2 | 8 | DETACHED_LAYER
		b.gravity_scale = 1.0
		b.linear_damp = 0.1
		b.angular_damp = 0.5
		b.can_sleep = true
		if controller and controller._disabled_collision_masks.has(r):
			controller._disabled_collision_masks.erase(r)
		# It no longer belongs to the man it was cut from.
		for other: RigidBody3D in bodies.values():
			if other != b and not other.name in chain:
				b.add_collision_exception_with(other)
	cut_body.apply_impulse(dir.normalized() * impulse + axis * impulse * 0.3, point - cut_body.global_position)
	if limb:
		limb.bodies = chain.map(func(r): return bodies.get(r))

	# 5. Caps on both faces.
	var r := _radius(cut_body)
	_cap(parent_body, joint_pos, -axis, r)
	_cap(cut_body, joint_pos, axis, r * 0.95)

	# 6. Blood from the stump (and a little from the limb).
	for reg in BELOW[region]:
		actor.injuries.regions[reg]["severed"] = true
	var main_reg: String = BELOW[region][0]
	actor.injuries.regions[main_reg]["bleed"] = float(actor.injuries.regions[main_reg]["bleed"]) \
		+ {"neck": 40.0, "upper_arm_l": 7.0, "upper_arm_r": 7.0, "thigh_l": 9.0, "thigh_r": 9.0}.get(region, 4.5)
	BleedingSource.attach(parent_body, joint_pos + axis * 0.01, axis, actor.injuries, main_reg, dir, 1.0, true)
	BleedingSource.attach(cut_body, joint_pos + axis * 0.03, -axis, actor.injuries, main_reg, dir, 0.4, false)

	# 7. What the body can no longer do.
	if "hand_r" in BELOW[region]:
		actor.drop_weapon(dir * 2.0)
	if "hand_l" in BELOW[region]:
		actor.drop_shield()
	_limbs.append(limb)
	_budget()


static func _radius(b: RigidBody3D) -> float:
	for c in b.get_children():
		if c is CollisionShape3D:
			var s = (c as CollisionShape3D).shape
			if s is CapsuleShape3D:
				return (s as CapsuleShape3D).radius
			if s is SphereShape3D:
				return (s as SphereShape3D).radius * 0.55
			if s is BoxShape3D:
				return minf((s as BoxShape3D).size.x, (s as BoxShape3D).size.z) * 0.5
	return 0.05


## A cut face: flesh round a pale bone, on [param body] at [param pos] facing
## [param normal]. Neutral (no gore) when blood is off.
static func _cap(body: RigidBody3D, pos: Vector3, normal: Vector3, radius: float) -> void:
	var root := Node3D.new()
	body.add_child(root)
	var n := normal.normalized()
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	# Cylinder's axis is Y: point Y along the normal.
	var basis := Basis.looking_at(n, up) * Basis(Vector3.RIGHT, -PI * 0.5)
	root.global_transform = Transform3D(basis, pos)
	root.reset_physics_interpolation()
	var gore := CombatFX.blood_enabled
	for part in [[radius, Color(0.45, 0.05, 0.04) if gore else Color(0.22, 0.2, 0.18), 0.012],
			[radius * 0.28, Color(0.9, 0.86, 0.76) if gore else Color(0.3, 0.28, 0.25), 0.016]]:
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = part[0]
		cyl.bottom_radius = part[0]
		cyl.height = part[2]
		cyl.radial_segments = 14
		cyl.rings = 1
		mi.mesh = cyl
		var m := StandardMaterial3D.new()
		m.albedo_color = part[1]
		m.roughness = 0.45 if gore else 0.9
		mi.material_override = m
		root.add_child(mi)


static func _budget() -> void:
	_limbs = _limbs.filter(func(l): return is_instance_valid(l))
	while _limbs.size() > MAX_LIMBS:
		var old = _limbs.pop_front()
		if is_instance_valid(old):
			old.retire()
