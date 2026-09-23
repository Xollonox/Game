class_name WeaponCatalog
extends RefCounted
## The arsenal: physical data measured by the Blender generator
## (`tools/blender/build_weapons.py` writes `<id>.json` next to each GLB) plus
## the gameplay tuning that cannot be measured — how a weapon wounds, how fast it
## can be brought round, which attack set its wielder draws from.
##
## Mass, centre of mass, reach and collision boxes always come from the JSON, so
## re-shaping a blade in Blender re-balances it in game with no code change.

const DIR := "res://assets/models/weapons/arsenal/"

## cut/pierce/blunt: how well each damage channel is delivered (0..1+).
## stagger: multiplier on the knock the target's rig receives.
## handling: attack-speed multiplier (lighter, shorter weapons recover faster).
## tier: rough equipment rank, 0 = improvised / cheap, 3 = knightly.
## attacks: which attack family the wielder's move set draws from.
const STATS := {
	"cudgel": {"tier": 0, "cut": 0.0, "pierce": 0.0, "blunt": 0.8, "stagger": 1.15, "handling": 1.05,
		"attacks": "blunt", "price": 4},
	"rondel_dagger": {"tier": 0, "cut": 0.35, "pierce": 1.2, "blunt": 0.1, "stagger": 0.55, "handling": 1.35,
		"attacks": "dagger", "price": 8},
	"bearded_axe": {"tier": 1, "cut": 1.2, "pierce": 0.1, "blunt": 0.45, "stagger": 1.2, "handling": 0.92,
		"attacks": "blunt", "price": 14},
	"falchion": {"tier": 1, "cut": 1.15, "pierce": 0.45, "blunt": 0.25, "stagger": 1.0, "handling": 1.0,
		"attacks": "sword", "price": 18},
	"arming_sword": {"tier": 2, "cut": 1.0, "pierce": 0.9, "blunt": 0.2, "stagger": 0.9, "handling": 1.08,
		"attacks": "sword", "price": 30},
	"flanged_mace": {"tier": 2, "cut": 0.0, "pierce": 0.0, "blunt": 1.3, "stagger": 1.35, "handling": 0.95,
		"attacks": "blunt", "price": 26},
	"war_spear": {"tier": 1, "cut": 0.3, "pierce": 1.25, "blunt": 0.25, "stagger": 1.05, "handling": 0.9,
		"attacks": "spear", "price": 12},
	"longsword": {"tier": 3, "cut": 1.15, "pierce": 1.05, "blunt": 0.3, "stagger": 1.05, "handling": 0.96,
		"attacks": "longsword", "price": 45},
	"heater_shield": {"tier": 1, "cut": 0.0, "pierce": 0.0, "blunt": 0.5, "stagger": 1.3, "handling": 1.0,
		"attacks": "shield", "price": 16},
}

static var _cache: Dictionary = {}


## Full definition for [param id]: STATS merged with the measured JSON.
static func get_def(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var def: Dictionary = STATS.get(id, {}).duplicate(true)
	var path := DIR + id + ".json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			def.merge(parsed, true)
	def["id"] = id
	_cache[id] = def
	return def


static func mesh_scene(id: String) -> PackedScene:
	var p := DIR + id + ".glb"
	return load(p) if ResourceLoader.exists(p) else null


static func v3(a) -> Vector3:
	if a is Array and a.size() == 3:
		return Vector3(a[0], a[1], a[2])
	return Vector3.ZERO


static func ids_up_to_tier(tier: int, include_shield := false) -> Array[String]:
	var out: Array[String] = []
	for id: String in STATS:
		if id == "heater_shield" and not include_shield:
			continue
		if int(STATS[id]["tier"]) <= tier:
			out.append(id)
	return out


static func display_name(id: String) -> String:
	return String(get_def(id).get("name", id.capitalize()))
