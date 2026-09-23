class_name Armory
extends RefCounted
## Everything a fighter can wear, what it protects, and how an opponent of a
## given rank gets kitted out.
##
## Garment names match the meshes the Blender wardrobe exports
## (tools/blender/wardrobe.py): `G_*` cloth, `A_*` armour, `H_*` headgear,
## `X_*` accessories. Protection is per damage channel (cut / pierce / blunt) as
## the fraction a layer absorbs; layers stack multiplicatively on the remaining
## damage, so a gambeson under mail under plate behaves like the real stack —
## each layer matters less once something harder is on top, but padding is what
## makes plate survivable against a mace. `cover` is the chance a blow to that
## body region actually lands on the layer (open-faced helmets, the gaps in a
## harness) rather than slipping past it.

## rig slot groups (Kickback rig_names)
const TORSO := ["Chest", "Spine", "Hips"]
const ARMS_UP := ["UpperArm_L", "UpperArm_R"]
const ARMS_LO := ["LowerArm_L", "LowerArm_R"]
const HANDS := ["Hand_L", "Hand_R"]
const LEGS_UP := ["UpperLeg_L", "UpperLeg_R"]
const LEGS_LO := ["LowerLeg_L", "LowerLeg_R"]
const FEET := ["Foot_L", "Foot_R"]
const HEAD := ["Head"]

## name: [slots, cut, pierce, blunt, cover, weight kg, hides body zones, hides hair]
const LAYERS := {
	"G_Shirt": [TORSO + ARMS_UP + ARMS_LO, 0.05, 0.02, 0.02, 1.0, 0.3, ["Torso", "UpperArm", "LowerArm"], false],
	"G_Tunic": [TORSO + ARMS_UP + LEGS_UP, 0.12, 0.05, 0.06, 1.0, 1.0, ["Torso", "UpperArm"], false],
	"G_Hose": [LEGS_UP + LEGS_LO, 0.05, 0.02, 0.02, 1.0, 0.3, ["Thigh", "ShinUp", "ShinLow"], false],
	"G_Shoes": [FEET, 0.1, 0.05, 0.05, 1.0, 0.4, ["Foot"], false],
	"G_Boots": [FEET + LEGS_LO, 0.2, 0.1, 0.06, 0.9, 1.0, ["Foot", "ShinLow"], false],
	"G_Cap": [HEAD, 0.04, 0.02, 0.03, 0.5, 0.1, [], true],
	"G_Hood": [HEAD, 0.12, 0.06, 0.08, 0.7, 0.5, ["Neck"], true],
	"G_Gloves": [HANDS, 0.2, 0.1, 0.08, 1.0, 0.2, ["Hand"], false],
	"A_Gambeson": [TORSO + ARMS_UP + ARMS_LO + LEGS_UP, 0.42, 0.3, 0.32, 1.0, 4.0, ["Torso", "UpperArm", "LowerArm"], false],
	"A_Haubergeon": [TORSO + ARMS_UP + LEGS_UP, 0.8, 0.45, 0.15, 1.0, 9.0, ["Torso", "UpperArm"], false],
	"A_MailCoif": [HEAD, 0.6, 0.4, 0.1, 0.65, 2.0, ["Neck"], true],
	"A_Brigandine": [["Chest", "Spine"], 0.88, 0.7, 0.35, 0.95, 8.0, [], false],
	"A_Cuirass": [TORSO, 0.95, 0.82, 0.45, 0.95, 12.0, [], false],
	"A_Pauldrons": [ARMS_UP, 0.9, 0.75, 0.35, 0.6, 2.0, [], false],
	"A_Rerebraces": [ARMS_UP, 0.9, 0.75, 0.35, 0.7, 1.5, [], false],
	"A_Vambraces": [ARMS_LO, 0.9, 0.75, 0.35, 0.85, 1.5, [], false],
	"A_Couters": [ARMS_LO, 0.9, 0.75, 0.35, 0.3, 0.5, [], false],
	"A_Gauntlets": [HANDS, 0.85, 0.7, 0.3, 1.0, 1.5, ["Hand"], false],
	"A_Cuisses": [LEGS_UP, 0.9, 0.75, 0.35, 0.7, 3.0, [], false],
	"A_Poleyns": [LEGS_LO, 0.9, 0.75, 0.35, 0.25, 0.5, [], false],
	"A_Greaves": [LEGS_LO, 0.9, 0.75, 0.35, 0.85, 2.5, [], false],
	"A_Sabatons": [FEET, 0.85, 0.7, 0.3, 1.0, 1.5, ["Foot"], false],
	"H_PaddedCoif": [HEAD, 0.35, 0.25, 0.3, 0.8, 0.6, [], true],
	"H_Skullcap": [HEAD, 0.8, 0.6, 0.3, 0.55, 1.5, [], true],
	"H_Kettle": [HEAD, 0.85, 0.7, 0.35, 0.7, 2.0, [], true],
	"H_Bascinet": [HEAD, 0.92, 0.8, 0.42, 0.8, 3.0, [], true],
	"H_Sallet": [HEAD, 0.92, 0.8, 0.42, 0.88, 3.0, [], true],
	"H_Barbute": [HEAD, 0.92, 0.8, 0.42, 0.9, 3.2, [], true],
	"X_Belt": [[], 0.0, 0.0, 0.0, 0.0, 0.3, [], false],
	"X_BeltOuter": [[], 0.0, 0.0, 0.0, 0.0, 0.3, [], false],
}

