class_name BleedingSource
extends Node3D
## A wound that bleeds from where it is.
##
## Parented to the struck rig body at the exact contact point, oriented with
## +Z along the wound's outward normal, so it rides the ragdoll wherever the
## body goes. It reads its own bleed rate from the fighter's InjurySystem
## region, and:
##   - on creation: the impact spray, thrown with the blow and off the surface
##   - while bleeding: drops, falling from the wound; each drop's landing is
##     ray-tested, and it leaves a pooled splat on whatever it hits (floor,
##     wall, a man lying on the ground)
##   - arterial (neck, thigh, a severed limb): pulsing directional spurts in
##     time with a heartbeat that weakens as blood runs out
## It decays as the wound clots and frees itself when done. A global budget
## caps active sources (fewer on low quality / web). Nothing happens at all
## when blood is disabled (CombatFX.blood_enabled) — gameplay is unaffected.

const MAX_ACTIVE_HIGH := 14
const MAX_ACTIVE_LOW := 6
const MAX_AGE := 75.0
static var _active: Array[BleedingSource] = []

var injuries: InjurySystem
var region := ""
var arterial := false
var severed := false
var _age := 0.0
var _drip_t := 0.0
var _beat := 0.0
## The wounded man's own bodies: his blood lands on the world, not inside him.
var _exclude: Array[RID] = []


## Attaches a source to [param body] at world [param point] with outward
## [param normal]. Returns null when blood is off or the budget is full of
## fresher, stronger wounds.
static func attach(body: RigidBody3D, point: Vector3, normal: Vector3, inj: InjurySystem, reg: String,
		blow_dir: Vector3, severity: float, is_severed := false) -> BleedingSource:
	if not CombatFX.blood_enabled or not is_instance_valid(body):
		return null
	var cap := MAX_ACTIVE_HIGH if CombatFX.quality_high else MAX_ACTIVE_LOW
	_active = _active.filter(func(s): return is_instance_valid(s))
	# A second wound close to an existing one on the same body feeds it.
	for s in _active:
		if s.get_parent() == body and s.global_position.distance_to(point) < 0.07:
			s._age = 0.0
			CombatFX.spray(point, (blow_dir + normal).normalized(), severity)
			return s
	while _active.size() >= cap:
		var oldest: BleedingSource = _active.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var src := BleedingSource.new()
	src.injuries = inj
	src.region = reg
	src.severed = is_severed
	src.arterial = is_severed or reg in ["neck", "thigh_l", "thigh_r"]
	body.add_child(src)
	var n := normal.normalized() if normal.length_squared() > 0.01 else -blow_dir.normalized()
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	src.global_transform = Transform3D(Basis.looking_at(-n, up), point)
	src.reset_physics_interpolation()
	_active.append(src)
	# The impact spray goes with the blow and off the wound.
	CombatFX.spray(point, (blow_dir.normalized() * 0.7 + n * 0.5).normalized(), severity)
	return src


func _rate() -> float:
	if not injuries or region == "":
		return 0.0
	return float(injuries.regions[region]["bleed"])


func _physics_process(delta: float) -> void:
	_age += delta
	var rate := _rate()
	if not CombatFX.blood_enabled or _age > MAX_AGE or (rate < 0.05 and _age > 3.0):
		queue_free()
		return
	var out := global_basis.z  # outward from the wound
	if arterial and rate > 0.6:
		# Heartbeat: ~1.2 Hz, spurt strength falling with blood volume and
		# the wound's own clotting.
		_beat += delta * 1.2 * lerpf(0.6, 1.0, injuries.blood)
		if _beat >= 1.0:
			_beat -= 1.0
			var strength := clampf(rate / 3.0, 0.15, 1.0) * injuries.blood
			var dir := (out + Vector3(randf_range(-0.2, 0.2), randf_range(0.0, 0.25), randf_range(-0.2, 0.2))).normalized()
			CombatFX.spurt(global_position, dir, strength)
			_land(global_position, dir * lerpf(1.5, 3.5, strength))
	# Drops: more often as the wound bleeds harder.
	_drip_t -= delta
	if _drip_t <= 0.0 and rate > 0.05:
		_drip_t = clampf(1.2 / rate, 0.25, 2.5) * randf_range(0.7, 1.3)
		CombatFX.drip(global_position)
		_land(global_position, Vector3.ZERO)


## Where blood leaving at [param from] with [param v0] lands: a short
## ballistic ray march (a few segments, one ray each) against the world and
## bodies, then a pooled splat on the surface hit.
func _land(from: Vector3, v0: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	if _exclude.is_empty():
		var body := get_parent()
		if body and body.has_meta(&"kickback_actor"):
			for b: RigidBody3D in (body.get_meta(&"kickback_actor") as KickbackActor).get_rig_bodies().values():
				_exclude.append(b.get_rid())
	var p := from
	var v := v0
	for i in 5:
		var nxt := p + v * 0.12 + Vector3.DOWN * 0.5 * 9.8 * 0.0144
		v += Vector3.DOWN * 9.8 * 0.12
		var q := PhysicsRayQueryParameters3D.create(p, nxt, 1 | KickbackLayers.ACTIVE_RAGDOLL_LAYER)
		q.exclude = _exclude
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			_splat_later(0.12 * (i + 1), hit["position"], hit["normal"], clampf(v0.length() / 4.0 + 0.2, 0.15, 0.6))
			return
		p = nxt
	# Still falling: find the floor straight below.
	var q2 := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 3.0, 1)
	var hit2 := space.intersect_ray(q2)
	if not hit2.is_empty():
		var fall := sqrt(2.0 * maxf(from.y - float(hit2["position"].y), 0.01) / 9.8)
		_splat_later(fall, hit2["position"], hit2["normal"], 0.2)


## The mark appears when the blood gets there, not when it leaves.
func _splat_later(t: float, pos: Vector3, normal: Vector3, size: float) -> void:
	get_tree().create_timer(t).timeout.connect(func(): CombatFX.splat_at(pos, normal, size))
