extends SceneTree
## Headless tests for trade contracts, production allocation, dispatch,
## reputation, deadlines and offline progress.
## Run:  godot --headless --path . -s tests/run_contract_tests.gd
##
## These drive the real simulation (GameSession / FactorySim / ContractBook),
## the same code the game runs, so a pass here means the rules hold in play.

const TICK := 1.0 / 60.0
const TEST_SAVE := "user://test_contract_save.json"

var _passed := 0
var _failed := 0
var _data: GameData
var _rules: ContractRules


func _init() -> void:
	_data = GameData.new()
	check(_data.load_all(), "data files load")
	_rules = ContractRules.new(_data.contracts)
	for t: String in [
		"test_golden_regression", "test_rules_data", "test_generation_reproducible", "test_generation_balance",
		"test_generation_extremes", "test_board_unlock_and_refresh", "test_accept_and_limits", "test_allocation_routing",
		"test_no_double_counting", "test_manual_clicks_feed_contracts", "test_completion_and_dispatch",
		"test_dispatch_pays_once", "test_price_follows_list_price", "test_bonus_rules", "test_reputation",
		"test_deadline_failure", "test_abandon", "test_factory_switching", "test_offline_single",
		"test_offline_deadline", "test_offline_multiple", "test_offline_rules", "test_offline_dispatch",
		"test_offline_vs_live", "test_save_roundtrip", "test_save_migration", "test_save_corruption",
		"test_future_products", "test_batched_output",
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


# ---------------------------------------------------------------- helpers
## A company with the contract board open for business but no random offers
## appearing, so scenarios are fully scripted.
func fresh() -> GameSession:
	var c := GameSession.new(_data)
	c.contracts.reset(4242)
	c.contracts.unlocked = true
	c.contracts.offer_timer = 1.0e9
	return c


func automate(s: FactorySim, lvl: int) -> void:
	for m: Dictionary in s.data.machines:
		s.state.upgrade_levels[m["id"]] = lvl
	s.refresh()


func run(c: GameSession, seconds: float) -> void:
	for i in int(round(seconds / TICK)):
		c.tick(TICK)


## A hand-made offer on the board (id must be unique per company).
func offer(c: GameSession, id: String, qty: int, value: float, opts: Dictionary = {}) -> Contract:
	var o := Contract.new()
	o.id = id
	o.serial = 900 + c.contracts.offers.size() + c.contracts.active.size()
	o.tier = opts.get("tier", "trade")
	o.customer = "Test " + id
	o.archetype = "installer"
	o.archetype_label = "Installer"
	o.factory = opts.get("factory", "copper")
	o.product_name = "Copper Cylinder"
	o.quantity = qty
	o.unit_ref = float(opts.get("unit_ref", 8.0))
	o.value = value
	# The price follows the list price: margin = quoted price / what the cylinders would net at the quoted unit price.
	o.margin = float(opts.get("margin", value / (float(qty) * o.unit_ref) if o.unit_ref > 0.0 else 0.0))
	o.bonus = float(opts.get("bonus", 0.0))
	o.bonus_pct = o.bonus / value if value > 0.0 else 0.0
	o.bonus_by = float(opts.get("bonus_by", 0.0))
	o.deadline = float(opts.get("deadline", 0.0))
	o.est_full = float(opts.get("est_full", 100.0))
	o.rep = int(opts.get("rep", 5))
	o.penalty = int(opts.get("penalty", 2))
	o.pallets = int(opts.get("pallets", 2))
	o.expires_in = 900.0
	c.contracts.offers.append(o)
	return o


func accept(c: GameSession, id: String, alloc: int = -1) -> Contract:
	var problem := c.contracts.accept(id)
	check(problem == "", "accept %s (%s)" % [id, problem])
	var k := c.contracts.find(id)
	if k != null and alloc >= 0:
		c.contracts.set_allocation(id, alloc)
	return k


## Records every payout and stock release so money can be reconciled exactly.
class Ledger:
	var paid := 0.0
	var payouts: Array = []
	var failures: Array = []
	var released_units := 0.0
	var ranks: Array = []
	var readies: Array = []

	func attach(book: ContractBook) -> void:
		book.completed.connect(func(c: Contract, base: float, bonus: float, rep: int) -> void:
			paid += base + bonus
			payouts.append({"id": c.id, "base": base, "bonus": bonus, "rep": rep}))
		book.failed.connect(func(c: Contract, reason: String, units: float) -> void:
			released_units += units
			failures.append({"id": c.id, "reason": reason, "units": units}))
		book.rank_changed.connect(func(i: int, n: String) -> void: ranks.append([i, n]))
		book.ready.connect(func(c: Contract) -> void: readies.append(c.id))


# ------------------------------------------------------------------ tests
func test_golden_regression() -> void:
	# The scripted playthrough (30 minutes of clicking and upgrading both factories,
	# then two hours away) must reproduce the numbers recorded from v0.4.0 exactly:
	# adding contracts changes nothing for a player who does not use them.
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden_v0_4_0.json"))
	var got: Dictionary = load("res://tests/regression_scenario.gd").play(_data)
	var mismatches := _compare_leaves(golden, got, "")
	check(mismatches.is_empty(), "existing gameplay identical to v0.4.0: " + str(mismatches))


## Where two nested values differ (for readable failures).
func _diff(a: Variant, b: Variant, path: String) -> Array:
	var out: Array = []
	if a is Dictionary and b is Dictionary:
		for k: Variant in a:
			out.append_array(_diff(a[k], (b as Dictionary).get(k), path + "/" + str(k)))
	elif a is Array and b is Array:
		if a.size() != b.size():
			out.append("%s: size %d != %d" % [path, a.size(), b.size()])
		else:
			for i in a.size():
				out.append_array(_diff(a[i], b[i], path + "[%d]" % i))
	elif typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_FLOAT:
		if absf(a - b) > maxf(absf(a), 1.0) * 1e-9:      # saves go through JSON text, which is exact to ~13 digits
			out.append("%s: %s != %s" % [path, a, b])
	elif a != b:
		out.append("%s: %s != %s" % [path, a, b])
	return out


func _compare_leaves(a: Variant, b: Variant, path: String) -> Array:
	var bad: Array = []
	if a is Dictionary:
		for k: String in a:
			bad.append_array(_compare_leaves(a[k], (b as Dictionary).get(k), path + "/" + k))
	elif typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_FLOAT:
		if absf(a - b) > absf(a) * 1e-12:       # the fixture is parsed by Godot's JSON reader, which can differ in the last digit
			bad.append("%s: %s != %s" % [path, a, b])
	elif a != b:
		bad.append("%s: %s != %s" % [path, a, b])
	return bad


func test_rules_data() -> void:
	check(_rules.enabled, "contract rules load")
	check(_rules.ranks.size() >= 5, "several reputation ranks")
	var last := -1
	for r: Dictionary in _rules.ranks:
		check(int(r["at"]) > last, "rank thresholds ascend (%s)" % r["name"])
		last = int(r["at"])
	check(int(_rules.ranks[0]["at"]) == 0, "everyone starts at the first rank")
	for tid: String in ["trade", "commercial", "major"]:
		check(not _rules.tier(tid).is_empty(), "tier %s defined" % tid)
	check(_rules.rank_index(0) == 0 and _rules.rank_index(19) == 0 and _rules.rank_index(20) == 1, "rank boundaries")
	check(_rules.rank_index(99999) == _rules.ranks.size() - 1, "top rank holds")
	check(_rules.next_rank_at(_rules.ranks.size() - 1) == -1, "no rank beyond the top")
	check(_rules.rep_factor("trade", 0) == 1.0 and _rules.rep_factor("trade", 5) == 0.0, "trade reputation fades with rank")
	check(int(_rules.rank(0)["slots"]) == 3 and int(_rules.rank(4)["slots"]) == 4, "contract slots grow with rank")
	check(float(_rules.rank(3)["mix"].get("major", 0.0)) > 0.0 and float(_rules.rank(2)["mix"].get("major", 0.0)) == 0.0, "major agreements only from rank 3")


func ctx_for(rank: int, factories: Array, premium: bool = true) -> Dictionary:
	return {"rank": rank, "premium_allowed": premium, "exclude": [], "factories": factories}


func test_generation_reproducible() -> void:
	var facs := [{"id": "copper", "product_name": "Copper Cylinder", "profit": 8.0, "rate": 0.4}]
	var a := ContractGenerator.generate(_rules, ctx_for(1, facs), 99, 7)
	var b := ContractGenerator.generate(_rules, ctx_for(1, facs), 99, 7)
	check(JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict()), "same seed + serial + market -> identical contract")
	# generating other contracts in between changes nothing (no hidden shared state)
	for i in 20:
		ContractGenerator.generate(_rules, ctx_for(3, facs), 5, i)
	var c := ContractGenerator.generate(_rules, ctx_for(1, facs), 99, 7)
	check(JSON.stringify(a.to_dict()) == JSON.stringify(c.to_dict()), "generation does not depend on call history")
	var d := ContractGenerator.generate(_rules, ctx_for(1, facs), 99, 8)
	var e := ContractGenerator.generate(_rules, ctx_for(1, facs), 100, 7)
	check(JSON.stringify(a.to_dict()) != JSON.stringify(d.to_dict()), "different serial -> different contract")
	check(JSON.stringify(a.to_dict()) != JSON.stringify(e.to_dict()), "different seed -> different contract")
	# the whole board is reproducible from the saved seed
	var c1 := fresh()
	var c2 := fresh()
	c1.state.lifetime_earned = 100.0
	c2.state.lifetime_earned = 100.0
	c1.contracts.refresh_board()
	c2.contracts.refresh_board()
	var s1 := JSON.stringify(c1.contracts.to_dict())
	check(s1 == JSON.stringify(c2.contracts.to_dict()) and c1.contracts.offers.size() == 3, "two companies with one seed get the same board")


