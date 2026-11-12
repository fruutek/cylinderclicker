extends Node
## Dev tool: drives the real menus end to end (main menu -> naming -> game ->
## pause -> save -> autosave -> main menu -> restart -> continue).
## tests/run_menu_flow.sh runs the phases; screenshots are saved when a
## display is available and "--capture=<dir>" is given.

var _phase := 1
var _out := ""
var _fails := 0
var _save_path := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):
			_phase = int(arg.trim_prefix("--phase="))
		elif arg.begins_with("--capture="):
			_out = arg.trim_prefix("--capture=")
			DirAccess.make_dir_recursive_absolute(_out)
	_save_path = Game.save_path
	await _wait(0.4)
	match _phase:
		1: await _phase_new_game()
		2: await _phase_continue()
		3: await _phase_broken_save()
	print("MENU FLOW PHASE %d: %s" % [_phase, "PASS" if _fails == 0 else "FAIL (%d)" % _fails])
	Game.save_enabled = false   # the checks are done; leave the save exactly as the flow left it
	get_tree().quit(1 if _fails > 0 else 0)


# ---------------------------------------------------------------- helpers
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


func _find_button(text: String, root: Node = null) -> Button:
	if root == null:
		root = _scene()
	var found: Button = null
	for c in root.get_children():
		if c is Button and (c as Button).text == text:
			found = c   # keep searching: later siblings are drawn on top
		var deeper := _find_button(text, c)
		if deeper != null:
			found = deeper
	return found


func _press(text: String) -> void:
	var b := _find_button(text)
	if b == null:
		check(false, "button '%s' exists" % text)
		return
	b.pressed.emit()
	await _wait(0.25)


func _find_edit(root: Node) -> LineEdit:
	for c in root.get_children():
		if c is LineEdit:
			return c
		var deeper := _find_edit(c)
		if deeper != null:
			return deeper
	return null


func _type_name(text: String) -> void:
	var edit := _find_edit(_scene())
	edit.text = text
	edit.text_changed.emit(text)
	await _wait(0.1)


func _shot(shot_name: String) -> void:
	if _out == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))


func _saved_state() -> Dictionary:
	return SaveManager.load_game(_save_path)


