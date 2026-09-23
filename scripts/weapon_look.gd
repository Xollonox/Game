class_name WeaponLook
extends RefCounted
## Shared PBR materials for the arsenal's named slots (W_Steel, W_Iron, W_Wood,
## W_Leather, W_Brass, W_Paint...). Same contract as WorldMaterials: the GLBs
## carry slot names, the look lives here.

static var _cache: Dictionary = {}


static func dress(instance: Node) -> void:
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src == null:
				continue
			var m := get_material(src.resource_name)
			if m:
				mi.set_surface_override_material(i, m)


static func get_material(slot: String) -> Material:
	if _cache.has(slot):
		return _cache[slot]
	var m: StandardMaterial3D = null
	match slot:
		"W_Steel":
			m = _tex_mat("res://assets/textures/character/plate", Color(0.86, 0.87, 0.88), 0.3, 0.5, 2.0)
		"W_Iron":
			m = _tex_mat("res://assets/textures/character/iron", Color(0.62, 0.6, 0.57), 0.5, 0.45, 3.0)
		"W_Brass":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.72, 0.54, 0.26)
			m.metallic = 1.0
			m.roughness = 0.35
		"W_Leather":
			m = _tex_mat("res://assets/textures/character/leather", Color(0.7, 0.55, 0.45), 0.72, 0.0, 3.0)
		"W_Wood":
			m = _tex_mat("res://assets/textures/world/wood", Color(0.62, 0.46, 0.32), 0.7, 0.0, 2.0)
		"W_WoodPale":
			m = _tex_mat("res://assets/textures/world/wood", Color(0.86, 0.72, 0.55), 0.8, 0.0, 2.0)
		"W_Paint":
			m = _tex_mat("res://assets/textures/world/wood", Color(0.62, 0.16, 0.11), 0.82, 0.0, 1.2)
	_cache[slot] = m
	return m


static func _tex_mat(base: String, tint: Color, rough: float, metal: float, uv: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = metal
	m.uv1_scale = Vector3(uv, uv, uv)
	for suffix in ["_diff.jpg"]:
		if ResourceLoader.exists(base + suffix):
			m.albedo_texture = load(base + suffix)
	if ResourceLoader.exists(base + "_nor.jpg"):
		m.normal_enabled = true
		m.normal_texture = load(base + "_nor.jpg")
		m.normal_scale = 0.6
	if ResourceLoader.exists(base + "_rough.jpg"):
		m.roughness_texture = load(base + "_rough.jpg")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return m
