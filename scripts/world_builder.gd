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
	# Crowd and banners sway per rendered frame (see _process).
	for c in _crowd:
		c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for b in _banners:
		if b:
			b.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


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
	for c in _crowd:
		var ph: float = c.get_meta(&"bob")
		c.position.y += sin(_time * 3.1 + ph) * 0.0009
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
	# World-space (triplanar) tiling everywhere: a disc's own UVs would stretch
	# one texture tile across the whole ring. Raked sand-and-straw lists in the
	# ring, trampled tracks out to the wall, an open mud field beyond it.
	var parent_ground := get_parent().get_node_or_null("Ground/MeshInstance3D")
	if parent_ground:
		parent_ground.visible = false
	_disc(RING_RADIUS + 0.9, 0.03, _ground_mat("lists", Color(0.86, 0.82, 0.74), 0.34), 48)
	_disc(WALL_RADIUS + 6.0, 0.015, _ground_mat("tracks", Color(0.72, 0.66, 0.58), 0.24), 48)
	_disc(420.0, 0.0, _ground_mat("mudfield", Color(0.5, 0.47, 0.4), 0.1), 64)
	_build_horizon()
	_build_lists()
	_build_pavilions()


static var _gm_cache: Dictionary = {}


static func _ground_mat(set: String, tint: Color, scale: float) -> StandardMaterial3D:
	var key := "%s_%s" % [set, scale]
	if _gm_cache.has(key):
		return _gm_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	var base := "res://assets/textures/world/" + set
	if ResourceLoader.exists(base + "_diff.jpg"):
		m.albedo_texture = load(base + "_diff.jpg")
	if ResourceLoader.exists(base + "_nor.jpg"):
		m.normal_enabled = true
		m.normal_texture = load(base + "_nor.jpg")
	if ResourceLoader.exists(base + "_rough.jpg"):
		m.roughness_texture = load(base + "_rough.jpg")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	_gm_cache[key] = m
	return m


func _disc(radius: float, y: float, mat: Material, segs: int) -> void:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = 0.02
	c.radial_segments = segs
	c.rings = 1
	c.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.position = Vector3(0.0, y, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Soft round sprite for every particle in the world (flame, smoke, dust):
## untextured quads read as debug squares.
static var _soft: GradientTexture2D


static func soft_dot() -> GradientTexture2D:
	if _soft:
		return _soft
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	_soft = GradientTexture2D.new()
	_soft.gradient = g
	_soft.fill = GradientTexture2D.FILL_RADIAL
	_soft.fill_from = Vector2(0.5, 0.5)
	_soft.fill_to = Vector2(1.0, 0.5)
	_soft.width = 64
	_soft.height = 64
	return _soft


# ------------------------------------------------------------ horizon -----
## Rolling hills and a forest line far beyond the village so the world has
## an edge that fog can swallow, instead of a disc ending in the void.
func _build_horizon() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 120
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.9
	var inner := 95.0
	var outer := 190.0
	var rows := [[inner, 0.0], [130.0, 1.0], [outer, 0.6]]
	var verts: Array = []
	for r in rows.size():
		var ring: Array = []
		for i in n + 1:
			var a := TAU * float(i) / float(n)
			var h: float = (8.0 + noise.get_noise_2d(cos(a) * 3.0, sin(a) * 3.0) * 14.0) * float(rows[r][1])
			var rad: float = rows[r][0]
			ring.append(Vector3(sin(a) * rad, maxf(h, 0.0) - 0.2, -cos(a) * rad))
		verts.append(ring)
	for r in rows.size() - 1:
		for i in n:
			var a0: Vector3 = verts[r][i]
			var a1: Vector3 = verts[r][i + 1]
			var b0: Vector3 = verts[r + 1][i]
			var b1: Vector3 = verts[r + 1][i + 1]
			for v in [a0, b0, a1, a1, b0, b1]:
				st.add_vertex(v)
	st.generate_normals()
	var hills := MeshInstance3D.new()
	hills.mesh = st.commit()
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.11, 0.13, 0.09)
	hm.roughness = 1.0
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	hills.material_override = hm
	hills.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hills)
	# Forest belt: crossed-quad billboards with a painted fir silhouette —
	# reads as trees at any angle, costs two quads each.
	var tex := _fir_texture()
	var tm := StandardMaterial3D.new()
	tm.albedo_texture = tex
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	tm.alpha_scissor_threshold = 0.5
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	tm.roughness = 1.0
	tm.albedo_color = Color(0.8, 0.85, 0.8)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var ax := Vector3(1, 0, 0) if k == 0 else Vector3(0, 0, 1)
		var q := [-ax * 2.2, ax * 2.2, ax * 2.2 + Vector3.UP * 9.0, -ax * 2.2 + Vector3.UP * 9.0]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st2.set_normal(Vector3.UP)
			st2.set_uv(uv[idx])
			st2.add_vertex(q[idx])
	var tree_mesh := st2.commit()
	tree_mesh.surface_set_material(0, tm)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tree_mesh
	mm.instance_count = 520
	for i in mm.instance_count:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(42.0, 115.0)
		var sc := _rng.randf_range(0.75, 1.5)
		var t := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(sc, sc * _rng.randf_range(0.85, 1.25), sc)),
			Vector3(sin(a) * r, -0.2, -cos(a) * r))
		mm.set_instance_transform(i, t)
	var trees := MultiMeshInstance3D.new()
	trees.multimesh = mm
	trees.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trees)


