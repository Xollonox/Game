class_name AttackLibrary
extends RefCounted
## Move sets per weapon family. Each move names the animation the rig's hands
## chase; the weapon itself stays a physics body, so the same cut looks and
## lands differently with a dagger and a mace.
##
## Our own clips (authored in tools/blender/melee_anims.py from HEMA body
## mechanics: passing steps, hip and shoulder rotation, follow-through) are
## preferred; the Quaternius clips are fallbacks so a missing clip never
## leaves a fighter unable to attack.
##
## Bare-handed strikes and kicks are real motion capture (MC_*, CMU mocap
## retargeted by tools/blender/mocap_anims.py); their hit windows come from the
## measured speed of the striking fist or foot (mocap_anims.json).
##
## Move fields: anim, speed (playback rate), commit (fraction of the clip the
## fighter is locked into), move_scale (how much locomotion survives the
## attack), dir (the line of the cut: high / left / right / low / thrust).

## Normalized clip times of [wind-up peak, strike, end of follow-through],
## the key layout every authored cut in melee_anims.py uses (0.28/0.47/0.66
## of a 1.2 s Oberhau). A move may carry its own "phases".
const DEFAULT_PHASES := [0.23, 0.39, 0.56]

const MOVES := {
	"sword": {
		"cut": [
			{"anim": "Cut_Oberhau", "dir": "high", "speed": 1.0, "commit": 0.78},
			{"anim": "Cut_Mittel_R", "dir": "right", "speed": 1.0, "commit": 0.74},
			{"anim": "Cut_Mittel_L", "dir": "left", "speed": 1.0, "commit": 0.74},
			{"anim": "Cut_Unterhau", "dir": "low", "speed": 1.0, "commit": 0.74},
			{"anim": "Sword_A", "dir": "right", "speed": 1.05, "commit": 0.72},
			{"anim": "Sword_B", "dir": "left", "speed": 1.05, "commit": 0.72},
			{"anim": "Sword_C", "dir": "high", "speed": 1.0, "commit": 0.75},
		],
		"thrust": [
			{"anim": "Thrust_Mid", "dir": "thrust", "speed": 1.0, "commit": 0.78, "move_scale": 0.9},
			{"anim": "Sword_Dash", "dir": "thrust", "speed": 1.0, "commit": 0.7, "move_scale": 0.9},
		],
		"heavy": [
			{"anim": "Cut_Heavy", "dir": "high", "speed": 1.0, "commit": 0.85},
			{"anim": "Sword_Heavy_Combo", "dir": "high", "speed": 1.1, "commit": 0.55},
		],
	},
	"longsword": {
		"cut": [
			{"anim": "LS_Oberhau", "dir": "high", "speed": 1.0, "commit": 0.78},
			{"anim": "LS_Zwerch_R", "dir": "right", "speed": 1.0, "commit": 0.76},
			{"anim": "LS_Zwerch_L", "dir": "left", "speed": 1.0, "commit": 0.76},
			{"anim": "LS_Unterhau", "dir": "low", "speed": 1.0, "commit": 0.76},
		],
		"thrust": [{"anim": "LS_Thrust", "dir": "thrust", "speed": 1.0, "commit": 0.8, "move_scale": 0.9}],
		"heavy": [{"anim": "LS_Oberhau", "dir": "high", "speed": 0.85, "commit": 0.85}],
	},
	"blunt": {
		"cut": [
			{"anim": "Blunt_Overhead", "dir": "high", "speed": 1.0, "commit": 0.8},
			{"anim": "Blunt_Side_R", "dir": "right", "speed": 1.0, "commit": 0.78},
			{"anim": "Blunt_Side_L", "dir": "left", "speed": 1.0, "commit": 0.78},
			{"anim": "Sword_Attack", "dir": "high", "speed": 1.1, "commit": 0.75},
			{"anim": "Sword_A", "dir": "right", "speed": 0.95, "commit": 0.75},
		],
		"thrust": [{"anim": "Blunt_Jab", "dir": "thrust", "speed": 1.0, "commit": 0.7},
			{"anim": "Sword_Dash", "dir": "thrust", "speed": 0.95, "commit": 0.7}],
		"heavy": [{"anim": "Blunt_Overhead", "dir": "high", "speed": 0.85, "commit": 0.85},
			{"anim": "Sword_Heavy_Combo", "dir": "high", "speed": 1.0, "commit": 0.55}],
	},
	"dagger": {
		"cut": [
			{"anim": "Dagger_Stab_High", "dir": "high", "speed": 1.0, "commit": 0.7, "move_scale": 0.8},
			{"anim": "Dagger_Stab_Low", "dir": "low", "speed": 1.0, "commit": 0.7, "move_scale": 0.8},
			{"anim": "Melee_Hook", "dir": "right", "speed": 1.1, "commit": 0.7},
			{"anim": "Punch_Cross", "dir": "thrust", "speed": 1.0, "commit": 0.7},
		],
		"thrust": [{"anim": "Dagger_Stab_Low", "dir": "thrust", "speed": 1.0, "commit": 0.7, "move_scale": 0.8},
			{"anim": "Punch_Jab", "dir": "thrust", "speed": 1.0, "commit": 0.7}],
		"heavy": [{"anim": "Dagger_Stab_High", "dir": "high", "speed": 0.9, "commit": 0.8}],
	},
	"unarmed": {
		"cut": [
			{"anim": "MC_Jab", "dir": "thrust", "speed": 1.1, "commit": 0.7, "strikers": ["Hand_L"]},
			{"anim": "MC_Cross", "dir": "right", "speed": 1.05, "commit": 0.72, "strikers": ["Hand_R"]},
			{"anim": "MC_Hook", "dir": "left", "speed": 1.05, "commit": 0.74, "strikers": ["Hand_R", "Hand_L"]},
			{"anim": "MC_Uppercut", "dir": "high", "speed": 1.0, "commit": 0.74, "strikers": ["Hand_R"]},
			{"anim": "MC_Body_Shot", "dir": "low", "speed": 1.0, "commit": 0.74, "strikers": ["Hand_R"]},
			# Fallbacks if the mocap library is missing.
			{"anim": "Punch_Jab", "dir": "thrust", "speed": 1.4, "commit": 0.62, "strikers": ["Hand_L", "Hand_R"],
				"fallback": true},
			{"anim": "Punch_Cross", "dir": "right", "speed": 1.35, "commit": 0.66, "strikers": ["Hand_R", "Hand_L"],
				"fallback": true},
		],
		"thrust": [
			{"anim": "MC_Jab", "dir": "thrust", "speed": 1.15, "commit": 0.68, "strikers": ["Hand_L"]},
			{"anim": "Punch_Jab", "dir": "thrust", "speed": 1.4, "commit": 0.62, "strikers": ["Hand_L", "Hand_R"],
				"fallback": true},
		],
		"heavy": [
			{"anim": "MC_Uppercut", "dir": "high", "speed": 0.95, "commit": 0.8, "power": 1.2, "strikers": ["Hand_R"]},
			{"anim": "MC_Cross", "dir": "right", "speed": 0.95, "commit": 0.8, "power": 1.2, "strikers": ["Hand_R"]},
			{"anim": "Punch_Cross", "dir": "high", "speed": 1.15, "commit": 0.75, "strikers": ["Hand_R", "Hand_L"],
				"fallback": true},
		],
		# Any fighter can kick, armed or not (see KickbackActor.attack).
		"kick": [
			{"anim": "MC_Kick_Front", "dir": "thrust", "speed": 1.15, "commit": 0.78, "move_scale": 0.3,
				"strikers": ["Foot_R", "LowerLeg_R"]},
			{"anim": "MC_Kick_Front_L", "dir": "thrust", "speed": 1.15, "commit": 0.78, "move_scale": 0.3,
				"strikers": ["Foot_L", "LowerLeg_L"]},
			{"anim": "Kick_Low", "dir": "low", "speed": 1.0, "commit": 0.8, "move_scale": 0.3,
				"strikers": ["Foot_R", "LowerLeg_R"]},
			{"anim": "Kick_Front", "dir": "thrust", "speed": 1.0, "commit": 0.8, "move_scale": 0.3,
				"strikers": ["Foot_R", "LowerLeg_R"], "fallback": true},
		],
	},
	"spear": {
		"cut": [
			{"anim": "Spear_Thrust", "dir": "thrust", "speed": 1.0, "commit": 0.75, "move_scale": 0.8},
			{"anim": "Spear_Thrust_High", "dir": "high", "speed": 1.0, "commit": 0.75, "move_scale": 0.8},
			{"anim": "Spear_Swing", "dir": "right", "speed": 1.0, "commit": 0.8},
			{"anim": "Sword_Dash", "dir": "thrust", "speed": 0.95, "commit": 0.7},
		],
		"thrust": [{"anim": "Spear_Thrust", "dir": "thrust", "speed": 1.0, "commit": 0.75, "move_scale": 0.8}],
		"heavy": [{"anim": "Spear_Swing", "dir": "right", "speed": 0.9, "commit": 0.85}],
	},
}


