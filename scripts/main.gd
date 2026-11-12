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
var _pause_dialog: ModalDialog
var _save_toast: Label
var _toast_time := 0.0


func _enter_tree() -> void:
	# Theme the whole window up-front so every control is measured with the pixel font.
	get_window().theme = UiTheme.theme()
	theme = UiTheme.theme()


func _ready() -> void:
	session = Game.session
	# This node keeps running while the game is paused (so the pause menu and
	# Escape work); the factory, HUD, shop and tutorial below are pausable.
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	_hud.settings_pressed.connect(open_pause_menu)

	_tutorial = Tutorial.new()
	add_child(_tutorial)
	_tutorial.setup(session)

	var tip_layer := Control.new()
	tip_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	tip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tip_layer)
	_shop.setup(session, tip_layer)

	_dialog_layer = Control.new()
	_dialog_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dialog_layer)

	# Save feedback sits above everything, so it is readable over the pause menu.
	_save_toast = UiTheme.label("", UiTheme.CREAM)
	_save_toast.position = Vector2(6, Hud.HEIGHT + 4)
	add_child(_save_toast)
	for node: Node in [_factory_area, _shop, _hud, _tutorial]:
		node.process_mode = Node.PROCESS_MODE_PAUSABLE

	session.shipped.connect(func(_c: float, _a: float) -> void: Sfx.play("sale", 0.06, -4.0))
	session.station_finished.connect(func(_i: int) -> void: Sfx.play("thunk", 0.1, -10.0))
	Game.saved.connect(_toast.bind("Game saved", UiTheme.CREAM))
	Game.save_failed.connect(_toast.bind("SAVE FAILED - could not write the save file", Color("ff8a70")))

	Game.apply_display()
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


func _toast(text: String, color: Color) -> void:
	_save_toast.text = text
	_save_toast.add_theme_color_override("font_color", color)
	_save_toast.modulate.a = 1.0
	_toast_time = 2.5


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
			if modal_open:
				var top := _dialog_layer.get_child(_dialog_layer.get_child_count() - 1) as ModalDialog
				if top != null and top.esc_closes:
					top.close()
			else:
				open_pause_menu()
		KEY_F11:
			session.state.settings["fullscreen"] = not bool(session.state.settings.get("fullscreen", false))
			Game.apply_display()
			Game.save_settings()
		KEY_1, KEY_2, KEY_3:
			if not modal_open:
				_shop.show_tab(event.keycode - KEY_1, true)
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- dialogs
func _open(d: ModalDialog) -> void:
	_dialog_layer.add_child(d)


func _show_intro() -> void:
	var d := ModalDialog.new("CYLINDER CLICKER", 300)
	d.esc_closes = false
	d.add_text("Welcome to %s!\n\nYou have just taken on a small British hot water cylinder factory: one production line, six hand-worked stations and a van waiting at the door." % session.state.factory_name)
	d.add_text("• CLICK the factory floor to work every station.\n• Finished cylinders roll to the van and earn money.\n• Spend it on upgrades and machines until the line runs itself.", UiTheme.INK_SOFT)
	d.add_button("Open the factory!", func() -> void: session.state.tutorial_step = 1)
	_open(d)


func _show_offline(summary: Dictionary) -> void:
	var d := ModalDialog.new("WELCOME BACK!", 280)
	d.esc_closes = false
	d.add_text("You were away for %s. Your machines kept the line running." % NumFmt.duration(summary["away_seconds"]))
	d.add_text("Cylinders built:  %s\nMoney earned:  %s" % [NumFmt.number(summary["cylinders"]), NumFmt.money(summary["cash"])], UiTheme.GREEN)
	if summary["capped"]:
		d.add_text("(The factory runs unattended for up to %s.)" % NumFmt.duration(summary["counted_seconds"]), UiTheme.INK_SOFT)
	d.add_button("Lovely!", func() -> void: Sfx.play("sale"))
	_open(d)
	if session.state.tutorial_step == 0:
		session.state.tutorial_step = 1


# ------------------------------------------------------------- pause menu
func open_pause_menu() -> void:
	if _dialog_layer.get_child_count() > 0:
		return
	Sfx.play("blip")
	get_tree().paused = true   # stops the simulation, autosave timer and factory animation
	var d := ModalDialog.new("PAUSED", 210)
	_pause_dialog = d
	var name_label := d.add_text(session.state.factory_name, UiTheme.INK_SOFT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.add_menu_button("Resume Game")
	d.add_menu_button("Save Game", func() -> void: Game.save_now(), false)
	d.add_menu_button("Settings", func() -> void: _open(Dialogs.settings(true)), false)
	d.add_menu_button("Rename Factory", func() -> void:
		_open(Dialogs.name_factory("RENAME FACTORY", session.state.factory_name, "Rename", func(new_name: String) -> void:
			session.state.factory_name = new_name
			name_label.text = new_name
			_factory.queue_sign_redraw())), false)
	d.add_menu_button("Save & Return to Main Menu", func() -> void: Game.return_to_menu(), false)
	d.add_menu_button("Quit to Desktop", func() -> void: Game.quit_game(), false)
	d.closed.connect(func() -> void: get_tree().paused = false)
	_open(d)
