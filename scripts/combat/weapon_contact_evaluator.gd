class_name WeaponContactEvaluator
extends RefCounted
## Decides whether a physical weapon contact is a *wounding blow* — and of
## which kind — or just contact: a blade resting on a shoulder, a scrape
## along mail, two men shoving, solver jitter.
##
## A contact is judged on four things, all at the actual contact point:
##
##   1. Relative velocity. v_rel = (v_w + ω_w × r_w) − (v_t + ω_t × r_t),
##      weapon point velocity minus target point velocity. A man walking into
##      a still sword has the same v_rel as a sword moving into a still man —
##      and neither is a cut unless the *edge* is what leads.
##   2. Which surface struck and how it was travelling. The weapon frame is
##      measured in Blender: local X is the flat, local Y runs edge to edge,
##      local Z runs pommel to point (the point is at −Z). So
##        edge speed    = |v_rel · Y|   — a cut needs the edge to lead,
##        flat speed    = |v_rel · X|   — a flat is a slap (blunt, weak),
##        axial speed   = v_rel · (−Z)  — a thrust needs the point to lead,
##        normal speed  = |v_rel · n|   — blunt needs to drive *into* the
##                                        surface, not slide along it.
##   3. Intent. The wielder's attack phase (prep / accel / active / follow /
##      recovery). Only accel, active and follow-through can wound; a blade
##      held in recovery or in a guard does not. With no attack (dropped
##      weapons, wild flailing) a contact must carry exceptional energy.
##   4. Contact lifetime (handled by the caller's ContactLog): one impact per
##      contact; sustained contact is never re-scored; a new impact needs a
##      real separation first.
##
## Thresholds are per weapon (WeaponCatalog STATS may override any of them);
## there is no single global minimum speed.

const PHASE_WEIGHT := {"prep": 0.0, "accel": 0.6, "active": 1.0, "follow": 0.75, "recovery": 0.0, "none": 0.0}

## Defaults by weapon class: min_cut / min_thrust / min_blunt are the
## qualifying component speeds (m/s); *_energy the minimum kinetic energy of
## that component (J, ½·m·v²); edge_align / thrust_align the fraction of the
## relative speed that must be carried by the edge / along the point.
const CLASS_DEFAULTS := {
	"sword": {"min_cut": 4.5, "min_thrust": 3.0, "min_blunt": 4.0, "cut_energy": 9.0, "thrust_energy": 5.0,
		"blunt_energy": 12.0, "edge_align": 0.6, "thrust_align": 0.8},
	"axe": {"min_cut": 4.0, "min_thrust": 99.0, "min_blunt": 3.8, "cut_energy": 10.0, "thrust_energy": 99.0,
		"blunt_energy": 11.0, "edge_align": 0.55, "thrust_align": 0.9},
	"dagger": {"min_cut": 3.2, "min_thrust": 2.2, "min_blunt": 4.0, "cut_energy": 1.8, "thrust_energy": 0.9,
		"blunt_energy": 8.0, "edge_align": 0.6, "thrust_align": 0.75},
	"spear": {"min_cut": 5.0, "min_thrust": 2.8, "min_blunt": 3.8, "cut_energy": 12.0, "thrust_energy": 7.0,
		"blunt_energy": 14.0, "edge_align": 0.65, "thrust_align": 0.82},
	"mace": {"min_cut": 99.0, "min_thrust": 99.0, "min_blunt": 3.4, "cut_energy": 99.0, "thrust_energy": 99.0,
		"blunt_energy": 9.0, "edge_align": 1.0, "thrust_align": 1.0},
	"club": {"min_cut": 99.0, "min_thrust": 99.0, "min_blunt": 3.6, "cut_energy": 99.0, "thrust_energy": 99.0,
		"blunt_energy": 8.0, "edge_align": 1.0, "thrust_align": 1.0},
	"shield": {"min_cut": 99.0, "min_thrust": 99.0, "min_blunt": 3.0, "cut_energy": 99.0, "thrust_energy": 99.0,
		"blunt_energy": 15.0, "edge_align": 1.0, "thrust_align": 1.0},
}
## Kinetic energy (J) a contact needs to wound with no attack behind it: a
## dropped axe landing blade-first, a weapon flung loose by a disarm.
const WILD_ENERGY := 45.0
## A haft, guard or pommel only ever knocks; this scales its blunt channel.
const HAFT_FACTOR := 0.35
const FLAT_FACTOR := 0.45


## Merged thresholds for a weapon definition.
static func thresholds(def: Dictionary) -> Dictionary:
	var cls: String = def.get("class", "sword")
	var t: Dictionary = (CLASS_DEFAULTS.get(cls, CLASS_DEFAULTS["sword"]) as Dictionary).duplicate()
	for k in t.keys():
		if def.has(k):
			t[k] = float(def[k])
	return t


## Velocity of [param point] on [param body] (a RigidBody3D, or null for a
## static target).
static func point_velocity(body: Object, point: Vector3) -> Vector3:
	if body is RigidBody3D:
		var rb := body as RigidBody3D
		var com := rb.global_transform * rb.center_of_mass if rb.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM \
			else rb.global_position
		return rb.linear_velocity + rb.angular_velocity.cross(point - com)
	return Vector3.ZERO


