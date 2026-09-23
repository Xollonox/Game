class_name ArenaHUD
extends CanvasLayer
## The arena interface: vitals, opponents, kill feed, control hint, and the
## death / pause screens.
##
## Built in code rather than authored as a scene for two reasons: every panel
## shares one theme builder (`ui_theme.gd`), and the arena scene stays a
## greybox that only wires gameplay nodes. All copy is written for the game's
## voice — no "State: NORMAL", no raw event logs, no debug labels.
##
## Runs with PROCESS_MODE_ALWAYS so the pause screen keeps working while the
## rest of the tree is paused.

signal restart_requested
signal leave_requested
signal choice_made(kind: String, value: String)

const HINT_DEFAULT := "WASD move   ·   SPACE/LMB cut (steer with movement)   ·   F thrust   ·   C/RMB guard   ·   SHIFT sprint   ·   ESC pause"
const HINT_FADE_AFTER := 14.0

var _root: Control
var _vitals_fill: ProgressBar
var _vitals_num: Label
var _enemy_rows: VBoxContainer
var _enemy_panel: PanelContainer
var _marker: VBoxContainer
var _marker_name: Label
var _marker_bar: ProgressBar
var _feed: VBoxContainer
var _hint: Label
var _hint_timer := 0.0
var _hint_shown := true

var _death: Control
var _pause: Control
var _settings_box: VBoxContainer

var _enemy_cache: Array = []
var _paused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_root()
	_build_vitals()
	_build_enemies()
	_build_feed()
	_build_hint()
	_build_death()
	_build_pause()
	_build_overlay()
	_set_fight_hud_visible(false)


func _process(delta: float) -> void:
	if _hint_shown and not _paused:
		_hint_timer += delta
		if _hint_timer > HINT_FADE_AFTER:
			_hint_shown = false
			var t := create_tween()
			t.tween_property(_hint, "modulate:a", 0.0, 1.6)


func _build_root() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.make_theme()
	add_child(_root)


func _build_vitals() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(28, 24)
	box.add_theme_constant_override("separation", 5)
	_root.add_child(box)

	var name_label := Label.new()
	name_label.text = "YOU"
	name_label.add_theme_font_override("font", UITheme.display(600))
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", UITheme.INK_DIM)
	box.add_child(name_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	_vitals_fill = _bar(UITheme.HEALTH, 264.0, 15.0)
	row.add_child(_vitals_fill)

	_vitals_num = Label.new()
	_vitals_num.add_theme_font_override("font", UITheme.display(600))
	_vitals_num.add_theme_font_size_override("font_size", 15)
	_vitals_num.add_theme_color_override("font_color", UITheme.INK)
	row.add_child(_vitals_num)


func _build_enemies() -> void:
	_enemy_panel = PanelContainer.new()
	_enemy_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_enemy_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_enemy_panel.offset_left = -236.0
	_enemy_panel.offset_top = 20.0
	_enemy_panel.offset_right = -20.0
	var sb := UITheme.panel_style(Color(0.03, 0.028, 0.025, 0.55), Color(0, 0, 0, 0), 0)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 10.0
	_enemy_panel.add_theme_stylebox_override("panel", sb)
	_enemy_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_enemy_panel)
	_enemy_rows = VBoxContainer.new()
	_enemy_rows.add_theme_constant_override("separation", 7)
	_enemy_rows.alignment = BoxContainer.ALIGNMENT_END
	_enemy_panel.add_child(_enemy_rows)
	# Marker over the opponent you are squared up to: name and a thin bar.
	_marker = VBoxContainer.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.add_theme_constant_override("separation", 2)
	_marker_name = Label.new()
	_marker_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marker_name.add_theme_font_override("font", UITheme.display(600))
	_marker_name.add_theme_font_size_override("font_size", 13)
	_marker_name.add_theme_color_override("font_color", UITheme.INK)
	_marker_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_marker_name.add_theme_constant_override("outline_size", 4)
	_marker.add_child(_marker_name)
	_marker_bar = _bar(Color(0.62, 0.17, 0.13), 90.0, 4.0)
	_marker.add_child(_centered(_marker_bar))
	_marker.visible = false
	_root.add_child(_marker)


func _build_feed() -> void:
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_feed.offset_left = -340.0
	_feed.offset_top = -190.0
	_feed.offset_right = -28.0
	_feed.offset_bottom = -60.0
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.add_theme_constant_override("separation", 4)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_feed)


