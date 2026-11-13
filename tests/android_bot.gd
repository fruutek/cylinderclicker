extends "res://tests/touch_flow_bot.gd"
## Runs inside the real Android app on an emulator (see tests/android/).
## Phase 1 plays the game by touch and then waits for genuine Android taps;
## the runner then sends the app to the background and kills it. Phase 2 is
## the cold start afterwards, followed by a genuine Home / reopen cycle.

const MARKER := "user://android_test_phase"


func _run() -> void:
	var offset := 0.0
	if FileAccess.file_exists(MARKER):
		var parts := FileAccess.get_file_as_string(MARKER).strip_edges().split(":")
		_phase = int(parts[0])
		offset = float(parts[1])
	var win := DisplayServer.window_get_size()
	print("ANDROID INFO os=%s model=%s window=%s screen=%s safe=%s refresh=%.0f max_fps=%d renderer=%s" % [
		OS.get_name(), OS.get_model_name(), win, DisplayServer.screen_get_size(), DisplayServer.get_display_safe_area(),
		DisplayServer.screen_get_refresh_rate(), Engine.max_fps, RenderingServer.get_video_adapter_name()])
	check(OS.get_name() == "Android", "running as a native Android app")
	check(win.x > win.y, "display is landscape (%s)" % win)
	var mode := DisplayServer.window_get_mode()
	check(mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, "app is fullscreen/immersive (system bars hidden)")
	check(OS.get_user_data_dir().contains("com.fruutek.cylinderclicker"), "saves go to the app's private storage (%s)" % OS.get_user_data_dir())
	if _phase == 1:
		await _phase_play()
		_write_marker("2:%f" % (Game.clock_offset + 7300.0))
		await _real_tap_probe()
		print("TOUCH FLOW PHASE 1: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
		print("PHASE DONE")       # the runner now presses Home and kills the app
	else:
		Game.clock_offset = offset
		await _phase_killed_in_background()
		await _tap_button("Lovely!")
		await _real_background_cycle()
		DirAccess.remove_absolute(MARKER)
		print("TOUCH FLOW PHASE 2: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
		print("ANDROID TEST DONE")
		Game.quit_game()


func _write_marker(text: String) -> void:
	var f := FileAccess.open(MARKER, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _after_name_dialog(edit: LineEdit) -> void:
	await _wait(2.5)
	var win := DisplayServer.window_get_size()
	var opened_by_itself := DisplayServer.virtual_keyboard_get_height()
	var after_tap := 0
	if opened_by_itself <= 0:
		# Ask the runner for one genuine finger tap on the text box.
		var p := _to_window(edit.get_global_rect().get_center())
		print("TAPBOX %d %d" % [int(p.x), int(p.y)])
		await _wait(5.0)
		after_tap = DisplayServer.virtual_keyboard_get_height()
	var kb := maxi(opened_by_itself, after_tap)
	var bottom := _to_window(edit.get_global_rect().end).y
	print("  keyboard: feature=%s editing=%s height by itself=%d, after a real tap=%d (screen %d tall), name box bottom at %d" % [
		DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD), edit.is_editing(), opened_by_itself, after_tap, win.y, int(bottom)])
	check(kb > 0, "Android keyboard opens for the factory name")
	check(bottom <= win.y - kb + 1.0, "the name box stays visible above the keyboard")
	await _shot("a02_name_with_keyboard")


## Genuine OS-level taps: the runner sends 20 `adb shell input tap` events.
func _real_tap_probe() -> void:
	var c: GameSession = Game.session
	Game.notification(NOTIFICATION_APPLICATION_RESUMED)      # leave the simulated background state
	var area: Control = _scene().get("_factory_area")
	var p := _to_window(area.get_global_rect().get_center() + Vector2(40, 30))
	var before := c.state.total_clicks
	print("PROBE %d %d" % [int(p.x), int(p.y)])
	for i in 60:
		await _wait(0.5)
		if c.state.total_clicks - before >= 20:
			break
	await _wait(1.5)
	check(c.state.total_clicks - before == 20, "20 real Android taps -> exactly 20 clicks (got %d)" % (c.state.total_clicks - before))
	await _shot("a15_after_real_taps")


## Genuine Home button / reopen: Android pauses and resumes the app.
func _real_background_cycle() -> void:
	var c: GameSession = Game.session
	var stamp := float(SaveManager.load_game(Game.save_path)["last_saved_unix"])
	var cash := c.state.cash
	var income := c.income_per_second()
	var t0 := Time.get_ticks_msec()
	print("BG READY")
	var cycled := false
	for i in 120:
		await _wait(0.5)
		if float(SaveManager.load_game(Game.save_path)["last_saved_unix"]) > stamp + 1.0:
			cycled = true
			break
	await _wait(1.0)
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	check(cycled, "Home button: Android paused the app and the game saved")
	check(c.state.cash - cash <= income * (elapsed + 5.0) * 1.3 + 100.0, "short trip to the home screen pays no bonus (earned %s in %.0fs)" % [NumFmt.money(c.state.cash - cash), elapsed])
	check(_find_button("Lovely!") == null, "no offline summary for a few seconds away")
	await _shot("a16_resumed")
