extends Node
## Dev tool: drives the phone presentation ("--touch-ui") with real injected
## touch events - taps, two-finger rapid tapping, drags and holds - and
## simulates Android's pause/resume lifecycle. Works on any platform, so it
## runs on a desktop test machine and inside the Android emulator in CI.
## tests/run_touch_flow.sh runs the phases.

var _phase := 1
var _out := ""
var _fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in Game._user_args():
		if arg.begins_with("--phase="):
			_phase = int(arg.trim_prefix("--phase="))
		elif arg.begins_with("--capture="):
			_out = arg.trim_prefix("--capture=")
			DirAccess.make_dir_recursive_absolute(_out)
	await _wait(0.6)
	await _run()


func _run() -> void:
	match _phase:
		1: await _phase_play()
		2: await _phase_killed_in_background()
	print("TOUCH FLOW PHASE %d: %s" % [_phase, "PASS" if _fails == 0 else "FAIL (%d)" % _fails])
	Game.save_enabled = false
	get_tree().quit(1 if _fails > 0 else 0)


## Hook for platform checks while the naming dialog is open.
func _after_name_dialog(_edit: LineEdit) -> void:
	pass


# ---------------------------------------------------------------- helpers
func check(cond: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _scene() -> Node:
	return get_tree().current_scene


func _wait_scene(scene_name: String) -> void:
	for i in 300:
		await get_tree().process_frame
		if _scene() != null and _scene().name == scene_name:
			await _wait(0.4)
			return
	check(false, "scene changed to " + scene_name)


func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size


## Screen (viewport) position -> the window pixel the OS would report.
func _to_window(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = _to_window(pos)
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, from: Vector2, to: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = _to_window(to)
	e.relative = _to_window(to) - _to_window(from)
	Input.parse_input_event(e)


func _tap(pos: Vector2) -> void:
	_touch(0, pos, true)
	await _frames(3)
	_touch(0, pos, false)
	await _frames(4)


func _find_button(prefix: String, root: Node = null) -> Button:
	if root == null:
		root = _scene()
	var found: Button = null
	for c in root.get_children():
		if c is Button and (c as Button).text.begins_with(prefix) and (c as Button).is_visible_in_tree():
			found = c
		var deeper := _find_button(prefix, c)
		if deeper != null:
			found = deeper
	return found


func _tap_button(prefix: String) -> void:
	var b := _find_button(prefix)
	if b == null:
		check(false, "button '%s' exists" % prefix)
		return
	await _tap(b.get_global_rect().get_center())
	await _wait(0.25)


func _find_edit(root: Node) -> LineEdit:
	for c in root.get_children():
		if c is LineEdit:
			return c
		var deeper := _find_edit(c)
		if deeper != null:
			return deeper
	return null


func _on_screen(c: Control) -> bool:
	return Rect2(Vector2.ZERO, _vp()).grow(0.5).encloses(c.get_global_rect())


func _shot(shot_name: String) -> void:
	if OS.get_name() == "Android":
		# The test runner watching the log takes a real device screenshot now.
		print("SHOT " + shot_name)
		await _wait(2.5)
		return
	if _out == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))


func _row(id: String) -> Button:
	return (_scene().get("_shop").get("_rows") as Dictionary)[id]["btn"]


