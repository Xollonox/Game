class_name InjurySystem
extends RefCounted
## Regional injuries: what a blow actually did to the body, and what that
## does to the man.
##
## Seventeen regions, each with its own tissue damage (cuts, thrusts), blunt
## trauma (bruising, broken bone), bleeding, a fracture flag and a severed
## flag. Function (0..1) per region comes from those. The consequences are
## physical, not a bar ticking down:
##
##   sword arm  -> weaker springs on that arm, less weapon control, a looser
##                 grip (disarms, see WeaponGrip), slower recovery
##   shield arm -> the shield droops
##   legs       -> limp (slower, shorter gait), weaker balance tolerance,
##                 eventually the leg gives way
##   head       -> concussion: stun (springs go slack for a moment), blurred
##                 balance; a crushed skull kills
##   neck/torso -> heavy bleeding, winded (slower attacks), lethal wounds
##
## Global `health` still exists for game flow (victory, yielding, the HUD),
## but it is now *systemic*: blood lost plus the shock of lethal-region
## wounds, not a sum of every scratch.

const REGIONS := ["head", "neck", "chest", "abdomen", "pelvis",
	"upper_arm_l", "forearm_l", "hand_l", "upper_arm_r", "forearm_r", "hand_r",
	"thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r"]

## Region -> [tissue capacity (damage to ruin it), vascular (bleed factor),
##             lethal weight (share of damage that is systemic), rig body]
const ANATOMY := {
	"head": [30.0, 0.6, 1.0, "Head"],
	"neck": [16.0, 2.2, 1.2, "Head"],
	"chest": [60.0, 1.0, 0.8, "Chest"],
	"abdomen": [50.0, 1.2, 0.7, "Spine"],
	"pelvis": [55.0, 1.0, 0.5, "Hips"],
	"upper_arm_l": [30.0, 0.9, 0.12, "UpperArm_L"], "upper_arm_r": [30.0, 0.9, 0.12, "UpperArm_R"],
	"forearm_l": [24.0, 0.7, 0.08, "LowerArm_L"], "forearm_r": [24.0, 0.7, 0.08, "LowerArm_R"],
	"hand_l": [14.0, 0.4, 0.04, "Hand_L"], "hand_r": [14.0, 0.4, 0.04, "Hand_R"],
	"thigh_l": [45.0, 1.3, 0.2, "UpperLeg_L"], "thigh_r": [45.0, 1.3, 0.2, "UpperLeg_R"],
	"shin_l": [30.0, 0.6, 0.08, "LowerLeg_L"], "shin_r": [30.0, 0.6, 0.08, "LowerLeg_R"],
	"foot_l": [18.0, 0.4, 0.04, "Foot_L"], "foot_r": [18.0, 0.4, 0.04, "Foot_R"],
}
## Blunt energy (after armour) that breaks the bone of a region in one blow.
const FRACTURE_AT := {"head": 0.9, "forearm_l": 0.75, "forearm_r": 0.75, "hand_l": 0.6, "hand_r": 0.6,
	"shin_l": 0.85, "shin_r": 0.85, "upper_arm_l": 0.95, "upper_arm_r": 0.95, "thigh_l": 1.2, "thigh_r": 1.2,
	"foot_l": 0.7, "foot_r": 0.7, "chest": 1.1}

## Per region: {tissue, blunt, bleed (hp/s), fractured, severed}
var regions: Dictionary = {}
## Blood volume, 1 = full; below ~0.45 a man cannot stay conscious.
var blood := 1.0
## Seconds of concussion stun left.
var stun := 0.0


func _init() -> void:
	for r in REGIONS:
		regions[r] = {"tissue": 0.0, "blunt": 0.0, "bleed": 0.0, "fractured": false, "severed": false}


## Region struck on rig body [param rig] at [param local] (point in that
## body's frame). The head body also carries the neck: a blow landing low on
## it, below the jaw, is the neck.
static func region_for(rig: String, local: Vector3 = Vector3.ZERO) -> String:
	match rig:
		"Head":
			return "neck" if local.y < -0.06 else "head"
		"Chest":
			return "chest"
		"Spine":
			return "abdomen"
		"Hips":
			return "pelvis"
	var side := "l" if rig.ends_with("_L") else "r"
	if rig.begins_with("UpperArm"):
		return "upper_arm_" + side
	if rig.begins_with("LowerArm"):
		return "forearm_" + side
	if rig.begins_with("Hand"):
		return "hand_" + side
	if rig.begins_with("UpperLeg"):
		return "thigh_" + side
	if rig.begins_with("LowerLeg"):
		return "shin_" + side
	if rig.begins_with("Foot"):
		return "foot_" + side
	return "chest"


