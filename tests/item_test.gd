extends Node3D
## Grip, disarm, drop and pickup: weapons as real world objects.
##
##   xvfb-run -a godot --path . res://tests/item_test.tscn

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
	cam.position = Vector3(2.5, 1.5, 2.5)
	cam.look_at(Vector3(0, 0.6, 0))
	await _run()
	for l in _log:
		print(l)
	print("ITEM_TEST ", "FAILED" if _fail else "OK")
	get_tree().quit(1 if _fail else 0)


func _fighter(pos: Vector3, weapon := "arming_sword", cls: GDScript = null) -> KickbackActor:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var spec := Armory.roll_fighter(2, rng)
	spec["garments"] = ["G_Tunic", "G_Hose", "G_Shoes"]
	spec["weapon"] = weapon
	spec["shield"] = false
	spec["vitality"] = 10.0
	var a: KickbackActor = cls.new() if cls else KickbackActor.new()
	a.spec = spec
	a.carries_weapon = true
	a.position = pos
	add_child(a)
	return a


func _cut(a: KickbackActor, w: PhysicsWeapon, rig: String, speed: float) -> void:
	var body: RigidBody3D = a.get_rig_bodies()[rig]
	a.receive_weapon_hit({"rig_name": rig, "dir": Vector3(1, 0, 0), "speed": speed, "kind": "cut", "quality": 1.0,
		"part": "edge", "weapon": w, "attacker": null, "mass": w.mass, "point": body.global_position})


func _run() -> void:
	var tool_sword := PhysicsWeapon.create("longsword")
	add_child(tool_sword)
	tool_sword.global_position = Vector3(30, 1, 30)
	tool_sword.freeze = true

	# 1. A cut-up sword arm can no longer hold the weapon.
	var a := _fighter(Vector3.ZERO)
	await get_tree().create_timer(1.5).timeout
	var w: PhysicsWeapon = a.weapon
	for i in 3:
		_cut(a, tool_sword, "LowerArm_R", 9.0)
		await get_tree().physics_frame
	_check(not is_instance_valid(a.weapon) and not w.is_held(), "a ruined sword arm drops the weapon")
	_check(w.is_in_group(&"world_items"), "the dropped weapon is a world item")
	await get_tree().create_timer(2.5).timeout
	_check(w.global_position.y < 0.35 and w.linear_velocity.length() < 0.5,
		"it falls and comes to rest on the ground (y %.2f, v %.2f)" % [w.global_position.y, w.linear_velocity.length()])

	# 2. The dropped blade lying against a man's feet does nothing.
	var b := _fighter(Vector3(w.global_position.x + 0.25, 0, w.global_position.z), "")
	await get_tree().create_timer(4.0).timeout
	_check(b.max_health - b.health == 0.0, "a dropped sword resting against a man does no damage (%.1f)" % (b.max_health - b.health))

	# 3. Pick it back up: the hand reaches, the weapon is drawn in, no pop.
	var c := _fighter(Vector3(w.global_position.x - 0.8, 0, w.global_position.z), "")
	# Actors face +Z; look_at aims -Z, so aim it away from the weapon.
	c.look_at(c.global_position - (Vector3(w.global_position.x, 0, w.global_position.z) - c.global_position), Vector3.UP)
	await get_tree().create_timer(1.2).timeout
	var started := c.pick_up(w)
	var max_jump := 0.0
	var prev := w.global_position
	var min_hand := 9.0
	var tick := Engine.get_physics_frames()
	for i in 200:
		await get_tree().physics_frame
		var ticks := Engine.get_physics_frames() - tick
		tick = Engine.get_physics_frames()
		var hb: RigidBody3D = c.get_rig_bodies().get("Hand_R")
		min_hand = minf(min_hand, hb.global_position.distance_to(w.grip_world() + Vector3.UP * 0.05))
		# Per physics tick (a slow software renderer can run several ticks
		# between two resumptions of this coroutine).
		var j := w.global_position.distance_to(prev) / maxf(ticks, 1)
		max_jump = maxf(max_jump, j)
		prev = w.global_position
	_check(started and w.is_held() and w.wielder == c and c.spec["weapon"] == w.weapon_id,
		"a fighter takes the same sword back up (held %s by %s, closest hand %.2f m, started %s)" % [w.is_held(), w.wielder, min_hand, started])
	# A teleport-pop is a >0.3 m jump in one tick; a hand rising fast with its
	# weapon moves ~0.1 m per tick (6 m/s).
	_check(max_jump < 0.15, "no teleport: the weapon never jumps (max %.3f m/tick)" % max_jump)

	# 4. Only a critical blow opens the hand: parries, a light cut on the
	# hand, a parry on a wounded hand and an ordinary knockdown all leave the
	# weapon held.
	var d := _fighter(Vector3(3, 0, 0), "arming_sword")
	var e := _fighter(Vector3(-3, 0, 0), "arming_sword")
	await get_tree().create_timer(1.5).timeout
	e.on_weapon_clash(tool_sword, 1.0)
	_check(is_instance_valid(e.weapon), "a sound grip survives the hardest parry")
	_cut(d, tool_sword, "Hand_R", 3.0)
	await get_tree().physics_frame
	_check(is_instance_valid(d.weapon), "a light cut on the hand does not disarm")
	if is_instance_valid(d.weapon):
		d.on_weapon_clash(tool_sword, 1.0)
	_check(is_instance_valid(d.weapon), "a parry on a wounded hand does not disarm either")
	if d.kickback_character:
		d.kickback_character.trigger_ragdoll()
	await get_tree().create_timer(0.3).timeout
	_check(is_instance_valid(d.weapon), "an ordinary fall keeps the weapon in hand")
	var g := _fighter(Vector3(6, 0, 3), "arming_sword")
	await get_tree().create_timer(1.5).timeout
	_cut(g, tool_sword, "LowerArm_R", 14.0)
	await get_tree().physics_frame
	_check(not is_instance_valid(g.weapon), "a critical blow on the sword arm tears the weapon loose")

	# 5. Death releases the weapon.
	var dw: PhysicsWeapon = e.weapon
	e._take_damage(1e6)
	await get_tree().physics_frame
	_check(dw and not dw.is_held() and dw.is_in_group(&"world_items"), "a dead man's weapon falls free")

	# 6. An opponent without a weapon goes and gets one, the same way.
	var loose := PhysicsWeapon.create("falchion")
	add_child(loose)
	loose.global_position = Vector3(0, 0.3, 4.0)
	loose.release()
	var f := _fighter(Vector3(0, 0, 7.5), "", Enemy)
	await get_tree().create_timer(0.5).timeout
	f.set_engage_delay(0.0)
	for i in 50:
		await get_tree().create_timer(0.2).timeout
		if loose.is_held():
			break
	_check(loose.is_held() and loose.wielder == f, "an unarmed opponent retrieves a loose weapon")