func _fir_texture() -> ImageTexture:
	var w := 128
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	for y in h:
		var v := float(y) / h  # 0 top .. 1 bottom
		if v > 0.93:
			# Trunk.
			for x in range(w / 2 - 3, w / 2 + 3):
				img.set_pixel(x, y, Color(0.12, 0.09, 0.06, 1))
			continue
		# Tiered, jagged half-width: each tier flares then pulls in.
		var tier := fposmod(v * 6.0, 1.0)
		var half := (0.08 + 0.4 * v) * (0.55 + 0.45 * tier) * w
		half *= rng.randf_range(0.85, 1.08)
		for x in w:
			var d := absf(x - w / 2.0)
			if d < half:
				var shade := lerpf(0.6, 1.0, 1.0 - d / maxf(half, 1.0)) * lerpf(1.0, 0.7, tier)
				var c := Color(0.07, 0.11, 0.07) * shade * rng.randf_range(0.85, 1.15)
				c.a = 1.0
				img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# -------------------------------------------------------------- lists -----
## The tournament proper: a waist-high list fence around the ring with the
## two entrances (gate side and the fighters' side) left open, pennant poles,
## and a painted crowd filling the stands.
func _build_lists() -> void:
	var lists := Node3D.new()
	lists.name = "Lists"
	add_child(lists)
	var r := RING_RADIUS + 0.7
	var n := 30
	for i in n:
		var a := TAU * float(i) / float(n)
		var rel := fposmod(a, TAU)
		if rel < 0.22 or rel > TAU - 0.22 or absf(rel - PI) < 0.22:
			continue
		var pos := Vector3(sin(a) * r, 0.0, -cos(a) * r)
		place("fence_section", pos, a, lists, true, 0.95)
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		var pos := Vector3(sin(a) * (r + 0.5), 0.0, -cos(a) * (r + 0.5))
		_banners.append(place("banner_red" if i % 2 == 0 else "banner_blue", pos, a + PI, lists, true, 0.85, "", true))


