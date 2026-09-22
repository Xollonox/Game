class_name WorldMaterials
extends RefCounted
## One shared PBR material per kit slot name, built once and reused by every
## instance in the world.
##
## The Blender kit exports flat named slots (M_Stone, M_Wood, M_Roof...) with
## real box-projected UVs; this class is the other half of that contract. Two
## reasons it lives here rather than inside the GLBs:
##
## 1. Batching. The web build runs through gl_compatibility, where draw-call
##    overhead is the ceiling. N instanced kit pieces sharing one material is
##    dramatically cheaper than N materials that merely look alike.
## 2. Retuning. The whole world's look (tints, roughness, texture sets) can be
##    adjusted in one file instead of re-exporting 50 GLBs.
##
## Textures are CC0 sets from Poly Haven / ambientCG, downscaled to 1k for the
## web budget. Missing files degrade to flat-coloured materials rather than
## failing, so the world always builds.

const TEX_DIR := "res://assets/textures/world/"

static var _cache: Dictionary = {}


static func get_material(slot: String) -> StandardMaterial3D:
	if _cache.has(slot):
		return _cache[slot]
	var m := _build(slot)
	_cache[slot] = m
	return m


static func _tex(name: String) -> Texture2D:
	var path := TEX_DIR + name
	if ResourceLoader.exists(path):
		return load(path)
	return null


static func _build(slot: String) -> StandardMaterial3D:
	match slot:
		"M_Stone":
			return _pbr("stone", Color(0.72, 0.70, 0.66), 0.95, 0.6)
		"M_StoneDark":
			return _pbr("stone", Color(0.42, 0.41, 0.40), 0.97, 0.6)
		"M_Cobble":
			return _pbr("ground", Color(0.75, 0.73, 0.70), 0.95, 0.5)
		"M_Wood":
			return _pbr("wood", Color(0.62, 0.50, 0.38), 0.85, 1.0)
		"M_WoodDark":
			return _pbr("wood", Color(0.38, 0.30, 0.23), 0.88, 1.0)
		"M_Roof":
			return _pbr("roof", Color(0.60, 0.36, 0.30), 0.9, 1.5)
		"M_Plaster":
			return _pbr("plaster", Color(0.80, 0.76, 0.68), 0.92, 0.5)
		"M_Thatch":
			return _pbr("straw", Color(0.72, 0.60, 0.36), 0.95, 1.0)
		"M_Straw":
			return _pbr("straw", Color(0.85, 0.72, 0.42), 0.97, 0.8)
		"M_Mud":
			return _pbr("ground", Color(0.34, 0.28, 0.22), 0.97, 0.35)
		"M_Grass":
			return _pbr("grass", Color(0.42, 0.48, 0.30), 0.95, 1.2)
		"M_Cloth":
			return _pbr("cloth2", Color(0.78, 0.72, 0.58), 0.92, 0.8)
		"M_ClothRed":
			return _pbr("cloth2", Color(0.62, 0.20, 0.18), 0.92, 0.8)
		"M_ClothBlue":
			return _pbr("cloth2", Color(0.28, 0.34, 0.60), 0.92, 0.8)
		"M_Metal":
			var mm := StandardMaterial3D.new()
			mm.albedo_color = Color(0.42, 0.42, 0.45)
			mm.metallic = 0.9
			mm.roughness = 0.42
			return mm
		"M_Water":
			var w := StandardMaterial3D.new()
			w.albedo_color = Color(0.10, 0.12, 0.14)
			w.metallic = 0.35
			w.roughness = 0.12
			return w
		_:
			var d := StandardMaterial3D.new()
			d.albedo_color = Color(0.6, 0.6, 0.6)
			return d


static func _pbr(set: String, tint: Color, rough: float, uv_scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = 0.0
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	var diff := _tex(set + "_diff.jpg")
	if diff:
		m.albedo_texture = diff
	var nor := _tex(set + "_nor.jpg")
	if nor:
		m.normal_enabled = true
		m.normal_texture = nor
		m.normal_scale = 1.0
	var rough_tex := _tex(set + "_rough.jpg")
	if rough_tex:
		m.roughness_texture = rough_tex
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return m


## Applies the shared material for every surface of an instanced kit piece.
## Kit GLBs keep their named slots, so surface order maps 1:1 to Blender slots.
static func dress(instance: Node) -> void:
	for child in instance.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var mesh := mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var slot := ""
			if src:
				slot = src.resource_name if src.resource_name != "" else src.resource_path.get_file().get_basename()
			if slot == "":
				continue
			mi.set_surface_override_material(i, get_material(slot))