const HAIR := ["Hair_SimpleParted", "Hair_Buzzed", "Hair_Long", ""]

## Medieval dye palette: undyed, russet, madder, woad, weld, walnut, grey.
const DYES := [
	Color(0.62, 0.56, 0.45), Color(0.45, 0.28, 0.18), Color(0.52, 0.16, 0.12), Color(0.2, 0.26, 0.42),
	Color(0.55, 0.47, 0.2), Color(0.25, 0.19, 0.14), Color(0.36, 0.36, 0.34), Color(0.24, 0.31, 0.2),
	Color(0.14, 0.13, 0.13),
]
const HAIR_COLORS := [
	Color(0.07, 0.05, 0.04), Color(0.16, 0.1, 0.06), Color(0.3, 0.19, 0.1), Color(0.42, 0.26, 0.12),
	Color(0.55, 0.43, 0.26), Color(0.5, 0.48, 0.45), Color(0.24, 0.1, 0.05),
]

const FIRST := ["Hans", "Konrad", "Ulrich", "Jörg", "Matthis", "Jacques", "Guillaume", "Piero", "Jan", "Wojciech",
	"Tomas", "Aldo", "Bertram", "Eckhart", "Florian", "Gerhard", "Henrik", "Istvan", "Lorenz", "Martin", "Niklas",
	"Oswin", "Rupert", "Sebald", "Veit", "Wendel", "Anselm", "Diether", "Gunther", "Janek"]
const EPITHET := ["the Tanner", "of Ulm", "the Red", "Half-Ear", "the Miller's Son", "of the Ford", "Crookback",
	"the Pious", "Longarm", "the Ox", "of Brno", "Three-Fingers", "the Quiet", "Blackbeard", "the Carter",
	"of Nürnberg", "the Fowler", "Stonehand", "the Lame", "of Kraków", "the Smith", "Grimtooth", "the Younger"]

const RANK_NAMES := ["Vagrant", "Peasant", "Militiaman", "Soldier", "Veteran", "Man-at-Arms", "Knight"]


static func rank_name(rank: int) -> String:
	return RANK_NAMES[clampi(rank, 0, RANK_NAMES.size() - 1)]


