class_name SkuCatalog
extends RefCounted
## Every stock-keeping unit the company can make (data/skus.json). A SKU belongs to one factory and
## is a variant of that factory's base product, so nothing here names copper or stainless: new
## products are new entries. Index = position among that factory's SKUs (what a belt token carries).

var cfg: Dictionary = {}
var all: Array[Dictionary] = []
var by_id: Dictionary = {}
var _by_factory: Dictionary = {}


func _init(raw: Dictionary = {}) -> void:
	cfg = raw.get("warehouse", {})
	for s: Dictionary in raw.get("skus", []):
		var sku := s.duplicate(true)
		var list: Array = _by_factory.get(sku["factory"], [])
		sku["index"] = list.size()
		list.append(sku)
		_by_factory[sku["factory"]] = list
		all.append(sku)
		by_id[sku["id"]] = sku


func enabled() -> bool:
	return not all.is_empty()


func num(key: String, fallback: float = 0.0) -> float:
	return float(cfg.get(key, fallback))


func for_factory(factory_id: String) -> Array:
	return _by_factory.get(factory_id, [])


func get_sku(id: String) -> Dictionary:
	return by_id.get(id, {})


## The base SKU of a factory (the one that is exactly its original product).
func baseline(factory_id: String) -> Dictionary:
	var list: Array = for_factory(factory_id)
	return list[0] if not list.is_empty() else {}
