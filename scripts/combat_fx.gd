extends Node3D
## Autoloaded combat feedback: blood, impact audio, hit-stop and camera shake.
##
## Everything here is pooled and built in code rather than authored as scenes,
## because the pools need to exist before the first hit lands and a hit can
## come from any actor — routing them all through one node keeps the per-hit
## cost to "grab the next free emitter" instead of instancing under load.
##
## Deliberately CPUParticles3D and plain quad meshes, not GPUParticles3D or
## Decal: the web build renders through gl_compatibility (WebGL 2.0), where
## Decal needs the clustered renderer and isn't drawn at all. These draw
## identically on desktop and in the browser.

signal shake_requested(strength: float)

const BURST_POOL := 10
const SPLAT_POOL := 36
const AUDIO_POOL := 10
const SPLAT_LIFETIME := 22.0

const HIT_SOUNDS := [
	"res://assets/sfx/impacts/hits_punches/hits/hit03.ogg",
	"res://assets/sfx/impacts/hits_punches/hits/hit07.ogg",
	"res://assets/sfx/impacts/hits_punches/hits/hit11.ogg",
	"res://assets/sfx/impacts/hits_punches/hits/hit15.ogg",
	"res://assets/sfx/impacts/hits_punches/hits/hit19.ogg",
	"res://assets/sfx/impacts/hits_punches/hits/hit24.ogg",
	"res://assets/sfx/impacts/hits_punches/hits/hit29.ogg",
	"res://assets/sfx/impacts/hits_punches/hits/hit33.ogg",
]
const SWISH_SOUNDS := [
	"res://assets/sfx/battle/battle_sfx/battle_sound_effects/swish_2.wav",
	"res://assets/sfx/battle/battle_sfx/battle_sound_effects/swish_3.wav",
	"res://assets/sfx/battle/battle_sfx/battle_sound_effects/swish_4.wav",
]
const CLASH_SOUNDS := [
	"res://assets/sfx/kenney/metal/impactPlate_heavy_000.ogg",
	"res://assets/sfx/kenney/metal/impactPlate_heavy_001.ogg",
	"res://assets/sfx/kenney/metal/impactPlate_heavy_002.ogg",
]
const FOOTSTEP_SOUNDS := [
	"res://assets/sfx/kenney/footsteps/footstep_concrete_000.ogg",
	"res://assets/sfx/kenney/footsteps/footstep_concrete_001.ogg",
	"res://assets/sfx/kenney/footsteps/footstep_concrete_002.ogg",
	"res://assets/sfx/kenney/footsteps/footstep_concrete_003.ogg",
]

var _bursts: Array[CPUParticles3D] = []
var _sparks: Array[CPUParticles3D] = []
var _next_spark := 0
var _next_burst := 0
var _splats: Array[MeshInstance3D] = []
var _splat_expiry: Array[float] = []
var _next_splat := 0
var _players: Array[AudioStreamPlayer3D] = []
var _next_player := 0

var _hit_streams: Array[AudioStream] = []
var _swish_streams: Array[AudioStream] = []
var _clash_streams: Array[AudioStream] = []
var _footstep_streams: Array[AudioStream] = []
## Public so the arena can honour the player's Blood setting.
var blood_enabled := true
## Public so the arena can honour the Quality setting (particle budgets).
var quality_high := true
var _rng := RandomNumberGenerator.new()

## Hit-stop deadline in *real* milliseconds. Engine.time_scale is what produces
## the stop, so anything that counts it down off `delta` would freeze with the
## rest of the game and never restore. Time.get_ticks_msec() ignores time_scale.
var _hitstop_until_ms := 0


