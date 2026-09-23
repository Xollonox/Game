extends Node
## Shop and inventory: buying, wearing, prerequisites, selling, looting, and
## that what is worn reaches the fighter's spec. Saves screenshots of both tabs.
##
##   xvfb-run -a godot --path . res://tests/shop_test.tscn

var _fail := false


func _check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		_fail = true


func _ready() -> void:
	GameState.new_run()
	var run := GameState.run
	_check(int(run["purse"]) == Shop.STARTING_PURSE, "a new life starts with a thin purse")
	_check(Shop.is_equipped(run, "tunic") and Shop.is_equipped(run, "falchion"), "starting kit is worn and in hand")
	_check(Shop.buy_block(run, "haubergeon", 0) != "", "mail is not sold to a vagrant")
	run["purse"] = 400
	_check(Shop.buy(run, "gambeson", 1), "buy a gambeson")
	_check(Shop.is_equipped(run, "gambeson"), "bought armour is put on")
	_check(Shop.buy(run, "haubergeon", 2) and Shop.is_equipped(run, "haubergeon"), "mail over the gambeson")
	var g := Shop.garments_for(run)
	_check("A_Haubergeon" in g and "A_Gambeson" in g and "X_BeltOuter" in g, "garments reach the spec (%s)" % [g])
	_check("A_Haubergeon" in GameState.player_spec()["garments"], "player spec wears the mail")
	Shop.equip(run, "tunic")
	_check(not Shop.is_equipped(run, "haubergeon"), "taking off the padding takes the mail off too")
	_check(Shop.equip_block(run, "haubergeon") != "", "mail cannot go over a tunic")
	Shop.equip(run, "gambeson")
	Shop.equip(run, "haubergeon")
	var before := int(run["purse"])
	_check(Shop.sell(run, "tunic") and int(run["purse"]) == before + Shop.sell_price("tunic"), "sell the tunic at half")
	_check(not Shop.sell(run, "falchion"), "cannot sell the weapon in your hand")
	_check(Shop.buy(run, "longsword", 3) and Shop.equip(run, "longsword"), "buy and take up a longsword")
	_check(Shop.buy(run, "heater_shield", 3) and Shop.equip_block(run, "heater_shield") != "", "no shield with a longsword")
	Shop.equip(run, "falchion")
	_check(Shop.equip(run, "heater_shield") and GameState.player_spec()["shield"], "shield with the falchion")
	Shop.equip(run, "war_spear") if Shop.owns(run, "war_spear") else null
	var l := Shop.loot(run, ["cudgel", "falchion", "cudgel"])
	_check((l[0] as Array) == ["cudgel"] and int(l[1]) == Shop.sell_price("falchion") + Shop.sell_price("cudgel"),
		"spoils go to the pack, spares are sold (%s)" % [l])
	# Old saves without a pack get one from what they wear.
	var old := {"bout": 5, "renown": 80, "player": {"weapon": "arming_sword", "shield": true,
		"garments": ["A_Gambeson", "G_Hose", "G_Boots", "G_Gloves", "H_Kettle"]}}
	Shop.ensure(old)
	_check(Shop.is_equipped(old, "kettle") and Shop.is_equipped(old, "boots") and Shop.owns(old, "heater_shield")
		and int(old["purse"]) > 80, "old save migrates to a pack")
	GameState.save_run()

	# Screens.
	run["bout"] = 9
	run["purse"] = 137
	var bg := ColorRect.new()
	bg.color = Color(0.25, 0.22, 0.18)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(bg)
	var ui := ShopUI.open(layer, run, Tournament.rank_for_bout(9))
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/shop_weapons.png")
	ui._set_tab("armour")
	await get_tree().create_timer(0.2).timeout
	(ui._rows["brigandine"] as Button).grab_focus()
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/shop_armour.png")
	print("SHOP_TEST ", "FAILED" if _fail else "OK")
	get_tree().quit(1 if _fail else 0)
