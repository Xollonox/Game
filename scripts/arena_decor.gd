extends Node3D
## Builds the arena shell — floor, perimeter wall, pillars, props and torches.
##
## Generated in code rather than authored into arena.tscn because it's all
## repeated primitives placed on a ring: as a scene it would be ~120 nodes of
## copy-pasted transforms that nobody can adjust without re-editing every one,
## whereas here the whole layout falls out of a handful of constants.
##
## Everything static shares one mesh and one material per prop type, so the
## renderer batches it. That matters more than usual here: the web build runs
## through gl_compatibility, where draw-call overhead is the ceiling long
## before triangle count is.

const ARENA_RADIUS := 13.0
const WALL_SEGMENTS := 28
const WALL_HEIGHT := 3.2
const PILLAR_COUNT := 8
const PILLAR_RADIUS := 11.0
const TORCH_COUNT := 6
const CRATE_COUNT := 11

## Flicker is per-torch so they don't pulse in unison, which reads as a global
## brightness wobble rather than fire.
const FLICKER_HZ := 7.0
const FLICKER_DEPTH := 0.22

var _torches: Array[OmniLight3D] = []
var _torch_phase: PackedFloat32Array = []
var _torch_base: PackedFloat32Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Fixed seed: the layout should be the same arena every run, not a new one
	# each launch — otherwise no two playtests or vision tests are comparable.
	_rng.seed = 7741

	var stone := _material(Color(0.30, 0.29, 0.27), 0.92)
	var dark_stone := _material(Color(0.20, 0.19, 0.18), 0.95)
	var wood := _material(Color(0.24, 0.16, 0.09), 0.85)

	_build_floor(dark_stone)
	_build_wall(stone)
	_build_pillars(dark_stone)
	_build_crates(wood)
	_build_torches()
	_build_cc0_props()


func _process(delta: float) -> void:
	for i in _torches.size():
		_torch_phase[i] += delta * FLICKER_HZ
		# Two out-of-step sines beat against each other, which reads closer to
		# firelight than a single sine or pure noise.
		var f := sin(_torch_phase[i]) * 0.6 + sin(_torch_phase[i] * 2.37) * 0.4
		_torches[i].light_energy = _torch_base[i] * (1.0 + f * FLICKER_DEPTH)


func _build_floor(mat: Material) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = ARENA_RADIUS
	disc.bottom_radius = ARENA_RADIUS
	disc.height = 0.3
	disc.radial_segments = 48
	disc.material = mat

	var m := MeshInstance3D.new()
	m.mesh = disc
	# Sunk so its top face sits a hair under y=0, where the ground plane's
	# collision already is — the disc is dressing, not a second floor.
	m.position = Vector3(0.0, -0.16, 0.0)
	add_child(m)


func _build_wall(mat: Material) -> void:
	var block := BoxMesh.new()
	block.size = Vector3(3.0, WALL_HEIGHT, 0.8)
	block.material = mat

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	for i in WALL_SEGMENTS:
		var a := TAU * float(i) / float(WALL_SEGMENTS)
		var pos := Vector3(cos(a), 0.0, sin(a)) * ARENA_RADIUS
		# Slight per-block jitter so the ring reads as stacked stone rather
		# than an extruded cylinder.
		var h := WALL_HEIGHT + _rng.randf_range(-0.35, 0.35)
		var xf := Transform3D(Basis(Vector3.UP, -a + PI * 0.5), pos + Vector3.UP * (h * 0.5 - 0.2))
		xf = xf.scaled_local(Vector3(1.0, h / WALL_HEIGHT, 1.0))

		var m := MeshInstance3D.new()
		m.mesh = block
		m.transform = xf
		body.add_child(m)

		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = block.size
		shape.shape = box
		shape.transform = xf
		body.add_child(shape)


