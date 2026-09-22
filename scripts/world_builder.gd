class_name WorldBuilder
extends Node3D
## Builds the lived-in medieval fighting ground: perimeter walls, a gatehouse
## landmark, viewing stands, terrain dressing and prop clusters.
##
## Everything visible comes from the headless-Blender kit in
## `assets/models/world/kit/` (see `tools/blender/build_world_kit.py`) so the
## world is modular and reusable rather than a pile of one-off meshes.
##
## Composition rules this file follows:
## - The fighting ring (r < 7) stays clear; every prop lives outside it.
## - Landmarks stack: gatehouse (north) > towers (corners) > stands (east/west)
##   > sheds/props > scatter, so the eye always has somewhere to land.
## - Clutter is clustered, never evenly sprinkled: carts/crates sit together by
##   the gate, training gear sits by the stands, camp gear sits by the fire.
##
## Performance shape: the world is ~200 kit instances, which as individual
## MeshInstance3D nodes is ~1000 draw calls — the wrong budget to spend on the
## web renderer, where draw-call overhead dominates and the pieces never move.
## `_batch_static()` merges them into one surface per shared material, and the
## colliders are re-parented out first so physics is untouched.

const RING_RADIUS := 9.0
const WALL_RADIUS := 15.0

var _rng := RandomNumberGenerator.new()
var _kit_cache: Dictionary = {}
var _placed: Array[Node3D] = []
var _braziers: Array[OmniLight3D] = []
var _brazier_phase: PackedFloat32Array = []
var _brazier_base: PackedFloat32Array = []
var _banners: Array[Node3D] = []
var _time := 0.0


func _ready() -> void:
	_rng.seed = 4242
	_build_ground()
	_build_perimeter()
	_build_stands()
	_build_gate_area()
	_build_training_area()
	_build_camp_area()
	_build_terrain_dressing()
	_build_background()
	_build_fires()
	_batch_static()


func _process(delta: float) -> void:
	# Firelight flicker, two out-of-step sines per brazier so they never pulse
	# in unison (which reads as a global brightness wobble, not fire).
	for i in _braziers.size():
		_brazier_phase[i] += delta * 6.5
		var f := sin(_brazier_phase[i]) * 0.6 + sin(_brazier_phase[i] * 2.31) * 0.4
		_braziers[i].light_energy = _brazier_base[i] * (1.0 + f * 0.24)

	# Cloth moves: banners lean into a slow breeze so the yard never reads as
	# a still frame. Rotation only — no deformation, so it costs nothing.
	_time += delta
	for i in _banners.size():
		var b := _banners[i]
		if b == null:
			continue
		b.rotation.z = sin(_time * 1.1 + float(i) * 1.7) * 0.022
		b.rotation.x = sin(_time * 0.7 + float(i) * 0.9) * 0.016


# ------------------------------------------------------------------ kit -----
## Instantiates a kit piece, dresses it with shared materials, optionally gives
## it a box collider sized from its bounds, and parents it to [param into].
## Pieces marked [param dynamic] (banners, which sway) are exempt from static
## batching because their transforms keep changing.
func place(name: String, pos: Vector3, rot_y := 0.0, into: Node3D = self,
		collide := false, scale := 1.0, lod := "", dynamic := false) -> Node3D:
	var use := name if lod == "" else name + lod
	if not _kit_cache.has(use):
		var path := "res://assets/models/world/kit/%s.glb" % use
		if not ResourceLoader.exists(path):
			return null
		_kit_cache[use] = load(path)
	var inst: Node3D = (_kit_cache[use] as PackedScene).instantiate()
	inst.position = pos
	inst.rotation.y = rot_y
	if scale != 1.0:
		inst.scale = Vector3.ONE * scale
	into.add_child(inst)
	WorldMaterials.dress(inst)
	if collide:
		_add_box_collision(inst)
	if not dynamic:
		_placed.append(inst)
	return inst


func _add_box_collision(inst: Node3D) -> void:
	var aabb := _instance_aabb(inst)
	if aabb.size.length_squared() < 0.001:
		return
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size
	shape.shape = box
	shape.position = aabb.get_center()
	body.add_child(shape)
	inst.add_child(body)


