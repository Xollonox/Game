class_name ShopUI
extends Control
## The armourer's tent: buy, sell and wear. One full-screen panel used after a
## victory and from the hall.
##
## Keyboard: arrows move through the wares, Enter jumps to the action buttons,
## Q / E switch between weapons and armour, Esc leaves. Touch: every control
## is a large button and the list scrolls with a drag.

signal closed

var run: Dictionary
var rank := 0
var _tab := "weapons"
var _selected := ""
var _list: VBoxContainer
var _scroll: ScrollContainer
var _tabs: Dictionary = {}
var _purse: Label
var _d_name: Label
var _d_sub: Label
var _d_note: Label
var _d_stats: Label
var _d_status: Label
var _b_buy: Button
var _b_wear: Button
var _b_off: Button
var _b_sell: Button
var _loadout: Label
var _rows: Dictionary = {}


static func open(parent: Node, run_state: Dictionary, standing: int) -> ShopUI:
	var s := ShopUI.new()
	s.run = run_state
	s.rank = standing
	Shop.ensure(run_state)
	parent.add_child(s)
	return s


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.make_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.017, 0.014, 0.8)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 44)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var title := _label("The Armourer's Tent", UITheme.decorative(), 34, UITheme.INK)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(title)
	var grow := Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(grow)
	_purse = _label("", UITheme.display(700), 24, UITheme.BRASS)
	_purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_purse.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(_purse)
	col.add_child(_label("You stand as %s. Finer pieces are offered as your standing rises; the armourer buys back at half." %
		Armory.rank_name(rank).to_lower(), UITheme.body(), 17, UITheme.INK_DIM))
	col.add_child(UITheme.rule(420.0))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	col.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(470, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.1
	body.add_child(left)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	left.add_child(tabs)
	var group := ButtonGroup.new()
	for t in [["weapons", "Weapons"], ["armour", "Armour"]]:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = t[0] == _tab
		b.custom_minimum_size = Vector2(150, 44)
		var on := UITheme.panel_style(Color(0.24, 0.17, 0.1, 0.95), UITheme.BRASS, 1)
		on.content_margin_top = 8
		on.content_margin_bottom = 8
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_color_override("font_pressed_color", UITheme.INK)
		b.add_theme_color_override("font_color", UITheme.INK_DIM)
		var key: String = t[0]
		b.pressed.connect(func(): _set_tab(key))
		b.mouse_entered.connect(AudioDirector.ui_hover)
		tabs.add_child(b)
		_tabs[key] = b
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	_scroll.add_child(_list)

	var detail := PanelContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(detail)
	var dcol := VBoxContainer.new()
	dcol.add_theme_constant_override("separation", 8)
	detail.add_child(dcol)
	_d_name = _label("", UITheme.display(700), 26, UITheme.INK)
	dcol.add_child(_d_name)
	_d_sub = _label("", UITheme.display(600), 14, UITheme.BRASS)
	dcol.add_child(_d_sub)
	dcol.add_child(UITheme.rule(260.0))
	_d_note = _label("", UITheme.body(), 18, UITheme.INK_DIM)
	dcol.add_child(_d_note)
	_d_stats = _label("", UITheme.body(500), 17, UITheme.INK)
	dcol.add_child(_d_stats)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dcol.add_child(fill)
	_d_status = _label("", UITheme.body(600), 17, UITheme.BLOOD_BRIGHT)
	dcol.add_child(_d_status)
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 8)
	acts.add_theme_constant_override("v_separation", 8)
	dcol.add_child(acts)
	_b_buy = _button("Buy", true, _on_buy)
	_b_wear = _button("Wear", true, _on_wear)
	_b_off = _button("Take Off", false, _on_off)
	_b_sell = _button("Sell", false, _on_sell)
	for b in [_b_buy, _b_wear, _b_off, _b_sell]:
		acts.add_child(b)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)
	_loadout = _label("", UITheme.body(), 16, UITheme.INK_DIM)
	_loadout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loadout.custom_minimum_size = Vector2(300, 0)
	foot.add_child(_loadout)
	var leave := _button("Leave the Tent", false, _close)
	foot.add_child(leave)

	_set_tab(_tab)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		_close()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			_set_tab("weapons")
		elif event.keycode == KEY_E:
			_set_tab("armour")


