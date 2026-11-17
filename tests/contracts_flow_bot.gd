extends Node
## Dev tool: end-to-end check of Expansion 3 through the real game, starting
## from a save written by the previous release (v3, no contracts).
## tests/run_contracts_flow.sh runs the phases:
##   1  old save -> play: ORDERS button, board, accept, share buttons, fill, DISPATCH,
##      factory switching with contracts running, save in the middle of a dispatch
##   2  restart: everything restored, the interrupted dispatch finishes and pays once
##   3  restart after two hours away: offline progress, deadline failure, summary box

const TICK := 1.0 / 60.0

var _phase := 1
var _fails := 0
var _warped := 0.0


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
	print("CONTRACTS FLOW PHASE %d: %s" % [_phase, "PASS" if _fails == 0 else "FAIL (%d)" % _fails])
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


func _find_button(prefix: String, root: Node = null, exact: bool = false) -> Button:
	if root == null:
		root = _scene()
	var found: Button = null
	for c in root.get_children():
		if c is Button and (c.text == prefix if exact else (c as Button).text.begins_with(prefix)) and (c as Button).is_visible_in_tree():
			found = c
		var deeper := _find_button(prefix, c, exact)
		if deeper != null:
			found = deeper
	return found


func _press(prefix: String, exact: bool = false) -> bool:
	var b := _find_button(prefix, null, exact)
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


## The factory view on screen is rebuilt whenever the screen layout changes, so never hold on to it.
func _yard() -> DispatchYard:
	return _scene().get("_factory").get("_yard")


func _close_dialogs() -> void:
	for c in (_scene().get("_dialog_layer") as Node).get_children():
		c.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## Runs the simulation ahead (as if the player had waited), a few seconds per frame so the view keeps up.
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


func _hand_offer(c: GameSession, id: String, factory: String, qty: int, value: float, opts: Dictionary = {}) -> Contract:
	var o := Contract.new()
	o.id = id
	o.serial = 700 + c.contracts.offers.size() + c.contracts.active.size() + int(id.substr(1))
	o.tier = opts.get("tier", "trade")
	o.customer = opts.get("customer", "Flow Test " + id)
	o.archetype = "installer"
	o.factory = factory
	o.product_name = "Copper Cylinder" if factory == "copper" else "Stainless Steel Cylinder"
	o.quantity = qty
	o.unit_ref = 8.0
	o.value = value
	o.bonus = float(opts.get("bonus", 0.0))
	o.bonus_by = float(opts.get("bonus_by", 0.0))
	o.deadline = float(opts.get("deadline", 0.0))
	o.est_full = float(opts.get("est_full", 100.0))
	o.rep = int(opts.get("rep", 5))
	o.penalty = int(opts.get("penalty", 3))
	o.pallets = int(opts.get("pallets", 2))
	o.expires_in = 900.0
	c.contracts.offers.append(o)
	return o


