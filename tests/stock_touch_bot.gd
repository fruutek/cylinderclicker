extends "res://tests/touch_flow_bot.gd"
## Dev tool: the warehouse economy's pages driven by real injected touch events at the phone's screen shape:
## ORDERS button, a telephone call answered with a finger, the STOCK tab (target buttons, toggles), CUSTOMERS
## and the SALES REP. Run by tests/run_stock_touch.sh.


func _run() -> void:
	await _stock_touch()
	print("STOCK TOUCH: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	Game.save_enabled = false
	get_tree().quit(1 if _fails > 0 else 0)


func _stock_touch() -> void:
	var c: GameSession = Game.session
	Game.save_enabled = false
	check(UiTheme.touch and c.state.stock_mode, "phone layout with the warehouse economy")
	for d in (_scene().get("_dialog_layer") as Node).get_children():
		d.queue_free()                       # the new-game name box
	await _frames(3)
	c.state.tutorial_step = 7
	c.state.cash = 100000.0
	c.state.lifetime_earned = 20000.0
	var copper := c.factory("copper")
	for m: Dictionary in copper.data.machines:
		copper.state.upgrade_levels[m["id"]] = 6
	copper.state.upgrade_levels["warehouse"] = 3
	copper.refresh()
	c.contracts.reset(5)
	c.contracts.unlocked = true
	c.contracts.offer_timer = 1.0e9
	c.sales.reset(5)
	c.sales.advance(0.2)
	c.sales.timers["copper"] = 1.0e9
	copper.warehouse.receive("CU-IND", 20.0)
	await _wait(0.5)
	# a call comes in
	var cust: Dictionary = c.sales.customers[0]
	cust["rel"] = 70.0
	c.sales.serial += 1
	c.sales.calls.append({"id": "tc1", "serial": c.sales.serial, "customer": cust["id"], "factory": "copper", "sku": "CU-IND", "qty": 12, "factor": 1.05, "expires_in": 120.0, "line": 0.4})
	await _wait(0.6)
	await _tap_button("ORDERS")
	var board: ContractBoard = null
	for d in (_scene().get("_dialog_layer") as Node).get_children():
		if d is ContractBoard:
			board = d
	check(board != null and board._tab_key() == "calls", "tapping ORDERS opens the board on the waiting call")
	await _tap_button("SUPPLY IN FULL")
	check(c.contracts.call_active_count() == 1 and c.sales.calls.is_empty(), "a finger accepted the order (12 reserved: %d)" % copper.warehouse.reserved_units("CU-IND"))
	# STOCK tab
	await _tap_button("STOCK")
	check(board._tab_key() == "stock", "the STOCK tab opens")
	await _tap_button("AUTO TARGETS")
	check(not copper.state.auto_targets, "AUTO TARGETS switched off by touch")
	var before := int(copper.state.targets.get("CU-IND", 0))
	var plus := _first_enabled("+")
	check(plus != null, "a + button is there")
	if plus != null:
		await _tap(plus.get_global_rect().get_center())
		await _wait(0.2)
	check(int(copper.state.targets.get("CU-IND", 0)) > before, "a target went up by touch (%d -> %d)" % [before, int(copper.state.targets.get("CU-IND", 0))])
	check(plus == null or plus.get_global_rect().size.x >= 36.0, "target buttons are fingertip sized (%d px)" % int(plus.get_global_rect().size.x if plus != null else 0))
	await _tap_button("WHOLESALE SURPLUS")
	check(not copper.state.wholesale_on, "WHOLESALE SURPLUS switched off by touch")
	await _tap_button("WHOLESALE SURPLUS")
	await _tap_button("MORE SPACE")
	check(copper.level("warehouse") == 4, "MORE SPACE bought a warehouse level")
	# CUSTOMERS and SALES REP
	await _tap_button("CUSTOMERS")
	check(board._tab_key() == "customers" and board._stock_ui._customers.size() >= 5, "the customers' book lists everybody")
	await _tap_button("SALES REP")
	check(board._tab_key() == "rep", "the SALES REP tab opens")
	await _tap_button("APPLY RECOMMENDED")
	check(not copper.state.auto_targets and int(copper.state.targets.get("CU-IND", 0)) >= 1, "APPLY RECOMMENDED STOCK sets the targets")
	await _tap_button("ACTIVE")
	check(board._tab_key() == "active", "ACTIVE shows the phone order")
	await _shot("stock_touch_active")
	# the board is still within the screen
	var panel_rect: Rect2 = board.get("_panel").get_global_rect()
	check(Rect2(Vector2.ZERO, _vp()).encloses(panel_rect.grow(-1.0)), "the board fits the phone screen (%s in %s)" % [panel_rect.size, _vp()])


func _first_enabled(prefix: String, root: Node = null) -> Button:
	if root == null:
		root = _scene()
	for c in root.get_children():
		if c is Button and (c as Button).text.begins_with(prefix) and (c as Button).is_visible_in_tree() and not (c as Button).disabled:
			return c
		var deeper := _first_enabled(prefix, c)
		if deeper != null:
			return deeper
	return null
