extends SceneTree
## Balancing aid: a simple simulated player. Prints when key milestones are
## reached so pacing can be tuned from the JSON data files.
## Run:  godot --headless --path . -s tests/balance_bot.gd

const TICK := 1.0 / 60.0


func _init() -> void:
	var data := GameData.new()
	data.load_all()
	var s := GameSession.new(data)
	var t := 0.0
	var click_acc := 0.0
	var marks := {}
	var next_report := 300.0
	while t < 3600.0:
		var cps := 4.0 if not s.all_automated() else 1.0
		click_acc += cps * TICK
		while click_acc >= 1.0:
			click_acc -= 1.0
			s.click()
		s.tick(TICK)
		t += TICK
		# Buy the cheapest thing we can afford (check twice a second).
		if int(t / TICK) % 30 == 0:
			var best := ""
			for id: String in data.upgrade_by_id:
				if s.is_visible(id) and s.can_afford(id) and (best == "" or s.cost(id) < s.cost(best)):
					best = id
			if best != "":
				s.buy(best)
				if not marks.has("first_buy"):
					marks["first_buy"] = t
					print("%6.0fs  first purchase: %s" % [t, best])
				if best.begins_with("machine_") and not marks.has("first_machine"):
					marks["first_machine"] = t
					print("%6.0fs  first machine: %s" % [t, best])
		if s.state.cylinders_made >= 1.0 and not marks.has("first_sale"):
			marks["first_sale"] = t
			print("%6.0fs  first sale" % t)
		if s.all_automated() and not marks.has("auto"):
			marks["auto"] = t
			print("%6.0fs  fully automated" % t)
		if t >= next_report:
			next_report += 300.0
			var lv := ""
			for m: Dictionary in data.machines:
				lv += "%d " % s.level(m["id"])
			print("%6.0fs  cash %s  income %s/s  rate %.1f/min  made %s  machines [%s] tools %d finish %d lean %d" % [
				t, NumFmt.money(s.state.cash), NumFmt.money(s.income_per_second()), s.steady_rate() * 60.0,
				NumFmt.number(s.state.cylinders_made), lv.strip_edges(), s.level("hand_tools"), s.level("finish"), s.level("lean")])
	quit()