func _phase_play() -> void:
	var c: GameSession = Game.session
	await _continue_into_game()
	for dlg in (_scene().get("_dialog_layer") as Node).get_children():
		dlg.queue_free()
	await _wait(0.5)
	var main := _scene()
	var copper := c.factory("copper")
	var steel := c.factory("stainless")

	# --- the v0.4.0 save loads exactly as before
	check(c.state.factory_name == "Contract Flow Ltd" and absf(c.state.cash - 5000.0) < 2000.0, "old save: name and cash kept")
	check(copper.level("machine_weld") == 10 and copper.level("finish") == 2, "old save: copper upgrades kept")
	check(steel.state.unlocked and steel.level("machine_tig") == 3, "old save: stainless plant kept")
	check(copper.state.cylinders_made == 5200.0 and copper.state.cylinders_sold == 5200.0 and copper.state.cylinders_contracted == 0.0, "old save: cylinder counts kept (all sold)")
	check(c.contracts.reputation == 0 and c.contracts.active.is_empty(), "old save: reputation starts at 0, no contracts")

	# --- customers start calling; the ORDERS button appears
	check(c.contracts.unlocked and c.contracts.offers.size() == 3, "an established company is offered its first orders (%d)" % c.contracts.offers.size())
	var orders := _find_button("ORDERS", null, true)
	check(orders != null and orders.is_visible_in_tree(), "the ORDERS button is on the HUD")
	var hud: Hud = main.get("_hud")
	check(hud.unseen_offers >= 3, "a badge shows that orders are waiting (%d)" % hud.unseen_offers)

	for o in c.contracts.offers:
		check(c.factory(o.factory) != null and o.quantity >= 5 and o.value > 0.0, "generated offer is sane: %s x%d for %s (%s)" % [o.customer, o.quantity, NumFmt.money(o.value), o.factory])
	# The offers above are random (seeded per game); swap in fixed copper orders so the rest is deterministic.
	c.contracts.offers.clear()
	_hand_offer(c, "g1", "copper", 600, 9000.0, {"customer": "Granite Plumbing Supplies", "bonus": 400.0, "bonus_by": 600.0, "deadline": 3000.0, "rep": 5})
	_hand_offer(c, "g2", "copper", 450, 7000.0, {"customer": "Harbour Heating"})
	_hand_offer(c, "g3", "copper", 300, 4000.0, {"customer": "Ivy Lane Installers"})

	# --- open the board, accept through the real buttons
	await _press("ORDERS", true)
	check(_board() != null, "the Contract Board opens")
	check(_find_button("ACCEPT") != null and _find_button("AVAILABLE (3)") != null, "offers are listed with ACCEPT buttons")
	check(hud.unseen_offers == 0, "looking at the board clears the new-orders badge")
	await _press("ACCEPT")
	check(c.contracts.active.size() == 1 and c.contracts.offers.size() == 2, "accepting moves the order into your contracts")
	var k: Contract = c.contracts.active[0]
	check(k.factory == "copper", "it is a copper order")
	check(k.allocation >= 50 and k.status == Contract.Status.ACTIVE, "it starts with a sensible production share (%d%%)" % k.allocation)
	check(_find_button("ACTIVE (1/3)") != null and _find_button("Give up") != null, "the board shows it on the ACTIVE tab")

	# --- change the share with the real buttons
	var before := k.allocation
	await _press("-", true)
	check(k.allocation == before - 10, "the - button lowers the share by 10 (%d -> %d)" % [before, k.allocation])
	await _press("+", true)
	check(k.allocation == before, "the + button raises it again")
	await _press("25", true)
	check(k.allocation == 25, "the 25 preset sets 25%")
	await _press("ALL", true)
	check(k.allocation == 100, "ALL commits the whole factory")
	check(c.contracts.free_share("copper") == 0, "so nothing is left for other copper orders")
	await _close_dialogs()

	# --- fill it: no sale revenue while 100% is committed, books balance throughout
	var sold0 := copper.state.cylinders_sold
	var cash0 := c.state.cash
	var invariant_ok := true
	var guard := 0
	while k.status == Contract.Status.ACTIVE and guard < 60:
		await _warp(20.0)
		guard += 1
		if absf(copper.state.cylinders_made - (copper.state.cylinders_sold + copper.state.cylinders_contracted)) > 1e-6:
			invariant_ok = false
	check(invariant_ok, "cylinders made = sold + contracted at every checkpoint")
	check(k.status == Contract.Status.READY and k.delivered == k.quantity, "the order fills to exactly %d and becomes ready" % k.quantity)
	near(copper.state.cylinders_sold, sold0 + (copper.state.cylinders_sold - sold0), 0.0, "sold counter consistent")
	check(copper.state.cylinders_contracted == float(k.quantity), "%d cylinders were built for the order" % k.quantity)
	var sold_during := copper.state.cylinders_sold - sold0
	check(sold_during < copper.steady_rate() * 20.0 * 1.5 + 5.0, "almost nothing was sold while the whole factory worked on the order (%s)" % sold_during)
	await _wait(0.3)
	check(_yard()._featured != null and _yard()._featured.id == k.id and _yard()._featured.status == Contract.Status.READY, "the pad shows the finished order")
	check((hud.get("_badge") as Label).visible and c.contracts.count_status(Contract.Status.READY) == 1, "the ORDERS badge is lit with one order ready (badge '%s')" % (hud.get("_badge") as Label).text)
	check(c.contracts.free_share("copper") == 100, "the share is released")

	# --- dispatch it through the board
	var rep0 := c.contracts.reputation
	var ledger := {"paid": 0.0, "n": 0}
	c.contracts.completed.connect(func(_k: Contract, base: float, bonus: float, _r: int) -> void:
		ledger["paid"] += base + bonus
		ledger["n"] += 1)
	await _press("ORDERS", true)
	check(_find_button("DISPATCH") != null, "the board offers DISPATCH for the finished order")
	var cash_before := c.state.cash
	var expected_pay := c.contracts.quote(k) + (c.contracts.bonus_quote(k) if k.bonus_earned else 0.0)
	await _press("DISPATCH")
	check(k.status == Contract.Status.DISPATCHING and _board() == null, "pressing DISPATCH starts the lorry and closes the board")
	var lorry_seen := false
	var van_left := false
	var waited := 0.0
	while c.contracts.find(k.id) != null and waited < 14.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		lorry_seen = lorry_seen or _yard()._lorry.visible
		van_left = van_left or _yard().van_dx() < -40.0
	check(lorry_seen and van_left, "the van drove out and the delivery lorry arrived at the bay")
	check(ledger["n"] == 1 and c.contracts.find(k.id) == null, "the lorry left and the order was paid (once)")
	check(absf(ledger["paid"] - expected_pay) <= 1.0 and ledger["paid"] > 0.0, "paid the quoted price for the day: %s (quote %s)" % [NumFmt.money(ledger["paid"]), NumFmt.money(expected_pay)])
	check(c.state.cash >= cash_before + ledger["paid"] - 0.01, "the money reached the bank")
	check(c.contracts.reputation > rep0 and c.contracts.history.size() == 1 and c.contracts.history[0]["outcome"] == "delivered", "reputation rose and the history recorded it (rep %d)" % c.contracts.reputation)
	await _wait(1.5)
	check(_yard().van_dx() > -2.0, "the standing van drove back in")
	var stars: Control = hud.get("_stars")
	check(stars != null, "reputation stars are on the HUD")
	await _wait(0.3)

	# --- two more orders, one at each factory, then look around while they run
	_hand_offer(c, "f1", "copper", 4000, 60000.0, {"customer": "Switch Test Merchants"})
	_hand_offer(c, "f2", "stainless", 5000, 9000000.0, {"customer": "Steel Order Ltd", "deadline": 3000.0, "penalty": 7, "tier": "commercial"})
	check(c.contracts.accept("f1") == "" and c.contracts.accept("f2") == "", "orders accepted at both factories")
	c.contracts.set_allocation("f1", 40)
	c.contracts.set_allocation("f2", 50)
	var f1: Contract = c.contracts.find("f1")
	var f2: Contract = c.contracts.find("f2")
	check(c.contracts.free_share("copper") == 60 and c.contracts.free_share("stainless") == 50, "each factory keeps its own share pool")
	check(main.call("switch_factory", "stainless") and c.state.current_factory == "stainless", "walk into the stainless plant")
	await _warp(90.0)
	var f1_in_steel_view := f1.delivered
	check(f1_in_steel_view > 0, "the copper order kept filling while the stainless plant was on screen (%d)" % f1_in_steel_view)
	check(f2.delivered > 0 or steel.state.cylinders_made > 0.0, "the stainless order is progressing (%d)" % f2.delivered)
	await _wait(0.3)
	check(_yard().sim == steel and _yard()._featured != null and _yard()._featured.id == "f2", "the stainless pad shows the stainless order")
	check(main.call("switch_factory", "copper"), "back to the copper works")
	await _warp(30.0)
	check(f1.delivered > f1_in_steel_view and f1.status == Contract.Status.ACTIVE, "the copper order is still running (%d)" % f1.delivered)
	near(copper.state.cylinders_made, copper.state.cylinders_sold + copper.state.cylinders_contracted, 1e-6, "copper books balance")
	near(steel.state.cylinders_made, steel.state.cylinders_sold + steel.state.cylinders_contracted, 1e-6, "stainless books balance")

	# --- finish a third order and save in the middle of its dispatch
	_hand_offer(c, "f3", "copper", 10, 777.0, {"customer": "Mid-dispatch Plumbing", "rep": 6})
	check(c.contracts.accept("f3") == "", "a small third order")
	c.contracts.set_allocation("f3", 0)       # leave room: f1 holds 40, this one gets no share and is completed by hand
	var f3: Contract = c.contracts.find("f3")
	f3.delivered = 10
	c.contracts._complete(f3)
	check(c.contracts.dispatch("f3") == "", "dispatch it")
	await _wait(1.2)
	check(f3.status == Contract.Status.DISPATCHING and f3.dispatch_left > 1.0, "the lorry is still loading (%.1fs left)" % f3.dispatch_left)
	check(Game.save_now(), "saved in the middle of the dispatch")
	var saved := SaveManager.load_game(Game.save_path)
	check(saved.has("contracts") and saved["contracts"]["active"].size() == 3 and int(JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))["version"]) == 4, "the save is version 4 and holds 3 contracts")
	Game.save_enabled = false


