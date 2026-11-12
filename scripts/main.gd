extends Control
## Root scene script: assembles the factory view, HUD, shop and dialogs and
## routes input. All nodes are created in code so the project has no fragile
## hand-edited scene files.

var session: GameSession
var _factory: FactoryView
var _factory_area: Control
var _hud: Hud
var _shop: ShopPanel
var _tutorial: Tutorial
var _dialog_layer: Control
var _settings_dialog: ModalDialog
var _save_toast: Label
var _toast_time := 0.0


func _enter_tree() -> void:
	# Theme the whole window up-front so every control is measured with the pixel font.
	get_window().theme = UiTheme.theme()
	theme = UiTheme.theme()


func _ready() -> void:
	session = Game.session
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_factory_area = Control.new()
	_factory_area.position = Vector2(0, Hud.HEIGHT)
	_factory_area.size = FactoryView.SIZE
	_factory_area.clip_contents = true
	_factory_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_factory_area.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_factory_area.gui_input.connect(_on_factory_input)
	add_child(_factory_area)
	_factory = FactoryView.new()
	_factory_area.add_child(_factory)
	_factory.setup(session)

	_shop = ShopPanel.new()
	_shop.position = Vector2(640 - ShopPanel.WIDTH, Hud.HEIGHT)
	add_child(_shop)

	_hud = Hud.new()
	add_child(_hud)
	_hud.setup(session)
	_hud.settings_pressed.connect(toggle_settings)

	_tutorial = Tutorial.new()
	add_child(_tutorial)
	_tutorial.setup(session)

	var tip_layer := Control.new()
	tip_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	tip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tip_layer)
	_shop.setup(session, tip_layer)

	_save_toast = UiTheme.label("", UiTheme.CREAM)
	_save_toast.position = Vector2(6, Hud.HEIGHT + 4)
	add_child(_save_toast)

	_dialog_layer = Control.new()
	_dialog_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dialog_layer)

	session.shipped.connect(func(_c: float, _a: float) -> void: Sfx.play("sale", 0.06, -4.0))
	session.station_finished.connect(func(_i: int) -> void: Sfx.play("thunk", 0.1, -10.0))
	Game.saved.connect(func() -> void:
		_save_toast.text = "Game saved"
		_toast_time = 2.0)

	_apply_fullscreen()
	if not Game.pending_offline.is_empty():
		_show_offline(Game.pending_offline)
		Game.pending_offline = {}
	elif session.state.tutorial_step == 0:
		_show_intro()

	# Dev tooling: "-- --bot=res://tests/some_bot.gd" attaches an automation script.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bot="):
			var bot: Node = (load(arg.trim_prefix("--bot=")) as GDScript).new()
			bot.set("main", self)
			add_child(bot)


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_save_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
		if _toast_time <= 0.0:
			_save_toast.text = ""


# ------------------------------------------------------------------ input
func _on_factory_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		do_click(event.position)


func do_click(at: Vector2) -> void:
	session.click()
	_factory.click_feedback(at)
	Sfx.play("click", 0.12, -3.0)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	var modal_open := _dialog_layer.get_child_count() > 0
	match event.keycode:
		KEY_SPACE, KEY_ENTER:
			if not modal_open:
				do_click(_factory.layout.station_positions[0] + Vector2(120, 60))
		KEY_ESCAPE:
			toggle_settings()
		KEY_F11:
			session.state.settings["fullscreen"] = not bool(session.state.settings.get("fullscreen", false))
			_apply_fullscreen()
		KEY_1, KEY_2, KEY_3:
			if not modal_open:
				_shop.show_tab(event.keycode - KEY_1, true)
	get_viewport().set_input_as_handled()


func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := bool(session.state.settings.get("fullscreen", false))
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if want != is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want else DisplayServer.WINDOW_MODE_WINDOWED)


# ---------------------------------------------------------------- dialogs
func _open(d: ModalDialog) -> void:
	_dialog_layer.add_child(d)


