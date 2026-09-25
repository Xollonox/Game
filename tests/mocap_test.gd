extends Node3D
## The motion-captured moves: every clip loads and binds, each bare-handed
## strike and kick actually lands on a man, and the ultimate fills, fires and
## lands more than one blow of its combination.
##
##   xvfb-run -a godot --path . res://tests/mocap_test.tscn

var _fail := false
var _log: Array[String] = []

const CLIPS := ["MC_Jab", "MC_Cross", "MC_Hook", "MC_Uppercut", "MC_Body_Shot", "MC_Kick_Front", "MC_Kick_Front_L",
	"MC_Block_High", "MC_Block_High_L", "MC_Guard_Box", "MC_Ultimate_Combo"]


func _check(cond: bool, what: String) -> void:
	var line := ("PASS " if cond else "FAIL ") + what
	print(line)
	_log.append(line)
	if not cond:
		_fail = true


func _ready() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	cs.shape = box
	cs.position.y = -0.5
	ground.add_child(cs)
	add_child(ground)
	var cam := Camera3D.new()
	cam.position = Vector3(3, 1.6, 3)
	add_child(cam)
	cam.look_at(Vector3(0, 1, 0))
	await _run()
	for l in _log:
		print(l)
	print("MOCAP_TEST ", "FAILED" if _fail else "OK")
	get_tree().quit(1 if _fail else 0)


func _fighter(pos: Vector3, facing: Vector3) -> KickbackActor:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var spec := Armory.roll_fighter(2, rng)
	spec["garments"] = ["G_Shirt", "G_Hose"]
	spec["weapon"] = ""
	spec["shield"] = false
	var a := KickbackActor.new()
	a.spec = spec
	a.carries_weapon = false
	a.position = pos
	add_child(a)
	a.face_dir = facing
	a.look_at(a.global_position - facing, Vector3.UP)
	return a


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _clear() -> void:
	for c in get_children():
		if c is KickbackActor:
			c.queue_free()
	await _wait(0.2)


func _set_range(a: KickbackActor, b: KickbackActor, want: float) -> void:
	for i in 180:
		var to := b.global_position - a.global_position
		to.y = 0.0
		a.face_dir = to.normalized()
		var err := to.length() - want
		a.move_dir = to.normalized() * clampf(err * 2.0, -0.6, 0.6) if absf(err) > 0.05 else Vector3.ZERO
		await get_tree().physics_frame
		if absf(err) <= 0.05 and a.get_state_name() == "NORMAL" and not a.is_swinging():
			break
	a.move_dir = Vector3.ZERO
	await _wait(0.25)


func _run() -> void:
	# 1. The library: every clip is there, with fists closed.
	var a := _fighter(Vector3(0, 0, 0), Vector3(0, 0, 1))
	await _wait(1.0)
	var missing := CLIPS.filter(func(c): return not a.anim.has_animation(c))
	_check(missing.is_empty(), "all mocap clips load (missing %s)" % [missing])
	if not missing.is_empty():
		return
	var jab := a.anim.get_animation("MC_Jab")
	var fingers := 0
	for i in jab.get_track_count():
		if String(jab.track_get_path(i).get_concatenated_subnames()).begins_with("index_"):
			fingers += 1
	_check(fingers > 0, "mocap strikes close the fist (%d finger tracks)" % fingers)
	_check(a.anim.get_animation("MC_Guard_Box").loop_mode == Animation.LOOP_LINEAR, "the boxing guard loops")
	var m := AttackLibrary.pick("unarmed", "cut", 0, {"dir": "thrust"}, a.anim, RandomNumberGenerator.new())
	_check(m.get("anim", "") == "MC_Jab" and m.has("phases"), "a bare-handed jab is the mocap jab, with its measured timing (%s)" % [m])
	a.set_guard(true)
	await _wait(0.6)
	_check(a.anim.current_animation.begins_with("MC_Block"), "a bare-handed guard is a mocap block (%s)" % a.anim.current_animation)
	a.set_guard(false)
	await _clear()

	# 2. Each strike lands (a fresh man for each, so wounds do not stack).
	for spec in [["cut", "thrust", 0.62], ["cut", "right", 0.6], ["cut", "left", 0.55], ["cut", "high", 0.55],
			["cut", "low", 0.55], ["kick", "thrust", 0.85]]:
		var boxer := _fighter(Vector3(0, 0, -0.7), Vector3(0, 0, 1))
		var bag := _fighter(Vector3(0, 0, 0.1), Vector3(0, 0, -1))
		var landed := [0.0]
		bag.wounded.connect(func(_x, info): landed[0] += float(info["damage"]))
		await _wait(1.0)
		var used := ""
		for i in 8:
			await _set_range(boxer, bag, spec[2])
			boxer.attack(spec[0], {"dir": spec[1]})
			used = boxer._attack_anim
			await _wait(1.4)
			if landed[0] > 0.0:
				break
		_check(landed[0] >= 2.0, "%s (%s) lands (%.1f dmg)" % [used, spec[1], landed[0]])
		await _clear()

	# 3. Ultimate: needs a full meter, then lands several blows of its combo.
	var hero := _fighter(Vector3(0, 0, -0.7), Vector3(0, 0, 1))
	var foe := _fighter(Vector3(0, 0, 0.1), Vector3(0, 0, -1))
	foe.spec["vitality"] = 30.0
	await _wait(1.0)
	_check(not hero.attack("ultimate"), "no ultimate on an empty meter")
	var blows := [0]
	foe.wounded.connect(func(_x, _i): blows[0] += 1)
	# Each landed blow charges the meter; a handful fill it.
	var tries := 0
	while blows[0] < 3 and tries < 20:
		tries += 1
		await _set_range(hero, foe, 0.62)
		hero.attack("cut", {"dir": "thrust"})
		await _wait(1.2)
	var per_blow := hero.ultimate / maxf(blows[0], 1)
	_check(per_blow >= 0.11 and per_blow <= 0.23,
		"each landed blow charges the ultimate (%.3f per blow; full after %d)" % [per_blow, ceili(1.0 / maxf(per_blow, 0.01))])
	hero._set_ultimate(1.0)
	blows[0] = 0
	await _set_range(hero, foe, 0.6)
	var started := hero.attack("ultimate")
	var hp0 := foe.health
	# Pressing forward through the combination, as a player holds the stick.
	for i in 240:
		var to := foe.global_position - hero.global_position
		to.y = 0.0
		hero.face_dir = to.normalized()
		hero.move_dir = to.normalized() * (0.8 if to.length() > 0.6 else 0.0)
		await get_tree().physics_frame
	hero.move_dir = Vector3.ZERO
	_check(started and hero.ultimate == 0.0, "the ultimate fires and spends the meter")
	_check(blows[0] >= 2, "the combination lands more than one blow (%d blows, %.1f dmg)" % [blows[0], hp0 - foe.health])
	await _clear()
