class_name Heraldry
extends RefCounted
## Procedural arms for shields and banners, seeded by the bearer's name so a
## fighter always carries the same device.
##
## Follows the rule of tincture — a metal (or, argent) on a colour (gules,
## azure, vert, sable, purpure) or the reverse, never colour on colour — with
## the common ordinaries of the period: per pale, per fess, bend, chevron,
## cross, saltire, chief, quarterly and a roundel charge. Painted texture,
## then worn: the paint is scuffed toward the edges where blows land.

const METALS := [Color(0.78, 0.6, 0.2), Color(0.84, 0.82, 0.76)]
const COLOURS := [Color(0.6, 0.1, 0.08), Color(0.12, 0.2, 0.48), Color(0.1, 0.33, 0.16), Color(0.08, 0.075, 0.07),
	Color(0.36, 0.14, 0.34)]
const ORDINARIES := ["pale", "fess", "bend", "chevron", "cross", "saltire", "chief", "quarterly", "roundel"]

static var _cache: Dictionary = {}


static func texture_for(bearer: String) -> ImageTexture:
	if _cache.has(bearer):
		return _cache[bearer]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(bearer)
	var metal_field := rng.randf() < 0.4
	var metal: Color = METALS[rng.randi() % METALS.size()]
	var colour: Color = COLOURS[rng.randi() % COLOURS.size()]
	var field := metal if metal_field else colour
	var charge := colour if metal_field else metal
	var kind: String = ORDINARIES[rng.randi() % ORDINARIES.size()]
	var w := 128
	var h := 160
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var u := float(x) / w
			var v := float(y) / h
			var on := false
			match kind:
				"pale":
					on = absf(u - 0.5) < 0.17
				"fess":
					on = absf(v - 0.42) < 0.12
				"bend":
					on = absf((u - v * 0.8) - 0.1) < 0.12
				"chevron":
					on = absf(v - (0.62 - absf(u - 0.5) * 0.9)) < 0.09
				"cross":
					on = absf(u - 0.5) < 0.09 or absf(v - 0.4) < 0.08
				"saltire":
					on = absf((u - 0.5) - (v - 0.45) * 0.8) < 0.08 or absf((u - 0.5) + (v - 0.45) * 0.8) < 0.08
				"chief":
					on = v < 0.28
				"quarterly":
					on = (u < 0.5) == (v < 0.42)
				"roundel":
					on = Vector2(u - 0.5, (v - 0.42) * 1.25).length() < 0.22
			var c: Color = charge if on else field
			# Wear: grime and chipped paint toward the rim.
			var edge := minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
			var grime := rng.randf_range(0.9, 1.0) * lerpf(0.72, 1.0, clampf(edge * 6.0, 0.0, 1.0))
			if rng.randf() < 0.012 + (0.05 if edge < 0.06 else 0.0):
				c = Color(0.36, 0.27, 0.18)  # bare wood under chipped paint
			img.set_pixel(x, y, c * grime)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[bearer] = tex
	return tex
