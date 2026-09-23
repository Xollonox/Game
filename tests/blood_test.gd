extends Node3D
## Blood comes from the wound, follows the body, lands on surfaces, and obeys
## the Blood setting.
##
##   xvfb-run -a godot --path . res://tests/blood_test.tscn

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
	cam.position = Vector3(2.2, 1.4, 2.2)
	cam.look_at(Vector3(0, 0.8, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	add_child(light)
	await _run()
	for l in _log:
		print(l)
	print("BLOOD_TEST ", "FAILED" if _fail else "OK")
	get_tree().quit(1 if _fail else 0)


func _fighter(pos: Vector3) -> KickbackActor:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var spec := Armory.roll_fighter(1, rng)
	spec["garments"] = ["G_Shirt", "G_Hose"]
	spec["weapon"] = ""
	spec["shield"] = false
	spec["vitality"] = 10.0
	var a := KickbackActor.new()
	a.spec = spec
	a.carries_weapon = false
	a.position = pos
	add_child(a)
	return a


func _sources(a: KickbackActor) -> Array:
	var out := []
	for b: RigidBody3D in a.get_rig_bodies().values():
		for c in b.get_children():
			if c is BleedingSource:
				out.append(c)
	return out


func _visible_splats() -> int:
	var n := 0
	for c in CombatFX.get_children():
		if c is MeshInstance3D and c.visible:
			n += 1
	return n


func _run() -> void:
	var sword := PhysicsWeapon.create("arming_sword")
	add_child(sword)
	sword.global_position = Vector3(30, 1, 30)
	sword.freeze = true
	CombatFX.blood_enabled = true
	var a := _fighter(Vector3.ZERO)
	await get_tree().create_timer(1.5).timeout
	var arm: RigidBody3D = a.get_rig_bodies()["UpperLeg_L"]
	var point := arm.global_position + arm.global_basis.x * 0.07
	var splats0 := _visible_splats()
	a.receive_weapon_hit({"rig_name": "UpperLeg_L", "dir": Vector3(1, 0, 0), "speed": 10.0, "kind": "cut", "quality": 1.0,
		"part": "edge", "weapon": sword, "attacker": null, "mass": sword.mass, "point": point})
	var src := _sources(a)
	_check(src.size() == 1, "a cut leaves one bleeding source (%d)" % src.size())
	if src.is_empty():
		return
	var s: BleedingSource = src[0]
	_check(s.get_parent() == arm and s.global_position.distance_to(point) < 0.01,
		"it sits on the struck body at the contact point")
	_check(s.arterial, "a deep thigh cut bleeds arterially")
	var local := arm.to_local(s.global_position)
	await get_tree().create_timer(3.0).timeout
	_check(arm.to_local(s.global_position).distance_to(local) < 0.001, "it rides the body wherever it goes")
	_check(_visible_splats() > splats0, "blood lands on the floor (%d splats)" % (_visible_splats() - splats0))
	# The only surface here is the floor (his own body is excluded): every
	# mark must lie on it, flat.
	var ok_floor := true
	for c in CombatFX.get_children():
		if c is MeshInstance3D and c.visible:
			var up: Vector3 = (c as MeshInstance3D).global_basis.z.normalized()
			if absf(c.global_position.y) > 0.03 or up.dot(Vector3.UP) < 0.95:
				ok_floor = false
	_check(ok_floor, "every mark lies flat on the floor")
	var shot := get_viewport().get_texture().get_image()
	shot.save_png("/tmp/blood_wound.png")

	# Blood off: no sources, no splats; the wound still counts.
	CombatFX.blood_enabled = false
	var b := _fighter(Vector3(2.5, 0, 0))
	await get_tree().create_timer(1.5).timeout
	var h0 := b.health
	var splats1 := _visible_splats()
	b.receive_weapon_hit({"rig_name": "LowerArm_R", "dir": Vector3(1, 0, 0), "speed": 10.0, "kind": "cut", "quality": 1.0,
		"part": "edge", "weapon": sword, "attacker": null, "mass": sword.mass, "point": b.get_rig_bodies()["LowerArm_R"].global_position})
	await get_tree().create_timer(2.0).timeout
	_check(_sources(b).is_empty() and _visible_splats() <= splats1, "blood disabled: no emitters, no new marks")
	_check(b.health < h0 and b.injuries.total_bleed() >= 0.0 and b.injuries.function("forearm_r") < 1.0,
		"gameplay damage still applies with blood off")
	CombatFX.blood_enabled = true
