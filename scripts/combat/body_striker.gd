class_name BodyStriker
extends Node
## Punches and kicks as physical strikes.
##
## While an unarmed attack (or a kick, which any fighter can throw) is in its
## accel / active / follow phase, the striking limb's rig body — a fist or a
## foot — is swept for contact with other fighters' bodies (one small sphere
## query per striking limb per physics step, only while striking). A contact
## is judged by the same WeaponContactEvaluator as a weapon: relative speed at
## the contact, intent from the attack phase, one blow per man per strike.
## The limb's effective striking mass (an arm behind a fist, a leg behind a
## heel) stands in for weapon mass.

const FIST := {"id": "fist", "name": "Fist", "class": "fist", "cut": 0.0, "pierce": 0.0, "blunt": 0.4,
	"stagger": 0.9, "mass": 2.2, "min_blunt": 3.2, "blunt_energy": 9.0}
const FOOT := {"id": "foot", "name": "Kick", "class": "foot", "cut": 0.0, "pierce": 0.0, "blunt": 0.55,
	"stagger": 1.6, "mass": 5.5, "min_blunt": 2.6, "blunt_energy": 16.0}
const RADIUS := {"fist": 0.075, "foot": 0.1}

var actor: KickbackActor
var _query := PhysicsShapeQueryParameters3D.new()
var _sphere := SphereShape3D.new()
var _logs: Dictionary = {}  # rig -> ContactLog


func setup(a: KickbackActor) -> void:
	actor = a
	_query.shape = _sphere
	_query.collision_mask = KickbackLayers.ACTIVE_RAGDOLL_LAYER
	_query.collide_with_areas = false


func _physics_process(_delta: float) -> void:
	if not actor or actor.is_dead() or actor.is_downed():
		return
	var strikers: Array = actor.current_strikers()
	if strikers.is_empty():
		return
	var phase := actor.attack_phase()
	if not phase in ["accel", "active", "follow"]:
		return
	var bodies := actor.get_rig_bodies()
	var exclude: Array[RID] = []
	for b: RigidBody3D in bodies.values():
		exclude.append(b.get_rid())
	_query.exclude = exclude
	var space := actor.get_world_3d().direct_space_state
	var now := Time.get_ticks_msec() / 1000.0
	for rig: String in strikers:
		var limb: RigidBody3D = bodies.get(rig)
		if not limb:
			continue
		var is_foot := rig.begins_with("Foot") or rig.begins_with("LowerLeg")
		var def: Dictionary = FOOT if is_foot else FIST
		_sphere.radius = RADIUS["foot" if is_foot else "fist"]
		_query.transform = Transform3D(Basis.IDENTITY, limb.global_position)
		if not _logs.has(rig):
			_logs[rig] = WeaponContactEvaluator.ContactLog.new()
		var clog: WeaponContactEvaluator.ContactLog = _logs[rig]
		for hit in space.intersect_shape(_query, 4):
			var body := hit["collider"] as RigidBody3D
			if not body or not body.has_meta(&"kickback_actor"):
				continue
			var target: KickbackActor = body.get_meta(&"kickback_actor")
			if target == actor or target.is_dead():
				continue
			var tid := target.get_instance_id()
			if not clog.touch(tid, now) or clog.already_hit_this_swing(tid, actor.attack_serial):
				continue
			var v_rel := limb.linear_velocity - WeaponContactEvaluator.point_velocity(body, limb.global_position)
			var normal := (body.global_position - limb.global_position).normalized()
			var verdict := WeaponContactEvaluator.evaluate(def, "head", limb.global_basis, v_rel, normal,
				float(def["mass"]), phase)
			if not verdict["valid"]:
				continue
			clog.mark_swing(tid, actor.attack_serial)
			target.receive_weapon_hit({
				"rig_name": String(body.name), "dir": v_rel.normalized(), "speed": float(verdict["speed"]),
				"kind": "blunt", "quality": float(verdict["quality"]), "part": "head", "weapon": null,
				"def": def, "attacker": actor, "point": limb.global_position, "mass": float(def["mass"]),
			})
			actor.landed_hit.emit(target.name, "")
			break
