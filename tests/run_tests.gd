extends SceneTree
## Headless test suite for the game logic.
## Run:  godot --headless --path . -s tests/run_tests.gd

const TICK := 1.0 / 60.0
const TEST_SAVE := "user://test_save.json"

var _passed := 0
var _failed := 0
var _data: GameData


func _init() -> void:
	_data = GameData.new()
	check(_data.load_all(), "data files load")
	for t: String in [
		"test_number_format", "test_data", "test_products", "test_manual_production", "test_idle_without_machines",
		"test_purchases", "test_sell_value", "test_stat_ops", "test_automation_revenue", "test_bottleneck",
		"test_click_boost", "test_batching", "test_save_roundtrip", "test_save_backup_and_migration",
		"test_offline", "test_determinism", "test_big_numbers", "test_factory_name", "test_line_persistence", "test_v1_migration",
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


func run(s: GameSession, seconds: float, clicks_per_second: float = 0.0) -> void:
	var steps := int(round(seconds / TICK))
	var click_acc := 0.0
	for i in steps:
		click_acc += clicks_per_second * TICK
		while click_acc >= 1.0:
			click_acc -= 1.0
			s.click()
		s.tick(TICK)


func automate_all(s: GameSession, lvl: int = 1) -> void:
	for m: Dictionary in _data.machines:
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
	check(_data.stations.size() == 6, "six stations")
	check(_data.machines.size() == 6, "six machines")
	check(_data.upgrade_by_id.has("hand_tools") and _data.upgrade_by_id.has("finish"), "core upgrades exist")
	check(_data.upgrade_by_id.has("machine_weld"), "machines are upgrades")
	near(_data.milestone_multiplier(9), 1.0, 0.0001, "no milestone below 10")
	near(_data.milestone_multiplier(25), 4.0, 0.0001, "two milestones at 25")
	var s := new_session()
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
	near(combo["value"], 150.0 * 9.0 * 1.25, 0.001, "combined value multiplies")
	near(combo["work_mult"], 2.5 * 3.0 * 1.1, 0.001, "combined work multiplies")
	check(not c.is_valid({"material": "unobtainium", "range": "standard"}), "invalid spec rejected")


func test_manual_production() -> void:
	var s := new_session()
	check(s.state.cash == 0.0, "start with no cash")
	near(s.profit_per_cylinder(), 8.0, 0.001, "base profit")
	run(s, 60.0, 4.0)
	check(s.state.cylinders_made >= 5.0, "clicking ships cylinders (made %s)" % s.state.cylinders_made)
	near(s.state.cash, s.state.cylinders_made * 8.0, 0.001, "cash = cylinders x profit")
	check(absi(s.state.total_clicks - 240) <= 1, "clicks counted")
	check(s.recent_rate_per_min() > 0.0, "live rate reported")


func test_idle_without_machines() -> void:
	var s := new_session()
	run(s, 120.0)
	check(s.state.cylinders_made == 0.0, "no clicks + no machines = no production")
	check(s.steady_rate() == 0.0, "steady rate is zero when manual")


func test_purchases() -> void:
	var s := new_session()
	check(not s.buy("hand_tools"), "cannot buy with no cash")
	s.state.cash = 100.0
	near(s.cost("hand_tools"), 15.0, 0.001, "base cost")
	check(s.buy("hand_tools"), "buy succeeds")
	near(s.state.cash, 85.0, 0.001, "cash deducted")
	check(s.level("hand_tools") == 1, "level incremented")
	near(s.cost("hand_tools"), 24.0, 0.001, "cost grows")
	near(s.stats["click_power"], 2.0, 0.001, "click power applied")
	check(not s.buy("nonexistent"), "unknown upgrade rejected")
	check(not s.is_visible("lean"), "late upgrade hidden early")
	s.state.cash = 1.0e9
	check(not s.buy("lean"), "hidden upgrade cannot be bought")
	for i in 20:
		s.buy("conveyor")
	check(s.level("conveyor") == 0, "conveyor locked until earnings milestone")
	s.state.lifetime_earned = 1000.0
	for i in 20:
		s.buy("conveyor")
	check(s.level("conveyor") == 5, "max level respected")
	check(s.is_maxed("conveyor"), "maxed flag")
	near(s.stats["belt_speed"], 48.0 * 2.0, 0.001, "belt speed stat")
	var before := s.state.cash
	check(s.buy("machine_cut"), "buy a machine")
	near(before - s.state.cash, 30.0, 0.001, "machine cost")
	near(s.station_rate(0), 1.0, 0.001, "machine supplies work")


func test_sell_value() -> void:
	var s := new_session()
	s.state.cash = 60.0
	check(s.buy("finish"), "buy polished finish")
	near(s.sale_price(), 14.4, 0.001, "sale price +20%")
	near(s.profit_per_cylinder(), 10.4, 0.001, "profit reflects price")
	var cash_before := s.state.cash
	run(s, 60.0, 4.0)
	near(s.state.cash - cash_before, s.state.cylinders_made * 10.4, 0.01, "revenue uses new price")


func test_stat_ops() -> void:
	var s := new_session()
	s.state.upgrade_levels = {"finish": 3, "lean": 2, "whistle": 2, "hand_tools": 4}
	s.refresh()
	near(s.stats["sell_value"], pow(1.2, 3), 0.0001, "mul op")
	near(s.stats["machine_speed"], pow(1.15, 2), 0.0001, "mul op 2")
	near(s.stats["click_boost"], 0.15, 0.0001, "add op")
	near(s.stats["click_power"], 5.0, 0.0001, "add op 2")


func test_automation_revenue() -> void:
	var s := new_session()
	automate_all(s)
	check(s.all_automated(), "all automated")
	near(s.steady_rate(), 1.0 / 8.0, 0.0001, "steady rate = slowest station (welding)")
	near(s.income_per_second(), 1.0, 0.0001, "income per second")
	run(s, 600.0)
	var made := s.state.cylinders_made
	check(made >= 60.0 and made <= 75.0, "600s of automation ships ~0.125/s (made %s)" % made)
	near(s.state.cash, made * 8.0, 0.001, "automation revenue is correct")
	near(s.recent_rate_per_min(), 7.5, 1.6, "live rate matches steady rate")
	# Steady-state check: after warm-up, output matches the analytic rate.
	var before := s.state.cylinders_made
	run(s, 800.0)
	near(s.state.cylinders_made - before, 100.0, 1.0, "long-run throughput matches steady rate")


func test_bottleneck() -> void:
	var s := new_session()
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
	var a := new_session()
	automate_all(a, 3)
	var b := new_session()
	automate_all(b, 3)
	run(a, 300.0)
	run(b, 300.0, 5.0)
	check(b.state.cylinders_made > a.state.cylinders_made * 1.15, "clicking still helps once automated (%s vs %s)" % [b.state.cylinders_made, a.state.cylinders_made])


func test_batching() -> void:
	var s := new_session()
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
	var s := new_session()
	s.state.cash = 500.0
	s.buy("hand_tools")
	s.buy("machine_cut")
	s.buy("machine_cut")
	run(s, 30.0, 4.0)
	s.state.settings["music_volume"] = 0.1
	s.state.tutorial_step = 4
	s.state.factory_name = "Taylor & Sons"
	check(SaveManager.save_game(s.save_data(), TEST_SAVE, 1000.0), "save succeeds")
	var loaded := SaveManager.load_game(TEST_SAVE)
	check(not loaded.is_empty(), "load succeeds")
	var s2 := new_session()
	s2.load_state(loaded)
	near(s2.state.cash, s.state.cash, 0.0001, "cash persists")
	near(s2.state.cylinders_made, s.state.cylinders_made, 0.0001, "cylinders persist")
	near(s2.state.lifetime_earned, s.state.lifetime_earned, 0.0001, "lifetime persists")
	check(s2.level("hand_tools") == 1 and s2.level("machine_cut") == 2, "upgrade levels persist")
	check(s2.state.total_clicks == s.state.total_clicks, "click stat persists")
	near(s2.station_rate(0), s.station_rate(0), 0.0001, "production rates restored")
	near(s2.stats["click_power"], 2.0, 0.0001, "derived stats restored")
	near(float(s2.state.settings["music_volume"]), 0.1, 0.0001, "settings persist")
	check(s2.state.tutorial_step == 4, "tutorial progress persists")
	near(s2.state.last_saved_unix, 1000.0, 0.001, "save timestamp stored")
	check(s2.state.current_product["material"] == "copper", "product persists")
	check(s2.state.factory_name == "Taylor & Sons", "factory name persists")
	check(s2.state.unlocked_products == s.state.unlocked_products, "unlocked products persist")


func test_save_backup_and_migration() -> void:
	var s := new_session()
	s.state.cash = 111.0
	SaveManager.save_game(s.state.to_dict(), TEST_SAVE, 1.0)
	s.state.cash = 222.0
	SaveManager.save_game(s.state.to_dict(), TEST_SAVE, 2.0)
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
	var s2 := new_session()
	s2.load_state(SaveManager.load_game(TEST_SAVE))
	near(s2.state.cash, 42.0, 0.001, "v0 save migrated")
	check(s2.level("hand_tools") == 2, "v0 levels migrated")
	check(not s2.state.upgrade_levels.has("removed_upgrade"), "unknown upgrades dropped")
	# Saves from the future are refused rather than misread.
	f = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 999, "state": {"cash": 5.0}}))
	f.close()
	SaveManager.delete_save(TEST_SAVE + ".bak")
	check(SaveManager.load_game(TEST_SAVE).is_empty(), "newer-version save refused")


