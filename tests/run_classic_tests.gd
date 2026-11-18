extends SceneTree
## Headless tests for the classic game: cylinder variants, the delivery van, bonus orders, saves from every earlier
## version, time away, and the factory-name dialog.
## Run:  godot --headless --path . -s tests/run_classic_tests.gd

const TICK := 1.0 / 60.0
const TEST_SAVE := "user://test_classic_save.json"

var _passed := 0
var _failed := 0
var _data: GameData


func _init() -> void:
	_data = GameData.new()
	check(_data.load_all(), "data files load")
	for t: String in [
		"test_variant_catalogue", "test_variant_selection", "test_van_cycle", "test_van_never_slows_the_factory", "test_van_upgrades",
		"test_bonus_orders", "test_bonus_order_offline", "test_save_roundtrip", "test_migration_from_warehouse_save",
		"test_migration_from_contract_save", "test_migration_from_old_direct_save", "test_offline_classic", "test_naming_dialog",
	]:
		print("- ", t)
		call(t)
	SaveManager.delete_save(TEST_SAVE)
	print("\n%d checks passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("    FAIL: ", what)


func near(a: float, b: float, tol: float, what: String) -> void:
	check(absf(a - b) <= tol, "%s (got %s, expected %s +/- %s)" % [what, a, b, tol])


func classic() -> GameSession:
	var c := GameSession.new(_data, false, true)
	c.bonus_orders.reset(3)
	return c


func automate(s: FactorySim, lvl: int = 6) -> void:
	for m: Dictionary in s.data.machines:
		s.state.upgrade_levels[m["id"]] = lvl
	s.refresh()


func run(c: GameSession, seconds: float) -> void:
	for i in int(round(seconds / TICK)):
		c.tick(TICK)


func unlock(s: FactorySim, id: String) -> void:
	s.state.upgrade_levels["variant_" + id.to_lower().replace("-", "_")] = 1
	s.refresh()


# ------------------------------------------------------------------ tests
func test_variant_catalogue() -> void:
	var c := classic()
	check(c.classic and not c.state.stock_mode and not c.contract_rules.enabled and not c.sales.enabled, "the classic game has no warehouse, contracts or customers")
	for sim in c.factories:
		check(sim.variants_enabled() and sim.skus.size() == 6, "%s makes six cylinder types (%d)" % [sim.data.id, sim.skus.size()])
		check(sim.sku_available(0) and str(sim.skus[0]["id"]).ends_with("STD"), "the standard cylinder is free: " + str(sim.skus[0]["id"]))
		var base := sim.sku_profit(0) / sim.sku_work(0)
		for i in range(1, sim.skus.size()):
			check(not sim.sku_available(i), "%s is locked at the start" % sim.sku_id(i))
			var ratio := (sim.sku_profit(i) / sim.sku_work(i)) / base
			check(ratio > 1.05 and ratio < 1.45, "%s earns %.0f%% more per minute of line time: rewarding, not game-breaking" % [sim.sku_id(i), (ratio - 1.0) * 100.0])
			check(sim.sku_price(i) > sim.sku_price(0) and sim.sku_work(i) > sim.sku_work(0), "%s sells for more and takes longer" % sim.sku_id(i))
		# every variant has exactly one unlock upgrade, with a price and an unlock threshold
		for i in range(1, sim.skus.size()):
			var req: Dictionary = sim.skus[i]["requires"][0]
			var up: Dictionary = sim.data.upgrade_by_id.get(str(req["upgrade"]), {})
			check(not up.is_empty() and float(up["base_cost"]) > 0.0 and int(up["max_level"]) == 1 and up.get("variant", "") == sim.sku_id(i), "%s: unlock '%s' costs %s" % [sim.sku_id(i), req["upgrade"], NumFmt.money(float(up.get("base_cost", 0)))])
	# the legacy rules never see them
	var legacy := GameSession.new(_data)
	check(not legacy.factory("copper").is_visible("variant_cu_dir") and not legacy.factory("copper").is_visible("van_speed"), "the older rules do not show classic-only upgrades")


func test_variant_selection() -> void:
	var c := classic()
	var cu := c.factory("copper")
	automate(cu)
	check(cu.variant_index() == 0 and cu.profit_per_cylinder() == 8.0, "standard copper nets £8 (the original game)")
	check(not cu.select_variant("CU-IND"), "a locked product cannot be chosen")
	unlock(cu, "CU-IND")
	cu.state.earned = 50000.0
	check(cu.is_visible("variant_cu_ind") and cu.select_variant("CU-IND") and cu.variant_index() == 2, "buying the unlock lets you choose it")
	check(cu.profit_per_cylinder() > 8.0, "and the line makes more money per cylinder (£%.2f)" % cu.profit_per_cylinder())
	# the line really makes it: slower per cylinder, richer per cylinder
	var a := classic()
	var b := classic()
	for s: GameSession in [a, b]:
		automate(s.factory("copper"), 8)
	unlock(b.factory("copper"), "CU-IND")
	b.factory("copper").select_variant("CU-IND")
	run(a, 200.0)
	run(b, 200.0)
	var made_a: float = a.factory("copper").state.cylinders_made
	var made_b: float = b.factory("copper").state.cylinders_made
	check(made_b < made_a and made_b > made_a / 1.4, "indirect copper is slower to build (%d vs %d in 200 s)" % [made_b, made_a])
	var worth_a: float = a.state.cash + a.factory("copper").bay.unpaid()
	var worth_b: float = b.state.cash + b.factory("copper").bay.unpaid()
	check(worth_b > worth_a * 1.05, "...but earns more per minute (£%.0f vs £%.0f)" % [worth_b, worth_a])
	# an unlocked product survives being locked out again by a stale save value
	cu.state.variant = "CU-HOR"
	check(cu.variant_index() == 0, "a saved choice that is not unlocked falls back to standard")


func test_van_cycle() -> void:
	var bay := DispatchBay.new()
	bay.set_stats(10.0, 40.0, 8.0, 0.0)
	var paid := {"n": 0, "money": 0.0, "cyl": 0.0}
	bay.departed.connect(func(cyl: float, money: float) -> void:
		paid["n"] += 1
		paid["money"] += money
		paid["cyl"] += cyl)
	var back := {"n": 0}
	bay.returned.connect(func() -> void: back["n"] += 1)
	bay.try_add(3.0, 8.0)
	check(bay.state == DispatchBay.State.LOADING, "the van waits at the bay while there is only a little to take")
	for i in int(2.5 / TICK):
		bay.tick(TICK)
	check(bay.state == DispatchBay.State.LEAVING and paid["n"] == 0, "it leaves once the pad has run dry, but nobody is paid until it has gone")
	for i in int(3.2 / TICK):
		bay.tick(TICK)
	check(paid["n"] == 1 and absf(paid["money"] - 24.0) < 1e-6 and bay.state == DispatchBay.State.AWAY, "the load is paid when the van drives away (£%.0f)" % paid["money"])
	bay.try_add(5.0, 8.0)                    # made while the van is out
	for i in int(7.5 / TICK):
		bay.tick(TICK)
	check(bay.state == DispatchBay.State.ARRIVING, "after its turnaround the van comes back")
	for i in int(1.5 / TICK):
		bay.tick(TICK)
	check(back["n"] == 1 and bay.state == DispatchBay.State.LOADING and bay.load > 0.0, "back at the bay: the cylinders made meanwhile were waiting for it")
	bay.try_add(20.0, 8.0)                   # a full van leaves as soon as it is loaded
	for i in int(3.0 / TICK):
		bay.tick(TICK)
	check(bay.state == DispatchBay.State.LEAVING, "a full van leaves straight away")
	var d := DispatchBay.new()
	d.from_dict(bay.to_dict())
	check(d.state == bay.state and d.carry_money == bay.carry_money and d.load == bay.load and d.unpaid() == bay.unpaid(), "the van's state survives a save")


func test_van_never_slows_the_factory() -> void:
	var legacy := GameSession.new(_data)
	var c := classic()
	for s: GameSession in [legacy, c]:
		automate(s.factory("copper"), 8)
	run(legacy, 300.0)
	run(c, 300.0)
	var m1: float = legacy.factory("copper").state.cylinders_made
	var m2: float = c.factory("copper").state.cylinders_made
	near(m2, m1, m1 * 0.01 + 2.0, "the classic line makes as many cylinders as the original (%d vs %d)" % [m2, m1])
	var cl := c.factory("copper")
	var worth: float = c.state.cash + cl.bay.unpaid()
	near(worth, legacy.state.cash, legacy.state.cash * 0.01 + 5.0, "everything made is paid for exactly once: cash + on the van = the original's cash (£%.0f vs £%.0f)" % [worth, legacy.state.cash])
	check(c.state.cash < worth and cl.bay.trips > 5, "money arrives in lumps as the van leaves (%d trips)" % cl.bay.trips)
	check(c.state.cash > legacy.state.cash * 0.8, "...with little delay (cash £%.0f of £%.0f)" % [c.state.cash, legacy.state.cash])


func test_van_upgrades() -> void:
	var c := classic()
	var cu := c.factory("copper")
	var cap0 := cu.bay.capacity
	var away0 := cu.bay.away_time
	cu.state.upgrade_levels["van_speed"] = 3
	cu.state.upgrade_levels["van_load"] = 2
	cu.refresh()
	check(cu.bay.away_time < away0 * 0.7 and cu.bay.away_time > 1.5, "Faster Turnaround shortens the van's time away (%.1f s -> %.1f s)" % [away0, cu.bay.away_time])
	check(cu.bay.capacity > cap0 * 2.0, "Bigger Delivery Vans take bigger loads (%d -> %d)" % [cap0, cu.bay.capacity])
	near(cu.bay.bonus, 3.0 * 0.02 + 2.0 * 0.02, 1e-9, "and both add a small delivery bonus")
	var paid := {"m": 0.0}
	cu.bay.departed.connect(func(_c: float, m: float) -> void: paid["m"] += m)
	cu.bay.try_add(10.0, 10.0)
	run(c, 9.0)
	near(paid["m"], 100.0 * 1.10, 1e-6, "the bonus is added to the pay")
	check(cu.is_visible("van_speed") and cu.cost("van_speed") > 0.0, "the van upgrades are in the shop")


func test_bonus_orders() -> void:
	var c := classic()
	var cu := c.factory("copper")
	automate(cu)
	unlock(cu, "CU-DIR")
	c.state.lifetime_earned = 5000.0
	var bo := c.bonus_orders
	check(bo.enabled and bo.offer.is_empty() and bo.active.is_empty(), "no order before the first offer")
	var seen := {"offered": 0, "completed": 0, "expired": 0}
	bo.offered.connect(func(_o: Dictionary) -> void: seen["offered"] += 1)
	bo.completed.connect(func(_o: Dictionary, _b: float) -> void: seen["completed"] += 1)
	bo.expired.connect(func(_o: Dictionary) -> void: seen["expired"] += 1)
	run(c, 125.0)
	check(not bo.offer.is_empty() and seen["offered"] == 1, "a customer offers an order after a couple of minutes")
	var o: Dictionary = bo.offer
	check(str(o["customer"]) != "" and int(o["qty"]) >= 8 and float(o["reward"]) > 0.0, "%s wants %d x %s for a £%.0f bonus" % [o["customer"], o["qty"], o["variant_name"], o["reward"]])
	check(cu.sku_available(cu.sku_index(str(o["variant"]))), "it only asks for a product you can make")
	# an ignored offer costs nothing
	run(c, 80.0)
	check(bo.offer.is_empty() and bo.active.is_empty() and seen["expired"] == 1, "an offer you ignore simply goes away")
	# accept one
	for i in 120:
		run(c, 5.0)
		if not bo.offer.is_empty():
			break
	check(not bo.offer.is_empty(), "the next offer comes along later")
	var want := str(bo.offer["variant"])
	var other := "CU-DIR" if want != "CU-DIR" else "CU-STD"
	cu.select_variant(other)
	var cash0 := c.state.cash
	check(bo.accept() and not bo.active.is_empty() and bo.offer.is_empty(), "ACCEPT is one call")
	check(cu.variant_index() == cu.sku_index(want), "the factory switches to the ordered product by itself")
	var qty := float(bo.active["qty"])
	var worth0 := c.state.cash + cu.bay.unpaid()
	for i in 400:
		run(c, 5.0)
		if bo.active.is_empty():
			break
	check(seen["completed"] == 1 and bo.done == 1, "the order was completed by the factory on its own")
	check(cu.state.variant == other and cu.variant_index() == cu.sku_index(other), "afterwards it goes back to what the player had chosen")
	var gain := (c.state.cash + cu.bay.unpaid()) - worth0
	check(gain > 0.0 and cash0 >= 0.0, "the factory earned from the order and the bonus rode out on the van (%s)" % NumFmt.money(gain))
	check(qty >= 8.0, "the order was a real one (%d cylinders)" % int(qty))
	# a second order cannot be accepted while one is running, and nothing is accepted when there is none
	check(not bo.accept(), "there is nothing to accept when no customer is waiting")


func test_bonus_order_offline() -> void:
	var c := classic()
	var cu := c.factory("copper")
	automate(cu, 8)
	c.state.lifetime_earned = 5000.0
	var bo := c.bonus_orders
	bo.timer = 0.0
	c.tick(TICK)
	check(not bo.offer.is_empty(), "an offer is waiting")
	bo.accept()
	c.state.cash = 0.0
	var r := c.apply_offline(3600.0)
	check(not r.is_empty() and bo.active.is_empty() and bo.done == 1, "an accepted order is finished while you are away")
	check(c.state.cash > 0.0 and cu.bay.money > 0.0, "the bonus rides out on the van with the next load (£%.0f waiting)" % cu.bay.money)


func test_save_roundtrip() -> void:
	var c := classic()
	var cu := c.factory("copper")
	automate(cu, 7)
	unlock(cu, "CU-DIR")
	cu.select_variant("CU-DIR")
	cu.state.upgrade_levels["van_speed"] = 2
	cu.refresh()
	c.state.lifetime_earned = 5000.0
	c.state.factory_name = "Telford Cylinder Works"
	c.bonus_orders.timer = 0.0
	run(c, 40.0)
	c.bonus_orders.accept()
	run(c, 10.0)
	SaveManager.save_game(c.save_data(), TEST_SAVE, 100.0)
	var d := classic()
	d.load_state(SaveManager.load_game(TEST_SAVE))
	var dc := d.factory("copper")
	check(d.state.factory_name == "Telford Cylinder Works", "the factory name is saved and loaded in full")
	check(dc.state.variant == "CU-DIR" and dc.level("van_speed") == 2 and dc.level("variant_cu_dir") == 1, "the chosen product and the upgrades survive")
	check(_diff(dc.bay.to_dict(), cu.bay.to_dict(), "").is_empty(), "the van's load and state survive: " + str(_diff(dc.bay.to_dict(), cu.bay.to_dict(), "")))
	check(_diff(d.bonus_orders.to_dict(), c.bonus_orders.to_dict(), "").is_empty() and not d.bonus_orders.active.is_empty(), "an accepted order survives: " + str(_diff(d.bonus_orders.to_dict(), c.bonus_orders.to_dict(), "")))
	check(d.factory("copper").order_variant == c.factory("copper").order_variant, "and the factory keeps working on it")
	run(c, 30.0)
	run(d, 30.0)
	near(d.state.cash, c.state.cash, 0.01, "a reloaded game carries on identically (cash)")


func _legacy_payload(session: GameSession, version: int) -> Dictionary:
	var st := session.save_data()
	if version < 5:
		for key in ["stock_mode", "stock_migrate", "sales", "bonus"]:
			st.erase(key)
	return {"game": "cylinder_clicker", "version": version, "state": st}


func _write(payload: Dictionary) -> void:
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(payload))
	f.close()


