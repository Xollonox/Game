extends Node
## Performance bench for the real arena: frame rate, frame times, draw calls
## and node count.
##
## `--noworld` frees the procedural world before measuring, so the cost of the
## world itself can be isolated from the cost of the fighters and effects.
## That comparison is how the web performance budget is actually kept: the
## world may only ever cost a fraction of the frame.
##
## Run:  godot --headless --path . res://tests/bench.tscn
##       xvfb-run -a godot --path . res://tests/bench.tscn -- --noworld

const ARENA := preload("res://scenes/arena.tscn")

var _elapsed := 0.0
var _frames := 0


func _ready() -> void:
	var arena: Node3D = ARENA.instantiate()
	add_child(arena)
	if OS.get_cmdline_user_args().has("--noworld"):
		var world := arena.get_node_or_null("World")
		if world:
			world.queue_free()


func _process(delta: float) -> void:
	_elapsed += delta
	_frames += 1
	if _elapsed >= 8.0:
		print("BENCH fps=%.1f process_ms=%.2f physics_ms=%.2f nodes=%d draws=%d prims=%d" % [
			_frames / _elapsed,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		])
		get_tree().quit()
