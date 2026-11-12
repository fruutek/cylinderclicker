class_name SaveManager
extends RefCounted
## Versioned local save files (JSON in the user data folder).
##
## * Every save carries a `version`. Older saves are upgraded step by step
##   through `_migrate`, so new fields/features never break existing saves.
## * Writes go to a temp file first and the previous save is kept as `.bak`,
##   so a crash mid-write cannot destroy progress.

const SAVE_VERSION := 2
const DEFAULT_PATH := "user://savegame.json"
const GAME_ID := "cylinder_clicker"


static func save_game(state_dict: Dictionary, path: String = DEFAULT_PATH, now_unix: float = -1.0) -> bool:
	if now_unix < 0.0:
		now_unix = Time.get_unix_time_from_system()
	state_dict["last_saved_unix"] = now_unix
	var payload := {"game": GAME_ID, "version": SAVE_VERSION, "state": state_dict}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot write %s (error %d)" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	if FileAccess.file_exists(path):
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("SaveManager: could not finalise save (error %d)" % err)
		return false
	return true


## Returns the saved state dictionary, or {} if there is no usable save.
static func load_game(path: String = DEFAULT_PATH) -> Dictionary:
	for candidate: String in [path, path + ".bak"]:
		var payload := _read(candidate)
		if payload.is_empty():
			continue
		payload = _migrate(payload)
		if payload.is_empty():
			continue
		var st: Variant = payload.get("state", {})
		if typeof(st) == TYPE_DICTIONARY and not st.is_empty():
			return st
	return {}


static func has_save(path: String = DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")


static func delete_save(path: String = DEFAULT_PATH) -> void:
	for p: String in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveManager: %s is corrupt, ignoring it" % path)
		return {}
	return parsed


## Upgrades a payload of any older version to SAVE_VERSION.
static func _migrate(payload: Dictionary) -> Dictionary:
	var version := int(payload.get("version", 0))
	if version > SAVE_VERSION:
		push_warning("SaveManager: save is from a newer game version (%d)" % version)
		return {}
	while version < SAVE_VERSION:
		match version:
			0:
				# v0 (prototype): state fields were stored at the top level.
				var st := payload.duplicate(true)
				st.erase("version")
				st.erase("game")
				payload = {"game": GAME_ID, "version": 1, "state": st}
			1:
				# v2 added factory naming and saved work-in-progress. Factories from
				# before naming keep the name that was painted on their wall sign.
				var st1: Variant = payload.get("state", {})
				if typeof(st1) != TYPE_DICTIONARY:
					return {}
				if not st1.has("factory_name"):
					st1["factory_name"] = GameState.LEGACY_FACTORY_NAME
				payload["version"] = 2
			_:
				return {}
		version = int(payload.get("version", version + 1))
	return payload
