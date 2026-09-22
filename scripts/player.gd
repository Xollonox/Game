extends KickbackActor
## Player: WASD walking (camera-relative) and a sword swing that lands a heavy
## hit on any dummy in front of it. Phase 2/3 of PLAN.md.

const ATTACK_RANGE := 2.2
const ATTACK_ARC_DOT := 0.35
## Delay between the swing starting and the blow landing, so the hit lines up
## with the animation's contact frame rather than the keypress.
const ATTACK_CONTACT_DELAY := 0.28

signal landed_hit(target_name: String, profile_name: String)

var camera: Camera3D
var touch_controls: TouchControls

var _pending_contact := -1.0


func _physics_process(delta: float) -> void:
	var input_2d := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch_controls:
		input_2d = (input_2d + touch_controls.get_move_vector()).limit_length(1.0)
	move_dir = _camera_relative(input_2d)
	super._physics_process(delta)

	if Input.is_action_just_pressed("attack") and swing():
		_pending_contact = ATTACK_CONTACT_DELAY

	if _pending_contact >= 0.0:
		_pending_contact -= delta
		if _pending_contact < 0.0:
			_resolve_swing()


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


func _resolve_swing() -> void:
	var forward := -global_basis.z
	for node in get_tree().get_nodes_in_group("hittable"):
		var target := node as KickbackActor
		if not target or target == self:
			continue
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		var dist := to_target.length()
		if dist > ATTACK_RANGE or dist < 0.01:
			continue
		if forward.dot(to_target / dist) < ATTACK_ARC_DOT:
			continue
		# Closer hits land cleaner: a blow at the edge of reach only staggers.
		var profile := CombatProfiles.crushing_blow() if dist < ATTACK_RANGE * 0.6 \
			else CombatProfiles.heavy_swing()
		target.receive_hit_at("Chest", (to_target / dist), profile)
		landed_hit.emit(target.name, String(profile.profile_name))
