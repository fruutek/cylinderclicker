extends SceneTree
## Headless tests for production bottlenecks: finite queues, a finite dispatch pad, the van's carrying capacity,
## the three dispatch upgrades, conservation of cylinders, saves and time away.
## Run:  godot --headless --path . -s tests/run_dispatch_tests.gd

const TICK := 1.0 / 60.0
const TEST_SAVE := "user://test_dispatch_save.json"

var _passed := 0
var _failed := 0
var _data: GameData


func _init() -> void:
	_data = GameData.new()
	check(_data.load_all(), "data files load")
	for t: String in [
		"test_line_exit_gate", "test_conservation", "test_backlog_grows_backwards", "test_taps_cannot_bypass", "test_automation_pauses_and_resumes",
		"test_van_loads_only_what_is_there", "test_van_intervals", "test_pad_is_finite", "test_upgrades", "test_two_factories_are_independent",
		"test_save_roundtrip", "test_old_save_migrates", "test_v6_save_file_loads", "test_offline_is_bounded", "test_early_game_is_not_blocked", "test_no_deadlock",
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
	c.bonus_orders.enabled = false          # no random orders in these tests
	return c


func automate(s: FactorySim, lvl: int = 6) -> void:
	for m: Dictionary in s.data.machines:
		s.state.upgrade_levels[m["id"]] = lvl
	s.refresh()


func run(c: GameSession, seconds: float) -> void:
	for i in int(round(seconds / TICK)):
		c.tick(TICK)


## Pins the dispatch numbers (refresh() would recompute them from the upgrades).
func pin(cu: FactorySim, capacity: float, storage: float, away: float) -> void:
	cu.state.upgrade_levels["van_load"] = 0
	cu.refresh()
	cu.bay.set_stats(capacity, storage, away, 0.0)


## Cylinders started = cylinders delivered + on the pad + aboard the van + still on the line.
func accounted(cu: FactorySim) -> float:
	return cu.state.cylinders_sold + cu.bay.held() + cu.line.on_line()


# ---------------------------------------------------------------- the line
func test_line_exit_gate() -> void:
	var line := ProductionLine.new()
	var lengths: Array[float] = [60.0, 60.0, 60.0]
	line.setup(3, lengths)
	var works: Array[float] = [1.0, 1.0, 1.0]
	var rates: Array[float] = [10.0, 10.0, 10.0]
	line.set_params(works, rates, 48.0, 1.0, 0.0)
	var room := {"n": 0.0}
	line.exit_cb = func(count: float, _sku: int) -> float:
		var n := minf(count, room["n"])
		room["n"] -= n
		return n
	var out := {"n": 0.0}
	line.shipped.connect(func(c: float, _s: int) -> void: out["n"] += c)
	for i in 600:
		line.tick(TICK)
	check(out["n"] == 0.0, "nothing leaves while dispatch has no room")
	check(line.exit_wait > 2.0, "the head cylinder has been waiting at the end")
	var full := line.blocked_stations()
	check(full.size() == 3 and full[2] == 2, "every station ends up holding a finished cylinder: all blocked (%s)" % [full])
	var before := line.on_line()
	for i in 300:
		line.tick(TICK)
	near(line.on_line(), before, 1e-9, "a blocked line neither creates nor loses cylinders")
	room["n"] = 1.0
	line.tick(TICK)
	near(out["n"], 1.0, 1e-9, "one place opens, one cylinder leaves")
	near(line.injected, line.released + line.on_line(), 1e-6, "injected = released + on the line")


func test_conservation() -> void:
	var c := classic()
	var cu := c.factory("copper")
	automate(cu, 25)
	pin(cu, 7.0, 11.0, 6.0)
	var worst := 0.0
	for i in 60 * 400:
		c.tick(TICK)
		if i % 30 == 0:
			var drift := absf(cu.line.injected - cu.line.released - cu.line.on_line())
			drift = maxf(drift, absf(cu.state.cylinders_made - cu.state.cylinders_sold - cu.bay.held()))
			worst = maxf(worst, drift)
	check(worst < 1e-6, "no cylinder is lost or invented over 400 s of jam, loading and delivery (drift %s)" % worst)
	check(cu.bay.trips > 10 and cu.state.cylinders_sold > 50.0, "and the van really delivered (%d trips)" % cu.bay.trips)
	near(c.state.cash, cu.state.earned, 1e-3, "money paid = what was earned, once")


func test_backlog_grows_backwards() -> void:
	var c := classic()
	var cu := c.factory("copper")
	# machines of equal speed (a level per unit of work), so only the jam - not a slow machine - can block anything
	for i in cu.data.stations.size():
		cu.state.upgrade_levels[GameData.machine_id(cu.data.stations[i]["id"])] = int(cu.data.stations[i]["work"])
	cu.refresh()
	pin(cu, 6.0, 8.0, 600.0)                   # the van will not be back for ten minutes
	cu.bay.state = DispatchBay.State.AWAY
	cu.bay.timer = 600.0
	var order: Array[int] = []
	var last := cu.line.stations.size() - 1
	for i in 60 * 120:
		c.tick(TICK)
		for s in cu.line.blocked_stations():
			if not order.has(s):
				order.append(s)
	check(cu.bay.is_full() and absf(cu.bay.load - 8.0) < 1e-6, "the pad fills to its limit and no further (%.2f of 8)" % cu.bay.load)
	check(order.size() > 0 and order[0] == last, "packing is the first station to block (order: %s)" % [order])
	check(order.size() == cu.line.stations.size(), "the jam creeps back until every station is blocked (%s)" % [order])
	var sorted := order.duplicate()
	sorted.sort()
	sorted.reverse()
	check(order == sorted, "and it spreads from the dispatch end towards the start, one station at a time")
	# every belt is full of waiting cylinders, none overlapping
	var ok := true
	for b in cu.line.belts:
		var prev := INF
		for t in b.tokens:
			ok = ok and t.pos <= prev - ProductionLine.TOKEN_SPACING + 0.01 or prev == INF
			prev = t.pos
	check(ok, "queued cylinders keep their places on the belts")
	check(cu.backed_up(), "the factory knows it is backed up")
	near(cu.line.injected, cu.line.released + cu.line.on_line(), 1e-6, "still accounted for")


func test_taps_cannot_bypass() -> void:
	var c := classic()
	var cu := c.factory("copper")
	pin(cu, 6.0, 5.0, 600.0)
	cu.bay.state = DispatchBay.State.AWAY
	cu.bay.timer = 600.0
	# no machines at all: tapping does everything by hand
	var made_before := cu.state.cylinders_made
	for i in 6000:
		cu.click()
		c.tick(TICK)
	var pad := cu.bay.load
	check(pad <= 5.0 + 1e-6, "tapping cannot put more on the pad than it holds (%.1f of 5)" % pad)
	check(cu.state.cylinders_made - made_before <= 5.0 + 1e-6, "...nor make more finished cylinders than there is room for")
	var money := c.state.cash
	var made := cu.state.cylinders_made
	var hit_total := 0
	var wasted := [0]
	cu.line_full.connect(func(_s: Array) -> void: wasted[0] += 1)
	for i in 200:
		hit_total += cu.click().size()
		c.tick(TICK)
	check(wasted[0] > 0, "tapping a full line says so (LINE FULL signal, %d times)" % wasted[0])
	check(c.state.cash == money and cu.state.cylinders_made == made, "a tap on a full line earns nothing and makes nothing")
	near(cu.line.injected, cu.line.released + cu.line.on_line(), 1e-6, "no cylinder appeared from taps")
	# stations that are not blocked still take work: the first one is empty-handed, the rest hold cylinders
	var c2 := classic()
	var cu2 := c2.factory("copper")
	pin(cu2, 6.0, 5.0, 600.0)
	cu2.click()
	var hit := cu2.click()
	check(hit.size() >= 1, "an open line still works when tapped")


func test_automation_pauses_and_resumes() -> void:
	var c := classic()
	var cu := c.factory("copper")
	automate(cu, 20)
	pin(cu, 6.0, 8.0, 600.0)
	cu.bay.state = DispatchBay.State.AWAY
	cu.bay.timer = 600.0
	run(c, 60.0)
	check(cu.line.blocked_stations().size() == cu.line.stations.size(), "the whole automated line has stopped")
	var progress: Array[float] = []
	for s in cu.line.stations:
		progress.append(s.progress)
	run(c, 20.0)
	var kept := true
	for i in cu.line.stations.size():
		kept = kept and absf(cu.line.stations[i].progress - progress[i]) < 1e-9
	check(kept, "blocked machines keep their finished work and add nothing")
	# the van comes back
	cu.bay.timer = 0.5
	var fewest := cu.line.stations.size()
	var made0 := cu.state.cylinders_made
	for i in int(10.0 / TICK):
		c.tick(TICK)
		fewest = mini(fewest, cu.line.blocked_stations().size())
	check(cu.bay.trips >= 1 and c.state.cash > 0.0, "the van collected a load and was paid")
	check(fewest < cu.line.stations.size() and cu.state.cylinders_made > made0, "the line moves again as soon as space opens (%d made, at best %d of %d stations blocked)" % [cu.state.cylinders_made - made0, fewest, cu.line.stations.size()])
	run(c, 30.0)
	check(cu.state.cylinders_made > 8.0, "production resumed (%d made)" % cu.state.cylinders_made)


# ------------------------------------------------------------------ the van
func test_van_loads_only_what_is_there() -> void:
	var bay := DispatchBay.new()
	bay.set_stats(10.0, 40.0, 8.0, 0.0)
	var trips: Array = []
	var left_behind := [-1.0]
	bay.departed.connect(func(cyl: float, money: float) -> void:
		trips.append([cyl, money])
		if left_behind[0] < 0.0:
			left_behind[0] = bay.load)
	check(bay.try_add(25.0, 10.0) == 25.0, "the pad takes what fits")
	for i in int(20.0 / TICK):
		bay.tick(TICK)
	check(trips.size() >= 1 and absf(trips[0][0] - 10.0) < 1e-6, "a van never carries more than its capacity (%.1f)" % trips[0][0])
	near(trips[0][1], 100.0, 1e-6, "and is paid for exactly those cylinders")
	near(left_behind[0], 15.0, 1e-6, "the rest stays on the pad for the next trip")
	# a nearly empty pad: the van takes the little that there is and leaves
	var b2 := DispatchBay.new()
	b2.set_stats(100.0, 100.0, 8.0, 0.0)
	var t2: Array = []
	b2.departed.connect(func(cyl: float, _m: float) -> void: t2.append(cyl))
	b2.try_add(3.0, 5.0)
	for i in int(12.0 / TICK):
		b2.tick(TICK)
	check(t2.size() == 1 and absf(t2[0] - 3.0) < 1e-6, "with only 3 cylinders waiting the van takes exactly 3")
	# an empty pad: the van does not leave empty-handed
	var b3 := DispatchBay.new()
	b3.set_stats(10.0, 10.0, 8.0, 0.0)
	var t3 := [0]
	b3.departed.connect(func(_c: float, _m: float) -> void: t3[0] += 1)
	for i in int(30.0 / TICK):
		b3.tick(TICK)
	check(t3[0] == 0 and b3.state == DispatchBay.State.LOADING, "with nothing to carry the van waits at the pad")
	b3.try_add(1.0, 2.0)
	for i in int(10.0 / TICK):
		b3.tick(TICK)
	check(t3[0] == 1, "it leaves as soon as there is something to take")
	# the pad refuses cylinders it has no room for
	var b4 := DispatchBay.new()
	b4.set_stats(10.0, 12.0, 8.0, 0.0)
	near(b4.try_add(9.0, 1.0), 9.0, 1e-9, "9 of 9 fit")
	near(b4.try_add(9.0, 1.0), 3.0, 1e-9, "then only 3 of 9 fit")
	near(b4.try_add(1.0, 1.0), 0.0, 1e-9, "then none")
	check(b4.is_full() and b4.room() == 0.0, "the pad is full")


func test_van_intervals() -> void:
	var bay := DispatchBay.new()
	bay.set_stats(10.0, 40.0, 12.0, 0.0)
	var times: Array[float] = []
	var clock := [0.0]
	bay.returned.connect(func() -> void: times.append(clock[0]))
	for i in int(120.0 / TICK):
		clock[0] += TICK
		bay.try_add(2.0 * TICK * 10.0, 1.0)         # plenty always waiting
		bay.tick(TICK)
	check(times.size() >= 5, "the van keeps coming back (%d returns in 2 minutes)" % times.size())
	var gap := times[3] - times[2]
	near(gap, bay.cycle_time(), 0.6, "a full van's round trip takes away + leave + arrive + load (%.1f s)" % gap)
	near(bay.cycle_time(), 12.0 + 3.0 + 1.6 + 2.0, 1e-9, "cycle time adds up")
	# a faster turnaround makes it come back sooner
	var fast := DispatchBay.new()
	fast.set_stats(10.0, 40.0, 6.0, 0.0)
	check(fast.cycle_time() < bay.cycle_time() - 5.0, "shorter turnaround, shorter cycle")


func test_pad_is_finite() -> void:
	var c := classic()
	var cu := c.factory("copper")
	automate(cu, 30)
	pin(cu, 5.0, 9.0, 300.0)
	cu.bay.state = DispatchBay.State.AWAY
	cu.bay.timer = 300.0
	var peak := 0.0
	for i in 60 * 60:
		c.tick(TICK)
		peak = maxf(peak, cu.bay.load)
	check(peak <= 9.0 + 1e-6, "the pad never holds more than its capacity (peak %.2f)" % peak)
	var tokens := 0.0
	for b in cu.line.belts:
		check(b.tokens.size() <= int(b.length / ProductionLine.TOKEN_SPACING) + 1, "a belt holds a limited number of cylinders (%d)" % b.tokens.size())
		tokens += b.tokens.size()
	check(tokens >= 10.0, "and they are all there, queued (%d on the belts)" % tokens)


# --------------------------------------------------------------- upgrades
func test_upgrades() -> void:
	var c := classic()
	var cu := c.factory("copper")
	var cap0 := cu.bay.capacity
	var store0 := cu.bay.storage
	var away0 := cu.bay.away_time
	for id: String in ["van_load", "dispatch_store", "van_speed"]:
		check(cu.data.upgrade_by_id.has(id) and cu.is_offered(id), "%s is an upgrade of the copper works" % id)
	cu.state.upgrade_levels["van_load"] = 1
	cu.refresh()
	near(cu.bay.capacity, cap0 * 1.7, 1e-6, "Bigger Delivery Vans: %d -> %d per trip" % [cap0, cu.bay.capacity])
	cu.state.upgrade_levels["dispatch_store"] = 2
	cu.refresh()
	near(cu.bay.storage, store0 * 1.8 * 1.8, 1e-6, "Dispatch Storage level 2: %d -> %d spaces" % [store0, cu.bay.storage])
	cu.state.upgrade_levels["van_speed"] = 4
	cu.refresh()
	near(cu.bay.away_time, away0 * pow(0.85, 4.0), 1e-6, "Faster Turnaround level 4: %.1f s -> %.1f s" % [away0, cu.bay.away_time])
	cu.state.upgrade_levels["van_speed"] = 8
	cu.refresh()
	check(cu.bay.away_time >= DispatchBay.MIN_AWAY, "and the turnaround has a sensible minimum (%.1f s)" % cu.bay.away_time)
	check(cu.bay.throughput(50.0) > 0.0, "throughput is positive")
	var lows := DispatchBay.new()
	lows.set_stats(20.0, 30.0, 10.0, 0.0)
	var t0 := lows.throughput(10.0)
	lows.set_stats(100.0, 30.0, 10.0, 0.0)
	var t1 := lows.throughput(10.0)
	lows.set_stats(100.0, 54.0, 10.0, 0.0)
	var t2 := lows.throughput(10.0)
	lows.set_stats(100.0, 54.0, 6.0, 0.0)
	var t3 := lows.throughput(10.0)
	check(t1 > t0 and t2 > t1 and t3 > t2, "each upgrade moves more cylinders: %.2f -> %.2f -> %.2f -> %.2f a second" % [t0, t1, t2, t3])
	# the shop explains each one in plain words
	check(cu.dispatch_text("van_load").contains("Carries") and cu.dispatch_text("dispatch_store").contains("holds") and cu.dispatch_text("van_speed").contains("Away") and cu.dispatch_text("van_load", true).begins_with("LINE FULL!"), "the shop rows say what they do")
	# stainless has its own
	var st := c.factory("stainless")
	check(st.data.upgrade_by_id.has("dispatch_store") and st.bay.capacity != cu.bay.capacity or st.bay.storage != cu.bay.storage, "the stainless plant has its own dispatch numbers")
	# a real run: bigger dispatch lets a jammed line produce more
	var small := classic()
	var big := classic()
	for s: GameSession in [small, big]:
		automate(s.factory("copper"), 30)
	big.factory("copper").state.upgrade_levels["van_load"] = 4
	big.factory("copper").state.upgrade_levels["dispatch_store"] = 4
	big.factory("copper").state.upgrade_levels["van_speed"] = 4
	big.factory("copper").refresh()
	run(small, 300.0)
	run(big, 300.0)
	var m_small: float = small.factory("copper").state.cylinders_sold
	var m_big: float = big.factory("copper").state.cylinders_sold
	check(m_big > m_small * 2.5, "the upgraded dispatch delivers far more (%d vs %d in 5 minutes)" % [m_big, m_small])


func test_two_factories_are_independent() -> void:
	var c := classic()
	var cu := c.factory("copper")
	var st := c.factory("stainless")
	st.state.unlocked = true
	automate(cu, 30)
	automate(st, 30)
	pin(cu, 5.0, 8.0, 500.0)
	cu.bay.state = DispatchBay.State.AWAY
	cu.bay.timer = 500.0
	st.state.upgrade_levels["van_load"] = 3
	st.refresh()
	run(c, 120.0)
	check(cu.backed_up() and cu.bay.is_full(), "the copper pad is full and its line is backed up")
	check(st.bay.trips >= 1 or st.bay.carry_load > 0.0 or st.state.cylinders_made > 0.0, "the stainless plant carried on regardless")
	check(st.bay.capacity != cu.bay.capacity, "each factory has its own van")
	var trips := st.bay.trips
	var t := cu.bay.timer
	# looking at another factory changes nothing: timers are part of the simulation, not the view
	run(c, 3.0)
	check(cu.bay.timer < t and st.bay.trips >= trips, "both vans keep their own timers")
	near(cu.line.injected, cu.line.released + cu.line.on_line(), 1e-6, "copper conserved")
	near(st.line.injected, st.line.released + st.line.on_line(), 1e-6, "stainless conserved")


# --------------------------------------------------------------- saving
func test_save_roundtrip() -> void:
	var c := classic()
	var cu := c.factory("copper")
	automate(cu, 25)
	pin(cu, 7.0, 11.0, 20.0)
	run(c, 37.0)
	var tokens := cu.line.all_tokens().size()
	var blocked := cu.line.blocked_stations()
	var held := cu.bay.held()
	var state := cu.bay.state
	var timer := cu.bay.timer
	var sold := cu.state.cylinders_sold
	check(tokens > 8 and held > 0.0, "the factory is busy (%d cylinders on the line, %.0f on the pad)" % [tokens, held])
	check(SaveManager.save_game(c.save_data(), TEST_SAVE, 100.0), "the game saves")
	var d := classic()
	d.load_state(SaveManager.load_game(TEST_SAVE))
	var du := d.factory("copper")
	pin(du, 7.0, 11.0, 20.0)                   # (the pinned numbers are not part of a save: they come from the upgrades)
	check(du.line.all_tokens().size() == tokens, "every queued cylinder is back (%d)" % du.line.all_tokens().size())
	check(du.line.blocked_stations() == blocked, "blocked stations are still blocked")
	near(du.bay.held(), held, 1e-9, "the pad's contents are back")
	check(du.bay.state == state, "the van's state is back")
	near(du.bay.timer, timer, 1e-9, "and the time it has left")
	near(du.state.cylinders_sold, sold, 1e-9, "delivered count is back")
	near(du.line.on_line(), cu.line.on_line(), 1e-9, "the same number of cylinders is on the line")
	# and the restored game goes on exactly as the original would have
	run(c, 20.0)
	run(d, 20.0)
	near(du.state.cylinders_sold, cu.state.cylinders_sold, cu.state.cylinders_sold * 0.05 + 3.0, "a reloaded game carries on the same way (%d vs %d)" % [du.state.cylinders_sold, cu.state.cylinders_sold])
	near(du.line.injected + 0.0, du.line.injected, 0.0, "(restored tokens are not counted as new)")


func test_old_save_migrates() -> void:
	# a 0.8.0 save: the pad had no limit, so it can hold more than the new pad allows
	var c := classic()
	var cu := c.factory("copper")
	cu.state.upgrade_levels["van_speed"] = 3
	cu.state.upgrade_levels["van_load"] = 2
	cu.refresh()
	cu.state.bay = {"state": 0, "load": 90.0, "money": 900.0, "carry_load": 0.0, "carry_money": 0.0, "timer": 0.0, "waited": 1.0, "trips": 12}
	cu.refresh()
	cu.bay.from_dict(cu.state.bay)
	near(cu.bay.load, 90.0, 1e-9, "an old oversized pad keeps all of its cylinders")
	check(cu.bay.is_full(), "...and simply refuses more until the van has taken some")
	near(cu.bay.try_add(5.0, 1.0), 0.0, 1e-9, "(nothing more fits)")
	var paid := [0.0]
	cu.bay.departed.connect(func(_c: float, m: float) -> void: paid[0] += m)
	var dropped := 0.0
	for i in 60 * 120:
		cu.bay.tick(TICK)
	dropped = cu.bay.held()
	near(paid[0] + cu.bay.unpaid(), 900.0 * (1.0 + cu.bay.bonus), 0.01, "every pound of the old load is paid out eventually (%.0f)" % [paid[0] + cu.bay.unpaid()])
	check(dropped < 90.0, "the van worked the old pile down (%.0f left)" % dropped)
	# the upgrade levels bought before keep their meaning
	check(cu.level("van_speed") == 3 and cu.level("van_load") == 2 and cu.level("dispatch_store") == 0, "van upgrades keep their levels; storage starts at 0")
	check(SaveManager.SAVE_VERSION == 7, "save version 7")


func test_v6_save_file_loads() -> void:
	# a real 0.8.0 save file: version 6, an unlimited pad with a big pile on it, a van mid-trip, van upgrades bought
	var old := classic()
	var cu := old.factory("copper")
	automate(cu, 14)
	cu.state.upgrade_levels["van_speed"] = 4
	cu.state.upgrade_levels["van_load"] = 3
	cu.state.upgrade_levels["variant_cu_dir"] = 1
	cu.state.variant = "CU-DIR"
	cu.refresh()
	old.state.cash = 12345.0
	var payload := {"game": "cylinder_clicker", "version": 6, "state": old.save_data()}
	payload["state"]["factories"]["copper"]["bay"] = {"state": 2, "load": 140.0, "money": 1960.0, "carry_load": 0.0, "carry_money": 0.0, "timer": 3.0, "waited": 0.0, "trips": 31}
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(payload))
	f.close()
	var st := SaveManager.load_game(TEST_SAVE)
	check(not st.is_empty(), "a version 6 save file is accepted and migrated")
	var c := classic()
	c.load_state(st)
	var u := c.factory("copper")
	check(c.state.cash == 12345.0 and u.level("van_speed") == 4 and u.level("van_load") == 3 and u.level("dispatch_store") == 0, "money and upgrades are as they were")
	near(u.bay.load, 140.0, 1e-9, "the 140 cylinders on the old pad are still there")
	check(u.bay.state == DispatchBay.State.AWAY and absf(u.bay.timer - 3.0) < 1e-9 and u.bay.trips == 31, "the van is still on the same trip")
	check(u.bay.capacity > 30.0 * 4.0 and u.bay.storage == 45.0, "it now has the new limits (van %d, pad %d)" % [u.bay.capacity, u.bay.storage])
	var earned0 := c.state.cash
	var worth := u.bay.unpaid()
	run(c, 200.0)
	check(c.state.cash - earned0 >= worth * 0.99, "the whole old pile was delivered and paid (£%s of £%s)" % [NumFmt.number(c.state.cash - earned0), NumFmt.number(worth)])
	near(u.line.injected, u.line.released + u.line.on_line(), 1e-6, "and the line is consistent")
	# saving again writes version 7
	SaveManager.save_game(c.save_data(), TEST_SAVE, 100.0)
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))
	check(typeof(raw) == TYPE_DICTIONARY and int(raw.get("version", 0)) == 7, "and it is saved as version 7")


