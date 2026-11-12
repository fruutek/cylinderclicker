extends SceneTree
## Headless test suite for the game logic.
## Run:  godot --headless --path . -s tests/run_tests.gd

const TICK := 1.0 / 60.0
const TEST_SAVE := "user://test_save.json"

var _passed := 0
var _failed := 0
var _data: GameData
var _copper: FactoryDef


func _init() -> void:
	_data = GameData.new()
	check(_data.load_all(), "data files load")
	_copper = _data.factory("copper")
	for t: String in [
		"test_number_format", "test_data", "test_products", "test_manual_production", "test_idle_without_machines",
		"test_purchases", "test_sell_value", "test_stat_ops", "test_automation_revenue", "test_bottleneck",
		"test_click_boost", "test_batching", "test_save_roundtrip", "test_save_backup_and_migration",
		"test_offline", "test_determinism", "test_big_numbers", "test_factory_name", "test_line_persistence", "test_v1_migration",
		"test_v2_migration", "test_factory_unlock", "test_factories_independent", "test_shared_cash_and_background",
		"test_multi_factory_save", "test_multi_factory_offline", "test_stainless_costs",
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


func new_session() -> GameSession:
	return GameSession.new(_data)


func run(s: FactorySim, seconds: float, clicks_per_second: float = 0.0) -> void:
	var steps := int(round(seconds / TICK))
	var click_acc := 0.0
	for i in steps:
		click_acc += clicks_per_second * TICK
		while click_acc >= 1.0:
			click_acc -= 1.0
			s.click()
		s.tick(TICK)


func automate_all(s: FactorySim, lvl: int = 1) -> void:
	for m: Dictionary in s.data.machines:
		s.state.upgrade_levels[m["id"]] = lvl
	s.refresh()


# ------------------------------------------------------------------ tests
func test_number_format() -> void:
	check(NumFmt.money(8.0) == "£8", "money integer")
	check(NumFmt.money(9.6) == "£9.60", "money decimals")
	check(NumFmt.money(12345.0) == "£12,345", "money thousands")
	check(NumFmt.number(1234567.0) == "1.23M", "millions suffix: " + NumFmt.number(1234567.0))
	check(NumFmt.number(2.5e12) == "2.50T", "trillions suffix")
	check(NumFmt.number(1.0e40) == "1.00e40", "scientific fallback: " + NumFmt.number(1.0e40))
	check(NumFmt.number(7.5, 1) == "7.5", "small decimals")
	check(NumFmt.duration(3725.0) == "1h 2m", "duration")


func test_data() -> void:
	check(_copper.stations.size() == 6, "six stations")
	check(_copper.machines.size() == 6, "six machines")
	check(_copper.upgrade_by_id.has("hand_tools") and _copper.upgrade_by_id.has("finish"), "core upgrades exist")
	check(_copper.upgrade_by_id.has("machine_weld"), "machines are upgrades")
	near(_copper.milestone_multiplier(9), 1.0, 0.0001, "no milestone below 10")
	near(_copper.milestone_multiplier(25), 4.0, 0.0001, "two milestones at 25")
	var c := new_session()
	var s := c.factory("copper")
	check(s.layout.belt_lengths.size() == 6, "six belts")
	for l in s.layout.belt_lengths:
		check(l > 2.0 * ProductionLine.TOKEN_SPACING, "belt long enough to buffer")


func test_products() -> void:
	var c := ProductCatalog.new(_data.products)
	var p := c.compose(c.starting_product())
	check(p["name"] == "Copper Cylinder", "starting product name: " + str(p["name"]))
	near(p["value"], 12.0, 0.001, "copper value")
	near(p["material_cost"], 4.0, 0.001, "copper material cost")
	var combo := c.compose({"material": "stainless", "range": "pre_plumbed", "variants": ["slimline"]})
	check(combo["name"] == "Slimline Stainless Steel Pre-Plumbed Cylinder", "combined name: " + str(combo["name"]))
	near(combo["value"], 3600.0 * 9.0 * 1.25, 0.001, "combined value multiplies")
	near(combo["material_cost"], 1200.0 * 6.0 * 1.05, 0.001, "combined material cost multiplies")
	near(combo["work_mult"], 1.0 * 3.0 * 1.1, 0.001, "combined work multiplies")
	check(not c.is_valid({"material": "unobtainium", "range": "standard"}), "invalid spec rejected")


func test_manual_production() -> void:
	var c := new_session()
	var s := c.factory("copper")
	check(c.state.cash == 0.0, "start with no cash")
	near(s.profit_per_cylinder(), 8.0, 0.001, "base profit")
	run(s, 60.0, 4.0)
	check(s.state.cylinders_made >= 5.0, "clicking ships cylinders (made %s)" % s.state.cylinders_made)
	near(c.state.cash, s.state.cylinders_made * 8.0, 0.001, "cash = cylinders x profit")
	check(absi(c.state.total_clicks - 240) <= 1, "clicks counted")
	check(s.recent_rate_per_min() > 0.0, "live rate reported")


func test_idle_without_machines() -> void:
	var c := new_session()
	var s := c.factory("copper")
	run(s, 120.0)
	check(s.state.cylinders_made == 0.0, "no clicks + no machines = no production")
	check(s.steady_rate() == 0.0, "steady rate is zero when manual")


func test_purchases() -> void:
	var c := new_session()
	var s := c.factory("copper")
	check(not s.buy("hand_tools"), "cannot buy with no cash")
	c.state.cash = 100.0
	near(s.cost("hand_tools"), 15.0, 0.001, "base cost")
	check(s.buy("hand_tools"), "buy succeeds")
	near(c.state.cash, 85.0, 0.001, "cash deducted")
	check(s.level("hand_tools") == 1, "level incremented")
	near(s.cost("hand_tools"), 24.0, 0.001, "cost grows")
	near(s.stats["click_power"], 2.0, 0.001, "click power applied")
	check(not s.buy("nonexistent"), "unknown upgrade rejected")
	check(not s.is_visible("lean"), "late upgrade hidden early")
	c.state.cash = 1.0e9
	check(not s.buy("lean"), "hidden upgrade cannot be bought")
	for i in 20:
		s.buy("conveyor")
	check(s.level("conveyor") == 0, "conveyor locked until earnings milestone")
	s.state.earned = 1000.0
	for i in 20:
		s.buy("conveyor")
	check(s.level("conveyor") == 5, "max level respected")
	check(s.is_maxed("conveyor"), "maxed flag")
	near(s.stats["belt_speed"], 48.0 * 2.0, 0.001, "belt speed stat")
	var before := c.state.cash
	check(s.buy("machine_cut"), "buy a machine")
	near(before - c.state.cash, 30.0, 0.001, "machine cost")
	near(s.station_rate(0), 1.0, 0.001, "machine supplies work")


func test_sell_value() -> void:
	var c := new_session()
	var s := c.factory("copper")
	c.state.cash = 60.0
	check(s.buy("finish"), "buy polished finish")
	near(s.sale_price(), 14.4, 0.001, "sale price +20%")
	near(s.profit_per_cylinder(), 10.4, 0.001, "profit reflects price")
	var cash_before := c.state.cash
	run(s, 60.0, 4.0)
	near(c.state.cash - cash_before, s.state.cylinders_made * 10.4, 0.01, "revenue uses new price")


func test_stat_ops() -> void:
	var c := new_session()
	var s := c.factory("copper")
	s.state.upgrade_levels = {"finish": 3, "lean": 2, "whistle": 2, "hand_tools": 4}
	s.refresh()
	near(s.stats["sell_value"], pow(1.2, 3), 0.0001, "mul op")
	near(s.stats["machine_speed"], pow(1.15, 2), 0.0001, "mul op 2")
	near(s.stats["click_boost"], 0.15, 0.0001, "add op")
	near(s.stats["click_power"], 5.0, 0.0001, "add op 2")


func test_automation_revenue() -> void:
	var c := new_session()
	var s := c.factory("copper")
	automate_all(s)
	check(s.all_automated(), "all automated")
	near(s.steady_rate(), 1.0 / 8.0, 0.0001, "steady rate = slowest station (welding)")
	near(s.income_per_second(), 1.0, 0.0001, "income per second")
	run(s, 600.0)
	var made := s.state.cylinders_made
	check(made >= 60.0 and made <= 75.0, "600s of automation ships ~0.125/s (made %s)" % made)
	near(c.state.cash, made * 8.0, 0.001, "automation revenue is correct")
	near(s.recent_rate_per_min(), 7.5, 1.6, "live rate matches steady rate")
	# Steady-state check: after warm-up, output matches the analytic rate.
	var before := s.state.cylinders_made
	run(s, 800.0)
	near(s.state.cylinders_made - before, 100.0, 1.0, "long-run throughput matches steady rate")


func test_bottleneck() -> void:
	var c := new_session()
	var s := c.factory("copper")
	automate_all(s, 6)
	s.state.upgrade_levels["machine_weld"] = 1
	s.refresh()
	check(s.line.bottleneck_index() == 2, "welding identified as bottleneck")
	near(s.steady_rate(), 0.125, 0.0001, "line limited by welding")
	run(s, 240.0)
	var queue := s.line.belts[1].tokens.size()
	check(queue >= 3, "cylinders queue before the bottleneck (%d waiting)" % queue)
	check(s.line.stations[1].state() == ProductionLine.State.BLOCKED, "upstream station is blocked")
	check(s.line.belts[3].tokens.size() <= 1, "downstream belts stay clear")
	var before := s.state.cylinders_made
	run(s, 400.0)
	near(s.state.cylinders_made - before, 50.0, 1.0, "throughput equals bottleneck rate")
	# Fixing the bottleneck raises output.
	s.state.upgrade_levels["machine_weld"] = 10
	s.refresh()
	near(s.steady_rate(), 6.0 / 6.0, 0.0001, "fixing welding lifts output to the next limit")
	check(s.line.bottleneck_index() == 3, "next bottleneck is pressure test")


func test_click_boost() -> void:
	var ca := new_session()
	var a := ca.factory("copper")
	automate_all(a, 3)
	var cb := new_session()
	var b := cb.factory("copper")
	automate_all(b, 3)
	run(a, 300.0)
	run(b, 300.0, 5.0)
	check(b.state.cylinders_made > a.state.cylinders_made * 1.15, "clicking still helps once automated (%s vs %s)" % [b.state.cylinders_made, a.state.cylinders_made])


func test_batching() -> void:
	var c := new_session()
	var s := c.factory("copper")
	automate_all(s, 200)
	var rate := s.steady_rate()
	check(rate > 1000.0, "huge factory rate (%s/s)" % rate)
	check(s.line.batch > 100.0, "tokens represent batches")
	run(s, 60.0)
	var tokens := s.line.all_tokens().size()
	check(tokens < 80, "simulated objects stay bounded (%d tokens)" % tokens)
	var before := s.state.cylinders_made
	run(s, 120.0)
	var got := (s.state.cylinders_made - before) / 120.0
	check(absf(got - rate) / rate < 0.03, "batched throughput within 3%% of steady rate (%s vs %s)" % [got, rate])


func test_save_roundtrip() -> void:
	SaveManager.delete_save(TEST_SAVE)
	check(SaveManager.load_game(TEST_SAVE).is_empty(), "no save -> empty")
	var c := new_session()
	var s := c.factory("copper")
	c.state.cash = 500.0
	s.buy("hand_tools")
	s.buy("machine_cut")
	s.buy("machine_cut")
	run(s, 30.0, 4.0)
	c.state.settings["music_volume"] = 0.1
	c.state.tutorial_step = 4
	c.state.factory_name = "Taylor & Sons"
	check(SaveManager.save_game(c.save_data(), TEST_SAVE, 1000.0), "save succeeds")
	var loaded := SaveManager.load_game(TEST_SAVE)
	check(not loaded.is_empty(), "load succeeds")
	var c2 := new_session()
	var s2 := c2.factory("copper")
	c2.load_state(loaded)
	near(c2.state.cash, c.state.cash, 0.0001, "cash persists")
	near(s2.state.cylinders_made, s.state.cylinders_made, 0.0001, "cylinders persist")
	near(c2.state.lifetime_earned, c.state.lifetime_earned, 0.0001, "lifetime persists")
	check(s2.level("hand_tools") == 1 and s2.level("machine_cut") == 2, "upgrade levels persist")
	check(c2.state.total_clicks == c.state.total_clicks, "click stat persists")
	near(s2.station_rate(0), s.station_rate(0), 0.0001, "production rates restored")
	near(s2.stats["click_power"], 2.0, 0.0001, "derived stats restored")
	near(float(c2.state.settings["music_volume"]), 0.1, 0.0001, "settings persist")
	check(c2.state.tutorial_step == 4, "tutorial progress persists")
	near(c2.state.last_saved_unix, 1000.0, 0.001, "save timestamp stored")
	check(s2.product["name"] == "Copper Cylinder", "product persists")
	check(c2.state.factory_name == "Taylor & Sons", "factory name persists")
	check(c2.state.unlocked_products == c.state.unlocked_products, "unlocked products persist")


func test_save_backup_and_migration() -> void:
	var c := new_session()
	var s := c.factory("copper")
	c.state.cash = 111.0
	SaveManager.save_game(c.save_data(), TEST_SAVE, 1.0)
	c.state.cash = 222.0
	SaveManager.save_game(c.save_data(), TEST_SAVE, 2.0)
	check(FileAccess.file_exists(TEST_SAVE + ".bak"), "backup kept")
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	var loaded := SaveManager.load_game(TEST_SAVE)
	near(float(loaded.get("cash", -1.0)), 111.0, 0.001, "corrupt save falls back to backup")
	# v0 prototype format: flat, no version field.
	SaveManager.delete_save(TEST_SAVE)
	f = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"cash": 42.0, "upgrade_levels": {"hand_tools": 2, "removed_upgrade": 3}}))
	f.close()
	var c2 := new_session()
	var s2 := c2.factory("copper")
	c2.load_state(SaveManager.load_game(TEST_SAVE))
	near(c2.state.cash, 42.0, 0.001, "v0 save migrated")
	check(s2.level("hand_tools") == 2, "v0 levels migrated")
	check(not s2.state.upgrade_levels.has("removed_upgrade"), "unknown upgrades dropped")
	# Saves from the future are refused rather than misread.
	f = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 999, "state": {"cash": 5.0}}))
	f.close()
	SaveManager.delete_save(TEST_SAVE + ".bak")
	check(SaveManager.load_game(TEST_SAVE).is_empty(), "newer-version save refused")


