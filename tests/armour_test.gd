extends Node3D
## Armour as real equipment: world items, putting it on, swapping, knocked
## off, and the arena's bench.
##
##   xvfb-run -a godot --path . res://tests/armour_test.tscn

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
	cam.position = Vector3(1.6, 1.4, 1.8)
	cam.look_at(Vector3(0, 0.8, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 35, 0)
	add_child(light)
	await _run()
	for l in _log:
		print(l)
	print("ARMOUR_TEST ", "FAILED" if _fail else "OK")
	get_tree().quit(1 if _fail else 0)


func _fighter(pos: Vector3, garments: Array) -> KickbackActor:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var spec := Armory.roll_fighter(1, rng)
	spec["garments"] = garments
	spec["weapon"] = ""
	spec["shield"] = false
	spec["vitality"] = 20.0
	var a := KickbackActor.new()
	a.spec = spec
	a.carries_weapon = false
	a.position = pos
	add_child(a)
	return a


func _shows(a: KickbackActor, garment: String) -> bool:
	for m in a.model.find_children("*", "MeshInstance3D", true, false):
		if (m as MeshInstance3D).visible and String(m.name).get_slice("__", 0) == garment:
			return true
	return false


func _head_cut_through(a: KickbackActor) -> float:
	var rng := RandomNumberGenerator.new()
	var s := 0.0
	for i in 200:
		s += float(Armory.protection(a.spec["garments"], "Head", "cut", rng)["remaining"])
	return s / 200.0


func _run() -> void:
	var a := _fighter(Vector3.ZERO, ["G_Tunic", "G_Hose", "G_Shoes"])
	await get_tree().create_timer(1.5).timeout
	var kettle := ArmourItem.create("kettle")
	_check(kettle != null and kettle.find_children("*", "MeshInstance3D", true, false).size() > 0,
		"a kettle hat exists as a world object with its own meshes")
	add_child(kettle)
	kettle.global_position = Vector3(0.35, 0.8, 0.3)
	await get_tree().create_timer(2.0).timeout
	_check(kettle.global_position.y < 0.3, "it falls and rests on the ground (y %.2f)" % kettle.global_position.y)

	var cut0 := _head_cut_through(a)
	var w0 := a.worn_weight
	var m0: float = a.get_rig_bodies()["Chest"].mass
	var ok := a.equip_armour(kettle)
	await get_tree().create_timer(1.3).timeout
	_check(ok and "H_Kettle" in a.spec["garments"], "he puts it on")
	_check(_shows(a, "H_Kettle"), "the helmet is drawn on his head")
	_check(not is_instance_valid(kettle), "it is no longer lying in the world")
	_check(_head_cut_through(a) < cut0 * 0.6, "his head is now protected (cut through %.2f -> %.2f)" % [cut0, _head_cut_through(a)])
	_check(a.worn_weight > w0 and a.get_rig_bodies()["Chest"].mass > m0, "and he is heavier (%.1f -> %.1f kg)" % [w0, a.worn_weight])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/armour_on.png")

	# Swap: a bascinet replaces the kettle hat, which goes on the ground.
	var basc := ArmourItem.create("bascinet")
	add_child(basc)
	basc.global_position = a.global_position + Vector3(0.3, 0.2, 0.3)
	await get_tree().create_timer(0.5).timeout
	a.equip_armour(basc)
	await get_tree().create_timer(1.3).timeout
	var ground_kettle := get_tree().get_nodes_in_group(&"armour_items").filter(func(n): return n.item_id == "kettle")
	_check("H_Bascinet" in a.spec["garments"] and not "H_Kettle" in a.spec["garments"] and ground_kettle.size() == 1,
		"a bascinet replaces the kettle hat, which is set down")

	# Prerequisite: no mail straight over a tunic.
	var mail := ArmourItem.create("haubergeon")
	add_child(mail)
	mail.global_position = Vector3(2, 0.3, 0)
	_check(a.equip_block(mail) != "" and not a.equip_armour(mail), "mail cannot go on without a gambeson")

	# A crushing blow knocks a loose helmet off.
	var b := _fighter(Vector3(-2.5, 0, 0), ["G_Tunic", "G_Hose", "H_Kettle"])
	await get_tree().create_timer(1.5).timeout
	var mace := PhysicsWeapon.create("flanged_mace")
	add_child(mace)
	mace.global_position = Vector3(30, 1, 30)
	mace.freeze = true
	var head: RigidBody3D = b.get_rig_bodies()["Head"]
	var res := b.receive_weapon_hit({"rig_name": "Head", "dir": Vector3(1, 0, 0), "speed": 13.0, "kind": "blunt", "quality": 1.0,
		"part": "head", "weapon": mace, "attacker": null, "mass": mace.mass, "point": head.global_position + Vector3.UP * 0.1})
	await get_tree().create_timer(0.5).timeout
	# One kettle hat was already set down by the swap above; the knocked-off
	# one is the second, and it is flying.
	var kettles := get_tree().get_nodes_in_group(&"armour_items").filter(func(n): return n.item_id == "kettle")
	var moving := kettles.filter(func(n): return (n as RigidBody3D).linear_velocity.length() > 0.5)
	_check(not "H_Kettle" in b.spec["garments"] and kettles.size() == 2 and moving.size() == 1,
		"a crushing blow knocks the kettle hat off, and it flies (%d kettles, %d moving)" % [kettles.size(), moving.size()])

	# The arena lays out a bench of gear on the fighters' side.
	GameState.new_run()
	var arena: Node = load("res://scenes/arena.tscn").instantiate()
	for c in get_children():
		if c is KickbackActor or c is ArmourItem or c is PhysicsWeapon:
			c.queue_free()
	await get_tree().process_frame
	add_child(arena)
	await get_tree().create_timer(2.0).timeout
	var bench_items := get_tree().get_nodes_in_group(&"armour_items").filter(
		func(n): return n.global_position.distance_to(arena.BENCH_POS) < 1.6)
	_check(bench_items.size() >= 1, "the arena lays armour out on the bench (%d pieces)" % bench_items.size())