func test_generation_balance() -> void:
	var counts := {"trade": 0, "commercial": 0, "major": 0}
	var customers := {}
	var premium_seen := 0
	var checked := 0
	var margins: Array = []
	var bad: Array = []
	# Capacities and prices spanning the whole game (the balance bot reaches ~15,000/min and 40x profit).
	for rank in range(0, _rules.ranks.size()):
		for rate_per_min: float in [0.5, 9.5, 40.0, 630.0, 4000.0, 15000.0, 120000.0]:
			for profit: float in [8.0, 34.0, 315.0, 2000.0, 25000.0]:
				var facs := [{"id": "copper", "product_name": "Copper Cylinder", "profit": profit, "rate": rate_per_min / 60.0}]
				for seed_value in [1, 77, 2024]:
					for serial in range(1, 11):
						var c := ContractGenerator.generate(_rules, ctx_for(rank, facs), seed_value, serial)
						checked += 1
						if c == null:
							bad.append("null contract")
							continue
						var tier := _rules.tier(c.tier)
						var rank_def := _rules.rank(rank)
						var rate := rate_per_min / 60.0
						counts[c.tier] += 1
						customers[c.customer] = true
						if c.premium:
							premium_seen += 1
						var market := float(c.quantity) * profit
						margins.append(c.value / market)
						if rank < int(tier["min_rank"]):
							bad.append("tier %s offered at rank %d" % [c.tier, rank])
						if rate * 60.0 * profit < float(tier["min_potential"]):
							bad.append("tier %s offered below its capacity gate" % c.tier)
						if c.quantity < int(tier["min_quantity"]) or c.quantity <= 0:
							bad.append("quantity %d below the tier minimum" % c.quantity)
						if c.value < 0.9 * market or c.value > 1.55 * market + 1.0:
							bad.append("value %.0f outside 0.9-1.55x market %.0f (%s, %s)" % [c.value, market, c.tier, c.archetype])
						if c.value + c.bonus > 1.75 * market + 1.0:
							bad.append("payout+bonus above 1.75x market")
						if c.bonus > 0.16 * c.value + 1.0:
							bad.append("bonus above 16% of value")
						if c.bonus > 0.0 and c.bonus_by < 1.2 * c.est_full:
							bad.append("bonus window shorter than 1.2x the full-rate build time")
						if c.deadline > 0.0 and c.deadline < 2.0 * c.est_full:
							bad.append("impossible-ish deadline %.0f for est %.0f" % [c.deadline, c.est_full])
						var max_minutes: float = float(tier["minutes"][1]) * float(rank_def["size"]) * 1.5 * 1.15 * 1.3
						if c.quantity > int(tier["min_quantity"]) and c.est_full > max_minutes * 60.0:
							bad.append("order bigger than the tier allows (%.0fs)" % c.est_full)
						if c.rep < 1 or c.rep > roundi(float(tier["rep"][1]) * 1.5) or c.penalty < 1 or c.penalty > c.rep:
							bad.append("reputation %d / penalty %d out of range" % [c.rep, c.penalty])
						if c.customer.is_empty() or c.customer.length() > 34:
							bad.append("customer name length")
						for i in c.customer.length():
							if c.customer.unicode_at(i) < 32 or c.customer.unicode_at(i) > 126:
								bad.append("customer name has a character the pixel font cannot draw: " + c.customer)
						if c.pallets < 1 or c.pallets > 4 or c.factory != "copper" or c.expires_in <= 0.0:
							bad.append("pallets / factory / lifetime")
	check(bad.is_empty(), "all %d generated contracts within bounds: %s" % [checked, str(bad.slice(0, 5))])
	check(counts["trade"] > 0 and counts["commercial"] > 0 and counts["major"] > 0, "every tier gets generated: " + str(counts))
	var varied := {}
	var vfacs := [{"id": "copper", "product_name": "Copper Cylinder", "profit": 100.0, "rate": 20.0}]
	for serial in range(1, 301):
		varied[ContractGenerator.generate(_rules, ctx_for(3, vfacs), 5, serial).customer] = true
	check(varied.size() >= 120, "plenty of customer variety (%d different names in 300 offers)" % varied.size())
	check(premium_seen > 0, "premium opportunities do occur")
	margins.sort()
	var median: float = margins[margins.size() / 2]
	check(median > 1.08 and median < 1.35, "typical contract pays a sensible premium over selling (median %.2fx)" % median)
	check(margins[0] >= 0.9, "no contract pays well below the market price (min %.2fx)" % margins[0])

	# Rank gating on the board: rank 0 sees only small trade orders; majors need rank 3.
	var facs2 := [{"id": "copper", "product_name": "Copper Cylinder", "profit": 100.0, "rate": 20.0}]
	var seen_r0 := {}
	var seen_r2 := {}
	var seen_r3 := {}
	for serial in range(1, 200):
		seen_r0[ContractGenerator.generate(_rules, ctx_for(0, facs2), 3, serial).tier] = true
		seen_r2[ContractGenerator.generate(_rules, ctx_for(2, facs2), 3, serial).tier] = true
		seen_r3[ContractGenerator.generate(_rules, ctx_for(3, facs2), 3, serial).tier] = true
	check(seen_r0.keys() == ["trade"], "rank 0 offers only small trade orders")
	check(not seen_r2.has("major") and seen_r2.has("commercial"), "rank 2 sees commercial but not major contracts")
	check(seen_r3.has("major") and seen_r3.has("commercial") and seen_r3.has("trade"), "rank 3 sees every tier")
	# Capacity gating: a weak factory never gets commercial/major work, however high the rank.
	var weak := [{"id": "copper", "product_name": "Copper Cylinder", "profit": 8.0, "rate": 0.15}]
	var weak_tiers := {}
	for serial in range(1, 100):
		weak_tiers[ContractGenerator.generate(_rules, ctx_for(5, weak), 8, serial).tier] = true
	check(weak_tiers.keys() == ["trade"], "a factory without the capacity is only offered small orders")
	# Premium pause: none while the lockout is active.
	var premium_during_lockout := 0
	for serial in range(1, 300):
		if ContractGenerator.generate(_rules, ctx_for(5, facs2, false), 11, serial).premium:
			premium_during_lockout += 1
	check(premium_during_lockout == 0, "no premium offers while premium customers are paused")
	# Nothing to build -> nothing offered.
	check(ContractGenerator.generate(_rules, ctx_for(0, []), 1, 1) == null, "no factory, no offers")
	check(ContractGenerator.generate(_rules, ctx_for(0, [{"id": "copper", "product_name": "x", "profit": 8.0, "rate": 0.0}]), 1, 1) == null, "a factory that builds nothing gets no offers")


func test_generation_extremes() -> void:
	var huge := [{"id": "copper", "product_name": "Copper Cylinder", "profit": 1.0e40, "rate": 1.0e20}]
	var c := ContractGenerator.generate(_rules, ctx_for(5, huge), 1, 1)
	check(c != null and c.quantity > 0 and c.quantity <= int(ContractGenerator.MAX_QUANTITY), "absurdly large factories still get a valid quantity (%d)" % c.quantity)
	check(c.value > 0.0 and not is_inf(c.value) and not is_nan(c.value), "value stays finite")
	var tiny := [{"id": "copper", "product_name": "Copper Cylinder", "profit": 0.01, "rate": 0.0001}]
	var t := ContractGenerator.generate(_rules, ctx_for(0, tiny), 1, 1)
	check(t != null and t.quantity >= 5 and t.value >= 1.0, "tiny factories still get a valid contract")
	check(ContractGenerator.nice_quantity(7.2) == 7 and ContractGenerator.nice_quantity(137.0) == 150 and ContractGenerator.nice_quantity(2340.0) == 2500, "quantities are tidy numbers")
	check(ContractGenerator.nice_quantity(0.2) == 1, "never below one cylinder")


func test_board_unlock_and_refresh() -> void:
	var c := GameSession.new(_data)
	c.contracts.reset(31337)
	var added := []
	c.contracts.offer_added.connect(func(o: Contract) -> void: added.append(o.id))
	var unlocked := []
	c.contracts.board_unlocked.connect(func() -> void: unlocked.append(true))
	run(c, 5.0)
	check(not c.contracts.unlocked and c.contracts.offers.is_empty(), "no orders before the company has earned anything")
	c.state.lifetime_earned = 60.0
	run(c, 1.0)
	check(c.contracts.unlocked and unlocked.size() == 1, "the board opens once the company has earned a little (once)")
	check(c.contracts.offers.size() == 3 and added.size() == 3, "an opening board of 3 offers: %d" % c.contracts.offers.size())
	for o in c.contracts.offers:
		check(o.tier == "trade" and o.status == Contract.Status.OFFER, "early offers are small trade orders")
		check(o.factory == "copper", "early offers are for the copper works (stainless is not built)")
		check(o.quantity >= 5 and o.quantity <= 80, "early quantity is a small, achievable order (%d)" % o.quantity)
	# Offers expire; the board refills on its own timer.
	var first_ids: Array = c.contracts.offers.map(func(o: Contract) -> String: return o.id)
	run(c, 1000.0)
	var still: int = c.contracts.offers.filter(func(o: Contract) -> bool: return first_ids.has(o.id)).size()
	check(still == 0, "unaccepted offers expire after their lifetime")
	check(c.contracts.offers.size() >= 1, "new customers keep calling (%d on the board)" % c.contracts.offers.size())
	# Rank-up widens the board and brings new offers quickly.
	c.contracts.reputation = 25
	c.contracts.offers.clear()
	c.contracts.offer_timer = 100.0
	c.contracts._add_rep(60)
	check(c.contracts.offer_timer <= 8.0, "a rank-up makes new offers arrive quickly")
	check(c.contracts.board_capacity() == 5, "the board grows with rank (%d)" % c.contracts.board_capacity())