func test_offline() -> void:
	var c := new_session()
	var s := c.factory("copper")
	check(c.apply_offline(3600.0).is_empty(), "no offline income without full automation")
	automate_all(s)
	check(c.apply_offline(30.0).is_empty(), "short absences ignored")
	var r := c.apply_offline(3600.0)
	near(r["cylinders"], 450.0, 0.001, "offline cylinders = rate x time")
	near(r["cash"], 3600.0, 0.001, "offline cash")
	near(c.state.cash, 3600.0, 0.001, "offline cash credited")
	check(not r["capped"], "not capped at 1h")
	var r2 := c.apply_offline(100.0 * 3600.0)
	check(r2["capped"], "long absence capped")
	near(r2["counted_seconds"], 8.0 * 3600.0, 0.001, "cap is 8 hours")
	near(r2["cash"], 8.0 * 3600.0, 0.001, "capped cash")


func test_determinism() -> void:
	var results: Array[float] = []
	for n in 2:
		var c := new_session()
		var s := c.factory("copper")
		c.state.cash = 400.0
		s.buy("machine_cut")
		s.buy("machine_roll")
		s.buy("hand_tools")
		run(s, 90.0, 3.0)
		results.append(c.state.cash)
	check(results[0] == results[1], "identical inputs give identical results")


