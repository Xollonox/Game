extends Node3D
## The tournament yard: runs one bout of the run's ladder.
##
## Flow: INTRO (the herald's card, the opponents waiting at the gate) ->
## FIGHT -> VICTORY (renown, the fallen, a choice from their weapons) or
## DEATH (descend into the Hollow, begin a new life, or leave). Each bout is
## rolled from GameState.run by Tournament.encounter(), so a reload is the
## next bout, not the same one again.
##
## The combat core is unchanged from the original build — same Jolt config,
## same active-ragdoll rig, same physics-first weapons. This file owns the
## camera, the bout director (entry timing and how many opponents may press
## you at once) and the wiring to the HUD.

const FIGHTER := preload("res://scenes/dummy.tscn")
const CAM_HEIGHT := 1.85
const CAM_DISTANCE := 4.6
const CAM_LAG := 7.0
const CAM_ZOOM_MIN := 2.8
const CAM_ZOOM_MAX := 10.0
const SHAKE_AMPLITUDE := 0.2
const SHAKE_DECAY := 5.0

enum Phase { INTRO, FIGHT, VICTORY, DEATH }

@onready var player: KickbackActor = $Player
@onready var camera: Camera3D = $Camera3D
@onready var touch_controls: TouchControls = $TouchControls
@onready var hud: ArenaHUD = $HUD
@onready var sun: DirectionalLight3D = $Sun

var encounter: Dictionary = {}
var phase := Phase.INTRO
var _cam_dist := CAM_DISTANCE
var _cam_yaw := 0.0
var _cam_manual := 0.0
var _shake := 0.0
var _rng := RandomNumberGenerator.new()
var _enemies: Array[Enemy] = []
var _fallen: Array = []
var _phase_t := 0.0
var _intro_orbit := 0.0


## Runs top-down, before any child's _ready: the player must be dressed from
## the run before its rig and look are built.
func _enter_tree() -> void:
	if not GameState.has_run():
		GameState.new_run()
	var p := get_node_or_null("Player")
	if p:
		p.spec = _player_spec()


func _player_spec() -> Dictionary:
	return GameState.player_spec()


func _ready() -> void:
	_rng.randomize()
	encounter = _make_encounter()

	if player:
		player.camera = camera
		player.touch_controls = touch_controls
		player.landed_hit.connect(_on_player_landed_hit)
		player.died.connect(_on_actor_died)
		player.global_position = Vector3(0, 0, 4.2)
		player.rotation.y = PI
	if touch_controls:
		touch_controls.camera_dragged.connect(_on_camera_dragged)
	CombatFX.shake_requested.connect(_on_shake_requested)
	_spawn_foes()

	hud.restart_requested.connect(_on_restart)
	hud.leave_requested.connect(_leave_to_menu)
	hud.choice_made.connect(_on_choice)
	GameState.settings_changed.connect(_apply_settings)
	_apply_settings()
	_music()
	_cam_yaw = 0.0
	camera.global_position = Vector3(6, 3.0, 8)
	_begin_intro()


func _make_encounter() -> Dictionary:
	var run := GameState.run
	return Tournament.encounter(int(run.get("bout", 0)), int(run.get("seed", 1)))


func _music() -> void:
	AudioDirector.play_fight_music()
	AudioDirector.start_ambience()


func _spawn_foes() -> void:
	var foes: Array = encounter.get("foes", [])
	var n := foes.size()
	for i in n:
		var f: Dictionary = foes[i]
		var e: Enemy = FIGHTER.instantiate()
		e.spec = f["spec"]
		e.team = int(f["team"])
		e.name = String(f["spec"]["name"]).replace(" ", "_")
		# Opponents wait in an arc on the far side of the ring, by the gate.
		var spread := 0.0 if n == 1 else lerpf(-0.9, 0.9, float(i) / float(n - 1))
		var pos := Vector3(sin(spread) * 5.2, 0, -cos(spread) * 5.2 - 0.6)
		add_child(e)
		e.global_position = pos
		e.rotation.y = atan2(-pos.x, -pos.z) + PI
		e.set_engage_delay(9999.0)
		e.token_granted = _grant_token
		e.landed_hit.connect(_on_enemy_landed_hit)
		e.died.connect(_on_actor_died)
		e.set_meta(&"entry", float(f["entry"]))
		_enemies.append(e)


