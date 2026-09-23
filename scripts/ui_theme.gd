class_name UITheme
extends RefCounted
## The single source of truth for the game's visual identity.
##
## Palette: iron, ash, parchment and dried blood — a fighting-yard palette
## rather than a fantasy-UI one. Typography is Cinzel (display, OFL) over
## EB Garamond (body, OFL); both are variable fonts, so weights are requested
## through FontVariation rather than shipping extra static files.

const FONT_DISPLAY := "res://assets/fonts/Cinzel.ttf"
const FONT_DECORATIVE := "res://assets/fonts/CinzelDecorative-Bold.ttf"
const FONT_BODY := "res://assets/fonts/EBGaramond.ttf"

## Ink on parchment.
const INK := Color(0.90, 0.86, 0.78)
const INK_DIM := Color(0.66, 0.61, 0.53)
const INK_FAINT := Color(0.45, 0.42, 0.37)
## Dried blood — the accent that marks anything hostile or final.
const BLOOD := Color(0.63, 0.17, 0.13)
const BLOOD_BRIGHT := Color(0.85, 0.28, 0.20)
## Old brass — used for frames, rules and hover states.
const BRASS := Color(0.71, 0.57, 0.33)
const BRASS_DIM := Color(0.44, 0.36, 0.22)
const PANEL := Color(0.055, 0.05, 0.045, 0.92)
const PANEL_SOFT := Color(0.08, 0.075, 0.065, 0.82)
const HEALTH := Color(0.66, 0.19, 0.15)
const HEALTH_LOW := Color(0.85, 0.42, 0.12)

static var _display: FontVariation
static var _decorative: FontVariation
static var _body: FontVariation


## OpenType tags are 4-char codes packed big-endian into an int, e.g.
## "wght" -> 0x77676874. Built by hand because TextServer's own tag helper
## is an instance method, not a static one.
static func _tag(tag: String) -> int:
	var v := 0
	for i in mini(tag.length(), 4):
		v = (v << 8) | tag.unicode_at(i)
	return v


static func display(weight := 700) -> Font:
	if _display == null:
		_display = FontVariation.new()
		_display.base_font = load(FONT_DISPLAY)
	_display.variation_opentype = {_tag("wght"): weight}
	return _display


static func decorative() -> Font:
	if _decorative == null:
		# Cinzel Decorative's TH/THE ligatures read as a misprint in titles.
		_decorative = FontVariation.new()
		_decorative.base_font = load(FONT_DECORATIVE)
		_decorative.opentype_features = {_tag("liga"): 0, _tag("dlig"): 0, _tag("clig"): 0}
	return _decorative


static func body(weight := 400) -> Font:
	if _body == null:
		_body = FontVariation.new()
		_body.base_font = load(FONT_BODY)
	_body.variation_opentype = {_tag("wght"): weight}
	return _body


## A framed panel: near-black fill, a thin brass rule inset, soft corners.
static func panel_style(fill := PANEL, border := BRASS_DIM, border_w := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	return sb


static func button_styles(theme: Theme, primary := false) -> void:
	var base := BLOOD if primary else PANEL_SOFT
	var hover := Color(0.16, 0.13, 0.11, 0.95) if not primary else Color(0.72, 0.22, 0.17)
	var normal := StyleBoxFlat.new()
	normal.bg_color = base
	normal.border_color = BRASS_DIM if not primary else Color(0.55, 0.22, 0.17)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 26.0
	normal.content_margin_right = 26.0
	normal.content_margin_top = 10.0
	normal.content_margin_bottom = 10.0

	var hv := normal.duplicate() as StyleBoxFlat
	hv.bg_color = hover
	hv.border_color = BRASS

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.10, 0.09, 0.08, 0.98) if not primary else Color(0.50, 0.14, 0.11)
	pressed.border_color = BRASS_DIM

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.10, 0.10, 0.10, 0.6)

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hv)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", hv)
	theme.set_stylebox("disabled", "Button", disabled)


## The game's base theme: fonts, button skins, label colours.
static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = body()
	theme.default_font_size = 17

	theme.set_font("font", "Button", display(600))
	theme.set_font_size("font_size", "Button", 19)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", Color(1, 0.97, 0.90))
	theme.set_color("font_pressed_color", "Button", INK_DIM)
	theme.set_color("font_disabled_color", "Button", INK_FAINT)
	theme.set_color("font_focus_color", "Button", Color(1, 0.97, 0.90))
	button_styles(theme, false)

	theme.set_color("font_color", "Label", INK)
	theme.set_font("font", "Label", body())

	theme.set_stylebox("panel", "Panel", panel_style())
	theme.set_stylebox("panel", "PanelContainer", panel_style())

	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(0.12, 0.11, 0.10, 0.9)
	slider_bg.set_corner_radius_all(2)
	slider_bg.content_margin_top = 3.0
	slider_bg.content_margin_bottom = 3.0
	theme.set_stylebox("slider", "HSlider", slider_bg)

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = BRASS
	grabber.set_corner_radius_all(2)
	theme.set_stylebox("grabber_area", "HSlider", grabber)
	theme.set_stylebox("grabber_area_highlight", "HSlider", grabber)

	theme.set_stylebox("panel", "PopupPanel", panel_style())
	return theme


## A thin brass rule used to separate menu sections.
static func rule(width := 320.0, color := BRASS_DIM) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(width, 1.0)
	return r