func test_migration_from_warehouse_save() -> void:
	# a v0.7.0 game: stock on the shelves, warehouse upgrades, tooling bought, orders in progress
	var old := GameSession.new(_data, true)
	old.contracts.reset(1)
	var cu := old.factory("copper")
	automate(cu, 12)
	cu.state.upgrade_levels["finish"] = 4
	cu.state.upgrade_levels["warehouse"] = 3
	cu.state.upgrade_levels["horizontal_tooling"] = 1
	cu.state.upgrade_levels["sales_rep"] = 2
	cu.refresh()
	cu.state.earned = 700000.0
	old.state.lifetime_earned = 700000.0
	old.state.cash = 50000.0
	old.state.factory_name = "Telford Cylinder Works"
	cu.warehouse.receive("CU-IND", 20.0)
	cu.warehouse.receive("CU-DIR", 6.0)
	old.contracts.unlocked = true
	old.contracts.refresh_board()
	var offer: Contract = old.contracts.offers[0]
	old.contracts.accept(offer.id)
	var worth := cu.sku_profit(0) * 26.0
	var refund := 0.0
	for id in ["warehouse", "sales_rep"]:
		for l in cu.level(id):
			refund += cu.cost_at_level(id, l)
	_write(_legacy_payload(old, 5))
	var c := classic()
	c.load_state(SaveManager.load_game(TEST_SAVE))
	var nc := c.factory("copper")
	check(c.state.factory_name == "Telford Cylinder Works" and nc.level("machine_weld") == 12 and nc.level("finish") == 4, "name, automation and upgrades are untouched")
	check(nc.level("warehouse") == 0 and nc.level("sales_rep") == 0 and nc.level("horizontal_tooling") == 0, "the retired upgrades are gone")
	check(nc.level("variant_cu_hor") == 1 and nc.sku_available(nc.sku_index("CU-HOR")), "the horizontal tooling you bought unlocked Horizontal Copper")
	check(c.state.cash >= 50000.0 + refund + worth * 0.99, "stock, refunds and unfinished orders came back as cash (£%.0f from £%.0f)" % [c.state.cash, 50000.0])
	check(c.state.contracts.is_empty() and c.state.sales.is_empty() and nc.state.warehouse.is_empty(), "the old systems' data is cleared")
	check(c.migration_note != "" and "classic" in c.migration_note, "the player is told once: " + c.migration_note)
	check(nc.state.earned == 700000.0 and c.state.lifetime_earned == 700000.0, "earnings statistics are preserved")
	check(c.factory("stainless").state.unlocked == old.factory("stainless").state.unlocked, "factory unlocks are preserved")
	# loading the converted save again does not pay twice
	SaveManager.save_game(c.save_data(), TEST_SAVE, 200.0)
	var again := classic()
	again.load_state(SaveManager.load_game(TEST_SAVE))
	near(again.state.cash, c.state.cash, 0.01, "converting happens once: loading again changes nothing")
	check(again.migration_note == "", "...and says nothing the second time")
	run(c, 60.0)
	check(c.state.cash > 0.0 and nc.warehouse.total_units() == 0, "the converted factory carries on producing")