func _begin_intro() -> void:
	phase = Phase.INTRO
	_phase_t = 0.0
	hud.show_intro(encounter, GameState.run, _enemies.map(func(e): return e.spec))


func _start_fight() -> void:
	if phase != Phase.INTRO:
		return
	phase = Phase.FIGHT
	_phase_t = 0.0
	hud.hide_intro()
	hud.show_fight_hud(int(encounter.get("bout", 0)) == 0)
	for e in _enemies:
		e.set_engage_delay(float(e.get_meta(&"entry")))
	AudioDirector.crowd_cheer(0.6)


## Attack tokens: how many opponents may press the same target at once. The
## rest hold at the ring, circle and wait — a ring of men, not a scrum.
func _grant_token(e: Enemy) -> bool:
	if e.target == null:
		return false
	if e.target != player:
		return true
	var limit := int(encounter.get("pressers", 1))
	var pressing := 0
	var mine_dist := e.global_position.distance_to(player.global_position)
	for o in _enemies:
		if o == e or o.is_dead() or o.is_downed() or o.target != player:
			continue
		var d := o.global_position.distance_to(player.global_position)
		if d < mine_dist:
			pressing += 1
	return pressing < limit


func _apply_settings() -> void:
	if sun:
		sun.shadow_enabled = GameState.quality_high
	CombatFX.blood_enabled = GameState.blood
	CombatFX.quality_high = GameState.quality_high


func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.INTRO:
		if _phase_t > 0.6 and (event.is_action_pressed("attack") or event.is_action_pressed("ui_accept")
				or (event is InputEventScreenTouch and event.pressed)):
			_start_fight()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if phase == Phase.FIGHT and player and not player.is_dead():
			hud.toggle_pause()
		return
	if hud.is_paused() or phase != Phase.FIGHT:
		return
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		_cam_yaw -= event.relative.x * 0.006
		_cam_manual = 2.5
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = clampf(_cam_dist - 0.5, CAM_ZOOM_MIN, CAM_ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = clampf(_cam_dist + 0.5, CAM_ZOOM_MIN, CAM_ZOOM_MAX)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				_cam_yaw += 0.3
				_cam_manual = 2.5
			KEY_E:
				_cam_yaw -= 0.3
				_cam_manual = 2.5
			KEY_TAB:
				player.lock_enabled = not player.lock_enabled


## Used by the vision test to drive a hit without a second fighter.
func _hit_player(profile: ImpactProfile, severity: float) -> void:
	if not player:
		return
	var dir := -player.global_basis.z
	player.receive_hit_at("Chest", dir, profile)
	CombatFX.impact(player.global_position + Vector3.UP * 1.25, dir, severity)


func _on_shake_requested(strength: float) -> void:
	_shake = maxf(_shake, clampf(strength, 0.0, 1.0))


func _process(delta: float) -> void:
	_phase_t += delta / maxf(Engine.time_scale, 0.05)
	if phase == Phase.INTRO and _phase_t > 14.0:
		_start_fight()


func _physics_process(delta: float) -> void:
	if not player or not camera:
		return
	_cam_manual = maxf(0.0, _cam_manual - delta)
	var focus := player.global_position
	var look := player.global_position + Vector3.UP * 1.1
	if phase == Phase.INTRO:
		# The herald's shot: slow arc across the waiting opponents.
		_intro_orbit += delta * 0.12
		var mid := Vector3(0, 0, -2.5)
		var pos := mid + Vector3(sin(0.6 + _intro_orbit) * 8.5, 2.4, cos(0.6 + _intro_orbit) * 8.5)
		camera.global_position = camera.global_position.lerp(pos, clampf(2.0 * delta, 0.0, 1.0))
		camera.look_at(mid + Vector3.UP * 1.2)
		return
	var tgt: KickbackActor = player.get("lock_target")
	if tgt and _cam_manual <= 0.0 and phase == Phase.FIGHT:
		# Frame both fighters: sit behind the player, looking past him at the
		# opponent, a little off his right shoulder.
		var to_t := tgt.global_position - player.global_position
		to_t.y = 0.0
		if to_t.length() > 0.3:
			var want := atan2(-to_t.x, -to_t.z) + 0.35
			_cam_yaw = lerp_angle(_cam_yaw, want, clampf(1.6 * delta, 0.0, 1.0))
			look = look.lerp(tgt.global_position + Vector3.UP * 1.1, 0.35)
	var offset := Vector3(sin(_cam_yaw), 0.0, cos(_cam_yaw)) * _cam_dist
	var target := focus + offset + Vector3.UP * CAM_HEIGHT
	camera.global_position = camera.global_position.lerp(target, clampf(CAM_LAG * delta, 0.0, 1.0))
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - SHAKE_DECAY * delta)
		var k := _shake * _shake * SHAKE_AMPLITUDE
		camera.global_position += Vector3(_rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0)) * k
	camera.look_at(look)
	_update_hud()
	if phase == Phase.FIGHT:
		_check_outcome()


