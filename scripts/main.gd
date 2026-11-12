extends Control
## Root scene script: assembles the factory view, HUD, shop and dialogs and
## routes input. All nodes are created in code so the project has no fragile
## hand-edited scene files.

var company: GameSession         # the whole business (shared cash, every factory)
var session: FactorySim          # the factory currently on screen
var _factory: FactoryView
var _factory_area: Control
var _hud: Hud
var _shop: ShopPanel
var _shop_holder: Control
var _tip_layer: Control
var _flash: ColorRect
var _notified_buildable := {}
var _check_timer := 0.0
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
	company = Game.session
	session = company.current()
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

	_shop_holder = Control.new()
	_shop_holder.position = Vector2(640 - ShopPanel.WIDTH, Hud.HEIGHT)
	_shop_holder.size = Vector2(ShopPanel.WIDTH, 330)
	_shop_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shop_holder)

	_hud = Hud.new()
	add_child(_hud)
	_hud.setup(company)
	_hud.settings_pressed.connect(open_pause_menu)
	_hud.factories_pressed.connect(open_factory_overview)

	# The tutorial teaches the starting factory, so it lives there.
	_tutorial = Tutorial.new()
	add_child(_tutorial)
	_tutorial.setup(company.factories[0], company.state)

	_tip_layer = Control.new()
	_tip_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tip_layer)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_dialog_layer = Control.new()
	_dialog_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dialog_layer)

	# Save feedback sits above everything, so it is readable over the pause menu.
	_save_toast = UiTheme.label("", UiTheme.CREAM)
	_save_toast.position = Vector2(6, Hud.HEIGHT + 4)
	add_child(_save_toast)
	for node: Node in [_factory_area, _shop_holder, _hud, _tutorial]:
		node.process_mode = Node.PROCESS_MODE_PAUSABLE

	# Every factory keeps running; only the one on screen makes noise.
	for sim in company.factories:
		sim.shipped.connect(_on_factory_shipped.bind(sim))
		sim.station_finished.connect(_on_factory_station_finished.bind(sim))
	Game.saved.connect(_toast.bind("Game saved", UiTheme.CREAM))
	Game.save_failed.connect(_toast.bind("SAVE FAILED - could not write the save file", Color("ff8a70")))

	_show_factory(session)
	Game.apply_display()
	if not Game.pending_offline.is_empty():
		_show_offline(Game.pending_offline)
		Game.pending_offline = {}
	elif company.state.tutorial_step == 0:
		_show_intro()

	# Dev tooling: "-- --bot=res://tests/some_bot.gd" attaches an automation script.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bot="):
			var bot: Node = (load(arg.trim_prefix("--bot=")) as GDScript).new()
			bot.set("main", self)
			add_child(bot)


## Builds the view and shop for one factory. Only presentation is rebuilt:
## the simulation of every factory carries on untouched.
func _show_factory(sim: FactorySim) -> void:
	session = sim
	if is_instance_valid(_factory):
		_factory.queue_free()
	if is_instance_valid(_shop):
		_shop.queue_free()
	_factory = FactoryView.new()
	_factory_area.add_child(_factory)
	_factory.setup(sim, company.state)
	_shop = ShopPanel.new()
	_shop_holder.add_child(_shop)
	_shop.setup(sim, company.state, _tip_layer)
	_hud.set_factory(sim)


func switch_factory(id: String) -> bool:
	if id == company.state.current_factory or not company.set_current(id):
		return false
	_show_factory(company.current())
	return true


func _on_factory_shipped(_count: float, _amount: float, sim: FactorySim) -> void:
	if sim == session:
		Sfx.play("sale", 0.06, -4.0)


func _on_factory_station_finished(_index: int, sim: FactorySim) -> void:
	if sim == session:
		Sfx.play("thunk", 0.1, -10.0)


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_save_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
		if _toast_time <= 0.0:
			_save_toast.text = ""
	if _flash.color.a > 0.0:
		_flash.color.a = maxf(_flash.color.a - delta * 1.6, 0.0)
	# Tell the player once when a new factory becomes buildable.
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = 0.5
		for sim in company.factories:
			var id := sim.data.id
			if company.can_unlock(id) and not _notified_buildable.has(id):
				_notified_buildable[id] = true
				_toast("You can now build the %s! Open FACTORIES (F)." % sim.data.name, UiTheme.GOLD)
				_toast_time = 6.0
				Sfx.play("buy")


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
			company.state.settings["fullscreen"] = not bool(company.state.settings.get("fullscreen", false))
			Game.apply_display()
			Game.save_settings()
		KEY_F:
			if not modal_open:
				open_factory_overview()
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
	d.add_text("Welcome to %s!\n\nYou have just taken on a small British hot water cylinder factory: one production line, six hand-worked stations and a van waiting at the door." % company.state.factory_name)
	d.add_text("• CLICK the factory floor to work every station.\n• Finished cylinders roll to the van and earn money.\n• Spend it on upgrades and machines until the line runs itself.", UiTheme.INK_SOFT)
	d.add_button("Open the factory!", func() -> void: company.state.tutorial_step = 1)
	_open(d)


