extends Node3D
## Main menu: a live view of the yard behind the title, with the entry points
## into the duel.
##
## The background is the real world — the same `world_builder` the arena uses —
## seen from a slowly drifting camera at dusk. Nothing is a static render, so
## the braziers flicker and the fog moves while the menu sits open, and the
## transition into a fight is a fade rather than a scene swap.

const ARENA_SCENE := "res://scenes/arena.tscn"

var _world: Node3D
var _camera: Camera3D
var _time := 0.0
var _fade: ColorRect
var _busy := false
var _open_panel: Control = null
var _buttons: Array[Button] = []


func _ready() -> void:
	_build_world()
	_build_ui()
	AudioDirector.play_menu_music()
	AudioDirector.stop_ambience()


func _process(delta: float) -> void:
	_time += delta
	# A slow arc across the yard toward the gatehouse, with a breath of
	# handheld bob so the shot never reads as a locked-off render.
	var a := -0.72 + sin(_time * 0.045) * 0.34
	var r := 15.8 + sin(_time * 0.09) * 0.5
	_camera.position = Vector3(sin(a) * r, 3.1 + sin(_time * 0.31) * 0.06, -cos(a) * r)
	_camera.look_at(Vector3(0.0, 2.3, -9.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not _busy:
		if _open_panel != null:
			_close_panel()


# ---------------------------------------------------------------- world -----
func _build_world() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.055, 0.065, 0.10)
	sky_mat.sky_horizon_color = Color(0.30, 0.23, 0.185)
	sky_mat.ground_bottom_color = Color(0.045, 0.04, 0.038)
	sky_mat.ground_horizon_color = Color(0.17, 0.145, 0.13)
	sky_mat.sun_angle_max = 14.0
	sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.20, 0.175, 0.165)
	env.fog_density = 0.030
	env.fog_sky_affect = 0.5
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.14
	env.adjustment_saturation = 0.90
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-18.0, 32.0, 0.0)
	sun.light_color = Color(1.0, 0.80, 0.62)
	sun.light_energy = 0.85
	sun.shadow_enabled = GameState.quality_high
	add_child(sun)

	_world = Node3D.new()
	_world.set_script(load("res://scripts/world_builder.gd"))
	add_child(_world)

	_camera = Camera3D.new()
	_camera.fov = 52.0
	_camera.position = Vector3(-10.0, 3.1, 13.0)
	add_child(_camera)


# ------------------------------------------------------------------- ui -----
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.make_theme()
	layer.add_child(root)

	# Scrim behind the title so the type holds against the bright yard.
	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.018, 0.016, 0.34)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(scrim)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	column.offset_left = 96.0
	column.offset_top = -220.0
	column.offset_right = 520.0
	column.offset_bottom = 260.0
	column.add_theme_constant_override("separation", 0)
	root.add_child(column)

	var title := Label.new()
	title.text = "BARE STEEL"
	title.add_theme_font_override("font", UITheme.decorative())
	title.add_theme_font_size_override("font_size", 74)
	title.add_theme_color_override("font_color", UITheme.INK)
	column.add_child(title)

	var rule_row := HBoxContainer.new()
	column.add_child(rule_row)
	rule_row.add_child(UITheme.rule(340.0, UITheme.BRASS))

	var sub := Label.new()
	sub.text = "Seventeen bouts, one body, no second chances above ground"
	sub.add_theme_font_override("font", UITheme.body())
	sub.add_theme_font_size_override("font_size", 21)
	sub.add_theme_color_override("font_color", UITheme.INK_DIM)
	column.add_child(sub)

	column.add_child(_spacer(46.0))

	if GameState.has_run():
		var run := GameState.run
		var in_hollow: bool = run.get("mode", "arena") == "hollow"
		var cont := _button("Descend Again" if in_hollow else "Continue the Tournament", true)
		cont.pressed.connect(func(): _enter("res://scenes/hollow.tscn" if in_hollow else ARENA_SCENE))
		column.add_child(cont)
		var st := Label.new()
		st.text = ("In the Hollow" if in_hollow else "Bout %d of %d · %s" % [int(run.get("bout", 0)) + 1,
			Tournament.bout_count(), Tournament.standing(int(run.get("bout", 0)))]) + " · %d renown" % int(run.get("renown", 0))
		st.add_theme_font_size_override("font_size", 15)
		st.add_theme_color_override("font_color", UITheme.INK_FAINT)
		column.add_child(st)
		column.add_child(_spacer(10.0))
		var fresh := _button("Begin a New Life", false)
		fresh.pressed.connect(func():
			GameState.new_run()
			_enter(ARENA_SCENE))
		column.add_child(fresh)
		column.add_child(_spacer(10.0))
		cont.grab_focus.call_deferred()
	else:
		var play := _button("Enter the Tournament", true)
		play.pressed.connect(func():
			GameState.new_run()
			_enter(ARENA_SCENE))
		column.add_child(play)
		column.add_child(_spacer(10.0))
		play.grab_focus.call_deferred()

	var how := _button("How to Fight", false)
	how.pressed.connect(func(): _show_panel(_controls_panel()))
	column.add_child(how)
	column.add_child(_spacer(10.0))

	var settings := _button("Settings", false)
	settings.pressed.connect(func(): _show_panel(_settings_panel()))
	column.add_child(settings)

	var version := Label.new()
	version.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	version.offset_left = 30.0
	version.offset_top = -40.0
	version.offset_right = 300.0
	version.offset_bottom = -18.0
	version.text = "v0.3 · Godot 4.7"
	version.add_theme_font_size_override("font_size", 14)
	version.add_theme_color_override("font_color", UITheme.INK_FAINT)
	root.add_child(version)

	var credit := Label.new()
	credit.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	credit.offset_left = -420.0
	credit.offset_top = -40.0
	credit.offset_right = -30.0
	credit.offset_bottom = -18.0
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credit.text = "CC0 art & audio · see CREDITS"
	credit.add_theme_font_size_override("font_size", 14)
	credit.add_theme_color_override("font_color", UITheme.INK_FAINT)
	root.add_child(credit)

	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)