# ----------------------------------------------------------------- phases
func _phase_play() -> void:
	var c: GameSession = Game.session
	var vp := _vp()
	print("  viewport %s  window %s  safe %s" % [vp, DisplayServer.window_get_size(), DisplayServer.get_display_safe_area()])
	check(_scene().name == "Menu", "opens on the main menu")
	check(vp.x > vp.y * 1.9 and is_equal_approx(vp.y, 360.0), "wide landscape view with no letterboxing (%s)" % vp)
	check(UiTheme.touch, "touch presentation active")
	for text: String in ["New Game", "Continue", "Settings", "Transfer Save", "Quit Game"]:
		var b := _find_button(text)
		check(b != null and _on_screen(b) and b.size.y >= 28.0, "menu button '%s' on screen and finger-sized" % text)
	await _shot("t01_menu")

	await _tap_button("New Game")
	var edit := _find_edit(_scene())
	check(edit != null and edit.has_focus(), "naming dialog opens with the text box focused")
	check(edit != null and edit.get_global_rect().end.y < vp.y * 0.5, "naming dialog sits in the top half, clear of the keyboard")
	await _shot("t02_name_dialog")
	await _after_name_dialog(edit)
	edit.text = "Pixel Cylinder Co"
	edit.text_changed.emit(edit.text)
	await _tap_button("Open the factory")
	await _wait_scene("Main")
	check(c.state.factory_name == "Pixel Cylinder Co", "factory named")
	await _shot("t03_intro")
	await _tap_button("Open the factory!")
	var main := _scene()
	var copper := c.factory("copper")

	# --- layout
	var area: Control = main.get("_factory_area")
	var shop_holder: Control = main.get("_shop_holder")
	var insets: Vector2 = main.get("_insets")
	check(_on_screen(area) and area.size == FactoryView.SIZE, "whole factory visible at its original size")
	check(_on_screen(shop_holder) and shop_holder.size.x >= 276.0, "shop panel on screen and widened (%d wide)" % int(shop_holder.size.x))
	check(area.position.x >= insets.x and shop_holder.get_global_rect().end.x <= vp.x - insets.y + 0.5, "nothing sits in the cutout/rounded-corner margins (insets %s)" % insets)
	check(area.get_global_rect().end.x <= shop_holder.position.x + 0.5, "factory and shop do not overlap")
	var gear: Button = main.get("_hud").get("_gear")
	var fbtn: Button = main.get("_hud").get("_factories")
	check(_on_screen(gear) and _on_screen(fbtn) and gear.get_global_rect().end.x <= vp.x - insets.y + 0.5, "HUD buttons on screen inside the safe area")
	check(_row("hand_tools").size.y >= 40.0, "upgrade rows are finger-sized (%d tall)" % int(_row("hand_tools").size.y))

	# --- tapping: each touch counts exactly once
	var centre := area.get_global_rect().get_center()
	var before := c.state.total_clicks
	await _tap(centre)
	check(c.state.total_clicks - before == 1, "one tap = one click (no double count from the emulated mouse)")
	before = c.state.total_clicks
	var t0 := Time.get_ticks_msec()
	for i in 120:           # two thumbs alternating, ~30 taps a second
		var finger := i % 2
		_touch(finger, centre + Vector2(-60 + finger * 120, (i % 5) * 6), true)
		await get_tree().process_frame
		_touch(finger, centre + Vector2(-60 + finger * 120, (i % 5) * 6), false)
		await get_tree().process_frame
	var took := (Time.get_ticks_msec() - t0) / 1000.0
	check(c.state.total_clicks - before == 120, "120 rapid two-finger taps all registered once each (got %d)" % (c.state.total_clicks - before))
	check((main.get("_factory").get("_particles") as Array).size() <= FactoryView.MAX_PARTICLES, "tap effects stay capped")
	print("  rapid tapping: 240 frames in %.2fs (%.0f fps on this machine)" % [took, 240.0 / took])
	# a tap on the shop or HUD is not a factory click
	before = c.state.total_clicks
	await _tap(shop_holder.get_global_rect().get_center() + Vector2(0, 120))
	check(c.state.total_clicks == before, "tapping outside the factory does not manufacture")
	await _shot("t04_tapping")

	# --- buying by tap
	c.state.cash = 100.0
	await _tap(_row("hand_tools").get_global_rect().get_center())
	check(copper.level("hand_tools") == 1 and is_equal_approx(c.state.cash, 85.0), "tap buys an upgrade exactly once")

	# --- hold for details: shows the tooltip, does not buy
	c.state.cash = 1000.0
	var tip: Control = main.get("_shop").get("_tooltip")
	var p := _row("finish").get_global_rect().get_center()
	_touch(0, p, true)
	await _wait(0.7)
	check(tip.visible and _on_screen(tip), "press and hold shows the details box on screen")
	await _shot("t05_hold_details")
	_touch(0, p, false)
	await _frames(5)
	check(copper.level("finish") == 0 and not tip.visible, "releasing a hold does not buy")

	# --- scrolling the machine list never buys
	await _tap_button("MACHINES")
	var scroll: ScrollContainer = (main.get("_shop").get("_scrolls") as Array)[1]
	var levels := JSON.stringify(copper.state.upgrade_levels)
	var start := _row("machine_test").get_global_rect().get_center()
	_touch(0, start, true)
	await _frames(2)
	var pos := start
	for i in 12:
		var next := pos + Vector2(0, -8)
		_drag(0, pos, next)
		pos = next
		await get_tree().process_frame
	_touch(0, pos, false)
	await _wait(0.4)
	check(scroll.scroll_vertical > 20, "dragging scrolls the list (scrolled %d)" % scroll.scroll_vertical)
	check(JSON.stringify(copper.state.upgrade_levels) == levels and is_equal_approx(c.state.cash, 1000.0), "scrolling does not buy anything")
	await _shot("t06_scrolled_machines")
	var footer: Label = main.get("_shop").get("_footer")
	check(footer.get_global_rect().position.y < vp.y, "scrolling reveals the bottom of the list")
	await _tap(_row("machine_pack").get_global_rect().get_center())
	check(copper.level("machine_pack") == 1, "a tap after scrolling still buys")

	# --- factories: build stainless and switch by touch
	for m: Dictionary in copper.data.machines:
		copper.state.upgrade_levels[m["id"]] = 8
	copper.refresh()
	copper.state.earned = 600000.0
	c.state.cash = 1300000.0
	await _tap_button("FACTORIES")
	check(_find_button("Build factory") != null and _on_screen(_find_button("Build factory")), "factory overview opens with the build button on screen")
	await _shot("t07_overview")
	await _tap_button("Build factory")
	await _tap_button("Build it!")
	await _wait(0.6)
	var steel := c.factory("stainless")
	check(steel.state.unlocked and c.state.current_factory == "stainless", "stainless plant built and entered by touch")
	await _tap_button("Cut the ribbon!")
	await _tap(area.get_global_rect().get_center())
	check(steel.line.stations[0].progress > 0.0 or steel.line.stations[0].cycles > 0.0, "tapping works the stainless line")
	for m: Dictionary in steel.data.machines:
		steel.state.upgrade_levels[m["id"]] = 6
	steel.refresh()
	main.call("_show_factory", steel)
	await _tap_button("MACHINES")
	var sscroll: ScrollContainer = (main.get("_shop").get("_scrolls") as Array)[1]
	sscroll.scroll_vertical = 400
	await _frames(3)
	check(sscroll.scroll_vertical > 30, "the eight-machine stainless list scrolls (max %d)" % sscroll.scroll_vertical)
	await _wait(14.0)
	await _shot("t08_stainless_plant")
	var copper_made := copper.state.cylinders_made
	await _wait(3.0)
	check(copper.state.cylinders_made > copper_made, "copper keeps producing while stainless is on screen")
	await _tap_button("FACTORIES")
	await _shot("t09_overview_both")
	await _tap_button("Enter factory")
	check(c.state.current_factory == "copper", "switched back to copper by touch")
	await _wait(1.0)
	await _shot("t10_copper_again")

	# --- pause menu via the Back button
	Game.back_pressed.emit()
	await _wait(0.3)
	check(get_tree().paused and _find_button("Resume Game") != null, "Back opens the pause menu")
	for text: String in ["Resume Game", "Save Game", "Settings", "Rename Factory", "Save & Return to Main Menu", "Quit"]:
		var b := _find_button(text)
		check(b != null and _on_screen(b) and b.size.y >= 28.0, "pause button '%s' on screen and finger-sized" % text)
	await _shot("t11_pause_menu")
	await _tap_button("Save Game")
	check(is_equal_approx(float(SaveManager.load_game(Game.save_path)["cash"]), c.state.cash), "Save Game tap saves")
	await _tap_button("Settings")
	await _shot("t12_settings")
	Game.back_pressed.emit()
	await _wait(0.3)
	check(_find_button("Done") == null and _find_button("Resume Game") != null, "Back closes the dialog on top")
	await _tap_button("Resume Game")
	check(not get_tree().paused, "Resume by tap")

	# --- Android lifecycle: background for two hours, then return
	var cash := c.state.cash
	var want := floorf(copper.steady_rate() * 7200.0) * copper.profit_per_cylinder() + floorf(steel.steady_rate() * 7200.0) * steel.profit_per_cylinder()
	Game.notification(NOTIFICATION_APPLICATION_PAUSED)
	var saved_at := float(SaveManager.load_game(Game.save_path)["last_saved_unix"])
	check(absf(saved_at - Game.now_unix()) < 2.0, "going to the background saves the game")
	Game.clock_offset += 7200.0
	Game.notification(NOTIFICATION_APPLICATION_RESUMED)
	await _wait(0.4)
	var got := c.state.cash - cash
	check(got >= want and got <= want * 1.001 + 50000.0, "two hours in the background pays offline earnings once (got %s, expected %s)" % [NumFmt.money(got), NumFmt.money(want)])
	check(_find_button("Lovely!") != null, "welcome-back summary shown after resuming")
	await _shot("t13_welcome_back")
	check(absf(float(SaveManager.load_game(Game.save_path)["last_saved_unix"]) - Game.now_unix()) < 2.0, "resume re-saves, so that time can never be paid twice")
	await _tap_button("Lovely!")
	cash = c.state.cash
	var live := c.recent_income_per_second()
	Game.notification(NOTIFICATION_APPLICATION_RESUMED)          # a stray resume
	Game.notification(NOTIFICATION_APPLICATION_PAUSED)
	Game.clock_offset += 20.0                                       # a quick app switch
	Game.notification(NOTIFICATION_APPLICATION_RESUMED)
	await _wait(0.3)
	check(c.state.cash - cash < live * 2.0 + 20000.0 and _find_button("Lovely!") == null, "brief app switches and repeated resumes pay nothing extra")

	# --- leave it in the background and "kill" the app (phase 2 reopens it later)
	Game.notification(NOTIFICATION_APPLICATION_PAUSED)
	print("EXPECT cash=%.2f offline=%.2f" % [c.state.cash, want])


func _phase_killed_in_background() -> void:
	# The app was killed while in the background; it is reopened two hours later.
	var c: GameSession = Game.session
	var saved := SaveManager.load_game(Game.save_path)
	check(_scene().name == "Menu" and not _find_button("Continue").disabled, "cold start after being killed: Continue available")
	await _tap_button("Continue")
	await _wait_scene("Main")
	var copper := c.factory("copper")
	var steel := c.factory("stainless")
	var want := floorf(copper.steady_rate() * 7200.0) * copper.profit_per_cylinder() + floorf(steel.steady_rate() * 7200.0) * steel.profit_per_cylinder()
	var got := c.state.cash - float(saved["cash"])
	check(c.state.factory_name == "Pixel Cylinder Co" and steel.state.unlocked, "factory name and both factories restored")
	check(copper.level("machine_weld") == 8 and steel.level("machine_tig") == 6 and copper.level("hand_tools") == 1, "upgrades and automation restored")
	check(got >= want and got <= want * 1.05, "offline earnings paid once for the time away (got %s, expected %s)" % [NumFmt.money(got), NumFmt.money(want)])
	check(_find_button("Lovely!") != null, "welcome-back summary shown")
	await _shot("t14_cold_start_welcome_back")
