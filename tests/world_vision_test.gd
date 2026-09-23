extends Node
## World/menu vision test: the critique-loop camera.
##
## Captures the main menu, then the arena from several composed angles (gate
## landmark, wide establishing shot, stands, camp, low hero angle), then two
## combat moments. `tests/vision_test.gd` stays focused on the fighter rig;
## this test exists to judge the *world* — composition, scale, silhouettes,
## clutter, atmosphere — from rendered frames, which is the only way those
## qualities can actually be assessed.
##
## Run under Xvfb:
##   xvfb-run -a godot --path . res://tests/world_vision_test.tscn -- --shots=/tmp/world

const MENU := preload("res://scenes/menu.tscn")
const ARENA := preload("res://scenes/arena.tscn")

var _out_dir := "/tmp/world"
var _menu: Node3D
var _arena: Node3D
var _steps: Array = []
var _step := 0
var _timer := 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_out_dir = arg.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)

	_menu = MENU.instantiate()
	add_child(_menu)

	_steps = [
		[2.4, "01_menu", func(): pass],
		[1.2, "02_menu_drift", func(): pass],
		[0.2, "03_swap", func(): _to_arena()],
		[2.2, "04_arena_gate", func(): _view(0.0, 6.5)],
		[1.3, "05_arena_wide", func(): _view(2.4, 9.6)],
		[1.3, "06_arena_stands", func(): _view(1.35, 7.2)],
		[1.3, "07_arena_camp", func(): _view(-1.5, 7.6)],
		[1.3, "08_arena_low", func(): _view(0.55, 3.4)],
		[1.3, "09_arena_brazier", func(): _view(-0.35, 5.0)],
		[0.6, "10_swing", func(): _arena.player.swing()],
		[0.5, "11_swing_mid", func(): pass],
		[2.0, "12_melee", func(): pass],
		[1.6, "13_melee_2", func(): pass],
		[1.2, "14_crushing", func(): _arena._hit_player(CombatProfiles.crushing_blow(), 1.0)],
		[2.0, "15_downed", func(): pass],
	]


func _to_arena() -> void:
	_menu.queue_free()
	_arena = ARENA.instantiate()
	add_child(_arena)
	# Skip the herald and take manual control of the framing.
	_arena._start_fight.call_deferred()


func _view(yaw: float, dist: float) -> void:
	_arena._cam_yaw = yaw
	_arena._cam_dist = dist
	_arena._cam_manual = 999.0


func _process(delta: float) -> void:
	if _step >= _steps.size():
		return
	var scale := maxf(Engine.time_scale, 0.05)
	_timer += delta / scale
	var entry: Array = _steps[_step]
	if _timer < entry[0]:
		return
	_timer = 0.0
	_step += 1
	entry[2].call()

	# Give the camera one frame to settle onto the new framing before capture.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out_dir, entry[1]])
	print("SHOT %s" % entry[1])

	if _step >= _steps.size():
		print("WORLD_VISION_DONE")
		get_tree().quit()