## Competitors' pavilions in the yard's corners: striped round tents in each
## lord's colours with a pennant on the king-pole — the tournament camp.
func _build_pavilions() -> void:
	# Weathered, sun-faded dyes: pavilions stood out all season.
	var colours := [[Color(0.5, 0.14, 0.11), Color(0.76, 0.73, 0.66)], [Color(0.16, 0.22, 0.4), Color(0.66, 0.54, 0.26)],
		[Color(0.16, 0.3, 0.18), Color(0.76, 0.73, 0.66)], [Color(0.34, 0.18, 0.3), Color(0.66, 0.54, 0.26)]]
	var angles := [PI * 0.29, PI * 0.71, PI * 1.29, PI * 1.71]
	for i in angles.size():
		var a: float = angles[i]
		var pos := Vector3(sin(a) * 12.4, 0.0, -cos(a) * 12.4)
		var tex := _stripe_texture(colours[i][0], colours[i][1])
		var cloth := StandardMaterial3D.new()
		cloth.albedo_texture = tex
		cloth.roughness = 0.95
		cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
		var wall := CylinderMesh.new()
		wall.top_radius = 1.55
		wall.bottom_radius = 1.65
		wall.height = 1.9
		wall.radial_segments = 20
		wall.cap_top = false
		wall.cap_bottom = false
		wall.material = cloth
		var wmi := MeshInstance3D.new()
		wmi.mesh = wall
		wmi.position = pos + Vector3.UP * 0.95
		add_child(wmi)
		var roof := CylinderMesh.new()
		roof.top_radius = 0.02
		roof.bottom_radius = 1.85
		roof.height = 1.5
		roof.radial_segments = 20
		roof.cap_bottom = false
		roof.material = cloth
		var rmi := MeshInstance3D.new()
		rmi.mesh = roof
		rmi.position = pos + Vector3.UP * 2.6
		add_child(rmi)
		var pole := CylinderMesh.new()
		pole.top_radius = 0.03
		pole.bottom_radius = 0.04
		pole.height = 1.2
		pole.material = WorldMaterials.get_material("M_WoodDark")
		var pmi := MeshInstance3D.new()
		pmi.mesh = pole
		pmi.position = pos + Vector3.UP * 3.9
		add_child(pmi)
		var pen := QuadMesh.new()
		pen.size = Vector2(0.9, 0.3)
		var pm := StandardMaterial3D.new()
		pm.albedo_color = colours[i][0]
		pm.cull_mode = BaseMaterial3D.CULL_DISABLED
		pen.material = pm
		var pnm := MeshInstance3D.new()
		pnm.mesh = pen
		pnm.position = pos + Vector3(0.45, 4.35, 0)
		add_child(pnm)
		_banners.append(pnm)
		# Collision so fighters do not walk through the canvas.
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 1.6
		cyl.height = 2.0
		cs.shape = cyl
		body.position = pos + Vector3.UP
		body.add_child(cs)
		add_child(body)


func _stripe_texture(a: Color, b: Color) -> ImageTexture:
	var img := Image.create(256, 64, false, Image.FORMAT_RGB8)
	for x in 256:
		var c := a if (x / 16) % 2 == 0 else b
		for y in 64:
			var shade := 0.85 + 0.15 * sin(float(x) * 0.39)
			var cc: Color = c * shade
			if y < 6:
				cc = a * 0.6  # scalloped valance band
			img.set_pixel(x, y, cc)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_crowd(stand_pos: Vector3, yaw: float) -> void:
	# Rows of painted spectators on the stand tiers: one quad per tier, a
	# generated texture of heads, hoods and shoulders in the dye palette.
	# The crowd grows with the fighter's fame: a vagrant's scrap fills one
	# row, the Grand Melee packs all three.
	var tiers := 3
	if GameState.has_run() and get_tree().current_scene and get_tree().current_scene.name == "Arena":
		tiers = clampi(1 + int(GameState.run.get("bout", 0)) / 4, 1, 3)
	for tier in tiers:
		var q := QuadMesh.new()
		q.size = Vector2(7.2, 1.0)
		var m := StandardMaterial3D.new()
		m.albedo_texture = _crowd_texture(tier)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 1.0
		q.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = q
		var back := Vector3(sin(yaw + PI), 0, -cos(yaw + PI))
		mi.position = stand_pos + Vector3.UP * (1.25 + tier * 0.62) - back * (0.3 - tier * 0.55)
		mi.rotation.y = yaw + PI
		mi.set_meta(&"bob", _rng.randf() * TAU)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_crowd.append(mi)


var _crowd: Array[MeshInstance3D] = []


