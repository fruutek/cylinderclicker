extends SceneTree
## Headless tests for the warehouse economy (Expansion 4): stock, capacity, SKUs, targets, the planner,
## wholesale overflow, save/migration and unattended time.
## Run:  godot --headless --path . -s tests/run_stock_tests.gd

const TICK := 1.0 / 60.0
const TEST_SAVE := "user://test_stock_save.json"

var _passed := 0
var _failed := 0
var _data: GameData


func _init() -> void:
	_data = GameData.new()
	check(_data.load_all(), "data files load")
	for t: String in [
		"test_catalog", "test_variant_economics", "test_warehouse_rules", "test_manufacture_to_stock", "test_overflow_wholesale",
		"test_planner_targets", "test_specialist_machinery", "test_capacity_upgrade", "test_conservation_long_run",
		"test_save_roundtrip", "test_migration", "test_offline_stock", "test_direct_mode_unchanged",
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


func stock_session() -> GameSession:
	var c := GameSession.new(_data, true)
	c.contracts.reset(1)
	for sim in c.factories:
		sim.state.auto_targets = false        # these tests set targets by hand
	return c


func automate(s: FactorySim, lvl: int = 1) -> void:
	for m: Dictionary in s.data.machines:
		s.state.upgrade_levels[m["id"]] = lvl
	s.refresh()


func run(c: GameSession, seconds: float) -> void:
	for i in int(round(seconds / TICK)):
		c.tick(TICK)


## Every unit ever built is somewhere: on the shelves, on the line, shipped, wholesaled, or a fraction.
func conserved(s: FactorySim) -> String:
	var w := s.warehouse
	for i in s.skus.size():
		var id := s.sku_id(i)
		var accounted := float(w.total(id)) + float(w.shipped.get(id, 0)) + float(w.wholesaled.get(id, 0)) + float(w.frac.get(id, 0.0))
		var made := float(w.made.get(id, 0.0))
		if absf(made - accounted) > 0.001:
			return "%s: made %s but stock+shipped+wholesaled+frac = %s" % [id, made, accounted]
	return ""


# ------------------------------------------------------------------ tests
func test_catalog() -> void:
	var c := stock_session()
	check(c.stock_default and c.state.stock_mode, "a stock session keeps a warehouse")
	var copper := c.factory("copper")
	var steel := c.factory("stainless")
	check(copper.skus.size() == 4 and steel.skus.size() == 3, "copper has 4 products, stainless 3 (%d / %d)" % [copper.skus.size(), steel.skus.size()])
	var ids := {}
	for s: Dictionary in c.sku_catalog.all:
		check(not ids.has(s["id"]), "SKU id %s is unique" % s["id"])
		ids[s["id"]] = true
		check(c.data.factory_by_id.has(s["factory"]), "%s belongs to a real factory" % s["id"])
	var base := c.sku_catalog.baseline("copper")
	check(base["id"] == "CU-IND" and float(base["value_mult"]) == 1.0 and float(base["material_mult"]) == 1.0 and float(base["work_mult"]) == 1.0, "Copper Indirect is exactly the original product")
	check(copper.sku_available(0) and copper.sku_available(1) and not copper.sku_available(2) and not copper.sku_available(3), "horizontal and slimline need machinery")
	check(not steel.sku_available(2), "stainless horizontal needs its handling cell")
	near(copper.sku_profit(0), copper.profit_per_cylinder(), 0.0001, "the baseline SKU nets exactly the v0.5.1 profit")
	near(steel.sku_profit(0), steel.profit_per_cylinder(), 0.0001, "...at stainless too")


func test_variant_economics() -> void:
	var c := stock_session()
	for sim in c.factories:
		# Better-paid variants never beat the baseline per minute of line time (so the best plan is demand-led, not "make the dearest").
		var base_per_min := sim.sku_profit(0) / sim.sku_work(0)
		for i in sim.skus.size():
			check(sim.sku_profit(i) > 0.0, "%s earns something" % sim.sku_id(i))
			check(sim.sku_profit(i) / sim.sku_work(i) <= base_per_min + 1e-9, "%s per line-minute (%.2f) does not beat the baseline (%.2f)" % [sim.sku_id(i), sim.sku_profit(i) / sim.sku_work(i), base_per_min])
		# ...but premium variants do sell for more each.
		for i in range(2, sim.skus.size()):
			check(sim.sku_price(i) > sim.sku_price(0), "%s has a higher list price" % sim.sku_id(i))
	# Prices follow the same upgrades as the base product.
	var copper := c.factory("copper")
	var p0 := copper.sku_price(2)
	copper.state.upgrade_levels["finish"] = 3
	copper.refresh()
	check(copper.sku_price(2) > p0, "selling-value upgrades lift every variant")


func test_warehouse_rules() -> void:
	var w := Warehouse.new()
	w.capacity = 10
	w.space = {"A": 1.0, "B": 1.0}
	check(w.receive("A", 4.0) == 0 and w.total("A") == 4 and w.available("A") == 4, "receive adds stock")
	check(w.reserve("A", 3) == 3 and w.available("A") == 1 and w.reserved_units("A") == 3, "reserve moves stock from available to reserved")
	check(w.reserve("A", 5) == 1, "cannot reserve more than is available")
	check(w.available("A") == 0 and w.reserved_units("A") == 4, "everything reserved")
	check(w.ship("A", 10) == 4 and w.total("A") == 0 and w.reserved_units("A") == 0, "ship can only send what is reserved")
	check(w.release("A", 3) == 0, "release of nothing is nothing")
	var over := w.receive("B", 14.0)
	check(over == 4 and w.total("B") == 10, "stock stops at capacity; the surplus (4) is handed back, never lost")
	w.note_overflow_sale("B", over)         # the caller sells what did not fit
	check(w.validate() == "", "no rule is broken (%s)" % w.validate())
	check(w.sell_wholesale("B", 100) == 10 and w.total("B") == 0, "wholesale only takes what is there")
	w.receive("B", 6.0)
	w.reserve("B", 4)
	check(w.sell_wholesale("B", 100) == 2 and w.reserved_units("B") == 4, "wholesale never touches reserved stock")
	check(w.receive("B", 0.5) == 0 and w.total("B") == 4, "fractions are carried, not rounded into stock")
	w.receive("B", 0.5)
	check(w.total("B") == 5, "...and become a whole cylinder once complete")
	var back := Warehouse.new()
	back.from_dict(w.to_dict())
	check(back.total("B") == w.total("B") and back.reserved_units("B") == w.reserved_units("B") and back.validate(true) == "", "to_dict / from_dict round-trips")
	var bad := {"stock": {"A": -5, "B": 3}, "reserved": {"B": 9}}
	var fixed := Warehouse.new()
	fixed.from_dict(bad)
	check(fixed.total("A") == 0 and fixed.reserved_units("B") <= fixed.total("B"), "a corrupt save cannot make negative or over-reserved stock")


func test_manufacture_to_stock() -> void:
	var c := stock_session()
	var copper := c.factory("copper")
	automate(copper, 5)
	copper.state.wholesale_on = false
	copper.state.targets = {"CU-IND": 12, "CU-DIR": 0, "CU-HOR": 0, "CU-SLM": 0}
	c.state.cash = 0.0
	run(c, 60.0)
	check(copper.warehouse.total("CU-IND") > 0, "finished cylinders go into the warehouse (%d)" % copper.warehouse.total("CU-IND"))
	near(c.state.cash, 0.0, 0.0001, "making a cylinder earns nothing until it is sold")
	check(copper.state.cylinders_made > 0.0 and copper.state.cylinders_sold == 0.0, "made counts, sold does not")
	check(copper.warehouse.total("CU-IND") <= 12, "automatic production stops at the target (%d)" % copper.warehouse.total("CU-IND"))
	check(copper.warehouse.total("CU-DIR") == 0, "products with no target are not made")
	check(conserved(copper) == "", "inventory conserved: " + conserved(copper))
	check(copper.warehouse.validate() == "", "warehouse valid: " + copper.warehouse.validate())
	# Selling the surplus pays net profit, exactly once per cylinder.
	copper.state.wholesale_on = true
	copper.state.targets["CU-IND"] = 2
	var have := copper.warehouse.total("CU-IND")
	var net := copper.sell_surplus_now()
	near(net, float(have - 2) * copper.sku_profit(0) * c.sku_catalog.num("wholesale_share", 0.8), 0.001, "wholesale pays share x profit for each surplus cylinder")
	near(c.state.cash, net, 0.001, "...and that is all the cash there is")
	check(copper.warehouse.total("CU-IND") == 2 and conserved(copper) == "", "stock after selling surplus is the target, inventory still conserved")


func test_overflow_wholesale() -> void:
	var c := stock_session()
	var copper := c.factory("copper")
	copper.warehouse.capacity = 3
	c.state.cash = 0.0
	copper._receive_stock(10.0, 0)
	check(copper.warehouse.total("CU-IND") == 3, "only what fits is stored (%d)" % copper.warehouse.total("CU-IND"))
	near(c.state.cash, 7.0 * copper.sku_profit(0) * c.sku_catalog.num("wholesale_share", 0.85), 0.001, "the 7 that did not fit went to the wholesaler at the lower margin")
	check(float(copper.warehouse.overflowed.get("CU-IND", 0)) == 7.0, "the overflow is on record")
	check(conserved(copper) == "", "nothing was deleted: " + conserved(copper))
	check(copper.state.cylinders_made == 10.0 and copper.state.cylinders_sold == 7.0, "made 10, sold 7")


func test_planner_targets() -> void:
	var c := stock_session()
	var copper := c.factory("copper")
	automate(copper, 6)
	copper.state.wholesale_on = false
	copper.state.targets = {"CU-IND": 0, "CU-DIR": 6, "CU-HOR": 0, "CU-SLM": 0}
	run(c, 90.0)
	check(copper.warehouse.total("CU-DIR") == 6 and copper.warehouse.total("CU-IND") == 0, "only the product with a target is built, up to it (DIR %d, IND %d)" % [copper.warehouse.total("CU-DIR"), copper.warehouse.total("CU-IND")])
	copper.set_target("CU-IND", 4)
	run(c, 60.0)
	check(copper.warehouse.total("CU-IND") == 4, "raising a target makes the line build it (%d)" % copper.warehouse.total("CU-IND"))
	check(conserved(copper) == "", "conserved: " + conserved(copper))
	# Priority decides what is built first when several are short.
	var d := stock_session()
	var cu := d.factory("copper")
	automate(cu, 6)
	cu.state.wholesale_on = false
	cu.state.targets = {"CU-IND": 5, "CU-DIR": 5, "CU-HOR": 0, "CU-SLM": 0}
	cu.prioritise("CU-DIR")
	check(cu.state.priority[0] == "CU-DIR", "prioritise moves a product to the front")
	check(cu.planner_pick(false) == 1, "with both empty and equal, the prioritised product is made first")
	# Auto production off: only a player's click makes stock.
	cu.state.auto_production = false
	cu.planner_wake()
	check(cu.planner_pick(false) == -1, "auto-production off: the machines make nothing by themselves")
	check(cu.planner_pick(true) >= 0, "...but a click still starts a cylinder")
	# Clicking can build beyond target (stockpiling), up to the shelf space.
	cu.state.targets = {"CU-IND": 1, "CU-DIR": 0, "CU-HOR": 0, "CU-SLM": 0}
	cu.warehouse.receive("CU-IND", 5.0)
	check(cu.planner_pick(true) >= 0, "a person can stockpile past the target")


func test_specialist_machinery() -> void:
	var c := stock_session()
	var copper := c.factory("copper")
	automate(copper, 6)
	copper.state.wholesale_on = false
	copper.state.targets = {"CU-IND": 0, "CU-DIR": 0, "CU-HOR": 5, "CU-SLM": 0}
	run(c, 60.0)
	check(copper.warehouse.total("CU-HOR") == 0, "no horizontal cylinders without the tooling")
	check(copper.sku_requirement_text(2).contains("Horizontal Tooling"), "the product says what it needs: " + copper.sku_requirement_text(2))
	copper.state.upgrade_levels["horizontal_tooling"] = 1
	copper.refresh()
	check(copper.sku_available(2) and copper.sku_requirement_text(2) == "", "buying the tooling unlocks it")
	run(c, 120.0)
	check(copper.warehouse.total("CU-HOR") == 5, "...and the line builds them (%d)" % copper.warehouse.total("CU-HOR"))
	# A slower product really is slower.
	var f := stock_session()
	var s := f.factory("copper")
	automate(s, 6)
	s.state.wholesale_on = false
	s.state.upgrade_levels["horizontal_tooling"] = 1
	s.state.upgrade_levels["warehouse"] = 6
	s.refresh()
	s.state.targets = {"CU-IND": 0, "CU-DIR": 0, "CU-HOR": 400, "CU-SLM": 0}
	run(f, 40.0)
	var hor := s.warehouse.total("CU-HOR")
	var g := stock_session()
	var s2 := g.factory("copper")
	automate(s2, 6)
	s2.state.wholesale_on = false
	s2.state.upgrade_levels["warehouse"] = 6
	s2.refresh()
	s2.state.targets = {"CU-IND": 400, "CU-DIR": 0, "CU-HOR": 0, "CU-SLM": 0}
	run(g, 40.0)
	var ind := s2.warehouse.total("CU-IND")
	check(hor > 0 and ind > hor, "horizontal is slower to build than indirect (%d vs %d in 40 s)" % [hor, ind])


func test_capacity_upgrade() -> void:
	var c := stock_session()
	var copper := c.factory("copper")
	check(copper.warehouse.capacity == 24, "copper starts with 24 places (%d)" % copper.warehouse.capacity)
	var last := copper.warehouse.capacity
	var last_cost := copper.cost("warehouse")
	for i in 5:
		copper.state.upgrade_levels["warehouse"] = copper.level("warehouse") + 1
		copper.refresh()
		check(copper.warehouse.capacity > last, "each warehouse upgrade adds capacity (%d -> %d)" % [last, copper.warehouse.capacity])
		check(copper.cost("warehouse") > last_cost, "...and costs more each time")
		last = copper.warehouse.capacity
		last_cost = copper.cost("warehouse")
	check(copper.is_visible("warehouse"), "the warehouse upgrade is offered in stock mode")
	var direct := GameSession.new(_data)
	check(not direct.factory("copper").is_visible("warehouse") and not direct.factory("copper").is_visible("sales_rep"), "direct-sales sessions do not show warehouse upgrades")
	check(c.factory("stainless").warehouse.capacity == 12, "stainless starts with 12 places (%d)" % c.factory("stainless").warehouse.capacity)


func test_conservation_long_run() -> void:
	var c := stock_session()
	c.state.cash = 5.0e6
	var copper := c.factory("copper")
	automate(copper, 4)
	copper.state.upgrade_levels["horizontal_tooling"] = 1
	copper.state.upgrade_levels["slimline_rig"] = 1
	copper.refresh()
	for i in 12:
		for t in 60:
			c.tick(TICK * 60.0 / 60.0)
		if i % 4 == 0:
			copper.state.targets["CU-HOR"] = (i * 3) % 7
			copper.sell_surplus_now()
		for t in 30:
			copper.click()
		check(conserved(copper) == "", "conserved at step %d: %s" % [i, conserved(copper)])
		check(copper.warehouse.validate() == "", "valid at step %d: %s" % [i, copper.warehouse.validate()])
	var units := float(copper.warehouse.total_units())
	var wip := 0.0
	for id in copper.warehouse.wip:
		wip += float(copper.warehouse.wip[id])
	var made := copper.state.cylinders_made
	var wh := 0.0
	for id in copper.warehouse.wholesaled:
		wh += float(copper.warehouse.wholesaled[id])
	near(made, units + wh + float(copper.state.cylinders_sold - wh) + wip + _frac(copper), maxf(wip + 1.0, 1.0), "company counters agree with the warehouse")


func _frac(s: FactorySim) -> float:
	var f := 0.0
	for id in s.warehouse.frac:
		f += float(s.warehouse.frac[id])
	return f


func test_save_roundtrip() -> void:
	var c := stock_session()
	var copper := c.factory("copper")
	automate(copper, 6)
	copper.state.targets = {"CU-IND": 9, "CU-DIR": 4, "CU-HOR": 0, "CU-SLM": 0}
	copper.prioritise("CU-DIR")
	copper.state.wholesale_on = false
	run(c, 100.0)
	check(copper.warehouse.total_units() > 0, "there is stock to save")
	SaveManager.save_game(c.save_data(), TEST_SAVE, 100.0)
	var d := stock_session()
	d.load_state(SaveManager.load_game(TEST_SAVE))
	var dc := d.factory("copper")
	check(d.state.stock_mode, "stock mode survives a save")
	for id: String in ["CU-IND", "CU-DIR", "CU-HOR", "CU-SLM"]:
		check(dc.warehouse.total(id) == copper.warehouse.total(id) and dc.warehouse.reserved_units(id) == copper.warehouse.reserved_units(id), "%s stock identical after load" % id)
	check(dc.state.targets == copper.state.targets and dc.state.priority == copper.state.priority, "targets and priorities survive")
	check(not dc.state.wholesale_on, "settings survive")
	check(conserved(dc) == "" and dc.warehouse.validate() == "", "loaded warehouse is consistent: " + conserved(dc) + dc.warehouse.validate())
	var line_units := 0.0
	for t in copper.line.all_tokens():
		line_units += t.count
	var loaded_units := 0.0
	for t in dc.line.all_tokens():
		loaded_units += t.count
	near(loaded_units, line_units, 0.001, "cylinders on the belts are restored")
	near(float(dc.warehouse.wip.get("CU-IND", 0.0)) + float(dc.warehouse.wip.get("CU-DIR", 0.0)), loaded_units, 0.001, "...and counted against the shelf space they will need")
	# Same state, same future: a loaded game carries on exactly like the original.
	run(c, 40.0)
	run(d, 40.0)
	check(dc.warehouse.total("CU-IND") == copper.warehouse.total("CU-IND") and dc.warehouse.total("CU-DIR") == copper.warehouse.total("CU-DIR"), "a reloaded game continues identically")


func test_migration() -> void:
	# A v0.5.1 save (version 4): no warehouse, no stock_mode.
	var old := GameSession.new(_data)
	automate(old.factory("copper"), 20)
	old.factory("copper").state.upgrade_levels["finish"] = 6
	old.factory("copper").state.earned = 900000.0
	old.state.cash = 123456.0
	old.state.lifetime_earned = 900000.0
	old.factory("copper").refresh()
	var d := old.save_data()
	for key in ["stock_mode", "stock_migrate", "sales"]:
		d.erase(key)
	for fs: Dictionary in d["factories"].values():
		for key in ["warehouse", "targets", "priority", "auto_production", "auto_targets", "wholesale_on", "wholesale_timer"]:
			fs.erase(key)
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"game": "cylinder_clicker", "version": 4, "state": d}))
	f.close()
	var st := SaveManager.load_game(TEST_SAVE)
	check(bool(st.get("stock_mode", false)) and bool(st.get("stock_migrate", false)), "a v4 save is migrated into stock keeping")
	var c := stock_session()
	c.load_state(st)
	var copper := c.factory("copper")
	check(c.state.stock_mode and not c.state.stock_migrate, "migration is applied once")
	near(c.state.cash, 123456.0, 0.001, "cash is preserved")
	check(copper.level("machine_weld") == 20 and copper.level("finish") == 6, "upgrades are preserved")
	near(copper.state.earned, 900000.0, 0.001, "earnings are preserved")
	var cover := c.sku_catalog.num("migration_cover_minutes", 8.0) * 60.0 * copper.steady_rate()
	check(float(copper.warehouse.capacity) >= cover, "the warehouse is big enough for the factory's output (%d places for %.0f)" % [copper.warehouse.capacity, cover])
	check(copper.state.auto_targets and copper.state.auto_production, "targets look after themselves for a migrated factory")
	check(copper.is_visible("warehouse"), "and the warehouse can be expanded")
	# It keeps producing without being asked (customers buy what it makes: see the order tests).
	run(c, 300.0)
	check(copper.warehouse.total_units() > 0 and copper.state.cylinders_made > 0.0, "a migrated factory keeps producing (%d in stock)" % copper.warehouse.total_units())
	check(conserved(copper) == "", "conserved after migration: " + conserved(copper))
	# Loading the same save twice does not grant twice.
	var e := stock_session()
	e.load_state(SaveManager.load_game(TEST_SAVE))
	var cap_first := e.factory("copper").warehouse.capacity
	e.load_state(e.save_data())
	check(e.factory("copper").warehouse.capacity == cap_first, "grants are not applied again on a later load")