## Records one wounding blow. [param flesh] is the damage that reached flesh
## (after armour), [param trauma] the blunt energy transmitted *through*
## armour (plate stops the edge, not the blow). Returns
## {region, systemic, fractured_now, bleed_added, lethal}.
func apply(region: String, kind: String, flesh: float, trauma: float) -> Dictionary:
	var r: Dictionary = regions[region]
	var an: Array = ANATOMY[region]
	var cap: float = an[0]
	var out := {"region": region, "systemic": 0.0, "fractured_now": false, "bleed_added": 0.0, "lethal": false}
	if r["severed"]:
		return out
	match kind:
		"cut":
			r["tissue"] = float(r["tissue"]) + flesh / cap
			out["bleed_added"] = flesh * 0.045 * float(an[1])
		"pierce":
			r["tissue"] = float(r["tissue"]) + flesh * 1.15 / cap
			out["bleed_added"] = flesh * 0.06 * float(an[1])
		_:
			r["tissue"] = float(r["tissue"]) + flesh * 0.3 / cap
	# Blunt trauma: from blunt blows, and what any blow transmits through armour.
	var tr := trauma / cap
	r["blunt"] = float(r["blunt"]) + tr
	if not r["fractured"] and FRACTURE_AT.has(region) and tr >= float(FRACTURE_AT[region]) * 0.45:
		r["fractured"] = true
		out["fractured_now"] = true
	r["bleed"] = float(r["bleed"]) + float(out["bleed_added"])
	if region == "head":
		stun = maxf(stun, clampf(tr * 3.0, 0.0, 2.5))
	# Systemic share: a cut throat kills, a cut hand does not.
	out["systemic"] = (flesh + trauma * 0.35) * float(an[2])
	out["lethal"] = (region in ["head", "neck", "chest", "abdomen"]) and float(r["tissue"]) >= 1.25 \
		or (region == "head" and float(r["blunt"]) >= 1.6)
	return out


## Function 0..1 of one region.
func function(region: String) -> float:
	var r: Dictionary = regions[region]
	if r["severed"]:
		return 0.0
	var f := 1.0 - 0.75 * clampf(float(r["tissue"]), 0.0, 1.0) - 0.55 * clampf(float(r["blunt"]), 0.0, 1.0)
	if r["fractured"]:
		f = minf(f, 0.25)
	return clampf(f, 0.0, 1.0)


## Function of a whole arm ("l"/"r"): the weakest link of shoulder to hand
## dominates, the rest still counts.
func arm_function(side: String) -> float:
	var parts := [function("upper_arm_" + side), function("forearm_" + side), function("hand_" + side)]
	return clampf(parts.min() * 0.7 + (parts[0] + parts[1] + parts[2]) / 3.0 * 0.3, 0.0, 1.0)


func leg_function(side: String) -> float:
	var parts := [function("thigh_" + side), function("shin_" + side), function("foot_" + side)]
	return clampf(parts.min() * 0.7 + (parts[0] + parts[1] + parts[2]) / 3.0 * 0.3, 0.0, 1.0)


## Breathing and core: cuts to chest and belly slow a man down.
func core_function() -> float:
	return clampf((function("chest") + function("abdomen")) * 0.5, 0.0, 1.0)


func total_bleed() -> float:
	var b := 0.0
	for r in regions.values():
		b += float(r["bleed"])
	return b


## Advances bleeding (clotting slowly) and stun. Returns blood-loss damage
## this step in health units (100 health ~ the whole blood volume that can
## be lost before collapse).
func tick(delta: float) -> float:
	stun = maxf(0.0, stun - delta)
	var loss := 0.0
	for key in regions:
		var r: Dictionary = regions[key]
		var b := float(r["bleed"])
		if b <= 0.0:
			continue
		loss += b * delta
		# Clotting: small wounds stop, arterial ones barely slow.
		var clot := 0.12 if not r["severed"] else 0.02
		r["bleed"] = maxf(0.0, b - (clot + b * 0.02) * delta)
	blood = maxf(0.0, blood - loss / 180.0)
	return loss


## Per-rig-body impairment (0 = sound, 1 = useless) for the spring layer.
func rig_impairment() -> Dictionary:
	var out := {}
	for key in regions:
		var rig: String = ANATOMY[key][3]
		out[rig] = maxf(float(out.get(rig, 0.0)), 1.0 - function(key))
	return out
