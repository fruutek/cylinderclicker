extends SceneTree
## Economy check of the classic game (cylinder variants + delivery van) against the original rules: a simulated
## player clicks, buys the cheapest upgrade, builds factories and always makes the best cylinder it has unlocked.
##
##   godot --headless --path . -s tests/classic_economy_sim.gd -- [--hours=2] [--mark=900]

const TICK := 1.0 / 60.0


func _init() -> void:
	var hours := 2.0
	var mark := 900.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hours="):
			hours = float(arg.trim_prefix("--hours="))
		elif arg.begins_with("--mark="):
			mark = float(arg.trim_prefix("--mark="))
	var data := GameData.new()
	data.load_all()
	var rows: Array = []
	for classic: bool in [false, true]:
		rows.append(_play(data, hours, mark, classic))
	print("")
	print("%-9s %12s %9s %11s" % ["rules", "earned", "vs orig.", "stainless"])
	for r: Dictionary in rows:
		print("%-9s %12s %+8.1f%% %11s" % [r["name"], NumFmt.number(r["earned"]), (r["earned"] / maxf(rows[0]["earned"], 1.0) - 1.0) * 100.0, ("%.0f min" % (r["stainless_at"] / 60.0)) if r["stainless_at"] > 0.0 else "-"])
	for r: Dictionary in rows:
		print("  %-8s %s" % [r["name"], r["timeline"]])
		print("  %-8s %s" % ["", r["unlocks"]])
	quit()


func _play(data: GameData, hours: float, mark: float, classic: bool) -> Dictionary:
	var c := GameSession.new(data, false, classic)
	c.contracts.reset(1)
	var t := 0.0
	var steps := 0
	var click_acc := 0.0
	var stainless_at := 0.0
	var timeline := ""
	var unlocks := ""
	var next_mark := mark
	var seen := {}
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
				if sim.is_visible(id) and sim.can_afford(id) and (best == "" or sim.cost(id) < best_sim.cost(best)):
					best = id
					best_sim = sim
		if best != "" and not saving:
			best_sim.buy(best)
			if classic and best.begins_with("variant_") and not seen.has(best_sim.data.id + best):
				seen[best_sim.data.id + best] = true
				unlocks += "%s@%dm " % [best.trim_prefix("variant_"), int(t / 60.0)]
		if classic:
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
			timeline += "%dm:%s " % [int(t / 60.0), NumFmt.number(c.state.lifetime_earned)]
	return {"name": "classic" if classic else "original", "earned": c.state.lifetime_earned, "stainless_at": stainless_at, "timeline": timeline, "unlocks": unlocks}