func test_accept_and_limits() -> void:
	var c := fresh()
	var ledger := Ledger.new()
	ledger.attach(c.contracts)
	var accepted := []
	c.contracts.accepted.connect(func(k: Contract) -> void: accepted.append(k.id))
	for i in 5:
		offer(c, "a%d" % i, 100, 1000.0)
	check(c.contracts.offers.size() == 5, "offers are on the board")
	check(c.contracts.accept("nope") != "", "accepting an unknown offer is refused")
	var first := accept(c, "a0")
	check(first.status == Contract.Status.ACTIVE and first.allocation == 50, "a new contract starts at the default 50% share")
	check(c.contracts.offers.size() == 4 and c.contracts.active.size() == 1, "accepting moves it from the board to your contracts")
	check(accepted == ["a0"], "acceptance is announced once")
	check(c.contracts.free_share("copper") == 50 and c.contracts.committed_share("copper") == 50, "half of copper output is promised")
	var second := accept(c, "a1")
	check(second.allocation == 30 and c.contracts.free_share("copper") == 20, "a second contract takes what is free except the 20%% kept for sales (%d)" % second.allocation)
	check(c.contracts.accept("a2") != "" and c.contracts.find("a2") == null, "a third copper contract is refused: it would leave nothing to sell")
	check(c.contracts.offers.size() == 3, "a refused offer stays on the board")
	# Lowering one share makes room.
	c.contracts.set_allocation("a0", 20)
	check(c.contracts.free_share("copper") == 50, "lowering a share frees capacity (%d)" % c.contracts.free_share("copper"))
	var third := accept(c, "a2")
	check(third.allocation == 30, "a new contract takes what is free (%d)" % third.allocation)
	check(c.contracts.accept("a3") != "", "slot limit: only 3 contracts at once at the first rank")
	check(c.contracts.active.size() == 3, "three accepted")
	# Shares never exceed 100% at one factory.
	check(c.contracts.set_allocation("a0", 100) == 40 and c.contracts.find("a0").allocation == 40, "a share is limited by what the others leave, but you may go past the 80%% default (%d)" % c.contracts.find("a0").allocation)
	check(c.contracts.set_allocation("a0", 0) == 0 and c.contracts.free_share("copper") == 40, "a share can be set to 0")
	check(c.contracts.set_allocation("a1", 47) == 45, "shares move in 5%% steps (47 -> %d)" % c.contracts.find("a1").allocation)
	check(c.contracts.set_allocation("nope", 10) == 0, "setting the share of an unknown contract does nothing")
	# Deadline-driven default: a tight deadline asks for more of the factory up front.
	var d := fresh()
	offer(d, "t1", 100, 1000.0, {"est_full": 1000.0, "deadline": 1200.0})
	check(accept(d, "t1").allocation == 80, "a deadline that needs the whole factory proposes the most a new order may take: 80%")
	var e := fresh()
	offer(e, "t2", 100, 1000.0, {"est_full": 100.0, "deadline": 1200.0})
	check(accept(e, "t2").allocation == 50, "a roomy deadline keeps the default 50%")
	# Different factories do not share a pool of output.
	var f := fresh()
	f.factory("copper").state.unlocked = true
	f.factory("stainless").state.unlocked = true
	offer(f, "x1", 100, 1000.0)
	offer(f, "x2", 100, 1000.0)
	offer(f, "x3", 10, 1000.0, {"factory": "stainless"})
	accept(f, "x1", 100)
	check(accept(f, "x3").allocation == 50 and f.contracts.free_share("stainless") == 50, "each factory has its own 100% to allocate")
	check(f.contracts.accept("x2") != "", "copper is full even though stainless has room")


func test_allocation_routing() -> void:
	var c := fresh()
	var s := c.factory("copper")
	var ledger := Ledger.new()
	ledger.attach(c.contracts)
	offer(c, "r1", 100000, 5.0e5)
	var k := accept(c, "r1", 40)
	var shipped := 0
	var to_contracts := 0.0
	for i in 1000:
		to_contracts += c.contracts.route("copper", 1.0)
		shipped += 1
	near(to_contracts, 400.0, 1e-6, "40%% allocation sends exactly 400 of 1000 cylinders to the contract")
	near(k.delivered, 400.0, 1e-6, "and the contract counts them")
	# every shipment is split by the share, however big or small: 40% of 1 is 0.4, of 1.25 is 0.5, of 30 is 12
	var c2 := fresh()
	offer(c2, "r2", 1000, 1000.0)
	accept(c2, "r2", 40)
	var splits_ok := true
	for count: float in [1.0, 1.25, 30.0, 2.5, 1.0, 7.0]:
		splits_ok = splits_ok and absf(c2.contracts.route("copper", count) - 0.4 * count) < 1e-9
	check(splits_ok, "every shipment is split exactly by the contract's share")
	# 100% means nothing at all is left to sell, even for fractional batches
	var c2b := fresh()
	offer(c2b, "r2b", 100000, 1000.0)
	accept(c2b, "r2b", 100)
	var all_taken := true
	for i in 100:
		all_taken = all_taken and absf(c2b.contracts.route("copper", 1.25) - 1.25) < 1e-12
	check(all_taken, "a 100% share takes the whole of a fractional batch (nothing leaks into sales)")
	# allocation 0 -> nothing goes to the contract
	var c3 := fresh()
	offer(c3, "r3", 1000, 1000.0)
	accept(c3, "r3", 0)
	var total := 0.0
	for i in 200:
		total += c3.contracts.route("copper", 1.0)
	check(total == 0.0, "a contract with 0% share receives nothing")
	# a contract only receives from its own factory
	var c4 := fresh()
	offer(c4, "r4", 1000, 1000.0, {"factory": "copper"})
	accept(c4, "r4", 100)
	check(c4.contracts.route("stainless", 1.0) == 0.0 and c4.contracts.route("copper", 1.0) == 1.0, "only the matching factory's output is routed")
	# Two contracts at one factory split output by their own shares.
	var c5 := fresh()
	offer(c5, "p1", 100000, 1.0e5)
	offer(c5, "p2", 100000, 1.0e5)
	accept(c5, "p1", 30)
	accept(c5, "p2", 60)
	for i in 1000:
		c5.contracts.route("copper", 1.0)
	check(absi(c5.contracts.find("p1").delivered - 300) <= 1 and absi(c5.contracts.find("p2").delivered - 600) <= 1, "two contracts get 30%% and 60%% of 1000 (%d, %d)" % [c5.contracts.find("p1").delivered, c5.contracts.find("p2").delivered])
	# Production speed untouched: same cylinders made with and without a contract.
	var with_contract := fresh()
	var without := fresh()
	automate(with_contract.factory("copper"), 6)
	automate(without.factory("copper"), 6)
	offer(with_contract, "s1", 1000000, 1.0e6)
	accept(with_contract, "s1", 70)
	run(with_contract, 300.0)
	run(without, 300.0)
	near(with_contract.factory("copper").state.cylinders_made, without.factory("copper").state.cylinders_made, 1e-9, "contracts do not change how fast cylinders are built")
	check(with_contract.state.cash < without.state.cash and with_contract.state.cash > 0.0, "contracted cylinders do not earn sale revenue, the rest still does")


func test_no_double_counting() -> void:
	# Run a busy factory with changing shares and several contracts finishing and
	# failing, then reconcile every cylinder and every pound.
	var c := fresh()
	var s := c.factory("copper")
	automate(s, 7)
	var ledger := Ledger.new()
	ledger.attach(c.contracts)
	var profit := s.profit_per_cylinder()
	check(profit == 8.0, "copper nets 8 per cylinder at the start")
	offer(c, "d1", 300, 5000.0)
	offer(c, "d2", 200, 3000.0, {"deadline": 90.0})
	var k1 := accept(c, "d1", 35)
	var k2 := accept(c, "d2", 15)
	var t := 0.0
	while t < 600.0:
		run(c, 20.0)
		t += 20.0
		if int(t) == 120:
			c.contracts.set_allocation("d1", 60)
		if int(t) == 300:
			offer(c, "d3", 150, 2500.0)
			accept(c, "d3", 30)
		# whatever happens, the books balance at every checkpoint
		var made := s.state.cylinders_made
		near(made, s.state.cylinders_sold + s.state.cylinders_contracted, 1e-6, "made = sold + contracted at t=%d" % int(t))
	# Money: starting cash 0 + sales + payouts + released stock
	var sold_cash := s.state.cylinders_sold * profit
	near(c.state.cash, sold_cash + ledger.paid, 0.01, "cash = every sold cylinder + every payout (no contract cylinder was also sold)")
	# Every cylinder built for contracts is accounted for by a contract.
	var in_contracts := 0.0
	for k in c.contracts.active:
		in_contracts += k.delivered
	near(s.state.cylinders_contracted, in_contracts + float(c.contracts.stats["units"]), 0.0001, "contract cylinders = those in open contracts + those delivered (stock released after a failure is counted as sold)")
	check(ledger.failures.size() == 1 and ledger.failures[0]["id"] == "d2", "the tight-deadline contract failed (exactly once)")
	check(absf(ledger.released_units - float(ledger.failures[0]["units"])) < 1e-9 and ledger.released_units > 0.0, "its %d built cylinders were released to stock and sold" % ledger.released_units)
	# lifetime and factory earnings equal cash (nothing spent in this scenario)
	near(c.state.lifetime_earned, c.state.cash, 0.01, "lifetime earnings = cash when nothing is spent")
	near(s.state.earned, c.state.cash, 0.01, "factory earnings = cash")


