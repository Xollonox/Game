class_name Shop
extends RefCounted
## The armourer's stock, the player's pack and what he wears.
##
## Armour is sold as the pieces a fifteenth-century buyer would actually ask
## for — a padded jack, a mail shirt, a brigandine, "a harness for the arms" —
## each filling one slot and mapping onto one or more wardrobe garments. A few
## pieces need the one beneath them: nobody wears mail or plate straight over a
## shirt. Weapons are the arsenal's own ids.
##
## Run state (in GameState.run):
##   purse: int                       coin
##   owned: Array[String]             item ids (armour and weapons), no dupes
##   equip: Dictionary slot -> id     armour worn; the weapon lives in run.player

const SLOTS := ["body", "mail", "plate", "head", "neck", "arms", "hands", "legs", "feet"]
const SLOT_NAMES := {"body": "Body", "mail": "Mail", "plate": "Plate", "head": "Head", "neck": "Neck",
	"arms": "Arms", "hands": "Hands", "legs": "Legs", "feet": "Feet", "weapon": "Weapon", "shield": "Shield"}

## id: [name, slot, garments, price, rank, needs (slot:id or ""), note]
const ARMOUR := {
	"shirt": ["Linen Shirt", "body", ["G_Shirt"], 0, 0, "", "What you were born to fight in."],
	"tunic": ["Wool Tunic", "body", ["G_Tunic"], 6, 0, "", "Warm, cheap, and it will turn a glancing cut."],
	"gambeson": ["Padded Gambeson", "body", ["A_Gambeson"], 24, 1, "",
		"Twenty layers of quilted linen. Soaks up blows; everything heavier is worn over it."],
	"haubergeon": ["Mail Haubergeon", "mail", ["A_Haubergeon"], 70, 2, "body:gambeson",
		"Riveted rings to the thigh. Edges skid off it; points and clubs still hurt."],
	"brigandine": ["Brigandine", "plate", ["A_Brigandine"], 95, 3, "body:gambeson",
		"Steel plates riveted inside a velvet coat. Covers the chest and back."],
	"cuirass": ["Steel Cuirass", "plate", ["A_Cuirass"], 170, 4, "body:gambeson",
		"Breast and back plate. A thrust must find the gaps."],
	"hood": ["Wool Hood", "head", ["G_Hood"], 3, 0, "", "Keeps the rain off. Little else."],
	"padded_coif": ["Arming Cap", "head", ["H_PaddedCoif"], 5, 0, "", "A quilted cap, worn alone or under a helm."],
	"skullcap": ["Steel Cap", "head", ["H_Skullcap"], 18, 1, "", "A simple bowl of iron."],
	"kettle": ["Kettle Hat", "head", ["H_Kettle"], 26, 2, "",
		"The foot-soldier's helm. The brim sheds blows aimed down at you."],
	"bascinet": ["Bascinet", "head", ["H_Bascinet"], 48, 3, "", "A close helm with a mail aventail for the neck."],
	"sallet": ["Sallet and Bevor", "head", ["H_Sallet"], 60, 4, "", "Swept tail behind, bevor before. Hard to find a way in."],
	"barbute": ["Barbute", "head", ["H_Barbute"], 62, 4, "", "An Italian helm, closed to a T-shaped opening."],
	"hounskull": ["Hounskull Bascinet", "head", ["H_Hounskull"], 85, 5, "", "The snouted visor of a knight. Blinkered, but blows glance off."],
	"mail_coif": ["Mail Coif", "neck", ["A_MailCoif"], 22, 2, "", "Rings over the head and throat."],
	"vambraces": ["Vambraces", "arms", ["A_Vambraces"], 30, 3, "", "Steel for the forearms, where most blows fall first."],
	"arm_harness": ["Arm Harness", "arms", ["A_Pauldrons", "A_Rerebraces", "A_Couters", "A_Vambraces"], 90, 4, "",
		"Plate from shoulder to wrist, articulated at the elbow."],
	"gloves": ["Leather Gloves", "hands", ["G_Gloves"], 5, 0, "", "Better than bare knuckles on a haft."],
	"gauntlets": ["Gauntlets", "hands", ["A_Gauntlets"], 34, 3, "", "Hands are always struck. These let you keep your fingers."],
	"greaves": ["Greaves and Poleyns", "legs", ["A_Greaves", "A_Poleyns"], 40, 3, "", "Shins and knees in steel."],
	"leg_harness": ["Leg Harness", "legs", ["A_Cuisses", "A_Poleyns", "A_Greaves"], 80, 4, "",
		"Thigh, knee and shin, all in plate."],
	"shoes": ["Turnshoes", "feet", ["G_Shoes"], 3, 0, "", "Soft leather. You feel the sand."],
	"boots": ["Riding Boots", "feet", ["G_Boots"], 10, 1, "", "Tall boots, good footing in mud."],
	"sabatons": ["Sabatons", "feet", ["A_Sabatons"], 30, 4, "", "Articulated steel shoes."],
}

