extends Node
## End-to-end run flow: win -> spoils -> next bout -> die -> Hollow -> clear it
## -> return to the living -> die in the Hollow -> run over. Drives the real
## scenes through their own choice handlers and asserts on GameState.
##
##   xvfb-run -a godot --path . res://tests/flow_test.tscn

var _log: Array[String] = []
var _fail := false


func _ready() -> void:
	# Survive scene changes: live on the root, not in the current scene.
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	_log.append(("PASS " if cond else "FAIL ") + what)
	if not cond:
		_fail = true


func _scene() -> Node:
	return get_tree().current_scene


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


## Waits until the current scene is a different instance than [param old].
func _changed(old: Node) -> void:
	var t := 0.0
	while is_instance_valid(old) and get_tree().current_scene == old and t < 30.0:
		await _wait(0.25)
		t += 0.25
	while get_tree().current_scene == null and t < 30.0:
		await _wait(0.25)
		t += 0.25
	await _wait(1.5)


func _load(path: String) -> void:
	get_tree().change_scene_to_file(path)
	await _wait(1.5)


func _run() -> void:
	await _wait(0.2)
	# Mercy: a yielded opponent wins the bout without a debt below.
	GameState.new_run()
	GameState.run["bout"] = 0
	await _load("res://scenes/arena.tscn")
	var a0 := _scene()
	a0._start_fight()
	await _wait(0.5)
	for e in a0._enemies:
		e.yield_fight()
	await _wait(3.5)
	_check(int(GameState.run["bout"]) == 1, "a yielded opponent wins the bout")
	_check((GameState.run.get("slain", []) as Array).is_empty(), "sparing him leaves no debt")
	GameState.new_run()
	GameState.run["bout"] = 2
	await _load("res://scenes/arena.tscn")
	var arena := _scene()
	arena._start_fight()
	await _wait(0.5)
	for e in arena._enemies:
		e._take_damage(999.0)
		e.last_attacker = arena.player
	await _wait(3.5)
	await _wait(1.8)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/flow_victory.png")
	_check(int(GameState.run["bout"]) == 3, "victory advances the bout (%d)" % int(GameState.run["bout"]))
	_check(int(GameState.run["renown"]) > 0, "victory awards renown")
	arena._on_choice("spoils", "bearded_axe")
	await _changed(arena)
	_check(GameState.run["player"]["weapon"] == "bearded_axe", "spoils change the player's weapon")
	arena = _scene()
	_check(arena.name == "Arena", "next bout loads")
	arena._start_fight()
	await _wait(0.5)
	arena.player._take_damage(999.0)
	await _wait(4.0)
	arena._on_choice("hollow", "")
	await _changed(arena)
	var hollow := _scene()
	_check(hollow.name == "Hollow", "death descends into the Hollow")
	_check(GameState.run["mode"] == "hollow", "run mode is hollow")
	_check(hollow._enemies.size() >= 2, "shades are waiting (%d)" % hollow._enemies.size())
	hollow._start_fight()
	await _wait(0.5)
	for e in hollow._enemies:
		e._take_damage(999.0)
	await _wait(4.0)
	hollow._on_choice("return", "")
	await _changed(hollow)
	_check(_scene().name == "Arena", "clearing the Hollow returns to the yard")
	_check(GameState.run["mode"] == "arena" and int(GameState.run["returns"]) == 1, "return is recorded")
	var a2 := _scene()
	a2._start_fight()
	await _wait(0.4)
	a2.player._take_damage(999.0)
	await _wait(4.0)
	a2._on_choice("hollow", "")
	await _changed(a2)
	var h2 := _scene()
	h2._start_fight()
	await _wait(0.4)
	h2.player._take_damage(999.0)
	await _wait(4.0)
	_check(GameState.run.get("over", false), "dying in the Hollow ends the run")
	_check(not GameState.has_run(), "no run to continue after that")
	for l in _log:
		print(l)
	print("FLOW_TEST ", "FAILED" if _fail else "OK")
	get_tree().quit(1 if _fail else 0)