func test_manual_clicks_feed_contracts() -> void:
	# Clicked cylinders go through the same door as automatic ones.
	var c := fresh()
	var s := c.factory("copper")
	offer(c, "m1", 100000, 1.0e5)
	var k := accept(c, "m1", 50)
	for i in 6000:
		if i % 6 == 0:
			s.click()
		c.tick(TICK)
	check(s.state.cylinders_made > 20.0, "clicking built cylinders (%s)" % s.state.cylinders_made)
	check(s.automated_count() == 0, "...with no machines at all")
	near(float(k.delivered), s.state.cylinders_made * 0.5, 1.0, "half the hand-made cylinders went to the contract")
	near(s.state.cylinders_made, s.state.cylinders_sold + s.state.cylinders_contracted, 1e-6, "hand-made cylinders are counted once")
	near(c.state.cash, s.state.cylinders_sold * 8.0, 0.001, "and only the sold half paid out")
	# A mix of clicking and machines
	var d := fresh()
	var t := d.factory("copper")
	t.state.upgrade_levels["machine_cut"] = 3
	t.state.upgrade_levels["machine_roll"] = 3
	t.refresh()
	offer(d, "m2", 100000, 1.0e5)
	accept(d, "m2", 25)
	for i in 3600:
		if i % 10 == 0:
			t.click()
		d.tick(TICK)
	near(t.state.cylinders_made, t.state.cylinders_sold + t.state.cylinders_contracted, 1e-6, "part-automated clicking counts every cylinder once")


func test_completion_and_dispatch() -> void:
	var c := fresh()
	var s := c.factory("copper")
	automate(s, 6)
	var ledger := Ledger.new()
	ledger.attach(c.contracts)
	offer(c, "c1", 60, 900.0, {"pallets": 3, "rep": 6})
	var k := accept(c, "c1", 100)
	check(k.allocation == 100, "all of the factory to this order")
	var sold_before := s.state.cylinders_sold
	run(c, 22.0)         # the first cylinders need a few seconds to ride the belts
	check(k.status == Contract.Status.ACTIVE and k.delivered < 60 and k.delivered > 0, "the order fills up gradually (%d/60)" % k.delivered)
	check(c.state.cash == 0.0 and s.state.cylinders_sold == sold_before, "with 100% allocated nothing is sold meanwhile")
	var guard := 0
	while k.status == Contract.Status.ACTIVE and guard < 100:
		run(c, 1.0)
		guard += 1
	check(k.status == Contract.Status.READY and absf(k.delivered - 60) < 1e-6, "the order completes at exactly its quantity (%d)" % k.delivered)
	check(k.allocation == 0 and c.contracts.free_share("copper") == 100, "a finished order releases its share of the factory")
	check(ledger.readies == ["c1"], "completion announced once")
	check(c.state.cash == 0.0 and ledger.paid == 0.0, "nothing is paid until the order is dispatched")
	check(absf(k.delivered - 60) < 1e-6 and s.state.cylinders_contracted == 60.0, "exactly 60 cylinders were built for it")
	# Normal sales resume at once.
	var cash0 := c.state.cash
	run(c, 10.0)
	check(c.state.cash > cash0, "the rest of the business keeps earning while the order waits for collection")
	check(absf(k.delivered - 60) < 1e-6 and s.state.cylinders_contracted == 60.0, "no more cylinders go to a finished order")
	# Dispatch.
	var started := []
	c.contracts.dispatch_started.connect(func(x: Contract) -> void: started.append(x.id))
	check(c.contracts.dispatch("c1") == "" and k.status == Contract.Status.DISPATCHING, "dispatch starts the lorry")
	near(k.dispatch_total, 3.2 + 1.2 * 3.0, 1e-9, "dispatch takes 3.2s + 1.2s per pallet")
	check(started == ["c1"], "dispatch start announced")
	check(k.dispatch_progress() == 0.0, "the lorry has not left yet")
	var cash1 := c.state.cash
	run(c, k.dispatch_total - 0.5)
	check(ledger.paid == 0.0 and c.contracts.find("c1") != null, "the payout waits until the lorry has gone")
	check(k.dispatch_progress() > 0.8 and k.dispatch_progress() < 1.0, "dispatch progress runs from 0 to 1 (%.2f)" % k.dispatch_progress())
	run(c, 1.0)
	check(ledger.payouts.size() == 1 and c.contracts.find("c1") == null, "once the lorry leaves the contract is paid and closed")
	near(ledger.paid, 900.0, 1e-9, "paid exactly the contract value")
	check(c.contracts.history.size() == 1 and c.contracts.history[0]["outcome"] == "delivered" and c.contracts.history[0]["quantity"] == 60, "recorded in the history")
	check(c.contracts.reputation == 6, "reputation earned: %d" % c.contracts.reputation)
	check(int(c.contracts.stats["completed"]) == 1 and int(c.contracts.stats["units"]) == 60, "statistics updated")


func test_dispatch_pays_once() -> void:
	var c := fresh()
	var s := c.factory("copper")
	var ledger := Ledger.new()
	ledger.attach(c.contracts)
	offer(c, "e1", 10, 500.0, {"rep": 4})
	var k := accept(c, "e1", 100)
	check(c.contracts.dispatch("e1") != "", "an unfinished order cannot be dispatched")
	k.delivered = 10
	c.contracts.route("copper", 0.0)        # no-op
	c.contracts._complete(k)
	check(k.status == Contract.Status.READY, "ready")
	var cash0 := c.state.cash
	var earned0 := c.state.lifetime_earned
	var fearned0 := s.state.earned
	check(c.contracts.dispatch("e1") == "", "first dispatch accepted")
	check(c.contracts.dispatch("e1") != "", "dispatching again while loading is refused")
	run(c, 30.0)
	check(ledger.payouts.size() == 1, "one payout, however many times dispatch was pressed")
	near(c.state.cash - cash0, 500.0, 1e-9, "cash rose by exactly the contract value (%s)" % (c.state.cash - cash0))
	near(c.state.lifetime_earned - earned0, 500.0, 1e-9, "lifetime earnings include the payout")
	near(s.state.earned - fearned0, 500.0, 1e-9, "so do the producing factory's earnings")
	check(c.contracts.dispatch("e1") != "" and c.contracts.find("e1") == null, "a dispatched contract cannot be dispatched again")
	run(c, 30.0)
	check(ledger.payouts.size() == 1 and c.contracts.reputation == 4, "later time changes nothing: still one payout, reputation %d" % c.contracts.reputation)
	# One lorry at a time per factory; a second order waits its turn.
	var d := fresh()
	offer(d, "q1", 5, 100.0)
	offer(d, "q2", 5, 100.0)
	for id in ["q1", "q2"]:
		var q := accept(d, id, 0)
		q.delivered = 5
		d.contracts._complete(q)
	check(d.contracts.dispatch("q1") == "" and d.contracts.dispatch("q2") != "", "only one lorry loads at a time at a factory")
	run(d, 12.0)
	check(d.contracts.dispatch("q2") == "", "the next order can go once the first has left")
	run(d, 12.0)
	check(d.contracts.active.is_empty() and d.contracts.history.size() == 2 and d.contracts.stats["completed"] == 2, "both delivered")
	near(d.state.cash, 200.0, 1e-9, "paid 2 x 100")


func test_price_follows_list_price() -> void:
	# The contract price is indexed to the factory's list price: upgrades bought while an
	# order is being built raise what it pays in step, so its premium never goes stale.
	var c := fresh()
	var s := c.factory("copper")
	var ledger := Ledger.new()
	ledger.attach(c.contracts)
	offer(c, "g1", 100, 880.0, {"unit_ref": 8.0})          # 1.10x selling at the time it was offered
	var k := accept(c, "g1", 100)
	near(k.margin, 1.1, 1e-9, "agreed price is 10% over selling")
	near(c.contracts.quote(k), 880.0, 1e-9, "quoted 880 at today's price")
	s.state.upgrade_levels["finish"] = 6                   # Polished Finish: price x1.2^6
	s.refresh()
	var profit := s.profit_per_cylinder()
	check(profit > 20.0, "profit per cylinder rose to %s" % profit)
	near(c.contracts.quote(k), roundf(100.0 * profit * 1.1), 1e-9, "the quote rose with it, keeping the same 10%% premium (%s)" % c.contracts.quote(k))
	k.delivered = 100
	c.contracts._complete(k)
	c.contracts.dispatch("g1")
	run(c, 10.0)
	near(ledger.payouts[0]["base"], roundf(100.0 * profit * 1.1), 1e-9, "paid at the list price of the day: 10%% over selling the same cylinders")
	# Contract premium is the same fraction at any stage of the game.
	for level in [0, 3, 9]:
		var d := fresh()
		d.factory("copper").state.upgrade_levels["finish"] = level
		d.factory("copper").refresh()
		var pf := d.factory("copper").profit_per_cylinder()
		var o := offer(d, "p%d" % level, 50, 50.0 * pf * 1.25, {"unit_ref": pf})
		near(d.contracts.quote(o) / (50.0 * pf), 1.25, 0.001, "a 25%% premium contract pays 25%% over selling at Finish level %d" % level)
	# A fixed-price contract (no margin) keeps its written price.
	var e := fresh()
	var ledger2 := Ledger.new()
	ledger2.attach(e.contracts)
	var fixed := offer(e, "g2", 100, 1000.0, {"margin": 0.0})
	fixed.margin = 0.0
	var k2 := accept(e, "g2", 100)
	e.factory("copper").state.upgrade_levels["finish"] = 6
	e.factory("copper").refresh()
	k2.delivered = 100
	e.contracts._complete(k2)
	e.contracts.dispatch("g2")
	run(e, 10.0)
	near(ledger2.payouts[0]["base"], 1000.0, 1e-9, "a fixed-price contract pays its written price")
	# The bonus follows the price as well.
	var f := fresh()
	var ledger3 := Ledger.new()
	ledger3.attach(f.contracts)
	offer(f, "g3", 100, 1000.0, {"bonus": 100.0, "bonus_by": 600.0})
	var k3 := accept(f, "g3", 100)
	f.factory("copper").state.upgrade_levels["finish"] = 6
	f.factory("copper").refresh()
	k3.delivered = 100
	f.contracts._complete(k3)
	f.contracts.dispatch("g3")
	run(f, 10.0)
	near(ledger3.payouts[0]["bonus"], roundf(ledger3.payouts[0]["base"] * 0.1), 1.0, "the bonus stays 10%% of the price")


