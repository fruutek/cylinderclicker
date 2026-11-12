class_name GameData
extends RefCounted
## Loads the data-driven definitions (stations, upgrades, products) from JSON.
## Machines are exposed as ordinary upgrades with the id "machine_<station>",
## so the shop, economy and save system treat everything uniformly.

const STATIONS_PATH := "res://data/stations.json"
const UPGRADES_PATH := "res://data/upgrades.json"
const PRODUCTS_PATH := "res://data/products.json"

var stations: Array = []          # ordered station definitions
var milestones: Array = []        # [[level, multiplier], ...]
var base_stats: Dictionary = {}
var upgrades: Array = []          # general upgrades, shop order
var machines: Array = []          # machine upgrades, line order
var upgrade_by_id: Dictionary = {}
var products: Dictionary = {}


static func load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("GameData: could not read %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameData: %s is not valid JSON" % path)
		return {}
	return parsed


func load_all() -> bool:
	var st := load_json(STATIONS_PATH)
	var up := load_json(UPGRADES_PATH)
	products = load_json(PRODUCTS_PATH)
	if st.is_empty() or up.is_empty() or products.is_empty():
		return false
	stations = st.get("stations", [])
	milestones = st.get("milestones", [])
	base_stats = up.get("base_stats", {})
	upgrades = up.get("upgrades", [])
	machines.clear()
	upgrade_by_id.clear()
	for u: Dictionary in upgrades:
		u["kind"] = "upgrade"
		upgrade_by_id[u["id"]] = u
	for i in stations.size():
		var s: Dictionary = stations[i]
		var m := {
			"id": machine_id(s["id"]),
			"kind": "machine",
			"station": s["id"],
			"station_index": i,
			"name": s["machine_name"],
			"icon": s["icon"],
			"desc": s["desc"],
			"base_cost": s["machine_cost"],
			"cost_growth": s["cost_growth"],
			"max_level": 0,
			"unlock_at": 0,
			"effects": [],
		}
		machines.append(m)
		upgrade_by_id[m["id"]] = m
	return true


static func machine_id(station_id: String) -> String:
	return "machine_" + station_id


func milestone_multiplier(level: int) -> float:
	var m := 1.0
	for pair: Array in milestones:
		if level >= int(pair[0]):
			m *= float(pair[1])
	return m


## Next milestone level above `level`, or 0 if none.
func next_milestone(level: int) -> int:
	for pair: Array in milestones:
		if level < int(pair[0]):
			return int(pair[0])
	return 0