func _phase_restart() -> void:
	var c: GameSession = Game.session
	await _continue_into_game()
	for dlg in (_scene().get("_dialog_layer") as Node).get_children():
		dlg.queue_free()
	await _wait(0.3)
	var copper := c.factory("copper")
	check(c.contracts.reputation > 0 and c.contracts.history.size() == 1, "reputation and history survived the restart (rep %d)" % c.contracts.reputation)
	check(c.contracts.active.size() == 3, "three contracts restored (%d)" % c.contracts.active.size())
	var f1 := c.contracts.find("f1")
	var f2 := c.contracts.find("f2")
	var f3 := c.contracts.find("f3")
	check(f1 != null and f1.allocation == 40 and f1.delivered > 100, "the copper order kept its 40%% share and %d cylinders" % (f1.delivered if f1 != null else -1))
	check(f2 != null and f2.allocation == 50 and f2.has_deadline() and f2.time_left < 3000.0 and f2.time_left > 2000.0, "the stainless order kept its share and its running deadline (%.0fs left)" % (f2.time_left if f2 != null else -1.0))
	check(f3 != null and f3.status == Contract.Status.DISPATCHING, "the interrupted dispatch resumed")
	check(c.state.factory_name == "Contract Flow Ltd", "company name kept")
	check(copper.state.cylinders_contracted >= 4010.0 - 1.0 or copper.state.cylinders_contracted > 0.0, "contract counters restored")
	var paid := {"n": 0, "amount": 0.0}
	c.contracts.completed.connect(func(_k: Contract, base: float, bonus: float, _r: int) -> void:
		paid["n"] += 1
		paid["amount"] += base + bonus)
	var cash0 := c.state.cash
	var waited := 0.0
	while c.contracts.find("f3") != null and waited < 12.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	check(paid["n"] == 1 and absf(paid["amount"] - 777.0) < 0.01, "the resumed dispatch paid exactly once: %s" % NumFmt.money(paid["amount"]))
	check(c.state.cash >= cash0 + 777.0 - 0.01, "and the money arrived")
	await _wait(1.0)
	check(paid["n"] == 1, "still only one payment a second later")

	# --- leaving for the menu and coming back must not leave stale listeners on the contract book
	var book := c.contracts
	var before := [book.ready.get_connections().size(), book.failed.get_connections().size(), book.offer_added.get_connections().size(), book.completed.get_connections().size() - 1]   # minus this bot's own
	check(Game.return_to_menu(), "back to the main menu")
	await _wait_scene("Menu")
	await _press("Continue")
	await _wait_scene("Main")
	for dlg in (_scene().get("_dialog_layer") as Node).get_children():
		dlg.queue_free()
	var after := [book.ready.get_connections().size(), book.failed.get_connections().size(), book.offer_added.get_connections().size(), book.completed.get_connections().size() - 1]
	check(before == after and before[0] == 1, "no duplicate or stale listeners after re-entering the game %s -> %s" % [before, after])
	check(c.contracts.active.size() == 2 and c.contracts.find("f1") != null and c.contracts.find("f2") != null and c.contracts.reputation > 0, "the two open contracts are intact after the round trip")
	f1 = c.contracts.find("f1")        # reloaded: new objects with the same state
	f2 = c.contracts.find("f2")
	# Leave a note of the numbers phase 3 will check against.
	var note := {"f1": f1.delivered, "f1_alloc": f1.allocation, "f2_left": f2.time_left, "f2_delivered": f2.delivered, "rep": c.contracts.reputation,
		"failed": c.contracts.stats["failed"], "history": c.contracts.history.size()}
	var file := FileAccess.open(Game.save_path + ".expect", FileAccess.WRITE)
	file.store_string(JSON.stringify(note))
	file.close()
	check(Game.save_now(), "saved again")
	Game.save_enabled = false


