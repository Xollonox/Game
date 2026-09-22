extends Node
const ARENA=preload("res://scenes/arena.tscn")
var elapsed:=0.0
var frames:=0
func _ready(): add_child(ARENA.instantiate())
func _process(delta):
 elapsed+=delta; frames+=1
 if elapsed>=8.0:
  print("BENCH fps=%.1f process_ms=%.2f physics_ms=%.2f nodes=%d" % [frames/elapsed,Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
  get_tree().quit()