## Picks a move of [param kind] for [param family]. [param context] may carry
## "dir" (the line the player steered the attack into). Without it, cuts
## alternate forehand/backhand/overhead with the combo counter so an exchange
## flows rather than repeating one clip.
static func pick(family: String, kind: String, combo: int, context: Dictionary, anim: AnimationPlayer,
		rng: RandomNumberGenerator) -> Dictionary:
	var set: Dictionary = MOVES.get(family, MOVES["sword"])
	var list: Array = set.get(kind, set["cut"]) if kind != "any" else set["cut"] + set.get("thrust", [])
	var avail: Array = []
	for m in list:
		if anim.has_animation(m["anim"]):
			avail.append(m)
	if avail.is_empty() and family != "sword" and family != "unarmed":
		return pick("sword", kind, combo, context, anim, rng)
	if avail.is_empty():
		return {}
	# Prefer our authored clips over the fallbacks when both exist.
	var authored := avail.filter(func(m): return _is_authored(m) and not m.get("fallback", false))
	if not authored.is_empty():
		avail = authored
	var want_dir: String = context.get("dir", "")
	if want_dir != "":
		var matching := avail.filter(func(m): return m.get("dir", "") == want_dir)
		if not matching.is_empty():
			return _with_timing(matching[rng.randi_range(0, matching.size() - 1)])
	if kind == "cut" and avail.size() > 1:
		# Alternate lines: after a right-side cut the blade is already on the
		# left, so the natural follow-up comes from there.
		return _with_timing(avail[(combo + (rng.randi() % 2 if context.get("ai", false) else 0)) % avail.size()])
	return _with_timing(avail[rng.randi_range(0, avail.size() - 1)])