## Weapons are gated by the rank a man would need to be trusted with one.
const WEAPON_RANK := {"cudgel": 0, "rondel_dagger": 0, "war_spear": 1, "bearded_axe": 1, "falchion": 1,
	"heater_shield": 1, "flanged_mace": 2, "arming_sword": 2, "longsword": 3}

const SELL_RATE := 0.5
const STARTING_PURSE := 12


static func is_weapon(id: String) -> bool:
	return WeaponCatalog.STATS.has(id)


static func item_name(id: String) -> String:
	if ARMOUR.has(id):
		return ARMOUR[id][0]
	return WeaponCatalog.display_name(id)


static func price(id: String) -> int:
	if ARMOUR.has(id):
		return int(ARMOUR[id][3])
	return int(WeaponCatalog.STATS.get(id, {}).get("price", 10))


static func sell_price(id: String) -> int:
	return int(floor(price(id) * SELL_RATE))


static func min_rank(id: String) -> int:
	if ARMOUR.has(id):
		return int(ARMOUR[id][4])
	return int(WEAPON_RANK.get(id, 0))


static func slot_of(id: String) -> String:
	if ARMOUR.has(id):
		return ARMOUR[id][1]
	return "shield" if id == "heater_shield" else "weapon"


static func note(id: String) -> String:
	if ARMOUR.has(id):
		return ARMOUR[id][6]
	return ""


static func weapon_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in WEAPON_RANK:
		out.append(id)
	out.sort_custom(func(a, b): return price(a) < price(b))
	return out


static func armour_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in ARMOUR:
		out.append(id)
	# Grouped by slot, cheapest first within a slot.
	out.sort_custom(func(a, b):
		var sa := SLOTS.find(ARMOUR[a][1])
		var sb := SLOTS.find(ARMOUR[b][1])
		return sa < sb if sa != sb else price(a) < price(b))
	return out


static func one_handed(weapon_id: String) -> bool:
	var d := WeaponCatalog.get_def(weapon_id)
	return int(d.get("hands", 1)) == 1 and String(d.get("class", "")) in ["sword", "axe", "mace", "club"]


# ------------------------------------------------------------ run state ----
static func ensure(run: Dictionary) -> void:
	if run.has("equip"):
		return
	# Older saves (and new runs) derive the pack from what the man is wearing.
	var p: Dictionary = run.get("player", {})
	var worn: Array = p.get("garments", [])
	var equip := {}
	var owned: Array = ["shirt"]
	for id: String in ARMOUR:
		var gs: Array = ARMOUR[id][2]
		var all := true
		for g in gs:
			if not g in worn:
				all = false
		if all and gs.size() > 0:
			var slot: String = ARMOUR[id][1]
			# Prefer the fuller piece when two match (arm harness over vambraces).
			if not equip.has(slot) or (ARMOUR[equip[slot]][2] as Array).size() < gs.size():
				equip[slot] = id
	for slot in equip:
		if not equip[slot] in owned:
			owned.append(equip[slot])
	if not equip.has("body"):
		equip["body"] = "shirt"
	var w: String = p.get("weapon", "")
	if w != "" and not w in owned:
		owned.append(w)
	if p.get("shield", false) and not "heater_shield" in owned:
		owned.append("heater_shield")
	run["equip"] = equip
	run["owned"] = owned
	if not run.has("purse"):
		# Coin for renown already won, so an old save is not left destitute.
		run["purse"] = STARTING_PURSE + int(run.get("renown", 0))


static func garments_for(run: Dictionary) -> Array[String]:
	ensure(run)
	var equip: Dictionary = run["equip"]
	var g: Array[String] = ["G_Hose"]
	for slot in SLOTS:
		var id: String = equip.get(slot, "")
		if id == "" or not ARMOUR.has(id):
			continue
		for gname in ARMOUR[id][2]:
			if not gname in g:
				g.append(gname)
	if equip.get("mail", "") != "" or equip.get("plate", "") != "":
		g.append("X_BeltOuter")
	elif equip.get("body", "shirt") != "shirt":
		g.append("X_Belt")
	return g


static func owns(run: Dictionary, id: String) -> bool:
	ensure(run)
	return id in (run["owned"] as Array)


static func is_equipped(run: Dictionary, id: String) -> bool:
	ensure(run)
	var p: Dictionary = run.get("player", {})
	if id == "heater_shield":
		return bool(p.get("shield", false))
	if is_weapon(id):
		return p.get("weapon", "") == id
	return (run["equip"] as Dictionary).get(slot_of(id), "") == id