func _show_intro() -> void:
	var d := ModalDialog.new("CYLINDER CLICKER", 300)
	d.add_text("Welcome to Coppertop Cylinder Works!\n\nYou have just taken on a small British hot water cylinder factory: one production line, six hand-worked stations and a van waiting at the door.")
	d.add_text("• CLICK the factory floor to work every station.\n• Finished cylinders roll to the van and earn money.\n• Spend it on upgrades and machines until the line runs itself.", UiTheme.INK_SOFT)
	d.add_button("Open the factory!", func() -> void: session.state.tutorial_step = 1)
	_open(d)


func _show_offline(summary: Dictionary) -> void:
	var d := ModalDialog.new("WELCOME BACK!", 280)
	d.add_text("You were away for %s. Your machines kept the line running." % NumFmt.duration(summary["away_seconds"]))
	d.add_text("Cylinders built:  %s\nMoney earned:  %s" % [NumFmt.number(summary["cylinders"]), NumFmt.money(summary["cash"])], UiTheme.GREEN)
	if summary["capped"]:
		d.add_text("(The factory runs unattended for up to %s.)" % NumFmt.duration(summary["counted_seconds"]), UiTheme.INK_SOFT)
	d.add_button("Lovely!", func() -> void: Sfx.play("sale"))
	_open(d)
	if session.state.tutorial_step == 0:
		session.state.tutorial_step = 1


func toggle_settings() -> void:
	if is_instance_valid(_settings_dialog):
		_settings_dialog.close()
		return
	if _dialog_layer.get_child_count() > 0:
		return
	Sfx.play("blip")
	var st := session.state
	var d := ModalDialog.new("SETTINGS", 270)
	_settings_dialog = d
	d.add_control(_slider_row("Sound effects", "sfx_volume"))
	d.add_control(_slider_row("Music", "music_volume"))
	var fs := Button.new()
	fs.focus_mode = Control.FOCUS_NONE
	fs.text = "Fullscreen: %s  (F11)" % ("ON" if bool(st.settings.get("fullscreen", false)) else "OFF")
	fs.pressed.connect(func() -> void:
		st.settings["fullscreen"] = not bool(st.settings.get("fullscreen", false))
		fs.text = "Fullscreen: %s  (F11)" % ("ON" if st.settings["fullscreen"] else "OFF")
		_apply_fullscreen())
	d.add_control(fs)
	d.add_text("Time played: %s    Clicks: %s\nTotal earned: %s\nBest output: %s cylinders/min" % [
		NumFmt.duration(st.play_seconds), NumFmt.number(st.total_clicks), NumFmt.money(st.lifetime_earned),
		NumFmt.number(st.best_rate_per_min, 1)], UiTheme.INK_SOFT)
	d.add_text("The game saves automatically every 30 seconds and when you quit.", UiTheme.INK_SOFT)
	d.add_button("Resume")
	d.add_button("Save now", func() -> void: Game.save_now(), false)
	d.add_button("Reset...", _confirm_reset)
	d.add_button("Quit", func() -> void: Game.quit_game())
	_open(d)


func _slider_row(text: String, key: String) -> Control:
	var row := HBoxContainer.new()
	var l := UiTheme.label(text)
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(session.state.settings.get(key, 0.5))
	s.custom_minimum_size = Vector2(140, 12)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(v: float) -> void:
		session.state.settings[key] = v
		Sfx.apply_settings()
		if key == "sfx_volume":
			Sfx.play("blip"))
	row.add_child(s)
	return row


func _confirm_reset() -> void:
	var d := ModalDialog.new("RESET PROGRESS?", 260)
	d.add_text("This wipes your factory, cash and upgrades and starts again from nothing. It cannot be undone.", UiTheme.RED)
	d.add_button("Keep my factory")
	d.add_button("Wipe everything", func() -> void:
		Game.reset_progress()
		get_tree().reload_current_scene())
	# Defer so the settings dialog has finished closing first.
	_open.call_deferred(d)