func test_big_numbers() -> void:
	var c := new_session()
	var s := c.factory("copper")
	c.state.cash = 1.0e305
	s._credit(1.0, 1.0e305)
	check(c.state.cash <= NumFmt.MAX_VALUE and not is_inf(c.state.cash), "cash clamped below overflow")
	check(NumFmt.money(c.state.cash).length() < 16, "huge values format compactly: " + NumFmt.money(c.state.cash))
	check(not is_inf(s.cost_at_level("finish", 5000)), "upgrade cost never overflows")


func test_factory_name() -> void:
	var c := new_session()
	var s := c.factory("copper")
	check(c.state.factory_name == "My Cylinder Factory", "sensible default name")
	check(GameState.clean_name("   ") == GameState.DEFAULT_FACTORY_NAME, "blank names fall back to the default")
	check(GameState.clean_name("  Bob's Works  ") == "Bob's Works", "names are trimmed")
	check(GameState.clean_name("A".repeat(60)).length() == GameState.MAX_NAME_LENGTH, "names are length-limited")
	check(GameState.clean_name("Caf\u00e9 \u2603 Works") == "Caf  Works", "undrawable characters removed")


func test_line_persistence() -> void:
	var c := new_session()
	var s := c.factory("copper")
	automate_all(s, 3)
	run(s, 47.3, 2.0)
	var before := s.line.all_tokens().size()
	check(before >= 6, "line has work in progress (%d items)" % before)
	var c2 := new_session()
	var s2 := c2.factory("copper")
	c2.load_state(JSON.parse_string(JSON.stringify(c.save_data())))
	check(s2.line.all_tokens().size() == before, "items on the line are restored")
	for i in s.line.stations.size():
		near(s2.line.stations[i].progress, s.line.stations[i].progress, 0.0001, "station %d progress restored" % i)
		check(s2.line.belts[i].tokens.size() == s.line.belts[i].tokens.size(), "belt %d queue restored" % i)
	# The restored line carries on exactly like the original.
	run(s, 120.0)
	run(s2, 120.0)
	near(s2.state.cylinders_made, s.state.cylinders_made, 1.0, "restored line keeps producing identically")
	near(c2.state.cash, c.state.cash, 8.01, "restored line earns identically")
	# Damaged snapshots are ignored rather than crashing.
	var c3 := new_session()
	var s3 := c3.factory("copper")
	var bad := c.save_data()
	bad["factories"]["copper"]["line"] = {"stations": "nonsense", "belts": [1, 2]}
	c3.load_state(bad)
	check(s3.line.all_tokens().is_empty(), "invalid line data is ignored")


