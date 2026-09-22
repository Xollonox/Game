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

var _cam_yaw := 0.0
var _log: Array[String] = []


func _ready() -> void:
	if player:
		player.camera = camera
		player.touch_controls = touch_controls
		if player.has_signal("landed_hit"):
			player.landed_hit.connect(_on_landed_hit)
	if touch_controls:
		touch_controls.camera_dragged.connect(_on_camera_dragged)
	_log_line("WASD/joystick move · SPACE/button swing · 1/2/3 hit self · drag orbit")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		_cam_yaw -= event.relative.x * 0.006
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_hit_player(CombatProfiles.light_swing())
			KEY_2:
				_hit_player(CombatProfiles.heavy_swing())
			KEY_3:
				_hit_player(CombatProfiles.crushing_blow())
			KEY_Q:
				_cam_yaw += 0.25
			KEY_E:
				_cam_yaw -= 0.25


func _hit_player(profile: ImpactProfile) -> void:
	if not player:
		return
	var dir := -player.global_basis.z
	player.receive_hit_at("Chest", dir, profile)
	_log_line("self-hit: %s" % profile.profile_name)


func _physics_process(delta: float) -> void:
	if not player or not camera:
		return
	var offset := Vector3(sin(_cam_yaw), 0.0, cos(_cam_yaw)) * CAM_DISTANCE
	var target := player.global_position + offset + Vector3.UP * CAM_HEIGHT
	camera.global_position = camera.global_position.lerp(target, clampf(CAM_LAG * delta, 0.0, 1.0))
	camera.look_at(player.global_position + Vector3.UP * 1.0)

	if state_label:
		state_label.text = "State: %s" % player.get_state_name()


func _on_camera_dragged(delta: Vector2) -> void:
	_cam_yaw -= delta.x * 0.006


func _on_landed_hit(target_name: String, profile_name: String) -> void:
	_log_line("hit %s with %s" % [target_name, profile_name])


func _log_line(text: String) -> void:
	_log.append(text)
	while _log.size() > MAX_LOG_LINES:
		_log.pop_front()
	if log_label:
		log_label.text = "\n".join(_log)