## The ultimate: a combination the fighter earns by landing blows (see
## KickbackActor.ultimate). Bare-handed it is the captured jab-jab-cross-
## kick-kick combination, every blow its own strike; with a weapon it is the
## family's heaviest move, thrown faster and landing half again as hard.
const ULTIMATE_UNARMED := {"anim": "MC_Ultimate_Combo", "dir": "thrust", "speed": 1.1, "commit": 0.9,
	"move_scale": 0.35, "power": 1.6, "ultimate": true,
	"strikers": ["Hand_L", "Hand_R", "Foot_R", "Foot_L", "LowerLeg_R", "LowerLeg_L"],
	"phases": [0.04, 0.08, 0.9], "hits": [0.16, 0.25, 0.37, 0.55, 0.74],
	# The punches set up, the kicks finish: power per blow of the combination.
	"hit_power": [1.15, 1.15, 1.25, 1.45, 1.75, 1.9]}


static func ultimate(family: String, anim: AnimationPlayer, rng: RandomNumberGenerator) -> Dictionary:
	if family == "unarmed" and anim.has_animation(ULTIMATE_UNARMED["anim"]):
		return ULTIMATE_UNARMED.duplicate()
	var m := pick(family, "heavy", 0, {}, anim, rng)
	if m.is_empty():
		return {}
	m = m.duplicate()
	m["speed"] = float(m.get("speed", 1.0)) * 1.15
	m["power"] = 1.6
	m["commit"] = maxf(float(m.get("commit", 0.8)), 0.85)
	m["ultimate"] = true
	return m


