extends Node3D
## Active-ragdoll response to blows of rising force, and get-up quality.
##
##   xvfb-run -a godot --path . res://tests/balance_test.tscn
##
## weak blow   -> stays on his feet, the struck region is displaced
## medium blow -> off balance, takes physical recovery steps, returns to NORMAL
## huge blow   -> overpowers the rig (RAGDOLL), then gets up without snapping
## throughout  -> no body ever explodes (solver stability)

var _fail := false
var _log: Array[String] = []


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
	add_child(cam)
	cam.position = Vector3(3.5, 1.6, 3.5)
	cam.look_at(Vector3(0, 1, 0))
	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation_degrees = Vector3(-50, 30, 0)
	await _run()
	for l in _log:
		print(l)
	print("BALANCE_TEST ", "FAILED" if _fail else "OK")
	get_tree().quit(1 if _fail else 0)


func _fighter() -> KickbackActor:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var spec := Armory.roll_fighter(2, rng)
	spec["garments"] = ["A_Gambeson", "G_Hose", "G_Boots"]
	spec["weapon"] = ""
	spec["shield"] = false
	spec["vitality"] = 20.0  # he must survive the huge blow to show the get-up
	var a := KickbackActor.new()
	a.spec = spec
	a.carries_weapon = false
	add_child(a)
	return a


func _blow(a: KickbackActor, mace: PhysicsWeapon, speed: float, rig: String) -> void:
	var body: RigidBody3D = a.get_rig_bodies()[rig]
	a.receive_weapon_hit({"rig_name": rig, "dir": Vector3(0, 0, -1), "speed": speed, "kind": "blunt", "quality": 1.0,
		"part": "head", "weapon": mace, "attacker": null, "mass": mace.mass, "point": body.global_position})


## Watches the fighter for [param t] s: returns {states, max_speed, min_hips,
## chest_shift, max_getup_speed}.
func _watch(a: KickbackActor, t: float) -> Dictionary:
	var states := {}
	var max_speed := 0.0
	var max_getup := 0.0
	var max_limb := 0.0
	var chest0: Vector3 = a.get_rig_bodies()["Chest"].global_position
	var chest_shift := 0.0
	var root0 := a.global_position
	var steps := 0
	var was_step := false
	var n := int(t * 60.0)
	for i in n:
		await get_tree().physics_frame
		var st := a.get_state_name()
		states[st] = true
		states["bal:" + a.balance.state] = true
		var stepping: bool = a.kickback_character.get_active_controller()._foot_ik.is_stepping() \
			if a.kickback_character.get_active_controller()._foot_ik else false
		if stepping and not was_step:
			steps += 1
		was_step = stepping
		for b: RigidBody3D in a.get_rig_bodies().values():
			var v := b.linear_velocity.length()
			max_speed = maxf(max_speed, v)
			if st == "GETTING UP":
				if String(b.name) in ["Hips", "Spine", "Chest", "Head"]:
					max_getup = maxf(max_getup, v)
				else:
					max_limb = maxf(max_limb, v)
		chest_shift = maxf(chest_shift, (a.get_rig_bodies()["Chest"].global_position - chest0).length())
	return {"states": states.keys(), "max_speed": max_speed, "max_getup": max_getup, "max_limb": max_limb, "chest_shift": chest_shift,
		"steps": steps, "root_moved": a.global_position.distance_to(root0)}


func _run() -> void:
	var mace := PhysicsWeapon.create("flanged_mace")
	add_child(mace)
	mace.global_position = Vector3(20, 1, 20)
	mace.freeze = true

	var a := _fighter()
	await get_tree().create_timer(1.5).timeout
	var idle := await _watch(a, 2.0)
	_check("NORMAL" in idle["states"] and not "STAGGER" in idle["states"] and idle["max_speed"] < 3.0,
		"stands still without drifting or jitter (max body speed %.2f, %s)" % [idle["max_speed"], idle["states"]])

	_blow(a, mace, 1.6, "Chest")
	var weak := await _watch(a, 1.5)
	_check(not "RAGDOLL" in weak["states"] and weak["chest_shift"] > 0.01,
		"weak blow bends the body but he keeps his feet (chest moved %.3f m, %s)" % [weak["chest_shift"], weak["states"]])
	await get_tree().create_timer(1.0).timeout

	_blow(a, mace, 7.0, "Chest")
	var med := await _watch(a, 4.0)
	_check("STAGGER" in med["states"] and not "RAGDOLL" in med["states"],
		"solid blow puts him off balance without felling him (%s)" % [med["states"]])
	_check(med["steps"] >= 1, "he takes physical recovery steps (%d)" % med["steps"])
	_check(a.get_state_name() == "NORMAL", "and recovers his stance (%s)" % a.get_state_name())
	await get_tree().create_timer(1.0).timeout

	_blow(a, mace, 22.0, "Head")
	var huge := await _watch(a, 9.0)
	_check("RAGDOLL" in huge["states"], "a huge blow overpowers the rig (%s)" % [huge["states"]])
	_check("GETTING UP" in huge["states"] and a.get_state_name() == "NORMAL",
		"he gets back up (%s, now %s)" % [huge["states"], a.get_state_name()])
	# Torso speed is the snap measure (a whip into the clip pose shows there
	# first). Hands legitimately move fast as they plant and push off the
	# ground; a violent snap there reads well above 10 m/s.
	_check(huge["max_getup"] < 3.5 and huge["max_limb"] < 10.0,
		"get-up does not snap (torso peak %.2f m/s, limbs %.2f m/s while rising)" % [huge["max_getup"], huge["max_limb"]])
	_check(huge["max_speed"] < 25.0 and med["max_speed"] < 25.0, "no solver explosion (peak %.1f m/s)" % maxf(huge["max_speed"], med["max_speed"]))

	# Balance from the side: a blow from +X should move him toward -X... (dir -X)
	var side_dir := Vector3(-1, 0, 0)
	var c0: Vector3 = a.get_rig_bodies()["Chest"].global_position
	var body: RigidBody3D = a.get_rig_bodies()["Chest"]
	a.receive_weapon_hit({"rig_name": "Chest", "dir": side_dir, "speed": 5.0, "kind": "blunt", "quality": 1.0,
		"part": "head", "weapon": mace, "attacker": null, "mass": mace.mass, "point": body.global_position})
	for i in 20:
		await get_tree().physics_frame
	var moved: Vector3 = a.get_rig_bodies()["Chest"].global_position - c0
	_check(moved.x < -0.01, "a blow from the side pushes him sideways (moved %s)" % moved)

	# The dead stay down.
	var d := _fighter()
	await get_tree().create_timer(1.5).timeout
	d._take_damage(99999.0)
	var dead := await _watch(d, 6.0)
	_check(not "GETTING UP" in dead["states"] and d.get_state_name() == "PERSISTENT",
		"a dead man never gets back up (%s)" % [dead["states"]])