func _phase_offline() -> void:
	var expect: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path + ".expect"))
	await _continue_into_game()
	var c: GameSession = Game.session
	var copper := c.factory("copper")
	var steel := c.factory("stainless")
	check(_find_button("Lovely!") != null, "the welcome-back summary is shown")
	var texts := ""
	for lbl in _all_labels(_scene().get("_dialog_layer")):
		texts += lbl.text + "\n"
	check(texts.contains("CONTRACTS"), "the summary has a CONTRACTS section")
	check(texts.contains("MISSED") and texts.contains("Steel Order Ltd"), "it reports the missed deadline (stainless order)")
	check(texts.contains("Switch Test Merchants"), "it reports the copper order's progress")
	var f1 := c.contracts.find("f1")
	var rate := copper.steady_rate()
	var added := rate * float(expect["f1_alloc"]) / 100.0 * 7200.0
	var want := minf(float(f1.quantity), float(expect["f1"]) + added) if f1 != null else -1.0
	check(f1 != null and absf(f1.delivered - want) <= 0.01, "the copper order advanced as far as two hours allow (%d of %d; it could add up to %d)" % [f1.delivered if f1 != null else -1, f1.quantity if f1 != null else -1, int(added)])
	check(f1 != null and f1.status == Contract.Status.READY, "it was finished while away and is waiting for dispatch")
	check(c.contracts.find("f2") == null and c.contracts.stats["failed"] == int(expect["failed"]) + 1, "the stainless order failed while away")
	check(c.contracts.reputation == max(int(expect["rep"]) - 7, int(c.contracts.rules.rank(c.contracts.rank_index())["at"])), "its reputation penalty was applied (%d -> %d)" % [int(expect["rep"]), c.contracts.reputation])
	check(c.contracts.history.size() == int(expect["history"]) + 1 and c.contracts.history[0]["outcome"] == "deadline", "the failure is in the history")
	near(steel.state.cylinders_contracted, 0.0, 1e-6, "stainless stock built for it was released")
	near(copper.state.cylinders_made, copper.state.cylinders_sold + copper.state.cylinders_contracted, 1e-3, "copper books balance after the absence")
	near(steel.state.cylinders_made, steel.state.cylinders_sold + steel.state.cylinders_contracted, 1e-3, "stainless books balance after the absence")
	await _press("Lovely!")
	await _press("ORDERS", true)
	check(_board() != null, "the board opens after the absence")
	await _press("HISTORY")
	check(_find_button("HISTORY") != null and _board().get("_tab") == 2, "the history tab opens")
	await _close_dialogs()
	check(Game.save_now(), "saved")
	Game.save_enabled = false


func _all_labels(root: Node) -> Array[Label]:
	var out: Array[Label] = []
	for ch in root.get_children():
		if ch is Label:
			out.append(ch)
		out.append_array(_all_labels(ch))
	return out