func test_bonus_rules() -> void:
	# Early delivery earns the bonus and 25% more reputation; late (but before any deadline) does not.
	for early in [true, false]:
		var c := fresh()
		var ledger := Ledger.new()
		ledger.attach(c.contracts)
		offer(c, "b1", 40, 1000.0, {"bonus": 150.0, "bonus_by": 60.0, "deadline": 400.0, "rep": 8})
		var k := accept(c, "b1", 0)
		run(c, 30.0 if early else 90.0)
		k.delivered = 40
		c.contracts._complete(k)
		check(k.bonus_earned == early, "bonus %s when delivered %s the bonus window" % ["earned" if early else "missed", "inside" if early else "after"])
		c.contracts.dispatch("b1")
		run(c, 12.0)
		var p: Dictionary = ledger.payouts[0]
		near(p["bonus"], 150.0 if early else 0.0, 1e-9, "bonus paid: %s" % p["bonus"])
		check(p["rep"] == (10 if early else 8), "reputation %d (+25%% with the bonus)" % p["rep"])
		near(c.state.cash, 1150.0 if early else 1000.0, 1e-9, "cash")
	# A contract with no bonus never pays one.
	var d := fresh()
	offer(d, "b2", 5, 100.0)
	var k2 := accept(d, "b2", 0)
	k2.delivered = 5
	d.contracts._complete(k2)
	check(not k2.bonus_earned, "no bonus offered, none earned")


func test_reputation() -> void:
	var c := fresh()
	var book := c.contracts
	var ledger := Ledger.new()
	ledger.attach(book)
	check(book.reputation == 0 and book.rank_index() == 0 and book.rank_name() == "Unknown Workshop", "the company starts with no reputation")
	check(book.slots() == 3 and book.board_capacity() == 3, "starting limits: 3 slots, 3 offers")
	book._add_rep(19)
	check(book.rank_index() == 0 and ledger.ranks.is_empty(), "19 points: still the first rank")
	book._add_rep(1)
	check(book.rank_index() == 1 and ledger.ranks == [[1, "Local Supplier"]], "20 points: rank up announced once")
	var prog := book.rank_progress()
	check(prog["have"] == 0 and prog["need"] == 60 and prog["fraction"] == 0.0, "progress to the next rank is tracked")
	book._add_rep(30)
	near(book.rank_progress()["fraction"], 0.5, 1e-9, "halfway to the next rank")
	book.reputation = 600
	check(book.rank_index() == 4 and book.slots() == 4, "rank 4 unlocks a fourth contract slot")
	# Reputation per contract fades for small orders as the company outgrows them (no grinding).
	var t := offer(c, "rt", 5, 10.0, {"tier": "trade", "rep": 4})
	var cm := offer(c, "rc", 5, 10.0, {"tier": "commercial", "rep": 16})
	var mj := offer(c, "rm", 5, 10.0, {"tier": "major", "rep": 60})
	var trade_rep: Array = []
	var com_rep: Array = []
	for pts in [0, 20, 80, 220, 500, 1000]:
		book.reputation = pts
		trade_rep.append(book.rep_reward(t))
		com_rep.append(book.rep_reward(cm))
	check(trade_rep == [4, 3, 2, 1, 0, 0], "trade orders stop paying reputation as you grow: " + str(trade_rep))
	check(com_rep == [16, 16, 16, 16, 8, 4], "commercial reputation fades at the top: " + str(com_rep))
	book.reputation = 500
	check(book.rep_reward(mj) == 60 and book.rep_reward(mj, true) == 75, "major agreements keep their value; the bonus adds 25%% (%d)" % book.rep_reward(mj, true))
	# A failure costs reputation but never a rank already earned.
	book.reputation = 85
	book._fail(accept_helper(c, "rf", 50, 100.0, {"penalty": 10}), "deadline")
	check(book.reputation == 80 and book.rank_index() == 2, "a failure cannot drop a rank (85 - 10 -> %d, floor 80)" % book.reputation)
	book.reputation = 300
	book._fail(accept_helper(c, "rg", 50, 100.0, {"penalty": 7}), "deadline")
	check(book.reputation == 293, "a failure costs its penalty (%d)" % book.reputation)
	book.reputation = 2
	book._fail(accept_helper(c, "rh", 50, 100.0, {"penalty": 9}), "deadline")
	check(book.reputation == 0, "reputation never goes negative")
	# reputation really unlocks bigger customers: a rank-0 board has no commercial work
	var low := fresh()
	low.state.lifetime_earned = 100.0
	low.contracts.refresh_board()
	var high := fresh()
	high.state.lifetime_earned = 100.0
	high.contracts.reputation = 300
	high.factory("copper").state.upgrade_levels["finish"] = 6
	for m: Dictionary in high.factory("copper").data.machines:
		high.factory("copper").state.upgrade_levels[m["id"]] = 30
	high.factory("copper").refresh()
	high.contracts.refresh_board()
	check(low.contracts.offers.all(func(o: Contract) -> bool: return o.tier == "trade"), "a new company is only offered small trade orders")
	check(high.contracts.board_capacity() == 6 and high.contracts.offers.size() == 6, "a reputable company has a bigger board")
	check(high.contracts.offers.any(func(o: Contract) -> bool: return o.tier != "trade"), "...with commercial or major contracts on it")


func accept_helper(c: GameSession, id: String, qty: int, value: float, opts: Dictionary = {}) -> Contract:
	offer(c, id, qty, value, opts)
	var k := accept(c, id, 0)
	k.delivered = 0
	return k


func test_deadline_failure() -> void:
	var c := fresh()
	var s := c.factory("copper")
	automate(s, 4)                       # 0.5 cylinders/second
	var ledger := Ledger.new()
	ledger.attach(c.contracts)
	c.contracts.reputation = 50
	offer(c, "f1", 1000, 9000.0, {"deadline": 120.0, "penalty": 6, "rep": 12, "bonus": 100.0, "bonus_by": 60.0})
	var k := accept(c, "f1", 20)
	near(k.time_left, 120.0, 1e-9, "the clock starts at the deadline")
	run(c, 30.0)
	near(k.time_left, 90.0, 0.02, "time left counts down in play (%s)" % k.time_left)
	near(k.elapsed, 30.0, 0.02, "elapsed counts up")
	check(c.contracts.lockout == 0.0 and ledger.failures.is_empty(), "no consequence before the deadline")
	var cash_before := c.state.cash
	run(c, 91.0)
	check(ledger.failures.size() == 1 and ledger.failures[0]["reason"] == "deadline", "missing the deadline fails the contract (once)")
	check(c.contracts.find("f1") == null and c.contracts.active.is_empty(), "the failed contract is closed and its slot is free")
	var units: int = ledger.failures[0]["units"]
	check(units > 3 and units < 20, "the %d cylinders built for it so far were not destroyed" % units)
	# The stock is sold at market price, in addition to ordinary sales.
	var expected := (s.state.cylinders_sold - units) * 8.0 + units * 8.0
	near(c.state.cash, s.state.cylinders_sold * 8.0, 0.01, "the released stock was sold at the normal price (cash %s)" % c.state.cash)
	near(s.state.cylinders_contracted, 0.0, 1e-9, "no cylinders remain counted as contracted")
	near(s.state.cylinders_made, s.state.cylinders_sold, 1e-6, "made = sold after the failure")
	check(c.contracts.reputation == 44, "a modest reputation penalty (50 -> %d)" % c.contracts.reputation)
	check(c.contracts.history[0]["outcome"] == "deadline" and c.contracts.history[0]["rep"] == -6, "failure recorded in the history")
	check(int(c.contracts.stats["failed"]) == 1, "statistics updated")
	near(c.contracts.lockout, 900.0 - 1.0, 1.5, "premium customers pause for 15 minutes (%s)" % c.contracts.lockout)
	var ctx := c.contracts._context()
	check(ctx["premium_allowed"] == false, "no premium offers while paused")
	run(c, 905.0)
	check(c.contracts.lockout == 0.0 and c.contracts._context()["premium_allowed"] == true, "premium offers return afterwards")
	# Completion beats a deadline that falls in the same moment: the factories tick first (route),
	# then the book's clock (tick), so a contract finished in this tick is never failed by it.
	var d := fresh()
	offer(d, "f2", 5, 100.0, {"deadline": 12.0})
	var k2 := accept(d, "f2", 100)
	k2.time_left = 0.01
	k2.delivered = 4
	d.contracts.route("copper", 1.0)
	d.contracts.tick(1.0)
	check(k2.status == Contract.Status.READY and d.contracts.stats["failed"] == 0, "an order finished in the same tick as its deadline counts as on time")
	# A READY order has no deadline pressure while it waits for the lorry.
	run(d, 500.0)
	check(k2.status == Contract.Status.READY and d.contracts.stats["failed"] == 0, "waiting for collection cannot fail an order that was finished in time")
	# Deadlines do not tick while paused (the game loop is not running).
	var e := fresh()
	offer(e, "f3", 100, 100.0, {"deadline": 100.0})
	var k3 := accept(e, "f3", 50)
	var before := k3.time_left
	check(k3.time_left == before, "nothing ticks when the game is paused")
	# An order with no deadline never fails.
	var g := fresh()
	offer(g, "f4", 100, 100.0)
	var k4 := accept(g, "f4", 0)
	run(g, 3000.0)
	check(k4.status == Contract.Status.ACTIVE and g.contracts.stats["failed"] == 0, "no deadline, no failure")