func _instance_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		var a := m.get_aabb()
		# Mesh AABB is in mesh space; kit pieces have identity mesh transforms,
		# so only the root scale matters here.
		a.position *= root.scale
		a.size *= root.scale
		merged = a if first else merged.merge(a)
		first = false
	return merged


## Static batching: merge every non-dynamic kit piece into one surface per
## shared material. Colliders are re-parented to a sibling node first (keeping
## their world transforms), so the physics shape of the yard is unchanged.
func _batch_static() -> void:
	var batches: Dictionary = {}
	for inst in _placed:
		if not is_instance_valid(inst):
			continue
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var node := mi as MeshInstance3D
			var mesh := node.mesh
			if mesh == null:
				continue
			var xf := node.global_transform
			for s in mesh.get_surface_count():
				var mat: Material = node.get_surface_override_material(s)
				if mat == null:
					mat = mesh.surface_get_material(s)
				if mat == null:
					continue
				if not batches.has(mat):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					batches[mat] = st
				(batches[mat] as SurfaceTool).append_from(mesh, s, xf)

	# Preserve collision: move the static bodies out before freeing the visuals.
	var collider_root := Node3D.new()
	collider_root.name = "Colliders"
	add_child(collider_root)
	for inst in _placed:
		if not is_instance_valid(inst):
			continue
		for child in inst.get_children():
			if child is StaticBody3D:
				child.reparent(collider_root, true)
	for inst in _placed:
		if is_instance_valid(inst):
			inst.free()
	_placed.clear()

	var batched := Node3D.new()
	batched.name = "Batched"
	add_child(batched)
	for mat in batches:
		var st: SurfaceTool = batches[mat]
		st.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		batched.add_child(mi)


# -------------------------------------------------------------- ground -----
func _build_ground() -> void:
	# Cobbled fighting ring, then a dirt apron out to the wall. Both are thin
	# discs sitting a hair above the existing ground-plane collision.
	var cobble := WorldMaterials.get_material("M_Cobble")
	var ring := CylinderMesh.new()
	ring.top_radius = RING_RADIUS + 0.6
	ring.bottom_radius = RING_RADIUS + 0.6
	ring.height = 0.08
	ring.radial_segments = 40
	ring.material = cobble
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.position = Vector3(0.0, 0.02, 0.0)
	ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring_mi)

	var dirt := WorldMaterials.get_material("M_Mud")
	var apron := CylinderMesh.new()
	apron.top_radius = WALL_RADIUS + 6.0
	apron.bottom_radius = WALL_RADIUS + 6.0
	apron.height = 0.04
	apron.radial_segments = 40
	apron.material = dirt
	var apron_mi := MeshInstance3D.new()
	apron_mi.mesh = apron
	apron_mi.position = Vector3(0.0, 0.008, 0.0)
	apron_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(apron_mi)


# ----------------------------------------------------------- perimeter -----
func _build_perimeter() -> void:
	var body := Node3D.new()
	body.name = "Perimeter"
	add_child(body)

	# Stone wall ring: straight segments with a gap at the north for the
	# gatehouse (which spans ~11 m).
	const SEGMENTS := 26
	const GATE_HALF := 0.62  # radians of arc left open for the gatehouse
	var seg_len := 2.0 * WALL_RADIUS * sin(PI / SEGMENTS)
	var seg_scale := seg_len / 4.0
	for i in SEGMENTS:
		var a := TAU * float(i) / float(SEGMENTS) + PI
		# Angle measured from north (-Z); skip the arc the gate occupies.
		var rel := fposmod(a - PI, TAU)
		if rel < GATE_HALF or rel > TAU - GATE_HALF:
			continue
		var pos := Vector3(sin(a) * WALL_RADIUS, 0.0, -cos(a) * WALL_RADIUS)
		var broken := _rng.randf() < 0.18
		place("wall_broken" if broken else "wall_straight", pos, a, body, true,
			seg_scale if not broken else seg_scale * 0.8)

	# Corner towers.
	for a in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		var pos := Vector3(sin(a) * WALL_RADIUS, 0.0, -cos(a) * WALL_RADIUS)
		place("tower_round", pos, a, body, true)

	# Buttresses punctuating the wall between towers.
	for a in [PI * 0.5, PI * 1.0, PI * 1.5]:
		var pos := Vector3(sin(a) * (WALL_RADIUS - 0.7), 0.0, -cos(a) * (WALL_RADIUS - 0.7))
		place("buttress", pos, a + PI, body, true)

	# The gatehouse: the north landmark everything else is composed around.
	place("gatehouse", Vector3(0.0, 0.0, -WALL_RADIUS), 0.0, body, true)