func test_v1_migration() -> void:
	check(SaveManager.SAVE_VERSION == 3, "save format is version 3")
	SaveManager.delete_save(TEST_SAVE)
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"game": "cylinder_clicker", "version": 1, "state": {
		"cash": 777.0, "cylinders_made": 55.0, "upgrade_levels": {"machine_cut": 3, "finish": 2}, "last_saved_unix": 5.0}}))
	f.close()
	var c := new_session()
	var s := c.factory("copper")
	c.load_state(SaveManager.load_game(TEST_SAVE))
	near(c.state.cash, 777.0, 0.001, "v1 cash kept")
	check(s.level("machine_cut") == 3 and s.level("finish") == 2, "v1 upgrades kept")
	check(c.state.factory_name == GameState.LEGACY_FACTORY_NAME, "v1 factory keeps its original sign name")
	check(s.line.all_tokens().is_empty(), "v1 save starts with an empty line")


# ------------------------------------------------------- multiple factories
func rich_company() -> GameSession:
	## A company that has met the stainless requirements and can afford it.
	var c := new_session()
	automate_all(c.factory("copper"), 5)
	c.factory("copper").state.earned = 600000.0
	c.state.cash = 5.0e6
	return c


func test_v2_migration() -> void:
	SaveManager.delete_save(TEST_SAVE)
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"game": "cylinder_clicker", "version": 2, "state": {
		"factory_name": "Taylor & Sons", "cash": 4321.0, "lifetime_earned": 9000.0, "cylinders_made": 310.0,
		"total_clicks": 77, "upgrade_levels": {"machine_cut": 4, "machine_weld": 2, "finish": 3, "hand_tools": 5},
		"best_rate_per_min": 12.5, "tutorial_step": 7, "unlocked_products": ["copper", "standard"],
		"current_product": {"material": "copper", "range": "standard", "variants": []},
		"line": {"stations": [{"progress": 1.5, "token": {"stage": 0, "count": 1.0}}, {"progress": 0}, {"progress": 0},
			{"progress": 0}, {"progress": 0}, {"progress": 0}], "belts": [[{"stage": 1, "count": 1.0, "pos": 30.0}], [], [], [], [], []]}}}))
	f.close()
	var c := new_session()
	c.load_state(SaveManager.load_game(TEST_SAVE))
	var copper := c.factory("copper")
	near(c.state.cash, 4321.0, 0.001, "v2 cash kept as company cash")
	check(c.state.factory_name == "Taylor & Sons", "v2 factory name kept")
	check(copper.level("machine_cut") == 4 and copper.level("finish") == 3 and copper.level("hand_tools") == 5, "v2 upgrades become copper upgrades")
	near(copper.state.cylinders_made, 310.0, 0.001, "v2 cylinder count kept")
	near(copper.state.earned, 9000.0, 0.001, "v2 earnings credited to copper")
	check(copper.line.all_tokens().size() == 2, "v2 work in progress kept")
	near(copper.line.stations[0].progress, 1.5, 0.0001, "v2 station progress kept")
	check(c.state.tutorial_step == 7 and c.state.total_clicks == 77, "v2 statistics kept")
	check(c.state.current_factory == "copper", "v2 save opens on the copper factory")
	check(not c.factory("stainless").state.unlocked, "stainless starts locked for existing players")
	near(copper.sale_price(), 12.0 * pow(1.2, 3), 0.001, "copper prices unchanged after migration")


