extends SceneTree
## Balancing aid: a simple simulated player for the whole company. It clicks,
## buys the cheapest thing it can afford in any factory, and builds new
## factories as soon as it can. Prints a timeline so pacing can be tuned
## from the JSON data files.
## Run:  godot --headless --path . -s tests/balance_bot.gd [-- --hours=3] [--no-expand]

const TICK := 1.0 / 60.0


func _init() -> void:
	var hours := 2.0
	var expand := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hours="):
			hours = float(arg.trim_prefix("--hours="))
		elif arg == "--no-expand":
			expand = false
	var data := GameData.new()
	data.load_all()
	var c := GameSession.new(data)
	var t := 0.0
	var click_acc := 0.0
	var marks := {}
	var next_report := 300.0
	while t < hours * 3600.0:
		# The player clicks in whichever factory is not yet fully automated.
		var focus := c.factories[0]
		for sim in c.unlocked_factories():
			if not sim.all_automated():
				focus = sim
		var cps := 4.0 if not focus.all_automated() else 1.0
		click_acc += cps * TICK
		while click_acc >= 1.0:
			click_acc -= 1.0
			focus.click()
		c.tick(TICK)
		t += TICK
		if int(t / TICK) % 30 == 0:
			for sim in c.factories:
				if expand and c.can_unlock(sim.data.id):
					c.unlock_factory(sim.data.id)
					print("%6.0fs  BUILT %s for %s (company income %s/s)" % [t, sim.data.name, NumFmt.money(sim.data.unlock_cost()), NumFmt.money(c.income_per_second())])
				elif expand and not sim.state.unlocked and c.requirements_met(sim.data.id) and not marks.has("req_" + sim.data.id):
					marks["req_" + sim.data.id] = t
					print("%6.0fs  requirements met for %s (cash %s, income %s/s)" % [t, sim.data.name, NumFmt.money(c.state.cash), NumFmt.money(c.income_per_second())])
			# Save for a factory once its requirements are met; otherwise buy the cheapest upgrade.
			var saving := false
			for sim in c.factories:
				if expand and not sim.state.unlocked and c.requirements_met(sim.data.id):
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
			for sim in c.unlocked_factories():
				if sim.all_automated() and not marks.has("auto_" + sim.data.id):
					marks["auto_" + sim.data.id] = t
					print("%6.0fs  %s fully automated (%s/s)" % [t, sim.data.name, NumFmt.money(sim.income_per_second())])
		if t >= next_report:
			next_report += 300.0 if t < 3600.0 else 600.0
			var line := "%6.0fs  cash %s  total %s/s" % [t, NumFmt.money(c.state.cash), NumFmt.money(c.income_per_second())]
			for sim in c.unlocked_factories():
				var lo := 9999
				var hi := 0
				for m: Dictionary in sim.data.machines:
					lo = mini(lo, sim.level(m["id"]))
					hi = maxi(hi, sim.level(m["id"]))
				line += "  | %s %s/s %.0f/min Lv%d-%d" % [sim.data.id, NumFmt.money(sim.income_per_second()), sim.steady_rate() * 60.0, lo, hi]
			print(line)
	quit()
