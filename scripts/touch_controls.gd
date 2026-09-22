class_name TouchControls
extends CanvasLayer
## On-screen controls for touchscreen devices: a virtual joystick (left side,
## drives movement) and a swing button (right side). The joystick exposes its
## vector for player.gd to read; the swing button drives the "attack" action
## directly via Input.action_press/release so the existing keyboard/mouse
## handling in player.gd needs no touch-specific branch.
##
## A drag anywhere on the right side outside the button orbits the camera,
## mirroring the existing right-mouse-drag behavior on desktop.

signal camera_dragged(delta: Vector2)

const JOYSTICK_RADIUS := 55.0

@onready var joystick_base: Control = $JoystickBase
@onready var joystick_knob: Control = $JoystickBase/JoystickKnob
@onready var attack_button: Button = $AttackButton

var _joystick_touch_index := -1
var _joystick_center := Vector2.ZERO
var _joystick_vector := Vector2.ZERO
var _camera_touch_index := -1


func _ready() -> void:
	# Show for real touch devices; a screen that later receives an actual touch
	# event (some browsers under-report touch support) reveals it too.
	visible = DisplayServer.is_touchscreen_available()
	attack_button.button_down.connect(func(): Input.action_press("attack"))
	attack_button.button_up.connect(func(): Input.action_release("attack"))
	_reset_knob()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if not visible:
			visible = true
		_on_touch(event)
	elif event is InputEventScreenDrag and visible:
		_on_drag(event)


func get_move_vector() -> Vector2:
	return _joystick_vector


func _on_touch(event: InputEventScreenTouch) -> void:
	var half_width := get_viewport().get_visible_rect().size.x * 0.5
	if event.pressed:
		if event.position.x < half_width:
			if _joystick_touch_index == -1:
				_joystick_touch_index = event.index
				_joystick_center = joystick_base.global_position + joystick_base.size * 0.5
		elif _camera_touch_index == -1 and not _point_in_control(attack_button, event.position):
			_camera_touch_index = event.index
	else:
		if event.index == _joystick_touch_index:
			_joystick_touch_index = -1
			_joystick_vector = Vector2.ZERO
			_reset_knob()
		elif event.index == _camera_touch_index:
			_camera_touch_index = -1


func _on_drag(event: InputEventScreenDrag) -> void:
	if event.index == _joystick_touch_index:
		var delta := (event.position - _joystick_center).limit_length(JOYSTICK_RADIUS)
		_joystick_vector = delta / JOYSTICK_RADIUS
		joystick_knob.position = joystick_base.size * 0.5 - joystick_knob.size * 0.5 + delta
	elif event.index == _camera_touch_index:
		camera_dragged.emit(event.relative)


func _reset_knob() -> void:
	joystick_knob.position = joystick_base.size * 0.5 - joystick_knob.size * 0.5


func _point_in_control(control: Control, point: Vector2) -> bool:
	return Rect2(control.global_position, control.size).has_point(point)
