class_name SalesOffice
extends RefCounted
## The company's sales side: customers, telephone orders, shipments and the sales rep. Factories ask it
## what customers are waiting for; it asks factories' warehouses for stock.

## Cylinders of this SKU owed to customers (orders and contracts) that are not yet reserved.
func backlog(_factory_id: String, _sku_id: String) -> float:
	return 0.0


## How urgent that backlog is: smaller = earlier promise.
func due_rank(_factory_id: String, _sku_id: String) -> float:
	return 0.0


## Stock level the sales rep recommends for a SKU (0 = no opinion yet).
func recommended(_factory_id: String, _sku_id: String) -> int:
	return 0


## New stock has arrived: give it to whoever is waiting.
func on_stock(_factory_id: String, _sku_id: String) -> void:
	pass


## Targets are managed by the sales rep (the Stock Planner upgrade or a migrated save).
func auto_targets() -> bool:
	return false


## Unattended time passes in slices (see GameSession.apply_offline).
func offline_step(_dt: float) -> void:
	pass


## What happened in the office while the player was away ({} = nothing worth telling).
func offline_report() -> Dictionary:
	return {}