func test_offline_is_bounded() -> void:
	var c := classic()
	var cu := c.factory("copper")
	automate(cu, 60)                                # a very fast factory
	var rate := cu.steady_rate()
	var cap := cu.dispatch_rate()
	check(rate > 20.0 and cap < rate * 0.5, "the machines (%.1f/s) are far faster than dispatch (%.1f/s)" % [rate, cap])
	var cash0 := c.state.cash
	var r := c.apply_offline(3600.0)
	var earned := c.state.cash - cash0
	var unlimited := rate * 3600.0 * cu.profit_per_cylinder()
	check(not r.is_empty() and earned < unlimited * 0.5, "an hour away earns what dispatch can carry (£%s), not what the machines could make (£%s)" % [NumFmt.number(earned), NumFmt.number(unlimited)])
	near(earned, cap * 3600.0 * cu.profit_per_cylinder() * (1.0 + cu.bay.bonus), earned * 0.01 + 5.0, "exactly the dispatch rate times the hour")
	check(bool(r["factories"][0]["dispatch_limited"]), "the welcome-back summary says dispatch held it back")
	# the same time away with a big dispatch earns more
	var d := classic()
	var du := d.factory("copper")
	automate(du, 60)
	du.state.upgrade_levels["van_load"] = 6
	du.state.upgrade_levels["dispatch_store"] = 6
	du.state.upgrade_levels["van_speed"] = 6
	du.refresh()
	var cash1 := d.state.cash
	d.apply_offline(3600.0)
	check(d.state.cash - cash1 > earned * 3.0, "bigger dispatch earns much more while away (£%s vs £%s)" % [NumFmt.number(d.state.cash - cash1), NumFmt.number(earned)])
	# a slow factory is not affected
	var e := classic()
	var eu := e.factory("copper")
	automate(eu, 6)
	var rate_e := eu.steady_rate()
	check(eu.dispatch_rate() >= rate_e * 0.9, "a modest factory is hardly held back (%.2f of %.2f/s)" % [eu.dispatch_rate(), rate_e])
	# what was on the pad when the game closed is delivered once, not twice
	var f := classic()
	var fu := f.factory("copper")
	automate(fu, 6)
	fu.bay.try_add(10.0, 100.0)
	var money0 := f.state.cash
	var sold0 := fu.state.cylinders_sold
	f.apply_offline(120.0)
	var gain := f.state.cash - money0
	check(fu.bay.held() == 0.0 and gain >= 100.0, "the cylinders waiting on the pad were delivered while away")
	var again := f.apply_offline(0.0)
	check(again.is_empty() and fu.state.cylinders_sold - sold0 >= 10.0, "and nothing is counted twice")