func test_offline_stock() -> void:
	var c := stock_session()
	var copper := c.factory("copper")
	automate(copper, 8)
	copper.state.targets = {"CU-IND": 10, "CU-DIR": 5, "CU-HOR": 0, "CU-SLM": 0}
	var r := c.apply_offline(3600.0)
	check(not r.is_empty() and float(r["cylinders"]) > 0.0, "an automated factory builds while you are away")
	check(copper.warehouse.total("CU-IND") <= copper.warehouse.capacity, "offline production respects the warehouse")
	check(copper.warehouse.available("CU-IND") <= 10 + 3 and copper.warehouse.available("CU-DIR") <= 5 + 3, "...and the targets, apart from what customers took (IND %d free, DIR %d free)" % [copper.warehouse.available("CU-IND"), copper.warehouse.available("CU-DIR")])
	near(float(r["cash"]), c.state.cash, 0.01, "offline cash is the cash that was earned (no double counting)")
	check(conserved(copper) == "" and copper.warehouse.validate() == "", "stock accounting survives offline time: " + conserved(copper))
	copper.state.targets = {"CU-IND": 0, "CU-DIR": 0, "CU-HOR": 0, "CU-SLM": 0}
	var held := copper.warehouse.total_units()
	c.state.cash = 0.0
	c.apply_offline(600.0)
	check(held > 0 and copper.warehouse.total_units() < held and c.state.cash > 0.0, "surplus above target went to the wholesaler while away (%d -> %d, cash %.0f)" % [held, copper.warehouse.total_units(), c.state.cash])
	# A line with no room and no wholesaler idles; nothing is invented.
	var d := stock_session()
	var cu := d.factory("copper")
	automate(cu, 8)
	cu.state.wholesale_on = false
	cu.state.targets = {"CU-IND": 4, "CU-DIR": 0, "CU-HOR": 0, "CU-SLM": 0}
	d.apply_offline(7200.0)
	check(cu.warehouse.total("CU-IND") == 4 and d.state.cash == 0.0, "targets met, nothing sold: %d in stock, cash %s" % [cu.warehouse.total("CU-IND"), d.state.cash])
	check(cu.state.cylinders_made == 4.0, "an idle factory is not credited with cylinders it did not make (%s)" % cu.state.cylinders_made)
	# Time is capped like before and short absences do nothing.
	var e := stock_session()
	automate(e.factory("copper"), 8)
	check(e.apply_offline(10.0).is_empty(), "short absences are ignored")
	var cap_run := e.apply_offline(100.0 * 3600.0)
	check(bool(cap_run["capped"]), "very long absences are capped")
	check(e.factory("stainless").warehouse.total_units() == 0, "a locked factory makes nothing")


func test_direct_mode_unchanged() -> void:
	var c := GameSession.new(_data)
	check(not c.state.stock_mode and not c.factory("copper").stock_enabled(), "a plain session keeps the v0.5.1 rules")
	automate(c.factory("copper"), 3)
	c.state.cash = 0.0
	run(c, 30.0)
	check(c.state.cash > 0.0 and c.factory("copper").warehouse.total_units() == 0, "direct mode: cylinders sell the moment they are made")
