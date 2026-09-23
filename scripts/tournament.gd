class_name Tournament
extends RefCounted
## The ladder of bouts, from a vagrant's scrap in the mud to the lists.
##
## Escalation runs on three axes at once, the way a real tournament's would:
## the opponents' rank (skill and equipment), their number, and the shape of
## the fight — duels first, then two against one, then brawls where every man
## is for himself and the crowd gets the chaos it paid for, and finally a
## grand melee. Numbers climb slowly and only after the kit has had a chance to
## catch up, so 1v4 arrives when you are in mail, not in a shirt.
##
## format: "duel" (1vN, all against you), "melee" (free-for-all: every fighter
## on his own team, they will happily kill each other), "gauntlet" (1vN with
## the opponents released one after another).

const LADDER := [
	# rank 0 — vagrants
	{"title": "A Scrap in the Mud", "ranks": [0], "format": "duel",
		"blurb": "A beggar with a stick. The crowd has not bothered to gather."},
	{"title": "The Hungry Man", "ranks": [0], "format": "duel", "boost": 0.1,
		"blurb": "He has nothing to lose, and he knows it."},
	{"title": "Two Against One", "ranks": [0, 0], "format": "duel",
		"blurb": "The yardmaster wants to see if you can count."},
	# rank 1 — peasants
	{"title": "Broad Hands", "ranks": [1], "format": "duel",
		"blurb": "Broad hands, a borrowed weapon and a family to feed."},
	{"title": "Village Grudge", "ranks": [1, 0, 1], "format": "melee",
		"blurb": "Three men with old quarrels and you in the middle. Every man for himself."},
	{"title": "Brothers", "ranks": [1, 1], "format": "duel",
		"blurb": "They fight as one. Keep them in a line."},
	# rank 2 — militia
	{"title": "The Watchman", "ranks": [2], "format": "duel",
		"blurb": "Drilled on the town square, and paid to stand his ground."},
	{"title": "Levy Muster", "ranks": [1, 2, 1], "format": "gauntlet",
		"blurb": "They come through the gate one by one. Do not let them become three."},
	{"title": "Pike and Buckler", "ranks": [2, 2], "format": "duel",
		"blurb": "Two militiamen who have stood a line before."},
	# rank 3 — soldiers
	{"title": "A Soldier's Wage", "ranks": [3], "format": "duel",
		"blurb": "Mail under his coat and a campaign behind him."},
	{"title": "Free Company", "ranks": [2, 3, 2, 2], "format": "melee",
		"blurb": "Four sellswords, no contract, no friends. Let them bleed each other."},
	{"title": "The Sergeant's Test", "ranks": [3, 2, 3], "format": "duel",
		"blurb": "A sergeant and his two best. Three blades, one of you."},
	# rank 4 — veterans
	{"title": "The Veteran", "ranks": [4], "format": "duel",
		"blurb": "Good steel on his back and twenty years of killing behind it."},
	{"title": "Wolves at the Gate", "ranks": [3, 4, 3, 3], "format": "gauntlet",
		"blurb": "Four men released one after another. Keep your back to the stands."},
	# rank 5 — men-at-arms
	{"title": "Harness of Steel", "ranks": [5], "format": "duel",
		"blurb": "Full plate. Cuts will not do; find the gaps or break the man inside."},
	{"title": "The Brawl of Nations", "ranks": [4, 5, 4, 3, 4], "format": "melee",
		"blurb": "Five champions of five banners. The yard will run red."},
	# final
	{"title": "The Grand Melee", "ranks": [5, 4, 4, 6, 4, 5], "format": "duel",
		"blurb": "Six at once, and the knight among them has never been unhorsed. Win, and your name is sung."},
]


static func bout_count() -> int:
	return LADDER.size()


static func rank_for_bout(bout: int) -> int:
	var b := clampi(bout, 0, LADDER.size() - 1)
	var ranks: Array = LADDER[b]["ranks"]
	return clampi(ranks.min(), 0, 5)


## The player's standing, for UI: [rank name, bouts into it].
static func standing(bout: int) -> String:
	return Armory.rank_name(rank_for_bout(bout))


## Builds the concrete encounter for [param bout]: rolled opponents with
## specs, teams and staggered entry times.
static func encounter(bout: int, seed: int) -> Dictionary:
	var b := clampi(bout, 0, LADDER.size() - 1)
	var def: Dictionary = LADDER[b]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + bout * 7919
	var foes: Array = []
	var fmt: String = def["format"]
	var i := 0
	for r in def["ranks"]:
		var spec := Armory.roll_fighter(int(r), rng)
		if def.has("boost"):
			spec["ai"]["skill"] = clampf(spec["ai"]["skill"] + def["boost"], 0.0, 1.0)
			spec["ai"]["aggression"] = clampf(spec["ai"]["aggression"] + def["boost"], 0.0, 1.0)
		var entry := 0.8 + i * 0.9
		if fmt == "gauntlet":
			entry = 1.0 + i * 9.0
		foes.append({
			"spec": spec,
			"team": (2 + i) if fmt == "melee" else 1,
			"entry": entry,
		})
		i += 1
	var reward := 10 + 6 * int(def["ranks"].size()) + 5 * rank_for_bout(b)
	return {
		"bout": b,
		"title": def["title"],
		"blurb": def["blurb"],
		"format": fmt,
		"foes": foes,
		"renown": reward,
		"final": b == LADDER.size() - 1,
		# How many may press the player at once: grows with the bout, never
		# the whole pack.
		"pressers": 1 if foes.size() <= 2 else (2 if b < 12 else 3),
	}


static func format_label(fmt: String, n: int) -> String:
	match fmt:
		"melee":
			return "Free-for-all · %d fighters" % (n + 1)
		"gauntlet":
			return "Gauntlet · %d in turn" % n
	return "Single combat" if n == 1 else "One against %d" % n
