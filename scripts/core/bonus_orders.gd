class_name BonusOrders
extends RefCounted
## Occasional optional bonus orders - the whole "customer" side of the classic game. A customer wants some
## cylinders of a product the player can make; ACCEPT (one button) and the factory switches to that product
## by itself; when the last one is made the delivery van collects a bonus on top of the normal sales.
## An ignored offer simply goes away. No negotiation, no allocation, no penalty, no stock.

signal offered(order: Dictionary)
signal accepted(order: Dictionary)
signal completed(order: Dictionary, bonus: float)
signal expired(order: Dictionary)

var cfg: Dictionary = {}
var enabled := false
var offer: Dictionary = {}
var active: Dictionary = {}
var timer := 120.0
var serial := 0
var done := 0
var seed_value := 1
var sims: Dictionary = {}               # factory id -> FactorySim (set by the session)


func _init(raw: Dictionary = {}) -> void:
	cfg = raw
	enabled = not raw.is_empty() and not (raw.get("names", []) as Array).is_empty()
	timer = float(raw.get("first_offer_seconds", 120.0))


func num(key: String, fallback: float = 0.0) -> float:
	return float(cfg.get(key, fallback))


func reset(p_seed: int = -1) -> void:
	seed_value = p_seed if p_seed >= 0 else int(randi() & 0x7fffffff)
	offer = {}
	active = {}
	timer = num("first_offer_seconds", 120.0)
	serial = 0
	done = 0


func to_dict() -> Dictionary:
	return {"offer": offer.duplicate(true), "active": active.duplicate(true), "timer": timer, "serial": serial, "done": done, "seed": seed_value}


func from_dict(d: Dictionary) -> void:
	reset(int(d.get("seed", -1)) if d.has("seed") else -1)
	if d.is_empty():
		return
	timer = clampf(float(d.get("timer", timer)), 0.0, 3600.0)
	serial = maxi(int(d.get("serial", 0)), 0)
	done = maxi(int(d.get("done", 0)), 0)
	for key: String in ["offer", "active"]:
		var o: Variant = d.get(key)
		if typeof(o) == TYPE_DICTIONARY and (o as Dictionary).has("variant") and (o as Dictionary).has("qty") and sims.has(str((o as Dictionary).get("factory", ""))):
			var clean: Dictionary = (o as Dictionary).duplicate(true)
			clean["qty"] = maxi(int(clean["qty"]), 1)
			clean["made"] = clampf(float(clean.get("made", 0.0)), 0.0, float(clean["qty"]))
			if key == "offer":
				offer = clean
			else:
				active = clean


func _unit(parts: Array) -> float:
	return float(hash(parts) & 0xffff) / 65536.0


func tick(dt: float, earned: float) -> void:
	if not enabled:
		return
	if not offer.is_empty():
		offer["expires_in"] = float(offer["expires_in"]) - dt
		if float(offer["expires_in"]) <= 0.0:
			var gone := offer
			offer = {}
			timer = _gap()
			expired.emit(gone)
	if not active.is_empty():
		active["time_left"] = float(active["time_left"]) - dt
		if float(active["time_left"]) <= 0.0:
			var gone2 := active
			active = {}
			timer = _gap()
			expired.emit(gone2)
	if offer.is_empty() and active.is_empty() and earned >= num("unlock_earned", 1500.0):
		timer -= dt
		if timer <= 0.0:
			_make_offer()


func _gap() -> float:
	return lerpf(num("gap_min_seconds", 150.0), num("gap_max_seconds", 260.0), _unit([seed_value, serial, "gap"]))


func _make_offer() -> void:
	serial += 1
	timer = 0.0
	var ids: Array = []
	for id: String in sims:
		var sim: FactorySim = sims[id]
		if sim.state.unlocked and sim.variants_enabled():
			ids.append(id)
	if ids.is_empty():
		timer = 30.0
		return
	var sim: FactorySim = sims[str(ids[int(_unit([seed_value, serial, "f"]) * ids.size()) % ids.size()])]
	var pool: Array[int] = []
	var total := 0.0
	for i in sim.skus.size():
		if sim.sku_available(i):
			pool.append(i)
			total += float(sim.skus[i].get("weight", 1.0))
	var roll := _unit([seed_value, serial, "v"]) * total
	var pick: int = pool[0]
	for i in pool:
		roll -= float(sim.skus[i].get("weight", 1.0))
		if roll < 0.0:
			pick = i
			break
	var rate := maxf(sim.planning_rate(1.5, 0.85), 0.05)
	var qty := int(roundf(rate * num("minutes", 1.0) * 60.0 / sim.sku_work(pick) / 5.0)) * 5
	qty = clampi(qty, int(num("min_quantity", 8)), int(num("max_quantity", 500)))
	var names: Array = cfg["names"]
	var reward := roundf(float(qty) * sim.sku_profit(pick) * num("bonus_fraction", 0.4))
	offer = {
		"id": "b%d" % serial, "customer": str(names[int(_unit([seed_value, serial, "n"]) * names.size()) % names.size()]),
		"factory": sim.data.id, "variant": sim.sku_id(pick), "variant_name": str(sim.skus[pick]["name"]), "qty": qty, "made": 0.0, "reward": reward,
		"expires_in": num("offer_lifetime", 75.0), "time_left": maxf(float(qty) / rate * sim.sku_work(pick) * num("time_limit_factor", 4.0), 120.0),
	}
	offered.emit(offer)


func accept() -> bool:
	if offer.is_empty() or not active.is_empty():
		return false
	active = offer
	offer = {}
	accepted.emit(active)
	return true


func dismiss() -> void:
	if offer.is_empty():
		return
	offer = {}
	timer = _gap()


## The product the factory must make for an accepted order ("" = no order for this factory).
func variant_for(factory_id: String) -> String:
	if not active.is_empty() and str(active["factory"]) == factory_id:
		return str(active["variant"])
	return ""


## Cylinders of a product have been made (live or while away): they count towards the accepted order.
func note_made(factory_id: String, variant_id: String, count: float) -> void:
	if active.is_empty() or str(active["factory"]) != factory_id or str(active["variant"]) != variant_id:
		return
	active["made"] = float(active["made"]) + count
	if float(active["made"]) >= float(active["qty"]):
		var order := active
		active = {}
		done += 1
		timer = _gap()
		completed.emit(order, float(order["reward"]))