func test_abandon() -> void:
	var c := fresh()
	var s := c.factory("copper")
	automate(s, 4)
	var ledger := Ledger.new()
	ledger.attach(c.contracts)
	c.contracts.reputation = 30
	offer(c, "x1", 500, 5000.0, {"penalty": 5})
	var k := accept(c, "x1", 50)
	check(c.contracts.abandon("x1") == "" and c.contracts.reputation == 30 and c.contracts.lockout == 0.0, "changing your mind straight away costs nothing")
	check(c.contracts.stats["failed"] == 0 and c.contracts.history[0]["outcome"] == "cancelled", "...and is not counted as a failure")
	offer(c, "x2", 500, 5000.0, {"penalty": 5})
	var k2 := accept(c, "x2", 50)
	run(c, 60.0)
	check(k2.delivered > 5, "built some stock (%d)" % k2.delivered)
	var delivered := k2.delivered
	var cash := c.state.cash
	check(c.contracts.abandon("x2") == "" and c.contracts.reputation == 25 and c.contracts.stats["failed"] == 1, "giving up a started order is a failure (reputation 30 -> %d)" % c.contracts.reputation)
	near(c.state.cash - cash, float(delivered) * 8.0, 1e-9, "the cylinders already built are sold, not lost")
	check(c.contracts.abandon("x2") != "" and c.contracts.abandon("zzz") != "", "cannot abandon twice or abandon something unknown")
	# A finished order cannot be abandoned.
	offer(c, "x3", 5, 100.0)
	var k3 := accept(c, "x3", 0)
	k3.delivered = 5
	c.contracts._complete(k3)
	check(c.contracts.abandon("x3") != "", "a finished order cannot be abandoned")


func test_factory_switching() -> void:
	# Looking at a different factory must not interrupt or alter anything.
	var a := fresh()
	var b := fresh()
	for c in [a, b]:
		c.factory("copper").state.unlocked = true
		c.factory("stainless").state.unlocked = true
		automate(c.factory("copper"), 5)
		automate(c.factory("stainless"), 2)
		offer(c, "w1", 2000, 40000.0)
		offer(c, "w2", 100, 300000.0, {"factory": "stainless"})
		accept(c, "w1", 50)
		accept(c, "w2", 60)
	for i in 30:
		run(a, 10.0)
		run(b, 10.0)
		b.set_current("stainless" if i % 2 == 0 else "copper")
		b.set_current("copper" if i % 3 == 0 else "stainless")
	check(JSON.stringify(a.contracts.to_dict()) == JSON.stringify(b.contracts.to_dict()), "contract state identical whether or not the player keeps switching factories")
	near(a.state.cash, b.state.cash, 1e-9, "cash identical")
	check(a.contracts.find("w1").delivered > 50 and b.contracts.find("w1").delivered == a.contracts.find("w1").delivered, "the copper order progressed while the stainless view was open")
	check(b.contracts.find("w2").delivered > 0, "the stainless order progressed too")
	near(a.factory("copper").state.cylinders_made, b.factory("copper").state.cylinders_made, 1e-9, "production identical")


## Offline helpers: a fully automated copper works at a known rate.
func offline_company(level: int = 4) -> GameSession:
	var c := fresh()
	automate(c.factory("copper"), level)
	return c


func test_offline_single() -> void:
	var c := offline_company(4)
	var s := c.factory("copper")
	var r := s.steady_rate()
	near(r, 0.5, 1e-9, "test factory builds 0.5 cylinders/second")
	var ledger := Ledger.new()
	ledger.attach(c.contracts)
	offer(c, "o1", 2000, 20000.0, {"deadline": 20000.0, "bonus": 500.0, "bonus_by": 8000.0})
	var k := accept(c, "o1", 40)
	var away := 3600.0
	var summary := c.apply_offline(away)
	# 40% of 1800 cylinders = 720 for the contract; the other 1080 are sold.
	check(absf(k.delivered - 720) < 1e-6 and k.status == Contract.Status.ACTIVE, "an hour away delivers 40%% of 1800 to the contract (%d)" % k.delivered)
	near(c.state.cash, 1080.0 * 8.0, 1e-6, "and sells the other 1080 (cash %s)" % c.state.cash)
	near(s.state.cylinders_made, 1800.0, 1e-9, "1800 cylinders built in total")
	near(s.state.cylinders_made, s.state.cylinders_sold + s.state.cylinders_contracted, 1e-9, "made = sold + contracted")
	near(k.elapsed, 3600.0, 1e-6, "the contract's clock ran for the hour")
	near(k.time_left, 20000.0 - 3600.0, 1e-6, "its deadline moved closer by the hour")
	check(summary.has("contracts") and summary["contracts"]["progress"].size() == 1, "the welcome-back summary reports contract progress")
	var line: Dictionary = summary["contracts"]["progress"][0]
	check(absf(line["added"] - 720.0) < 1e-6 and absf(line["delivered"] - 720.0) < 1e-6 and line["quantity"] == 2000 and line["customer"] == "Test o1", "progress line: " + str(line))
	near(float(summary["cash"]), 1080.0 * 8.0, 1e-6, "summary cash is sales only")
	near(float(summary["cylinders"]), 1800.0, 1e-9, "summary cylinders counts all production")
	# Completing during the absence: shares freed, sales continue at 100% afterwards, completion time is exact.
	var d := offline_company(4)
	var ledger2 := Ledger.new()
	ledger2.attach(d.contracts)
	offer(d, "o2", 300, 3000.0, {"bonus": 90.0, "bonus_by": 700.0})
	var k2 := accept(d, "o2", 50)
	var sm := d.apply_offline(3600.0)
	check(k2.status == Contract.Status.READY and absf(k2.delivered - 300) < 1e-6, "an order that fits in the time away is complete on return")
	near(k2.elapsed, 300.0 / (0.5 * 0.5), 1e-6, "it finished at exactly quantity / (rate x share) = 1200s (%s)" % k2.elapsed)
	check(not k2.bonus_earned, "1200s is later than the 700s bonus window")
	near(d.factory("copper").state.cylinders_sold, 1800.0 - 300.0, 1e-9, "the other cylinders were sold, including the whole factory's output after completion (%s)" % d.factory("copper").state.cylinders_sold)
	near(d.state.cash, 1500.0 * 8.0, 1e-6, "cash from sales")
	check(sm["contracts"]["ready"] == ["Test o2"], "the summary says it is ready for dispatch")
	check(d.contracts.free_share("copper") == 100 and k2.allocation == 0, "share freed")
	# A quick one earns its bonus.
	var e := offline_company(4)
	offer(e, "o3", 100, 1000.0, {"bonus": 90.0, "bonus_by": 700.0})
	var k3 := accept(e, "o3", 50)
	e.apply_offline(3600.0)
	near(k3.elapsed, 400.0, 1e-6, "finished at 400s")
	check(k3.bonus_earned, "inside the bonus window (400s < 700s)")


func test_offline_deadline() -> void:
	var c := offline_company(4)
	var s := c.factory("copper")
	var ledger := Ledger.new()
	ledger.attach(c.contracts)
	c.contracts.reputation = 40
	offer(c, "od", 2000, 20000.0, {"deadline": 600.0, "penalty": 8})
	var k := accept(c, "od", 40)
	k.time_left = 400.0                    # 400 seconds left when the game was closed
	var summary := c.apply_offline(3600.0)
	check(ledger.failures.size() == 1 and ledger.failures[0]["reason"] == "deadline", "the deadline passed while away: the contract failed")
	# It had run for exactly 400s at 40% of 0.5/s = 80 cylinders, which were then sold.
	check(absf(ledger.failures[0]["units"] - 80.0) < 1e-6, "it had built exactly 80 cylinders when time ran out (%d)" % ledger.failures[0]["units"])
	near(s.state.cylinders_made, 1800.0, 1e-9, "1800 cylinders built in the hour")
	near(s.state.cylinders_sold, 1800.0, 1e-9, "all of them were eventually sold (the 80 as released stock)")
	near(s.state.cylinders_contracted, 0.0, 1e-9, "nothing remains counted as contracted")
	near(c.state.cash, 1800.0 * 8.0, 1e-6, "cash = 1800 cylinders at 8 (nothing lost, nothing doubled)")
	check(c.contracts.reputation == 32, "reputation penalty applied")
	check(summary["contracts"]["failed"].size() == 1 and absf(summary["contracts"]["failed"][0]["units"] - 80.0) < 1e-6, "the summary reports the failure")
	# The failure happened at t=400s, so the premium pause had 3200s of the away time to run down.
	near(c.contracts.lockout, 0.0, 1e-9, "the 15-minute pause ran down during the hour away")
	# With a shorter absence the pause is still running, counted from the moment the deadline passed.
	var e := offline_company(4)
	offer(e, "od3", 2000, 20000.0, {"deadline": 600.0})
	var k3 := accept(e, "od3", 40)
	k3.time_left = 400.0
	e.apply_offline(1000.0)
	near(e.contracts.lockout, 900.0 - 600.0, 1e-6, "failure at 400s of a 1000s absence: 300s of the premium pause remain (%s)" % e.contracts.lockout)
	# Completion beats a deadline that falls on the very same moment.
	var d := offline_company(4)
	offer(d, "od2", 100, 1000.0, {"deadline": 400.0})
	var k2 := accept(d, "od2", 50)      # 100 / (0.5 x 0.5) = 400s
	d.apply_offline(3600.0)
	check(k2.status == Contract.Status.READY and d.contracts.stats["failed"] == 0, "finishing at the deadline moment counts as on time")


