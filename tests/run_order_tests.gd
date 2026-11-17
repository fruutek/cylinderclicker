extends SceneTree
## Headless tests for customers, telephone orders, reservations, partial deliveries, backorders,
## relationships, contracts on stock, the sales rep, and unattended time (Expansion 4, milestones C and D).
## Run:  godot --headless --path . -s tests/run_order_tests.gd

const TICK := 1.0 / 60.0
const TEST_SAVE := "user://test_order_save.json"

var _passed := 0
var _failed := 0
var _data: GameData


func _init() -> void:
	_data = GameData.new()
	check(_data.load_all(), "data files load")
	for t: String in [
		"test_customers_and_calls", "test_options", "test_full_order", "test_part_delivery_and_backorder", "test_available_only",
		"test_delayed_full_order", "test_decline", "test_relationship_rules", "test_lateness_and_cancel", "test_board_contract_on_stock",
		"test_reservations_conserved", "test_save_roundtrip", "test_migration_with_contracts", "test_offline_orders", "test_sales_rep",
		"test_planner_serves_backorders", "test_simple_layer",
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


## A company that keeps stock, with the copper line automated and the telephones switched on.
func company(automated: bool = true) -> GameSession:
	var c := GameSession.new(_data, true)
	c.contracts.reset(1)
	c.sales.reset(1)
	c.state.lifetime_earned = 500.0
	if automated:
		for m: Dictionary in c.factory("copper").data.machines:
			c.factory("copper").state.upgrade_levels[m["id"]] = 6
		c.factory("copper").refresh()
	for sim in c.factories:
		sim.state.auto_targets = false        # these tests set targets by hand
	c.sales.advance(0.1)
	c.sales.timers = {"copper": 3000.0, "stainless": 3000.0}      # no random calls unless a test asks for one
	return c


func run(c: GameSession, seconds: float) -> void:
	for i in int(round(seconds / TICK)):
		c.tick(TICK)
		if c.sales.timers.get("copper", 0.0) < 100.0:
			c.sales.timers["copper"] = 3000.0


func stock(c: GameSession, sku: String, n: int) -> void:
	c.factory("copper").warehouse.receive(sku, float(n))
	c.factory("copper").state.cylinders_made += float(n)


func call_for(c: GameSession, sku: String, qty: int, customer: int = 0, factor: float = 1.0) -> Dictionary:
	c.sales.serial += 1
	var cust: Dictionary = c.sales.customers[customer]
	var call := {"id": "call%d" % c.sales.serial, "serial": c.sales.serial, "customer": cust["id"], "factory": "copper", "sku": sku,
		"qty": qty, "factor": factor, "expires_in": 150.0, "line": 0.1}
	c.sales.calls.append(call)
	return call


func option(c: GameSession, call: Dictionary, id: String) -> Dictionary:
	for o: Dictionary in c.sales.options_for(call):
		if o["id"] == id:
			return o
	return {}


## An answer the customer will take: choose the roll so the deterministic dice agree.
func accept(c: GameSession, call: Dictionary, id: String) -> Dictionary:
	var cust: Dictionary = c.sales.find_customer(str(call["customer"]))
	cust["rel"] = 60.0                       # a trusted customer: very likely to agree
	var r: Dictionary = c.sales.answer(str(call["id"]), id)
	return r


func reserved_sum(c: GameSession, sku: String) -> float:
	var n := 0.0
	for k in c.contracts.active:
		if k.factory == "copper" and k.sku == sku:
			n += k.held
	return n


# ------------------------------------------------------------------ tests
func test_customers_and_calls() -> void:
	var c := GameSession.new(_data, true)
	c.contracts.reset(1)
	c.sales.reset(1)
	c.sales.advance(1.0)
	check(not c.sales.unlocked and c.sales.customers.is_empty(), "no telephone customers before the company has earned something")
	c.state.lifetime_earned = 100.0
	c.sales.advance(1.0)
	check(c.sales.unlocked and c.sales.customers.size() == 5, "five customers to start with (%d)" % c.sales.customers.size())
	var names := {}
	for cu: Dictionary in c.sales.customers:
		names[cu["name"]] = true
		check(float(cu["rel"]) == 20.0 and int(cu["completed"]) == 0, "%s starts as a new customer" % cu["name"])
	check(names.size() == 5, "customers have different names")
	# Calls arrive, but never more than three wait.
	c.sales.timers["copper"] = 0.0
	var copper := c.factory("copper")
	for i in 40:
		c.sales.timers["copper"] = 0.0
		c.sales.advance(1.0)
	check(c.sales.calls.size() <= 3 and c.sales.calls.size() >= 1, "calls queue up to the limit and no further (%d)" % c.sales.calls.size())
	for call: Dictionary in c.sales.calls:
		var i := copper.sku_index(str(call["sku"]))
		check(i >= 0 and copper.sku_available(i), "customers only ask for what the factory can make (%s)" % call["sku"])
		check(int(call["qty"]) >= 2, "an order is for at least two cylinders")
	check(c.sales.call_text(c.sales.calls[0]).length() > 10, "the call has something to say: " + c.sales.call_text(c.sales.calls[0]))
	# Unanswered calls are taken by the sales rep (at a weaker price) - unless it cannot, then the customer remembers.
	var cust: Dictionary = c.sales.find_customer(str(c.sales.calls[0]["customer"]))
	var rel_before := float(cust["rel"])
	c.sales.cfg["max_open_orders"] = 0
	for i in 200:
		c.sales.advance(1.0)
	check(int(c.sales.stats["missed"]) >= 1 and float(cust["rel"]) <= rel_before, "a call nobody can take counts against the relationship")
	c.sales.cfg["max_open_orders"] = 6
	c.sales.calls.clear()
	var d := call_for(c, "CU-IND", 6, 2)
	d["factor"] = 1.0
	c.sales.advance(0.1)
	c.state.cash = 0.0
	stock(c, "CU-IND", 8) if c.factory("copper").warehouse.available("CU-IND") < 6 else null
	for i in 200:
		c.sales.advance(1.0)
	check(int(c.sales.stats["rep_orders"]) >= 1 and c.contracts.active.size() + c.contracts.history.size() >= 1, "left to ring, the call is answered by the sales rep (%d orders)" % int(c.sales.stats["rep_orders"]))
	# Same seed, same calls.
	var a := GameSession.new(_data, true)
	var b := GameSession.new(_data, true)
	for s: GameSession in [a, b]:
		s.contracts.reset(1)
		s.sales.reset(7)
		s.state.lifetime_earned = 100.0
		for i in 120:
			s.sales.advance(1.0)
	check(JSON.stringify(a.sales.to_dict()) == JSON.stringify(b.sales.to_dict()), "the same seed produces the same customers and calls")


func test_options() -> void:
	var c := company()
	var sim := c.factory("copper")
	var call := call_for(c, "CU-IND", 10)
	var none := c.sales.options_for(call)
	var ids: Array = []
	for o: Dictionary in none:
		ids.append(o["id"])
	check(ids == ["delayed", "decline"], "no stock: you can only offer a delayed full order or decline (%s)" % str(ids))
	check(float(option(c, call, "delayed")["eta"]) > 0.0, "a delayed order comes with an ETA (%s)" % NumFmt.duration(float(option(c, call, "delayed")["eta"])))
	stock(c, "CU-IND", 4)
	ids.clear()
	for o: Dictionary in c.sales.options_for(call):
		ids.append(o["id"])
	check(ids == ["partial", "available", "delayed", "decline"], "some stock: part delivery, available only, delayed or decline (%s)" % str(ids))
	var part := option(c, call, "partial")
	check(part["ship_now"] == 4 and part["backorder"] == 6, "part delivery ships what is there (4) and backorders the rest (6)")
	check(option(c, call, "available")["ship_now"] == 4 and option(c, call, "available")["backorder"] == 0, "'available only' ships 4 and nothing more")
	stock(c, "CU-IND", 20)
	ids.clear()
	for o: Dictionary in c.sales.options_for(call):
		ids.append(o["id"])
	check(ids == ["full", "decline"], "plenty of stock: supply in full or decline (%s)" % str(ids))
	check(option(c, call, "available").is_empty(), "no pointless part-delivery offer when everything is on the shelves")
	# Reserved stock is not offered twice.
	var other := call_for(c, "CU-IND", 20, 1)
	accept(c, other, "full")
	var again := call_for(c, "CU-IND", 10, 2)
	var left := sim.warehouse.available("CU-IND")
	check(left == 4 and option(c, again, "partial")["ship_now"] == 4, "stock promised to one customer is not promised to another (%d left)" % left)
	check(float(option(c, call, "partial")["chance"]) > 0.0 and ["Likely", "Maybe", "Unlikely"].has(option(c, call, "partial")["verdict"]), "every offer shows how it will be received")


func test_full_order() -> void:
	var c := company()
	var sim := c.factory("copper")
	stock(c, "CU-IND", 12)
	c.state.cash = 0.0
	var call := call_for(c, "CU-IND", 10, 0, 1.05)
	var r := accept(c, call, "full")
	check(r["accepted"], "the customer agrees to a full order: " + str(r["text"]))
	var k: Contract = c.contracts.active[0]
	check(k.is_call() and k.quantity == 10 and k.held == 10.0 and sim.warehouse.reserved_units("CU-IND") == 10 and sim.warehouse.available("CU-IND") == 2, "ten cylinders are reserved for it (stock 12: 10 reserved, 2 available)")
	check(k.status == Contract.Status.DISPATCHING, "the lorry starts loading at once")
	check(c.state.cash == 0.0, "nothing is paid until the lorry leaves")
	run(c, 8.0)
	check(c.contracts.active.is_empty(), "the order is complete")
	var unit := sim.sku_profit(0) * 1.05
	near(c.state.cash, 10.0 * unit, 0.01, "paid for exactly ten at the agreed price")
	check(sim.warehouse.total("CU-IND") == 2 and sim.warehouse.reserved_units("CU-IND") == 0, "the stock left with the lorry: 2 remain, none reserved")
	check(sim.warehouse.shipped.get("CU-IND", 0) == 10, "ten shipped on record")
	var cust: Dictionary = c.sales.find_customer(str(call["customer"]))
	check(int(cust["completed"]) == 1 and float(cust["spent"]) > 0.0, "the customer's history records the order")


func test_part_delivery_and_backorder() -> void:
	var c := company()
	var sim := c.factory("copper")
	sim.state.targets = {"CU-IND": 0, "CU-DIR": 0, "CU-HOR": 0, "CU-SLM": 0}
	sim.state.auto_targets = false
	sim.state.wholesale_on = false
	stock(c, "CU-IND", 4)
	c.state.cash = 0.0
	var call := call_for(c, "CU-IND", 30, 0, 1.0)
	var r := accept(c, call, "partial")
	check(r["accepted"], "part delivery accepted: " + str(r["text"]))
	var k: Contract = c.contracts.active[0]
	check(k.mode == "partial" and k.quantity == 30 and k.held == 4.0 and k.promised > 0.0, "ordered 30, 4 held, with a promised date (%s)" % NumFmt.duration(k.promised))
	check(sim.backlog(0) == 26.0, "the factory knows 26 are owed")
	run(c, 6.0)
	check(k.shipped == 4.0 and k.status == Contract.Status.ACTIVE and k.shipments == 1, "the first lorry took the 4 that were there")
	near(c.state.cash, 4.0 * sim.sku_profit(0), 0.01, "paid for the 4 shipped, not for the 26 still owed")
	var paid_after_first := c.state.cash
	# The line builds the rest for this customer - nothing else has a target.
	run(c, 120.0)
	check(k.delivered >= 30.0 - 1e-6 or c.contracts.active.is_empty(), "the backorder is built (%s of 30)" % k.delivered)
	run(c, 30.0)
	check(c.contracts.active.is_empty(), "later lorries took the rest and the order closed")
	near(c.state.cash, 30.0 * sim.sku_profit(0), 0.01, "total paid is exactly 30 x unit profit: nothing paid twice (%.2f vs %.2f)" % [c.state.cash, 30.0 * sim.sku_profit(0)])
	check(c.state.cash > paid_after_first, "the later deliveries were paid as they left")
	check(sim.warehouse.shipped.get("CU-IND", 0) == 30 and sim.warehouse.total("CU-IND") <= 1, "30 shipped, nothing extra built (stock %d)" % sim.warehouse.total("CU-IND"))
	var fin := c.sales.find_customer(str(call["customer"]))
	check(int(fin["completed"]) == 1, "completed once")
	check(c.factory("copper").warehouse.validate() == "", "warehouse still valid: " + c.factory("copper").warehouse.validate())


func test_available_only() -> void:
	var c := company()
	var sim := c.factory("copper")
	stock(c, "CU-IND", 5)
	c.state.cash = 0.0
	var call := {}
	var r := {"accepted": false, "text": ""}
	for who in c.sales.customers.size():
		call = call_for(c, "CU-IND", 6, who)
		c.sales.find_customer(str(call["customer"]))["reliability"] = 0.0
		r = accept(c, call, "available")
		if r["accepted"]:
			break
	check(r["accepted"], "a relaxed customer takes what is available: " + str(r["text"]))
	var k: Contract = c.contracts.active[0]
	check(k.quantity == 5 and k.asked == 6, "the order is for 5 (they asked for 6)")
	run(c, 8.0)
	check(c.contracts.active.is_empty() and sim.warehouse.shipped.get("CU-IND", 0) == 5, "5 shipped and the order is closed")
	near(c.state.cash, 5.0 * sim.sku_profit(0) * float(k.margin), 0.01, "paid for 5")
	check(sim.backlog(0) == 0.0, "no backorder was created")
	# A customer can refuse a part order (deterministic).
	var d := company()
	stock(d, "CU-IND", 1)
	var big := call_for(d, "CU-IND", 40)
	var cu: Dictionary = d.sales.find_customer(str(big["customer"]))
	cu["reliability"] = 1.0
	cu["rel"] = 5.0
	check(float(option(d, big, "available")["chance"]) < 0.3, "a demanding customer is unlikely to accept 1 of 40 (%.2f)" % float(option(d, big, "available")["chance"]))


func test_delayed_full_order() -> void:
	var c := company()
	var sim := c.factory("copper")
	sim.state.targets = {"CU-IND": 0, "CU-DIR": 0, "CU-HOR": 0, "CU-SLM": 0}
	sim.state.wholesale_on = false
	stock(c, "CU-IND", 3)
	c.state.cash = 0.0
	var call := call_for(c, "CU-IND", 15)
	var r := accept(c, call, "delayed")
	check(r["accepted"], "a delayed full order is accepted: " + str(r["text"]))
	var k: Contract = c.contracts.active[0]
	check(k.mode == "delayed" and k.held == 3.0, "3 reserved, waiting for the rest")
	run(c, 5.0)
	check(k.shipments == 0 and c.state.cash == 0.0, "nothing ships until the order is complete")
	for i in 40:
		run(c, 5.0)
		if c.contracts.active.is_empty():
			break
	check(c.contracts.active.is_empty(), "the full order shipped once complete")
	near(c.state.cash, 15.0 * sim.sku_profit(0) * k.margin, 0.01, "paid once, for all 15")
	check(k.shipments == 1, "in a single lorry")


func test_decline() -> void:
	var c := company()
	var cust: Dictionary = c.sales.customers[0]
	cust["rel"] = 50.0
	var a := call_for(c, "CU-IND", 10)
	var r1: Dictionary = c.sales.answer(str(a["id"]), "decline")
	check(r1["ok"] and not r1["accepted"] and c.contracts.active.is_empty(), "declining creates no order")
	var after1 := float(cust["rel"])
	check(after1 < 50.0, "one refusal costs a little (50 -> %.1f)" % after1)
	var b := call_for(c, "CU-IND", 10)
	c.sales.answer(str(b["id"]), "decline")
	var after2 := float(cust["rel"])
	check(after1 - after2 > 50.0 - after1, "repeated refusals cost more (%.1f then %.1f)" % [50.0 - after1, after1 - after2])
	var d := call_for(c, "CU-IND", 10)
	c.sales.answer(str(d["id"]), "decline")
	check(float(cust["dormant_until"]) > c.sales.clock, "a customer who keeps being turned away stops calling for a while")
	check(float(c.sales.lost.get("CU-IND", 0.0)) == 30.0, "lost sales are recorded (30)")
	var before_calls: int = c.sales.calls.size()
	c.sales.timers["copper"] = 0.0
	for i in 5:
		c.sales.timers["copper"] = 0.0
		c.sales.advance(1.0)
	for call: Dictionary in c.sales.calls:
		check(call["customer"] != cust["id"], "the dormant customer does not ring")
	check(before_calls == 0, "nothing was left waiting")


func test_relationship_rules() -> void:
	var c := company()
	stock(c, "CU-IND", 200)
	var cust: Dictionary = c.sales.customers[0]
	check(c.sales.relationship_tier(20.0) == "Known" and c.sales.relationship_tier(5.0) == "New" and c.sales.relationship_tier(85.0) == "Partner", "relationship tiers by score")
	# Two tiny orders cannot make a partner.
	for i in 2:
		var call := call_for(c, "CU-IND", 2)
		cust["rel"] = 20.0
		c.sales.answer(str(call["id"]), "full")
		run(c, 8.0)
	check(int(cust["completed"]) == 2, "two orders completed")
	check(float(cust["rel"]) < 40.0, "loyalty builds slowly: two tiny orders reach only %.1f" % float(cust["rel"]))
	check(c.sales.relationship_cap(cust) < 30.0, "and the ceiling is low until more orders are done (%.0f)" % c.sales.relationship_cap(cust))
	# Many good orders raise it, but never past the cap or 100.
	cust["rel"] = 20.0
	for i in 40:
		cust["completed"] = int(cust["completed"]) + 1
	c.sales._change_rel(cust, 500.0)
	check(float(cust["rel"]) == 100.0, "enough completed orders allow full loyalty")
	# Better relationship: bigger orders, better price, more calls.
	var sim := c.factory("copper")
	sim.state.upgrade_levels["warehouse"] = 8              # room enough that order size is not capped by the shelves
	sim.refresh()
	var poor := cust.duplicate(true)
	poor["rel"] = 5.0
	var good := cust.duplicate(true)
	good["rel"] = 95.0
	var qp := 0
	var qg := 0
	for s in 30:
		c.sales.serial += 1
		qp += c.sales.typical_quantity(sim, poor, 0)
		qg += c.sales.typical_quantity(sim, good, 0)
	check(qg > qp, "good relationships mean larger orders (%d vs %d over 30 calls)" % [qg, qp])
	check(c.sales.price_factor(good) > c.sales.price_factor(poor) + 0.05, "...and a better price (%.3f vs %.3f)" % [c.sales.price_factor(good), c.sales.price_factor(poor)])
	check(c.sales.price_factor(poor) > 0.95 and c.sales.price_factor(good) < 1.2, "prices stay within sensible bounds")
	cust["dormant_until"] = 0.0
	for cu: Dictionary in c.sales.customers:
		cu["rel"] = 95.0
		cu["dormant_until"] = 0.0
	var q := sim.planning_rate(1.5, 0.85) * 60.0
	var gap_good: float = c.sales._next_gap(sim, {"qty": q})
	for cu: Dictionary in c.sales.customers:
		cu["rel"] = 3.0
	var gap_poor: float = c.sales._next_gap(sim, {"qty": q})
	check(gap_poor > gap_good, "a badly treated customer base rings less often (every %.0f s vs %.0f s)" % [gap_poor, gap_good])
	# Company reputation is a separate thing.
	check(c.contracts.reputation == 0, "company reputation is unaffected by customer relationships")


func test_lateness_and_cancel() -> void:
	var c := company(false)       # a line with no machines builds nothing by itself
	var sim := c.factory("copper")
	stock(c, "CU-IND", 3)
	c.state.cash = 0.0
	var call := call_for(c, "CU-IND", 20)
	var r := accept(c, call, "partial")
	check(r["accepted"], "accepted")
	var k: Contract = c.contracts.active[0]
	run(c, 8.0)
	check(k.shipped == 3.0, "3 went at once")
	var cust: Dictionary = c.sales.find_customer(str(call["customer"]))
	var rel_before := float(cust["rel"])
	k.time_left = -1.0
	run(c, 1.0)
	check(k.late, "past the promise the order is late")
	k.time_left = -k.patience + 0.5
	stock(c, "CU-IND", 0)
	run(c, 2.0)
	check(c.contracts.active.is_empty(), "the customer gives up after their patience runs out")
	check(float(cust["rel"]) < rel_before, "a cancelled order hurts the relationship (%.1f -> %.1f)" % [rel_before, float(cust["rel"])])
	near(c.state.cash, 3.0 * sim.sku_profit(0) * k.margin, 0.01, "the 3 already delivered stay paid for")
	check(int(cust["failed"]) == 1 and float(c.sales.lost.get("CU-IND", 0.0)) >= 17.0, "the cancelled 17 are recorded as lost")
	check(sim.warehouse.reserved_units("CU-IND") == 0 and reserved_sum(c, "CU-IND") == 0.0, "no stock is left reserved for a dead order")
	# Stock that had been put aside goes back on the shelves, never lost.
	var d := company(false)
	stock(d, "CU-IND", 3)
	var call2 := call_for(d, "CU-IND", 10)
	accept(d, call2, "delayed")
	var k2: Contract = d.contracts.active[0]
	check(d.factory("copper").warehouse.available("CU-IND") == 0, "all three are reserved for the delayed order")
	k2.time_left = -k2.patience - 1.0
	run(d, 1.0)
	check(d.contracts.active.is_empty() and d.factory("copper").warehouse.available("CU-IND") == 3, "...and available again when it is cancelled")
	check(d.state.cash == 0.0, "a delayed order that never shipped paid nothing")


func test_board_contract_on_stock() -> void:
	var c := company()
	c.contracts.auto_ship_board = false      # this test sends the lorry by hand
	var sim := c.factory("copper")
	sim.state.upgrade_levels["warehouse"] = 6         # room for a whole order on the shelves
	sim.refresh()
	sim.state.targets = {"CU-IND": 0, "CU-DIR": 0, "CU-HOR": 0, "CU-SLM": 0}
	sim.state.wholesale_on = false
	c.contracts.refresh_board()
	check(c.contracts.offers.size() > 0, "the board has offers")
	for o in c.contracts.offers:
		check(o.sku != "" and sim.sku_index(o.sku) >= 0 and sim.sku_available(sim.sku_index(o.sku)), "an offer names a product the factory can make (%s)" % o.sku)
	var offer: Contract = c.contracts.offers[0]
	var sku := offer.sku
	var qty := offer.quantity
	var have := mini(qty, 3)
	stock(c, sku, have)
	var problem := c.contracts.accept(offer.id)
	check(problem == "", "accepting needs no share of the factory's output: " + problem)
	var k := c.contracts.find(offer.id)
	check(k.allocation == 0 and k.held == float(have) and k.delivered == float(have), "stock on the shelves is put aside at once (%d of %d)" % [have, qty])
	check(sim.warehouse.reserved_units(sku) == have, "and shows as reserved in the warehouse")
	check(sim.backlog(sim.sku_index(sku)) == float(qty - have), "the planner is told what is still owed (%d)" % (qty - have))
	c.state.cash = 0.0
	for i in 200:
		run(c, 5.0)
		if k.status == Contract.Status.READY:
			break
	check(k.status == Contract.Status.READY, "the line builds the rest and the order becomes ready (%s / %d)" % [k.delivered, qty])
	check(c.state.cash == 0.0, "still no money before dispatch")
	var quote := c.contracts.quote(k)
	check(c.contracts.dispatch(k.id) == "", "dispatch")
	run(c, 9.0)
	check(c.contracts.find(offer.id) == null, "the lorry left")
	near(c.state.cash, quote + (c.contracts.history[0]["bonus"] as float), 0.5, "paid the quote exactly once")
	check(sim.warehouse.shipped.get(sku, 0) == qty and sim.warehouse.reserved_units(sku) == 0, "the cylinders left the warehouse (%d shipped)" % sim.warehouse.shipped.get(sku, 0))
	# A missed deadline puts the stock back, unsold.
	var e := company()
	e.contracts.refresh_board()
	var o2: Contract = e.contracts.offers[0]
	stock(e, o2.sku, 2)
	e.contracts.accept(o2.id)
	var k2 := e.contracts.find(o2.id)
	k2.time_left = 0.01
	k2.deadline = maxf(k2.deadline, 1.0)
	e.state.cash = 0.0
	run(e, 1.0)
	check(e.contracts.find(o2.id) == null and e.state.cash == 0.0, "a missed contract pays nothing")
	check(e.factory("copper").warehouse.available(o2.sku) >= 2 and e.factory("copper").warehouse.reserved_units(o2.sku) == 0, "...and its reserved stock goes back on the shelves, not sold off")


func test_reservations_conserved() -> void:
	var c := company()
	var sim := c.factory("copper")
	c.state.lifetime_earned = 5000.0
	c.sales.timers["copper"] = 0.0
	var accepted := 0
	for step in 60:
		c.sales.timers["copper"] = 0.0 if step % 3 == 0 else 3000.0
		for t in 120:
			c.tick(TICK)
			if c.sales.timers.get("copper", 0.0) < 3000.0 - 1.0 and t > 0:
				c.sales.timers["copper"] = 3000.0
		for call in c.sales.calls.duplicate():
			var opts: Array = c.sales.options_for(call)
			var pick := "decline"
			for o: Dictionary in opts:
				if o["id"] == "partial" or o["id"] == "full" or o["id"] == "delayed":
					pick = o["id"]
					break
			c.sales.find_customer(str(call["customer"]))["rel"] = 70.0
			if c.sales.answer(str(call["id"]), pick)["accepted"]:
				accepted += 1
		var bad := sim.warehouse.validate()
		if bad != "":
			check(false, "warehouse invalid at step %d: %s" % [step, bad])
			break
		for sku in ["CU-IND", "CU-DIR"]:
			if absf(reserved_sum(c, sku) - float(sim.warehouse.reserved_units(sku))) > 1e-6:
				check(false, "reservations %s: orders hold %s but the warehouse reserved %s (step %d)" % [sku, reserved_sum(c, sku), sim.warehouse.reserved_units(sku), step])
				break
	check(accepted >= 3, "plenty of orders went through the whole life cycle (%d)" % accepted)
	var total_made := 0.0
	for id in sim.warehouse.made:
		total_made += float(sim.warehouse.made[id])
	var accounted := 0.0
	for s in sim.skus:
		var id := str(s["id"])
		accounted += float(sim.warehouse.total(id)) + float(sim.warehouse.shipped.get(id, 0)) + float(sim.warehouse.wholesaled.get(id, 0)) + float(sim.warehouse.frac.get(id, 0.0))
	near(total_made, accounted, 0.01, "every cylinder made is on the shelves, shipped or wholesaled")
	check(c.state.cash > 0.0, "the business earned money (%.0f)" % c.state.cash)
	check(c.contracts.stats["paid"] <= c.state.lifetime_earned - 500.0 + 0.5, "order income never exceeds money earned")


func test_save_roundtrip() -> void:
	var c := company()
	stock(c, "CU-IND", 4)
	var call := call_for(c, "CU-IND", 25)
	accept(c, call, "partial")
	var open := call_for(c, "CU-DIR", 6, 1)
	var cu: Dictionary = c.sales.customers[2]
	cu["rel"] = 47.5
	cu["completed"] = 3
	cu["history"].push_front({"sku": "CU-IND", "qty": 8, "outcome": "complete", "paid": 40.0})
	run(c, 20.0)
	SaveManager.save_game(c.save_data(), TEST_SAVE, 100.0)
	var d := GameSession.new(_data, true)
	d.load_state(SaveManager.load_game(TEST_SAVE))
	var sales_diff := _diff(c.sales.to_dict(), d.sales.to_dict(), "")
	check(sales_diff.is_empty(), "customers, relationships and waiting calls survive a save: " + str(sales_diff))
	var book_diff := _diff(c.contracts.to_dict(), d.contracts.to_dict(), "")
	check(book_diff.is_empty(), "open orders (shipped, held, promised) survive a save: " + str(book_diff))
	var k: Contract = d.contracts.active[0]
	check(k.is_call() and k.mode == "partial" and k.shipped == 4.0 and k.shipments == 1, "the part-delivery order resumes where it was")
	check(not d.sales.find_call(str(open["id"])).is_empty(), "a call that was ringing is still ringing")
	for s in [c, d]:
		for i in 60:
			run(s, 5.0)
	var after_diff := _diff(c.sales.to_dict(), d.sales.to_dict(), "")
	check(after_diff.is_empty() and absf(c.state.cash - d.state.cash) < 0.01, "a reloaded game carries on identically: " + str(after_diff))


func test_migration_with_contracts() -> void:
	# A v0.5.1 game with a contract partly built, one ready and one on the lorry.
	var old := GameSession.new(_data)
	old.contracts.reset(1)
	for m: Dictionary in old.factory("copper").data.machines:
		old.factory("copper").state.upgrade_levels[m["id"]] = 8
	old.factory("copper").refresh()
	old.state.lifetime_earned = 90000.0
	old.contracts.refresh_board()
	var ids: Array[String] = []
	for o in old.contracts.offers.slice(0, 3):
		ids.append(o.id)
	for id in ids:
		check(old.contracts.accept(id) == "", "accepted " + id)
		old.contracts.set_allocation(id, 20)
	var ka := old.contracts.find(ids[0])
	var kb := old.contracts.find(ids[1])
	var kc := old.contracts.find(ids[2])
	ka.delivered = floorf(float(ka.quantity) * 0.4)
	kb.delivered = float(kb.quantity)
	old.contracts._complete(kb)
	kc.delivered = float(kc.quantity)
	old.contracts._complete(kc)
	old.contracts.dispatch(kc.id)
	old.state.cash = 1000.0
	var data := old.save_data()
	for key in ["stock_mode", "stock_migrate", "sales"]:
		data.erase(key)
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"game": "cylinder_clicker", "version": 4, "state": data}))
	f.close()
	var c := GameSession.new(_data, true)
	c.contracts.auto_ship_board = false      # the finished contract is sent by hand below
	c.load_state(SaveManager.load_game(TEST_SAVE))
	var sim := c.factory("copper")
	check(c.state.stock_mode and c.contracts.active.size() == 3, "all three contracts survive the move to stock keeping")
	var a2 := c.contracts.find(ids[0])
	var b2 := c.contracts.find(ids[1])
	var c2 := c.contracts.find(ids[2])
	check(a2.held == ka.delivered and a2.delivered == ka.delivered, "built progress becomes reserved stock (%d)" % int(a2.held))
	check(b2.status == Contract.Status.READY and b2.held == float(b2.quantity), "a finished contract is still ready, with its cylinders reserved")
	check(c2.status == Contract.Status.DISPATCHING and c2.loading == float(c2.quantity), "a lorry that was loading is still loading")
	var reserved := int(a2.held + b2.held + c2.held)
	check(sim.warehouse.reserved_units("CU-IND") == reserved, "the warehouse holds exactly those cylinders reserved (%d)" % reserved)
	check(sim.warehouse.validate(true) == "", "the warehouse is consistent: " + sim.warehouse.validate(true))
	# No duplicate payout: the loading lorry pays once; the READY one pays once when dispatched.
	var cash0 := c.state.cash
	var quote_c := c.contracts.quote(c2)
	for i in 600:
		c.tick(TICK)
	check(c.contracts.find(ids[2]) == null, "the loading contract completed")
	var gained := c.state.cash - cash0
	check(gained >= quote_c - 0.5 and gained < quote_c + c.contracts.bonus_quote(c2) + 1.0e9, "it was paid (%.0f vs %.0f)" % [gained, quote_c])
	var cash1 := c.state.cash
	check(c.contracts.dispatch(ids[1]) == "", "the ready contract can be dispatched")
	for i in 600:
		c.tick(TICK)
	check(c.contracts.find(ids[1]) == null and c.state.cash > cash1, "...and paid once")
	check(sim.warehouse.shipped.get("CU-IND", 0) >= int(b2.quantity) + int(c2.quantity), "their cylinders left the warehouse")