# -------------------------------------------------------------- stands -----
func _build_stands() -> void:
	var stands := Node3D.new()
	stands.name = "Stands"
	add_child(stands)
	# Two timber stands facing the ring from east and west, with tiled roofs
	# and faction banners — the "lived-in" audience side of the space.
	for spec in [[PI * 0.5, -1.0], [PI * 1.5, 1.0]]:
		var a: float = spec[0]
		var pos := Vector3(sin(a) * 11.6, 0.0, -cos(a) * 11.6)
		var yaw := a + PI
		place("stand_section", pos, yaw, stands, true)
		place("stand_roof", pos + Vector3(sin(a) * 0.9, 0.0, -cos(a) * 0.9), yaw, stands)
		_banners.append(place("banner_red" if spec[1] < 0.0 else "banner_blue",
			pos + Vector3(sin(a + 0.35) * 1.9, 0.0, -cos(a + 0.35) * 1.9), yaw, stands, true,
			1.0, "", true))
		_banners.append(place("banner_blue" if spec[1] < 0.0 else "banner_red",
			pos + Vector3(sin(a - 0.35) * 1.9, 0.0, -cos(a - 0.35) * 1.9), yaw, stands, true,
			1.0, "", true))


# ------------------------------------------------------------ gate area ----
func _build_gate_area() -> void:
	var area := Node3D.new()
	area.name = "GateArea"
	add_child(area)
	# Supply clutter clustered either side of the gate — a working gate is a
	# busy gate, and this is the first thing the camera sees. Only the pieces a
	# body could realistically be stopped by carry collision; small dressing is
	# visual-only so the fight never snags on a bucket.
	place("cart", Vector3(-4.6, 0.0, -11.4), 0.45, area, true)
	place("crate", Vector3(-6.3, 0.0, -12.1), 0.3, area)
	place("crate", Vector3(-6.9, 0.0, -11.3), 0.9, area)
	place("crate", Vector3(-6.0, 0.0, -12.9), -0.2, area)
	place("barrel", Vector3(-3.2, 0.0, -12.3), 0.0, area)
	place("barrel", Vector3(-2.5, 0.0, -12.7), 0.4, area)
	place("sack", Vector3(-3.6, 0.0, -11.6), 0.0, area)
	place("sack", Vector3(-4.1, 0.0, -11.1), 1.2, area)
	place("cage", Vector3(4.4, 0.0, -11.8), -0.35, area, true)
	place("log_pile", Vector3(6.2, 0.0, -11.0), 0.25, area, true)
	place("hay_bale", Vector3(5.2, 0.0, -12.4), 0.15, area)
	place("wheel_spare", Vector3(-7.6, 0.0, -10.4), 0.0, area)
	place("bucket", Vector3(-2.2, 0.0, -11.4), 0.0, area)
	# Faction banners flanking the gate: the landmark reads from across the yard.
	_banners.append(place("banner_red", Vector3(-3.4, 0.0, -13.15), 0.0, area, true, 1.0, "", true))
	_banners.append(place("banner_blue", Vector3(3.4, 0.0, -13.15), 0.0, area, true, 1.0, "", true))


# --------------------------------------------------------- training area ---
func _build_training_area() -> void:
	var area := Node3D.new()
	area.name = "TrainingArea"
	add_child(area)
	# Training gear lives beside the west stand: racks, pells, a grindstone.
	place("weapon_rack", Vector3(-8.4, 0.0, 2.6), 1.15, area, true)
	place("weapon_rack", Vector3(-9.2, 0.0, 4.4), 1.5, area, true)
	place("training_dummy", Vector3(-7.6, 0.0, 6.4), 0.0, area, true)
	place("training_dummy", Vector3(-8.9, 0.0, 7.4), 0.5, area, true)
	place("grindstone", Vector3(-9.6, 0.0, 0.8), 0.8, area)
	place("crate", Vector3(-8.2, 0.0, 0.2), 0.4, area)
	place("barrel", Vector3(-9.4, 0.0, -1.2), 0.0, area)


