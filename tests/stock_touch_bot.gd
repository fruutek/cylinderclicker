extends "res://tests/touch_flow_bot.gd"
## Dev tool: the phone-first interface driven by real injected touch events at the phone's screen shape:
## the order card on the side deck (all in stock, and part-delivery with production queued), rapid tapping of
## the four destinations and of upgrade rows, AUTO STOCK / MANUAL, the rep's one-tap advice, MORE DETAILS,
## and coming back after two hours away. Run by tests/run_stock_touch.sh.

const TICKS := 1.0 / 60.0


func _run() -> void:
	await _stock_touch()
	print("STOCK TOUCH: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	Game.save_enabled = false
	get_tree().quit(1 if _fails > 0 else 0)


func _warp_sim(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var step := minf(left, 4.0)
		for i in int(step / TICKS):
			Game.session.tick(TICKS)
		left -= step
		await get_tree().process_frame


func _screens() -> Array[Node]:
	var out: Array[Node] = []
	for d in (_scene().get("_dialog_layer") as Node).get_children():
		if d is ScreenFrame and not d.is_queued_for_deletion():
			out.append(d)
	return out


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


## A row of the upgrades list is a button whose label is a child, not its own text.
func _row_button(upgrade_name: String, root: Node = null) -> Button:
	if root == null:
		root = _scene()
	for c in root.get_children():
		if c is Button and (c as Button).is_visible_in_tree():
			for l in _all_labels(c):
				if l.text == upgrade_name:
					return c
		var deeper := _row_button(upgrade_name, c)
		if deeper != null:
			return deeper
	return null


func _all_labels(root: Node) -> Array[Label]:
	var out: Array[Label] = []
	for c in root.get_children():
		if c is Label:
			out.append(c)
		out.append_array(_all_labels(c))
	return out


func _call(c: GameSession, sku: String, qty: int, who: int, rel: float) -> String:
	c.sales.serial += 1
	var cust: Dictionary = c.sales.customers[who]
	cust["rel"] = rel
	var id := "tc%d" % c.sales.serial
	c.sales.calls.append({"id": id, "serial": c.sales.serial, "customer": cust["id"], "factory": "copper", "sku": sku, "qty": qty, "factor": 1.05, "expires_in": 140.0, "line": 0.4})
	return id


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
	copper.state.auto_targets = false
	copper.state.targets = {"CU-IND": 0, "CU-DIR": 0, "CU-HOR": 0, "CU-SLM": 0}
	copper.warehouse.receive("CU-IND", 20.0)
	copper.warehouse.receive("CU-DIR", 6.0)
	await _wait(0.5)
	# --- the main screen shows only what matters
	for nav in ["FACTORY", "ORDERS", "STOCK", "UPGRADES"]:
		check(_find_button(nav) != null, "%s is a button on the main screen" % nav)
	check(_find_button("PROFIT") == null and _find_button("OUTPUT") == null, "no statistics clutter on the main screen")
	check(_find_button("BUY") != null, "with nobody calling, the card offers the next upgrade")
	# --- a customer: everything in stock = one prominent button
	_call(c, "CU-IND", 12, 0, 70.0)
	await _wait(0.6)
	var cash0 := c.state.cash
	await _tap_button("FULFIL ORDER")
	check(c.contracts.call_active_count() == 1, "one tap on FULFIL ORDER accepted it (12 reserved: %d)" % copper.warehouse.reserved_units("CU-IND"))
	await _warp_sim(12.0)
	check(c.contracts.call_active_count() == 0 and c.state.cash > cash0, "the lorry went by itself and it was paid (%s)" % NumFmt.money(c.state.cash - cash0))
	# --- a customer who wants more than there is: SEND 6 + MAKE 12
	_call(c, "CU-DIR", 18, 1, 70.0)
	await _wait(0.6)
	check(_find_button("SEND 6 + MAKE 12") != null and _find_button("SEND 6 ONLY") != null and _find_button("DECLINE") != null, "three plain buttons: SEND 6 + MAKE 12, SEND 6 ONLY, DECLINE")
	cash0 = c.state.cash
	await _tap_button("SEND 6 + MAKE 12")
	var order: Contract = c.contracts.active[0] if not c.contracts.active.is_empty() else null
	check(order != null and order.mode == "partial" and order.quantity == 18, "the part delivery order exists, the missing 12 are queued automatically")
	await _warp_sim(6.0)
	check(order != null and order.shipped >= 6.0 and order.shipped < 18.0, "partial dispatch: the 6 in stock went first (%d sent)" % (int(order.shipped) if order != null else -1))
	check(c.state.cash > cash0, "and they were paid for straight away")
	copper.state.targets = {"CU-IND": 0, "CU-DIR": 0, "CU-HOR": 0, "CU-SLM": 0}
	for i in 12:
		await _warp_sim(10.0)
		if c.contracts.call_active_count() == 0:
			break
	check(c.contracts.call_active_count() == 0 and copper.warehouse.shipped.get("CU-DIR", 0) == 18, "the production queue built the rest and later lorries delivered all 18 (%d)" % copper.warehouse.shipped.get("CU-DIR", 0))
	# --- rapid tapping between the four destinations never stacks or breaks screens
	for i in 12:
		for label in ["STOCK", "ORDERS", "UPGRADES"]:
			var b := _find_button(label)
			if b != null:
				await _tap(b.get_global_rect().get_center())
	await _wait(0.4)
	check(_screens().size() <= 1, "rapid tapping leaves at most one screen open (%d)" % _screens().size())
	# --- UPGRADES: tap a row once, tap it many times quickly
	await _tap_button("UPGRADES")
	check(_screens().size() == 1 and _screens()[0] is UpgradesScreen, "UPGRADES opens its screen")
	var row := _row_button("Better Hand Tools")
	check(row != null, "the list has big tappable rows")
	if row != null:
		var level0 := copper.level("hand_tools")
		var cash1 := c.state.cash
		await _tap(row.get_global_rect().get_center())
		check(copper.level("hand_tools") == level0 + 1, "one tap buys exactly one level")
		for i in 8:
			var again := _row_button("Better Hand Tools")
			if again != null:
				await _tap(again.get_global_rect().get_center())
		check(c.state.cash >= 0.0 and c.state.cash <= cash1, "rapid tapping buys levels but never goes below zero (%s left)" % NumFmt.money(c.state.cash))
	# --- STOCK: AUTO STOCK / MANUAL and the rep's one-tap advice
	await _tap_button("STOCK")
	check(_screens().size() == 1 and _screens()[0] is StockScreen, "STOCK opens its screen")
	copper.warehouse.stock["CU-IND"] = 0
	copper.warehouse.stock["CU-DIR"] = 0
	copper.state.auto_targets = true
	await _wait(0.6)
	await _tap_button("MANUAL")
	check(not copper.state.auto_targets, "MANUAL by touch")
	var plus := _first_enabled("+")
	if plus != null and not _screens().is_empty():
		(_screens()[0].get("_scroll") as ScrollContainer).ensure_control_visible(plus)      # a finger would scroll down to it
		await _frames(3)
	check(plus != null and plus.get_global_rect().size.x >= 30.0 and plus.get_global_rect().size.y >= 30.0, "target buttons are fingertip sized")
	var before := int(copper.state.targets.get("CU-IND", 0))
	if plus != null:
		await _tap(plus.get_global_rect().get_center())
	check(int(copper.state.targets.get("CU-IND", 0)) == before + 1 or int(copper.state.targets.get("CU-IND", 0)) > before, "+ raises a target")
	await _tap_button("AUTO STOCK")
	check(copper.state.auto_targets, "AUTO STOCK by touch")
	var restock := _find_button("RESTOCK RECOMMENDED")
	if restock != null:
		await _tap(restock.get_global_rect().get_center())
		check(not copper.state.priority.is_empty(), "RESTOCK RECOMMENDED is one tap")
	var wh0 := copper.warehouse.capacity
	_call(c, "CU-IND", 6, 2, 50.0)
	# --- ORDERS and MORE DETAILS
	await _tap_button("ORDERS")
	check(_screens().size() == 1 and _screens()[0] is OrdersScreen, "ORDERS opens its screen")
	check(_find_button("DECLINE") != null, "the waiting customer is there too")
	await _tap_button("DECLINE")
	await _tap_button("MORE DETAILS")
	var board: Node = null
	for d in (_scene().get("_dialog_layer") as Node).get_children():
		if d is ContractBoard:
			board = d
	check(board != null, "MORE DETAILS leads to the advanced Contract Board")
	for d in (_scene().get("_dialog_layer") as Node).get_children():
		d.queue_free()
	await _frames(3)
	# --- two hours away, then back
	var cash2 := c.state.cash
	copper.state.auto_targets = true
	Game.notification(NOTIFICATION_APPLICATION_PAUSED)
	Game.clock_offset += 7200.0
	Game.notification(NOTIFICATION_APPLICATION_RESUMED)
	await _wait(0.6)
	check(c.state.cash > cash2, "returning after two hours pays out (%s -> %s)" % [NumFmt.money(cash2), NumFmt.money(c.state.cash)])
	check(c.sales.calls.size() <= 2, "no flood of calls: at most two are waiting (%d)" % c.sales.calls.size())
	check(copper.warehouse.validate() == "", "stock is consistent after time away: " + copper.warehouse.validate())
	await _tap_button("Lovely!")
	await _shot("stock_touch_after_offline")
	var vp := _vp()
	await _tap_button("ORDERS")
	var panel_rect: Rect2 = (_screens()[0].get("_panel") as Control).get_global_rect() if not _screens().is_empty() else Rect2()
	check(Rect2(Vector2.ZERO, vp).encloses(panel_rect.grow(-1.0)), "the screens fit the phone (%s in %s)" % [panel_rect.size, vp])
	check(wh0 > 0, "done")