func test_offline_orders() -> void:
	var c := company()
	var sim := c.factory("copper")
	sim.state.targets = {"CU-IND": 0, "CU-DIR": 0, "CU-HOR": 0, "CU-SLM": 0}
	stock(c, "CU-IND", 2)
	var call := call_for(c, "CU-IND", 25)
	accept(c, call, "partial")
	var k: Contract = c.contracts.active[0]
	c.state.cash = 0.0
	var r := c.apply_offline(1800.0)
	check(not r.is_empty(), "there is something to report after half an hour")
	check(c.contracts.find(k.id) == null, "the backorder was built and delivered while away")
	near(c.state.cash, 25.0 * sim.sku_profit(0) * k.margin + _wholesale_cash(c), 0.5, "paid once for all 25 (cash %.1f)" % c.state.cash)
	check(sim.warehouse.validate() == "", "warehouse valid after unattended time")
	check(c.sales.calls.size() <= 3, "at most three calls are waiting when you return (%d)" % c.sales.calls.size())
	# Calls keep coming offline but never flood.
	var d := company()
	d.sales.timers["copper"] = 5.0
	d.sales.timers["stainless"] = 3000.0
	d.apply_offline(6.0 * 3600.0)
	check(d.sales.calls.size() <= 3, "a six-hour absence leaves at most three calls (%d)" % d.sales.calls.size())
	check(int(d.sales.stats["calls"]) > 3 and int(d.sales.stats["rep_orders"]) > 3, "more rang than are waiting: the sales rep took the rest (%d calls, %d taken)" % [d.sales.stats["calls"], d.sales.stats["rep_orders"]])
	var rel_total := 0.0
	for cu: Dictionary in d.sales.customers:
		rel_total += float(cu["rel"])
	check(rel_total / float(d.sales.customers.size()) >= 15.0, "customers are not driven away by unattended time (average %.1f)" % (rel_total / float(d.sales.customers.size())))
	check(d.state.cash > 0.0, "the rep's orders were delivered and paid while away (%.0f)" % d.state.cash)
	check(r.has("cash") and float(r["cash"]) >= 0.0, "the summary carries the cash earned")


