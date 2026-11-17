extends SceneTree
## Pre-implementation model of the demand-driven economy (Expansion 4).
##
## It runs the real v0.5.1 production engine with the balancing bot, but replaces the income each
## factory earns with what a demand-limited warehouse business would earn, and adds a virtual
## warehouse upgrade the bot has to pay for. This shows how pacing changes BEFORE the system exists.
##
##   income factor = demand match x premium over wholesale... (see POLICIES)
##   warehouse     = capacity 24 x growth^level, cost base x cost_growth^level; if the warehouse holds less
##                   than COVER_MIN minutes of production, sales are limited in proportion.
##
## Run:  godot --headless --path . -s tests/economy_prototype.gd [-- --hours=2]

const TICK := 1.0 / 60.0
const COVER_MIN := 4.0

# name, income factor (what share of the old income a business of this skill keeps, premium included),
# warehouse capacity growth, cost growth, weight of warehouse space in service quality (0 = ignored)
const POLICIES := [
	["v0.5.1 (sell every cylinder made)", 1.0, 0.0, 0.0, 0.0],
	["skilled: demand 1.25x, +8% premium, cheap warehouse", 1.08, 1.7, 1.8, 0.10],
	["average: some wrong stock, bigger gaps", 0.92, 1.7, 1.8, 0.10],
	["careless: wholesale floor only", 0.70, 1.7, 1.8, 0.10],
	["skilled, but warehouse x1.6 at x2.2 cost", 1.08, 1.6, 2.2, 0.10],
]


func _init() -> void:
	var hours := 2.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hours="):
			hours = float(arg.trim_prefix("--hours="))
	var data := GameData.new()
	data.load_all()
	var rows: Array = []
	for pol: Array in POLICIES:
		rows.append(_play(data, hours, pol))
	print("")
	print("%-46s %10s %9s %12s %9s %9s" % ["policy (after %.1f h)" % hours, "earned", "vs 0.5.1", "stainless at", "warehouse", "copper/min"])
	for r: Dictionary in rows:
		print("%-46s %10s %+8.1f%% %12s %9s %9s" % [r["name"], NumFmt.number(r["earned"]), (r["earned"] / maxf(rows[0]["earned"], 1.0) - 1.0) * 100.0,
			("%.0f min" % (r["stainless_at"] / 60.0)) if r["stainless_at"] > 0.0 else "-", "Lv %d/%d" % [r["w_copper"], r["w_steel"]], NumFmt.number(r["copper_rate"])])
	quit()


func _play(data: GameData, hours: float, pol: Array) -> Dictionary:
	var c := GameSession.new(data)
	c.contracts.reset(1)
	var factor: float = pol[1]
	var growth: float = pol[2]
	var cost_growth: float = pol[3]
	var weight: float = pol[4]
	var wl := {"copper": 0, "stainless": 0}
	var base_cost := {"copper": 150.0, "stainless": 40000.0}
	var base_cap := {"copper": 24.0, "stainless": 12.0}
	var t := 0.0
	var steps := 0
	var click_acc := 0.0
	var stainless_at := 0.0
	var last_earned := {"copper": 0.0, "stainless": 0.0}
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
		# Re-price what the factories just earned: demand-limited and gated by warehouse space.
		if factor != 1.0:
			for sim in c.unlocked_factories():
				var id: String = sim.data.id
				var gained: float = sim.state.earned - float(last_earned[id])
				if gained > 0.0:
					var cap: float = base_cap[id] * pow(growth, wl[id])
					var need: float = COVER_MIN * 60.0 * sim.planning_rate(1.5, 0.85)
					# A small warehouse still sells (orders become backorders), just less efficiently: late deliveries, lost repeat business.
					var eff: float = factor * ((1.0 - weight) + weight * minf(1.0, cap / maxf(need, 1.0)))
					var delta: float = gained * (eff - 1.0)
					c.state.cash = maxf(c.state.cash + delta, 0.0)
					c.state.lifetime_earned = maxf(c.state.lifetime_earned + delta, 0.0)
					sim.state.earned = maxf(sim.state.earned + delta, 0.0)
				last_earned[id] = sim.state.earned
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
		var best_cost := INF
		for sim in c.unlocked_factories():
			for uid: String in sim.data.upgrade_by_id:
				if sim.is_visible(uid) and sim.can_afford(uid) and sim.cost(uid) < best_cost:
					best = uid
					best_sim = sim
					best_cost = sim.cost(uid)
		# the virtual warehouse upgrade competes with everything else on price
		var warehouse_pick := ""
		if growth > 0.0:
			for sim in c.unlocked_factories():
				var id2: String = sim.data.id
				var wc: float = base_cost[id2] * pow(cost_growth, wl[id2])
				if c.state.cash >= wc and wc < best_cost and not saving:
					best_cost = wc
					warehouse_pick = id2
		if warehouse_pick != "":
			c.state.cash -= base_cost[warehouse_pick] * pow(cost_growth, wl[warehouse_pick])
			wl[warehouse_pick] += 1
		elif best != "" and not saving:
			best_sim.buy(best)
	return {"name": pol[0], "earned": c.state.lifetime_earned, "stainless_at": stainless_at, "w_copper": wl["copper"], "w_steel": wl["stainless"],
		"copper_rate": c.factory("copper").steady_rate() * 60.0}