func test_offline_multiple() -> void:
	var c := offline_company(4)
	var s := c.factory("copper")
	var ledger := Ledger.new()
	ledger.attach(c.contracts)
	offer(c, "m1", 90, 900.0)                          # 30% -> 90 / 0.15 = 600s
	offer(c, "m2", 5000, 50000.0, {"deadline": 5000.0})  # 50% -> runs on
	var k1 := accept(c, "m1", 30)
	var k2 := accept(c, "m2", 50)
	c.apply_offline(3600.0)
	check(k1.status == Contract.Status.READY and absf(k1.delivered - 90) < 1e-6, "the small order finished")
	near(k1.elapsed, 600.0, 1e-6, "at exactly 600s")
	check(k2.status == Contract.Status.ACTIVE and absf(k2.delivered - 900) < 1e-6 and k2.allocation == 50, "the other kept its own 50%% share throughout: 900 of 1800 (%d)" % k2.delivered)
	near(k2.time_left, 5000.0 - 3600.0, 1e-6, "its clock ran for the full hour")
	# Sales: 30% for 600s then 50%->... total output 1800; contracted 90 + 900; sold 810.
	near(s.state.cylinders_sold, 810.0, 1e-9, "810 sold")
	near(c.state.cash, 810.0 * 8.0, 1e-6, "cash from those 810")
	# Offline and one fully-automated factory plus one that cannot run unattended.
	var d := fresh()
	d.factory("copper").state.unlocked = true
	d.factory("stainless").state.unlocked = true
	automate(d.factory("copper"), 4)       # copper runs unattended; stainless has no machines
	offer(d, "n1", 5000, 10000.0, {"deadline": 20000.0})
	offer(d, "n2", 10, 100000.0, {"factory": "stainless", "deadline": 600.0})
	var j1 := accept(d, "n1", 50)
	var j2 := accept(d, "n2", 50)
	d.apply_offline(7200.0)
	check(absf(j1.delivered - 1800) < 1e-6 and j1.status == Contract.Status.ACTIVE, "copper order built unattended: %d" % j1.delivered)
	check(absf(j2.delivered - 0) < 1e-6 and j2.status == Contract.Status.ACTIVE and j2.time_left == 600.0 and j2.elapsed == 0.0, "the stainless order's clock did not move: that factory cannot run unattended")
	check(d.contracts.stats["failed"] == 0, "so the stainless order did not fail while the player was away")


func test_offline_rules() -> void:
	var c := offline_company(4)
	offer(c, "r1", 2000, 20000.0, {"deadline": 20000.0})
	var k := accept(c, "r1", 50)
	check(c.apply_offline(30.0).is_empty() and absf(k.delivered - 0) < 1e-6 and k.elapsed == 0.0, "under a minute away: nothing happens")
	# The existing 8 hour cap applies to contracts too.
	var d := offline_company(4)
	offer(d, "r2", 100000, 1.0e6, {"deadline": 200000.0})
	var k2 := accept(d, "r2", 50)
	var sm := d.apply_offline(3.0 * 86400.0)
	check(sm["capped"] == true and absf(k2.delivered - 7200.0) < 1e-6, "three days away counts only the 8 hour limit: %d" % k2.delivered)
	near(k2.elapsed, 28800.0, 1e-6, "contract clock capped as well")
	# No contracts at all: the summary is exactly what it always was.
	var e := offline_company(4)
	var s3 := e.apply_offline(3600.0)
	check(s3["cylinders"] == 1800.0 and s3["cash"] == 14400.0 and s3["factories"].size() == 1, "no contracts -> the familiar summary")
	check(not s3.has("contracts") or (s3["contracts"]["progress"].is_empty() and s3["contracts"]["paid"].is_empty()), "...with no contract progress to report")
	# A contract with 0% share only watches its clock.
	var f := offline_company(4)
	offer(f, "r3", 100, 1000.0, {"deadline": 500.0})
	var k3 := accept(f, "r3", 0)
	f.apply_offline(3600.0)
	check(f.contracts.stats["failed"] == 1 and absf(k3.delivered - 0) < 1e-6, "a contract that is given no production fails on its deadline")
	# Offers age while away and new customers call.
	var g := offline_company(4)
	g.contracts.refresh_board()
	var before_ids: Array = g.contracts.offers.map(func(o: Contract) -> String: return o.id)
	g.contracts.offer_timer = 1.0e9
	var sg := g.apply_offline(4000.0)
	check(g.contracts.offers.size() == 3, "the board is full again after a long absence")
	var kept: int = g.contracts.offers.filter(func(o: Contract) -> bool: return before_ids.has(o.id)).size()
	check(kept < 3, "old offers lapsed while away (%d kept)" % kept)


func test_offline_dispatch() -> void:
	# A lorry that was loading when the game closed has left by the time you return - paid exactly once.
	var c := fresh()
	var ledger := Ledger.new()
	ledger.attach(c.contracts)
	offer(c, "d1", 5, 700.0, {"rep": 4})
	var k := accept(c, "d1", 0)
	k.delivered = 5
	c.contracts._complete(k)
	c.contracts.dispatch("d1")
	run(c, 1.0)                       # closed one second into the dispatch
	check(k.status == Contract.Status.DISPATCHING and ledger.payouts.is_empty(), "mid-dispatch when saved")
	var snapshot := JSON.stringify(c.save_data())
	var d := GameSession.new(_data)
	d.load_state(JSON.parse_string(snapshot))
	var ledger2 := Ledger.new()
	ledger2.attach(d.contracts)
	check(d.contracts.find("d1") != null and d.contracts.find("d1").status == Contract.Status.DISPATCHING, "the dispatch survives a save and load")
	var summary := d.apply_offline(600.0)
	check(ledger2.payouts.size() == 1 and d.contracts.find("d1") == null, "paid when the player returns")
	near(d.state.cash, 700.0, 1e-9, "exactly once, exactly the contract value")
	check(summary.has("contracts") and summary["contracts"]["paid"].size() == 1, "the summary reports the delivery")
	check(d.contracts.reputation == 4, "reputation awarded")
	var again := d.apply_offline(600.0)
	near(d.state.cash, 700.0, 1e-9, "a second return pays nothing more")
	# Reloading mid-dispatch without being away also continues from where it stopped.
	var e := GameSession.new(_data)
	e.load_state(JSON.parse_string(snapshot))
	var ledger3 := Ledger.new()
	ledger3.attach(e.contracts)
	run(e, 3.0)
	check(ledger3.payouts.size() == 0, "a short reload does not skip the dispatch animation")
	run(e, 3.0)
	check(ledger3.payouts.size() == 1, "and it completes after the remaining time")


func test_offline_vs_live() -> void:
	# The analytic offline result must agree with really running the simulation.
	var live := offline_company(5)
	var away := offline_company(5)
	for c in [live, away]:
		offer(c, "v1", 100000, 1.0e6)
		accept(c, "v1", 40)
	run(live, 600.0)
	away.apply_offline(600.0)
	var rate := live.factory("copper").steady_rate()
	var expect := 0.4 * rate * 600.0
	near(float(away.contracts.find("v1").delivered), expect, 1.0, "offline: 40%% of %s = %s" % [rate * 600.0, expect])
	near(float(live.contracts.find("v1").delivered), expect, expect * 0.05 + 3.0, "live play agrees within the line's warm-up time")
	near(away.factory("copper").state.cylinders_made, live.factory("copper").state.cylinders_made, live.factory("copper").state.cylinders_made * 0.05 + 3.0, "production agrees too")


func test_save_roundtrip() -> void:
	var c := fresh()
	automate(c.factory("copper"), 4)
	c.state.factory_name = "Roundtrip Ltd"
	c.contracts.reputation = 130
	c.contracts.lockout = 321.0
	c.contracts.serial = 17
	c.contracts.history.push_front({"outcome": "delivered", "customer": "Old Customer", "product": "Copper Cylinder", "tier": "trade", "quantity": 20, "delivered": 20, "payout": 250.0, "bonus": 0.0, "rep": 4})
	c.contracts.offer_timer = 3000.0
	offer(c, "s1", 500, 5000.0, {"deadline": 3000.0, "bonus": 200.0, "bonus_by": 1500.0})
	offer(c, "s2", 40, 400.0)
	offer(c, "s3", 10, 100.0)
	offer(c, "s4", 70, 700.0, {"tier": "commercial"})
	offer(c, "s5", 70, 700.0)
	accept(c, "s1", 30)
	accept(c, "s2", 0)
	accept(c, "s3", 0)
	run(c, 100.0)
	var done := c.contracts.find("s3")          # finish and start dispatching it just before saving
	done.delivered = 10
	c.contracts._complete(done)
	c.contracts.dispatch("s3")
	run(c, 1.0)
	var k1 := c.contracts.find("s1")
	check(k1.delivered > 0.0, "contract has progress to save (%d)" % k1.delivered)
	var d := c.save_data()
	check(SaveManager.save_game(d, TEST_SAVE, 1000.0), "saved")
	var back := SaveManager.load_game(TEST_SAVE)
	var file_ver := int(JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))["version"])
	check(file_ver == 4, "the file is save version 4")
	var e := GameSession.new(_data)
	e.load_state(back)
	var field_diff := _diff(c.contracts.to_dict(), e.contracts.to_dict(), "")
	check(field_diff.is_empty(), "every contract field survives a save and load: " + str(field_diff))
	check(e.contracts.reputation == 130 and e.contracts.serial == 17 and absf(e.contracts.lockout - c.contracts.lockout) < 1e-9 and c.contracts.lockout < 321.0, "reputation, premium pause (still running down) and serial restored (%s, %s)" % [e.contracts.reputation, e.contracts.lockout])
	check(e.contracts.offers.size() == 2 and e.contracts.active.size() == 3, "offers and accepted contracts restored")
	check(e.contracts.find("s1").status == Contract.Status.ACTIVE and e.contracts.find("s1").allocation == 30, "production allocation restored")
	near(e.contracts.find("s1").time_left, k1.time_left, 1e-9, "deadline restored")
	check(e.contracts.find("s2").status == Contract.Status.ACTIVE and e.contracts.find("s3").status == Contract.Status.DISPATCHING, "states restored")
	check(e.contracts.history.size() == 1 and e.contracts.history[0]["customer"] == "Old Customer", "history restored")
	check(e.state.factory_name == "Roundtrip Ltd" and absf(e.factory("copper").state.cylinders_contracted - c.factory("copper").state.cylinders_contracted) < 1e-6, "company and counters restored")
	check(e.contracts.seed_value == c.contracts.seed_value, "the generator seed is saved, so future offers are reproducible")
	# The restored game plays on identically to the original.
	run(c, 200.0)
	run(e, 200.0)
	check(absf(e.contracts.find("s1").delivered - c.contracts.find("s1").delivered) < 1e-6, "loading does not change what happens next (delivered %d)" % c.contracts.find("s1").delivered)
	near(e.state.cash, c.state.cash, 1e-6, "cash identical")
	# Save transfer codes carry contracts too.
	var code := SaveManager.export_code(TEST_SAVE)
	var decoded := SaveManager.decode_code(code)
	check(not decoded.is_empty() and decoded["contracts"]["reputation"] == 130, "contracts travel in a save code")


