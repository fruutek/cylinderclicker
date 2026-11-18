class_name SaveManager
extends RefCounted
## Versioned local save files (JSON in the user data folder).
##
## * Every save carries a `version`. Older saves are upgraded step by step
##   through `_migrate`, so new fields/features never break existing saves.
## * Writes go to a temp file first and the previous save is kept as `.bak`,
##   so a crash mid-write cannot destroy progress.

const SAVE_VERSION := 7
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
			2:
				# v3 introduced multiple factories. Everything that used to describe
				# "the factory" becomes the copper factory; cash stays company-wide.
				var st2: Variant = payload.get("state", {})
				if typeof(st2) != TYPE_DICTIONARY:
					return {}
				var copper := {
					"unlocked": true,
					"upgrade_levels": st2.get("upgrade_levels", {}),
					"cylinders_made": st2.get("cylinders_made", 0.0),
					"earned": st2.get("lifetime_earned", 0.0),
					"best_rate_per_min": st2.get("best_rate_per_min", 0.0),
					"line": st2.get("line", {}),
				}
				for old_key: String in ["upgrade_levels", "cylinders_made", "best_rate_per_min", "line", "current_product"]:
					st2.erase(old_key)
				st2["factories"] = {"copper": copper}
				st2["current_factory"] = "copper"
				payload["version"] = 3
			3:
				# v4 added trade contracts, reputation and dispatch. Nothing about the
				# factories changes; the contract book simply starts empty and fills
				# itself once the company has earned enough.
				var st3: Variant = payload.get("state", {})
				if typeof(st3) != TYPE_DICTIONARY:
					return {}
				if not st3.has("contracts"):
					st3["contracts"] = {}
				payload["version"] = 4
			4:
				# v5 added the warehouse, SKUs, customers and telephone orders. Existing factories,
				# upgrades, money and contracts are untouched; the game switches to stock keeping and
				# GameSession grants a stock room sized to each factory (see _apply_stock_migration).
				var st4: Variant = payload.get("state", {})
				if typeof(st4) != TYPE_DICTIONARY:
					return {}
				if not st4.has("stock_mode"):
					st4["stock_mode"] = true
					st4["stock_migrate"] = true
				if not st4.has("sales"):
					st4["sales"] = {}
				payload["version"] = 5
			5:
				# v6 is the classic game: cylinder variants, the delivery van and bonus orders. The warehouse and the
				# old contract/customer systems are retired; GameSession converts their leftovers into cash when
				# the save is loaded (nothing is lost), everything else is untouched.
				var st5: Variant = payload.get("state", {})
				if typeof(st5) != TYPE_DICTIONARY:
					return {}
				payload["version"] = 6
			6:
				# v7 gave dispatch real limits: a finite pad, a carrying capacity for the van, and queues that
				# back up. The pad and van contents in `bay` keep their meaning (an old pad that holds more than
				# the new limit keeps everything and just refuses more), and the three dispatch upgrades take
				# their levels from the old van upgrades. Nothing needs converting.
				var st6: Variant = payload.get("state", {})
				if typeof(st6) != TYPE_DICTIONARY:
					return {}
				payload["version"] = 7
			_:
				return {}
		version = int(payload.get("version", version + 1))
	return payload


# ----------------------------------------------------------- save transfer
const TRANSFER_PREFIX := "CYLSAVE1:"


## Packs the current save into a short text code that can be copied between
## devices (for example from Windows to a phone). Returns "" if there is no save.
static func export_code(path: String = DEFAULT_PATH) -> String:
	var st := load_game(path)
	if st.is_empty():
		return ""
	var raw := JSON.stringify({"game": GAME_ID, "version": SAVE_VERSION, "state": st}).to_utf8_buffer()
	return "%s%d:%s" % [TRANSFER_PREFIX, raw.size(), Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_GZIP))]


## Reads a transfer code. Returns the (migrated) state, or {} if the text is
## not a valid Cylinder Clicker save code.
static func decode_code(code: String) -> Dictionary:
	code = code.strip_edges().replace("\n", "").replace("\r", "").replace(" ", "")
	if not code.begins_with(TRANSFER_PREFIX):
		return {}
	var rest := code.trim_prefix(TRANSFER_PREFIX)
	var sep := rest.find(":")
	if sep <= 0 or not rest.substr(0, sep).is_valid_int():
		return {}
	var size := int(rest.substr(0, sep))
	if size <= 0 or size > 4000000:
		return {}
	var packed := Marshalls.base64_to_raw(rest.substr(sep + 1))
	if packed.is_empty():
		return {}
	var raw := packed.decompress(size, FileAccess.COMPRESSION_GZIP)
	if raw.size() != size:
		return {}
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or parsed.get("game", "") != GAME_ID:
		return {}
	var payload := _migrate(parsed)
	var st: Variant = payload.get("state", {})
	if typeof(st) != TYPE_DICTIONARY or st.is_empty():
		return {}
	return st


## Replaces the save with the one in `code`. The previous save is kept as the
## .bak file. Returns false (changing nothing) if the code is invalid.
static func import_code(code: String, path: String = DEFAULT_PATH) -> bool:
	var st := decode_code(code)
	if st.is_empty():
		return false
	return save_game(st, path, float(st.get("last_saved_unix", 0.0)))
