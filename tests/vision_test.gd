extends Node
## Vision test: runs the real arena and saves rendered frames to disk.
##
## Exists because state-only checks lie. The character once read state=NORMAL
## in a headless assertion while lying collapsed in a heap on screen — nothing
## short of looking at a rendered frame catches that class of bug, and the same
## applies to every effect in CombatFX: particles, splats and the blade trail
## either draw or they don't, and no amount of GDScript introspection proves it.
##
## Run under Xvfb (rendering needs a real GL context, so --headless won't do):
##   xvfb-run -a godot --path . res://tests/vision_test.tscn -- --shots=/tmp/out

const ARENA := preload("res://scenes/arena.tscn")

var _out_dir := "/tmp/vision"
var _arena: Node3D
var _script_steps: Array = []
var _step := 0
var _timer := 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_out_dir = arg.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)

	_arena = ARENA.instantiate()
	add_child(_arena)

	# [delay before running, label, callable]. Delays are wall-clock seconds so
	# the physics rig has settled before anything is asserted about it.
	_script_steps = [
		[1.5, "01_idle", func(): pass],
		[0.4, "02_swing", func(): _arena.player.swing()],
		[0.35, "03_swing_mid", func(): pass],
		[0.5, "04_swing_follow", func(): pass],
		[0.6, "05_light_hit", func(): _arena._hit_player(CombatProfiles.light_swing(), 0.25)],
		[0.9, "06_heavy_hit", func(): _arena._hit_player(CombatProfiles.heavy_swing(), 0.65)],
		[0.9, "07_crushing", func(): _arena._hit_player(CombatProfiles.crushing_blow(), 1.0)],
		[0.5, "08_crushing_blood", func(): pass],
		[2.0, "09_downed", func(): pass],
		[3.0, "10_recovered", func(): pass],
	]


func _process(delta: float) -> void:
	if _step >= _script_steps.size():
		return
	# Undo any hit-stop the FX system applied, so the test's own pacing isn't
	# stretched by it.
	var scale := maxf(Engine.time_scale, 0.05)
	_timer += delta / scale

	var entry: Array = _script_steps[_step]
	if _timer < entry[0]:
		return
	_timer = 0.0
	_step += 1

	entry[2].call()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, entry[1]]
	img.save_png(path)
	print("SHOT %s state=%s" % [entry[1], _arena.player.get_state_name()])

	if _step >= _script_steps.size():
		print("VISION_TEST_DONE")
		get_tree().quit()
