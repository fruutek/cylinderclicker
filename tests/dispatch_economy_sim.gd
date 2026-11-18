extends SceneTree
## Economy check of the production-bottleneck rules: a simulated player clicks, buys upgrades, builds factories
## and picks the best cylinder it has unlocked, in one of two styles:
##   cheapest - buys the cheapest affordable upgrade (dispatch upgrades get bought early, so it rarely jams)
##   attentive - buys a dispatch upgrade as soon as the line has backed up (and not before), otherwise the cheapest other
## and prints, every few minutes, what it earned and how much of the time each factory was held up at dispatch.
##
##   godot --headless --path . -s tests/dispatch_economy_sim.gd -- [--hours=2] [--mark=600] [--policy=cheapest|lazy]

const TICK := 1.0 / 60.0
const DISPATCH := ["van_speed", "van_load", "dispatch_store"]


func _init() -> void:
	var hours := 2.0
	var mark := 600.0
	var policies: Array[String] = ["cheapest", "attentive"]
	var clicks := 4.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hours="):
			hours = float(arg.trim_prefix("--hours="))
		elif arg.begins_with("--mark="):
			mark = float(arg.trim_prefix("--mark="))
		elif arg.begins_with("--policy="):
			policies = [arg.trim_prefix("--policy=")]
		elif arg.begins_with("--clicks="):
			clicks = float(arg.trim_prefix("--clicks="))
	var data := GameData.new()
	data.load_all()
	for policy in policies:
		print("== policy: ", policy)
		_play(data, hours, mark, policy, clicks)
	quit()


func _play(data: GameData, hours: float, mark: float, policy: String, clicks: float) -> void:
	var c := GameSession.new(data, false, true)
	c.bonus_orders.enabled = false
	var t := 0.0
	var steps := 0
	var click_acc := 0.0
	var next_mark := mark
	var blocked := {}
	var made0 := {}
	var made_window := {}
	for sim in c.factories:
		blocked[sim.data.id] = 0.0
	while t < hours * 3600.0:
		var focus := c.factories[0]
		for sim in c.unlocked_factories():
			if not sim.all_automated():
				focus = sim
		click_acc += (clicks if not focus.all_automated() else clicks * 0.25) * TICK
		while click_acc >= 1.0:
			click_acc -= 1.0
			focus.click()
		if policy == "unlimited":
			for sim in c.unlocked_factories():
				sim.bay.set_stats(1.0e9, 1.0e9, DispatchBay.MIN_AWAY, sim.bay.bonus)
		c.tick(TICK)
		t += TICK
		steps += 1
		for sim in c.unlocked_factories():
			if sim.line.exit_wait > 0.0:
				blocked[sim.data.id] += TICK
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
				if not sim.is_visible(id) or not sim.can_afford(id):
					continue
				if DISPATCH.has(id) and policy == "attentive" and not sim.backed_up():
					continue
				if best == "" or sim.cost(id) < best_sim.cost(best):
					best = id
					best_sim = sim
		if policy == "attentive":
			# the line is backed up: the player spots it and buys the fix the shop points at, even while saving
			for sim in c.unlocked_factories():
				var fix := sim.dispatch_advice() if sim.backed_up() else ""
				if fix != "" and sim.can_afford(fix):
					sim.buy(fix)
					best = ""
		if best != "" and not saving:
			best_sim.buy(best)
		for sim in c.unlocked_factories():
			var pick := 0
			var top := 0.0
			for i in sim.skus.size():
				if sim.sku_available(i) and sim.sku_profit(i) / sim.sku_work(i) > top:
					top = sim.sku_profit(i) / sim.sku_work(i)
					pick = i
			sim.select_variant(sim.sku_id(pick))
		if t >= next_mark:
			next_mark += mark
			var line := "%3dm earned %-8s" % [int(t / 60.0), NumFmt.number(c.state.lifetime_earned)]
			for sim in c.unlocked_factories():
				var id: String = sim.data.id
				var made_now: float = sim.state.cylinders_made
				line += " | %s made %6.1f/s (machines %5.1f eff %5.1f) jam %3d%% van %d/%d/%d" % [id.substr(0, 2), (made_now - float(made0.get(id, 0.0))) / mark, sim.steady_rate(), sim.effective_rate(),
					int(blocked[id] / mark * 100.0), sim.level("van_load"), sim.level("dispatch_store"), sim.level("van_speed")]
				made0[id] = made_now
				blocked[id] = 0.0
			print(line)
	print("   total earned ", NumFmt.number(c.state.lifetime_earned))