func _build_hint() -> void:
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -330.0
	_hint.offset_top = -54.0
	_hint.offset_right = 330.0
	_hint.offset_bottom = -26.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_override("font", UITheme.body())
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", UITheme.INK_DIM)
	_hint.text = HINT_DEFAULT
	_hint.offset_left = -520.0
	_hint.offset_right = 520.0
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("outline_size", 4)
	_root.add_child(_hint)


func _build_death() -> void:
	_death = Control.new()
	_death.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death.visible = false
	_root.add_child(_death)

	var veil := ColorRect.new()
	veil.color = Color(0.03, 0.02, 0.02, 0.72)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_death.add_child(veil)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -240.0
	box.offset_top = -150.0
	box.offset_right = 240.0
	box.offset_bottom = 150.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	_death.add_child(box)

	var title := Label.new()
	title.text = "YOU HAVE FALLEN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UITheme.decorative())
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", UITheme.BLOOD_BRIGHT)
	box.add_child(title)

	var rule_center := CenterContainer.new()
	rule_center.add_child(UITheme.rule(300.0))
	box.add_child(rule_center)

	var sub := Label.new()
	sub.text = "The yard keeps what it takes."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_override("font", UITheme.body())
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", UITheme.INK_DIM)
	box.add_child(sub)

	box.add_child(_spacer(10.0))

	var rise := _menu_button("Rise Again", true)
	rise.pressed.connect(func(): restart_requested.emit())
	box.add_child(_centered(rise))

	var leave := _menu_button("Leave the Yard", false)
	leave.pressed.connect(func(): leave_requested.emit())
	box.add_child(_centered(leave))

	var hint := Label.new()
	hint.text = "or press R"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_override("font", UITheme.body())
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", UITheme.INK_FAINT)
	box.add_child(hint)


func _build_pause() -> void:
	_pause = Control.new()
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	_root.add_child(_pause)

	var veil := ColorRect.new()
	veil.color = Color(0.03, 0.02, 0.02, 0.66)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause.add_child(veil)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.PANEL, UITheme.BRASS_DIM, 1))
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320.0, 0.0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UITheme.display(700))
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", UITheme.INK)
	box.add_child(title)
	box.add_child(_centered(UITheme.rule(240.0)))

	var resume := _menu_button("Return to the Fight", true)
	resume.pressed.connect(toggle_pause)
	box.add_child(resume)

	var restart := _menu_button("Restart the Duel", false)
	restart.pressed.connect(func():
		toggle_pause()
		restart_requested.emit())
	box.add_child(restart)

	var settings := _menu_button("Settings", false)
	settings.pressed.connect(func():
		_settings_box.visible = not _settings_box.visible)
	box.add_child(settings)

	_settings_box = _build_settings()
	_settings_box.visible = false
	box.add_child(_settings_box)

	var leave := _menu_button("Leave the Yard", false)
	leave.pressed.connect(func():
		toggle_pause()
		leave_requested.emit())
	box.add_child(leave)


func _build_settings() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	box.add_child(_slider_row("Volume", GameState.master, func(v):
		GameState.master = v
		GameState.apply()))
	box.add_child(_slider_row("Music", GameState.music, func(v):
		GameState.music = v
		GameState.apply()))
	box.add_child(_slider_row("Ambience", GameState.ambience, func(v):
		GameState.ambience = v
		GameState.apply()))
	box.add_child(_toggle_row("Shadows & Effects", GameState.quality_high, func(on):
		GameState.quality_high = on
		GameState.apply()))
	box.add_child(_toggle_row("Blood", GameState.blood, func(on):
		GameState.blood = on
		GameState.apply()))
	return box


# ---------------------------------------------------------------- API -------
func set_vitals(health: float, max_health: float) -> void:
	var ratio := clampf(health / maxf(max_health, 1.0), 0.0, 1.0)
	_vitals_fill.value = ratio * 100.0
	_vitals_num.text = "%d" % roundi(health)
	var col := UITheme.HEALTH if ratio > 0.35 else UITheme.HEALTH_LOW
	var sb := _vitals_fill.get_theme_stylebox("fill") as StyleBoxFlat
	if sb and sb.bg_color != col:
		sb.bg_color = col


