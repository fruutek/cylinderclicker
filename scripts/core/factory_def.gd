class_name FactoryDef
extends RefCounted
## Static definition of one factory building, loaded from data/factories.json
## plus that factory's own stations and upgrades files. Adding a factory is a
## data change: a new entry in factories.json and two JSON files.

var id := ""
var index := 0
var name := ""
var short_name := ""
var description := ""
var hud_product := ""
var thumbnail := ""
var product_spec: Dictionary = {}
var unlock: Dictionary = {}       # {} = owned from the start; else {cost, requires[]}
var view: Dictionary = {}         # sprite names / sign style overrides for the factory view
var layout: Dictionary = {}
var stations: Array = []          # ordered station definitions
var milestones: Array = []        # [[level, multiplier], ...]
var base_stats: Dictionary = {}
var upgrades: Array = []          # general upgrades, shop order
var machines: Array = []          # machine upgrades, line order
var upgrade_by_id: Dictionary = {}


func load_from(entry: Dictionary, p_index: int) -> bool:
	id = entry.get("id", "")
	index = p_index
	name = entry.get("name", id)
	short_name = entry.get("short_name", name)
	description = entry.get("description", "")
	hud_product = entry.get("hud_product", "")
	thumbnail = entry.get("thumbnail", "")
	product_spec = entry.get("product", {})
	unlock = entry.get("unlock", {})
	var st := GameData.load_json(entry.get("stations_file", ""))
	var up := GameData.load_json(entry.get("upgrades_file", ""))
	if id == "" or st.is_empty() or up.is_empty():
		return false
	stations = st.get("stations", [])
	milestones = st.get("milestones", [])
	layout = st.get("layout", {})
	view = st.get("view", {})
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
			"id": GameData.machine_id(s["id"]),
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


func starts_unlocked() -> bool:
	return unlock.is_empty()


func unlock_cost() -> float:
	return float(unlock.get("cost", 0.0))


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
