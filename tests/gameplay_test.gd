extends Node
const ARENA := preload("res://scenes/arena.tscn")
const ENGAGE_RANGE := 1.2
const STRIKE_RANGE := 1.7
const RETREAT_TIME := 0.5
const LIMIT := 35.0
var arena
var t := 0.0
var attack_cd := 0.0
var retreat := 0.0
var hits := 0
var kills := 0

func _ready() -> void:
    arena = ARENA.instantiate()
    add_child(arena)
    arena.player.landed_hit.connect(func(_a,_b): hits += 1)
    for e in get_tree().get_nodes_in_group("hittable"):
        if e is Enemy: e.died.connect(func(_a): kills += 1)

func _physics_process(delta: float) -> void:
    t += delta; attack_cd -= delta; retreat -= delta
    var p: KickbackActor = arena.player
    if p.is_dead() or kills >= 3 or t >= LIMIT:
        _release_all()
        print("GAMEPLAY_SUMMARY reason=%s hits=%d kills=%d player_health=%d enemies_alive=%d t=%.1f" % ["cleared" if kills >= 3 else ("player_died" if p.is_dead() else "timeout"), hits, kills, roundi(p.health), 3-kills, t])
        get_tree().quit(); return
    var target: Enemy
    var best := INF
    for n in get_tree().get_nodes_in_group("hittable"):
        if n is Enemy and not n.is_dead():
            var d = p.global_position.distance_to(n.global_position)
            if d < best: best=d; target=n
    if not target: return
    var d3 := target.global_position - p.global_position; d3.y=0
    var desired := -d3.normalized() if retreat > 0 else (d3.normalized() if best > ENGAGE_RANGE else Vector3.ZERO)
    _drive(desired)
    if best <= STRIKE_RANGE and attack_cd <= 0 and retreat <= 0:
        Input.action_press("attack"); await get_tree().process_frame; Input.action_release("attack")
        attack_cd=0.9; retreat=RETREAT_TIME

func _drive(world: Vector3) -> void:
    _release_move()
    if world.length_squared() < 0.01: return
    var cam: Camera3D=arena.camera
    var right=cam.global_basis.x; right.y=0; right=right.normalized()
    var fwd=-cam.global_basis.z; fwd.y=0; fwd=fwd.normalized()
    var x=world.dot(right); var y=world.dot(fwd)
    if x < -0.1: Input.action_press("move_left",abs(x))
    if x > 0.1: Input.action_press("move_right",x)
    if y > 0.1: Input.action_press("move_forward",y)
    if y < -0.1: Input.action_press("move_back",abs(y))
func _release_move():
    for a in ["move_left","move_right","move_forward","move_back"]: Input.action_release(a)
func _release_all():
    _release_move(); Input.action_release("attack")
