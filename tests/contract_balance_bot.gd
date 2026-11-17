extends SceneTree
## Balancing aid: plays the same simulated game under different contract
## policies and compares how the company does against ignoring contracts.
## Use it to check that contracts are worth taking in sensible hands but do not
## swamp normal production (or ruin a player who commits too much).
## Run:  godot --headless --path . -s tests/contract_balance_bot.gd [-- --hours=3]

const TICK := 1.0 / 60.0

# name, max orders per factory, production share per order (0 = game default), skip major supply agreements (1) or not (0)
const POLICIES := [
	["ignore contracts", 0, 0, 0],
	["take everything (default shares)", 99, 0, 0],
	["one order per factory (default 50%)", 1, 0, 0],
	["one order per factory at 25%", 1, 25, 0],
	["trade + commercial only, one each", 1, 0, 1],
]


func _init() -> void:
	var hours := 3.0
	var only: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hours="):
			hours = float(arg.trim_prefix("--hours="))
		elif arg.begins_with("--policies="):
			only = Array(arg.trim_prefix("--policies=").split(",")).map(func(v: String) -> int: return int(v))
	var data := GameData.new()
	data.load_all()
	var results: Array = []
	for i in POLICIES.size():
		if only.is_empty() or only.has(i):
			results.append(_play(data, hours, POLICIES[i]))
	var base: Dictionary = results[0]
	print("")
	print("%-40s %12s %12s %9s %9s %6s %6s %8s %8s" % ["policy (after %.1f h)" % hours, "earned", "vs ignore", "copper/min", "steel/min", "done", "failed", "rep", "premium"])
	for r: Dictionary in results:
		print("%-40s %12s %+11.1f%% %9s %9s %6d %6d %8d %+7.1f%%" % [
			r["name"], NumFmt.number(r["earned"]), (r["earned"] / maxf(base["earned"], 1.0) - 1.0) * 100.0,
			NumFmt.number(r["copper"]), NumFmt.number(r["steel"]), r["done"], r["failed"], r["rep"], (r["paid"] / maxf(r["market"], 1.0) - 1.0) * 100.0])
	print("")
	print("earned at 1h / 2h / 3h:")
	for r: Dictionary in results:
		print("  %-40s %s" % [r["name"], "  ".join((r["marks"] as Array).map(func(v: float) -> String: return NumFmt.number(v)))])
	quit()


func _play(data: GameData, hours: float, pol: Array) -> Dictionary:
	var c := GameSession.new(data)
	c.contracts.reset(777)
	var ledger := {"paid": 0.0, "market": 0.0}
	c.contracts.completed.connect(func(k: Contract, base: float, bonus: float, _r: int) -> void:
		ledger["paid"] += base + bonus
		ledger["market"] += k.delivered * k.unit_ref)
	var marks: Array = []
	var t := 0.0
	var click_acc := 0.0
	var steps := 0
	var next_mark := 3600.0
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
		if t >= next_mark:
			next_mark += 3600.0
			marks.append(c.state.lifetime_earned)
		if steps % 30 != 0:
			continue
		for sim in c.factories:
			if c.can_unlock(sim.data.id):
				c.unlock_factory(sim.data.id)
		var saving := false
		for sim in c.factories:
			if not sim.state.unlocked and c.requirements_met(sim.data.id):
				saving = true
		var best := ""
		var best_sim: FactorySim = null
		for sim in c.unlocked_factories():
			for id: String in sim.data.upgrade_by_id:
				if sim.is_visible(id) and sim.can_afford(id) and (best == "" or sim.cost(id) < best_sim.cost(best)):
					best = id
					best_sim = sim
		if best != "" and not saving:
			best_sim.buy(best)
		if int(pol[1]) > 0 and steps % 300 == 0:
			for k in c.contracts.active.duplicate():
				if k.status == Contract.Status.READY:
					c.contracts.dispatch(k.id)
			for o in c.contracts.offers.duplicate():
				var open_here := 0
				for k in c.contracts.active:
					if k.factory == o.factory and k.status == Contract.Status.ACTIVE:
						open_here += 1
				if open_here >= int(pol[1]) or c.contracts.accept_problem(o) != "":
					continue
				if int(pol[3]) == 1 and o.tier == "major":
					continue
				if c.contracts.accept(o.id) == "" and int(pol[2]) > 0:
					c.contracts.set_allocation(o.id, int(pol[2]))
	return {
		"name": pol[0], "earned": c.state.lifetime_earned, "copper": c.factory("copper").steady_rate() * 60.0, "steel": c.factory("stainless").steady_rate() * 60.0,
		"done": c.contracts.stats["completed"], "failed": c.contracts.stats["failed"], "rep": c.contracts.reputation,
		"paid": ledger["paid"], "market": ledger["market"], "marks": marks,
	}