func _update_hud() -> void:
	hud.set_vitals(player.health, player.max_health)
	var entries: Array = []
	for e in _enemies:
		entries.append({"name": String(e.spec.get("name", e.name)), "health": e.health, "max": e.max_health,
			"dead": e.is_dead(), "focus": e == player.get("lock_target")})
	hud.set_enemies(entries)
	var lt: KickbackActor = player.get("lock_target")
	if lt and not lt.is_dead() and phase == Phase.FIGHT:
		var head := lt.global_position + Vector3.UP * 2.05
		var vis := not camera.is_position_behind(head)
		hud.set_target(String(lt.spec.get("name", "")), lt.health / maxf(lt.max_health, 1.0),
			camera.unproject_position(head), vis)
	else:
		hud.set_target("", 0.0, Vector2.ZERO, false)


func _check_outcome() -> void:
	var alive := 0
	for e in _enemies:
		if not e.is_dead():
			alive += 1
	if alive == 0 and not player.is_dead():
		_victory()


func _victory() -> void:
	phase = Phase.VICTORY
	AudioDirector.crowd_cheer(1.0)
	var fallen_specs: Array = []
	var weapons: Array[String] = []
	for e in _enemies:
		fallen_specs.append(e.spec)
		var w: String = e.spec.get("weapon", "")
		if w != "" and not w in weapons and w != player.spec.get("weapon", ""):
			weapons.append(w)
	# Only the dead you killed yourself count against you below.
	var mine: Array = []
	for e in _enemies:
		if e.last_attacker == player:
			mine.append(e.spec)
	var renown: int = encounter.get("renown", 10)
	GameState.bout_won(renown, mine)
	await get_tree().create_timer(2.2).timeout
	hud.show_victory(encounter, GameState.run, fallen_specs, weapons, player.spec)


func _on_choice(kind: String, value: String) -> void:
	match kind:
		"spoils":
			if value != "":
				GameState.set_weapon(value, WeaponCatalog.get_def(value).get("class", "") in ["sword", "axe", "mace", "club"]
					and bool(player.spec.get("shield", false)))
			if int(GameState.run.get("bout", 0)) >= Tournament.bout_count():
				hud.show_champion(GameState.run)
			else:
				_next_scene("res://scenes/arena.tscn")
		"hollow":
			GameState.enter_hollow()
			_next_scene("res://scenes/hollow.tscn")
		"new_run":
			GameState.new_run()
			_next_scene("res://scenes/arena.tscn")
		"menu":
			_leave_to_menu()


func _on_player_death() -> void:
	hud.show_death(GameState.run, player.kills)


func _next_scene(path: String) -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	await hud.fade_out(0.8)
	get_tree().change_scene_to_file(path)


func _on_restart() -> void:
	_on_choice("new_run", "")


func _leave_to_menu() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	AudioDirector.stop_ambience()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _on_camera_dragged(delta: Vector2) -> void:
	_cam_yaw -= delta.x * 0.006
	_cam_manual = 2.5


func _on_player_landed_hit(_target_name: String, _profile_name: String) -> void:
	pass


func _on_enemy_landed_hit(_target_name: String, _profile_name: String) -> void:
	pass


func _on_actor_died(actor: KickbackActor) -> void:
	if actor == player:
		phase = Phase.DEATH
		Engine.time_scale = 0.35
		await get_tree().create_timer(0.9, true, false, true).timeout
		Engine.time_scale = 1.0
		_on_player_death()
	else:
		hud.feed("%s falls" % actor.spec.get("name", actor.name))
		AudioDirector.crowd_cheer(0.8)