func _ready() -> void:
	_rng.randomize()
	blood_enabled = not OS.get_cmdline_user_args().has("--noblood")
	var blood_tex := _make_blood_texture()
	_build_bursts()
	_build_sparks()
	_build_splats(blood_tex)
	_build_audio()
	for path in HIT_SOUNDS:
		if ResourceLoader.exists(path):
			_hit_streams.append(load(path))
	for path in SWISH_SOUNDS:
		if ResourceLoader.exists(path): _swish_streams.append(load(path))
	for path in CLASH_SOUNDS:
		if ResourceLoader.exists(path): _clash_streams.append(load(path))
	for path in FOOTSTEP_SOUNDS:
		if ResourceLoader.exists(path): _footstep_streams.append(load(path))


func _process(_delta: float) -> void:
	if _hitstop_until_ms > 0 and Time.get_ticks_msec() >= _hitstop_until_ms:
		_hitstop_until_ms = 0
		Engine.time_scale = 1.0

	var now := float(Time.get_ticks_msec()) * 0.001
	for i in _splats.size():
		if _splat_expiry[i] > 0.0 and now >= _splat_expiry[i]:
			_splats[i].visible = false
			_splat_expiry[i] = 0.0


## The one call sites use: everything a landed hit should produce, scaled by
## [param severity] (0 = graze, 1 = crushing). [param dir] is the direction the
## blow travelled, so spray goes with the swing rather than straight up.
func impact(pos: Vector3, dir: Vector3, severity: float) -> void:
	severity = clampf(severity, 0.0, 1.0)
	spray(pos, dir, severity)
	play_hit(pos, severity)
	shake_requested.emit(lerpf(0.25, 1.0, severity))
	# Only the heavy end of the range gets hit-stop: on every connect it reads
	# as the game stuttering, on the big ones it reads as weight.
	if severity >= 0.5:
		hitstop(lerpf(0.045, 0.11, (severity - 0.5) / 0.5), 0.05)


## Blood burst plus a ground splat under the impact.
func spray(pos: Vector3, dir: Vector3, severity: float) -> void:
	if not blood_enabled:
		return
	if _bursts.is_empty():
		return
	var p := _bursts[_next_burst]
	_next_burst = (_next_burst + 1) % _bursts.size()
	p.global_position = pos
	p.direction = dir.normalized() if dir.length_squared() > 0.001 else Vector3.UP
	p.amount = int(lerpf(10.0, 44.0, severity) * (1.0 if quality_high else 0.55))
	p.initial_velocity_min = lerpf(1.2, 3.0, severity)
	p.initial_velocity_max = lerpf(3.5, 9.0, severity)
	p.scale_amount_min = lerpf(0.018, 0.03, severity)
	p.scale_amount_max = lerpf(0.05, 0.10, severity)
	p.restart()
	p.emitting = true
	_ground_splat(pos, severity)


## Swing whoosh — pitched by how fast the blade is actually moving.
func play_swish(pos: Vector3, speed_ratio: float) -> void:
	if _swish_streams.is_empty():
		return
	var pl := _take_player()
	pl.stream = _swish_streams[_rng.randi() % _swish_streams.size()]
	pl.global_position = pos
	pl.pitch_scale = lerpf(0.82, 1.25, clampf(speed_ratio, 0.0, 1.0))
	pl.volume_db = -8.0
	pl.play()


func play_hit(pos: Vector3, severity: float) -> void:
	if _hit_streams.is_empty():
		return
	var pl := _take_player()
	pl.stream = _hit_streams[_rng.randi() % _hit_streams.size()]
	pl.global_position = pos
	# Heavier hits read lower and louder.
	pl.pitch_scale = lerpf(1.25, 0.78, severity) * _rng.randf_range(0.95, 1.05)
	pl.volume_db = lerpf(-10.0, 2.0, severity)
	pl.play()


