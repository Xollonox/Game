extends KickbackActor
## The player fighter.
##
## Attacks are steered, not canned: the movement you hold as you strike picks
## the line of the cut — pressing forward brings the blade down from above
## (Oberhau), sideways cuts horizontally from that side (Mittelhau), backing
## off rises from below (Unterhau), and the thrust key drives the point in.
## The hands then chase that pose and the physics weapon does the rest.
##
## In a fight the body squares up to the nearest opponent (soft lock), so
## footwork circles and backs away instead of turning your back on a blade.

var camera: Camera3D
var touch_controls: TouchControls
var lock_target: KickbackActor
var lock_enabled := true


func _physics_process(delta: float) -> void:
	if is_dead():
		move_dir = Vector3.ZERO
		return
	var input_2d := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch_controls:
		input_2d = (input_2d + touch_controls.get_move_vector()).limit_length(1.0)
	move_dir = _camera_relative(input_2d) * clampf(input_2d.length() * 1.2, 0.0, 1.0)
	sprinting = Input.is_key_pressed(KEY_SHIFT) and input_2d.length() > 0.1
	_update_lock()
	if lock_target and not sprinting:
		face_dir = Vector3(lock_target.global_position.x - global_position.x, 0.0,
			lock_target.global_position.z - global_position.z)
	else:
		face_dir = Vector3.ZERO
	set_guard(Input.is_action_pressed("guard") and not sprinting)
	super._physics_process(delta)

	if Input.is_action_just_pressed("attack"):
		attack("heavy" if sprinting else "cut", {"dir": _line_from_input(input_2d)})
	elif Input.is_action_just_pressed("thrust"):
		attack("thrust", {"dir": "thrust"})


func _line_from_input(input_2d: Vector2) -> String:
	if input_2d.length() < 0.3:
		return ""
	if absf(input_2d.x) > absf(input_2d.y):
		return "right" if input_2d.x > 0 else "left"
	return "high" if input_2d.y < 0 else "low"


func _update_lock() -> void:
	if not lock_enabled:
		lock_target = null
		return
	var best: KickbackActor = null
	var best_d := 7.0
	for node in get_tree().get_nodes_in_group("fighters"):
		var a := node as KickbackActor
		if a == null or a == self or a.is_dead():
			continue
		var d := global_position.distance_to(a.global_position)
		if a == lock_target:
			d -= 1.0
		if d < best_d:
			best_d = d
			best = a
	lock_target = best


func _camera_relative(input_2d: Vector2) -> Vector3:
	if input_2d == Vector2.ZERO:
		return Vector3.ZERO
	var basis_z := Vector3.FORWARD
	var basis_x := Vector3.RIGHT
	if camera:
		basis_z = -camera.global_basis.z
		basis_x = camera.global_basis.x
		basis_z.y = 0.0
		basis_x.y = 0.0
		basis_z = basis_z.normalized()
		basis_x = basis_x.normalized()
	return (basis_x * input_2d.x + basis_z * -input_2d.y).normalized()
