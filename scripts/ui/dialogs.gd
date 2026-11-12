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
	fs.pressed.connect(func() -> void:
		st.settings["fullscreen"] = not bool(st.settings.get("fullscreen", false))
		fs.text = "Fullscreen: %s  (F11)" % ("ON" if st.settings["fullscreen"] else "OFF")
		Game.apply_display()
		Game.save_settings())
	d.add_control(fs)
	if with_stats:
		d.add_text("Time played: %s    Clicks: %s\nTotal earned: %s\nBest output: %s cylinders/min" % [
			NumFmt.duration(st.play_seconds), NumFmt.number(st.total_clicks), NumFmt.money(st.lifetime_earned),
			NumFmt.number(st.best_rate_per_min, 1)], UiTheme.INK_SOFT)
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
	s.custom_minimum_size = Vector2(140, 12)
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
	edit.custom_minimum_size = Vector2(0, 18)
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
	edit.ready.connect(edit.grab_focus)
	return d
