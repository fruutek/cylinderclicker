class_name FactoryState
extends RefCounted
## Persistent state of one factory building. Cash is not here: it belongs to
## the company (GameState) and is shared by every factory.

var unlocked := false
var upgrade_levels: Dictionary = {}   # upgrade id -> level
var cylinders_made: float = 0.0       # every cylinder built, however it left the factory
var cylinders_sold: float = 0.0       # ...of which sold on the open market
var cylinders_contracted: float = 0.0 # ...of which built for customer contracts (made = sold + contracted)
var earned: float = 0.0               # lifetime profit made by this factory
var best_rate_per_min: float = 0.0
var line: Dictionary = {}             # work-in-progress snapshot (see ProductionLine.to_dict)


func level(id: String) -> int:
	return int(upgrade_levels.get(id, 0))


func to_dict() -> Dictionary:
	return {
		"unlocked": unlocked,
		"upgrade_levels": upgrade_levels.duplicate(),
		"cylinders_made": cylinders_made,
		"cylinders_sold": cylinders_sold,
		"cylinders_contracted": cylinders_contracted,
		"earned": earned,
		"best_rate_per_min": best_rate_per_min,
		"line": line.duplicate(true),
	}


func from_dict(d: Dictionary) -> void:
	unlocked = bool(d.get("unlocked", false))
	upgrade_levels = {}
	var levels: Variant = d.get("upgrade_levels", {})
	if typeof(levels) == TYPE_DICTIONARY:
		for k: String in levels:
			upgrade_levels[k] = maxi(0, int(levels[k]))
	cylinders_made = NumFmt.clamp_value(float(d.get("cylinders_made", 0.0)))
	# Saves from before contracts: everything built was sold.
	cylinders_contracted = maxf(NumFmt.clamp_value(float(d.get("cylinders_contracted", 0.0))), 0.0)
	cylinders_sold = NumFmt.clamp_value(float(d.get("cylinders_sold", maxf(cylinders_made - cylinders_contracted, 0.0))))
	earned = NumFmt.clamp_value(float(d.get("earned", 0.0)))
	best_rate_per_min = float(d.get("best_rate_per_min", 0.0))
	var saved_line: Variant = d.get("line", {})
	line = saved_line.duplicate(true) if typeof(saved_line) == TYPE_DICTIONARY else {}
