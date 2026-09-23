class_name FighterLook
extends RefCounted
## Dresses an instanced fighter.glb from a fighter spec (see Armory.roll_fighter).
##
## The GLB carries every garment of the wardrobe as its own skinned mesh; this
## shows the ones the spec wears, hides the body zones they fully cover (no skin
## poke-through, fewer skinned triangles) and hair under helmets, and applies
## shared PBR materials. Dyed cloth is cached per (slot, colour) so a crowd of
## fighters wearing the same russet wool shares one material.

const TEX := "res://assets/textures/character/"

static var _mat_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}


static func apply(model: Node3D, spec: Dictionary) -> void:
	var worn: Array = spec.get("garments", [])
	var hidden_zones := {}
	var hide_hair := false
	for gname in worn:
		var layer = Armory.LAYERS.get(gname)
		if layer == null:
			continue
		for z in layer[6]:
			hidden_zones[z] = true
		if layer[7]:
			hide_hair = true
	var hair: String = spec.get("hair", "")
	var colors: Dictionary = spec.get("colors", {})
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		# Meshes are cut into limb segments ("G_Shirt__forearm_l", see
		# tools/blender/segments.py): the wardrobe matches the base name, the
		# dismemberment code the segment.
		var full := String(mi.name)
		var n := full.get_slice("__", 0)
		mi.set_meta(&"segment", full.get_slice("__", 1) if full.contains("__") else "core")
		var visible := true
		if n.begins_with("B_"):
			visible = not hidden_zones.has(n.substr(2))
		elif n.begins_with("G_") or n.begins_with("A_") or n.begins_with("H_") or n.begins_with("X_"):
			visible = n in worn
		elif n.begins_with("Hair_Beard"):
			visible = spec.get("beard", false) and not ("H_Barbute" in worn)
		elif n.begins_with("Hair_"):
			visible = n == hair and not hide_hair
		elif n == "Icosphere":
			visible = false
		if String(mi.get_meta(&"segment")) in (model.get_meta(&"severed", []) as Array):
			visible = false  # a limb that is no longer there
		mi.visible = visible
		if not visible:
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var mesh := mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var slot := src.resource_name.get_slice(".", 0) if src else ""
			var m := material_for(slot, spec, colors)
			if m and spec.get("shade", false):
				m = _shade_of(m, slot)
			if m:
				mi.set_surface_override_material(i, m)
		if spec.get("shade", false):
			mi.material_overlay = _shade_overlay()


## The dead: colour drained to ash, a cold sheen on every edge.
static func _shade_of(m: Material, slot: String) -> Material:
	var key := "shade_" + str(m.get_instance_id())
	if _mat_cache.has(key):
		return _mat_cache[key]
	var d := m.duplicate() as StandardMaterial3D
	if d:
		var c := d.albedo_color
		var g := (c.r + c.g + c.b) / 3.0
		d.albedo_color = Color(g, g * 1.05, g * 1.12).lerp(Color(0.3, 0.34, 0.38), 0.45)
		if slot == "MI_Eyes":
			d.emission_enabled = true
			d.emission = Color(0.5, 0.85, 1.0)
			d.emission_energy_multiplier = 3.0
	_mat_cache[key] = d if d else m
	return _mat_cache[key]


static var _overlay: ShaderMaterial