func _controls_panel() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 34)
	grid.add_theme_constant_override("v_separation", 10)
	var rows := [
		["Move", "W A S D  ·  joystick"],
		["Sprint", "Shift"],
		["Cut", "Space  ·  left click  ·  CUT"],
		["Line of the cut", "hold forward: from above · sideways: level · back: rising"],
		["Thrust", "F  ·  middle click  ·  THRUST"],
		["Guard", "hold C  ·  right mouse  ·  GUARD"],
		["Heavy blow", "cut while sprinting"],
		["Camera", "Q / E  ·  middle-drag  ·  wheel  ·  Tab: lock on/off"],
		["Pause", "Esc"],
	]
	for r in rows:
		var k := Label.new()
		k.text = String(r[0])
		k.add_theme_font_override("font", UITheme.display(600))
		k.add_theme_font_size_override("font_size", 17)
		k.add_theme_color_override("font_color", UITheme.BRASS)
		grid.add_child(k)
		var v := Label.new()
		v.text = String(r[1])
		v.add_theme_font_size_override("font_size", 17)
		v.add_theme_color_override("font_color", UITheme.INK)
		grid.add_child(v)
	return _panel("How to Fight", grid)


func _settings_panel() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.add_child(_slider("Volume", GameState.master, func(v):
		GameState.master = v
		GameState.apply()))
	box.add_child(_slider("Music", GameState.music, func(v):
		GameState.music = v
		GameState.apply()))
	box.add_child(_slider("Ambience", GameState.ambience, func(v):
		GameState.ambience = v
		GameState.apply()))
	box.add_child(_toggle("Shadows & Effects", GameState.quality_high, func(on):
		GameState.quality_high = on
		GameState.apply()))
	box.add_child(_toggle("Blood", GameState.blood, func(on):
		GameState.blood = on
		GameState.apply()))
	return _panel("Settings", box)


func _panel(title_text: String, content: Control) -> Control:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)

	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.018, 0.016, 0.62)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_close_panel())
	holder.add_child(veil)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.PANEL, UITheme.BRASS_DIM, 1))
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(430.0, 0.0)
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_override("font", UITheme.display(700))
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", UITheme.INK)
	box.add_child(title)
	box.add_child(UITheme.rule(240.0))
	box.add_child(content)

	var back := _button("Back", false)
	back.pressed.connect(_close_panel)
	box.add_child(_centered(back))
	return holder


func _show_panel(panel: Control) -> void:
	_close_panel()
	_open_panel = panel
	add_child(panel)
	panel.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(panel, "modulate:a", 1.0, 0.18)


func _close_panel() -> void:
	if _open_panel == null:
		return
	AudioDirector.ui_click()
	_open_panel.queue_free()
	_open_panel = null


func _enter_yard() -> void:
	if not GameState.has_run():
		GameState.new_run()
	_enter(ARENA_SCENE)


func _enter(path: String) -> void:
	if _busy:
		return
	_busy = true
	AudioDirector.ui_click()
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.55)
	await t.finished
	get_tree().change_scene_to_file(path)


# -------------------------------------------------------------- widgets -----
func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300.0, 0.0)
	if primary:
		var theme := UITheme.make_theme()
		UITheme.button_styles(theme, true)
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, theme.get_stylebox(state, "Button"))
	b.mouse_entered.connect(AudioDirector.ui_hover)
	b.pressed.connect(AudioDirector.ui_click)
	_buttons.append(b)
	return b


func _slider(label_text: String, value: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(120.0, 0.0)
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", UITheme.INK_DIM)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(220.0, 0.0)
	s.value_changed.connect(on_change)
	row.add_child(s)
	return row


func _toggle(label_text: String, value: bool, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(240.0, 0.0)
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", UITheme.INK_DIM)
	row.add_child(l)
	var c := CheckButton.new()
	c.button_pressed = value
	c.toggled.connect(on_change)
	row.add_child(c)
	return row


func _centered(control: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.add_child(control)
	return c


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, h)
	return c