func _crowd_texture(seed: int) -> ImageTexture:
	var w := 512
	var h := 72
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + seed
	var dyes := [Color(0.45, 0.28, 0.18), Color(0.52, 0.16, 0.12), Color(0.2, 0.26, 0.42), Color(0.55, 0.47, 0.2),
		Color(0.25, 0.19, 0.14), Color(0.36, 0.36, 0.34), Color(0.24, 0.31, 0.2), Color(0.62, 0.56, 0.45)]
	var x := 4
	while x < w - 10:
		var bw := rng.randi_range(14, 20)
		var body: Color = dyes[rng.randi() % dyes.size()] * rng.randf_range(0.7, 1.0)
		body.a = 1.0
		var top := rng.randi_range(18, 30)
		img.fill_rect(Rect2i(x, top + 10, bw, h - top - 10), body)
		var skin := Color(0.72, 0.55, 0.44) * rng.randf_range(0.75, 1.0)
		skin.a = 1.0
		var hr := 5
		var cx := x + bw / 2
		for yy in range(-hr, hr + 1):
			for xx in range(-hr, hr + 1):
				if xx * xx + yy * yy <= hr * hr:
					img.set_pixel(cx + xx, top + 4 + yy, skin)
		if rng.randf() < 0.4:
			img.fill_rect(Rect2i(cx - 6, top - 3, 12, 5), body * 0.8)
		x += bw + rng.randi_range(-3, 3)
	return ImageTexture.create_from_image(img)


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
		_build_crowd(pos, yaw)
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
	place("barrel", Vector3(-3.9, 0.0, -12.9), 0.0, area)
	place("barrel", Vector3(-3.4, 0.0, -13.4), 0.4, area)
	place("sack", Vector3(-4.0, 0.0, -12.2), 0.0, area)
	place("sack", Vector3(-4.1, 0.0, -11.1), 1.2, area)
	place("cage", Vector3(4.4, 0.0, -11.8), -0.35, area, true)
	place("log_pile", Vector3(6.2, 0.0, -11.0), 0.25, area, true)
	place("hay_bale", Vector3(5.2, 0.0, -12.4), 0.15, area)
	place("wheel_spare", Vector3(-7.6, 0.0, -10.4), 0.0, area)
	place("bucket", Vector3(-3.3, 0.0, -11.9), 0.0, area)
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
	# The arsenal on display: real weapons leaning in the racks.
	var display := [["war_spear", Vector3(-8.2, 0.0, 2.1)], ["longsword", Vector3(-8.55, 0.0, 2.95)],
		["bearded_axe", Vector3(-9.05, 0.0, 4.0)], ["flanged_mace", Vector3(-9.3, 0.0, 4.8)]]
	for d in display:
		var sc := WeaponCatalog.mesh_scene(d[0])
		if sc == null:
			continue
		var w: Node3D = sc.instantiate()
		WeaponLook.dress(w)
		area.add_child(w)
		# Point up, leaning back against the rack.
		w.position = d[1] + Vector3.UP * 0.18
		w.rotation = Vector3(-PI / 2 + 0.22, 1.2, 0.0)
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
	for i in 3:
		var a := _rng.randf() * TAU
		place("puddle", Vector3(sin(a) * 12.5, 0.0, -cos(a) * 12.5), 0.0, dress)

	# Rubble and stone scatter hug the wall line.
	for i in 10:
		var a := TAU * float(i) / 10.0 + 0.3
		var r := WALL_RADIUS - _rng.randf_range(1.2, 2.6)
		place("rubble_pile", Vector3(sin(a) * r, 0.0, -cos(a) * r), _rng.randf() * TAU, dress)
	# Straw for the lists: bales stacked against the outside of the fence,
	# where grooms and squires would have left them.
	for i in 7:
		var a := TAU * float(i) / 7.0 + 0.45
		var r := RING_RADIUS + 1.6
		place("hay_bale", Vector3(sin(a) * r, 0.0, -cos(a) * r), a + _rng.randf_range(-0.3, 0.3), dress, true)
		if i % 2 == 0:
			place("hay_bale", Vector3(sin(a + 0.07) * (r + 0.1), 0.55, -cos(a + 0.07) * (r + 0.1)), a + 0.4, dress)

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
		Vector3(3.7, 0.0, -9.4), Vector3(-10.2, 0.0, 3.4),
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
	flame_mat.albedo_texture = soft_dot()
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
	smoke_mat.albedo_texture = soft_dot()
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
	mat.albedo_texture = soft_dot()
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