# -------------------------------------------------------------- camp -------
func _build_camp_area() -> void:
	var area := Node3D.new()
	area.name = "CampArea"
	add_child(area)
	# The east side reads as the fighters' camp: table, bench, firewood, shed.
	place("shed", Vector3(10.4, 0.0, 4.6), -1.2, area, true)
	place("table", Vector3(8.2, 0.0, 7.4), 0.5, area)
	place("bench", Vector3(8.0, 0.0, 5.9), 0.5, area)
	place("firewood", Vector3(9.6, 0.0, 1.4), 0.3, area)
	place("firewood", Vector3(10.2, 0.0, 0.7), 1.1, area)
	place("log_pile", Vector3(11.2, 0.0, 2.4), -0.4, area, true)
	place("barrel", Vector3(11.0, 0.0, 6.6), 0.0, area)
	place("sack", Vector3(9.2, 0.0, 6.8), 0.8, area)
	place("crate", Vector3(11.4, 0.0, 5.4), -0.3, area)


# ---------------------------------------------------- terrain dressing -----
func _build_terrain_dressing() -> void:
	var dress := Node3D.new()
	dress.name = "Dressing"
	add_child(dress)

	# Mud churn where fighters actually fight and walk: a ring of patches
	# around the edge of the cobbles.
	for i in 9:
		var a := TAU * float(i) / 9.0 + _rng.randf() * 0.5
		var r := _rng.randf_range(7.5, 11.5)
		place("mud_patch_a" if i % 2 == 0 else "mud_patch_b",
			Vector3(sin(a) * r, 0.0, -cos(a) * r), _rng.randf() * TAU, dress)
	for i in 4:
		place("puddle", Vector3(_rng.randf_range(-7.0, 7.0), 0.0, _rng.randf_range(-7.0, 7.0)), 0.0, dress)

	# Rubble and stone scatter hug the wall line.
	for i in 10:
		var a := TAU * float(i) / 10.0 + 0.3
		var r := WALL_RADIUS - _rng.randf_range(1.2, 2.6)
		place("rubble_pile", Vector3(sin(a) * r, 0.0, -cos(a) * r), _rng.randf() * TAU, dress)
	for i in 16:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(9.0, WALL_RADIUS - 1.0)
		var kind: String = ["rock_a", "rock_b", "rock_c"][i % 3]
		place(kind, Vector3(sin(a) * r, 0.0, -cos(a) * r), _rng.randf() * TAU, dress)

	# Vegetation: tufts pushed to the wall line and into corners, plus dirt
	# mounds breaking up the flat apron.
	for i in 26:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(10.5, WALL_RADIUS - 0.8)
		place("grass_tuft_a" if i % 2 == 0 else "grass_tuft_b",
			Vector3(sin(a) * r, 0.0, -cos(a) * r), _rng.randf() * TAU, dress, false,
			_rng.randf_range(0.8, 1.5))
	for i in 7:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(8.5, 13.0)
		place("dirt_mound", Vector3(sin(a) * r, 0.0, -cos(a) * r), _rng.randf() * TAU, dress, false,
			_rng.randf_range(0.8, 1.6))


# ---------------------------------------------------------- background -----
func _build_background() -> void:
	var bg := Node3D.new()
	bg.name = "Background"
	add_child(bg)
	# A village silhouette beyond the wall, low-detail and far enough that fog
	# does most of the work. This is what gives the arena depth: layered roofs
	# over the wall line instead of empty sky.
	var houses := ["house_a", "house_b", "house_c"]
	for i in 16:
		var a := TAU * float(i) / 16.0 + _rng.randf_range(-0.12, 0.12)
		var rel := fposmod(a - PI, TAU)
		if rel < 0.45 or rel > TAU - 0.45:
			continue
		var r := _rng.randf_range(WALL_RADIUS + 7.0, WALL_RADIUS + 20.0)
		var pos := Vector3(sin(a) * r, 0.0, -cos(a) * r)
		var scl := _rng.randf_range(0.9, 1.5)
		# Far houses get the decimated LOD mesh.
		place(houses[i % 3], pos, a + _rng.randf_range(-0.4, 0.4), bg, false, scl,
			"_lod" if r > WALL_RADIUS + 12.0 else "")