func _build_pillars(mat: Material) -> void:
	var col := CylinderMesh.new()
	col.top_radius = 0.34
	col.bottom_radius = 0.42
	col.height = 4.6
	col.radial_segments = 10
	col.material = mat

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	for i in PILLAR_COUNT:
		var a := TAU * float(i) / float(PILLAR_COUNT) + 0.19
		var pos := Vector3(cos(a), 2.3, sin(a)) * Vector3(PILLAR_RADIUS, 1.0, PILLAR_RADIUS)

		var m := MeshInstance3D.new()
		m.mesh = col
		m.position = pos
		body.add_child(m)

		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.42
		cyl.height = 4.6
		shape.shape = cyl
		shape.position = pos
		body.add_child(shape)


func _build_crates(mat: Material) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	for i in CRATE_COUNT:
		var s := _rng.randf_range(0.5, 0.95)
		var cube := BoxMesh.new()
		cube.size = Vector3(s, s, s)
		cube.material = mat

		# Pushed out past the fighting area so props dress the space without
		# becoming obstacles in the middle of a duel.
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(6.0, ARENA_RADIUS - 1.6)
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU),
			Vector3(cos(a) * d, s * 0.5, sin(a) * d))

		var m := MeshInstance3D.new()
		m.mesh = cube
		m.transform = xf
		body.add_child(m)

		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = cube.size
		shape.shape = box
		shape.transform = xf
		body.add_child(shape)


func _build_torches() -> void:
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = Color(1.0, 0.62, 0.22)

	var flame := SphereMesh.new()
	flame.radius = 0.11
	flame.height = 0.3
	flame.radial_segments = 8
	flame.rings = 4
	flame.material = flame_mat

	for i in TORCH_COUNT:
		var a := TAU * float(i) / float(TORCH_COUNT) + 0.4
		var pos := Vector3(cos(a), 2.6, sin(a)) * Vector3(ARENA_RADIUS - 1.2, 1.0, ARENA_RADIUS - 1.2)

		var m := MeshInstance3D.new()
		m.mesh = flame
		m.position = pos
		add_child(m)

		var light := OmniLight3D.new()
		light.position = pos
		light.light_color = Color(1.0, 0.64, 0.32)
		light.light_energy = 3.2
		light.omni_range = 11.0
		# Torches are atmosphere, not the shadow-casting key light — six
		# shadow-casting omnis would cost more than the whole rest of the scene
		# on the web build.
		light.shadow_enabled = false
		add_child(light)

		_torches.append(light)
		_torch_phase.append(_rng.randf() * TAU)
		_torch_base.append(light.light_energy)


func _build_cc0_props() -> void:
	var specs := [
		["res://assets/models/props/town/banner-red.glb", Vector3(-8.5, 1.8, -8.0), 0.5, 0.0],
		["res://assets/models/props/town/banner-green.glb", Vector3(8.5, 1.8, -8.0), 0.5, 0.0],
		["res://assets/models/props/town/cart.glb", Vector3(8.2, 0.0, 5.0), 1.0, -1.0],
		["res://assets/models/props/town/fence.glb", Vector3(-9.0, 0.0, 4.2), 1.0, 0.3],
		["res://assets/models/props/survival/campfire-pit.glb", Vector3(-7.0, 0.0, 6.2), 1.0, 0.0],
		["res://assets/models/props/survival/chest.glb", Vector3(7.5, 0.0, -5.0), 1.0, 0.5],
		["res://assets/models/props/survival/barrel.glb", Vector3(7.0, 0.0, -6.0), 1.0, 0.0],
		["res://assets/models/props/survival/box-large.glb", Vector3(8.0, 0.0, -6.1), 1.0, 0.2],
		["res://assets/models/props/survival/bucket.glb", Vector3(-6.3, 0.0, 6.0), 1.0, 0.0],
		["res://assets/models/props/castle/rocks-large.glb", Vector3(-8.0, 0.0, -5.8), 1.0, 0.0],
		["res://assets/models/props/castle/rocks-small.glb", Vector3(6.5, 0.0, 7.0), 1.0, 0.0],
	]
	for s in specs:
		if not ResourceLoader.exists(s[0]): continue
		var prop := (load(s[0]) as PackedScene).instantiate()
		prop.position = s[1]
		prop.scale = Vector3.ONE * s[2]
		prop.rotation.y = s[3]
		add_child(prop)


static func _material(albedo: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = roughness
	m.metallic = 0.0
	return m