# ----------------------------------------------------------------- phases
func _phase_new_game() -> void:
	var s: GameSession = Game.session
	check(_scene().name == "Menu", "game starts at the main menu")
	check(not Game.active, "no factory is running behind the menu")
	check(_find_button("Continue").disabled, "Continue is disabled with no save")
	await _shot("m01_main_menu_no_save")

	await _press("New Game")
	check(_find_edit(_scene()) != null, "New Game opens the naming dialog (no confirmation needed yet)")
	check(_find_edit(_scene()).text == "My Cylinder Factory", "default name offered")
	await _shot("m02_name_factory")
	await _type_name("    ")
	check(_find_button("Open the factory").disabled, "blank name cannot be confirmed")
	await _type_name("Peter's Copper Cylinders")
	check(not _find_button("Open the factory").disabled, "valid name can be confirmed")
	await _press("Open the factory")
	await _wait_scene("Main")
	check(s.state.factory_name == "Peter's Copper Cylinders", "factory has the chosen name")
	check(Game.active, "factory is running")
	check(str(_saved_state().get("factory_name", "")) == "Peter's Copper Cylinders", "new game is saved immediately")
	await _shot("m03_intro_with_name")
	await _press("Open the factory!")

	# Play a little: buy machines and upgrades.
	s.state.cash = 5000.0
	for m: Dictionary in s.data.machines:
		s.buy(m["id"])
		s.buy(m["id"])
	s.buy("finish")
	s.buy("hand_tools")
	await _wait(6.0)
	await _shot("m04_in_game_named_blue_insulation")

	# Pause menu.
	_scene().call("open_pause_menu")
	await _wait(0.3)
	check(get_tree().paused, "pause menu pauses the game")
	var t0 := s.state.play_seconds
	var made0 := s.state.cylinders_made
	var line0 := JSON.stringify(s.line.to_dict())
	await _wait(2.0)
	check(s.state.play_seconds == t0 and s.state.cylinders_made == made0 and JSON.stringify(s.line.to_dict()) == line0,
		"simulation is frozen while paused")
	for text: String in ["Resume Game", "Save Game", "Settings", "Save & Return to Main Menu", "Quit to Desktop"]:
		check(_find_button(text) != null, "pause menu has '%s'" % text)
	await _shot("m05_pause_menu")

	# Manual save.
	s.state.cash += 123.0
	await _press("Save Game")
	near_cash("manual save writes the current cash", s.state.cash)
	var toast: Label = _scene().get("_save_toast")
	check(toast.text == "Game saved", "save success message shown")
	await _shot("m06_saved_feedback")

	# Rename.
	await _press("Rename Factory")
	await _type_name("Taylor & Sons Cylinders")
	await _shot("m07_rename")
	await _press("Rename")
	check(s.state.factory_name == "Taylor & Sons Cylinders", "factory renamed")

	await _press("Settings")
	await _shot("m08_settings")
	await _press("Done")

	await _press("Resume Game")
	check(not get_tree().paused, "Resume unpauses")
	await _wait(1.0)
	check(s.state.play_seconds > t0, "production carries on after resuming")
	await _shot("m09_renamed_sign")

	# Autosave (no manual save from here on).
	var stamp := float(_saved_state().get("last_saved_unix", 0.0))
	await _wait(Game.AUTOSAVE_SECONDS + 1.5)
	var st := _saved_state()
	check(float(st.get("last_saved_unix", 0.0)) > stamp, "autosave wrote a newer save")
	check(str(st.get("factory_name", "")) == "Taylor & Sons Cylinders", "autosave contains the renamed factory")

	# Save & return to the main menu.
	_scene().call("open_pause_menu")
	await _wait(0.3)
	var cash_at_exit := s.state.cash
	await _press("Save & Return to Main Menu")
	await _wait_scene("Menu")
	check(not get_tree().paused and not Game.active, "back at the main menu, simulation stopped")
	near_cash("returning to the menu saved the game", cash_at_exit)
	check(not _find_button("Continue").disabled, "Continue is enabled now a save exists")
	await _shot("m10_main_menu_with_save")

	# New Game must ask before replacing the save.
	await _press("New Game")
	check(_find_button("Keep my factory") != null and _find_edit(_scene()) == null, "New Game asks for confirmation first")
	await _shot("m11_new_game_confirm")
	await _press("Keep my factory")
	check(str(_saved_state().get("factory_name", "")) == "Taylor & Sons Cylinders", "declining keeps the existing save")
	print("EXPECT cash=%.2f made=%.0f levels=%s tokens=%d" % [
		float(_saved_state()["cash"]), float(_saved_state()["cylinders_made"]),
		JSON.stringify(_saved_state()["upgrade_levels"]), s.line.all_tokens().size()])


func near_cash(what: String, expected: float) -> void:
	check(absf(float(_saved_state().get("cash", -1.0)) - expected) < 0.01, what)


func _phase_continue() -> void:
	var s: GameSession = Game.session
	check(_scene().name == "Menu", "restart lands on the main menu")
	var saved := _saved_state()
	check(not _find_button("Continue").disabled, "Continue is enabled")
	await _press("Continue")
	await _wait_scene("Main")
	check(s.state.factory_name == "Taylor & Sons Cylinders", "factory name restored")
	check(s.state.cash >= float(saved["cash"]), "cash restored (%.2f saved, %.2f now)" % [float(saved["cash"]), s.state.cash])
	check(s.level("finish") == 1 and s.level("hand_tools") == 1, "upgrades restored")
	var all_two := true
	for m: Dictionary in s.data.machines:
		all_two = all_two and s.level(m["id"]) == 2
	check(all_two, "machine levels restored")
	check(s.all_automated() and is_equal_approx(s.steady_rate(), 0.25), "automation and production rate restored")
	check(s.state.cylinders_made >= float(saved["cylinders_made"]), "cylinders made restored")
	check(s.line.all_tokens().size() >= 6, "cylinders on the line restored (%d items)" % s.line.all_tokens().size())
	var made := s.state.cylinders_made
	await _wait(8.0)
	check(s.state.cylinders_made > made, "factory keeps producing by itself after loading")
	await _shot("m12_continued")
	print("GOT cash=%.2f made=%.0f levels=%s" % [s.state.cash, s.state.cylinders_made, JSON.stringify(s.state.upgrade_levels)])


func _phase_broken_save() -> void:
	check(_scene().name == "Menu", "menu opens even with a damaged save")
	check(_find_button("Continue").disabled, "Continue is disabled when the save is invalid")
	check(not Game.continue_game(), "loading a damaged save is refused cleanly")
	await _shot("m13_menu_invalid_save")
