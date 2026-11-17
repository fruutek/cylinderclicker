extends SceneTree
## Economy check of the REAL warehouse system (Expansion 4) against the v0.5.1 "sell every cylinder" game.
## A simulated player clicks, buys the cheapest upgrade, builds factories, and (depending on the policy)
## answers customers' calls and manages stock. Prints earnings so pacing can be tuned from data/*.json.
##
##   godot --headless --path . -s tests/stock_economy_sim.gd -- [--hours=2] [--only=skilled]
##
## policies: direct (v0.5.1) | skilled | average | careless | blind

const TICK := 1.0 / 60.0
const POLICIES := ["direct", "skilled", "average", "careless", "blind"]

var _mark := 1800.0


func _init() -> void:
	var hours := 2.0
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mark="):
			_mark = float(arg.trim_prefix("--mark="))
		if arg.begins_with("--hours="):
			hours = float(arg.trim_prefix("--hours="))
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	var data := GameData.new()
	data.load_all()
	var rows: Array = []
	for p: String in POLICIES:
		if only == "" or only == p or p == "direct":
			rows.append(_play(data, hours, p))
	print("")
	print("%-10s %12s %9s %11s %9s %8s %7s %9s" % ["policy", "earned", "vs 0.5.1", "stainless", "warehouse", "orders", "missed", "wholesale"])
	for r: Dictionary in rows:
		print("%-10s %12s %+8.1f%% %11s %9s %8d %7d %9s" % [r["policy"], NumFmt.number(r["earned"]), (r["earned"] / maxf(rows[0]["earned"], 1.0) - 1.0) * 100.0,
			("%.0f min" % (r["stainless_at"] / 60.0)) if r["stainless_at"] > 0.0 else "-", "Lv %d/%d" % [r["w_copper"], r["w_steel"]], r["orders"], r["missed"], NumFmt.number(r["wholesale"])])
	for r: Dictionary in rows:
		print("  %-9s %s" % [r["policy"], r["timeline"]])
	quit()


func _play(data: GameData, hours: float, policy: String) -> Dictionary:
	var stock := policy != "direct"
	var c := GameSession.new(data, stock)
	c.contracts.reset(1)
	c.sales.reset(1)
	var t := 0.0
	var steps := 0
	var click_acc := 0.0
	var stainless_at := 0.0
	var timeline := ""
	var next_mark := _mark
	var orders := 0
	var next_answer := 5.0
	var wholesale_cash := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var win_made := 0.0
	var win_cap := 0.0
	var win_ship := 0.0
	var win_whole := 0.0
	var made_prev := 0.0
	var ship_prev := 0.0
	var whole_prev := 0.0
	while t < hours * 3600.0:
		var focus := c.factories[0]
		for sim in c.unlocked_factories():
			if not sim.all_automated():
				focus = sim
		click_acc += (4.0 if not focus.all_automated() else 1.0) * TICK
		while click_acc >= 1.0:
			click_acc -= 1.0
			focus.click()
		c.tick(TICK)
		t += TICK
		steps += 1
		for sim in c.unlocked_factories():
			win_cap += sim.steady_rate() * TICK
		if stock and t >= next_answer:
			next_answer += 8.0
			orders += _answer_calls(c, policy, rng)
			if policy == "skilled":
				_manage_targets(c)
		if steps % 30 != 0:
			continue
		for sim in c.factories:
			if c.can_unlock(sim.data.id):
				c.unlock_factory(sim.data.id)
				if sim.data.id == "stainless":
					stainless_at = t
		var saving := false
		for sim in c.factories:
			if not sim.state.unlocked and c.requirements_met(sim.data.id):
				saving = true
		var best := ""
		var best_sim: FactorySim = null
		for sim in c.unlocked_factories():
			for id: String in sim.data.upgrade_by_id:
				if id == "warehouse" and policy == "skilled" and sim.stock_enabled() and sim.warehouse.usage_fraction() < 0.6 and float(sim.warehouse.capacity) * 0.75 > sim.demand_rate() * 90.0:
					continue            # a skilled manager adds shelving when it is needed, not before
				if sim.is_visible(id) and sim.can_afford(id) and (best == "" or sim.cost(id) < best_sim.cost(best)):
					best = id
					best_sim = sim
		if best != "" and not saving:
			best_sim.buy(best)
		if t >= next_mark:
			next_mark += _mark
			var made_now := 0.0
			var ship_now := 0.0
			var whole_now := 0.0
			for sim in c.unlocked_factories():
				made_now += sim.state.cylinders_made
				for sk in sim.skus:
					ship_now += float(sim.warehouse.shipped.get(str(sk["id"]), 0))
					whole_now += float(sim.warehouse.wholesaled.get(str(sk["id"]), 0))
			timeline += "%dm:%s[util %d%% ord %d%% whl %d%%] " % [int(t / 60.0), NumFmt.number(c.state.lifetime_earned),
				int((made_now - made_prev) / maxf(win_cap, 1.0) * 100.0), int((ship_now - ship_prev) / maxf(made_now - made_prev, 1.0) * 100.0), int((whole_now - whole_prev) / maxf(made_now - made_prev, 1.0) * 100.0)]
			made_prev = made_now
			ship_prev = ship_now
			whole_prev = whole_now
			win_cap = 0.0
	var w := {"copper": 0, "stainless": 0}
	for sim in c.unlocked_factories():
		w[sim.data.id] = sim.level("warehouse")
		for s in sim.skus:
			wholesale_cash += float(sim.warehouse.wholesaled.get(str(s["id"]), 0)) * sim.sku_profit(sim.sku_index(str(s["id"]))) * 0.8
	return {"policy": policy, "earned": c.state.lifetime_earned, "stainless_at": stainless_at, "w_copper": w["copper"], "w_steel": w["stainless"],
		"orders": orders, "missed": int(c.sales.stats["missed"]) + int(c.sales.stats["declined"]), "wholesale": wholesale_cash, "timeline": timeline}


## The player's phone manner. Returns how many orders were taken.
func _answer_calls(c: GameSession, policy: String, rng: RandomNumberGenerator) -> int:
	var taken := 0
	for call: Dictionary in c.sales.calls.duplicate():
		if policy == "careless":
			continue                                   # never picks up
		var opts: Array = c.sales.options_for(call)
		var pick := "decline"
		var order := ["full", "partial", "delayed", "available"]
		if policy == "blind":
			order = ["full"]
		for want: String in order:
			for o: Dictionary in opts:
				if o["id"] == want and (float(o["chance"]) >= 0.5 or want == "full"):
					pick = want
					break
			if pick != "decline":
				break
		if policy == "average" and rng.randf() < 0.3:
			pick = "decline"
		if bool(c.sales.answer(str(call["id"]), pick).get("accepted", false)):
			taken += 1
	return taken


## A skilled manager keeps targets at the sales rep's recommendation and lets the planner run.
func _manage_targets(c: GameSession) -> void:
	for sim in c.unlocked_factories():
		sim.state.auto_targets = true
		if sim.data.upgrade_by_id.has("sales_rep") and sim.level("sales_rep") < 1 and sim.can_afford("sales_rep") and sim.is_visible("sales_rep") and sim.cost("sales_rep") < c.state.cash * 0.05:
			sim.buy("sales_rep")
