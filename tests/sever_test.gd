extends Node3D
## Dismemberment: only a qualified cut severs; the limb detaches physically,
## no duplicate stays on the body, blood comes from the stump.
##
##   xvfb-run -a godot --path . res://tests/sever_test.tscn

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
	cam.position = Vector3(1.9, 1.5, 1.6)
	cam.look_at(Vector3(0, 0.9, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 35, 0)
	add_child(light)
	CombatFX.blood_enabled = true
	await _run()
	for l in _log:
		print(l)
	print("SEVER_TEST ", "FAILED" if _fail else "OK")
	get_tree().quit(1 if _fail else 0)


func _fighter(pos: Vector3, garments: Array) -> KickbackActor:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var spec := Armory.roll_fighter(2, rng)
	spec["garments"] = garments
	spec["weapon"] = "arming_sword"
	spec["shield"] = false
	spec["vitality"] = 30.0
	var a := KickbackActor.new()
	a.spec = spec
	a.carries_weapon = true
	a.position = pos
	add_child(a)
	return a


func _cut(a: KickbackActor, w: PhysicsWeapon, rig: String, speed: float, kind := "cut") -> Dictionary:
	var body: RigidBody3D = a.get_rig_bodies()[rig]
	return a.receive_weapon_hit({"rig_name": rig, "dir": Vector3(1, 0, 0.2).normalized(), "speed": speed, "kind": kind,
		"quality": 1.0, "part": "edge" if kind == "cut" else "head", "weapon": w, "attacker": null, "mass": w.mass,
		"point": body.global_position})


func _shown(a: KickbackActor, seg: String) -> int:
	var n := 0
	for m in a.model.find_children("*", "MeshInstance3D", true, false):
		if (m as MeshInstance3D).visible and String(m.get_meta(&"segment", "")) == seg:
			n += 1
	return n


func _run() -> void:
	var sword := PhysicsWeapon.create("longsword")
	add_child(sword)
	sword.global_position = Vector3(30, 1, 30)
	sword.freeze = true
	var mace := PhysicsWeapon.create("flanged_mace")
	add_child(mace)
	mace.global_position = Vector3(31, 1, 30)
	mace.freeze = true

	var a := _fighter(Vector3.ZERO, ["G_Shirt", "G_Hose", "G_Shoes"])
	var p := _fighter(Vector3(3, 0, 0), ["A_Gambeson", "A_Haubergeon", "A_Vambraces", "A_Gauntlets", "G_Hose"])
	var m := _fighter(Vector3(-3, 0, 0), ["G_Shirt", "G_Hose"])
	await get_tree().create_timer(1.5).timeout
	_check(_shown(a, "forearm_r") > 0, "the forearm is drawn from its own segment meshes (%d)" % _shown(a, "forearm_r"))

	# 1. An ordinary cut does not sever.
	var r1 := _cut(a, sword, "LowerArm_R", 7.0)
	_check(not r1.get("severed", false), "an ordinary cut does not sever")

	# 2. Repeated severe, well-aimed cuts to the exposed forearm can.
	var severed := false
	for i in 4:
		var r := _cut(a, sword, "LowerArm_R", 13.0)
		await get_tree().physics_frame
		if r.get("severed", false):
			severed = true
			break
	_check(severed, "a severe qualified cut through a badly cut forearm severs it")
	_check(_shown(a, "forearm_r") == 0 and _shown(a, "hand_r") == 0, "no forearm or hand remains visible on the body")
	var limb: DetachedLimb = null
	for c in get_children():
		if c is DetachedLimb:
			limb = c
	_check(limb != null and limb.find_children("*", "MeshInstance3D", true, false).size() > 0,
		"the severed forearm exists as a detached limb")
	_check(not is_instance_valid(a.weapon), "the sword falls from the severed hand")
	var fb: RigidBody3D = a.get_rig_bodies()["LowerArm_R"]
	_check(not fb.has_meta(&"kickback_actor") and fb.collision_layer == Dismemberment.DETACHED_LAYER,
		"the limb's bodies no longer belong to the fighter")
	var stump_src := false
	for c in a.get_rig_bodies()["UpperArm_R"].get_children():
		if c is BleedingSource and (c as BleedingSource).arterial:
			stump_src = true
	_check(stump_src, "arterial bleeding starts at the stump")
	var y0 := fb.global_position.y
	await get_tree().create_timer(2.5).timeout
	var cam: Camera3D = get_viewport().get_camera_3d()
	var stump: Vector3 = a.get_rig_bodies()["UpperArm_R"].global_position
	var mid := (stump + fb.global_position) * 0.5
	cam.global_position = mid + Vector3(0.9, 0.9, 1.4)
	cam.look_at(mid)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/sever.png")
	_check(fb.global_position.y < y0 - 0.3, "the limb falls physically (%.2f -> %.2f)" % [y0, fb.global_position.y])
	var skel: Skeleton3D = limb.get_node("Skeleton")
	var bi := skel.find_bone("lowerarm_r")
	var bone_world := skel.global_transform * skel.get_bone_global_pose(bi)
	_check(bone_world.origin.distance_to(fb.global_position) < 0.3, "its meshes follow the falling body")

	# 3. Plate-covered forearm: not casually severed.
	var plate_sev := false
	for i in 6:
		if _cut(p, sword, "LowerArm_R", 14.0).get("severed", false):
			plate_sev = true
	_check(not plate_sev, "a vambraced forearm cannot be casually severed")

	# 4. Blunt weapons do not sever.
	var blunt_sev := false
	for i in 6:
		if _cut(m, mace, "LowerArm_R", 12.0, "blunt").get("severed", false):
			blunt_sev = true
	_check(not blunt_sev, "a mace does not sever")