func _close() -> void:
	AudioDirector.ui_click()
	GameState.save_run()
	closed.emit()
	queue_free()


func _set_tab(t: String) -> void:
	_tab = t
	(_tabs[t] as Button).button_pressed = true
	_selected = ""
	_rebuild()


func _ids() -> Array[String]:
	return Shop.weapon_ids() if _tab == "weapons" else Shop.armour_ids()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	var last_slot := ""
	var first: Button = null
	for id in _ids():
		var slot := Shop.slot_of(id)
		if _tab == "armour" and slot != last_slot:
			last_slot = slot
			var h := _label(String(Shop.SLOT_NAMES.get(slot, slot)).to_upper(), UITheme.display(600), 13, UITheme.BRASS_DIM)
			_list.add_child(h)
		var row := _row(id)
		_list.add_child(row)
		_rows[id] = row
		if first == null:
			first = row
	if _selected == "" or not _rows.has(_selected):
		_selected = _ids()[0]
	_refresh()
	var focus: Button = _rows.get(_selected, first)
	if focus:
		focus.grab_focus.call_deferred()


func _row(id: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 42)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 16
	h.offset_right = -16
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var n := _label(Shop.item_name(id), UITheme.display(600), 17, UITheme.INK)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_OFF
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.name = "Name"
	h.add_child(n)
	var s := _label("", UITheme.body(600), 16, UITheme.INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.autowrap_mode = TextServer.AUTOWRAP_OFF
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.name = "Status"
	h.add_child(s)
	b.focus_entered.connect(func(): _select(id))
	b.pressed.connect(func():
		_select(id)
		_focus_action())
	b.mouse_entered.connect(AudioDirector.ui_hover)
	return b


func _select(id: String) -> void:
	if _selected == id:
		return
	_selected = id
	_refresh()


func _focus_action() -> void:
	for b in [_b_buy, _b_wear, _b_off, _b_sell]:
		if b.visible and not b.disabled:
			b.grab_focus()
			return


func _refresh() -> void:
	_purse.text = "%d coin" % int(run.get("purse", 0))
	for id: String in _rows:
		var row: Button = _rows[id]
		var st: Label = row.find_child("Status", true, false)
		var nm: Label = row.find_child("Name", true, false)
		var locked := Shop.min_rank(id) > rank and not Shop.owns(run, id)
		if Shop.is_equipped(run, id):
			st.text = "ON YOUR ARM" if id == "heater_shield" else ("IN HAND" if Shop.is_weapon(id) else "WORN")
			st.add_theme_color_override("font_color", UITheme.BRASS)
		elif Shop.owns(run, id):
			st.text = "in your pack"
			st.add_theme_color_override("font_color", UITheme.INK)
		elif locked:
			st.text = Armory.rank_name(Shop.min_rank(id))
			st.add_theme_color_override("font_color", UITheme.INK_FAINT)
		else:
			st.text = "%d coin" % Shop.price(id)
			var can := int(run.get("purse", 0)) >= Shop.price(id)
			st.add_theme_color_override("font_color", UITheme.INK_DIM if can else UITheme.BLOOD)
		nm.add_theme_color_override("font_color", UITheme.INK_FAINT if locked else UITheme.INK)
		row.add_theme_stylebox_override("normal", _row_style(id == _selected))
	_detail()
	_loadout.text = _loadout_text()


func _row_style(sel: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.15, 0.1, 0.9) if sel else Color(0.08, 0.075, 0.065, 0.7)
	sb.border_color = UITheme.BRASS if sel else Color(0.3, 0.25, 0.17, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	return sb


func _detail() -> void:
	var id := _selected
	if id == "":
		return
	_d_name.text = Shop.item_name(id)
	var slot := Shop.slot_of(id)
	_d_sub.text = "%s  ·  %d coin  ·  from %s" % [String(Shop.SLOT_NAMES.get(slot, slot)).to_upper(), Shop.price(id),
		Armory.rank_name(Shop.min_rank(id)).to_lower()]
	if Shop.is_weapon(id):
		var d := WeaponCatalog.get_def(id)
		_d_note.text = _sentence(ArenaHUD.weapon_note(id)) if id != "heater_shield" else \
			"Oak boards under painted linen. Held in the off hand; blocks and bashes."
		_d_stats.text = "Cut  %s\nThrust  %s\nCrush  %s\n%.2f kg  ·  %.2f m  ·  %s" % [
			_pips(float(d.get("cut", 0.0))), _pips(float(d.get("pierce", 0.0))), _pips(float(d.get("blunt", 0.0))),
			float(d.get("mass", 1.0)), float(d.get("length", 0.8)),
			"two hands" if int(d.get("hands", 1)) == 2 else "one hand"]
	else:
		_d_note.text = Shop.note(id)
		var gs: Array = Shop.ARMOUR[id][2]
		var cut := 0.0
		var thr := 0.0
		var cr := 0.0
		var kg := 0.0
		for g in gs:
			var l: Array = Armory.LAYERS.get(g, [])
			if l.is_empty():
				continue
			cut = maxf(cut, l[1] * l[4])
			thr = maxf(thr, l[2] * l[4])
			cr = maxf(cr, l[3] * l[4])
			kg += l[5]
		_d_stats.text = "Against cuts  %s\nAgainst thrusts  %s\nAgainst blows  %s\n%.1f kg" % [
			_pips(cut * 1.2), _pips(thr * 1.2), _pips(cr * 1.2), kg]
	var owned := Shop.owns(run, id)
	var worn := Shop.is_equipped(run, id)
	var bblock := Shop.buy_block(run, id, rank)
	var eblock := Shop.equip_block(run, id) if owned else ""
	_b_buy.visible = not owned
	_b_buy.text = "Buy · %d coin" % Shop.price(id)
	_b_buy.disabled = bblock != ""
	_b_wear.visible = owned and not worn
	_b_wear.text = "Take in Hand" if Shop.is_weapon(id) and id != "heater_shield" else "Wear"
	_b_wear.disabled = eblock != ""
	var main_weapon := Shop.is_weapon(id) and id != "heater_shield"
	_b_off.visible = worn and not main_weapon and id != "shirt"
	_b_sell.visible = owned and id != "shirt" and not (worn and main_weapon)
	_b_sell.text = "Sell · %d coin" % Shop.sell_price(id)
	if not owned:
		_d_status.text = bblock
	elif eblock != "" and not worn:
		_d_status.text = eblock
	elif worn and main_weapon:
		_d_status.text = "In your hand. Take up another before you sell it."
	else:
		_d_status.text = ""
	_d_status.add_theme_color_override("font_color", UITheme.INK_FAINT if bblock == "Already yours" else UITheme.BLOOD_BRIGHT)


static func _sentence(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1) + "."


func _pips(v: float) -> String:
	var n := clampi(int(round(v * 4.0)), 0, 5)
	return "■".repeat(n) + "□".repeat(5 - n)


func _loadout_text() -> String:
	var g := Shop.garments_for(run)
	var parts: Array[String] = []
	for r in Shop.REGIONS:
		parts.append("%s %d%%" % [r[0], int(round(Shop.region_protection(g, r[1], "cut") * 100.0))])
	var p: Dictionary = run.get("player", {})
	var w := WeaponCatalog.display_name(p.get("weapon", ""))
	if p.get("shield", false):
		w += " and shield"
	return "%s  ·  %.1f kg worn  ·  cut protection: %s" % [w, Armory.worn_weight(g), "  ".join(parts)]


func _after(ok: bool) -> void:
	if ok:
		AudioDirector.ui_click()
		GameState.save_run()
	_refresh()
	if not ok or (_b_buy.visible == false and _b_wear.visible == false):
		(_rows[_selected] as Button).grab_focus()
	else:
		_focus_action()


func _on_buy() -> void:
	_after(Shop.buy(run, _selected, rank))


func _on_wear() -> void:
	_after(Shop.equip(run, _selected))


func _on_off() -> void:
	Shop.unequip(run, _selected)
	_after(true)


func _on_sell() -> void:
	_after(Shop.sell(run, _selected))


func _label(text: String, font: Font, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	if primary:
		var th := UITheme.make_theme()
		UITheme.button_styles(th, true)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(state, th.get_stylebox(state, "Button"))
	b.pressed.connect(cb)
	b.mouse_entered.connect(AudioDirector.ui_hover)
	return b
