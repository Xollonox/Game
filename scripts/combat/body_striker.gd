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

const FIST := {"id": "fist", "name": "Fist", "class": "fist", "cut": 0.0, "pierce": 0.0, "blunt": 0.55,
	"stagger": 1.0, "mass": 3.5, "min_blunt": 2.3, "blunt_energy": 4.0}
const FOOT := {"id": "foot", "name": "Kick", "class": "foot", "cut": 0.0, "pierce": 0.0, "blunt": 0.6,
	"stagger": 1.7, "mass": 5.5, "min_blunt": 2.0, "blunt_energy": 8.0}
const RADIUS := {"fist": 0.075, "foot": 0.1}

var actor: KickbackActor
var _query := PhysicsShapeQueryParameters3D.new()
var _sphere := SphereShape3D.new()
var _pending: Dictionary = {}  # target id -> best contact of this strike
var _struck: Dictionary = {}  # target id -> attack serial already delivered


func setup(a: KickbackActor) -> void:
	actor = a
	_query.shape = _sphere
	_query.collision_mask = KickbackLayers.ACTIVE_RAGDOLL_LAYER
	_query.collide_with_areas = false


func _physics_process(_delta: float) -> void:
	if not actor or actor.is_dead() or actor.is_downed():
		_pending.clear()
		return
	var strikers: Array = actor.current_strikers()
	var phase := actor.attack_phase()
	var live := not strikers.is_empty() and phase in ["accel", "active", "follow"]
	var touched := {}
	if live:
		_scan(strikers, phase, touched)
	# A strike lands with its hardest moment of contact: while fist or foot
	# stays on a man, keep the best verdict; deliver it once contact ends or
	# the strike's live window closes.
	for tid in _pending.keys():
		if live and touched.has(tid):
			continue
		_deliver(_pending[tid])
		_pending.erase(tid)


func _scan(strikers: Array, phase: String, touched: Dictionary) -> void:
	var bodies := actor.get_rig_bodies()
	var exclude: Array[RID] = []
	for b: RigidBody3D in bodies.values():
		exclude.append(b.get_rid())
	_query.exclude = exclude
	var space := actor.get_world_3d().direct_space_state
	for rig: String in strikers:
		var limb: RigidBody3D = bodies.get(rig)
		if not limb:
			continue
		var is_foot := rig.begins_with("Foot") or rig.begins_with("LowerLeg")
		var def: Dictionary = FOOT if is_foot else FIST
		_sphere.radius = RADIUS["foot" if is_foot else "fist"]
		_query.transform = Transform3D(Basis.IDENTITY, limb.global_position)
		for hit in space.intersect_shape(_query, 4):
			var body := hit["collider"] as RigidBody3D
			if not body or not body.has_meta(&"kickback_actor"):
				continue
			var target: KickbackActor = body.get_meta(&"kickback_actor")
			if target == actor or target.is_dead():
				continue
			var tid := target.get_instance_id()
			touched[tid] = true
			if _struck.get(tid, -1) == actor.attack_serial:
				continue  # once per man per strike
			var v_rel := limb.linear_velocity - WeaponContactEvaluator.point_velocity(body, limb.global_position)
			var normal := (body.global_position - limb.global_position).normalized()
			var verdict := WeaponContactEvaluator.evaluate(def, "head", limb.global_basis, v_rel, normal,
				float(def["mass"]), phase)
			if not verdict["valid"]:
				continue
			var best: Dictionary = _pending.get(tid, {})
			if best.is_empty() or float(verdict["energy"]) > float(best["verdict"]["energy"]):
				_pending[tid] = {"verdict": verdict, "target": target, "body": body, "point": limb.global_position,
					"dir": v_rel.normalized(), "def": def, "serial": actor.attack_serial,
					"power": actor.attack_power()}


func _deliver(p: Dictionary) -> void:
	var target: KickbackActor = p["target"]
	if not is_instance_valid(target) or target.is_dead() or not is_instance_valid(p["body"]):
		return
	_struck[target.get_instance_id()] = p["serial"]
	var v: Dictionary = p["verdict"]
	var def: Dictionary = p["def"]
	target.receive_weapon_hit({
		"rig_name": String((p["body"] as RigidBody3D).name), "dir": p["dir"], "speed": float(v["speed"]),
		"kind": "blunt", "quality": float(v["quality"]), "part": "head", "weapon": null,
		"def": def, "attacker": actor, "point": p["point"], "mass": float(def["mass"]),
		"power": p.get("power", 1.0),
	})
	actor.landed_hit.emit(target.name, "")
