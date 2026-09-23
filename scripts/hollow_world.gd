extends WorldBuilder
## The Hollow: where the tournament's dead wait for the one who put them there.
##
## Built from the same kit as the yard, deliberately: it is the yard drowned
## and emptied — the gatehouse sunk to its arch in black mud, walls reduced to
## a broken ring, palisade stakes leaning like grave markers, and cold
## soul-fires where the braziers burned. The palette is inverted too: no warm
## light at all, a low blue moon, heavy fog and ash drifting upward.

var _ash: CPUParticles3D
var _souls: Array[OmniLight3D] = []
var _t := 0.0


func _ready() -> void:
	_rng.seed = 666
	_build_hollow_ground()
	_build_ring()
	_build_drowned_gate()
	_build_markers()
	_build_soulfires()
	_build_ash()
	_batch_static()


func _process(delta: float) -> void:
	_t += delta
	for i in _souls.size():
		var l := _souls[i]
		l.light_energy = 0.9 + sin(_t * 2.3 + i * 1.7) * 0.25 + sin(_t * 5.1 + i) * 0.1


func _build_hollow_ground() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.17, 0.19, 0.21)
	m.roughness = 0.35
	m.metallic_specular = 0.6
	var base := WorldMaterials.get_material("M_Mud")
	m.albedo_texture = base.albedo_texture
	m.normal_enabled = base.normal_enabled
	m.normal_texture = base.normal_texture
	m.uv1_scale = Vector3(0.3, 0.3, 0.3)
	var disc := CylinderMesh.new()
	disc.top_radius = 60.0
	disc.bottom_radius = 60.0
	disc.height = 0.04
	disc.radial_segments = 48
	disc.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = disc
	mi.position = Vector3(0, 0.01, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Standing water: a still black mirror in the low ground around the ring.
	for i in 7:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(12.0, 22.0)
		place("puddle", Vector3(cos(a) * r, 0.02, sin(a) * r), _rng.randf() * TAU, self, false, _rng.randf_range(2.5, 4.5))


func _build_ring() -> void:
	# A broken circle of wall around the fighting ground, sunk and leaning.
	var n := 11
	for i in n:
		if i in [0, 6]:
			continue  # gaps where the dead come through
		var a := TAU * i / n
		var r := 12.5 + _rng.randf_range(-0.6, 0.6)
		var pos := Vector3(sin(a) * r, _rng.randf_range(-0.9, -0.3), -cos(a) * r)
		var piece := place("wall_broken" if _rng.randf() < 0.7 else "wall_straight", pos, -a, self, true)
		if piece:
			piece.rotation.z = _rng.randf_range(-0.12, 0.12)
			piece.rotation.x = _rng.randf_range(-0.08, 0.08)
	for i in 5:
		var a := TAU * (i + 0.5) / 5.0 + 0.3
		place("rubble_pile", Vector3(sin(a) * 10.5, 0, -cos(a) * 10.5), _rng.randf() * TAU, self, false, 1.3)
	# Monoliths: stretched rock, the only tall shapes on the horizon.
	for i in 6:
		var a := TAU * i / 6.0 + 0.4
		var r := _rng.randf_range(17.0, 26.0)
		var rock := place(["rock_a", "rock_b", "rock_c"][i % 3], Vector3(sin(a) * r, -0.2, -cos(a) * r), _rng.randf() * TAU,
			self, false, 1.0)
		if rock:
			rock.scale = Vector3(1.6, _rng.randf_range(3.5, 6.0), 1.4)


func _build_drowned_gate() -> void:
	var g := place("gatehouse", Vector3(0, -2.6, -27), 0.0, self, false)
	if g:
		g.rotation.z = 0.06
		g.rotation.x = -0.05
	for i in 2:
		var t := place("tower_round", Vector3(-11 + i * 22, -3.5, -24), 0.0, self, false)
		if t:
			t.rotation.z = (-0.12 if i == 0 else 0.1)


func _build_markers() -> void:
	# Palisade stakes and fence rails leaning out of the mud like grave marks,
	# one cluster per gap in the ring.
	for c in [Vector3(0, 0, -15.5), Vector3(0, 0, 15.5), Vector3(-15, 0, 4), Vector3(15, 0, -4)]:
		for k in 4:
			var p: Vector3 = c + Vector3(_rng.randf_range(-3, 3), -0.3, _rng.randf_range(-1.5, 1.5))
			var s := place("palisade_section" if k % 2 == 0 else "fence_section", p, _rng.randf() * TAU, self, false)
			if s:
				s.rotation.z = _rng.randf_range(-0.35, 0.35)
	place("cage", Vector3(-7.5, -0.1, -9.5), 0.6, self, true)
	place("weapon_rack", Vector3(8.2, -0.05, -8.8), -0.8, self, true)
	place("cart", Vector3(9.5, -0.35, 7.5), 2.2, self, true)


func _build_soulfires() -> void:
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var pos := Vector3(sin(a) * 9.6, 0, -cos(a) * 9.6)
		place("brazier", pos, 0.0, self, true)
		var l := OmniLight3D.new()
		l.light_color = Color(0.45, 0.7, 0.95)
		l.omni_range = 9.0
		l.light_energy = 1.0
		l.position = pos + Vector3.UP * 1.25
		add_child(l)
		_souls.append(l)
		var f := CPUParticles3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.18, 0.28)
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		fm.albedo_color = Color(0.5, 0.78, 1.0, 0.55)
		q.material = fm
		f.mesh = q
		f.amount = 22
		f.lifetime = 1.1
		f.direction = Vector3.UP
		f.spread = 12.0
		f.initial_velocity_min = 0.4
		f.initial_velocity_max = 1.0
		f.gravity = Vector3(0, 0.6, 0)
		f.scale_amount_min = 0.5
		f.scale_amount_max = 1.2
		f.position = pos + Vector3.UP * 1.05
		add_child(f)


func _build_ash() -> void:
	_ash = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.025)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.75, 0.8, 0.85, 0.5)
	q.material = m
	_ash.mesh = q
	_ash.amount = 260
	_ash.lifetime = 9.0
	_ash.preprocess = 9.0
	_ash.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_ash.emission_box_extents = Vector3(16, 0.5, 16)
	_ash.direction = Vector3.UP
	_ash.spread = 25.0
	_ash.initial_velocity_min = 0.15
	_ash.initial_velocity_max = 0.45
	_ash.gravity = Vector3(0.05, 0.04, 0.0)
	_ash.position = Vector3(0, 0.3, 0)
	add_child(_ash)