static var _mocap_timing: Dictionary = {}


## Mocap moves carry their measured [wind-up, strike, recovery] timing.
static func _with_timing(m: Dictionary) -> Dictionary:
	if m.has("phases") or not String(m["anim"]).begins_with("MC_"):
		return m
	if _mocap_timing.is_empty():
		var f := FileAccess.open("res://assets/models/characters/fighter/mocap_anims.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			_mocap_timing = d if d is Dictionary else {"_": {}}
		else:
			_mocap_timing = {"_": {}}
	var ph = _mocap_timing.get(m["anim"], {}).get("phases")
	if ph is Array and ph.size() == 3:
		m = m.duplicate()
		# The live window opens a little before the measured start of the
		# strike (the physical fist lags the pose) and stays open to recovery.
		m["phases"] = [maxf(0.0, float(ph[0]) - 0.04), float(ph[1]), minf(1.0, float(ph[2]) + 0.05)]
	return m


static func _is_authored(m: Dictionary) -> bool:
	var a := String(m["anim"])
	return not (a.begins_with("Sword_") or a.begins_with("Melee"))


static func stance_candidates(family: String, has_shield: bool) -> Array:
	if has_shield:
		return ["Stance_Shield", "Shield_Idle", "Sword_Idle"]
	match family:
		"longsword":
			return ["Guard_Longsword", "Stance_Sword", "Sword_Idle"]
		"spear":
			return ["Guard_Spear", "Stance_Sword", "Sword_Idle"]
		"dagger":
			return ["Stance_Dagger", "Stance_Sword", "Sword_Idle"]
		"blunt":
			return ["Stance_Blunt", "Stance_Sword", "Sword_Idle"]
		"none":
			return ["Stance_Idle", "Idle"]
	return ["Stance_Sword", "Sword_Idle"]


static func guard_anim(family: String, has_shield: bool, anim: AnimationPlayer, line := "") -> String:
	var cands := ["Guard_Shield", "Shield_Idle"] if has_shield else []
	var sfx: String = {"low": "_Low", "left": "_Side_L", "right": "_Side_R"}.get(line, "")
	match family:
		"unarmed":
			# Forearm blocks from the mocap: the lead (left) arm covers the
			# left flank, the rear arm the head and right.
			cands += ["MC_Block_High_L"] if line == "left" else ["MC_Block_High"]
			cands += ["Guard_High"]
		"longsword":
			if sfx != "":
				cands.append("Guard_Longsword" + sfx)
			cands += ["Guard_Longsword_High", "Guard_High"]
		"spear":
			cands += ["Guard_Spear_High", "Guard_High"]
		_:
			if sfx != "":
				cands.append("Guard" + sfx)
			cands += ["Guard_High"]
	cands.append("Sword_Block")
	for c in cands:
		if anim and anim.has_animation(c):
			return c
	return "Sword_Block"


static func getup_anim(face_up: bool, anim: AnimationPlayer, rng: RandomNumberGenerator) -> String:
	var cands := ["GetUp_Back", "GetUp_Back_2"] if face_up else ["GetUp_Front", "GetUp_Front_2", "GetUp_Back"]
	var avail := cands.filter(func(c): return anim.has_animation(c))
	if avail.is_empty():
		return ""
	return avail[rng.randi_range(0, avail.size() - 1)]