func test_offline() -> void:
	var s := new_session()
	check(s.apply_offline(3600.0).is_empty(), "no offline income without full automation")
	automate_all(s)
	check(s.apply_offline(30.0).is_empty(), "short absences ignored")
	var r := s.apply_offline(3600.0)
	near(r["cylinders"], 450.0, 0.001, "offline cylinders = rate x time")
	near(r["cash"], 3600.0, 0.001, "offline cash")
	near(s.state.cash, 3600.0, 0.001, "offline cash credited")
	check(not r["capped"], "not capped at 1h")
	var r2 := s.apply_offline(100.0 * 3600.0)
	check(r2["capped"], "long absence capped")
	near(r2["counted_seconds"], 8.0 * 3600.0, 0.001, "cap is 8 hours")
	near(r2["cash"], 8.0 * 3600.0, 0.001, "capped cash")


func test_determinism() -> void:
	var results: Array[float] = []
	for n in 2:
		var s := new_session()
		s.state.cash = 400.0
		s.buy("machine_cut")
		s.buy("machine_roll")
		s.buy("hand_tools")
		run(s, 90.0, 3.0)
		results.append(s.state.cash)
	check(results[0] == results[1], "identical inputs give identical results")


func test_big_numbers() -> void:
	var s := new_session()
	s.state.cash = 1.0e305
	s._credit(1.0, 1.0e305)
	check(s.state.cash <= NumFmt.MAX_VALUE and not is_inf(s.state.cash), "cash clamped below overflow")
	check(NumFmt.money(s.state.cash).length() < 16, "huge values format compactly: " + NumFmt.money(s.state.cash))
	check(not is_inf(s.cost_at_level("finish", 5000)), "upgrade cost never overflows")


