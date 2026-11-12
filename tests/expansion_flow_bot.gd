extends Node
## Dev tool: end-to-end check of the multi-factory expansion through the real
## game, starting from a save made by the previous (single-factory) version.
## tests/run_expansion_flow.sh runs the phases.

var _phase := 1
var _fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):
			_phase = int(arg.trim_prefix("--phase="))
	await _wait(0.4)
	match _phase:
		1: await _phase_upgrade_and_build()
		2: await _phase_restart()
		3: await _phase_offline()
	print("EXPANSION FLOW PHASE %d: %s" % [_phase, "PASS" if _fails == 0 else "FAIL (%d)" % _fails])
	Game.save_enabled = false
	get_tree().quit(1 if _fails > 0 else 0)


func check(cond: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _scene() -> Node:
	return get_tree().current_scene


func _wait_scene(scene_name: String) -> void:
	for i in 200:
		await get_tree().process_frame
		if _scene() != null and _scene().name == scene_name:
			await _wait(0.3)
			return
	check(false, "scene changed to " + scene_name)


func _find_button(prefix: String, root: Node = null) -> Button:
	if root == null:
		root = _scene()
	var found: Button = null
	for c in root.get_children():
		if c is Button and (c as Button).text.begins_with(prefix):
			found = c
		var deeper := _find_button(prefix, c)
		if deeper != null:
			found = deeper
	return found


func _press(prefix: String) -> void:
	var b := _find_button(prefix)
	if b == null or b.disabled:
		check(false, "button '%s' is available" % prefix)
		return
	b.pressed.emit()
	await _wait(0.3)


func _continue_into_game() -> void:
	check(_scene().name == "Menu", "starts at the main menu")
	await _press("Continue")
	await _wait_scene("Main")
	for c in (_scene().get("_dialog_layer") as Node).get_children():
		c.queue_free()      # dismiss any welcome-back box
	await _wait(0.2)


func _phase_upgrade_and_build() -> void:
	var c: GameSession = Game.session
	await _continue_into_game()
	var copper := c.factory("copper")
	var steel := c.factory("stainless")
	var main := _scene()
	# --- the old save loads as a copper-only company
	check(c.state.factory_name == "Taylor & Sons", "old save: name kept")
	check(c.state.cash >= 2000000.0 and c.state.cash < 2100000.0, "old save: cash kept (%s)" % NumFmt.money(c.state.cash))
	check(copper.level("machine_weld") == 12 and copper.level("finish") == 4 and copper.level("hand_tools") == 3, "old save: copper upgrades kept")
	check(copper.state.cylinders_made >= 5000.0, "old save: cylinder count kept")
	check(not steel.state.unlocked and c.state.current_factory == "copper", "old save: stainless locked, copper on screen")
	check((main.get("_factory").get("_fronts") as Array).size() == 6, "copper view shows its 6 stations")
	check(not main.call("switch_factory", "stainless"), "cannot walk into a locked factory")

	# --- overview and purchase
	main.call("open_factory_overview")
	await _wait(0.4)
	check(_find_button("Build factory") != null and not _find_button("Build factory").disabled, "overview offers to build stainless")
	check(_find_button("You are here") != null, "overview marks the current factory")
	await _press("Build factory")
	check(_find_button("Build it!") != null, "building asks for confirmation")
	var cash_before := c.state.cash
	var earned_before := copper.state.earned
	await _press("Not yet")
	check(not steel.state.unlocked, "declining builds nothing")
	await _press("Build factory")
	await _press("Build it!")
	await _wait(0.5)
	check(steel.state.unlocked, "stainless factory purchased")
	var expect_cash := cash_before - 1000000.0 + (copper.state.earned - earned_before)
	check(absf(c.state.cash - expect_cash) < 0.01, "exactly the construction cost was deducted")
	check(c.state.current_factory == "stainless" and (main.get("session") as FactorySim) == steel, "game moves into the new factory")
	check((main.get("_factory").get("_fronts") as Array).size() == 8, "stainless view shows its own 8-station line")
	check(_find_button("Cut the ribbon!") != null, "grand opening shown")
	await _press("Cut the ribbon!")
	check(not SaveManager.load_game(Game.save_path).is_empty()
		and bool(SaveManager.load_game(Game.save_path)["factories"]["stainless"]["unlocked"]), "purchase saved straight away")

	# --- independent upgrades, shared cash, background production
	var copper_levels := JSON.stringify(copper.state.upgrade_levels)
	var copper_rate := copper.steady_rate()
	var spent := 0.0
	cash_before = c.state.cash
	var c_earned := copper.state.earned
	var s_earned := steel.state.earned
	for n in 3:
		for m: Dictionary in steel.data.machines:
			spent += steel.cost(m["id"])
			check(steel.buy(m["id"]), "bought %s level %d" % [m["name"], n + 1])
	spent += steel.cost("torque_tools")
	steel.buy("torque_tools")
	check(JSON.stringify(copper.state.upgrade_levels) == copper_levels and is_equal_approx(copper.steady_rate(), copper_rate),
		"stainless purchases leave copper machinery untouched")
	check(steel.all_automated(), "stainless line fully automated")
	var copper_made := copper.state.cylinders_made
	await _wait(25.0)
	check(copper.state.cylinders_made > copper_made + 20.0, "copper keeps producing while stainless is on screen")
	# hop between factories repeatedly
	for n in 6:
		main.call("switch_factory", "copper" if n % 2 == 0 else "stainless")
		await _wait(5.0)
	check(c.state.current_factory == "stainless", "ended in the stainless factory")
	check(steel.state.cylinders_made >= 1.0, "stainless ships cylinders (made %s)" % steel.state.cylinders_made)
	var expected := cash_before - spent + (copper.state.earned - c_earned) + (steel.state.earned - s_earned)
	check(absf(c.state.cash - expected) < 0.01, "company cash = purchases + both factories' sales exactly (no double counting when switching)")

	# --- save and leave
	main.call("open_pause_menu")
	await _wait(0.3)
	await _press("Save & Return to Main Menu")
	await _wait_scene("Menu")
	var st := SaveManager.load_game(Game.save_path)
	print("EXPECT cash=%.2f copper_made=%.0f steel_made=%.0f steel_tokens=%d" % [
		float(st["cash"]), float(st["factories"]["copper"]["cylinders_made"]),
		float(st["factories"]["stainless"]["cylinders_made"]), steel.line.all_tokens().size()])


func _phase_restart() -> void:
	var c: GameSession = Game.session
	var saved := SaveManager.load_game(Game.save_path)
	await _continue_into_game()
	var copper := c.factory("copper")
	var steel := c.factory("stainless")
	var main := _scene()
	check(steel.state.unlocked, "stainless still owned after restart")
	check(c.state.current_factory == "stainless" and (main.get("_factory").get("_fronts") as Array).size() == 8, "reopens in the factory you left")
	check(c.state.cash >= float(saved["cash"]), "shared cash restored")
	var ok := true
	for m: Dictionary in steel.data.machines:
		ok = ok and steel.level(m["id"]) == 3
	check(ok and steel.level("torque_tools") == 1, "stainless upgrade levels restored")
	check(copper.level("machine_weld") == 12 and copper.level("finish") == 4, "copper upgrade levels restored")
	check(copper.state.cylinders_made >= float(saved["factories"]["copper"]["cylinders_made"]), "copper statistics restored")
	check(steel.state.cylinders_made >= float(saved["factories"]["stainless"]["cylinders_made"]), "stainless statistics restored")
	check(steel.line.all_tokens().size() >= 8 and copper.line.all_tokens().size() >= 6, "work in progress restored in both factories")
	var cm := copper.state.cylinders_made
	var sm := steel.state.cylinders_made
	await _wait(16.0)
	check(copper.state.cylinders_made > cm and steel.state.cylinders_made > sm, "both factories carry on producing after loading")
	check(main.call("switch_factory", "copper") and (main.get("_factory").get("_fronts") as Array).size() == 6, "can still switch to copper")
	main.call("open_pause_menu")
	await _wait(0.3)
	await _press("Save & Return to Main Menu")
	await _wait_scene("Menu")


func _phase_offline() -> void:
	var c: GameSession = Game.session
	var saved := SaveManager.load_game(Game.save_path)
	check(_scene().name == "Menu", "starts at the main menu")
	await _press("Continue")
	await _wait_scene("Main")
	var copper := c.factory("copper")
	var steel := c.factory("stainless")
	var want := floorf(copper.steady_rate() * 7200.0) * copper.profit_per_cylinder() + floorf(steel.steady_rate() * 7200.0) * steel.profit_per_cylinder()
	var got := c.state.cash - float(saved["cash"])
	check((_scene().get("_dialog_layer") as Node).get_child_count() > 0, "welcome-back summary shown")
	check(got >= want and got < want * 1.01, "offline earnings cover both factories (got %s, expected about %s)" % [NumFmt.money(got), NumFmt.money(want)])
	check(want > floorf(copper.steady_rate() * 7200.0) * copper.profit_per_cylinder() * 1.01, "stainless contributes to offline earnings")