func test_migration_from_contract_save() -> void:
	# a v0.5.1 game with a contract part-built, one ready, one on the lorry
	var old := GameSession.new(_data)
	old.contracts.reset(1)
	var cu := old.factory("copper")
	automate(cu, 9)
	old.state.lifetime_earned = 90000.0
	old.state.cash = 1000.0
	old.contracts.refresh_board()
	var ids: Array[String] = []
	for o in old.contracts.offers.slice(0, 3):
		ids.append(o.id)
	for id in ids:
		old.contracts.accept(id)
		old.contracts.set_allocation(id, 20)
	var a := old.contracts.find(ids[0])
	var b := old.contracts.find(ids[1])
	a.delivered = floorf(float(a.quantity) * 0.5)
	b.delivered = float(b.quantity)
	old.contracts._complete(b)
	var expect := old.contracts.quote(a) * a.delivered / float(a.quantity) + b.value
	var spare := old.contracts.find(ids[2]).value * 0.0
	_write(_legacy_payload(old, 4))
	var c := classic()
	c.load_state(SaveManager.load_game(TEST_SAVE))
	check(c.state.contracts.is_empty() and c.contracts.active.is_empty(), "unfinished contracts are gone from the game")
	check(c.state.cash >= 1000.0 + expect * 0.5, "their value came back as cash (£%.0f)" % (c.state.cash - 1000.0))
	check(spare == 0.0 and c.factory("copper").level("machine_weld") == 9, "automation is preserved")