## Weapon-on-weapon clash (PLAN.md Phase 5, "clash on weapon-weapon contact"):
## the impact set brightened and softened — at this asset fidelity the punch
## set pitched past 1.5x reads as metal-on-metal, and it keeps the asset ledger
## unchanged.
func play_clash(pos: Vector3, intensity: float, wooden := false) -> void:
	if _clash_streams.is_empty(): return
	var pl := _take_player()
	if wooden and not _hit_streams.is_empty():
		# Steel into a shield board or a haft: a dull knock, not a ring.
		pl.stream = _hit_streams[_rng.randi() % _hit_streams.size()]
		pl.global_position = pos
		pl.pitch_scale = lerpf(0.9, 0.7, clampf(intensity, 0.0, 1.0)) * _rng.randf_range(0.95, 1.05)
		pl.volume_db = lerpf(-10.0, -1.0, clampf(intensity, 0.0, 1.0))
		pl.play()
		return
	pl.stream = _clash_streams[_rng.randi() % _clash_streams.size()]
	pl.global_position = pos
	pl.pitch_scale = lerpf(1.05, 0.82, clampf(intensity, 0.0, 1.0)) * _rng.randf_range(0.96, 1.04)
	pl.volume_db = lerpf(-12.0, -3.0, clampf(intensity, 0.0, 1.0))
	pl.play()


func play_footstep(pos: Vector3, worn_weight := 0.0) -> void:
	if _footstep_streams.is_empty(): return
	var pl := _take_player()
	pl.stream = _footstep_streams[_rng.randi() % _footstep_streams.size()]
	pl.global_position = pos
	pl.pitch_scale = _rng.randf_range(0.92, 1.08)
	pl.volume_db = -14.0
	pl.play()
	# Armour layer: a fighter in plate is never silent. One in three steps also
	# rings a quiet plate impact, pitched out of the clash set — same asset
	# ledger, and it is what makes the fighters read as armoured.
	if not _clash_streams.is_empty() and worn_weight > 12.0 and _rng.randf() < clampf(worn_weight / 45.0, 0.2, 0.8):
		var metal := _take_player()
		metal.stream = _clash_streams[_rng.randi() % _clash_streams.size()]
		metal.global_position = pos
		metal.pitch_scale = _rng.randf_range(1.35, 1.6)
		metal.volume_db = lerpf(-24.0, -15.0, clampf(worn_weight / 45.0, 0.0, 1.0))
		metal.play()


## Steel struck on steel: a spray of sparks, a hard ring, a short shake.
func armor_impact(pos: Vector3, dir: Vector3, intensity: float, layer: String) -> void:
	var metal := layer.begins_with("A_") or layer.begins_with("H_")
	if metal and layer != "A_Gambeson" and layer != "H_PaddedCoif":
		sparks(pos, dir, intensity)
		play_clash(pos, clampf(intensity * 1.2, 0.2, 1.0))
	else:
		play_hit(pos, intensity * 0.5)


func sparks(pos: Vector3, dir: Vector3, intensity: float) -> void:
	if _sparks.is_empty():
		return
	var p := _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % _sparks.size()
	p.global_position = pos
	p.direction = (-dir + Vector3.UP * 0.4).normalized()
	p.amount = int(lerpf(8.0, 26.0, intensity) * (1.0 if quality_high else 0.5))
	p.restart()
	p.emitting = true


