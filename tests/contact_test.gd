extends Node3D
## Regression tests for "touching is not striking" (WeaponContactEvaluator)
## plus live physics scenarios with real fighters and real weapons.
##
##   xvfb-run -a godot --path . res://tests/contact_test.tscn
##   (headless also works: godot --headless --path . res://tests/contact_test.tscn)

var _fail := false
var _log: Array[String] = []


func _check(cond: bool, what: String) -> void:
	var line := ("PASS " if cond else "FAIL ") + what
	print(line)
	_log.append(line)
	if not cond:
		_fail = true


func _ready() -> void:
	PhysicsWeapon.debug_stats = true
	_unit_tests()
	await _live_tests()
	for l in _log:
		print(l)
	print("CONTACT_TEST ", "FAILED" if _fail else "OK")
	get_tree().quit(1 if _fail else 0)


# ------------------------------------------------------------------ unit ----
## Weapon frame used in the unit tests: blade pointing +Z world (so local −Z
## is world +Z... we build it explicitly): X = flat normal, Y = edge, point
## toward world +X.
func _frame() -> Basis:
	# Point toward +X: local −Z = +X  => local Z = −X. Edge along +Y.
	var z := Vector3(-1, 0, 0)
	var y := Vector3(0, 1, 0)
	return Basis(y.cross(z), y, z)


func _unit_tests() -> void:
	var sword := WeaponCatalog.get_def("arming_sword")
	var spear := WeaponCatalog.get_def("war_spear")
	var mace := WeaponCatalog.get_def("flanged_mace")
	var b := _frame()
	var n_side := Vector3(0, 1, 0)  # struck surface facing the edge
	var E := WeaponContactEvaluator

	var cut := E.evaluate(sword, "edge", b, Vector3(0, -9, 0), n_side, 1.15, "active")
	_check(cut["valid"] and cut["kind"] == "cut", "fast edge-aligned cut is a cut (%s)" % cut["reason"])
	var flat := E.evaluate(sword, "edge", b, b.x.normalized() * 9.0, b.x.normalized(), 1.15, "active")
	_check(flat["kind"] == "blunt", "flat of the blade is blunt, not a cut")
	var flat_dmg := float(flat["speed"]) * float(flat["quality"]) if flat["valid"] else 0.0
	_check(flat_dmg < float(cut["speed"]) * float(cut["quality"]) * 0.35,
		"flat hit carries far less than an edge cut (%.2f vs %.2f)" % [flat_dmg, float(cut["speed"]) * float(cut["quality"])])
	var rest := E.evaluate(sword, "edge", b, Vector3(0, -0.05, 0.02), n_side, 1.15, "none")
	_check(not rest["valid"], "resting blade does nothing (%s)" % rest["reason"])
	var scrape := E.evaluate(sword, "edge", b, Vector3(1.2, 0, 0), n_side, 1.15, "active")
	_check(not scrape["valid"], "slow scrape along the blade does nothing (%s)" % scrape["reason"])
	var idle_fast := E.evaluate(sword, "edge", b, Vector3(0, -5, 0), n_side, 1.15, "recovery")
	_check(not idle_fast["valid"], "blade moving in recovery does not cut (%s)" % idle_fast["reason"])
	var guard := E.evaluate(sword, "edge", b, Vector3(0, -4, 0), n_side, 1.15, "none")
	_check(not guard["valid"], "held blade with no attack behind it does not cut (%s)" % guard["reason"])
	var wild := E.evaluate(WeaponCatalog.get_def("bearded_axe"), "edge", b, Vector3(0, -10, 0), n_side, 1.35, "none")
	_check(wild["valid"] and wild["kind"] == "cut", "a loose axe arriving edge-first at 10 m/s still cuts")
	var windup := E.evaluate(sword, "edge", b, Vector3(0, -7, 0), n_side, 1.15, "prep")
	_check(not windup["valid"], "wind-up contact does not cut")

	var thrust := E.evaluate(spear, "point", b, Vector3(6, 0, 0), Vector3(-1, 0, 0), 2.1, "active")
	_check(thrust["valid"] and thrust["kind"] == "pierce", "aligned spear thrust pierces (%s)" % thrust["reason"])
	var side_tip := E.evaluate(spear, "point", b, Vector3(0.4, 0, 3.5), Vector3(0, 0, -1), 2.1, "active")
	_check(side_tip["kind"] != "pierce", "sideways spear-tip contact does not pierce")
	var press := E.evaluate(spear, "point", b, Vector3(0.6, 0, 0), Vector3(-1, 0, 0), 2.1, "active")
	_check(not press["valid"], "spear point pressed gently does nothing (%s)" % press["reason"])
	var dagger_touch := E.evaluate(WeaponCatalog.get_def("rondel_dagger"), "point", b, Vector3(1.0, 0, 0),
		Vector3(-1, 0, 0), 0.38, "active")
	_check(not dagger_touch["valid"], "dagger tip touching does nothing")

	var blow := E.evaluate(mace, "head", b, Vector3(0, -7, 0), Vector3(0, 1, 0), 1.55, "active")
	_check(blow["valid"] and blow["kind"] == "blunt", "mace head impact is blunt trauma")
	var slide := E.evaluate(mace, "head", b, Vector3(6, -0.4, 0), Vector3(0, 1, 0), 1.55, "active")
	_check(not slide["valid"], "mace head sliding along a surface is not a blow (%s)" % slide["reason"])
	var haft := E.evaluate(mace, "haft", b, Vector3(0, -7, 0), Vector3(0, 1, 0), 1.55, "active")
	_check(not haft["valid"] or float(haft["speed"]) < float(blow["speed"]) * 0.5, "haft knocks far less than the head")

	var logc := WeaponContactEvaluator.ContactLog.new()
	_check(logc.touch(7, 0.0), "first contact is an impact")
	var sustained := false
	for i in 300:
		sustained = sustained or logc.touch(7, 0.016 * (i + 1))
	_check(not sustained, "five seconds of sustained contact is never a new impact")
	_check(logc.touch(7, 4.8 + 0.3), "a new contact after separation is an impact")
	logc.mark_swing(7, 3)
	_check(logc.already_hit_this_swing(7, 3) and not logc.already_hit_this_swing(7, 4), "one blow per man per swing")


