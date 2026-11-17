class_name StockPort
extends RefCounted
## The contract book's view of the warehouses: it can ask how much stock there is and reserve, release or
## ship it, but knows nothing about factories or nodes. GameSession fills `sims` (factory id -> FactorySim).

var sims: Dictionary = {}


func has_stock(factory_id: String) -> bool:
	var sim: FactorySim = sims.get(factory_id)
	return sim != null and sim.stock_enabled()


func available(factory_id: String, sku: String) -> int:
	var sim: FactorySim = sims.get(factory_id)
	return sim.warehouse.available(sku) if sim != null else 0


func reserve(factory_id: String, sku: String, n: int) -> int:
	var sim: FactorySim = sims.get(factory_id)
	return sim.warehouse.reserve(sku, n) if sim != null else 0


func release(factory_id: String, sku: String, n: int) -> int:
	var sim: FactorySim = sims.get(factory_id)
	if sim == null:
		return 0
	var r := sim.warehouse.release(sku, n)
	sim.planner_wake()
	return r


## The lorry has left: the cylinders go for good. Returns how many left.
func ship(factory_id: String, sku: String, n: int) -> int:
	var sim: FactorySim = sims.get(factory_id)
	if sim == null:
		return 0
	var r := sim.warehouse.ship(sku, n)
	sim.state.cylinders_sold += float(r)
	sim.planner_wake()
	return r


## Net profit of one cylinder of this SKU at today's list price.
func unit_profit(factory_id: String, sku: String) -> float:
	var sim: FactorySim = sims.get(factory_id)
	if sim == null:
		return 0.0
	var i := sim.sku_index(sku)
	return sim.sku_profit(i) if i >= 0 else sim.profit_per_cylinder()


## Shelf space left at a factory (cylinders), so the book can unblock a line that is full of reserved stock.
func free_space(factory_id: String) -> float:
	var sim: FactorySim = sims.get(factory_id)
	return sim.warehouse.free_space() if sim != null else 0.0