# ---------------------------------------------------------------- fires ----
func _build_fires() -> void:
	var fires := Node3D.new()
	fires.name = "Fires"
	add_child(fires)
	var spots := [
		Vector3(0.0, 0.0, -10.6), Vector3(-10.2, 0.0, 3.4),
		Vector3(9.6, 0.0, 2.0), Vector3(0.0, 0.0, 10.8),
	]
	for i in spots.size():
		var pos: Vector3 = spots[i]
		place("brazier", pos, 0.0, fires, true)
		var light := OmniLight3D.new()
		light.position = pos + Vector3.UP * 1.35
		light.light_color = Color(1.0, 0.62, 0.30)
		light.light_energy = 2.6
		light.omni_range = 9.0
		light.shadow_enabled = false
		fires.add_child(light)
		_braziers.append(light)
		_brazier_phase.append(_rng.randf() * TAU)
		_brazier_base.append(light.light_energy)
		_fire_particles(fires, pos + Vector3.UP * 1.05)
	_build_dust()


## Flame + smoke for a brazier. CPUParticles3D for the same reason CombatFX
## uses them: the web build renders through gl_compatibility, where these draw
## identically to desktop. Kept small — 4 braziers x 22 particles is well
## inside the browser budget.
func _fire_particles(parent: Node3D, pos: Vector3) -> void:
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.vertex_color_use_as_albedo = true
	flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flame_mat.billboard_keep_scale = true
	flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_mat.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = flame_mat

	var flame := CPUParticles3D.new()
	flame.amount = 12
	flame.lifetime = 0.85
	flame.local_coords = false
	flame.direction = Vector3.UP
	flame.spread = 14.0
	flame.gravity = Vector3(0.0, 0.5, 0.0)
	flame.initial_velocity_min = 0.5
	flame.initial_velocity_max = 1.1
	flame.scale_amount_min = 0.10
	flame.scale_amount_max = 0.26
	flame.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.72, 0.28, 0.9))
	ramp.set_color(1, Color(0.55, 0.10, 0.02, 0.0))
	flame.color_ramp = ramp
	flame.position = pos
	parent.add_child(flame)

	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.vertex_color_use_as_albedo = true
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smoke_mat.billboard_keep_scale = true
	smoke_mat.disable_receive_shadows = true
	var smoke_quad := QuadMesh.new()
	smoke_quad.size = Vector2.ONE
	smoke_quad.material = smoke_mat

	var smoke := CPUParticles3D.new()
	smoke.amount = 10
	smoke.lifetime = 3.0
	smoke.local_coords = false
	smoke.direction = Vector3.UP
	smoke.spread = 20.0
	smoke.gravity = Vector3(0.0, 0.28, 0.0)
	smoke.initial_velocity_min = 0.35
	smoke.initial_velocity_max = 0.7
	smoke.scale_amount_min = 0.2
	smoke.scale_amount_max = 0.55
	smoke.mesh = smoke_quad
	var smoke_ramp := Gradient.new()
	smoke_ramp.set_color(0, Color(0.16, 0.15, 0.14, 0.0))
	smoke_ramp.set_color(1, Color(0.30, 0.29, 0.28, 0.22))
	smoke.color_ramp = smoke_ramp
	smoke.position = pos + Vector3.UP * 0.5
	parent.add_child(smoke)


## Drifting dust motes across the yard: the cheapest possible way to make a
## static space feel alive. 36 particles, no shadows, no collision.
func _build_dust() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat

	var dust := CPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 36
	dust.lifetime = 16.0
	dust.preprocess = 10.0
	dust.local_coords = false
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(15.0, 2.5, 15.0)
	dust.direction = Vector3(0.5, 0.12, 0.3)
	dust.spread = 40.0
	dust.gravity = Vector3(0.0, 0.015, 0.0)
	dust.initial_velocity_min = 0.04
	dust.initial_velocity_max = 0.22
	dust.scale_amount_min = 0.02
	dust.scale_amount_max = 0.055
	dust.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.94, 0.82, 0.0))
	ramp.set_color(1, Color(1.0, 0.94, 0.82, 0.10))
	dust.color_ramp = ramp
	dust.position = Vector3(0.0, 2.4, 0.0)
	add_child(dust)