## [param entries] is an array of dictionaries: name, health, max, dead.
func set_enemies(entries: Array) -> void:
	if entries.size() != _enemy_cache.size():
		_rebuild_enemy_rows(entries)
	for i in mini(entries.size(), _enemy_cache.size()):
		var e: Dictionary = entries[i]
		var row: Dictionary = _enemy_cache[i]
		var bar: ProgressBar = row["bar"]
		bar.value = clampf(float(e["health"]) / maxf(float(e["max"]), 1.0), 0.0, 1.0) * 100.0
		var name_label: Label = row["name"]
		var dead: bool = e["dead"]
		name_label.text = String(e["name"]) if not dead else String(e["name"]) + "  ✝"
		var col := UITheme.INK_FAINT if dead else (UITheme.BRASS if e.get("focus", false) else UITheme.INK_DIM)
		name_label.add_theme_color_override("font_color", col)
		bar.modulate.a = 0.35 if dead else 1.0


func _rebuild_enemy_rows(entries: Array) -> void:
	for child in _enemy_rows.get_children():
		child.queue_free()
	_enemy_cache.clear()
	for e in entries:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		_enemy_rows.add_child(col)

		var name_label := Label.new()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		name_label.add_theme_font_override("font", UITheme.display(600))
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", UITheme.INK_DIM)
		name_label.text = String(e["name"])
		col.add_child(name_label)

		var bar_row := HBoxContainer.new()
		bar_row.alignment = BoxContainer.ALIGNMENT_END
		col.add_child(bar_row)
		var bar := _bar(Color(0.52, 0.16, 0.13), 150.0, 7.0)
		bar_row.add_child(bar)
		_enemy_cache.append({"name": name_label, "bar": bar})


## Places the marker over the locked opponent (screen position of the head).
func set_target(name_text: String, ratio: float, screen_pos: Vector2, show: bool) -> void:
	if not _marker:
		return
	_marker.visible = show and _enemy_panel.visible
	if not show:
		return
	_marker_name.text = name_text
	_marker_bar.value = clampf(ratio, 0.0, 1.0) * 100.0
	_marker.reset_size()
	_marker.position = screen_pos - Vector2(_marker.size.x * 0.5, _marker.size.y + 6.0)


## One line in the corner feed, e.g. a kill or a telling blow.
func feed(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_override("font", UITheme.body())
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", UITheme.INK_DIM)
	label.modulate.a = 0.0
	_feed.add_child(label)
	while _feed.get_child_count() > 4:
		var oldest := _feed.get_child(0)
		_feed.remove_child(oldest)
		oldest.queue_free()
	var t := create_tween()
	t.tween_property(label, "modulate:a", 1.0, 0.25)
	t.tween_interval(3.4)
	t.tween_property(label, "modulate:a", 0.0, 1.2)
	t.tween_callback(label.queue_free)


func hide_death() -> void:
	_death.visible = false


func is_paused() -> bool:
	return _paused


func toggle_pause() -> void:
	_paused = not _paused
	_pause.visible = _paused
	get_tree().paused = _paused
	if not _paused:
		AudioDirector.ui_click()


# ------------------------------------------------------------ widgets -------
func _bar(fill: Color, w: float, h: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(w, h)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.055, 0.05, 0.85)
	bg.border_color = UITheme.BRASS_DIM
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	return bar


func _menu_button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	if primary:
		var theme := UITheme.make_theme()
		UITheme.button_styles(theme, true)
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, theme.get_stylebox(state, "Button"))
	b.mouse_entered.connect(AudioDirector.ui_hover)
	b.pressed.connect(AudioDirector.ui_click)
	return b


func _slider_row(label_text: String, value: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(96.0, 0.0)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", UITheme.INK_DIM)
	row.add_child(l)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(170.0, 0.0)
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	return row


func _toggle_row(label_text: String, value: bool, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(180.0, 0.0)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", UITheme.INK_DIM)
	row.add_child(l)
	var check := CheckButton.new()
	check.button_pressed = value
	check.toggled.connect(on_change)
	row.add_child(check)
	return row


func _centered(control: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.add_child(control)
	return c


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, h)
	return c


# ------------------------------------------------------------ overlays ------
var _overlay: Control
var _fade_rect: ColorRect
var _intro_hint: Label


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_overlay)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade_rect)
	var t := create_tween()
	t.tween_property(_fade_rect, "modulate:a", 0.0, 1.1)


