class_name ProductCatalog
extends RefCounted
## Modular product system: a product is material + range + variants, and its
## numbers are derived by multiplying the parts together. Nothing about a
## specific combination is hard-coded.

var _materials := {}
var _ranges := {}
var _variants := {}
var _raw: Dictionary


func _init(products: Dictionary) -> void:
	_raw = products
	for m: Dictionary in products.get("materials", []):
		_materials[m["id"]] = m
	for r: Dictionary in products.get("ranges", []):
		_ranges[r["id"]] = r
	for v: Dictionary in products.get("variants", []):
		_variants[v["id"]] = v


func starting_product() -> Dictionary:
	return _raw.get("starting_product", {"material": "copper", "range": "standard", "variants": []}).duplicate(true)


func materials() -> Array:
	return _raw.get("materials", [])


func ranges() -> Array:
	return _raw.get("ranges", [])


func variants() -> Array:
	return _raw.get("variants", [])


func is_valid(spec: Dictionary) -> bool:
	if not _materials.has(spec.get("material", "")) or not _ranges.has(spec.get("range", "")):
		return false
	for v: Variant in spec.get("variants", []):
		if not _variants.has(v):
			return false
	return true


## Returns {name, value, material_cost, manufacturing_cost, work_mult} for a product spec.
func compose(spec: Dictionary) -> Dictionary:
	if not is_valid(spec):
		spec = starting_product()
	var mat: Dictionary = _materials[spec["material"]]
	var rng: Dictionary = _ranges[spec["range"]]
	var value := float(mat["value"]) * float(rng["value_mult"])
	var cost := float(mat["material_cost"]) * float(rng["cost_mult"])
	var work := float(mat["work_mult"]) * float(rng["work_mult"])
	var making := float(mat.get("manufacturing_cost", 0.0)) * float(rng["cost_mult"])
	var prefix := ""
	for vid: String in spec.get("variants", []):
		var v: Dictionary = _variants[vid]
		value *= float(v["value_mult"])
		cost *= float(v["cost_mult"])
		making *= float(v["cost_mult"])
		work *= float(v["work_mult"])
		prefix += String(v["name"]) + " "
	return {
		"name": "%s%s %s" % [prefix, mat["name"], rng["name"]],
		"value": value,
		"material_cost": cost,
		"manufacturing_cost": making,
		"work_mult": work,
	}