func _wholesale_cash(c: GameSession) -> float:
	var n := 0.0
	var sim := c.factory("copper")
	for s in sim.skus:
		n += float(sim.warehouse.wholesaled.get(str(s["id"]), 0)) * sim.sku_profit(sim.sku_index(str(s["id"]))) * sim.sku_catalog.num("wholesale_share", 0.85)
	return n


func test_sales_rep() -> void:
	var c := company()
	var sim := c.factory("copper")
	var rows: Array = c.sales.forecast(sim)
	check(rows.size() == 2, "only the two products the factory can make are forecast (%d)" % rows.size())
	var share := 0.0
	for r: Dictionary in rows:
		share += float(r["share"])
	near(share, 1.0, 0.0001, "shares add up to 100%")
	var ind := 0.0
	var dir := 0.0
	for r: Dictionary in rows:
		if r["sku"] == "CU-IND":
			ind = float(r["share"])
		if r["sku"] == "CU-DIR":
			dir = float(r["share"])
	check(ind > dir, "indirect is the more likely request (%.0f%% vs %.0f%%)" % [ind * 100.0, dir * 100.0])
	check(float(rows[0]["per_min"]) > 0.0 and int(rows[0]["recommended"]) >= 1, "a rate and a recommended stock level for each")
	# New products rebalance the forecast.
	sim.state.upgrade_levels["horizontal_tooling"] = 1
	sim.refresh()
	var rows2: Array = c.sales.forecast(sim)
	check(rows2.size() == 3, "unlocking horizontal adds it to the forecast")
	var ind2 := 0.0
	for r: Dictionary in rows2:
		if r["sku"] == "CU-IND":
			ind2 = float(r["share"])
	check(ind2 < ind, "...and the others' shares shrink to make room (%.0f%% -> %.0f%%)" % [ind * 100.0, ind2 * 100.0])
	# It learns from what customers actually ask for, and better with training.
	var low := company()
	var high := company()
	high.factory("copper").state.upgrade_levels["sales_rep"] = 5
	high.factory("copper").refresh()
	for s: GameSession in [low, high]:
		s.sales.observed["copper"] = []
		for i in 30:
			s.sales.observed["copper"].append("CU-DIR")          # customers are all asking for direct
	var q_low: float = low.sales.forecast_quality(low.factory("copper"))
	var q_high: float = high.sales.forecast_quality(high.factory("copper"))
	check(q_high > q_low + 0.5, "sales-rep training raises forecast quality (%.2f -> %.2f)" % [q_low, q_high])
	var f_low := _share(low.sales.forecast(low.factory("copper")), "CU-DIR")
	var f_high := _share(high.sales.forecast(high.factory("copper")), "CU-DIR")
	check(f_high > f_low and f_high > 0.8, "a trained rep sees the shift sooner (%.0f%% vs %.0f%%)" % [f_high * 100.0, f_low * 100.0])
	# Targets follow the recommendation when planning is automatic.
	var h := high.factory("copper")
	h.state.auto_targets = true
	var t_dir := h.effective_target(1)
	var t_ind := h.effective_target(0)
	check(t_dir > t_ind, "automatic targets follow the forecast (direct %d, indirect %d)" % [t_dir, t_ind])
	# Report: shortfalls, lost sales and dead stock.
	stock(high, "CU-IND", 60)
	var rep: Array = high.sales.forecast(h)
	var dead := false
	for r: Dictionary in rep:
		if r["sku"] == "CU-IND":
			dead = bool(r["dead"])
	check(dead, "stock nobody is asking for is flagged")
	high.sales.lost["CU-DIR"] = 12.0
	var lost_seen := 0.0
	for r: Dictionary in high.sales.forecast(h):
		if r["sku"] == "CU-DIR":
			lost_seen = float(r["lost"])
			check(int(r["shortfall"]) > 0, "an expected shortfall is reported (%d short)" % int(r["shortfall"]))
	check(lost_seen == 12.0, "recent lost sales are reported")


