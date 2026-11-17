extends RefCounted
## A deterministic, scripted playthrough of the whole company, used to prove
## that existing gameplay is unchanged when contracts are not used.
##
## The scenario only calls APIs that already existed in v0.4.0, so it can be
## run against that version to record the golden numbers that
## tests/run_contract_tests.gd compares against. To re-record them, check out
## the commit tagged in GOLDEN_SOURCE and run:
##   godot --headless --path . -s tests/print_regression.gd

const TICK := 1.0 / 60.0
const GOLDEN_SOURCE := "c36c21c (v0.4.0, before Expansion 3)"


## Plays 30 simulated minutes (clicking, buying the cheapest affordable upgrade,
## building the stainless plant part-way) and then 2 hours away, and returns
## every number that matters.
static func play(data: GameData) -> Dictionary:
	var c := GameSession.new(data)
	var click_acc := 0.0
	var steps := 0
	var built := false
	while steps < 30 * 60 * 60:
		var focus := c.factories[0]
		for sim in c.unlocked_factories():
			if not sim.all_automated():
				focus = sim
		click_acc += (4.0 if not focus.all_automated() else 1.0) * TICK
		while click_acc >= 1.0:
			click_acc -= 1.0
			focus.click()
		c.tick(TICK)
		steps += 1
		if steps == 15 * 60 * 60 and not built:
			# Skip the long saving-up phase: grant what the stainless plant needs.
			built = true
			c.factory("copper").state.earned = maxf(c.factory("copper").state.earned, 600000.0)
			c.state.cash += 1500000.0
			c.unlock_factory("stainless")
		if steps % 30 == 0:
			var best := ""
			var best_sim: FactorySim = null
			for sim in c.unlocked_factories():
				for id: String in sim.data.upgrade_by_id:
					if sim.is_visible(id) and sim.can_afford(id) and (best == "" or sim.cost(id) < best_sim.cost(best)):
						best = id
						best_sim = sim
			if best != "":
				best_sim.buy(best)
	var summary := c.apply_offline(7200.0)
	var out := {
		"cash": c.state.cash,
		"lifetime_earned": c.state.lifetime_earned,
		"total_clicks": c.state.total_clicks,
		"offline_cash": float(summary.get("cash", 0.0)),
		"offline_cylinders": float(summary.get("cylinders", 0.0)),
		"factories": {},
	}
	for sim in c.factories:
		out["factories"][sim.data.id] = {
			"unlocked": sim.state.unlocked,
			"cylinders_made": sim.state.cylinders_made,
			"earned": sim.state.earned,
			"steady_rate": sim.steady_rate(),
			"profit_each": sim.profit_per_cylinder(),
			"levels": JSON.stringify(sim.state.upgrade_levels, "", true),
		}
	return out