## Rolls a complete opponent (or the player's starting kit) for [param rank].
static func roll_fighter(rank: int, rng: RandomNumberGenerator) -> Dictionary:
	var g: Array[String] = []
	var helm := ""
	var shield := false
	var weapon := "cudgel"
	var pick := func(arr: Array): return arr[rng.randi_range(0, arr.size() - 1)]
	rank = clampi(rank, 0, 6)
	match rank:
		0:
			g.append_array(["G_Shirt", "G_Hose"] if rng.randf() < 0.6 else ["G_Tunic", "G_Hose"])
			if rng.randf() < 0.6:
				g.append("G_Shoes")
			if rng.randf() < 0.3:
				helm = "H_PaddedCoif"
			weapon = pick.call(["cudgel", "cudgel", "rondel_dagger"])
		1:
			g.append_array(["G_Tunic", "G_Hose", "G_Shoes", "X_Belt"])
			if rng.randf() < 0.35:
				g.erase("G_Tunic")
				g.append("A_Gambeson")
			helm = pick.call(["", "H_PaddedCoif", "H_PaddedCoif", "H_Skullcap"])
			weapon = pick.call(["cudgel", "bearded_axe", "war_spear", "falchion", "rondel_dagger"])
			shield = weapon in ["falchion", "bearded_axe"] and rng.randf() < 0.25
		2:
			g.append_array(["A_Gambeson", "G_Hose", "G_Boots", "X_Belt"])
			if rng.randf() < 0.5:
				g.append("G_Gloves")
			helm = pick.call(["H_PaddedCoif", "H_Kettle", "H_Skullcap"])
			weapon = pick.call(["falchion", "bearded_axe", "war_spear", "arming_sword"])
			shield = weapon != "war_spear" and rng.randf() < 0.3
		3:
			g.append_array(["A_Gambeson", "A_Haubergeon", "G_Hose", "G_Boots", "G_Gloves", "X_BeltOuter"])
			helm = pick.call(["H_Kettle", "H_Skullcap", "H_Kettle"])
			if helm == "H_Skullcap" or rng.randf() < 0.4:
				g.append("A_MailCoif")
			weapon = pick.call(["arming_sword", "falchion", "flanged_mace", "war_spear", "bearded_axe"])
			shield = weapon in ["arming_sword", "flanged_mace"] and rng.randf() < 0.4
		4:
			g.append_array(["A_Gambeson", "A_Haubergeon", "A_Brigandine", "G_Hose", "G_Boots", "A_Vambraces",
				"A_Gauntlets", "X_BeltOuter"])
			if rng.randf() < 0.5:
				g.append_array(["A_Greaves", "A_Poleyns"])
			helm = pick.call(["H_Kettle", "H_Bascinet", "H_Sallet"])
			weapon = pick.call(["arming_sword", "flanged_mace", "longsword", "war_spear"])
			shield = weapon == "arming_sword" and rng.randf() < 0.4
		_:
			g.append_array(["A_Gambeson", "A_Haubergeon", "A_Cuirass", "G_Hose", "A_Rerebraces", "A_Pauldrons",
				"A_Vambraces", "A_Couters", "A_Gauntlets", "A_Cuisses", "A_Poleyns", "A_Greaves", "A_Sabatons"])
			helm = pick.call(["H_Sallet", "H_Bascinet", "H_Barbute"])
			weapon = pick.call(["longsword", "flanged_mace", "longsword", "arming_sword"])
			shield = weapon == "arming_sword"
	if helm != "":
		g.append(helm)

	var colors := {}
	colors["G_Wool"] = pick.call(DYES)
	colors["G_Wool2"] = pick.call(DYES)
	colors["G_Hose"] = pick.call(DYES)
	colors["G_Padded"] = (pick.call(DYES) as Color).lerp(Color(0.72, 0.66, 0.52), 0.55)
	colors["G_Velvet"] = pick.call([Color(0.42, 0.08, 0.07), Color(0.12, 0.16, 0.34), Color(0.1, 0.22, 0.12), Color(0.12, 0.1, 0.1)])
	colors["G_Linen"] = Color(0.8, 0.76, 0.66).lerp(Color(0.62, 0.55, 0.43), rng.randf())
	var hair: String = pick.call(HAIR)
	var skill := clampf(0.15 + rank * 0.14 + rng.randf_range(-0.08, 0.08), 0.05, 0.98)
	return {
		"name": "%s %s" % [pick.call(FIRST), pick.call(EPITHET)],
		"rank": rank,
		"garments": g,
		"weapon": weapon,
		"shield": shield,
		"hair": hair,
		"beard": rng.randf() < 0.6,
		"hair_color": pick.call(HAIR_COLORS),
		"skin": "dark" if rng.randf() < 0.3 else "light",
		"skin_tint": Color(1, 1, 1).lerp(Color(1.0, 0.86, 0.78), rng.randf() * 0.6),
		"colors": colors,
		"scale": rng.randf_range(0.95, 1.05),
		"ai": {
			"skill": skill,
			"aggression": rng.randf_range(0.35, 1.0),
			"spacing": rng.randf_range(0.8, 1.25),
			"cadence": rng.randf_range(0.8, 1.25),
			"infighting": rng.randf_range(0.0, 1.0),
		},
	}