func _share(rows: Array, sku: String) -> float:
	for r: Dictionary in rows:
		if r["sku"] == sku:
			return float(r["share"])
	return 0.0


func test_planner_serves_backorders() -> void:
	var c := company()
	var sim := c.factory("copper")
	sim.state.targets = {"CU-IND": 20, "CU-DIR": 0, "CU-HOR": 0, "CU-SLM": 0}
	sim.state.wholesale_on = false
	# Customers waiting for direct cylinders come before stock targets for indirect.
	var call := call_for(c, "CU-DIR", 8)
	accept(c, call, "delayed")
	sim.planner_wake()
	check(sim.planner_pick(false) == 1, "a customer waiting beats a stock target")
	var urgent := call_for(c, "CU-IND", 6, 1)
	accept(c, urgent, "delayed")
	c.contracts.find("o%d" % int(urgent["serial"])).time_left = 30.0
	c.contracts.find("o%d" % int(call["serial"])).time_left = 300.0
	sim.planner_wake()
	check(sim.planner_pick(false) == 0, "the earliest promise is built first")
	run(c, 200.0)
	check(c.contracts.active.is_empty(), "both customers were served from production")
	check(sim.warehouse.shipped.get("CU-DIR", 0) == 8 and sim.warehouse.shipped.get("CU-IND", 0) == 6, "exactly what was ordered shipped (DIR %d, IND %d)" % [sim.warehouse.shipped.get("CU-DIR", 0), sim.warehouse.shipped.get("CU-IND", 0)])