## Why [param id] cannot be bought right now, or "" if it can.
static func buy_block(run: Dictionary, id: String, rank: int) -> String:
	if owns(run, id):
		return "Already yours"
	if min_rank(id) > rank:
		return "Sold only to a %s" % Armory.rank_name(min_rank(id)).to_lower()
	if int(run.get("purse", 0)) < price(id):
		return "You cannot afford it"
	return ""


## Why [param id] cannot be worn right now, or "".
static func equip_block(run: Dictionary, id: String) -> String:
	if not owns(run, id):
		return "Not yours"
	if ARMOUR.has(id):
		var need: String = ARMOUR[id][5]
		if need != "":
			var parts := need.split(":")
			if (run["equip"] as Dictionary).get(parts[0], "") != parts[1]:
				return "Must be worn over a %s" % item_name(parts[1]).to_lower()
	if id == "heater_shield":
		var w: String = (run.get("player", {}) as Dictionary).get("weapon", "")
		if not one_handed(w):
			return "Needs a one-handed sword, axe, mace or club"
	return ""


static func buy(run: Dictionary, id: String, rank: int) -> bool:
	if buy_block(run, id, rank) != "":
		return false
	run["purse"] = int(run.get("purse", 0)) - price(id)
	(run["owned"] as Array).append(id)
	# Armour is bought to be worn: put it on if nothing stands in the way.
	if not is_weapon(id) and equip_block(run, id) == "":
		equip(run, id)
	return true


static func sell(run: Dictionary, id: String) -> bool:
	if not owns(run, id) or id == "shirt":
		return false
	if is_equipped(run, id):
		if is_weapon(id) and id != "heater_shield":
			return false  # never leave yourself empty-handed
		unequip(run, id)
	(run["owned"] as Array).erase(id)
	run["purse"] = int(run.get("purse", 0)) + sell_price(id)
	return true


static func equip(run: Dictionary, id: String) -> bool:
	if equip_block(run, id) != "":
		return false
	var p: Dictionary = run.get("player", {})
	if id == "heater_shield":
		p["shield"] = true
	elif is_weapon(id):
		p["weapon"] = id
		if not one_handed(id):
			p["shield"] = false
	else:
		var slot := slot_of(id)
		(run["equip"] as Dictionary)[slot] = id
	run["player"] = p
	_settle(run)
	return true


static func unequip(run: Dictionary, id: String) -> void:
	var p: Dictionary = run.get("player", {})
	if id == "heater_shield":
		p["shield"] = false
	elif ARMOUR.has(id):
		var slot := slot_of(id)
		if slot == "body":
			(run["equip"] as Dictionary)["body"] = "shirt"
		else:
			(run["equip"] as Dictionary).erase(slot)
	_settle(run)


## Drops pieces whose foundation was taken off (plate without the padding).
static func _settle(run: Dictionary) -> void:
	var equip: Dictionary = run["equip"]
	for slot in equip.keys():
		var id: String = equip[slot]
		if ARMOUR.has(id) and ARMOUR[id][5] != "":
			var parts: PackedStringArray = String(ARMOUR[id][5]).split(":")
			if equip.get(parts[0], "") != parts[1]:
				equip.erase(slot)


## Spoils: the fallen's weapons go into the pack; a spare of something you
## already own is sold on the spot. Returns [taken ids, coin from spares].
static func loot(run: Dictionary, weapons: Array) -> Array:
	ensure(run)
	var taken: Array[String] = []
	var coin := 0
	for w in weapons:
		if w == "" or not is_weapon(w):
			continue
		if owns(run, w) or w in taken:
			coin += sell_price(w)
		else:
			(run["owned"] as Array).append(w)
			taken.append(w)
	run["purse"] = int(run.get("purse", 0)) + coin
	return [taken, coin]


## Coin paid for a won bout: the purse follows the renown, plus a little for
## each man you put down.
static func bout_purse(renown: int, foes: int) -> int:
	return int(round(renown * 1.2)) + 3 * foes


# ------------------------------------------------------------- summary -----
## Fraction of a [param kind] blow stopped on average over a body region.
static func region_protection(garments: Array, slots: Array, kind: String) -> float:
	var idx: int = {"cut": 1, "pierce": 2, "blunt": 3}.get(kind, 1)
	var total := 0.0
	for s in slots:
		var remaining := 1.0
		for gname in garments:
			var layer = Armory.LAYERS.get(gname)
			if layer == null or not s in layer[0]:
				continue
			remaining *= 1.0 - float(layer[idx]) * float(layer[4])
		total += 1.0 - remaining
	return total / maxf(slots.size(), 1)


const REGIONS := [["Head", ["Head"]], ["Body", ["Chest", "Spine", "Hips"]],
	["Arms", ["UpperArm_L", "LowerArm_L", "Hand_L"]], ["Legs", ["UpperLeg_L", "LowerLeg_L", "Foot_L"]]]