## Player's opening kit: poor and lightly dressed, like everyone at the bottom.
static func starting_kit(rng: RandomNumberGenerator) -> Dictionary:
	var f := roll_fighter(1, rng)
	f["name"] = "You"
	f["garments"] = ["G_Tunic", "G_Hose", "G_Shoes", "X_Belt"]
	f["weapon"] = "falchion"
	f["shield"] = false
	f["hair"] = "Hair_SimpleParted"
	f["beard"] = true
	f["colors"]["G_Wool"] = Color(0.45, 0.28, 0.18)
	return f


## Upgrade path: the kit the player earns at [param rank] (a fixed, readable
## progression rather than random loot).
static func player_kit_for_rank(base: Dictionary, rank: int) -> Dictionary:
	var f := base.duplicate(true)
	var tiers := [
		["G_Tunic", "G_Hose", "G_Shoes", "X_Belt"],
		["G_Tunic", "G_Hose", "G_Shoes", "X_Belt", "H_PaddedCoif"],
		["A_Gambeson", "G_Hose", "G_Boots", "G_Gloves", "X_Belt", "H_Kettle"],
		["A_Gambeson", "A_Haubergeon", "G_Hose", "G_Boots", "G_Gloves", "X_BeltOuter", "H_Kettle", "A_MailCoif"],
		["A_Gambeson", "A_Haubergeon", "A_Brigandine", "G_Hose", "G_Boots", "A_Vambraces", "A_Gauntlets",
			"A_Greaves", "A_Poleyns", "X_BeltOuter", "H_Bascinet"],
		["A_Gambeson", "A_Haubergeon", "A_Cuirass", "G_Hose", "A_Rerebraces", "A_Pauldrons", "A_Vambraces",
			"A_Couters", "A_Gauntlets", "A_Cuisses", "A_Poleyns", "A_Greaves", "A_Sabatons", "H_Sallet"],
	]
	f["garments"] = tiers[clampi(rank, 0, tiers.size() - 1)]
	return f


## Total worn weight (kg): slows the fighter and steadies them against blows.
static func worn_weight(garments: Array) -> float:
	var w := 0.0
	for gname in garments:
		if LAYERS.has(gname):
			w += float(LAYERS[gname][5])
	return w


## Damage multiplier (0..1) that reaches flesh for a blow of [param kind]
## ("cut"/"pierce"/"blunt") landing on rig slot [param slot].
static func protection(garments: Array, slot: String, kind: String, rng: RandomNumberGenerator) -> Dictionary:
	var remaining := 1.0
	var struck := ""
	var idx: int = {"cut": 1, "pierce": 2, "blunt": 3}.get(kind, 1)
	var best := 0.0
	for gname in garments:
		var layer = LAYERS.get(gname)
		if layer == null or not slot in layer[0]:
			continue
		if rng.randf() > float(layer[4]):
			continue
		var p: float = layer[idx]
		remaining *= 1.0 - p
		if p > best:
			best = p
			struck = gname
	return {"remaining": remaining, "struck": struck, "hard": best >= 0.8}