func test_save_migration() -> void:
	# A v3 save from the last release: no contracts anywhere.
	var v3 := {"game": "cylinder_clicker", "version": 3, "state": {
		"factory_name": "Old Faithful", "cash": 5000.0, "lifetime_earned": 90000.0, "total_clicks": 400, "play_seconds": 3000.0,
		"unlocked_products": ["copper", "standard"], "current_factory": "copper", "tutorial_step": 7, "last_saved_unix": 0.0,
		"factories": {"copper": {"unlocked": true, "upgrade_levels": {"machine_cut": 9, "machine_roll": 9, "machine_weld": 9, "machine_test": 9, "machine_foam": 9, "machine_pack": 9, "finish": 3},
			"cylinders_made": 1234.0, "earned": 90000.0, "best_rate_per_min": 80.0, "line": {}}}}}
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(v3))
	f.close()
	var st := SaveManager.load_game(TEST_SAVE)
	check(not st.is_empty() and st.has("contracts") and st["contracts"].is_empty(), "a v3 save migrates with an empty contract section")
	var c := GameSession.new(_data)
	c.load_state(st)
	check(c.state.factory_name == "Old Faithful" and c.state.cash == 5000.0, "nothing existing is reset")
	check(c.factory("copper").level("machine_weld") == 9 and c.factory("copper").level("finish") == 3, "factory upgrades kept")
	check(c.factory("copper").state.cylinders_made == 1234.0 and c.factory("copper").state.cylinders_sold == 1234.0 and c.factory("copper").state.cylinders_contracted == 0.0, "old cylinder count becomes 'all sold'")
	check(c.contracts.reputation == 0 and c.contracts.offers.is_empty() and c.contracts.active.is_empty() and c.contracts.history.is_empty(), "contracts start empty")
	check(not c.contracts.unlocked, "board not yet open")
	run(c, 2.0)
	check(c.contracts.unlocked and c.contracts.offers.size() == 3, "an established company gets its first offers straight away (%d)" % c.contracts.offers.size())
	for o in c.contracts.offers:
		check(o.factory == "copper" and o.tier == "trade", "...sized for the copper works")
	# The first save after migration is v4 and loads again.
	check(SaveManager.save_game(c.save_data(), TEST_SAVE, 5.0), "saved after migration")
	check(int(JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))["version"]) == 4, "now version 4")
	var d := GameSession.new(_data)
	d.load_state(SaveManager.load_game(TEST_SAVE))
	check(d.contracts.offers.size() == 3 and d.contracts.unlocked, "and reloads with its board")
	# Even older saves still go all the way up.
	var v1 := {"game": "cylinder_clicker", "version": 1, "state": {"cash": 77.0, "lifetime_earned": 100.0, "upgrade_levels": {"hand_tools": 2}, "cylinders_made": 12.0}}
	f = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(v1))
	f.close()
	var e := GameSession.new(_data)
	e.load_state(SaveManager.load_game(TEST_SAVE))
	check(e.state.cash == 77.0 and e.factory("copper").level("hand_tools") == 2 and e.contracts.reputation == 0, "v1 saves still load, with contracts initialised")


func test_save_corruption() -> void:
	# Damaged contract data never stops the game loading.
	var good := offer(fresh(), "ok", 100, 1000.0).to_dict()
	good["status"] = "active"
	good["allocation"] = 70
	var good2 := good.duplicate()
	good2["id"] = "ok2"
	good2["allocation"] = 70                 # 70 + 70 > 100 at one factory
	var raw := {"v": 1, "reputation": "lots", "seed": 5, "serial": -4, "unlocked": true, "offer_timer": -50.0, "lockout": "x",
		"offers": [3, "no", {"id": "bad"}, {"id": "", "customer": "x", "factory": "copper", "quantity": 5}, good.duplicate()],
		"active": [null, good, good2, {"id": "q", "customer": "Q", "factory": "copper", "quantity": 10, "status": "ready", "delivered": 99, "allocation": 80}],
		"history": ["x", 5, {"outcome": "delivered"}], "stats": {"completed": "7", "paid": 12.5}}
	var c := GameSession.new(_data)
	var st: Dictionary = c.save_data()
	st["contracts"] = raw
	c.load_state(st)
	check(c.contracts.reputation == 0 and c.contracts.serial == 0, "garbage numbers fall back to defaults")
	check(c.contracts.offers.size() == 1 and c.contracts.offers[0].status == Contract.Status.OFFER, "only the valid offer survives; its status is normalised")
	check(c.contracts.active.size() == 3, "valid accepted contracts survive (%d)" % c.contracts.active.size())
	var total := 0
	for k in c.contracts.active:
		if k.status == Contract.Status.ACTIVE:
			total += k.allocation
	check(total <= 100, "allocations are clamped to 100%% per factory (%d)" % total)
	var q := c.contracts.find("q")
	check(absf(q.delivered - 10) < 1e-6 and q.allocation == 0 and q.status == Contract.Status.READY, "over-delivery is clamped and a ready order holds no share")
	check(c.contracts.history.size() == 1 and int(c.contracts.stats["completed"]) == 7 and absf(float(c.contracts.stats["paid"]) - 12.5) < 1e-9, "history/stats keep what is valid")
	# Wrong type entirely.
	st["contracts"] = "not a dictionary"
	c.load_state(st)
	check(c.contracts.reputation == 0 and c.contracts.offers.is_empty(), "a non-dictionary contract section is ignored")
	# Contract for a factory that no longer exists: ticks safely.
	var d := fresh()
	offer(d, "gone", 10, 100.0, {"factory": "thermal_store"})
	check(d.contracts.accept("gone") == "", "accepting a contract for an unknown factory does not crash")
	run(d, 5.0)
	d.apply_offline(3600.0)
	check(d.contracts.find("gone") != null, "and it simply waits")


func test_future_products() -> void:
	# New products and factories need no contract code: any factory id and product the market reports gets contracts.
	var rules := _rules
	var facs := [
		{"id": "copper", "product_name": "Copper Cylinder", "profit": 50.0, "rate": 2.0},
		{"id": "stainless", "product_name": "Stainless Steel Cylinder", "profit": 2000.0, "rate": 0.1},
		{"id": "thermal_store", "product_name": "Thermal Store", "profit": 9000.0, "rate": 0.05},
		{"id": "preplumbed", "product_name": "Pre-Plumbed Cylinder", "profit": 20000.0, "rate": 0.02},
	]
	var seen := {}
	for serial in range(1, 400):
		var c := ContractGenerator.generate(rules, ctx_for(3, facs), 1, serial)
		seen[c.factory] = c.product_name
		check(c.quantity > 0 and c.value > 0.0, "valid contract for %s" % c.factory)
	check(seen.size() == 4, "every factory the company owns can receive orders: " + str(seen.keys()))
	# Routing, accepting and dispatching are keyed by factory id, not by anything built in.
	var book := ContractBook.new(rules)
	book.unlocked = true
	var o := Contract.new()
	o.id = "t1"; o.customer = "Future Customer"; o.factory = "thermal_store"; o.quantity = 10; o.value = 99.0; o.pallets = 1
	book.offers.append(o)
	check(book.accept("t1") == "", "accepted")
	book.set_allocation("t1", 100)
	check(book.route("thermal_store", 1.0) == 1.0 and book.route("copper", 1.0) == 0.0, "routed by factory id")
	var paid := []
	book.completed.connect(func(c: Contract, base: float, bonus: float, _r: int) -> void: paid.append(base + bonus))
	for i in 20:
		book.route("thermal_store", 1.0)
	check(book.dispatch("t1") == "", "dispatched")
	book.tick(60.0)
	check(paid == [99.0], "paid without a market feed: the written price")


func test_batched_output() -> void:
	# At high output a token carries many cylinders; contracts must still get exact shares.
	var c := fresh()
	var s := c.factory("copper")
	automate(s, 60)
	check(s.line.batch > 5.0, "high output is batched (%.1f cylinders per item)" % s.line.batch)
	var ledger := Ledger.new()
	ledger.attach(c.contracts)
	offer(c, "h1", 10000000, 1.0e8)
	var k := accept(c, "h1", 25)
	run(c, 120.0)
	var made := s.state.cylinders_made
	check(made > 5000.0, "built %s cylinders" % made)
	near(float(k.delivered), made * 0.25, made * 0.01 + 5.0, "a 25%% share of batched output is 25%% (%d of %s)" % [k.delivered, made])
	near(made, s.state.cylinders_sold + s.state.cylinders_contracted, 1e-6, "made = sold + contracted with batches")
	near(c.state.cash, s.state.cylinders_sold * s.profit_per_cylinder(), 0.01, "revenue only for sold cylinders")
	# a huge shipment in one go is still O(1)
	var d := fresh()
	offer(d, "h2", 1000000000000, 1.0e15)
	accept(d, "h2", 40)
	var t0 := Time.get_ticks_usec()
	var taken := d.contracts.route("copper", 1.0e9)
	check(taken == 4.0e8, "40%% of a billion is 400 million (%s)" % taken)
	check(Time.get_ticks_usec() - t0 < 5000, "routing does not loop per cylinder")
