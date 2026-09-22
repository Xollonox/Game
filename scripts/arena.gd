extends Node3D
## Arena: follow camera, interface wiring, and the debug keys used to exercise
## the ragdoll without a second combatant (1 = light, 2 = heavy, 3 = crushing).
##
## The combat core is unchanged from the original build — same Jolt config,
## same active-ragdoll rig, same physics sword. This file only owns the camera
## feel, the interface updates, and the wiring between the world, the fighters
## and the HUD.

const CAM_HEIGHT := 2.6
const CAM_DISTANCE := 6.0
const CAM_LAG := 9.0
const CAM_ZOOM_MIN := 3.2
const CAM_ZOOM_MAX := 10.0

@onready var player: KickbackActor = $Player
@onready var camera: Camera3D = $Camera3D
@onready var touch_controls: TouchControls = $TouchControls
@onready var hud: ArenaHUD = $HUD
@onready var sun: DirectionalLight3D = $Sun

## Peak positional shake in metres at severity 1.0. Small on purpose — camera
## shake that reads as "impact" rather than "earthquake" is a few centimetres.
const SHAKE_AMPLITUDE := 0.22
const SHAKE_DECAY := 5.0

var _cam_dist := CAM_DISTANCE
var _cam_yaw := 0.0
var _shake := 0.0
var _rng := RandomNumberGenerator.new()
var _enemies: Array[Enemy] = []


func _ready() -> void:
	_rng.randomize()
	if player:
		player.camera = camera
		player.touch_controls = touch_controls
		player.landed_hit.connect(_on_player_landed_hit)
		player.died.connect(_on_actor_died)
	if touch_controls:
		touch_controls.camera_dragged.connect(_on_camera_dragged)
	CombatFX.shake_requested.connect(_on_shake_requested)

	for node in get_tree().get_nodes_in_group("hittable"):
		if node is Enemy:
			_enemies.append(node)
			node.target = player
			node.landed_hit.connect(_on_enemy_landed_hit)
			node.died.connect(_on_actor_died)

	hud.restart_requested.connect(_restart)
	hud.leave_requested.connect(_leave_to_menu)
	GameState.settings_changed.connect(_apply_settings)
	_apply_settings()
	AudioDirector.play_fight_music()
	AudioDirector.start_ambience()


## Settings that live on the arena side: shadows, particle budget, blood.
func _apply_settings() -> void:
	if sun:
		sun.shadow_enabled = GameState.quality_high
	CombatFX.blood_enabled = GameState.blood
	CombatFX.quality_high = GameState.quality_high


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if player and not player.is_dead():
			hud.toggle_pause()
		return
	if hud.is_paused():
		return

	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		_cam_yaw -= event.relative.x * 0.006
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = clampf(_cam_dist - 0.6, CAM_ZOOM_MIN, CAM_ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = clampf(_cam_dist + 0.6, CAM_ZOOM_MIN, CAM_ZOOM_MAX)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_hit_player(CombatProfiles.light_swing(), 0.25)
			KEY_2:
				_hit_player(CombatProfiles.heavy_swing(), 0.65)
			KEY_3:
				_hit_player(CombatProfiles.crushing_blow(), 1.0)
			KEY_Q:
				_cam_yaw += 0.25
			KEY_E:
				_cam_yaw -= 0.25
			KEY_R:
				if player and player.is_dead():
					_restart()


## Used by the debug keys and by the vision test to drive a hit without a
## second fighter. Kept public for exactly that reason.
func _hit_player(profile: ImpactProfile, severity: float) -> void:
	if not player:
		return
	var dir := -player.global_basis.z
	player.receive_hit_at("Chest", dir, profile)
	CombatFX.impact(player.global_position + Vector3.UP * 1.25, dir, severity)


func _on_shake_requested(strength: float) -> void:
	_shake = maxf(_shake, clampf(strength, 0.0, 1.0))


func _physics_process(delta: float) -> void:
	if not player or not camera:
		return
	var offset := Vector3(sin(_cam_yaw), 0.0, cos(_cam_yaw)) * _cam_dist
	var target := player.global_position + offset + Vector3.UP * CAM_HEIGHT
	camera.global_position = camera.global_position.lerp(target, clampf(CAM_LAG * delta, 0.0, 1.0))

	# Shake is applied after the follow lerp, not folded into the target, so it
	# jitters the camera without the smoothing eating it.
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - SHAKE_DECAY * delta)
		var k := _shake * _shake * SHAKE_AMPLITUDE
		camera.global_position += Vector3(
			_rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0)) * k

	camera.look_at(player.global_position + Vector3.UP * 1.0)
	_update_hud()


func _update_hud() -> void:
	hud.set_vitals(player.health, player.max_health)
	var entries: Array = []
	for e in _enemies:
		entries.append({
			"name": String(e.name),
			"health": e.health,
			"max": e.max_health,
			"dead": e.is_dead(),
		})
	hud.set_enemies(entries)


func _restart() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()


func _leave_to_menu() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	AudioDirector.stop_ambience()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _on_camera_dragged(delta: Vector2) -> void:
	_cam_yaw -= delta.x * 0.006


func _on_player_landed_hit(target_name: String, profile_name: String) -> void:
	hud.feed("%s — %s" % [target_name, profile_name])


func _on_enemy_landed_hit(target_name: String, profile_name: String) -> void:
	if target_name == "Player":
		hud.feed("You take a %s" % profile_name.to_lower())
	else:
		hud.feed("%s — %s" % [target_name, profile_name])


func _on_actor_died(actor: KickbackActor) -> void:
	if actor == player:
		hud.show_death()
	else:
		hud.feed("%s falls" % actor.name)