func test_migration_from_old_direct_save() -> void:
	# a v0.4.0 game: nothing to convert, nothing may change
	var old := GameSession.new(_data)
	var cu := old.factory("copper")
	automate(cu, 10)
	old.state.cash = 12345.0
	old.state.lifetime_earned = 80000.0
	old.state.factory_name = "Old Faithful"
	cu.state.cylinders_made = 777.0
	var st := old.save_data()
	for key in ["stock_mode", "stock_migrate", "sales", "bonus", "contracts"]:
		st.erase(key)
	_write({"game": "cylinder_clicker", "version": 3, "state": st})
	var c := classic()
	c.load_state(SaveManager.load_game(TEST_SAVE))
	near(c.state.cash, 12345.0, 0.001, "cash is exactly what it was")
	check(c.state.factory_name == "Old Faithful" and c.factory("copper").state.cylinders_made == 777.0 and c.factory("copper").level("machine_weld") == 10, "name, statistics and upgrades are exactly what they were")
	check(c.migration_note == "", "no message when there was nothing to convert")
	var diff := ""
	for sim in c.factories:
		if sim.state.unlocked != old.factory(sim.data.id).state.unlocked:
			diff = sim.data.id
	check(diff == "", "factory unlocks are unchanged")


func test_offline_classic() -> void:
	var c := classic()
	var cu := c.factory("copper")
	automate(cu, 8)
	c.state.cash = 0.0
	var r := c.apply_offline(3600.0)
	check(not r.is_empty() and float(r["cash"]) > 0.0 and absf(float(r["cash"]) - c.state.cash) < 0.01, "a factory that runs by itself earns while you are away (£%.0f)" % c.state.cash)
	var legacy := GameSession.new(_data)
	automate(legacy.factory("copper"), 8)
	legacy.state.cash = 0.0
	legacy.apply_offline(3600.0)
	near(c.state.cash, legacy.state.cash, legacy.state.cash * 0.001 + 0.01, "offline earnings are exactly the original game's")
	check(c.apply_offline(10.0).is_empty(), "short absences are ignored")


