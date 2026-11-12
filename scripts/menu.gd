extends Control
## Main menu: New Game, Continue, Settings, Quit. Uses the same theme,
## dialogs and art as the game so it feels like part of the factory.

var _continue: Button
var _continue_note: Label
var _dialog_layer: Control


func _enter_tree() -> void:
	get_window().theme = UiTheme.theme()
	theme = UiTheme.theme()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Game.apply_display()

	# Backdrop: the factory floor, dimmed, inside a wooden frame.
	var frame := ColorRect.new()
	frame.color = UiTheme.WOOD
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	var floor_art := TextureRect.new()
	floor_art.texture = preload("res://assets/sprites/factory_bg.png")
	floor_art.position = Vector2(98, 15)
	floor_art.modulate = Color(0.55, 0.5, 0.52)
	add_child(floor_art)
	var border := Panel.new()
	border.add_theme_stylebox_override("panel", UiTheme.flat(Color(0, 0, 0, 0), UiTheme.WOOD_DARK, 2, 0))
	border.position = Vector2(96, 13)
	border.size = Vector2(448, 334)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)

	var title_shadow := UiTheme.label("CYLINDER CLICKER", UiTheme.OUTLINE, 32)
	title_shadow.position = Vector2(0, 84)
	title_shadow.size = Vector2(640, 40)
	title_shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title_shadow)
	var title := UiTheme.label("CYLINDER CLICKER", UiTheme.GOLD, 32)
	title.position = Vector2(0, 81)
	title.size = Vector2(640, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var tagline := UiTheme.label("A cosy hot water cylinder factory", UiTheme.CREAM)
	tagline.position = Vector2(0, 122)
	tagline.size = Vector2(640, 12)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(tagline)

	var panel := PanelContainer.new()
	var sb := UiTheme.flat(UiTheme.PARCH, UiTheme.WOOD_DARK, 2, 8)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(2, 3)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(230, 150)
	panel.custom_minimum_size = Vector2(180, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	_menu_button(box, "New Game", _on_new_game)
	_continue = _menu_button(box, "Continue", _on_continue)
	_continue_note = UiTheme.label("", UiTheme.INK_SOFT)
	_continue_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_continue_note)
	_menu_button(box, "Settings", func() -> void: _open(Dialogs.settings(false)))
	_menu_button(box, "Quit Game", func() -> void: Game.quit_game())

	var version := UiTheme.label("v" + str(ProjectSettings.get_setting("application/config/version", "")), UiTheme.PARCH_DARK)
	version.position = Vector2(6, 348)
	add_child(version)

	_dialog_layer = Control.new()
	_dialog_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dialog_layer)

	_refresh_continue()

	if Game.autostart:   # dev flag: go straight into a factory
		if not Game.continue_game():
			Game.start_new(GameState.DEFAULT_FACTORY_NAME)
		Game.enter_game_scene.call_deferred()


func _menu_button(box: Container, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 20)
	b.pressed.connect(func() -> void:
		Sfx.play("blip")
		action.call())
	box.add_child(b)
	return b


func _refresh_continue() -> void:
	var saved_name := Game.saved_factory_name()
	_continue.disabled = saved_name.is_empty()
	_continue_note.text = saved_name if not saved_name.is_empty() else "No saved factory yet"


func _open(d: ModalDialog) -> void:
	_dialog_layer.add_child(d)


func _on_new_game() -> void:
	var saved_name := Game.saved_factory_name()
	if saved_name.is_empty():
		_ask_name()
		return
	var d := ModalDialog.new("START AGAIN?", 270)
	d.add_text("You already have a saved factory:\n\"%s\"\n\nStarting a new game replaces it. Its cash, upgrades and machines will be lost." % saved_name, UiTheme.RED)
	d.add_button("Keep my factory")
	d.add_button("Start a new one", func() -> void: _ask_name.call_deferred())
	_open(d)


func _ask_name() -> void:
	_open(Dialogs.name_factory("NAME YOUR FACTORY", GameState.DEFAULT_FACTORY_NAME, "Open the factory", func(factory_name: String) -> void:
		Game.start_new(factory_name)
		Game.enter_game_scene()))


func _on_continue() -> void:
	if Game.continue_game():
		Game.enter_game_scene()
		return
	var d := ModalDialog.new("SAVE NOT FOUND", 250)
	d.add_text("The saved factory could not be loaded. It may have been moved or damaged.")
	d.add_button("OK")
	_open(d)
	_refresh_continue()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE and _dialog_layer.get_child_count() > 0:
		var top := _dialog_layer.get_child(_dialog_layer.get_child_count() - 1) as ModalDialog
		if top != null and top.esc_closes:
			top.close()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F11:
		var settings: Dictionary = Game.session.state.settings
		settings["fullscreen"] = not bool(settings.get("fullscreen", false))
		Game.apply_display()
		Game.save_settings()