static func _shade_overlay() -> ShaderMaterial:
	if _overlay:
		return _overlay
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 tint : source_color = vec4(0.35, 0.6, 0.85, 1.0);
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = tint.rgb * f * 0.9;
	ALPHA = f;
}"""
	_overlay = ShaderMaterial.new()
	_overlay.shader = sh
	return _overlay


static func _tex(name: String) -> Texture2D:
	if _tex_cache.has(name):
		return _tex_cache[name]
	var p := TEX + name
	var t: Texture2D = load(p) if ResourceLoader.exists(p) else null
	_tex_cache[name] = t
	return t


static func material_for(slot: String, spec: Dictionary, colors: Dictionary) -> Material:
	var tint := Color(1, 1, 1)
	var key := slot
	match slot:
		"MI_Superhero_Male":
			var tone: String = spec.get("skin", "light")
			tint = spec.get("skin_tint", Color(1, 1, 1))
			key = "skin_%s_%s" % [tone, tint.to_html()]
		"MI_Hair_1", "MI_Hair_2":
			tint = spec.get("hair_color", Color(0.2, 0.13, 0.08))
			key = "hair_%s_%s" % [slot, tint.to_html()]
		_:
			if colors.has(slot):
				tint = colors[slot]
				key = "%s_%s" % [slot, tint.to_html()]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := _build(slot, spec, tint)
	# Cloth and mail are single sheets: draw both faces so a collar or cuff
	# never shows a black hole into the garment.
	if m is StandardMaterial3D and (slot.begins_with("G_") or slot == "A_Mail"):
		(m as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache[key] = m
	return m


static func _pbr(set: String, tint: Color, rough: float, metal: float, uv: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = metal
	m.uv1_scale = Vector3(uv, uv, uv)
	var d := _tex(set + "_diff.jpg")
	if d:
		m.albedo_texture = d
	var n := _tex(set + "_nor.jpg")
	if n:
		m.normal_enabled = true
		m.normal_texture = n
	var r := _tex(set + "_rough.jpg")
	if r:
		m.roughness_texture = r
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return m


static func _build(slot: String, spec: Dictionary, tint: Color) -> Material:
	match slot:
		"MI_Superhero_Male":
			var m := StandardMaterial3D.new()
			var tone: String = spec.get("skin", "light")
			m.albedo_texture = _tex("skin_%s_diff.jpg" % tone)
			# Slightly desaturated and cooled: the source skin is stylised warm.
			m.albedo_color = tint * Color(0.95, 0.9, 0.88)
			m.normal_enabled = true
			m.normal_texture = _tex("skin_nor.jpg")
			m.roughness_texture = _tex("skin_rough.jpg")
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			m.roughness = 1.0
			# A touch of subsurface-like warmth without the SSS cost on web:
			# rim lighting reads as skin catching the light at grazing angles.
			m.rim_enabled = true
			m.rim = 0.25
			m.rim_tint = 0.6
			return m
		"MI_Hair_1", "MI_Hair_2":
			var h := StandardMaterial3D.new()
			h.albedo_texture = _tex("hair1_diff.png" if slot == "MI_Hair_1" else "hair2_diff.png")
			# The source texture is a light grey strand map, tinted to colour.
			h.albedo_color = tint * 1.6
			h.roughness = 0.62
			h.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
			h.anisotropy_enabled = true
			h.anisotropy = 0.5
			return h
		"MI_Eyes":
			var e := StandardMaterial3D.new()
			e.albedo_texture = _tex("eye_diff.jpg")
			e.roughness = 0.15
			return e
		"G_Linen":
			return _pbr("linen", tint, 0.95, 0.0, 2.6)
		"G_Wool", "G_Wool2", "G_Hose":
			return _pbr("wool", tint * 1.15, 1.0, 0.0, 2.2)
		"G_Padded":
			return _pbr("linen", tint, 0.97, 0.0, 3.2)
		"G_Velvet":
			var v := _pbr("wool", tint * 1.6, 0.9, 0.0, 3.0)
			v.rim_enabled = true
			v.rim = 0.35
			return v
		"G_Leather":
			return _pbr("leather", Color(0.95, 0.88, 0.82), 0.7, 0.0, 1.2)
		"A_Mail":
			var ml := _pbr("mail", Color(0.6, 0.6, 0.61), 0.55, 0.55, 0.62)
			ml.metallic_specular = 0.7
			return ml
		"A_Plate":
			var pl := _pbr("plate", Color(0.66, 0.67, 0.68), 0.46, 0.6, 1.0)
			pl.metallic_specular = 0.5
			pl.rim_enabled = true
			pl.rim = 0.2
			return pl
		"A_Iron":
			return _pbr("plate", Color(0.6, 0.58, 0.55), 0.48, 0.55, 1.0)
		"A_Brass":
			var b := StandardMaterial3D.new()
			b.albedo_color = Color(0.72, 0.55, 0.28)
			b.metallic = 1.0
			b.roughness = 0.38
			return b
	return null
