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
# --- stock keeping (Expansion 4)
var warehouse: Dictionary = {}        # saved Warehouse (stock, reserved, counters)
var targets: Dictionary = {}          # sku id -> stock level automatic production works towards
var priority: Array = []              # sku ids, most important first (ties in the planner)
var auto_production := true           # replenish stock towards the targets by itself
var variant := ""                    # the cylinder being made ("" = the standard one)
var bay: Dictionary = {}              # the delivery van's bay (cylinders waiting, what they are worth)
var focus_backlog := false           # build only what waiting customers need until they are served
var auto_targets := true              # keep the targets at the sales rep's recommendation
var wholesale_on := true              # surplus above target (and overflow) may go to the wholesaler
var wholesale_timer := 0.0


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
		"warehouse": warehouse.duplicate(true),
		"targets": targets.duplicate(),
		"priority": priority.duplicate(),
		"auto_production": auto_production,
		"auto_targets": auto_targets,
		"focus_backlog": focus_backlog,
		"variant": variant,
		"bay": bay.duplicate(true),
		"wholesale_on": wholesale_on,
		"wholesale_timer": wholesale_timer,
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
	var wh: Variant = d.get("warehouse", {})
	warehouse = wh.duplicate(true) if typeof(wh) == TYPE_DICTIONARY else {}
	targets = {}
	var tg: Variant = d.get("targets", {})
	if typeof(tg) == TYPE_DICTIONARY:
		for k: String in tg:
			targets[k] = maxi(int(tg[k]), 0)
	var pr: Variant = d.get("priority", [])
	priority = []
	if typeof(pr) == TYPE_ARRAY:
		for v: Variant in pr:
			priority.append(str(v))
	auto_production = bool(d.get("auto_production", true))
	auto_targets = bool(d.get("auto_targets", true))
	focus_backlog = bool(d.get("focus_backlog", false))
	variant = str(d.get("variant", ""))
	var b: Variant = d.get("bay")
	bay = (b as Dictionary).duplicate(true) if typeof(b) == TYPE_DICTIONARY else {}
	wholesale_on = bool(d.get("wholesale_on", true))
	wholesale_timer = maxf(float(d.get("wholesale_timer", 0.0)), 0.0)