func test_factory_unlock() -> void:
	var c := new_session()
	var steel := c.factory("stainless")
	check(_data.factories.size() == 2, "two factories defined")
	check(c.factory("copper").state.unlocked and not steel.state.unlocked, "copper owned, stainless locked at the start")
	c.state.cash = 1.0e9
	check(not c.can_unlock("stainless") and not c.unlock_factory("stainless"), "cash alone does not unlock stainless")
	check(not c.set_current("stainless"), "a locked factory cannot be entered")
	automate_all(c.factory("copper"), 3)
	check(not c.can_unlock("stainless"), "still locked until copper has earned enough")
	c.factory("copper").state.earned = 500000.0
	check(c.requirements_met("stainless"), "requirements met")
	c.state.cash = 999999.0
	check(not c.unlock_factory("stainless"), "cannot build without the full cost")
	c.state.cash = 1250000.0
	check(c.unlock_factory("stainless"), "factory purchased")
	near(c.state.cash, 250000.0, 0.001, "construction cost deducted exactly once")
	check(steel.state.unlocked, "stainless is now owned")
	check(not c.unlock_factory("stainless"), "cannot be bought twice")
	near(c.state.cash, 250000.0, 0.001, "no second charge")
	check(c.state.unlocked_products.has("stainless"), "stainless product unlocked")
	check(c.set_current("stainless") and c.current() == steel, "can switch to the new factory")
	check(steel.data.stations.size() == 8 and c.factory("copper").data.stations.size() == 6, "stainless line has more stages than copper")
	for l in steel.layout.belt_lengths:
		check(l > 2.0 * ProductionLine.TOKEN_SPACING, "stainless belt long enough to buffer")


