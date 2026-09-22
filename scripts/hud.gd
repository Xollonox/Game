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

const HINT_DEFAULT := "WASD move · SHIFT sprint · SPACE swing · drag to look · ESC pause"
const HINT_FADE_AFTER := 10.0

var _root: Control
var _vitals_fill: ProgressBar
var _vitals_num: Label
var _enemy_rows: VBoxContainer
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
	_enemy_rows = VBoxContainer.new()
	_enemy_rows.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_enemy_rows.offset_left = -240.0
	_enemy_rows.offset_top = 24.0
	_enemy_rows.offset_right = -28.0
	_enemy_rows.add_theme_constant_override("separation", 8)
	_enemy_rows.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(_enemy_rows)


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
		name_label.add_theme_color_override("font_color", UITheme.INK_FAINT if dead else UITheme.INK_DIM)
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


func show_death() -> void:
	_death.visible = true
	_death.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_death, "modulate:a", 1.0, 0.7)


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
