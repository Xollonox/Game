extends Node3D
## Arena: follow camera, HUD, and the debug keys used to exercise the ragdoll
## without a second combatant (1 = light, 2 = heavy/stagger, 3 = crushing/ragdoll).

const CAM_HEIGHT := 2.6
const CAM_DISTANCE := 5.5
const CAM_LAG := 6.0
const MAX_LOG_LINES := 6

@onready var player: KickbackActor = $Player
@onready var camera: Camera3D = $Camera3D
@onready var state_label: Label = $HUD/StateLabel
@onready var log_label: Label = $HUD/LogLabel
@onready var touch_controls: TouchControls = $TouchControls

## Phase 6 UI: per-fighter health readout and the death overlay, built in code
## so the arena scene stays a greybox.
var health_label: Label
var death_overlay: Label

## Peak positional shake in metres at severity 1.0. Small on purpose — camera
## shake that reads as "impact" rather than "earthquake" is a few centimetres.
const SHAKE_AMPLITUDE := 0.22
const SHAKE_DECAY := 5.0

var _cam_yaw := 0.0
var _log: Array[String] = []
var _shake := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if player:
		player.camera = camera
		player.touch_controls = touch_controls
		if player.has_signal("landed_hit"):
			player.landed_hit.connect(_on_landed_hit)
		player.died.connect(_on_actor_died)
	if touch_controls:
		touch_controls.camera_dragged.connect(_on_camera_dragged)
	CombatFX.shake_requested.connect(_on_shake_requested)

	for node in get_tree().get_nodes_in_group("hittable"):
		if node is Enemy:
			node.target = player
			node.landed_hit.connect(_on_enemy_landed_hit)
			node.died.connect(_on_actor_died)
	_build_hud()
	_log_line("WASD/joystick move · SPACE/button swing · 1/2/3 hit self · drag orbit")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		_cam_yaw -= event.relative.x * 0.006
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
					get_tree().reload_current_scene()


func _hit_player(profile: ImpactProfile, severity: float) -> void:
	if not player:
		return
	var dir := -player.global_basis.z
	player.receive_hit_at("Chest", dir, profile)
	CombatFX.impact(player.global_position + Vector3.UP * 1.25, dir, severity)
	_log_line("self-hit: %s" % profile.profile_name)


func _on_shake_requested(strength: float) -> void:
	_shake = maxf(_shake, clampf(strength, 0.0, 1.0))


func _physics_process(delta: float) -> void:
	if not player or not camera:
		return
	var offset := Vector3(sin(_cam_yaw), 0.0, cos(_cam_yaw)) * CAM_DISTANCE
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

	if state_label:
		state_label.text = "State: %s" % player.get_state_name()
	if health_label:
		health_label.text = _health_text()


func _on_camera_dragged(delta: Vector2) -> void:
	_cam_yaw -= delta.x * 0.006


func _on_landed_hit(target_name: String, profile_name: String) -> void:
	_log_line("hit %s with %s" % [target_name, profile_name])


func _on_enemy_landed_hit(target_name: String, profile_name: String) -> void:
	_log_line("%s took %s" % [target_name, profile_name])


func _log_line(text: String) -> void:
	_log.append(text)
	while _log.size() > MAX_LOG_LINES:
		_log.pop_front()
	if log_label:
		log_label.text = "\n".join(_log)


## Phase 6 basic UI: one line of per-fighter health plus a death overlay with
## the restart hint. Built in code — nothing here needs scene authoring.
func _build_hud() -> void:
	var hud: CanvasLayer = $HUD
	health_label = Label.new()
	health_label.position = Vector2(16, 42)
	health_label.add_theme_font_size_override("font_size", 20)
	hud.add_child(health_label)

	death_overlay = Label.new()
	death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	death_overlay.add_theme_font_size_override("font_size", 44)
	death_overlay.add_theme_color_override("font_color", Color(0.92, 0.18, 0.12))
	death_overlay.text = "YOU DIED\nPress R to restart"
	death_overlay.visible = false
	hud.add_child(death_overlay)


func _health_text() -> String:
	if player.is_dead():
		return ""
	var parts: Array[String] = ["You %d" % roundi(player.health)]
	for node in get_tree().get_nodes_in_group("hittable"):
		if node is Enemy and not node.is_dead():
			parts.append("%s %d" % [node.name, roundi(node.health)])
	return "   ".join(parts)


func _on_actor_died(actor: KickbackActor) -> void:
	if actor == player:
		death_overlay.visible = true
	else:
		_log_line("%s is down" % actor.name)