func _show_offline(summary: Dictionary) -> void:
	var d := ModalDialog.new("WELCOME BACK!", 280)
	d.esc_closes = false
	d.add_text("You were away for %s. Your machines kept the line running." % NumFmt.duration(summary["away_seconds"]))
	var parts: Array = summary.get("factories", [])
	if parts.size() > 1:
		var lines := ""
		for part: Dictionary in parts:
			lines += "%s:  %s cylinders,  %s\n" % [part["name"], NumFmt.number(part["cylinders"]), NumFmt.money(part["cash"])]
		d.add_text(lines.strip_edges(), UiTheme.INK_SOFT)
	d.add_text("Cylinders built:  %s\nMoney earned:  %s" % [NumFmt.number(summary["cylinders"]), NumFmt.money(summary["cash"])], UiTheme.GREEN)
	if summary["capped"]:
		d.add_text("(The factory runs unattended for up to %s.)" % NumFmt.duration(summary["counted_seconds"]), UiTheme.INK_SOFT)
	d.add_button("Lovely!", func() -> void: Sfx.play("sale"))
	_open(d)
	if company.state.tutorial_step == 0:
		company.state.tutorial_step = 1


# ------------------------------------------------------------- pause menu
func open_pause_menu() -> void:
	if _dialog_layer.get_child_count() > 0:
		return
	Sfx.play("blip")
	get_tree().paused = true   # stops the simulation, autosave timer and factory animation
	var d := ModalDialog.new("PAUSED", 210)
	_pause_dialog = d
	var name_label := d.add_text(company.state.factory_name, UiTheme.INK_SOFT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.add_menu_button("Resume Game")
	d.add_menu_button("Save Game", func() -> void: Game.save_now(), false)
	d.add_menu_button("Settings", func() -> void: _open(Dialogs.settings(true)), false)
	d.add_menu_button("Rename Factory", func() -> void:
		_open(Dialogs.name_factory("RENAME FACTORY", company.state.factory_name, "Rename", func(new_name: String) -> void:
			company.state.factory_name = new_name
			name_label.text = new_name
			_factory.queue_sign_redraw())), false)
	d.add_menu_button("Save & Return to Main Menu", func() -> void: Game.return_to_menu(), false)
	d.add_menu_button("Quit to Desktop", func() -> void: Game.quit_game(), false)
	d.closed.connect(func() -> void: get_tree().paused = false)
	_open(d)


# ------------------------------------------------------ factory navigation
func open_factory_overview() -> void:
	if _dialog_layer.get_child_count() > 0:
		return
	Sfx.play("blip")
	var d := FactoryOverview.new(company)
	d.enter_requested.connect(func(id: String) -> void:
		d.close()
		switch_factory(id))
	d.build_requested.connect(_confirm_build)
	_open(d)


func _confirm_build(id: String) -> void:
	var def: FactoryDef = company.data.factory(id)
	var cost := def.unlock_cost()
	var d := ModalDialog.new("BUILD NEW FACTORY?", 290)
	d.add_text("Build the %s for %s?" % [def.name, NumFmt.money(cost)])
	d.add_text("You have %s. After building you will have %s left to equip it." % [
		NumFmt.money(company.state.cash), NumFmt.money(company.state.cash - cost)], UiTheme.INK_SOFT)
	d.add_text("It is yours for good, and your other factories keep running while you work in it.", UiTheme.INK_SOFT)
	d.add_button("Not yet")
	d.add_button("Build it!", func() -> void: _build_factory.call_deferred(id))
	_open(d)


func _build_factory(id: String) -> void:
	if not company.unlock_factory(id):
		Sfx.play("deny")
		return
	for c in _dialog_layer.get_children():
		(c as ModalDialog).close()
	Sfx.play("fanfare")
	_toast_time = 0.01
	_flash.color.a = 0.9
	switch_factory(id)
	_factory.celebrate()
	var def: FactoryDef = company.data.factory(id)
	var d := ModalDialog.new("GRAND OPENING!", 300)
	d.esc_closes = false
	d.add_text("The %s is open for business!" % def.name, UiTheme.GREEN)
	d.add_text(def.description)
	d.add_text("\u2022 It has its own machines and upgrades - start by clicking, then automate each of its %d stations.\n\u2022 Everything it sells is paid into the same company account.\n\u2022 Your other factories carry on earning. Switch between them any time with FACTORIES (F)." % def.stations.size(), UiTheme.INK_SOFT)
	d.add_button("Cut the ribbon!", func() -> void: _factory.celebrate())
	_open.call_deferred(d)
	Game.save_now()
