extends Node
## Autoload "Game": the thin layer between the engine and the pure-logic
## GameSession. It advances the simulation on a fixed timestep, autosaves,
## and applies offline progress on start-up. All game rules live in
## scripts/core - nothing here knows how anything is drawn.

const TICK := 1.0 / 60.0
const MAX_STEPS_PER_FRAME := 12
const AUTOSAVE_SECONDS := 30.0

signal saved

var data: GameData
var session: GameSession
var pending_offline: Dictionary = {}   # summary for the welcome-back dialog
var is_new_game := true
var save_enabled := true
var save_path := SaveManager.DEFAULT_PATH

var _accumulator := 0.0
var _autosave_timer := 0.0


func _ready() -> void:
	get_tree().auto_accept_quit = false
	# Dev/testing flags, passed after "--" on the command line.
	for arg in OS.get_cmdline_user_args():
		if arg == "--fresh":
			save_enabled = false
		elif arg.begins_with("--save-path="):
			save_path = arg.trim_prefix("--save-path=")
	data = GameData.new()
	if not data.load_all():
		push_error("Game: data files failed to load")
	session = GameSession.new(data)
	_load()


func _load() -> void:
	if not save_enabled:
		return
	var saved_state := SaveManager.load_game(save_path)
	if saved_state.is_empty():
		return
	is_new_game = false
	session.load_state(saved_state)
	var last := session.state.last_saved_unix
	if last > 0.0:
		var away := Time.get_unix_time_from_system() - last
		pending_offline = session.apply_offline(maxf(away, 0.0))   # clock moved back -> nothing


func _process(delta: float) -> void:
	_accumulator = minf(_accumulator + delta, TICK * MAX_STEPS_PER_FRAME)
	while _accumulator >= TICK:
		_accumulator -= TICK
		session.tick(TICK)
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_SECONDS:
		save_now()


func save_now() -> bool:
	_autosave_timer = 0.0
	if not save_enabled:
		return false
	var ok := SaveManager.save_game(session.state.to_dict(), save_path)
	if ok:
		saved.emit()
	return ok


func reset_progress() -> void:
	var settings := session.state.settings.duplicate()
	SaveManager.delete_save(save_path)
	session.new_game()
	session.state.settings = settings
	is_new_game = true
	pending_offline = {}
	save_now()


func quit_game() -> void:
	save_now()
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		save_now()