## Scores one contact. Inputs:
##   def         weapon definition (WeaponCatalog.get_def)
##   part        struck part: edge / point / head / haft / guard / shield
##   basis       weapon world basis (X flat, Y edge, Z pommel->point is −Z)
##   v_rel       relative velocity at the contact point (weapon − target)
##   normal      contact normal (either sign)
##   mass        weapon mass (kg)
##   phase       wielder's attack phase ("none" if no wielder / not attacking)
## Returns {valid, kind, speed (qualifying component), energy, quality,
## reason}. `quality` (0..1) scales damage for glancing / early-phase blows.
static func evaluate(def: Dictionary, part: String, basis: Basis, v_rel: Vector3, normal: Vector3,
		mass: float, phase: String) -> Dictionary:
	var t := thresholds(def)
	var speed := v_rel.length()
	var out := {"valid": false, "kind": "", "speed": 0.0, "energy": 0.0, "quality": 0.0, "reason": "",
		"rel_speed": speed}
	if speed < 0.5:
		out["reason"] = "resting"
		return out
	var ke_total := 0.5 * mass * speed * speed
	var intent := float(PHASE_WEIGHT.get(phase, 0.0))
	var wild := ke_total >= WILD_ENERGY
	if intent <= 0.0 and not wild:
		out["reason"] = "no_intent"
		return out
	if intent <= 0.0:
		intent = 0.7  # uncontrolled but violent
	var ex := basis.x.normalized()
	var ey := basis.y.normalized()
	var ez := -basis.z.normalized()  # toward the point
	var n := normal.normalized() if normal.length_squared() > 1e-6 else v_rel / speed
	var edge_v := absf(v_rel.dot(ey))
	var flat_v := absf(v_rel.dot(ex))
	var axial_v := v_rel.dot(ez)
	var normal_v := absf(v_rel.dot(n))
	out["edge_v"] = edge_v
	out["flat_v"] = flat_v
	out["axial_v"] = axial_v
	out["normal_v"] = normal_v
	out["part"] = part
	var cls: String = def.get("class", "sword")
	var cutting := float(def.get("cut", 0.0))
	var piercing := float(def.get("pierce", 0.0))

	var kind := ""
	var comp := 0.0
	var align := 0.0
	match part:
		"point":
			align = axial_v / speed
			if piercing > 0.3 and axial_v >= t["thrust_align"] * speed and axial_v >= t["min_thrust"]:
				kind = "pierce"
				comp = axial_v
			elif cutting > 0.3 and edge_v >= t["edge_align"] * speed and edge_v >= t["min_cut"]:
				kind = "cut"  # the last hand of an edge sweeping through
				comp = edge_v * 0.8
				align = edge_v / speed
			else:
				kind = "blunt"
				comp = normal_v * 0.4
				align = 0.4
		"edge":
			align = edge_v / speed
			if cutting > 0.2 and edge_v >= t["edge_align"] * speed and edge_v >= t["min_cut"]:
				kind = "cut"
				comp = edge_v
			elif flat_v >= 0.6 * speed:
				kind = "blunt"  # the flat of the blade: a slap
				comp = minf(flat_v, normal_v) * FLAT_FACTOR
				align = FLAT_FACTOR
			else:
				kind = "blunt"  # sliding along the blade: a scrape
				comp = normal_v * 0.25
				align = 0.25
		"head":
			kind = "blunt"
			comp = normal_v
			align = normal_v / speed
		"shield":
			kind = "blunt"
			comp = normal_v
			align = normal_v / speed
		_:  # haft, guard, pommel
			kind = "blunt"
			comp = normal_v * HAFT_FACTOR
			align = HAFT_FACTOR
	var min_key: String = {"cut": "min_cut", "pierce": "min_thrust", "blunt": "min_blunt"}[kind]
	var e_key: String = {"cut": "cut_energy", "pierce": "thrust_energy", "blunt": "blunt_energy"}[kind]
	var energy := 0.5 * mass * comp * comp
	out["kind"] = kind
	out["speed"] = comp
	out["energy"] = energy
	# Secondary surfaces (haft, guard, a flat or scraping blade) are judged on
	# their already-reduced speed against a proportionally lower bar.
	if comp < float(t[min_key]) * (0.35 if kind == "blunt" and part != "head" and part != "shield" else 1.0):
		out["reason"] = "too_slow"
		return out
	if energy < float(t[e_key]) * (0.25 if kind == "blunt" and part != "head" and part != "shield" else 1.0):
		out["reason"] = "too_weak"
		return out
	out["valid"] = true
	out["quality"] = clampf(intent * clampf(align, 0.2, 1.0), 0.05, 1.0)
	out["reason"] = "ok"
	if cls == "shield":
		out["kind"] = "blunt"
	return out


# ------------------------------------------------------------ contact log --
## Per-weapon memory of which targets it is touching, so a contact is scored
## once on impact, never while it persists, and again only after a genuine
## separation (and, during an attack, only once per swing per target).
class ContactLog:
	extends RefCounted
	const SEPARATION := 0.12  # s without contact before a new impact counts
	var _last_seen: Dictionary = {}  # target id -> time (s)
	var _swing_hit: Dictionary = {}  # target id -> attack serial

	## Registers contact with [param target_id] at [param now]. Returns true if
	## this is a fresh impact (no contact within SEPARATION before it).
	func touch(target_id: int, now: float) -> bool:
		var prev: float = _last_seen.get(target_id, -1e9)
		_last_seen[target_id] = now
		return now - prev > SEPARATION

	func already_hit_this_swing(target_id: int, serial: int) -> bool:
		return serial > 0 and int(_swing_hit.get(target_id, -1)) == serial

	func mark_swing(target_id: int, serial: int) -> void:
		if serial > 0:
			_swing_hit[target_id] = serial