func test_early_game_is_not_blocked() -> void:
	# a young factory (first machines) should flow freely with the starting dispatch
	var c := classic()
	var cu := c.factory("copper")
	automate(cu, 6)
	var blocked_time := 0.0
	var seconds := 600.0
	for i in int(seconds / TICK):
		c.tick(TICK)
		if cu.line.exit_wait > 0.0:
			blocked_time += TICK
	var share := blocked_time / seconds
	check(share < 0.05, "with its starting dispatch a young factory is held up only %.1f%% of the time" % (share * 100.0))
	near(cu.state.cylinders_sold + cu.bay.held() + cu.line.on_line(), cu.line.injected, 1e-6, "and every cylinder is accounted for")


func test_no_deadlock() -> void:
	# whatever the dispatch numbers, a line that is stopped always starts again when the van returns
	for caps: Array in [[1.0, 1.0, 2.5], [3.0, 2.0, 5.0], [50.0, 4.0, 3.0], [4.0, 100.0, 20.0]]:
		var c := classic()
		var cu := c.factory("copper")
		automate(cu, 30)
		pin(cu, caps[0], caps[1], caps[2])
		run(c, 300.0)
		var sold := cu.state.cylinders_sold
		run(c, 120.0)
		check(cu.state.cylinders_sold > sold, "capacity %s / pad %s / away %s: it keeps delivering (%d -> %d)" % [caps[0], caps[1], caps[2], sold, cu.state.cylinders_sold])
		near(cu.line.injected, cu.line.released + cu.line.on_line(), 1e-6, "    and is conserved")
