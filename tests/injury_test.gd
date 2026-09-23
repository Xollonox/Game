extends Node3D
## Regional injuries and their consequences.
##
##   xvfb-run -a godot --path . res://tests/injury_test.tscn

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
	await _run()
	for l in _log:
		print(l)
	print("INJURY_TEST ", "FAILED" if _fail else "OK")
	get_tree().quit(1 if _fail else 0)


func _fighter(pos: Vector3, garments: Array, weapon := "arming_sword") -> KickbackActor:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var spec := Armory.roll_fighter(2, rng)
	spec["garments"] = garments
	spec["weapon"] = weapon
	spec["shield"] = false
	var a := KickbackActor.new()
	a.spec = spec
	a.carries_weapon = weapon != ""
	a.position = pos
	add_child(a)
	return a


func _hit(a: KickbackActor, w: PhysicsWeapon, rig: String, kind: String, speed: float, part := "edge") -> Dictionary:
	var body: RigidBody3D = a.get_rig_bodies()[rig]
	return a.receive_weapon_hit({"rig_name": rig, "dir": Vector3(0, 0, -1), "speed": speed, "kind": kind, "quality": 1.0,
		"part": part, "weapon": w, "attacker": null, "mass": w.mass, "point": body.global_position})


func _run() -> void:
	var sword := PhysicsWeapon.create("arming_sword")
	add_child(sword)
	sword.global_position = Vector3(30, 1, 30)
	sword.freeze = true
	var mace := PhysicsWeapon.create("flanged_mace")
	add_child(mace)
	mace.global_position = Vector3(31, 1, 30)
	mace.freeze = true

	var a := _fighter(Vector3(-3, 0, 0), ["G_Shirt", "G_Hose"])
	var b := _fighter(Vector3(0, 0, 0), ["G_Shirt", "G_Hose"])
	var c := _fighter(Vector3(3, 0, 0), ["A_Gambeson", "A_Haubergeon", "A_Cuirass", "A_Rerebraces", "A_Vambraces",
		"A_Gauntlets", "G_Hose", "H_Bascinet"])
	await get_tree().create_timer(1.5).timeout

	# Sword arm cut: the arm weakens, control drops, it bleeds, the man lives.
	var ctrl0: float = a.weapon.control
	_hit(a, sword, "LowerArm_R", "cut", 9.0)
	_hit(a, sword, "LowerArm_R", "cut", 9.0)
	var f := a.injuries.arm_function("r")
	_check(f < 0.7, "cut forearm loses function (%.2f)" % f)
	_check(a.weapon.control < ctrl0 - 0.15, "weapon control drops with the arm (%.2f -> %.2f)" % [ctrl0, a.weapon.control])
	_check(a.injuries.total_bleed() > 0.0, "the cut bleeds (%.2f/s)" % a.injuries.total_bleed())
	_check(a.health > 80.0, "an arm wound is not a death blow (health %.1f)" % a.health)
	var imp: float = a._controller._spring.impairment.get("LowerArm_R", 0.0)
	_check(imp > 0.2, "the forearm's springs are impaired (%.2f)" % imp)

	# The same cuts to the chest threaten life much more.
	_hit(b, sword, "Chest", "cut", 9.0)
	_hit(b, sword, "Chest", "cut", 9.0)
	_check(b.health < a.health - 5.0, "torso cuts cost far more health than arm cuts (%.1f vs %.1f)" % [b.health, a.health])

	# Legs: a cut thigh makes him limp and weakens his balance.
	_hit(a, sword, "UpperLeg_L", "cut", 10.0)
	_hit(a, sword, "UpperLeg_L", "cut", 10.0)
	_check(a.injury_speed < 0.85 and a.balance.leg_function < 0.8,
		"cut thigh: limp (speed x%.2f) and weaker balance (legs %.2f)" % [a.injury_speed, a.balance.leg_function])

	# Head: a mace blow concusses and can break the skull.
	var res := _hit(b, mace, "Head", "blunt", 8.0, "head")
	_check(b.injuries.stun > 0.0 or b.is_dead(), "a mace to the head concusses (stun %.2f)" % b.injuries.stun)

	# Armour: plate stops the edge but not the blow.
	var plate_cut := _hit(c, sword, "Chest", "cut", 10.0)
	var bare_cut := _hit(a, sword, "Spine", "cut", 10.0)
	_check(float(plate_cut["flesh"]) < float(bare_cut["flesh"]) * 0.3,
		"plate turns the edge (flesh %.1f vs bare %.1f)" % [plate_cut["flesh"], bare_cut["flesh"]])
	_check(float(plate_cut["trauma"]) > 0.0, "but the blow still lands through it (trauma %.1f)" % plate_cut["trauma"])
	var arm_plate := _hit(c, sword, "LowerArm_R", "cut", 10.0)
	_check(float(arm_plate["flesh"]) < 4.0, "vambraced forearm barely cut (%.1f)" % arm_plate["flesh"])

	# Bleeding over time: blood drains, wounds clot.
	var bleed0 := a.injuries.total_bleed()
	var blood0 := a.injuries.blood
	await get_tree().create_timer(3.0).timeout
	_check(a.injuries.blood < blood0 and a.injuries.total_bleed() < bleed0, "wounds bleed, then slowly clot")
