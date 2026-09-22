extends KickbackActor
## Player: WASD walking (camera-relative) and a physics-driven sword swing
## (PLAN.md Phase 3/4). The sword (scripts/physics_sword.gd) grip-follows the
## rig's Hand_R bone through the existing "Sword_Attack" animation and deals
## damage from its own real contact velocity — there is no separate raycast/
## arc hit check here any more; the blade either physically connects or it
## doesn't.

var camera: Camera3D
var touch_controls: TouchControls


func _physics_process(delta: float) -> void:
	if is_dead():
		# Dead player: the rig owns the body; no input until the arena restarts.
		move_dir = Vector3.ZERO
		return

	var input_2d := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch_controls:
		input_2d = (input_2d + touch_controls.get_move_vector()).limit_length(1.0)
	move_dir = _camera_relative(input_2d)
	var sprinting := Input.is_key_pressed(KEY_SHIFT) and input_2d.length() > 0.1
	move_speed = SPRINT_SPEED if sprinting else WALK_SPEED
	locomotion_anim = SPRINT_ANIM if sprinting else WALK_ANIM
	super._physics_process(delta)

	if Input.is_action_just_pressed("attack"):
		swing()


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
