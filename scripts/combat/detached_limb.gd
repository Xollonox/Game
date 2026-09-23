class_name DetachedLimb
extends Node3D
## The visible part of a severed limb.
##
## A fresh Skeleton3D with the fighter's bone hierarchy carries *only* the
## severed segment meshes (same Mesh and Skin resources, same materials), so
## nothing is duplicated on screen: the fighter no longer shows them. Each
## physics step every bone is posed in world space — bones of the freed rig
## bodies follow their body, every other bone stays rigidly where it was
## relative to the limb's root body (so the skin near the cut, weighted
## partly to the parent bone, keeps its shape).

var bodies: Array = []  # freed rig bodies (root first)
var _skel: Skeleton3D
var _root_body: RigidBody3D
var _bone_body: Dictionary = {}  # bone idx -> [body, offset]
var _rel: Dictionary = {}  # bone idx -> transform relative to the root body
var _order: PackedInt32Array = PackedInt32Array()
var _rest_timer := 0.0
var _frozen := false


static func create(actor: KickbackActor, segs: Array, chain: Array, cut_rig: String) -> DetachedLimb:
	var src := actor.skeleton
	var bodies := actor.get_rig_bodies()
	var root_body: RigidBody3D = bodies.get(cut_rig)
	if not src or not root_body:
		return null
	var limb := DetachedLimb.new()
	limb.name = "Limb_" + cut_rig
	limb.top_level = true
	actor.get_parent().add_child(limb)
	limb.global_transform = Transform3D.IDENTITY
	var sk := Skeleton3D.new()
	sk.name = "Skeleton"
	limb.add_child(sk)
	for i in src.get_bone_count():
		sk.add_bone(src.get_bone_name(i))
	for i in src.get_bone_count():
		sk.set_bone_parent(i, src.get_bone_parent(i))
		sk.set_bone_rest(i, src.get_bone_rest(i))
	limb._skel = sk
	limb._root_body = root_body
	# World-space pose of every bone right now.
	var world := {}
	for i in src.get_bone_count():
		world[i] = src.global_transform * src.get_bone_global_pose(i)
	var inv_root := root_body.global_transform.affine_inverse()
	for i in src.get_bone_count():
		limb._rel[i] = inv_root * world[i]
	var builder: PhysicsRigBuilder = actor._rig_builder
	for r in chain:
		var b: RigidBody3D = bodies.get(r)
		var bname := builder.get_bone_name_for_body(r)
		var bi := src.find_bone(bname)
		if b and bi >= 0:
			limb._bone_body[bi] = [b, b.global_transform.affine_inverse() * world[bi]]
	# Parent-first order.
	var order: Array[int] = []
	var seen := {}
	for i in src.get_bone_count():
		_push(src, i, order, seen)
	limb._order = PackedInt32Array(order)
	# The severed pieces, re-skinned onto the new skeleton.
	for node in actor.model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.visible or not String(mi.get_meta(&"segment", "core")) in segs:
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		copy.skin = mi.skin
		for s in mi.get_surface_override_material_count():
			copy.set_surface_override_material(s, mi.get_surface_override_material(s))
		copy.material_overlay = mi.material_overlay
		sk.add_child(copy)
		copy.skeleton = copy.get_path_to(sk)
	limb._pose()
	return limb


static func _push(sk: Skeleton3D, i: int, order: Array[int], seen: Dictionary) -> void:
	if seen.has(i):
		return
	var p := sk.get_bone_parent(i)
	if p >= 0:
		_push(sk, p, order, seen)
	seen[i] = true
	order.append(i)


func _physics_process(delta: float) -> void:
	if _frozen or not is_instance_valid(_root_body):
		return
	_pose()
	# Sleep the physics once it has come to rest (performance budget).
	if _root_body.linear_velocity.length() < 0.05 and _root_body.angular_velocity.length() < 0.1:
		_rest_timer += delta
		if _rest_timer > 4.0:
			for b in bodies:
				if is_instance_valid(b):
					b.sleeping = true
	else:
		_rest_timer = 0.0


func _pose() -> void:
	var world := {}
	var root_xf := _root_body.global_transform
	for i in _order:
		var w: Transform3D
		if _bone_body.has(i) and is_instance_valid(_bone_body[i][0]):
			w = (_bone_body[i][0] as RigidBody3D).global_transform * (_bone_body[i][1] as Transform3D)
		else:
			w = root_xf * (_rel[i] as Transform3D)
		world[i] = w
		var p := _skel.get_bone_parent(i)
		var local: Transform3D = (world[p] as Transform3D).affine_inverse() * w if p >= 0 else w
		_skel.set_bone_pose_position(i, local.origin)
		_skel.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())
		_skel.set_bone_pose_scale(i, local.basis.get_scale())


## Over budget: stop simulating and leave it lying where it is.
func retire() -> void:
	_frozen = true
	for b in bodies:
		if is_instance_valid(b):
			b.freeze = true