func _build_sparks() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.72, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.25)
	mat.emission_energy_multiplier = 3.0
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.035)
	quad.material = mat
	for i in 6:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 0.95
		p.lifetime = 0.35
		p.mesh = quad
		p.spread = 55.0
		p.initial_velocity_min = 2.5
		p.initial_velocity_max = 6.5
		p.gravity = Vector3(0, -9.8, 0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.3
		add_child(p)
		_sparks.append(p)


## Drops Engine.time_scale for [param duration] real seconds. Re-entrant: a
## bigger hit landing mid-stop extends it rather than cutting it short.
func hitstop(duration: float, scale: float) -> void:
	var until := Time.get_ticks_msec() + int(duration * 1000.0)
	if until <= _hitstop_until_ms:
		return
	_hitstop_until_ms = until
	Engine.time_scale = scale


func _ground_splat(pos: Vector3, severity: float) -> void:
	if _splats.is_empty():
		return
	var idx := _next_splat
	_next_splat = (_next_splat + 1) % _splats.size()
	var s := _splats[idx]
	var size := lerpf(0.35, 1.05, severity)
	s.scale = Vector3(size, size, size)
	# Land it on the ground under the hit, lifted a hair to avoid z-fighting
	# with the ground plane.
	s.global_position = Vector3(
		pos.x + _rng.randf_range(-0.25, 0.25),
		0.012,
		pos.z + _rng.randf_range(-0.25, 0.25))
	s.rotation = Vector3(-PI * 0.5, 0.0, _rng.randf() * TAU)
	s.visible = true
	_splat_expiry[idx] = float(Time.get_ticks_msec()) * 0.001 + SPLAT_LIFETIME


func _take_player() -> AudioStreamPlayer3D:
	var pl := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	return pl


func _build_bursts() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# Billboarding rebuilds the model-view basis from scratch, which throws away
	# each particle's own scale unless this is set — without it every droplet
	# draws at the quad's full 1 m size and the spray renders as a wall of flat
	# red squares (caught in the first vision test, invisible to state checks).
	mat.billboard_keep_scale = true
	mat.disable_receive_shadows = true
	# Without this the quads render as hard-edged squares — unmistakably
	# rectangles of red rather than droplets, even at 3 cm.
	mat.albedo_texture = _make_droplet_texture()

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat

	# CPUParticles3D.color_ramp is a Gradient itself, unlike the texture a
	# ParticleProcessMaterial would want.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.62, 0.03, 0.03, 1.0))
	ramp.set_color(1, Color(0.22, 0.01, 0.01, 0.0))

	for i in BURST_POOL:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 0.92
		p.lifetime = 1.1
		p.local_coords = false
		p.spread = 38.0
		p.gravity = Vector3(0.0, -11.0, 0.0)
		p.damping_min = 0.4
		p.damping_max = 1.6
		p.mesh = quad
		p.color_ramp = ramp
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.06
		add_child(p)
		_bursts.append(p)


func _build_splats(tex: Texture2D) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat

	for i in SPLAT_POOL:
		var m := MeshInstance3D.new()
		m.mesh = quad
		m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		_splats.append(m)
		_splat_expiry.append(0.0)


func _build_audio() -> void:
	for i in AUDIO_POOL:
		var pl := AudioStreamPlayer3D.new()
		pl.unit_size = 6.0
		pl.max_distance = 35.0
		add_child(pl)
		_players.append(pl)


## Soft round falloff, white so the particle's own colour tints it.
static func _make_droplet_texture() -> ImageTexture:
	const SIZE := 32
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var centre := Vector2(SIZE * 0.5, SIZE * 0.5)
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(centre) / (SIZE * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 0.75)))
	return ImageTexture.create_from_image(img)


## Procedural splat: one core blob with a ring of smaller satellites, so it
## reads as spatter rather than a circle. Generated instead of shipped as art
## because it's a handful of distance tests at startup and keeps the repo free
## of another asset to license-track.
static func _make_blood_texture() -> ImageTexture:
	const SIZE := 96
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260922
	var centre := Vector2(SIZE * 0.5, SIZE * 0.5)
	var blobs: Array = [[centre, SIZE * 0.24]]
	for i in 9:
		var a := rng.randf() * TAU
		var d := rng.randf_range(SIZE * 0.14, SIZE * 0.36)
		blobs.append([centre + Vector2(cos(a), sin(a)) * d, rng.randf_range(SIZE * 0.05, SIZE * 0.14)])

	for y in SIZE:
		for x in SIZE:
			var p := Vector2(x + 0.5, y + 0.5)
			var best := 0.0
			for b in blobs:
				var falloff: float = 1.0 - clampf(p.distance_to(b[0]) / b[1], 0.0, 1.0)
				best = maxf(best, falloff)
			if best > 0.0:
				img.set_pixel(x, y, Color(0.34, 0.02, 0.02, pow(best, 0.65)))
	return ImageTexture.create_from_image(img)