func test_factories_independent() -> void:
	var c := rich_company()
	c.unlock_factory("stainless")
	var copper := c.factory("copper")
	var steel := c.factory("stainless")
	var copper_rates: Array[float] = []
	for i in 6:
		copper_rates.append(copper.station_rate(i))
	var copper_profit := copper.profit_per_cylinder()
	var cash := c.state.cash
	check(steel.buy("machine_tig"), "buy a stainless machine")
	near(cash - c.state.cash, 22000.0, 0.001, "stainless machine paid from company cash")
	check(steel.buy("mirror_finish") and steel.buy("torque_tools"), "buy stainless upgrades")
	check(not copper.state.upgrade_levels.has("machine_tig") and not copper.state.upgrade_levels.has("mirror_finish"), "copper upgrade state untouched")
	for i in 6:
		near(copper.station_rate(i), copper_rates[i], 0.0001, "copper machine %d unaffected" % i)
	near(copper.profit_per_cylinder(), copper_profit, 0.0001, "copper profit unaffected")
	near(steel.stats["click_power"], 5.0, 0.001, "stainless click power is its own stat")
	near(copper.stats["click_power"], 1.0, 0.001, "copper click power unchanged")
	check(not steel.buy("hand_tools") and not copper.buy("torque_tools"), "each factory only sells its own upgrades")
	check(copper.buy("finish"), "copper upgrades still purchasable")
	near(steel.sale_price(), 3600.0 * 1.2, 0.001, "copper finish does not change stainless price")


