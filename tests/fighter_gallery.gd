extends Node3D
## Visual review: a line-up of rolled fighters, one per rank, rendered in the
## real game renderer at close, medium and gameplay distances.
##
##   xvfb-run -a godot --path . res://tests/fighter_gallery.tscn -- --shots=/tmp/gallery [--seed=N] [--anim=Walk]

const FIGHTER := preload("res://scenes/dummy.tscn")

var _out := "/tmp/gallery"
var _fighters: Array = []
var _cam: Camera3D
var _anim := ""


func _ready() -> void:
	var seed := 7
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_out = a.substr(8)
		elif a.begins_with("--seed="):
			seed = int(a.substr(7))
		elif a.begins_with("--anim="):
			_anim = a.substr(7)
	DirAccess.make_dir_recursive_absolute(_out)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.3, 0.38, 0.5)
	sm.sky_horizon_color = Color(0.62, 0.58, 0.52)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_white = 6.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_energy = 1.4
	sun.light_color = Color(1, 0.92, 0.8)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	ground.add_child(cs)
	var gm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	gm.mesh = pm
	gm.material_override = WorldMaterials.get_material("M_Mud")
	ground.add_child(gm)
	add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in 6:
		var f: Enemy = FIGHTER.instantiate()
		f.spec = Armory.roll_fighter(i, rng)
		f.position = Vector3(-4.5 + i * 1.8, 0, 0)
		f.rotation.y = 0.0
		f.set_engage_delay(9999.0)
		add_child(f)
		_fighters.append(f)
		print("FIGHTER ", i, " ", f.spec["name"], " ", f.spec["weapon"], " ", f.spec["garments"])
	_cam = Camera3D.new()
	_cam.fov = 50
	add_child(_cam)
	_run()


func _run() -> void:
	await get_tree().create_timer(1.8).timeout
	if _anim != "":
		for f in _fighters:
			f.anim.play(_anim)
	await get_tree().create_timer(0.6).timeout
	for f in _fighters:
		var sk: Skeleton3D = f.skeleton
		var ip := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("index_01_r")).origin
		var pp := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("pinky_01_r")).origin
		var hb: RigidBody3D = f.get_rig_bodies()["Hand_R"]
		var hp := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hand_r"))
		print("DBG thumbdir ", (ip - pp).normalized(), " blade ", f.weapon.blade_axis() if f.weapon else Vector3.ZERO,
			" wpos ", f.weapon.global_position if f.weapon else Vector3.ZERO, " hb ", hb.global_position, " hbone ", hp.origin,
			" basisdot ", hb.global_basis.x.dot(hp.basis.x.normalized()), " ", hb.global_basis.y.dot(hp.basis.y.normalized()))
	await _shot(Vector3(0, 1.5, 7.5), Vector3(0, 0.95, 0), "lineup")
	for i in _fighters.size():
		var p: Vector3 = _fighters[i].global_position
		await _shot(p + Vector3(0.5, 1.75, 2.2), p + Vector3(0, 1.1, 0), "medium_%d" % i)
		await _shot(p + Vector3(0.25, 1.7, 0.85), p + Vector3(0, 1.58, 0), "close_%d" % i)
	await _shot(Vector3(2, 3.2, 9), Vector3(0, 0.9, 0), "gameplay")
	await get_tree().create_timer(0.2).timeout
	print("GALLERY_DONE")
	get_tree().quit()


func _shot(pos: Vector3, look: Vector3, label: String) -> void:
	_cam.global_position = pos
	_cam.look_at(look)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, label])
