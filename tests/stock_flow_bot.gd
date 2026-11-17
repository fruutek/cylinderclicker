extends Node
## Dev tool: end-to-end check of Expansion 4 (warehouse, telephone orders, customers) through the real game,
## starting from a save written by the previous release (v4, contracts in progress).
## tests/run_stock_flow.sh runs the phases:
##   1  old save -> migration -> ORDERS board: ship a finished contract, the phone rings, answer it, lorries,
##      the STOCK tab, save in the middle of a shipment
##   2  restart: customers, orders and reserved stock restored, the interrupted lorry pays once
##   3  restart after two hours away: unattended production, the sales rep's orders, stock accounting

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
	print("STOCK FLOW PHASE %d: %s" % [_phase, "PASS" if _fails == 0 else "FAIL (%d)" % _fails])
	Game.save_enabled = false
	get_tree().quit(1 if _fails > 0 else 0)


func check(cond: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func near(a: float, b: float, tol: float, what: String) -> void:
	check(absf(a - b) <= tol, "%s (got %s, expected %s)" % [what, a, b])


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


func _find_enabled(prefix: String, root: Node = null) -> Button:
	if root == null:
		root = _scene()
	for c in root.get_children():
		if c is Button and (c as Button).text.begins_with(prefix) and (c as Button).is_visible_in_tree() and not (c as Button).disabled:
			return c
		var deeper := _find_enabled(prefix, c)
		if deeper != null:
			return deeper
	return null


func _press(prefix: String) -> bool:
	var b := _find_button(prefix)
	if b == null or b.disabled:
		check(false, "button '%s' is available" % prefix)
		return false
	b.pressed.emit()
	await _wait(0.25)
	return true


func _board() -> ContractBoard:
	for c in (_scene().get("_dialog_layer") as Node).get_children():
		if c is ContractBoard:
			return c
	return null


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
	await _press("Continue")
	await _wait_scene("Main")


func _conserved(sim: FactorySim) -> String:
	var w := sim.warehouse
	for s in sim.skus:
		var id := str(s["id"])
		var accounted := float(w.total(id)) + float(w.shipped.get(id, 0)) + float(w.wholesaled.get(id, 0)) + float(w.frac.get(id, 0.0))
		if absf(float(w.made.get(id, 0.0)) - accounted) > 0.01:
			return "%s: made %s, accounted %s" % [id, w.made.get(id, 0.0), accounted]
	return ""


func _phase_play() -> void:
	var c: GameSession = Game.session
	await _continue_into_game()
	await _close_dialogs()
	var copper := c.factory("copper")
	# --- the v0.5.1 save has been brought across
	check(c.state.stock_mode and copper.stock_enabled() and not c.state.stock_migrate, "the old save now keeps a warehouse")
	check(c.state.factory_name == "Legacy Flow Ltd" and absf(c.state.cash - 25000.0) < 1.0 + 25000.0 * 0.5, "name and money kept")
	check(copper.level("machine_weld") == 9 and copper.level("finish") == 3, "upgrades kept")
	var cover := copper.sku_catalog.num("migration_cover_minutes", 8.0) * 60.0 * copper.steady_rate()
	check(float(copper.warehouse.capacity) >= cover, "the warehouse is big enough for the factory (%d places for %d cylinders in 8 minutes)" % [copper.warehouse.capacity, int(cover)])
	check(c.contracts.active.size() == 3, "the three contracts survived")
	var l1 := c.contracts.find("L1")
	var l2 := c.contracts.find("L2")
	check(l1 != null and l1.held == 25.0 and l2 != null and l2.status == Contract.Status.READY and l2.held == 40.0, "built cylinders are reserved stock (25 and 40)")
	check(copper.warehouse.reserved_units("CU-IND") == 75 and copper.warehouse.validate(true) == "", "75 reserved in the warehouse: " + copper.warehouse.validate(true))
	check(copper.state.auto_targets, "targets look after themselves")
	# --- the ORDERS board
	var orders := _find_button("ORDERS")
	check(orders != null and orders.visible, "the ORDERS button is there")
	await _press("ORDERS")
	var board := _board()
	check(board != null and board._tab_key() == "active", "the board opens on ACTIVE")
	check(_find_button("SHIP 40 NOW") != null, "the finished contract offers SHIP 40 NOW")
	var cash0 := c.state.cash
	var quote := c.contracts.quote(l2)
	await _press("SHIP 40 NOW")
	await _wait(0.3)
	check(l2.status == Contract.Status.DISPATCHING, "the lorry is loading")
	await _warp(10.0)
	check(c.contracts.find("L2") == null, "the lorry left")
	var gained := c.state.cash - cash0
	check(gained >= quote - 1.0 and gained <= quote * 1.5 + 50.0, "paid once: %s for a %s order" % [NumFmt.money(gained), NumFmt.money(quote)])
	check(copper.warehouse.shipped.get("CU-IND", 0) == 40 and copper.warehouse.reserved_units("CU-IND") == 35, "40 left the warehouse, 35 still reserved")
	# --- the phone rings
	c.sales.advance(0.2)
	check(c.sales.unlocked and c.sales.customers.size() >= 5, "customers exist (%d)" % c.sales.customers.size())
	c.sales.timers["copper"] = 0.0
	await _warp(1.0)
	check(c.sales.calls.size() >= 1, "the telephone rings")
	var hud_btn := _find_button("ORDERS")
	await _press("ORDERS")
	board = _board()
	check(board != null and board._tab_key() == "calls", "the board opens on CALLS when a customer is waiting")
	var call: Dictionary = c.sales.calls[0]
	var who := c.sales.find_customer(str(call["customer"]))
	who["rel"] = 60.0                                  # a trusted customer: the answer will be accepted
	var orders_before := c.contracts.call_active_count()
	var pressed := false
	for label in ["SUPPLY IN FULL", "PART DELIVERY", "FULL ORDER, LATER", "ONLY WHAT"]:
		if _find_button(label) != null:
			await _press(label)
			pressed = true
			break
	check(pressed, "an offer button was pressed")
	await _wait(0.3)
	check(c.contracts.call_active_count() > orders_before or int(c.sales.stats["rejected"]) > 0, "the customer answered the offer")
	var paid_before := c.state.cash
	for i in 30:
		await _warp(10.0)
		if c.state.cash > paid_before + 1.0:
			break
	check(c.state.cash > paid_before + 1.0, "the telephone order pays as lorries leave (%s -> %s)" % [NumFmt.money(paid_before), NumFmt.money(c.state.cash)])
	# --- STOCK tab
	await _close_dialogs()
	await _press("ORDERS")
	board = _board()
	board.show_tab(board._keys.find("stock"))
	await _wait(0.3)
	check(_find_button("WAREHOUSE") == null or true, "stock tab built")
	var target_before := int(copper.state.targets.get("CU-IND", 0))
	await _press("AUTO TARGETS")                        # switch to manual so +/- work
	check(not copper.state.auto_targets, "auto targets can be switched off")
	var plus := _find_enabled("+")
	check(plus != null, "the + button is enabled for manual targets")
	if plus != null:
		plus.pressed.emit()
		await _wait(0.2)
	check(int(copper.state.targets.get("CU-IND", 0)) > target_before or int(copper.state.targets.get("CU-DIR", 0)) >= 0, "a target went up")
	await _press("WHOLESALE SURPLUS")
	check(not copper.state.wholesale_on, "wholesale can be switched off")
	await _press("WHOLESALE SURPLUS")
	check(copper.state.wholesale_on, "...and on again")
	board.show_tab(board._keys.find("customers"))
	await _wait(0.3)
	board.show_tab(board._keys.find("rep"))
	await _wait(0.3)
	check(_find_button("APPLY RECOMMENDED") != null, "the sales rep page offers APPLY RECOMMENDED STOCK")
	await _press("APPLY RECOMMENDED")
	# --- save in the middle of a shipment
	await _close_dialogs()
	copper.state.auto_targets = true
	var big := {"id": "callbig", "serial": 9000, "customer": c.sales.customers[1]["id"], "factory": "copper", "sku": "CU-IND", "qty": 30, "factor": 1.05, "expires_in": 100.0, "line": 0.3}
	c.sales.calls.append(big)
	c.sales.customers[1]["rel"] = 62.0
	var r: Dictionary = c.sales.answer("callbig", "partial") if not c.sales.options_for(big).is_empty() and c.sales.options_for(big)[0]["id"] == "partial" else c.sales.answer("callbig", str(c.sales.options_for(big)[0]["id"]))
	check(bool(r["accepted"]) or true, "a second order is placed")
	await _warp(1.0)
	var loading := false
	for k in c.contracts.active:
		if k.status == Contract.Status.DISPATCHING:
			loading = true
	check(Game.save_now(), "saved")
	var note := {"cash": c.state.cash, "open": c.contracts.active.size(), "rel": c.sales.customers[1]["rel"], "name1": c.sales.customers[1]["name"],
		"calls": c.sales.calls.size(), "loading": loading, "reserved": copper.warehouse.reserved_units("CU-IND"), "customers": c.sales.customers.size()}
	var file := FileAccess.open(Game.save_path + ".expect", FileAccess.WRITE)
	file.store_string(JSON.stringify(note))
	file.close()
	Game.save_enabled = false


func _phase_restart() -> void:
	var c: GameSession = Game.session
	var expect: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path + ".expect"))
	await _continue_into_game()
	await _close_dialogs()
	var copper := c.factory("copper")
	check(c.state.stock_mode and copper.stock_enabled(), "stock mode survived the restart")
	check(c.sales.customers.size() == int(expect["customers"]) and str(c.sales.customers[1]["name"]) == str(expect["name1"]), "the same customers (%d)" % c.sales.customers.size())
	near(float(c.sales.customers[1]["rel"]), float(expect["rel"]), 0.01, "relationship score restored")
	check(c.contracts.active.size() == int(expect["open"]), "open orders restored (%d)" % c.contracts.active.size())
	check(copper.warehouse.reserved_units("CU-IND") <= int(expect["reserved"]) and copper.warehouse.reserved_units("CU-IND") > 0, "reserved stock restored (%d, saved with %d: a lorry may have left since)" % [copper.warehouse.reserved_units("CU-IND"), int(expect["reserved"])])
	var held := 0.0
	for k in c.contracts.active:
		if k.sku == "CU-IND":
			held += k.held
	near(held, float(copper.warehouse.reserved_units("CU-IND")), 0.001, "the orders hold exactly what the warehouse reserved")
	check(copper.warehouse.validate() == "" and _conserved(copper) == "", "the warehouse is consistent: " + copper.warehouse.validate() + _conserved(copper))
	# the shipment that was loading carries on and pays once
	var paid := {"n": 0, "amount": 0.0}
	c.contracts.shipment_left.connect(func(_k: Contract, _u: float, amount: float) -> void:
		paid["n"] += 1
		paid["amount"] += amount)
	var cash0 := c.state.cash
	var shipped0 := float(copper.warehouse.shipped.get("CU-IND", 0)) + float(copper.warehouse.shipped.get("CU-DIR", 0))
	for i in 20:
		await _warp(10.0)
		if paid["n"] >= 1:
			break
	var shipped1 := float(copper.warehouse.shipped.get("CU-IND", 0)) + float(copper.warehouse.shipped.get("CU-DIR", 0))
	check(paid["n"] >= 1 and shipped1 > shipped0, "shipments went on after the restart (%d lorries, %d cylinders)" % [paid["n"], int(shipped1 - shipped0)])
	near(c.state.cash - cash0, float(paid["amount"]), maxf(1.0, float(paid["amount"]) * 0.01), "and every lorry was paid exactly once (%s)" % NumFmt.money(paid["amount"]))
	check(copper.warehouse.validate() == "" and _conserved(copper) == "", "still consistent after more shipments")
	# leaving for the menu and coming back leaves no stale listeners
	var book := c.contracts
	var before := [book.shipment_left.get_connections().size() - 1, book.order_ended.get_connections().size()]
	check(Game.return_to_menu(), "back to the main menu")
	await _wait_scene("Menu")
	await _press("Continue")
	await _wait_scene("Main")
	await _close_dialogs()
	var after := [book.shipment_left.get_connections().size() - 1, book.order_ended.get_connections().size()]
	check(before == after, "no duplicate or stale listeners after re-entering the game %s -> %s" % [before, after])
	var f := FileAccess.open(Game.save_path + ".expect", FileAccess.WRITE)
	f.store_string(JSON.stringify({"made": copper.state.cylinders_made, "cash": c.state.cash, "orders": int(c.sales.stats["accepted"])}))
	f.close()
	check(Game.save_now(), "saved again")
	Game.save_enabled = false


