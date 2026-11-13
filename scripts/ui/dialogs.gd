class_name Dialogs
extends RefCounted
## Dialogs shared by the main menu and the in-game pause menu.


## Audio and display settings. `with_stats` adds the factory statistics
## (only meaningful while a factory is open).
static func settings(with_stats: bool) -> ModalDialog:
	var st: GameState = Game.session.state
	var d := ModalDialog.new("SETTINGS", 270)
	d.add_control(_slider_row("Sound effects", "sfx_volume"))
	d.add_control(_slider_row("Music", "music_volume"))
	var fs := Button.new()
	fs.focus_mode = Control.FOCUS_NONE
	fs.text = "Fullscreen: %s  (F11)" % ("ON" if bool(st.settings.get("fullscreen", false)) else "OFF")
	fs.custom_minimum_size = Vector2(0, UiTheme.button_height())
	fs.visible = not OS.has_feature("mobile")      # phones are always fullscreen
	fs.pressed.connect(func() -> void:
		st.settings["fullscreen"] = not bool(st.settings.get("fullscreen", false))
		fs.text = "Fullscreen: %s  (F11)" % ("ON" if st.settings["fullscreen"] else "OFF")
		Game.apply_display()
		Game.save_settings())
	d.add_control(fs)
	if with_stats:
		d.add_text("Time played: %s    Clicks: %s\nTotal earned: %s\nBest output: %s cylinders/min" % [
			NumFmt.duration(st.play_seconds), NumFmt.number(st.total_clicks), NumFmt.money(st.lifetime_earned),
			NumFmt.number(Game.session.current().state.best_rate_per_min, 1)], UiTheme.INK_SOFT)
		d.add_text("The game saves automatically every 30 seconds and when you quit.", UiTheme.INK_SOFT)
	d.add_button("Done")
	d.closed.connect(Game.save_settings)
	return d


static func _slider_row(text: String, key: String) -> Control:
	var st: GameState = Game.session.state
	var row := HBoxContainer.new()
	var l := UiTheme.label(text)
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(st.settings.get(key, 0.5))
	s.custom_minimum_size = Vector2(140, 22 if UiTheme.touch else 12)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(v: float) -> void:
		st.settings[key] = v
		Sfx.apply_settings()
		if key == "sfx_volume":
			Sfx.play("blip"))
	row.add_child(s)
	return row


## Asks for a factory name. `on_confirm` receives the cleaned, non-blank name.
static func name_factory(title: String, initial: String, confirm_text: String, on_confirm: Callable) -> ModalDialog:
	var d := ModalDialog.new(title, 250)
	d.add_text("What is your factory called?")
	var edit := LineEdit.new()
	edit.text = initial
	edit.max_length = GameState.MAX_NAME_LENGTH
	edit.select_all_on_focus = true
	edit.caret_blink = true
	edit.context_menu_enabled = false
	edit.custom_minimum_size = Vector2(0, UiTheme.button_height())
	d.add_control(edit)
	d.add_text("Up to %d letters, numbers and symbols. It appears on the sign above the factory floor." % GameState.MAX_NAME_LENGTH, UiTheme.INK_SOFT)
	var ok := d.add_button(confirm_text, func() -> void: on_confirm.call(GameState.clean_name(edit.text)))
	d.add_button("Cancel")
	edit.text_changed.connect(func(t: String) -> void:
		# Drop anything the pixel font cannot draw; blank names cannot be confirmed.
		var cleaned := ""
		for i in t.length():
			var code := t.unicode_at(i)
			if code >= 32 and code <= 126:
				cleaned += t[i]
		if cleaned != t:
			var caret := edit.caret_column
			edit.text = cleaned
			edit.caret_column = mini(caret, cleaned.length())
		ok.disabled = cleaned.strip_edges().is_empty())
	edit.text_submitted.connect(func(_t: String) -> void:
		if not ok.disabled:
			ok.pressed.emit())
	if UiTheme.touch:
		d.align_top()      # keep clear of the on-screen keyboard
	edit.ready.connect(edit.grab_focus)
	return d


## Moves a save between devices as a text code on the clipboard (for example
## from the Windows game to a phone). `on_imported` runs after a successful import.
static func transfer_save(on_imported: Callable) -> ModalDialog:
	var d := ModalDialog.new("TRANSFER SAVE", 310)
	d.add_text("Move your factory to another device, for example from your PC to your phone:")
	d.add_text("1. On the old device press COPY SAVE CODE.\n2. Paste the code into an email or message to yourself.\n3. On the new device copy that code, open this screen and press PASTE SAVE CODE.", UiTheme.INK_SOFT)
	var status := d.add_text("", UiTheme.GREEN)
	var copy := d.add_button("Copy save code", func() -> void:
		var code := SaveManager.export_code(Game.save_path)
		if code == "":
			status.text = "There is no saved factory on this device yet."
			status.add_theme_color_override("font_color", UiTheme.RED)
		else:
			DisplayServer.clipboard_set(code)
			status.text = "Copied! The code is on your clipboard (%d characters)." % code.length()
			status.add_theme_color_override("font_color", UiTheme.GREEN), false)
	copy.disabled = not Game.has_valid_save()
	d.add_button("Paste save code", func() -> void:
		var code := DisplayServer.clipboard_get()
		var st := SaveManager.decode_code(code)
		if st.is_empty():
			status.text = "The clipboard does not hold a Cylinder Clicker save code. Copy the whole code and try again."
			status.add_theme_color_override("font_color", UiTheme.RED)
			return
		var incoming := GameState.clean_name(str(st.get("factory_name", "")))
		var confirm := ModalDialog.new("IMPORT THIS SAVE?", 280)
		confirm.add_text("Found: \"%s\" with %s in the bank." % [incoming, NumFmt.money(float(st.get("cash", 0.0)))])
		var existing := Game.saved_factory_name()
		if existing != "":
			confirm.add_text("It will replace the factory saved on this device (\"%s\")." % existing, UiTheme.RED)
		confirm.add_button("Cancel")
		confirm.add_button("Import", func() -> void:
			if SaveManager.import_code(code, Game.save_path):
				status.text = "Imported \"%s\". Press Continue to play." % incoming
				status.add_theme_color_override("font_color", UiTheme.GREEN)
				copy.disabled = false
				on_imported.call()
			else:
				status.text = "Could not write the save file."
				status.add_theme_color_override("font_color", UiTheme.RED))
		d.get_parent().add_child(confirm), false)
	d.add_button("Close")
	return d