func fade_out(duration: float) -> void:
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var t := create_tween()
	t.tween_property(_fade_rect, "modulate:a", 1.0, duration)
	await t.finished


func _set_fight_hud_visible(on: bool) -> void:
	if _marker and not on:
		_marker.visible = false
	for c in [_enemy_panel, _feed, _hint]:
		if c:
			c.visible = on
	if _vitals_fill:
		_vitals_fill.get_parent().get_parent().visible = on


func _clear_overlay() -> void:
	for c in _overlay.get_children():
		c.queue_free()


func _label(text: String, font: Font, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _gradient_band(from_bottom := true, height := 0.55) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.018, 0.015, 0.0))
	g.set_color(1, Color(0.02, 0.018, 0.015, 0.92))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.anchor_top = 1.0 - height if from_bottom else 0.0
	tr.anchor_bottom = 1.0 if from_bottom else height
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not from_bottom:
		tr.flip_v = true
	return tr


static func describe_kit(spec: Dictionary) -> String:
	var g: Array = spec.get("garments", [])
	var parts: Array[String] = []
	if "A_Cuirass" in g:
		parts.append("full harness")
	elif "A_Brigandine" in g:
		parts.append("brigandine over mail")
	elif "A_Haubergeon" in g:
		parts.append("mail")
	elif "A_Gambeson" in g:
		parts.append("a padded jack")
	elif "G_Tunic" in g:
		parts.append("a wool tunic")
	else:
		parts.append("his shirt")
	for h in [["H_Sallet", "sallet"], ["H_Bascinet", "bascinet"], ["H_Barbute", "barbute"], ["H_Kettle", "kettle hat"],
			["H_Skullcap", "steel cap"], ["H_PaddedCoif", "arming cap"], ["G_Hood", "hood"]]:
		if h[0] in g:
			parts.append(h[1])
			break
	var w := WeaponCatalog.display_name(spec.get("weapon", "")).to_lower()
	if spec.get("shield", false):
		w += " and shield"
	return "%s · %s" % [" and ".join(parts), w]


## The herald's card before a bout.
func show_intro(enc: Dictionary, run: Dictionary, specs: Array) -> void:
	_clear_overlay()
	_set_fight_hud_visible(false)
	_overlay.add_child(_gradient_band(true, 0.62))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.anchor_right = 1.0
	box.offset_left = 72.0
	box.offset_right = -72.0
	box.offset_top = -330.0
	box.offset_bottom = -40.0
	box.add_theme_constant_override("separation", 6)
	box.alignment = BoxContainer.ALIGNMENT_END
	_overlay.add_child(box)
	var bout := int(enc.get("bout", 0))
	var header: String = enc.get("header", "BOUT %d OF %d  ·  %s  ·  RENOWN %d" % [bout + 1, Tournament.bout_count(),
		Tournament.standing(bout).to_upper(), int(run.get("renown", 0))])
	box.add_child(_label(header, UITheme.display(600), 14, UITheme.BRASS))
	box.add_child(_label(String(enc.get("title", "")), UITheme.decorative(), 46, UITheme.INK))
	box.add_child(_label(String(enc.get("blurb", "")), UITheme.body(400), 20, UITheme.INK_DIM))
	box.add_child(_label(Tournament.format_label(enc.get("format", "duel"), specs.size()).to_upper(),
		UITheme.display(600), 13, UITheme.BLOOD_BRIGHT))
	box.add_child(UITheme.rule(420.0))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 2)
	box.add_child(grid)
	for sp in specs:
		var nl := _label(String(sp.get("name", "")), UITheme.display(700), 18, UITheme.INK)
		nl.autowrap_mode = TextServer.AUTOWRAP_OFF
		grid.add_child(nl)
		var kl := _label("%s — %s" % [Armory.rank_name(int(sp.get("rank", 0))), describe_kit(sp)],
			UITheme.body(), 17, UITheme.INK_DIM)
		kl.autowrap_mode = TextServer.AUTOWRAP_OFF
		grid.add_child(kl)
	_intro_hint = _label("Strike to begin", UITheme.display(600), 15, UITheme.INK_FAINT)
	box.add_child(_intro_hint)
	var t := _intro_hint.create_tween().set_loops()
	t.tween_property(_intro_hint, "modulate:a", 0.35, 0.9)
	t.tween_property(_intro_hint, "modulate:a", 1.0, 0.9)
	_overlay.modulate.a = 0.0
	create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.8)


