extends "res://scripts/arena.gd"
## The Hollow — this game's afterlife.
##
## Death in the yard is not the end of a run: you wake below in your burial
## shirt, holding the weapon you died with, and the men you killed come for
## you out of the fog — the same men, in the same kit, now grey and patient.
## Destroy them and the debt is paid: you climb back to the living and the
## run continues (at a cost in renown). Fall here and your name is forgotten:
## the run ends.
##
## Everything else — rig, weapons, wound model, camera, HUD — is the arena's,
## so the Hollow plays by the same physics; only the stakes and the world
## change.


func _make_encounter() -> Dictionary:
	var run := GameState.run
	var debt: Array = run.get("hollow_debt", [])
	var foes: Array = []
	var i := 0
	for spec0 in debt:
		var spec: Dictionary = (spec0 as Dictionary).duplicate(true)
		spec["shade"] = true
		spec["name"] = "Shade of " + String(spec.get("name", "a stranger")).get_slice(" ", 0)
		spec["skin_tint"] = Color(0.55, 0.6, 0.64)
		var ai: Dictionary = spec.get("ai", {})
		ai["skill"] = clampf(float(ai.get("skill", 0.4)) * 0.7, 0.1, 0.7)
		ai["aggression"] = 0.95
		ai["cadence"] = 1.25
		spec["ai"] = ai
		foes.append({"spec": spec, "team": 1, "entry": 0.6 + i * 2.2})
		i += 1
	return {
		"bout": int(run.get("bout", 0)),
		"header": "THE HOLLOW  ·  RETURNS %d" % int(run.get("returns", 0)),
		"title": "The Hollow",
		"blurb": "Those you sent below have been waiting. Lay them to rest, or join them.",
		"format": "duel",
		"foes": foes,
		"renown": 0,
		"pressers": 2,
	}


func _player_spec() -> Dictionary:
	var p: Dictionary = GameState.player_spec()
	# The dead are buried in their shirts.
	p["garments"] = ["G_Shirt", "G_Hose"]
	p["shield"] = false
	p["colors"]["G_Linen"] = Color(0.5, 0.5, 0.48)
	p["skin_tint"] = Color(0.82, 0.84, 0.86)
	return p


func _music() -> void:
	AudioDirector.hollow_ambience()


func _victory() -> void:
	phase = Phase.VICTORY
	await get_tree().create_timer(2.0).timeout
	hud.show_panel("THE DEBT IS PAID", UITheme.BRASS, [
		["The last of them sinks back into the mud. Somewhere above, a crowd is still shouting.", 20],
		["You may return — but the heralds will remember that you died. (-15 renown)", 16],
	], [["Climb Back to the Living", "return", "", true], ["Return to the Hall", "menu", ""]])


func _on_player_death() -> void:
	GameState.end_run()
	var run := GameState.run
	hud.show_panel("FORGOTTEN", Color(0.62, 0.72, 0.8), [
		["The Hollow keeps you. No herald will cry your name.", 20],
		["Reached bout %d · %d renown · %d slain" % [int(run.get("best_bout", 0)) + 1, int(run.get("renown", 0)),
			int(run.get("slain_total", 0))], 16],
	], [["Begin a New Life", "new_run", "", true], ["Return to the Hall", "menu", ""]])


func _on_choice(kind: String, value: String) -> void:
	if kind == "return":
		GameState.return_from_hollow()
		AudioDirector.restore_ambience()
		_next_scene("res://scenes/arena.tscn")
		return
	super._on_choice(kind, value)
