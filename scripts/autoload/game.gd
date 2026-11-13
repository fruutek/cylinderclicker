extends Node
## Autoload "Game": the thin layer between the engine and the pure-logic
## GameSession. It advances the simulation on a fixed timestep while a
## factory is open, autosaves, and moves between the main menu and the game.
## All game rules live in scripts/core - nothing here knows how anything is drawn.

const TICK := 1.0 / 60.0
const MAX_STEPS_PER_FRAME := 12
const AUTOSAVE_SECONDS := 30.0
const MENU_SCENE := "res://scenes/menu.tscn"
const GAME_SCENE := "res://scenes/main.tscn"

signal saved
signal save_failed
signal welcome_back(summary: Dictionary)   # offline earnings credited after a resume
signal back_pressed                        # Android Back button / gesture

var data: GameData
var session: GameSession
var active := false                    # true while a factory is open (not in the main menu)
var pending_offline: Dictionary = {}   # summary for the welcome-back dialog
var is_new_game := true
var save_enabled := true
var autostart := false                 # dev flag: skip the main menu
var touch_ui := false                  # phone/tablet presentation (Android, or "--touch-ui" for testing)
var clock_offset := 0.0                # test hook: pretend this many extra seconds have passed
var _paused_at := -1.0                 # when the app was sent to the background
var save_path := SaveManager.DEFAULT_PATH

var _accumulator := 0.0
var _autosave_timer := 0.0


func _ready() -> void:
	get_tree().auto_accept_quit = false
	# Dev/testing flags, passed after "--" on the command line.
	for arg in _user_args():
		if arg == "--fresh":
			save_enabled = false
		elif arg == "--autostart":
			autostart = true
		elif arg.begins_with("--save-path="):
			save_path = arg.trim_prefix("--save-path=")
		elif arg.begins_with("--clock-offset="):
			clock_offset = float(arg.trim_prefix("--clock-offset="))
		elif arg == "--touch-ui":
			touch_ui = true
			Input.emulate_touch_from_mouse = true     # lets desktop test runs drive touch scrolling
	if OS.has_feature("mobile"):
		touch_ui = true
		Engine.max_fps = 60                           # plenty for pixel art; saves battery on 120 Hz phones
		get_tree().quit_on_go_back = false            # the Back button opens the pause menu instead
	if touch_ui:
		# Phones are wider than 16:9: let the view widen to fill the screen
		# (the layout adapts) instead of adding black bars. Desktop is unchanged.
		var window := get_window()
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	UiTheme.touch = touch_ui
	data = GameData.new()
	if not data.load_all():
		push_error("Game: data files failed to load")
	session = GameSession.new(data)
	_load_settings()
	# Dev tooling: "-- --root-bot=res://tests/x.gd" attaches a script that survives scene changes.
	for arg in _user_args():
		if arg.begins_with("--root-bot="):
			get_tree().root.add_child.call_deferred((load(arg.trim_prefix("--root-bot=")) as GDScript).new())


## Dev flags. On Android they can be passed through the launch intent
## (see tests/android), where everything arrives as ordinary arguments.
func _user_args() -> PackedStringArray:
	var args := OS.get_cmdline_user_args()
	for a in OS.get_cmdline_args():
		if a.begins_with("--") and not args.has(a):
			args.append(a)
	return args


func now_unix() -> float:
	return Time.get_unix_time_from_system() + clock_offset


# --------------------------------------------------------------- settings
## Audio/display settings live in their own small file so they work from the
## main menu, before any factory is loaded.
func _settings_path() -> String:
	return save_path.get_base_dir().path_join("settings.json")


func _load_settings() -> void:
	if not save_enabled:
		return
	var stored := {}
	if FileAccess.file_exists(_settings_path()):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_settings_path()))
		if typeof(parsed) == TYPE_DICTIONARY:
			stored = parsed
	if stored.is_empty():
		# Older saves kept the settings inside the save file.
		var from_save: Variant = SaveManager.load_game(save_path).get("settings", {})
		if typeof(from_save) == TYPE_DICTIONARY:
			stored = from_save
	for k: String in stored:
		session.state.settings[k] = stored[k]