func hide_intro() -> void:
	var t := create_tween()
	t.tween_property(_overlay, "modulate:a", 0.0, 0.4)
	t.tween_callback(_clear_overlay)
	t.tween_callback(func(): _overlay.modulate.a = 1.0)


func show_fight_hud(first_bout: bool) -> void:
	_set_fight_hud_visible(true)
	_hint.visible = first_bout
	_hint_timer = 0.0
	_hint_shown = first_bout
	_hint.modulate.a = 1.0


func _choice_panel(title: String, title_color: Color, lines: Array, buttons: Array) -> void:
	_clear_overlay()
	_set_fight_hud_visible(false)
	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.015, 0.013, 0.62)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	box.add_child(_label(title, UITheme.decorative(), 50, title_color, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_centered(UITheme.rule(340.0)))
	for l in lines:
		box.add_child(_label(l[0], UITheme.body(l[2] if l.size() > 2 else 400), l[1], UITheme.INK_DIM,
			HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_spacer(12.0))
	var first: Button = null
	for b in buttons:
		var btn := _menu_button(b[0], b.size() > 3 and b[3])
		btn.custom_minimum_size = Vector2(360, 0)
		var kind: String = b[1]
		var val: String = b[2]
		btn.pressed.connect(func(): choice_made.emit(kind, val))
		box.add_child(_centered(btn))
		if first == null:
			first = btn
	if first:
		first.grab_focus.call_deferred()
	_overlay.modulate.a = 0.0
	create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.7)


func show_panel(title: String, color: Color, lines: Array, buttons: Array) -> void:
	_choice_panel(title, color, lines, buttons)


func show_victory(enc: Dictionary, run: Dictionary, fallen: Array, weapons: Array, pspec: Dictionary) -> void:
	var lines := [
		["+%d renown  ·  %d in all" % [int(enc.get("renown", 0)), int(run.get("renown", 0))], 22, 600],
		["You now stand as %s." % Tournament.standing(int(run.get("bout", 0))).to_lower(), 18],
	]
	var names: Array[String] = []
	for f in fallen:
		names.append(String(f.get("name", "")))
	if not names.is_empty():
		lines.append(["Left in the sand: " + ", ".join(names), 16])
	lines.append(["", 8])
	lines.append(["SPOILS OF THE YARD", 14, 700])
	var buttons := []
	for w in weapons.slice(0, 3):
		buttons.append(["Take the %s" % WeaponCatalog.display_name(w).to_lower(), "spoils", w, false])
	buttons.push_front(["Keep your %s" % WeaponCatalog.display_name(pspec.get("weapon", "")).to_lower(), "spoils", "", true])
	_choice_panel("VICTORY", UITheme.BRASS, lines, buttons)


func show_champion(run: Dictionary) -> void:
	_choice_panel("CHAMPION", UITheme.BRASS, [
		["The Grand Melee is yours. The heralds will cry your name in every yard from here to the sea.", 20],
		["%d renown  ·  %d slain  ·  %d returns from the Hollow" % [int(run.get("renown", 0)),
			int(run.get("slain_total", 0)), int(run.get("returns", 0))], 16],
	], [["Begin a New Life", "new_run", "", true], ["Return to the Hall", "menu", ""]])


func show_death(run: Dictionary, kills: int) -> void:
	var debt := (run.get("slain", []) as Array).size()
	var line := "The yard keeps what it takes."
	if debt > 0:
		line = "%d you sent below are waiting for you in the Hollow." % mini(debt, 5)
	elif kills == 0:
		line = "You die with clean hands. Even so, something waits below."
	_choice_panel("YOU HAVE FALLEN", UITheme.BLOOD_BRIGHT, [
		[line, 20],
		["Bout %d · %s · %d renown" % [int(run.get("bout", 0)) + 1, Tournament.standing(int(run.get("bout", 0))),
			int(run.get("renown", 0))], 16],
	], [
		["Descend into the Hollow", "hollow", "", true],
		["Begin a New Life", "new_run", ""],
		["Return to the Hall", "menu", ""],
	])