func test_shared_cash_and_background() -> void:
	var c := rich_company()
	c.unlock_factory("stainless")
	var copper := c.factory("copper")
	var steel := c.factory("stainless")
	automate_all(steel, 2)
	c.state.cash = 0.0
	c.state.lifetime_earned = 0.0
	var copper_made := copper.state.cylinders_made
	var copper_earned := copper.state.earned
	# Run the whole company, switching the viewed factory back and forth.
	var steps := int(round(600.0 / TICK))
	for i in steps:
		if i % 600 == 0:
			c.set_current("stainless" if c.state.current_factory == "copper" else "copper")
		c.tick(TICK)
	var dc := copper.state.cylinders_made - copper_made
	var ds := steel.state.cylinders_made
	check(dc > 300.0 and ds > 30.0, "both factories produce at once (copper %s, stainless %s)" % [dc, ds])
	var expected := dc * copper.profit_per_cylinder() + ds * steel.profit_per_cylinder()
	near(c.state.cash, expected, 0.01, "company cash = copper sales + stainless sales, nothing counted twice")
	near(copper.state.earned - copper_earned + steel.state.earned, c.state.cash, 0.01, "per-factory earnings add up to company cash")
	# Same run without any switching gives the identical result.
	var c2 := rich_company()
	c2.unlock_factory("stainless")
	automate_all(c2.factory("stainless"), 2)
	c2.state.cash = 0.0
	for i in steps:
		c2.tick(TICK)
	near(c2.state.cash, c.state.cash, 0.0001, "switching views changes nothing")
	near(c.income_per_second(), copper.income_per_second() + steel.income_per_second(), 0.0001, "company income is the sum of the factories")
	# A locked factory never runs.
	var c3 := new_session()
	automate_all(c3.factory("stainless"), 5)
	for i in 6000:
		c3.tick(TICK)
	check(c3.factory("stainless").state.cylinders_made == 0.0 and c3.state.cash == 0.0, "locked factory produces nothing")


