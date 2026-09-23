extends Node
## Autoloaded player settings, persisted to `user://settings.cfg`.
##
## Kept deliberately small: the three mix levels, a quality switch (shadows +
## particle budget) and the blood toggle. The arena and the audio director read
## these, so a change made in the pause menu applies immediately and survives
## a reload — including on the web build, where Godot maps user:// onto
## IndexedDB.

signal settings_changed

const PATH := "user://settings.cfg"

var master := 0.85
var music := 0.55
var ambience := 0.75
var quality_high := true
var blood := true


func _ready() -> void:
	load_settings()
	load_run()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	master = cfg.get_value("audio", "master", master)
	music = cfg.get_value("audio", "music", music)
	ambience = cfg.get_value("audio", "ambience", ambience)
	quality_high = cfg.get_value("video", "quality_high", quality_high)
	blood = cfg.get_value("video", "blood", blood)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master)
	cfg.set_value("audio", "music", music)
	cfg.set_value("audio", "ambience", ambience)
	cfg.set_value("video", "quality_high", quality_high)
	cfg.set_value("video", "blood", blood)
	cfg.save(PATH)


func apply() -> void:
	settings_changed.emit()
	save_settings()


# ------------------------------------------------------------------ run -----
## The persistent run: who you are, how far you have climbed, what you carry,
## and whose blood is on your hands (the Hollow remembers). Saved to
## user://run.cfg after every bout so a closed tab resumes where it left off.

const RUN_PATH := "user://run.cfg"

var run: Dictionary = {}


func has_run() -> bool:
	return not run.is_empty() and not run.get("over", false)


func new_run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	run = {
		"seed": rng.randi(),
		"bout": 0,
		"renown": 0,
		"player": Armory.starting_kit(rng),
		"slain": [],
		"slain_total": 0,
		"hollow_debt": [],
		"returns": 0,
		"best_bout": 0,
		"over": false,
		"mode": "arena",
	}
	save_run()


func load_run() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(RUN_PATH) != OK:
		return
	var r = cfg.get_value("run", "data", {})
	if r is Dictionary:
		run = r


func save_run() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("run", "data", run)
	cfg.save(RUN_PATH)


func player_spec() -> Dictionary:
	var rank := Tournament.rank_for_bout(int(run.get("bout", 0)))
	var p: Dictionary = Armory.player_kit_for_rank(run.get("player", {}), rank)
	return p


## A bout was won: renown, record the fallen, advance.
func bout_won(renown_gain: int, fallen: Array) -> void:
	run["renown"] = int(run.get("renown", 0)) + renown_gain
	run["bout"] = int(run.get("bout", 0)) + 1
	run["best_bout"] = maxi(int(run.get("best_bout", 0)), int(run["bout"]))
	var slain: Array = run.get("slain", [])
	for s in fallen:
		slain.append(s)
	# The Hollow only keeps the most recent dead: a bounded, readable debt.
	while slain.size() > 8:
		slain.pop_front()
	run["slain"] = slain
	run["slain_total"] = int(run.get("slain_total", 0)) + fallen.size()
	save_run()


func set_weapon(weapon_id: String, shield: bool) -> void:
	var p: Dictionary = run.get("player", {})
	p["weapon"] = weapon_id
	p["shield"] = shield
	run["player"] = p
	save_run()


## Death in the arena: the dead you made wait below.
func enter_hollow() -> void:
	var slain: Array = run.get("slain", [])
	var debt := slain.slice(maxi(0, slain.size() - 5))
	if debt.size() < 2:
		# Even the innocent are met by something.
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		while debt.size() < 2:
			debt.append(Armory.roll_fighter(maxi(0, Tournament.rank_for_bout(int(run.get("bout", 0))) - 1), rng))
	run["hollow_debt"] = debt
	run["mode"] = "hollow"
	save_run()


## The debt is paid: back to the living, at a price in renown.
func return_from_hollow() -> void:
	run["mode"] = "arena"
	run["returns"] = int(run.get("returns", 0)) + 1
	run["renown"] = maxi(0, int(run.get("renown", 0)) - 15)
	run["slain"] = []
	run["hollow_debt"] = []
	save_run()


func end_run() -> void:
	run["over"] = true
	run["mode"] = "over"
	save_run()
