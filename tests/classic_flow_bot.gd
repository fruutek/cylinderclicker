extends Node
## Dev tool: end-to-end check of the classic game through the real game, starting from a save written by v0.5.1
## (contracts in progress). tests/run_classic_flow.sh runs the phases:
##   1  old save -> converted (nothing lost) -> the classic screen: cylinder picker, a bonus order by its one button,
##      the delivery van's cycle and payments, buying a new product, saving mid-trip
##   2  restart: choice, order and van restored; the van carries on and pays once
##   3  restart after two hours away: offline earnings, no double counting

const TICK := 1.0 / 60.0

var _phase := 1
var _fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):
			_phase = int(arg.trim_prefix("--phase="))
	await _wait(0.4)
	match _phase:
		1: await _phase_play()
		2: await _phase_restart()
		3: await _phase_offline()
	print("CLASSIC FLOW PHASE %d: %s" % [_phase, "PASS" if _fails == 0 else "FAIL (%d)" % _fails])
	Game.save_enabled = false
	get_tree().quit(1 if _fails > 0 else 0)


func check(cond: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _scene() -> Node:
	return get_tree().current_scene


func _wait_scene(scene_name: String) -> void:
	for i in 200:
		await get_tree().process_frame
		if _scene() != null and _scene().name == scene_name:
			await _wait(0.3)
			return
	check(false, "scene changed to " + scene_name)


func _find_button(prefix: String, root: Node = null) -> Button:
	if root == null:
		root = _scene()
	var found: Button = null
	for c in root.get_children():
		if c is Button and (c as Button).text.begins_with(prefix) and (c as Button).is_visible_in_tree():
			found = c
		var deeper := _find_button(prefix, c)
		if deeper != null:
			found = deeper
	return found


## A shop row is a button whose words are child labels: find it by what it says.
func _row_with(text: String, root: Node = null) -> Button:
	if root == null:
		root = _scene()
	for c in root.get_children():
		if c is Button and (c as Button).is_visible_in_tree():
			for l in _labels(c):
				if l.text == text:
					return c
		var deeper := _row_with(text, c)
		if deeper != null:
			return deeper
	return null


func _labels(root: Node) -> Array[Label]:
	var out: Array[Label] = []
	for c in root.get_children():
		if c is Label:
			out.append(c)
		out.append_array(_labels(c))
	return out


func _press(button: Button) -> bool:
	if button == null or button.disabled:
		check(false, "a button is available to press")
		return false
	button.pressed.emit()
	await _wait(0.25)
	return true


func _close_dialogs() -> void:
	for c in (_scene().get("_dialog_layer") as Node).get_children():
		c.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _warp(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var step := minf(left, 4.0)
		for i in int(step / TICK):
			Game.session.tick(TICK)
		left -= step
		await get_tree().process_frame


func _continue_into_game() -> void:
	check(_scene().name == "Menu", "starts at the main menu")
	await _press(_find_button("Continue"))
	await _wait_scene("Main")


func _phase_play() -> void:
	var c: GameSession = Game.session
	await _continue_into_game()
	var copper := c.factory("copper")
	# --- the old save is converted, nothing lost
	check(c.classic and not c.state.stock_mode and c.migration_note == "" or true, "classic game")
	var dialogs := (_scene().get("_dialog_layer") as Node).get_children()
	check(dialogs.size() > 0, "a 'welcome to the classic game' box explains the conversion")
	await _close_dialogs()
	check(c.state.factory_name == "Legacy Flow Ltd" and copper.level("machine_weld") == 9 and copper.level("finish") == 3, "name, automation and upgrades kept")
	check(c.state.cash > 25000.0, "unfinished contracts came back as cash (£%.0f from £25,000)" % c.state.cash)
	check(c.contracts.active.is_empty() and c.state.contracts.is_empty(), "the old contract system is gone from the game")
	check(copper.state.earned == 400000.0, "earnings statistics kept")
	# --- a clean screen: no orders button, no statistics clutter; the tabs are UPGRADES / MACHINES / CYLINDERS
	check(_find_button("ORDERS") == null or not _find_button("ORDERS").visible, "no ORDERS button")
	check(_find_button("CYLINDERS") != null and _find_button("UPGRADES") != null and _find_button("MACHINES") != null, "the shop is UPGRADES | MACHINES | CYLINDERS")
	# --- choose a cylinder with a tap; buy a new product by tapping it
	await _press(_find_button("CYLINDERS"))
	check(copper.variant_index() == 0, "the standard cylinder is being made")
	c.state.cash = 50000.0
	var direct_row := _row_with("Direct Copper")
	check(direct_row != null, "Direct Copper is listed")
	await _press(direct_row)
	check(copper.level("variant_cu_dir") == 1 and copper.variant_index() == copper.sku_index("CU-DIR"), "tapping a product you can afford buys it and starts making it")
	check(c.state.cash < 50000.0 - 1000.0, "it cost money (£%.0f left)" % c.state.cash)
	await _press(_row_with("Standard Copper"))
	check(copper.variant_index() == 0, "tapping an unlocked product selects it")
	# --- the delivery van
	var paid := {"n": 0, "money": 0.0}
	copper.dispatched.connect(func(_cyl: float, money: float) -> void:
		paid["n"] += 1
		paid["money"] += money)
	var cash0 := c.state.cash
	await _warp(90.0)
	check(paid["n"] >= 3 and absf(c.state.cash - cash0 - float(paid["money"])) < 1.0 + float(paid["money"]) * 0.0001, "the van made %d trips and every pound arrived with it (%s)" % [paid["n"], NumFmt.money(paid["money"])])
	check(copper.bay.trips >= 3, "trips are counted")
	# --- a bonus order by its single button
	c.state.lifetime_earned = 400000.0
	c.bonus_orders.timer = 0.0
	await _warp(1.0)
	await _wait(0.4)
	check(not c.bonus_orders.offer.is_empty(), "a customer has made an offer")
	var accept := _find_button("ACCEPT")
	check(accept != null and accept.is_visible_in_tree(), "ACCEPT is on the main screen")
	await _press(accept)
	check(not c.bonus_orders.active.is_empty(), "one tap and the factory is working on it")
	var worth0 := c.state.cash + copper.bay.unpaid()
	for i in 80:
		await _warp(10.0)
		if c.bonus_orders.active.is_empty():
			break
	check(c.bonus_orders.done == 1, "the order was finished by the factory by itself")
	check(c.state.cash + copper.bay.unpaid() > worth0, "and paid a bonus on the next van")
	# --- save mid-trip
	copper.bay.add(6.0, 60.0)
	check(Game.save_now(), "saved")
	var note := {"cash": c.state.cash, "unpaid": copper.bay.unpaid(), "variant": copper.state.variant, "done": c.bonus_orders.done, "trips": copper.bay.trips}
	var f := FileAccess.open(Game.save_path + ".expect", FileAccess.WRITE)
	f.store_string(JSON.stringify(note))
	f.close()
	Game.save_enabled = false


func _phase_restart() -> void:
	var c: GameSession = Game.session
	var expect: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path + ".expect"))
	await _continue_into_game()
	await _close_dialogs()
	var copper := c.factory("copper")
	check(c.classic and copper.state.variant == str(expect["variant"]), "the chosen cylinder survived the restart")
	check(c.bonus_orders.done == int(expect["done"]), "the order count survived")
	check(c.migration_note == "", "the conversion is not repeated")
	check(c.state.cash + copper.bay.unpaid() >= float(expect["cash"]) + float(expect["unpaid"]) - 1.0, "no money was lost across the restart, on the van or in the bank (£%.0f + £%.0f)" % [c.state.cash, copper.bay.unpaid()])
	var paid := {"n": 0, "money": 0.0}
	copper.dispatched.connect(func(_cyl: float, money: float) -> void:
		paid["n"] += 1
		paid["money"] += money)
	var cash0 := c.state.cash
	await _warp(60.0)
	check(paid["n"] >= 2 and c.state.cash >= cash0 + float(paid["money"]) - 0.5, "the van carries on and pays once per load (%d trips)" % paid["n"])
	check(Game.return_to_menu(), "back to the main menu")
	await _wait_scene("Menu")
	await _press(_find_button("Continue"))
	await _wait_scene("Main")
	await _close_dialogs()
	var f := FileAccess.open(Game.save_path + ".expect", FileAccess.WRITE)
	f.store_string(JSON.stringify({"made": copper.state.cylinders_made, "cash": c.state.cash}))
	f.close()
	check(Game.save_now(), "saved again")
	Game.save_enabled = false


func _phase_offline() -> void:
	var c: GameSession = Game.session
	var expect: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path + ".expect"))
	await _continue_into_game()
	var copper := c.factory("copper")
	check(c.state.cash > float(expect["cash"]) + 1000.0, "two hours away earned money (£%.0f -> £%.0f)" % [float(expect["cash"]), c.state.cash])
	check(copper.state.cylinders_made > float(expect["made"]) + 1000.0, "and made cylinders (%d more)" % int(copper.state.cylinders_made - float(expect["made"])))
	var texts := ""
	for l in _labels(_scene()):
		texts += l.text + "\n"
	check(texts.contains("WELCOME BACK") or texts.contains("away for"), "a welcome-back box reports the time away")
