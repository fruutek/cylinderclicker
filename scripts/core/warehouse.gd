class_name Warehouse
extends RefCounted
## One factory's stock room. Integer stock per SKU with a reserved part (promised to a customer or
## contract) and an available part, a fixed capacity, and counters that make every cylinder
## traceable:   made = stock + shipped + wholesaled + fraction carried + still on the line.
## It never goes negative, never reserves more than it holds and never stores past its capacity
## (cylinders that arrive with no room are returned to the caller as overflow, never deleted).

var stock: Dictionary = {}          # sku id -> whole cylinders on the shelves
var reserved: Dictionary = {}       # sku id -> of which promised to someone
var frac: Dictionary = {}           # sku id -> part of a cylinder built but not yet a whole one
var made: Dictionary = {}           # sku id -> cylinders ever built into this warehouse
var shipped: Dictionary = {}        # sku id -> sent to customers (orders and contracts)
var wholesaled: Dictionary = {}     # sku id -> sold to the wholesaler (surplus and overflow)
var overflowed: Dictionary = {}     # sku id -> arrived with no room (all of these were wholesaled)
var wip: Dictionary = {}            # sku id -> cylinders on the line (not saved: rebuilt from the belt)
var space: Dictionary = {}          # sku id -> shelf space one cylinder takes (set by the factory)
var capacity := 24                  # set by the factory from its upgrades


func total(sku: String) -> int:
	return int(stock.get(sku, 0))


func reserved_units(sku: String) -> int:
	return int(reserved.get(sku, 0))


func available(sku: String) -> int:
	return maxi(total(sku) - reserved_units(sku), 0)


func space_of(sku: String) -> float:
	return float(space.get(sku, 1.0))


func used_space() -> float:
	var used := 0.0
	for sku: String in stock:
		used += float(stock[sku]) * space_of(sku)
	return used


func wip_space() -> float:
	var w := 0.0
	for sku: String in wip:
		w += float(wip[sku]) * space_of(sku)
	return w


func free_space() -> float:
	return float(capacity) - used_space() - wip_space()


func usage_fraction() -> float:
	return clampf(used_space() / maxf(float(capacity), 1.0), 0.0, 1.0)


## Whole cylinders of this SKU that could still be put on the shelves right now (ignores the line).
func shelf_room(sku: String) -> int:
	return maxi(int(floorf((float(capacity) - used_space()) / space_of(sku) + 1e-9)), 0)


## Whether a batch of cylinders may start on the line: there must be room for it once it arrives.
func can_load(sku: String, count: float) -> bool:
	return free_space() >= count * space_of(sku) - 1e-9


func total_units() -> int:
	var n := 0
	for sku: String in stock:
		n += int(stock[sku])
	return n


## Builds `count` cylinders into stock. Returns how many whole cylinders had no room (the caller
## must sell them through the wholesaler - nothing is thrown away).
func receive(sku: String, count: float) -> int:
	made[sku] = float(made.get(sku, 0.0)) + count
	frac[sku] = float(frac.get(sku, 0.0)) + count
	var whole := int(floorf(float(frac[sku]) + 1e-9))
	frac[sku] = maxf(float(frac[sku]) - float(whole), 0.0)
	var stored := mini(whole, shelf_room(sku))
	stock[sku] = total(sku) + stored
	var overflow := whole - stored
	if overflow > 0:
		overflowed[sku] = int(overflowed.get(sku, 0)) + overflow
	return overflow


## Puts the cylinders asked for aside for a customer. Returns how many were actually reserved.
func reserve(sku: String, n: int) -> int:
	var n_ok := clampi(n, 0, available(sku))
	reserved[sku] = reserved_units(sku) + n_ok
	return n_ok


func release(sku: String, n: int) -> int:
	var n_ok := clampi(n, 0, reserved_units(sku))
	reserved[sku] = reserved_units(sku) - n_ok
	return n_ok


## Sends reserved cylinders out on a lorry. Returns how many left.
func ship(sku: String, n: int) -> int:
	var n_ok := clampi(n, 0, mini(reserved_units(sku), total(sku)))
	reserved[sku] = reserved_units(sku) - n_ok
	stock[sku] = total(sku) - n_ok
	shipped[sku] = int(shipped.get(sku, 0)) + n_ok
	return n_ok


## Sells surplus (unreserved) stock to the wholesaler. Returns how many went.
func sell_wholesale(sku: String, n: int) -> int:
	var n_ok := clampi(n, 0, available(sku))
	stock[sku] = total(sku) - n_ok
	wholesaled[sku] = int(wholesaled.get(sku, 0)) + n_ok
	return n_ok


## Cylinders that arrived with no room and went straight to the wholesaler.
func note_overflow_sale(sku: String, n: int) -> void:
	wholesaled[sku] = int(wholesaled.get(sku, 0)) + n


## Hand-over from the old counters (a migrated save): cylinders that already exist.
func add_existing(sku: String, n: int, reserve_them: bool = false) -> void:
	made[sku] = float(made.get(sku, 0.0)) + float(n)
	stock[sku] = total(sku) + n
	if reserve_them:
		reserved[sku] = reserved_units(sku) + n


## "" if every rule holds, otherwise what is wrong (used by the tests and the debug overlay).
func validate(allow_over_capacity: bool = false) -> String:
	for sku: String in stock:
		if int(stock[sku]) < 0:
			return "negative stock of %s" % sku
		if reserved_units(sku) < 0 or reserved_units(sku) > total(sku):
			return "reserved %d of %s but only %d in stock" % [reserved_units(sku), sku, total(sku)]
	for sku: String in made:
		var left := float(made[sku]) - (float(total(sku)) + float(shipped.get(sku, 0)) + float(wholesaled.get(sku, 0)) + float(frac.get(sku, 0.0)))
		if absf(left) > 1e-6:
			return "%s does not add up: made %s, accounted for %s" % [sku, made[sku], float(made[sku]) - left]
	if not allow_over_capacity and used_space() > float(capacity) + 1e-6:
		return "over capacity: %s of %d" % [used_space(), capacity]
	return ""


func to_dict() -> Dictionary:
	return {"stock": stock.duplicate(), "reserved": reserved.duplicate(), "frac": frac.duplicate(), "made": made.duplicate(),
		"shipped": shipped.duplicate(), "wholesaled": wholesaled.duplicate(), "overflowed": overflowed.duplicate()}


func from_dict(d: Dictionary) -> void:
	stock = _ints(d.get("stock"))
	reserved = _ints(d.get("reserved"))
	frac = _floats(d.get("frac"))
	made = _floats(d.get("made"))
	shipped = _ints(d.get("shipped"))
	wholesaled = _ints(d.get("wholesaled"))
	overflowed = _ints(d.get("overflowed"))
	for sku: String in reserved.keys():       # a damaged save can never reserve more than exists
		reserved[sku] = clampi(int(reserved[sku]), 0, total(sku))
	for sku: String in stock.keys():
		made[sku] = maxf(float(made.get(sku, 0.0)), float(total(sku)) + float(shipped.get(sku, 0)) + float(wholesaled.get(sku, 0)) + float(frac.get(sku, 0.0)))


static func _ints(v: Variant) -> Dictionary:
	var out := {}
	if typeof(v) == TYPE_DICTIONARY:
		for k: String in v:
			out[k] = maxi(int(v[k]), 0)
	return out


static func _floats(v: Variant) -> Dictionary:
	var out := {}
	if typeof(v) == TYPE_DICTIONARY:
		for k: String in v:
			out[k] = maxf(float(v[k]), 0.0)
	return out