func test_multi_factory_save() -> void:
	var c := rich_company()
	c.unlock_factory("stainless")
	var steel := c.factory("stainless")
	automate_all(steel, 3)
	steel.state.upgrade_levels["mirror_finish"] = 2
	steel.refresh()
	c.set_current("stainless")
	for i in int(round(200.0 / TICK)):
		c.tick(TICK)
	SaveManager.delete_save(TEST_SAVE)
	check(SaveManager.save_game(c.save_data(), TEST_SAVE, 50.0), "multi-factory save succeeds")
	var c2 := new_session()
	c2.load_state(SaveManager.load_game(TEST_SAVE))
	var steel2 := c2.factory("stainless")
	var copper2 := c2.factory("copper")
	near(c2.state.cash, c.state.cash, 0.001, "shared cash restored")
	check(steel2.state.unlocked, "unlock status restored")
	check(c2.state.current_factory == "stainless", "selected factory restored")
	check(steel2.level("machine_tig") == 3 and steel2.level("mirror_finish") == 2, "stainless upgrade levels restored")
	check(copper2.level("machine_weld") == 5, "copper upgrade levels restored")
	near(steel2.state.cylinders_made, steel.state.cylinders_made, 0.001, "stainless statistics restored")
	near(copper2.state.cylinders_made, c.factory("copper").state.cylinders_made, 0.001, "copper statistics restored")
	near(steel2.state.earned, steel.state.earned, 0.001, "per-factory earnings restored")
	check(steel2.line.all_tokens().size() == steel.line.all_tokens().size() and steel2.line.all_tokens().size() >= 8, "stainless work in progress restored")
	check(copper2.line.all_tokens().size() == c.factory("copper").line.all_tokens().size(), "copper work in progress restored")
	near(steel2.steady_rate(), steel.steady_rate(), 0.0001, "stainless production rate restored")


func test_multi_factory_offline() -> void:
	var c := rich_company()
	c.unlock_factory("stainless")
	var copper := c.factory("copper")
	var steel := c.factory("stainless")
	c.state.cash = 0.0
	var r := c.apply_offline(3600.0)
	check(r["factories"].size() == 1, "only the automated factory earns offline")
	near(r["cash"], floorf(copper.steady_rate() * 3600.0) * copper.profit_per_cylinder(), 0.01, "offline: copper only")
	automate_all(steel, 2)
	c.state.cash = 0.0
	r = c.apply_offline(7200.0)
	var want_c := floorf(copper.steady_rate() * 7200.0) * copper.profit_per_cylinder()
	var want_s := floorf(steel.steady_rate() * 7200.0) * steel.profit_per_cylinder()
	check(r["factories"].size() == 2, "both automated factories earn offline")
	near(r["cash"], want_c + want_s, 0.01, "offline total = copper + stainless")
	near(c.state.cash, want_c + want_s, 0.01, "offline cash credited once")
	near(r["cylinders"], floorf(copper.steady_rate() * 7200.0) + floorf(steel.steady_rate() * 7200.0), 0.01, "offline cylinders counted per factory")


func test_stainless_costs() -> void:
	var c := rich_company()
	c.unlock_factory("stainless")
	var steel := c.factory("stainless")
	near(steel.sale_price(), 3600.0, 0.001, "stainless sale price")
	near(steel.material_cost(), 1200.0, 0.001, "stainless material cost")
	near(steel.manufacturing_cost(), 400.0, 0.001, "stainless manufacturing cost")
	near(steel.profit_per_cylinder(), 2000.0, 0.001, "profit = price - materials - manufacturing")
	near(c.factory("copper").manufacturing_cost(), 0.0, 0.001, "copper has no manufacturing cost (unchanged)")
	near(c.factory("copper").profit_per_cylinder(), 8.0, 0.001, "copper profit unchanged")
	steel.state.upgrade_levels = {"steel_contract": 2, "energy_recovery": 1, "mirror_finish": 1}
	steel.refresh()
	near(steel.profit_per_cylinder(), 3600.0 * 1.2 - 1200.0 * 0.94 * 0.94 - 400.0 * 0.92, 0.001, "cost upgrades each applied once")
	automate_all(steel, 1)
	c.state.cash = 0.0
	for i in int(round(300.0 / TICK)):
		steel.tick(TICK)
	check(steel.state.cylinders_made >= 5.0, "stainless line ships cylinders (made %s)" % steel.state.cylinders_made)
	near(c.state.cash, steel.state.cylinders_made * steel.profit_per_cylinder(), 0.01, "each stainless sale credits profit once")
	near(steel.steady_rate(), 4.0 / 64.0, 0.0001, "stainless bottleneck is TIG welding")
	check(steel.steady_rate() < c.factory("copper").steady_rate(), "stainless starts slower than copper")