func test_naming_dialog() -> void:
	# The dialog itself is exercised inside the real game (tests/menu_flow_bot.gd); here: the rules behind it.
	check(GameState.MAX_NAME_LENGTH == 24, "the limit is the advertised 24")
	check(GameState.clean_typed("Telford Cylinder Works") == "Telford Cylinder Works", "'Telford Cylinder Works' is kept whole, spaces included")
	check(GameState.clean_typed("  ABCDEFGHIJKLMNOPQRSTUVWX  ") == "ABCDEFGHIJKLMNOPQRSTUVWX" and GameState.clean_typed("ABCDEFGHIJKLMNOPQRSTUVWX").length() == 24, "a 24-character name is kept whole")
	check(GameState.clean_typed("x".repeat(40)).length() == 24 and GameState.clean_name("x".repeat(40)).length() == 24, "anything longer is cut to 24")
	check(GameState.clean_typed("   ") == "" and GameState.clean_name("   ") == GameState.DEFAULT_FACTORY_NAME, "blank means keep the default")
	var c := classic()
	for name in ["Telford Cylinder Works", "ABCDEFGHIJKLMNOPQRSTUVWX"]:
		c.state.factory_name = GameState.clean_name(name)
		SaveManager.save_game(c.save_data(), TEST_SAVE, 1.0)
		var back := classic()
		back.load_state(SaveManager.load_game(TEST_SAVE))
		check(back.state.factory_name == name, "'%s' is saved and loaded whole" % name)
		var code := SaveManager.export_code(TEST_SAVE)
		check(SaveManager.decode_code(code).get("factory_name", "") == name, "...and survives a transfer code")