func test_factory_name() -> void:
	var s := new_session()
	check(s.state.factory_name == "My Cylinder Factory", "sensible default name")
	check(GameState.clean_name("   ") == GameState.DEFAULT_FACTORY_NAME, "blank names fall back to the default")
	check(GameState.clean_name("  Bob's Works  ") == "Bob's Works", "names are trimmed")
	check(GameState.clean_name("A".repeat(60)).length() == GameState.MAX_NAME_LENGTH, "names are length-limited")
	check(GameState.clean_name("Caf\u00e9 \u2603 Works") == "Caf  Works", "undrawable characters removed")


func test_line_persistence() -> void:
	var s := new_session()
	automate_all(s, 3)
	run(s, 47.3, 2.0)
	var before := s.line.all_tokens().size()
	check(before >= 6, "line has work in progress (%d items)" % before)
	var s2 := new_session()
	s2.load_state(JSON.parse_string(JSON.stringify(s.save_data())))
	check(s2.line.all_tokens().size() == before, "items on the line are restored")
	for i in s.line.stations.size():
		near(s2.line.stations[i].progress, s.line.stations[i].progress, 0.0001, "station %d progress restored" % i)
		check(s2.line.belts[i].tokens.size() == s.line.belts[i].tokens.size(), "belt %d queue restored" % i)
	# The restored line carries on exactly like the original.
	run(s, 120.0)
	run(s2, 120.0)
	near(s2.state.cylinders_made, s.state.cylinders_made, 1.0, "restored line keeps producing identically")
	near(s2.state.cash, s.state.cash, 8.01, "restored line earns identically")
	# Damaged snapshots are ignored rather than crashing.
	var s3 := new_session()
	var bad := s.save_data()
	bad["line"] = {"stations": "nonsense", "belts": [1, 2]}
	s3.load_state(bad)
	check(s3.line.all_tokens().is_empty(), "invalid line data is ignored")


func test_v1_migration() -> void:
	check(SaveManager.SAVE_VERSION == 2, "save format is version 2")
	SaveManager.delete_save(TEST_SAVE)
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"game": "cylinder_clicker", "version": 1, "state": {
		"cash": 777.0, "cylinders_made": 55.0, "upgrade_levels": {"machine_cut": 3, "finish": 2}, "last_saved_unix": 5.0}}))
	f.close()
	var s := new_session()
	s.load_state(SaveManager.load_game(TEST_SAVE))
	near(s.state.cash, 777.0, 0.001, "v1 cash kept")
	check(s.level("machine_cut") == 3 and s.level("finish") == 2, "v1 upgrades kept")
	check(s.state.factory_name == GameState.LEGACY_FACTORY_NAME, "v1 factory keeps its original sign name")
	check(s.line.all_tokens().is_empty(), "v1 save starts with an empty line")