## Differences between two plain data trees (numbers compare within a tiny tolerance).
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
			out.append("%s size %d != %d" % [path, a.size(), b.size()])
		else:
			for i in a.size():
				out.append_array(_diff(a[i], b[i], "%s[%d]" % [path, i]))
	elif (typeof(a) == TYPE_FLOAT or typeof(a) == TYPE_INT) and (typeof(b) == TYPE_FLOAT or typeof(b) == TYPE_INT):
		if absf(float(a) - float(b)) > 1.0e-6 * maxf(1.0, absf(float(a))):
			out.append("%s: %s != %s" % [path, a, b])
	elif a != b:
		out.append("%s: %s != %s" % [path, a, b])
	return out


## The phone game's plain-language layer: three-button order cards, the rep's advice, focus on backorders,
## the next upgrade to buy, finished contracts shipping themselves, and relationship feedback.
func test_simple_layer() -> void:
	var c := company()
	var sim := c.factory("copper")
	sim.state.wholesale_on = false
	# --- order cards: one button when everything is in stock, three when some is missing
	stock(c, "CU-IND", 20)
	var full := c.sales.simple_offer(call_for(c, "CU-IND", 10))
	var ids: Array = []
	for b: Dictionary in full["buttons"]:
		ids.append(b["id"])
	check(ids == ["full", "decline"] and full["buttons"][0]["label"] == "FULFIL ORDER" and full["missing"] == 0, "all in stock: FULFIL ORDER (and DECLINE)")
	var part := c.sales.simple_offer(call_for(c, "CU-IND", 30, 1))
	ids.clear()
	for b: Dictionary in part["buttons"]:
		ids.append(b["id"])
	check(ids == ["partial", "available", "decline"] and part["in_stock"] == 20 and part["missing"] == 10, "some missing: SEND + MAKE, SEND ONLY, DECLINE (%s)" % str(ids))
	check(part["buttons"][0]["label"] == "SEND 20 + MAKE 10" and part["buttons"][1]["label"] == "SEND 20 ONLY", "the labels say what happens: " + str(part["buttons"][0]["label"]))
	var d := company()
	var none := d.sales.simple_offer(call_for(d, "CU-IND", 12))
	check(none["buttons"][0]["id"] == "delayed" and none["buttons"][-1]["id"] == "decline" and none["in_stock"] == 0, "nothing in stock: MAKE IT or DECLINE")
	# --- the production queue is handled for you: SEND 20 + MAKE 10 ships now and builds the rest, no further taps
	var keep := c.sales.find_call(str(part["call_id"]))
	c.sales.calls.clear()
	c.sales.calls.append(keep)                      # only this call is ringing
	var cust: Dictionary = c.sales.find_customer(str(keep["customer"]))
	cust["rel"] = 70.0
	sim.state.targets = {"CU-IND": 0, "CU-DIR": 0, "CU-HOR": 0, "CU-SLM": 0}
	sim.state.auto_targets = false
	var r: Dictionary = c.sales.answer(str(part["call_id"]), "partial")
	check(r["accepted"], "SEND 20 + MAKE 10 accepted by a trusted customer")
	var cash0 := c.state.cash
	run(c, 150.0)
	check(c.contracts.active.is_empty() and sim.warehouse.shipped.get("CU-IND", 0) == 30, "all 30 delivered with no further input (the missing 10 were queued and built)")
	check(c.state.cash > cash0, "and it paid as the lorries left")
	# --- relationship feedback
	var heard := {"n": 0, "delta": 0.0, "reason": ""}
	c.sales.relationship_moved.connect(func(_id: String, _name: String, delta: float, reason: String) -> void:
		heard["n"] += 1
		heard["delta"] = delta
		heard["reason"] = reason)
	var e := company()
	stock(e, "CU-IND", 8)
	e.sales.relationship_moved.connect(func(_id: String, _name: String, delta: float, reason: String) -> void:
		heard["n"] += 1
		heard["delta"] = delta
		heard["reason"] = reason)
	var ec := call_for(e, "CU-IND", 6)
	e.sales.find_customer(str(ec["customer"]))["completed"] = 10
	e.sales.find_customer(str(ec["customer"]))["rel"] = 40.0
	e.sales.answer(str(ec["id"]), "full")
	run(e, 12.0)
	check(heard["n"] >= 1 and heard["reason"] == "happy" and heard["delta"] > 0.0, "a delivered order tells the player the customer is happy (+%.1f)" % heard["delta"])
	# --- sales rep advice
	var f := company()
	var fs := f.factory("copper")
	check(f.sales.advice(fs).size() >= 1, "the rep always has something to say")
	fs.state.auto_targets = false
	fs.state.targets = {"CU-IND": 0, "CU-DIR": 0, "CU-HOR": 0, "CU-SLM": 0}
	for sku in ["CU-IND", "CU-DIR"]:
		fs.warehouse.stock[sku] = 0
	var adv: Array = f.sales.advice(fs)
	var low_found := false
	for a: Dictionary in adv:
		if a["action"] == "restock":
			low_found = true
			check("running low" in str(a["text"]), "plain words: " + str(a["text"]))
	check(low_found, "empty shelves: the rep says stock is running low")
	var calls := call_for(f, "CU-IND", 10)
	f.sales.answer(str(calls["id"]), "delayed")
	adv = f.sales.advice(fs)
	var focus_found := false
	for a: Dictionary in adv:
		if a["action"] == "focus_backlog":
			focus_found = true
	check(focus_found or fs.owed_work() <= 0.0, "customers waiting: the rep offers FOCUS ON BACKORDERS")
	if focus_found:
		var item := {"action": "focus_backlog", "sku": ""}
		f.sales.do_advice(fs, item)
		check(fs.state.focus_backlog, "...and one tap does it")
		fs.state.targets = {"CU-IND": 50, "CU-DIR": 50, "CU-HOR": 0, "CU-SLM": 0}
		fs.planner_wake()
		var pick := fs.planner_pick(false)
		check(pick == 0, "focus builds only for the waiting customer, not the stock targets (picked %d)" % pick)
		run(f, 80.0)
		check(not fs.state.focus_backlog, "focus switches itself off once everyone has been served")
	# --- warehouse advice
	var g := company()
	var gs := g.factory("copper")
	gs.state.wholesale_on = false
	gs.warehouse.receive("CU-IND", float(gs.warehouse.capacity))
	g.sales.lost["CU-IND"] = 12.0
	var gadv: Array = g.sales.advice(gs)
	var wh := false
	for a: Dictionary in gadv:
		if a["action"] == "upgrade_warehouse":
			wh = true
			check(a["label"] == "UPGRADE WAREHOUSE" and "warehouse is full" in str(a["text"]), "plain words: " + str(a["text"]))
	check(wh, "full shelves and lost orders: the rep offers UPGRADE WAREHOUSE")
	g.state.cash = 1.0e6
	var cap0 := gs.warehouse.capacity
	g.sales.do_advice(gs, {"action": "upgrade_warehouse"})
	check(gs.warehouse.capacity > cap0, "one tap upgrades it (%d -> %d)" % [cap0, gs.warehouse.capacity])
	# --- next upgrade
	var h := company(false)
	var hs := h.factory("copper")
	var nu := hs.next_upgrade()
	check(nu.begins_with("machine_"), "a line that is not automated yet is told to buy a machine (%s)" % nu)
	for m: Dictionary in hs.data.machines:
		hs.state.upgrade_levels[m["id"]] = 3
	hs.refresh()
	var nb := hs.next_upgrade()
	check(nb.begins_with("machine_") and hs.level(nb) >= 3, "an automated line is told to lift its slowest machine (%s)" % nb)
	hs.warehouse.receive("CU-IND", float(hs.warehouse.capacity))
	check(hs.next_upgrade() == "warehouse", "full shelves put the warehouse first")
	# --- finished board contracts ship themselves in the phone game
	var k := company()
	k.contracts.refresh_board()
	var offer: Contract = k.contracts.offers[0]
	k.factory("copper").state.upgrade_levels["warehouse"] = 6
	k.factory("copper").refresh()
	stock(k, offer.sku, offer.quantity)
	k.contracts.accept(offer.id)
	k.state.cash = 0.0
	run(k, 15.0)
	check(k.contracts.find(offer.id) == null and k.state.cash > 0.0, "a finished board contract is sent and paid without a dispatch screen")