# ------------------------------------------------------------------ live ----
func _ground() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)


func _fighter(pos: Vector3, facing: Vector3, garments: Array, weapon: String) -> KickbackActor:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var spec := Armory.roll_fighter(2, rng)
	spec["garments"] = garments
	spec["weapon"] = weapon
	spec["shield"] = false
	var a := KickbackActor.new()
	a.spec = spec
	a.carries_weapon = weapon != ""
	a.position = pos
	add_child(a)
	a.face_dir = facing
	a.look_at(a.global_position - facing, Vector3.UP)
	return a


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _clear() -> void:
	for c in get_children():
		if c is KickbackActor or c is PhysicsWeapon:
			c.queue_free()
	await _wait(0.2)


func _damage(a: KickbackActor) -> float:
	return a.max_health - a.health


func _live_tests() -> void:
	_ground()
	var cam := Camera3D.new()
	cam.position = Vector3(3, 1.6, 3)
	add_child(cam)
	cam.look_at(Vector3(0, 1, 0))

	# 1. A free weapon laid across a man's shoulder and left there.
	var t1 := _fighter(Vector3.ZERO, Vector3(0, 0, 1), ["G_Shirt", "G_Hose"], "")
	await _wait(1.0)
	var w := PhysicsWeapon.create("arming_sword")
	add_child(w)
	var chest := t1.get_chest_position()
	w.global_transform = Transform3D(Basis(Vector3.UP, 0.3), chest + Vector3(0, 0.35, 0))
	await _wait(5.0)
	_check(_damage(t1) == 0.0, "sword resting on a man for 5 s: zero damage (%.1f)" % _damage(t1))
	await _clear()

	# 2. Two unarmed men walking into each other.
	var a := _fighter(Vector3(0, 0, -0.9), Vector3(0, 0, 1), ["G_Tunic", "G_Hose"], "")
	var b := _fighter(Vector3(0, 0, 0.9), Vector3(0, 0, -1), ["G_Tunic", "G_Hose"], "")
	await _wait(1.0)
	a.move_dir = Vector3(0, 0, 1)
	b.move_dir = Vector3(0, 0, -1)
	await _wait(3.0)
	_check(_damage(a) == 0.0 and _damage(b) == 0.0, "bodies colliding: zero damage")
	await _clear()

	# 3. A man walks into a sword held still (no attack), and 4. the holder's
	# blade jitters against him.
	var holder := _fighter(Vector3(0, 0, -1.05), Vector3(0, 0, 1), ["G_Tunic", "G_Hose"], "arming_sword")
	var walker := _fighter(Vector3(0, 0, 1.2), Vector3(0, 0, -1), ["G_Shirt", "G_Hose"], "")
	await _wait(1.0)
	walker.move_dir = Vector3(0, 0, -1)
	await _wait(2.5)
	walker.move_dir = Vector3.ZERO
	_check(_damage(walker) == 0.0, "walking into a still-held sword: zero cutting damage (%.1f)" % _damage(walker))
	var jitter_rng := RandomNumberGenerator.new()
	for i in 90:
		if is_instance_valid(holder.weapon):
			holder.weapon.apply_central_impulse(Vector3(jitter_rng.randf_range(-1, 1), jitter_rng.randf_range(-1, 1),
				jitter_rng.randf_range(-1, 1)) * 0.25)
		await get_tree().physics_frame
	_check(_damage(walker) == 0.0, "held weapon jittering against a man: zero damage (%.1f)" % _damage(walker))
	await _clear()

	# 5. Real attacks from a real fighter DO wound.
	var att := _fighter(Vector3(0, 0, -1.25), Vector3(0, 0, 1), ["G_Tunic", "G_Hose"], "arming_sword")
	var vic := _fighter(Vector3(0, 0, 0.1), Vector3(0, 0, -1), ["G_Shirt", "G_Hose"], "")
	var kinds: Array[String] = []
	vic.wounded.connect(func(_x, info): kinds.append(String(info["kind"])))
	await _wait(1.0)
	for i in 10:
		att.attack("cut")
		await _wait(1.3)
		if "cut" in kinds:
			break
	_check(_damage(vic) > 0.0 and "cut" in kinds, "a real swing cuts (%s, %.1f dmg)" % [kinds, _damage(vic)])
	await _clear()

	# 6. Armour: the same qualified cut on plate vs on a bare arm.
	var bare := _fighter(Vector3(-2, 0, 0), Vector3(0, 0, 1), ["G_Shirt", "G_Hose"], "")
	var plate := _fighter(Vector3(2, 0, 0), Vector3(0, 0, 1), ["A_Gambeson", "A_Haubergeon", "A_Cuirass", "A_Rerebraces",
		"A_Vambraces", "G_Hose"], "")
	await _wait(1.0)
	var sw := PhysicsWeapon.create("arming_sword")
	add_child(sw)
	var info := {"rig_name": "LowerArm_R", "dir": Vector3(0, 0, -1), "speed": 11.0, "kind": "cut", "quality": 1.0,
		"part": "edge", "weapon": sw, "attacker": null, "mass": 1.15}
	var sum_bare := 0.0
	var sum_plate := 0.0
	for i in 6:
		info["point"] = bare.get_chest_position()
		sum_bare += float(bare.receive_weapon_hit(info).get("damage", 0.0))
		info["point"] = plate.get_chest_position()
		sum_plate += float(plate.receive_weapon_hit(info).get("damage", 0.0))
	_check(sum_plate < sum_bare * 0.35, "cut into plate is strongly reduced (%.1f vs bare %.1f)" % [sum_plate, sum_bare])
	await _clear()
