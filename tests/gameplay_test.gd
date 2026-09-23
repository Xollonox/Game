extends Node
## Autonomous bout: a bot plays the player through a real encounter of the run
## ladder. Optional screenshots for visual review.
##
##   xvfb-run -a godot --path . res://tests/gameplay_test.tscn -- [--bout=N] [--shots=/tmp/g] [--limit=40]

const ARENA := preload("res://scenes/arena.tscn")
const ENGAGE_RANGE := 1.15
const STRIKE_RANGE := 1.45
var arena
var t := 0.0
var attack_cd := 0.0
var retreat := 0.0
var retreat_delay := 0.0
var hits := 0
var kills := 0
var limit := 40.0
var shots := ""
var _shot_t := 0.0
var _shot_i := 0
var _started := false
var _foes := 0
var _done := false


func _ready() -> void:
	var bout := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bout="):
			bout = int(a.substr(7))
		elif a.begins_with("--shots="):
			shots = a.substr(8)
			DirAccess.make_dir_recursive_absolute(shots)
		elif a.begins_with("--limit="):
			limit = float(a.substr(8))
	Enemy.debug_log = true
	PhysicsWeapon.debug_stats = true
	GameState.new_run()
	GameState.run["bout"] = bout
	var scene := ARENA
	if "--hollow" in OS.get_cmdline_user_args():
		var rng := RandomNumberGenerator.new()
		GameState.run["slain"] = [Armory.roll_fighter(1, rng), Armory.roll_fighter(2, rng), Armory.roll_fighter(0, rng)]
		GameState.enter_hollow()
		scene = load("res://scenes/hollow.tscn")
	arena = scene.instantiate()
	add_child(arena)
	arena.player.landed_hit.connect(func(_a, _b): hits += 1)


func _physics_process(delta: float) -> void:
	t += delta
	attack_cd -= delta
	retreat -= delta
	if retreat_delay > 0.0:
		retreat_delay -= delta
		if retreat_delay <= 0.0:
			retreat = 0.4
	if not _started:
		if t > 2.5:
			await _snap("intro")
			arena._start_fight()
			_started = true
			for e in arena._enemies:
				e.died.connect(func(_a): kills += 1)
				e.wounded.connect(func(a, info): print("WOUND %s dmg=%.1f v=%.1f part=%s kind=%s at=%s struck=%s prof=%s" % [a.spec["name"], info["damage"], info["speed"], info["part"], info["kind"], info["rig_name"], info["struck"], info["profile"]]))
			arena.player.wounded.connect(func(a, info): print("PWOUND v=%.1f dmg=%.1f kind=%s at=%s prof=%s" % [info["speed"], info["damage"], info["kind"], info["rig_name"], info["profile"]]))
			_foes = arena._enemies.size()
		return
	_shot_t += delta
	if shots != "" and _shot_t > 2.5:
		_shot_t = 0.0
		_snap("fight_%02d" % _shot_i)
		_shot_i += 1
	var p: KickbackActor = arena.player
	if int(t * 2) != int((t - delta) * 2):
		var lt = p.lock_target
		print("DBG p=%s face=%s cam=%s lock=%s" % [p.global_position, p.global_basis.z, arena.camera.global_position, lt.global_position if lt else null])
	if _done:
		return
	if p.is_dead() or kills >= _foes or t >= limit:
		_release_all()
		_done = true
		print("VERDICTS ", PhysicsWeapon.verdict_stats)
		print("GAMEPLAY_SUMMARY reason=%s hits=%d kills=%d/%d player_health=%d t=%.1f" % [
			"cleared" if kills >= _foes else ("player_died" if p.is_dead() else "timeout"),
			hits, kills, _foes, roundi(p.health), t])
		if shots != "":
			await get_tree().create_timer(2.5).timeout
			_snap("outcome")
		get_tree().quit()
		return
	var target: Enemy
	var best := INF
	for n in arena._enemies:
		if not n.is_dead():
			var d = p.global_position.distance_to(n.global_position)
			if d < best:
				best = d
				target = n
	if not target:
		_release_move()
		return
	var d3 := target.global_position - p.global_position
	d3.y = 0
	var desired := -d3.normalized() if retreat > 0 else (d3.normalized() if best > ENGAGE_RANGE else Vector3.ZERO)
	_drive(desired)
	if best <= STRIKE_RANGE and attack_cd <= 0 and retreat <= 0:
		var act := "thrust" if randf() < 0.25 else "attack"
		Input.action_press(act)
		await get_tree().process_frame
		Input.action_release(act)
		attack_cd = 1.2
		# Back off only after the follow-through: the blade is live 0.4-0.6 s
		# into the swing, and retreating earlier drags it out of range.
		retreat_delay = 0.75


func _snap(label: String) -> void:
	if shots == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots, label])


func _drive(world: Vector3) -> void:
	_release_move()
	if world.length_squared() < 0.01:
		return
	var cam: Camera3D = arena.camera
	var right = cam.global_basis.x
	right.y = 0
	right = right.normalized()
	var fwd = -cam.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var x = world.dot(right)
	var y = world.dot(fwd)
	if x < -0.1: Input.action_press("move_left", abs(x))
	if x > 0.1: Input.action_press("move_right", x)
	if y > 0.1: Input.action_press("move_forward", y)
	if y < -0.1: Input.action_press("move_back", abs(y))


func _release_move():
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(a)


func _release_all():
	_release_move()
	Input.action_release("attack")
	Input.action_release("thrust")