func save_settings() -> void:
	if not save_enabled:
		return
	var f := FileAccess.open(_settings_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(session.state.settings, "\t"))
		f.close()


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := bool(session.state.settings.get("fullscreen", false))
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if want != is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want else DisplayServer.WINDOW_MODE_WINDOWED)


# ------------------------------------------------------- starting / loading
func has_valid_save() -> bool:
	return save_enabled and not SaveManager.load_game(save_path).is_empty()


## Name of the saved factory, or "" if there is no usable save.
func saved_factory_name() -> String:
	if not save_enabled:
		return ""
	var st := SaveManager.load_game(save_path)
	if st.is_empty():
		return ""
	return GameState.clean_name(str(st.get("factory_name", GameState.LEGACY_FACTORY_NAME)))


## Starts a brand new factory. The previous save (if any) is replaced by the
## first save of the new game; SaveManager keeps it as the .bak file.
func start_new(factory_name: String) -> void:
	var settings := session.state.settings.duplicate()
	session.new_game()
	session.state.settings = settings
	session.state.factory_name = GameState.clean_name(factory_name)
	is_new_game = true
	pending_offline = {}
	_begin()
	save_now()


## Loads the saved factory. Returns false (and changes nothing) if the save
## is missing or unreadable.
func continue_game() -> bool:
	if not save_enabled:
		return false
	var saved_state := SaveManager.load_game(save_path)
	if saved_state.is_empty():
		return false
	var settings := session.state.settings.duplicate()
	session.load_state(saved_state)
	session.state.settings = settings
	is_new_game = false
	pending_offline = {}
	var last := session.state.last_saved_unix
	if last > 0.0:
		var away := now_unix() - last
		pending_offline = session.apply_offline(maxf(away, 0.0))   # clock moved back -> nothing
	_begin()
	return true


func _begin() -> void:
	active = true
	_accumulator = 0.0
	_autosave_timer = 0.0
	get_tree().paused = false


func enter_game_scene() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


## Saves and goes back to the main menu. Returns false if the save failed
## (the game then stays open so nothing is lost).
func return_to_menu() -> bool:
	if save_enabled and not save_now():
		return false
	active = false
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)
	return true


# ------------------------------------------------------------------- loop
func _process(delta: float) -> void:
	if not active:
		return
	_accumulator = minf(_accumulator + delta, TICK * MAX_STEPS_PER_FRAME)
	while _accumulator >= TICK:
		_accumulator -= TICK
		session.tick(TICK)
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_SECONDS:
		save_now()


func save_now() -> bool:
	_autosave_timer = 0.0
	if not save_enabled or not active:
		return false
	var ok := SaveManager.save_game(session.save_data(), save_path, now_unix())
	if ok:
		session.state.last_saved_unix = now_unix()
		saved.emit()
	else:
		save_failed.emit()
	return ok


func quit_game() -> void:
	save_now()
	save_settings()
	get_tree().quit()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			quit_game()
		NOTIFICATION_APPLICATION_PAUSED:
			_on_app_paused()
		NOTIFICATION_APPLICATION_RESUMED:
			_on_app_resumed()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			back_pressed.emit()


## Android sent the app to the background (Home, app switcher, screen off).
## The engine stops running there, and Android may kill the app without
## warning, so save now and remember the moment.
func _on_app_paused() -> void:
	save_settings()
	if not active:
		return
	save_now()
	_paused_at = now_unix()


## Back in the foreground. The factories did not run while the app was
## suspended, so credit that time exactly once through the normal offline
## rules, then save so the same period can never be credited again.
func _on_app_resumed() -> void:
	if not active or _paused_at < 0.0:
		return
	var away := maxf(now_unix() - _paused_at, 0.0)
	_paused_at = -1.0
	_accumulator = 0.0
	var summary := session.apply_offline(away)
	save_now()
	if not summary.is_empty():
		welcome_back.emit(summary)