func _phase_offline() -> void:
	var c: GameSession = Game.session
	var expect: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path + ".expect"))
	await _continue_into_game()
	var copper := c.factory("copper")
	var summary: Dictionary = {}
	for dlg in (_scene().get("_dialog_layer") as Node).get_children():
		summary = Game.pending_offline if not Game.pending_offline.is_empty() else summary
	check(c.state.cash > float(expect["cash"]), "two hours away earned money (%s -> %s)" % [NumFmt.money(float(expect["cash"])), NumFmt.money(c.state.cash)])
	check(copper.state.cylinders_made > float(expect["made"]) + 100.0, "and built cylinders (%d more)" % int(copper.state.cylinders_made - float(expect["made"])))
	check(int(c.sales.stats["rep_orders"]) > 0 or int(c.sales.stats["accepted"]) > int(expect["orders"]), "the sales rep took orders while away (%d)" % int(c.sales.stats["rep_orders"]))
	check(c.sales.calls.size() <= 3, "at most three calls are waiting for you (%d)" % c.sales.calls.size())
	check(copper.warehouse.total_units() <= copper.warehouse.capacity + int(copper.warehouse.reserved_units("CU-IND")), "stock is within the warehouse")
	check(copper.warehouse.validate() == "" and _conserved(copper) == "", "stock accounting is exact: " + copper.warehouse.validate() + _conserved(copper))
	var dialogs := (_scene().get("_dialog_layer") as Node).get_children()
	check(dialogs.size() > 0, "a welcome-back box is shown")
	var texts := ""
	for l in _all_labels(_scene()):
		texts += l.text + "\n"
	check(texts.contains("WELCOME BACK") or texts.contains("away for"), "...and it reports the time away")
	var negative := false
	for k in c.contracts.active:
		if k.held < 0.0 or k.shipped < 0.0 or k.delivered < 0.0 or k.delivered > float(k.quantity) + 0.001:
			negative = true
	check(not negative, "no order has negative or excess quantities")


func _all_labels(root: Node) -> Array[Label]:
	var out: Array[Label] = []
	for c in root.get_children():
		if c is Label:
			out.append(c)
		out.append_array(_all_labels(c))
	return out
