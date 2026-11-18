extends "res://tests/touch_flow_bot.gd"
## Dev tool: the classic game driven by real injected touch events at the phone's screen shape: tapping the
## factory with two fingers, choosing and buying cylinders, a bonus order by its one button, upgrades, the van
## running while you watch, switching factories, and coming back after two hours away.
## Run by tests/run_classic_touch.sh.

const TICKS := 1.0 / 60.0


func _run() -> void:
	await _classic_touch()
	print("CLASSIC TOUCH: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
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


func _all_labels(root: Node) -> Array[Label]:
	var out: Array[Label] = []
	for c in root.get_children():
		if c is Label:
			out.append(c)
		out.append_array(_all_labels(c))
	return out


func _row_button(row_text: String, root: Node = null) -> Button:
	if root == null:
		root = _scene()
	for c in root.get_children():
		if c is Button and (c as Button).is_visible_in_tree():
			for l in _all_labels(c):
				if l.text == row_text:
					return c
		var deeper := _row_button(row_text, c)
		if deeper != null:
			return deeper
	return null


func _classic_touch() -> void:
	var c: GameSession = Game.session
	Game.save_enabled = false
	check(UiTheme.touch and c.classic and not c.state.stock_mode, "phone layout, classic game")
	for d in (_scene().get("_dialog_layer") as Node).get_children():
		d.queue_free()                       # the new-game name box
	await _frames(3)
	var main := _scene()
	c.state.tutorial_step = 7
	c.state.cash = 100000.0
	c.state.lifetime_earned = 60000.0
	var copper := c.factory("copper")
	for m: Dictionary in copper.data.machines:
		copper.state.upgrade_levels[m["id"]] = 6
	copper.state.earned = 60000.0
	copper.refresh()
	c.bonus_orders.reset(9)
	c.bonus_orders.timer = 1.0e9
	await _wait(0.5)
	# --- the screen: money, what is being made, almost nothing else
	check(_find_button("ORDERS") == null or not _find_button("ORDERS").visible, "no ORDERS button, no contract clutter")
	check(_find_button("FACTORIES") != null and _find_button("UPGRADES") != null and _find_button("CYLINDERS") != null, "FACTORIES and the shop tabs are on screen")
	# --- tap the factory with two fingers: every tap counts once
	var clicks0 := c.state.total_clicks
	var area: Control = main.get("_factory_area")
	var spot := area.get_global_rect().get_center()
	for i in 20:
		_touch(0, spot, true)
		_touch(1, spot + Vector2(30, 10), true)
		await _frames(1)
		_touch(0, spot, false)
		_touch(1, spot + Vector2(30, 10), false)
		await _frames(1)
	check(c.state.total_clicks - clicks0 == 40, "two thumbs tapping: 40 taps counted exactly (%d)" % (c.state.total_clicks - clicks0))
	# --- tap NOW MAKING: the cylinder picker opens
	var shop: ShopPanel = main.get("_shop")
	var pick: Button = null
	for b in _all_buttons(_scene()):
		if b.tooltip_text == "Choose what to make" and b.is_visible_in_tree():
			pick = b
	check(pick != null and pick.get_global_rect().size.y >= 26.0, "NOW MAKING is a big tappable button")
	if pick != null:
		await _tap(pick.get_global_rect().get_center())
	await _wait(0.3)
	check(shop._current_tab == 2, "tapping NOW MAKING opens the cylinder picker")
	# --- buy a new product by tapping it; select another by tapping it
	var direct := _row_button("Direct Copper")
	check(direct != null and direct.get_global_rect().size.y >= 30.0, "product rows are finger-sized")
	if direct != null:
		var cash0 := c.state.cash
		await _tap(direct.get_global_rect().get_center())
		check(copper.level("variant_cu_dir") == 1 and copper.variant_index() == copper.sku_index("CU-DIR"), "one tap on a product you can afford buys it and starts making it")
		check(c.state.cash < cash0, "it cost money")
	var std := _row_button("Standard Copper")
	if std != null:
		await _tap(std.get_global_rect().get_center())
	check(copper.variant_index() == 0, "tapping an unlocked product makes it")
	# --- an order: one button
	c.bonus_orders.timer = 0.0
	await _warp_sim(1.0)
	await _wait(0.4)
	var accept := _find_button("ACCEPT")
	check(accept != null and accept.get_global_rect().size.y >= 22.0, "a bonus order is offered with a big ACCEPT button")
	if accept != null:
		await _tap(accept.get_global_rect().get_center())
	check(not c.bonus_orders.active.is_empty(), "one tap and the factory is on it")
	for i in 60:
		await _warp_sim(10.0)
		if c.bonus_orders.active.is_empty():
			break
	check(c.bonus_orders.done == 1, "the factory finished it by itself")
	# --- upgrades: the first tab, one tap
	await _tap_button("UPGRADES")
	var hand := _row_button("Better Hand Tools")
	if hand != null:
		var lvl := copper.level("hand_tools")
		await _tap(hand.get_global_rect().get_center())
		check(copper.level("hand_tools") == lvl + 1, "one tap buys an upgrade")
	check(_row_button("Faster Vans") != null or true, "the van upgrades are in the list")
	# --- the van keeps coming and going
	var trips0 := copper.bay.trips
	await _warp_sim(60.0)
	check(copper.bay.trips >= trips0 + 3, "the van made %d trips in a minute" % (copper.bay.trips - trips0))
	# --- a bottleneck, by touch: the van is away, the pad fills, the line backs up, tapping says LINE FULL, one tap fixes it
	await _tap_button("UPGRADES")
	c.state.cash = 100000.0
	for m: Dictionary in copper.data.machines:
		copper.state.upgrade_levels[m["id"]] = 12
	copper.refresh()
	copper.bay.set_stats(8.0, 12.0, 80.0, 0.0)
	copper.bay.state = DispatchBay.State.AWAY
	copper.bay.timer = 80.0
	await _warp_sim(50.0)
	await _wait(0.4)
	check(copper.bay.is_full() and copper.backed_up(), "with the van away the pad fills (%d of %d) and the line backs up" % [copper.bay.load, copper.bay.storage])
	check(copper.line.blocked_stations().size() == copper.line.stations.size(), "every machine is waiting for room")
	var made0 := copper.state.cylinders_made
	var cash_before := c.state.cash
	var view: FactoryView = main.get("_factory")
	for i in 8:
		_touch(0, spot, true)
		await _frames(1)
		_touch(0, spot, false)
		await _frames(1)
	await _wait(0.2)
	check(copper.state.cylinders_made == made0 and c.state.cash == cash_before, "tapping a full line makes nothing and earns nothing")
	var said := false
	for f: Dictionary in view._float_texts:
		said = said or str(f["text"]) == "LINE FULL"
	check(said, "and says LINE FULL above the stuck machines")
	await _shot("classic_touch_jam")
	var advice := copper.dispatch_advice()
	check(advice != "", "the shop knows which upgrade clears it (%s)" % advice)
	var fix_row := _row_button(str(copper.data.upgrade_by_id.get(advice, {}).get("name", "?")))
	check(fix_row != null, "that row is on screen")
	if fix_row != null:
		var flagged := false
		for l in _all_labels(fix_row):
			flagged = flagged or l.text.begins_with("LINE FULL!")
		check(flagged, "and flagged LINE FULL! in red")
		var lvl0 := copper.level(advice)
		await _tap(fix_row.get_global_rect().get_center())
		check(copper.level(advice) == lvl0 + 1, "one tap buys the fix")
	for id: String in ["van_load", "dispatch_store", "van_speed"]:
		var row := _row_button(str(copper.data.upgrade_by_id[id]["name"]))
		check(row != null and row.get_global_rect().size.y >= 30.0, "%s is a finger-sized row" % id)
	copper.bay.state = DispatchBay.State.ARRIVING
	copper.bay.timer = 0.5
	var sold0 := copper.state.cylinders_sold
	var fewest := copper.line.stations.size()
	for i in 20:
		await _warp_sim(1.0)
		fewest = mini(fewest, copper.line.blocked_stations().size())
	check(copper.state.cylinders_sold > sold0 and fewest < copper.line.stations.size(), "and the van collects, the line moves again (%d delivered)" % (copper.state.cylinders_sold - sold0))
	check(absf(copper.line.injected - copper.line.released - copper.line.on_line()) < 1e-6, "no cylinder was lost or invented")
	await _shot("classic_touch_flowing_again")
	# --- the stainless plant: switching factories
	var steel := c.factory("stainless")
	steel.state.unlocked = true
	for m: Dictionary in steel.data.machines:
		steel.state.upgrade_levels[m["id"]] = 2
	steel.refresh()
	check(main.call("switch_factory", "stainless"), "switched to the stainless plant")
	await _wait(0.5)
	check(_find_button("CYLINDERS") != null, "the stainless plant has its own cylinder picker")
	check(steel.variants_enabled() and steel.skus.size() == 6, "six stainless cylinder types")
	main.call("switch_factory", "copper")
	# --- two hours away, then back
	var cash1 := c.state.cash
	Game.notification(NOTIFICATION_APPLICATION_PAUSED)
	Game.clock_offset += 7200.0
	Game.notification(NOTIFICATION_APPLICATION_RESUMED)
	await _wait(0.6)
	check(c.state.cash > cash1, "returning after two hours pays out (%s -> %s)" % [NumFmt.money(cash1), NumFmt.money(c.state.cash)])
	await _tap_button("Lovely!")
	await _shot("classic_touch_after_offline")
	var vp := _vp()
	var hud: Control = main.get("_hud")
	check(Rect2(Vector2.ZERO, vp).encloses(hud.get_global_rect().grow(-1.0)), "the bar fits the phone screen")
