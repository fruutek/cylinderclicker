class_name GameData
extends RefCounted
## Loads the data-driven definitions: the list of factories (each with its
## own stations and upgrades) and the shared product catalogue.
## Machines are exposed as ordinary upgrades with the id "machine_<station>",
## so the shop, economy and save system treat everything uniformly.

const FACTORIES_PATH := "res://data/factories.json"
const PRODUCTS_PATH := "res://data/products.json"

var factories: Array[FactoryDef] = []
var factory_by_id: Dictionary = {}
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
	products = load_json(PRODUCTS_PATH)
	var raw := load_json(FACTORIES_PATH)
	if products.is_empty() or raw.is_empty():
		return false
	factories.clear()
	factory_by_id.clear()
	for entry: Dictionary in raw.get("factories", []):
		var def := FactoryDef.new()
		if not def.load_from(entry, factories.size()):
			push_error("GameData: factory '%s' failed to load" % entry.get("id", "?"))
			return false
		factories.append(def)
		factory_by_id[def.id] = def
	return not factories.is_empty()


func factory(id: String) -> FactoryDef:
	return factory_by_id.get(id)


static func machine_id(station_id: String) -> String:
	return "machine_" + station_id