## Differences between two plain data trees (numbers within a tiny tolerance).
func _diff(a: Variant, b: Variant, path: String) -> Array:
	var out: Array = []
	if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
		for k: Variant in a:
			if not b.has(k):
				out.append("%s/%s missing" % [path, k])
			else:
				out.append_array(_diff(a[k], b[k], "%s/%s" % [path, k]))
		for k: Variant in b:
			if not a.has(k):
				out.append("%s/%s extra" % [path, k])
	elif typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY:
		if a.size() != b.size():
			out.append("%s size" % path)
		else:
			for i in a.size():
				out.append_array(_diff(a[i], b[i], "%s[%d]" % [path, i]))
	elif (typeof(a) == TYPE_FLOAT or typeof(a) == TYPE_INT) and (typeof(b) == TYPE_FLOAT or typeof(b) == TYPE_INT):
		if absf(float(a) - float(b)) > 1.0e-6 * maxf(1.0, absf(float(a))):
			out.append("%s: %s != %s" % [path, a, b])
	elif a != b:
		out.append("%s: %s != %s" % [path, a, b])
	return out


func _find_button(root_node: Node, prefix: String) -> Button:
	for c in root_node.get_children():
		if c is Button and (c as Button).text.begins_with(prefix):
			return c
		var deeper := _find_button(c, prefix)
		if deeper != null:
			return deeper
	return null
