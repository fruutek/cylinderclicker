class_name SalesOffice
extends RefCounted
## The company's sales side: persistent customers, their telephone orders, and the sales rep's forecasts.
## Orders it agrees become ordinary Contracts in the ContractBook (source "call"), so there is one order
## system, one reservation system and one lorry pipeline. Factories ask it what customers are waiting for.
## No nodes. Every random choice is a hash of (seed, serial, ...) so games and tests are reproducible.

signal call_arrived(call: Dictionary)
signal call_closed(call: Dictionary, outcome: String)       # "accepted", "rejected", "declined", "expired"
signal customer_changed(customer_id: String)

const STATE_VERSION := 1
const OPTIONS := ["partial", "available", "decline", "delayed", "full"]

var cfg: Dictionary = {}
var archetypes: Array = []
var places: Array = []
var surnames: Array = []
var enabled := false

var book: ContractBook = null
var sims: Dictionary = {}                  # factory id -> FactorySim (set by GameSession)

var seed_value := 1
var unlocked := false
var clock := 0.0                           # seconds the office has been running
var serial := 0                            # calls ever made
var customers: Array[Dictionary] = []
var calls: Array[Dictionary] = []          # waiting on the player, newest last
var timers: Dictionary = {}                # factory id -> seconds to its next call
var observed: Dictionary = {}              # factory id -> [recently requested sku ids]
var lost: Dictionary = {}                  # sku id -> cylinders customers wanted that we did not supply
var stats := {"calls": 0, "accepted": 0, "declined": 0, "rejected": 0, "missed": 0, "rep_orders": 0, "units_ordered": 0.0}
var _missed_offline := 0
var _calls_offline := 0
var _was_offline := false
var _rep_orders_before := 0


func _init(raw: Dictionary = {}, rules: ContractRules = null) -> void:
	cfg = raw.get("calls", {})
	archetypes = raw.get("archetypes", [])
	if rules != null:
		places = rules.places
		surnames = rules.surnames
	enabled = not cfg.is_empty() and not archetypes.is_empty() and not places.is_empty() and not surnames.is_empty()


func num(key: String, fallback: float = 0.0) -> float:
	return float(cfg.get(key, fallback))


func reset(p_seed: int = -1) -> void:
	seed_value = p_seed if p_seed >= 0 else int(randi() & 0x7fffffff)
	unlocked = false
	clock = 0.0
	serial = 0
	customers.clear()
	calls.clear()
	timers.clear()
	observed.clear()
	lost.clear()
	stats = {"calls": 0, "accepted": 0, "declined": 0, "rejected": 0, "missed": 0, "rep_orders": 0, "units_ordered": 0.0}
	_missed_offline = 0
	_calls_offline = 0
	_was_offline = false


# ------------------------------------------------------------ persistence
func to_dict() -> Dictionary:
	return {
		"v": STATE_VERSION, "seed": seed_value, "unlocked": unlocked, "clock": clock, "serial": serial,
		"customers": customers.duplicate(true), "calls": calls.duplicate(true), "timers": timers.duplicate(),
		"observed": observed.duplicate(true), "lost": lost.duplicate(), "stats": stats.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	reset(int(d.get("seed", -1)) if d.has("seed") else -1)
	if d.is_empty():
		return
	unlocked = bool(d.get("unlocked", false))
	clock = maxf(float(d.get("clock", 0.0)), 0.0)
	serial = maxi(int(d.get("serial", 0)), 0)
	for raw: Variant in _array(d.get("customers")):
		var cust := _clean_customer(raw)
		if not cust.is_empty():
			customers.append(cust)
	for raw: Variant in _array(d.get("calls")):
		if typeof(raw) == TYPE_DICTIONARY and (raw as Dictionary).has("id") and (raw as Dictionary).has("customer"):
			var call: Dictionary = (raw as Dictionary).duplicate(true)
			call["qty"] = maxi(int(call.get("qty", 1)), 1)
			call["expires_in"] = maxf(float(call.get("expires_in", 60.0)), 1.0)
			call["factor"] = maxf(float(call.get("factor", 1.0)), 0.1)
			if find_customer(str(call["customer"])).is_empty():
				continue
			calls.append(call)
	var t: Variant = d.get("timers")
	if typeof(t) == TYPE_DICTIONARY:
		for k: String in t:
			timers[k] = clampf(float(t[k]), 0.0, 3600.0)
	var o: Variant = d.get("observed")
	if typeof(o) == TYPE_DICTIONARY:
		for k: String in o:
			var list: Array = []
			for v: Variant in _array(o[k]):
				list.append(str(v))
			observed[k] = list
	var l: Variant = d.get("lost")
	if typeof(l) == TYPE_DICTIONARY:
		for k: String in l:
			lost[k] = maxf(float(l[k]), 0.0)
	var s: Variant = d.get("stats")
	if typeof(s) == TYPE_DICTIONARY:
		for k: String in stats.keys():
			if s.has(k):
				stats[k] = float(s[k]) if k == "units_ordered" else int(s[k])


static func _array(v: Variant) -> Array:
	return v if typeof(v) == TYPE_ARRAY else []


func _clean_customer(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY or str(raw.get("id", "")) == "" or str(raw.get("name", "")) == "":
		return {}
	var c: Dictionary = (raw as Dictionary).duplicate(true)
	c["rel"] = clampf(float(c.get("rel", 20.0)), 0.0, 100.0)
	c["completed"] = maxi(int(c.get("completed", 0)), 0)
	c["failed"] = maxi(int(c.get("failed", 0)), 0)
	c["calls"] = maxi(int(c.get("calls", 0)), 0)
	c["spent"] = maxf(float(c.get("spent", 0.0)), 0.0)
	c["refusals"] = maxi(int(c.get("refusals", 0)), 0)
	c["dormant_until"] = maxf(float(c.get("dormant_until", 0.0)), 0.0)
	c["last_call"] = float(c.get("last_call", -1.0e9))
	c["size"] = clampf(float(c.get("size", 1.0)), 0.3, 4.0)
	c["patience"] = clampf(float(c.get("patience", 4.0)), 0.5, 30.0)
	c["reliability"] = clampf(float(c.get("reliability", 0.5)), 0.0, 1.0)
	c["price_sens"] = clampf(float(c.get("price_sens", 0.5)), 0.0, 1.0)
	if typeof(c.get("prefer")) != TYPE_DICTIONARY:
		c["prefer"] = {}
	if typeof(c.get("history")) != TYPE_ARRAY:
		c["history"] = []
	if typeof(c.get("asked")) != TYPE_DICTIONARY:
		c["asked"] = {}
	return c


# -------------------------------------------------------------- customers
func find_customer(id: String) -> Dictionary:
	for c in customers:
		if c["id"] == id:
			return c
	return {}


func _h(parts: Array) -> int:
	return hash(parts) & 0x7fffffff


func _unit(parts: Array) -> float:
	return float(_h(parts) & 0xffff) / 65536.0


## How many customers the company has dealings with: it grows with the trade-contract rank.
func customer_limit() -> int:
	var rank := book.rank_index() if book != null else 0
	return mini(int(num("start_customers", 5)) + int(num("customers_per_rank", 2)) * rank, int(num("max_customers", 14)))


func _make_customer(n: int) -> Dictionary:
	var order := ["installer", "merchant", "supplier", "installer", "developer", "wholesaler", "merchant", "housing_group", "supplier", "installer", "developer", "merchant", "wholesaler", "housing_group"]
	var kind := str(order[n % order.size()])
	var arch: Dictionary = {}
	for a: Dictionary in archetypes:
		if a["id"] == kind:
			arch = a
	if arch.is_empty():
		arch = archetypes[0]
	var used := {}
	for c in customers:
		used[c["name"]] = true
	var name := ""
	var templates: Array = arch.get("names", ["{surname} Heating"])
	for attempt in 30:
		var tpl := str(templates[_h([seed_value, n, attempt, "tpl"]) % templates.size()])
		name = tpl.replace("{surname}", str(surnames[_h([seed_value, n, attempt, "s"]) % surnames.size()])).replace("{place}", str(places[_h([seed_value, n, attempt, "p"]) % places.size()]))
		if not used.has(name):
			break
	var jitter := func(base: float, spread: float, salt: String) -> float:
		return base * (1.0 - spread + 2.0 * spread * _unit([seed_value, n, salt]))
	return {
		"id": "cu%d" % n, "name": name, "archetype": kind, "label": str(arch.get("label", "Customer")),
		"rel": num("relationship_start", 20.0), "completed": 0, "failed": 0, "calls": 0, "spent": 0.0, "refusals": 0,
		"dormant_until": 0.0, "last_call": -1.0e9,
		"prefer": (arch.get("prefer", {}) as Dictionary).duplicate(),
		"size": jitter.call(float(arch.get("size", 1.0)), 0.15, "size"),
		"patience": jitter.call(float(arch.get("patience", 4.0)), 0.25, "pat"),
		"reliability": clampf(jitter.call(float(arch.get("reliability", 0.5)), 0.2, "rel"), 0.0, 1.0),
		"price_sens": clampf(jitter.call(float(arch.get("price_sens", 0.5)), 0.2, "ps"), 0.0, 1.0),
		"history": [], "asked": {},
	}


func _ensure_customers() -> void:
	while customers.size() < customer_limit():
		customers.append(_make_customer(customers.size()))


func relationship_tier(rel: float) -> String:
	var name := "New"
	for t: Dictionary in cfg.get("tiers", []):
		if rel >= float(t["at"]):
			name = str(t["name"])
	return name


## The most a customer's relationship can reach for the orders actually completed so far.
func relationship_cap(cust: Dictionary) -> float:
	return minf(100.0, num("relationship_cap_base", 15.0) + num("relationship_cap_per_order", 6.0) * float(cust["completed"]))


func _change_rel(cust: Dictionary, delta: float) -> void:
	var before := float(cust["rel"])
	if delta > 0.0:
		cust["rel"] = minf(before + delta, maxf(relationship_cap(cust), before))
	else:
		cust["rel"] = maxf(before + delta, 0.0)
	if absf(float(cust["rel"]) - before) > 1e-6:
		customer_changed.emit(str(cust["id"]))


## Price a customer pays relative to the list profit: trust earns a premium, hard bargainers give less.
func price_factor(cust: Dictionary) -> float:
	var rel := float(cust["rel"]) / 100.0
	var ps := float(cust["price_sens"])
	return 1.0 + num("price_premium_max", 0.16) * rel * (1.0 - 0.5 * ps) + 0.04 - 0.03 * ps


# ------------------------------------------------------------------- time
## Wall-clock tick while playing.
func tick(dt: float) -> void:
	if not enabled or book == null:
		return
	advance(dt)


func _stock_factories() -> Array[FactorySim]:
	var out: Array[FactorySim] = []
	for id: String in sims:
		var sim: FactorySim = sims[id]
		if sim.state.unlocked and sim.stock_enabled():
			out.append(sim)
	return out


func advance(dt: float) -> void:
	clock += dt
	var factories := _stock_factories()
	if factories.is_empty():
		return
	if not unlocked:
		# Customers start ringing once there is something on the shelves to talk about (or money has been made).
		var made := 0.0
		for sim in factories:
			made += sim.state.cylinders_made
		if made < num("unlock_made", 8.0) and factories[0].company.lifetime_earned < num("unlock_earned", 30.0):
			return
		unlocked = true
		_ensure_customers()
		for sim in factories:
			timers[sim.data.id] = 6.0
	_ensure_customers()
	for call in calls.duplicate():
		call["expires_in"] = float(call["expires_in"]) - dt
		if float(call["expires_in"]) <= 0.0:
			_expire(call)
	for sim in factories:
		var id := sim.data.id
		timers[id] = float(timers.get(id, 20.0)) - dt
		if float(timers[id]) <= 0.0:
			var made := _new_call(sim)
			timers[id] = _next_gap(sim, made)


func _next_gap(sim: FactorySim, call: Dictionary) -> float:
	var rate := sim.demand_rate()
	var qty := float(call.get("qty", 4)) if not call.is_empty() else maxf(rate * num("order_minutes", 1.5) * 60.0, num("min_order", 2.0))
	var gap := qty / maxf(num("demand_vs_capacity", 1.25) * maxf(rate, 0.005), 1e-6)
	var avg := 0.0
	var n := 0
	for cust in customers:
		if float(cust["dormant_until"]) <= clock:
			avg += float(cust["rel"])
			n += 1
	var rel := avg / maxf(float(n), 1.0) / 100.0
	gap /= (0.85 + 0.35 * rel)                         # a company people trust is telephoned more
	return clampf(gap, num("min_gap", 25.0), 240.0)


# ------------------------------------------------------------------ calls
func _choose_customer(sim: FactorySim) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1.0
	var waiting := {}
	for call in calls:
		waiting[call["customer"]] = true
	for cust in customers:
		if float(cust["dormant_until"]) > clock or waiting.has(cust["id"]):
			continue
		if book != null:
			var has_order := false
			for c in book.active:
				if c.is_call() and c.customer_id == cust["id"]:
					has_order = true
			if has_order:
				continue
		var since := clampf((clock - float(cust["last_call"])) / 300.0, 0.0, 3.0)
		var score := (0.4 + float(cust["rel"]) / 100.0 + since) * (0.6 + _unit([seed_value, serial, cust["id"], "pick"]))
		if score > best_score:
			best_score = score
			best = cust
	return best


func _choose_sku(sim: FactorySim, cust: Dictionary) -> int:
	var total := 0.0
	var weights: Array[float] = []
	for i in sim.skus.size():
		var w := 0.0
		if sim.sku_available(i):
			w = float(sim.skus[i].get("weight", 1.0)) * float((cust["prefer"] as Dictionary).get(str(sim.skus[i].get("family", "")), 1.0))
		weights.append(w)
		total += w
	if total <= 0.0:
		return -1
	var roll := _unit([seed_value, serial, "sku"]) * total
	for i in weights.size():
		roll -= weights[i]
		if roll < 0.0 and weights[i] > 0.0:
			return i
	return 0


func typical_quantity(sim: FactorySim, cust: Dictionary, sku_i: int) -> int:
	var rate := sim.demand_rate()
	var rel := float(cust["rel"]) / 100.0
	var jitter := 0.6 + 0.8 * _unit([seed_value, serial, "qty"])
	var qty := rate * num("order_minutes", 1.5) * 60.0 * float(cust["size"]) * (0.85 + 0.4 * rel) * jitter / maxf(sim.sku_work(sku_i), 0.5)
	# An order has to fit on the shelves and a lorry: a small warehouse means small orders.
	var fit := int(floorf(float(sim.warehouse.capacity) * num("order_fit", 0.75)))
	return maxi(mini(int(roundf(qty)), fit), int(num("min_order", 2.0)))


func _new_call(sim: FactorySim) -> Dictionary:
	serial += 1
	if calls.size() >= int(num("max_queued", 3)):
		return {}
	var cust := _choose_customer(sim)
	if cust.is_empty():
		return {}
	var sku_i := _choose_sku(sim, cust)
	if sku_i < 0:
		return {}
	var qty := typical_quantity(sim, cust, sku_i)
	var call := {
		"id": "call%d" % serial, "serial": serial, "customer": cust["id"], "factory": sim.data.id, "sku": sim.sku_id(sku_i),
		"qty": qty, "factor": price_factor(cust), "expires_in": num("call_expiry", 150.0), "line": _unit([seed_value, serial, "line"]),
	}
	calls.append(call)
	cust["calls"] = int(cust["calls"]) + 1
	cust["last_call"] = clock
	stats["calls"] = int(stats["calls"]) + 1
	_calls_offline += 1 if _was_offline else 0
	_remember_request(sim.data.id, str(call["sku"]))
	call_arrived.emit(call)
	return call


func _remember_request(factory_id: String, sku: String) -> void:
	var list: Array = observed.get(factory_id, [])
	list.append(sku)
	while list.size() > int(num("forecast_window", 40)):
		list.pop_front()
	observed[factory_id] = list


func _expire(call: Dictionary) -> void:
	if _rep_answer(call):
		return                      # nobody picked up: the sales rep took the order (at a worse price)
	calls.erase(call)
	var cust := find_customer(str(call["customer"]))
	_note_lost(str(call["sku"]), float(call["qty"]))
	stats["missed"] = int(stats["missed"]) + 1
	if not cust.is_empty():
		if not _was_offline or _missed_offline < 3:
			_change_rel(cust, -num("loss_missed_call", 1.0))
		if _was_offline:
			_missed_offline += 1
	call_closed.emit(call, "expired")


## While nobody answers, the sales rep does: the best offer that is likely to be taken, at a weaker price.
## This is what keeps a factory selling when you are away from the telephone (or the game).
func _rep_answer(call: Dictionary) -> bool:
	if find_call(str(call["id"])).is_empty():
		return false
	var opts: Array = options_for(call)
	var pick := ""
	for want: String in ["full", "partial", "delayed", "available"]:
		for o: Dictionary in opts:
			if o["id"] == want and (want == "full" or float(o["chance"]) >= 0.45):
				pick = want
				break
		if pick != "":
			break
	if pick == "":
		return false
	call["factor"] = float(call["factor"]) * num("rep_price_factor", 0.92)
	var r: Dictionary = answer(str(call["id"]), pick)
	if bool(r.get("accepted", false)):
		stats["rep_orders"] = int(stats["rep_orders"]) + 1
		return true
	return find_call(str(call["id"])).is_empty()


func _note_lost(sku: String, units: float) -> void:
	lost[sku] = float(lost.get(sku, 0.0)) + units


func find_call(id: String) -> Dictionary:
	for call in calls:
		if call["id"] == id:
			return call
	return {}


func call_text(call: Dictionary) -> String:
	var cust := find_customer(str(call["customer"]))
	var sim: FactorySim = sims.get(str(call["factory"]))
	var sku_name := str(call["sku"])
	if sim != null:
		var i := sim.sku_index(str(call["sku"]))
		if i >= 0:
			sku_name = str(sim.skus[i]["name"])
	var lines := {
		"installer": ["Morning! Any chance of %d %s? I've a job lined up.", "Hi, it's urgent-ish: can you supply %d %s?", "Got a van waiting: %d %s, can you do it?"],
		"merchant": ["We're running low. Can you supply %d %s?", "Counter's been busy - %d %s, please.", "Could you send %d %s this week?"],
		"supplier": ["Stock order for you: %d %s. Can you do that?", "Our customers keep asking for %s... can you supply %d?", "Need %d %s to top up our shelves."],
		"developer": ["We're fitting out a block: need %d %s. Can you supply?", "Site manager here - %d %s, as soon as you can.", "Can you commit to %d %s for our next phase?"],
		"housing_group": ["Planned works need %d %s. What can you do?", "We have a programme of replacements: %d %s.", "Can you provide %d %s for our contractors?"],
		"wholesaler": ["Bulk order: %d %s. Best price, please.", "Need %d %s to restock the warehouse. What can you do?", "%d %s - can you supply the lot?"],
	}
	var pool: Array = lines.get(str(cust.get("archetype", "installer")), lines["installer"])
	var tpl := str(pool[int(float(call.get("line", 0.0)) * pool.size()) % pool.size()])
	if tpl.begins_with("Our customers"):
		return tpl % [sku_name, int(call["qty"])]
	return tpl % [int(call["qty"]), sku_name]


# ---------------------------------------------------------------- options
## What the player can offer for a call right now, with what would be shipped, when the rest could follow
## and how likely the customer is to agree. Pure: nothing changes.
func options_for(call: Dictionary) -> Array:
	var sim: FactorySim = sims.get(str(call["factory"]))
	var cust := find_customer(str(call["customer"]))
	if sim == null or cust.is_empty():
		return []
	var i := sim.sku_index(str(call["sku"]))
	var qty := int(call["qty"])
	var sku := str(call["sku"])
	var avail := sim.warehouse.available(sku)
	var ship_now := mini(avail, qty)
	var rest := qty - ship_now
	var base_rate := sim.planning_rate(1.5, 0.85)                   # baseline cylinders a second the line can build
	var eta := INF
	if base_rate > 0.0 and sim.sku_available(i):
		eta = (sim.owed_work() + float(rest) * sim.sku_work(i)) / base_rate + 8.0    # everything already promised is built first
	var rel := float(cust["rel"]) / 100.0
	var pat := float(cust["patience"]) * 60.0 * (0.8 + 0.6 * rel)
	var relb := 0.25 * (rel - 0.3)
	var unit := sim.sku_profit(i) * float(call["factor"])
	var out: Array = []
	if rest == 0:
		out.append(_option("full", "Supply in full", ship_now, 0, 0.0, 0.98 + relb, unit * float(qty), "Everything is on the shelves: it ships now."))
	else:
		if ship_now > 0:
			var chance_a := 0.9 - 0.25 * float(cust["reliability"]) * float(rest) / float(qty)
			if eta > pat * 1.5:
				chance_a *= clampf(pat * 1.5 / eta, 0.1, 1.0)
			out.append(_option("partial", "Part delivery now, backorder the rest", ship_now, rest, eta, chance_a + relb, unit * float(qty),
				"Ships %d now. The other %d follow in about %s." % [ship_now, rest, NumFmt.duration(eta)]))
			var f := float(ship_now) / float(qty)
			var chance_b := (0.25 + 0.75 * pow(f, 1.2)) * (1.0 - 0.35 * float(cust["reliability"]) * (1.0 - f))
			out.append(_option("available", "Only what we have", ship_now, 0, 0.0, chance_b + relb, unit * float(ship_now),
				"Ships %d now and nothing more. They may not want a part order." % ship_now))
		if qty <= sim.warehouse.capacity:         # a delayed order waits on the shelves, so it has to fit there
			var chance_d := 0.85 - 0.1 * float(cust["reliability"])
			if eta > pat:
				chance_d *= clampf(pat / eta, 0.1, 1.0)
			out.append(_option("delayed", "Full order, delivered later", 0, rest, eta, chance_d + relb, unit * float(qty),
				"All %d ship together in about %s." % [qty, NumFmt.duration(eta)]))
	out.append(_option("decline", "Decline", 0, 0, 0.0, 1.0, 0.0, "Turn the order down. Doing it often costs you the customer."))
	for o: Dictionary in out:
		if o["id"] != "decline":
			o["chance"] = clampf(float(o["chance"]), 0.04, 0.97)
			o["verdict"] = "Likely" if float(o["chance"]) >= 0.7 else ("Maybe" if float(o["chance"]) >= 0.4 else "Unlikely")
	return out


func _option(id: String, label: String, ship_now: int, backorder: int, eta: float, chance: float, value: float, note: String) -> Dictionary:
	return {"id": id, "label": label, "ship_now": ship_now, "backorder": backorder, "eta": eta, "chance": chance, "value": value, "note": note, "verdict": ""}


## The player's answer. Returns {ok, accepted, text, contract_id}.
func answer(call_id: String, option_id: String) -> Dictionary:
	var call := find_call(call_id)
	if call.is_empty():
		return {"ok": false, "accepted": false, "text": "That call has ended."}
	var cust := find_customer(str(call["customer"]))
	var sim: FactorySim = sims.get(str(call["factory"]))
	if cust.is_empty() or sim == null:
		calls.erase(call)
		return {"ok": false, "accepted": false, "text": "That call has ended."}
	if option_id == "decline":
		_decline(call, cust)
		return {"ok": true, "accepted": false, "text": "%s: \"Right. I'll try elsewhere.\"" % cust["name"]}
	var opt: Dictionary = {}
	for o: Dictionary in options_for(call):
		if o["id"] == option_id:
			opt = o
	if opt.is_empty():
		return {"ok": false, "accepted": false, "text": "That is not on offer."}
	if book.call_active_count() >= int(num("max_open_orders", 6)):
		return {"ok": false, "accepted": false, "text": "You have too many open orders. Finish some first."}
	var roll := _unit([seed_value, call["serial"], option_id])
	if roll >= float(opt["chance"]):
		calls.erase(call)
		_note_lost(str(call["sku"]), float(call["qty"]))
		stats["rejected"] = int(stats["rejected"]) + 1
		_change_rel(cust, -num("loss_rejected_offer", 1.0))
		call_closed.emit(call, "rejected")
		return {"ok": true, "accepted": false, "text": "%s: \"No, that won't do. I'll find someone else this time.\"" % cust["name"]}
	var contract := _make_order(call, cust, sim, opt)
	calls.erase(call)
	stats["accepted"] = int(stats["accepted"]) + 1
	stats["units_ordered"] = float(stats["units_ordered"]) + float(contract.quantity)
	cust["refusals"] = maxi(int(cust["refusals"]) - 1, 0)
	var asked: Dictionary = cust["asked"]
	asked[str(call["sku"])] = float(asked.get(str(call["sku"]), 0.0)) + float(contract.quantity)
	book.add_order(contract)
	call_closed.emit(call, "accepted")
	var reply := {"partial": "Fine, send what you have and the rest when you can.", "available": "OK, I'll take what you've got.", "delayed": "All right. I'll wait for the full order.", "full": "Brilliant, thanks."}
	return {"ok": true, "accepted": true, "contract_id": contract.id, "text": "%s: \"%s\"" % [cust["name"], reply.get(option_id, "Thanks.")]}


func _make_order(call: Dictionary, cust: Dictionary, sim: FactorySim, opt: Dictionary) -> Contract:
	var i := sim.sku_index(str(call["sku"]))
	var c := Contract.new()
	c.id = "o%d" % int(call["serial"])
	c.serial = 1000000 + int(call["serial"])
	c.tier = "call"
	c.customer = str(cust["name"])
	c.customer_id = str(cust["id"])
	c.archetype = str(cust["archetype"])
	c.archetype_label = str(cust["label"])
	c.factory = sim.data.id
	c.sku = str(call["sku"])
	c.product_name = str(sim.skus[i]["name"])
	c.asked = int(call["qty"])
	c.quantity = int(opt["ship_now"]) if opt["id"] == "available" else int(call["qty"])
	c.margin = float(call["factor"])
	c.unit_ref = sim.sku_profit(i)
	c.value = roundf(float(c.quantity) * c.unit_ref * c.margin)
	c.mode = {"partial": "partial", "delayed": "delayed", "available": "full", "full": "full"}.get(str(opt["id"]), "full")
	c.pallets = clampi(int(ceilf(float(c.quantity) / 8.0)), 1, 4)
	c.patience = float(cust["patience"]) * 60.0 * (0.8 + 0.6 * float(cust["rel"]) / 100.0)
	if opt["id"] == "partial" or opt["id"] == "delayed":
		c.promised = float(opt["eta"]) * num("promise_slack", 1.25) + 20.0
		c.deadline = c.promised
	return c


func _decline(call: Dictionary, cust: Dictionary) -> void:
	calls.erase(call)
	_note_lost(str(call["sku"]), float(call["qty"]))
	stats["declined"] = int(stats["declined"]) + 1
	var repeat := int(cust["refusals"]) >= 1
	_change_rel(cust, -(num("loss_repeat_decline", 4.0) if repeat else num("loss_declined", 2.0)))
	cust["refusals"] = int(cust["refusals"]) + 1
	if int(cust["refusals"]) >= 3 or float(cust["rel"]) < num("dormant_below", 6.0):
		cust["dormant_until"] = clock + num("dormant_return_seconds", 900.0)       # tired of being turned down: stops ringing for a while
		customer_changed.emit(str(cust["id"]))
	call_closed.emit(call, "declined")


## A telephone order is over (see ContractBook.order_ended): the customer remembers how it went.
func order_ended(c: Contract, outcome: String) -> void:
	var cust := find_customer(c.customer_id)
	if cust.is_empty():
		return
	var size_factor := clampf(float(c.quantity) / maxf(float(cust["size"]) * 12.0, 4.0), 0.3, 1.5)
	var asked_share := float(c.quantity) / maxf(float(c.asked), 1.0)
	match outcome:
		"complete":
			cust["completed"] = int(cust["completed"]) + 1
			_change_rel(cust, num("gain_on_time", 3.0) * size_factor * (0.5 + 0.5 * asked_share))
		"late_complete":
			cust["completed"] = int(cust["completed"]) + 1
			_change_rel(cust, num("gain_late", 0.8) * size_factor)
		_:
			cust["failed"] = int(cust["failed"]) + 1
			var share := 0.5 if c.shipped > 0.0 else 1.0
			_change_rel(cust, -num("loss_cancelled", 7.0) * share)
			_note_lost(c.sku, c.outstanding())
	cust["spent"] = float(cust["spent"]) + c.paid_total
	var hist: Array = cust["history"]
	hist.push_front({"sku": c.sku, "qty": c.quantity, "outcome": outcome, "paid": c.paid_total})
	while hist.size() > int(num("history_size", 8)):
		hist.pop_back()
	customer_changed.emit(str(cust["id"]))


# ---------------------------------------------------------- the factories
func backlog(factory_id: String, sku: String) -> float:
	return book.backlog(factory_id, sku) if book != null else 0.0


func due_rank(factory_id: String, sku: String) -> float:
	return book.due_rank(factory_id, sku) if book != null else 0.0


func on_stock(factory_id: String, sku: String) -> void:
	if book != null:
		book.allocate_stock(factory_id, sku)


func auto_targets() -> bool:
	return false


# ------------------------------------------------------------- sales rep
## 0..1: how good the sales rep is at reading the market (a stat that upgrades raise).
func forecast_quality(sim: FactorySim) -> float:
	return clampf(float(sim.stats.get("forecast_quality", 0.3)), 0.0, 1.0)


## The rep's view of demand for one factory: for each product it can make, the share of calls it expects,
## the cylinders a minute that implies, the stock level it recommends and what is short.
## Relative likelihood, not a guarantee: poor forecasts wobble, good ones follow what customers really ask.
func forecast(sim: FactorySim, with_target: bool = true) -> Array:
	var rows: Array = []
	var pool: Array[int] = []
	var total_prior := 0.0
	for i in sim.skus.size():
		if sim.sku_available(i):
			pool.append(i)
			total_prior += float(sim.skus[i].get("weight", 1.0))
	if pool.is_empty():
		return rows
	var seen: Array = observed.get(sim.data.id, [])
	var counts := {}
	for s: Variant in seen:
		counts[str(s)] = int(counts.get(str(s), 0)) + 1
	var q := forecast_quality(sim) * clampf(float(seen.size()) / 20.0, 0.0, 1.0)
	var rate_min := maxf(sim.steady_rate(), sim.demand_rate()) * 60.0
	var demand := num("demand_vs_capacity", 1.25) * rate_min
	var shares: Array[float] = []
	var sum := 0.0
	for i in pool:
		var id := sim.sku_id(i)
		var prior := float(sim.skus[i].get("weight", 1.0)) / total_prior
		var obs := float(counts.get(id, 0)) / maxf(float(seen.size()), 1.0)
		var share := q * obs + (1.0 - q) * prior
		# a poorly trained rep misjudges: the error shrinks as the forecast quality rises
		var wobble := (_unit([seed_value, id, int(clock / 600.0)]) - 0.5) * 0.7 * (1.0 - forecast_quality(sim))
		share = maxf(share * (1.0 + wobble), 0.01)
		shares.append(share)
		sum += share
	var cover := (sim.sku_catalog.num("target_cover_minutes", 3.0)) * num("cover_safety", 1.15)
	# the recommendations as a whole must fit on the shelves: shrink them together if they do not
	var wanted := cover * demand
	var limit := float(sim.warehouse.capacity) * sim.sku_catalog.num("target_fill_max", 0.8)
	var squeeze := minf(1.0, limit / maxf(wanted, 0.001))
	for n in pool.size():
		var i := pool[n]
		var id := sim.sku_id(i)
		var share := shares[n] / sum
		var per_min := demand * share
		var rec := maxi(int(ceilf(cover * per_min * squeeze)), 1 if share >= 0.05 else 0)
		var stock := sim.warehouse.total(id)
		rows.append({
			"sku": id, "name": str(sim.skus[i]["name"]), "short": str(sim.skus[i].get("short", sim.skus[i]["name"])), "index": i,
			"share": share, "per_min": per_min, "recommended": rec, "stock": stock, "available": sim.warehouse.available(id),
			"reserved": sim.warehouse.reserved_units(id), "target": sim.effective_target(i) if with_target else 0, "in_production": float(sim.warehouse.wip.get(id, 0.0)),
			"owed": backlog(sim.data.id, id), "shortfall": maxi(rec - stock, 0), "lost": float(lost.get(id, 0.0)),
			"dead": stock > 2 * rec + 3,
		})
	return rows


func recommended(factory_id: String, sku_id: String) -> int:
	var sim: FactorySim = sims.get(factory_id)
	if sim == null or not enabled or not unlocked:
		return 0
	for r: Dictionary in forecast(sim, false):
		if r["sku"] == sku_id:
			return int(r["recommended"])
	return 0


# ---------------------------------------------------------------- offline
## Unattended time passes in slices (see GameSession.apply_offline): orders age and ship, calls arrive
## but never pile up (at most `max_queued` wait, older ones lapse), and nothing is double counted.
func offline_step(dt: float) -> void:
	if not _was_offline:
		_rep_orders_before = int(stats["rep_orders"])
	_was_offline = true
	if book != null:
		book.offline_stock_step(dt)
	if enabled and book != null:
		advance(dt)
		# Away from the telephone, the rep takes every call that has been ringing for a minute; only the last
		# minute's calls (at most three) are left for you.
		for call in calls.duplicate():
			if float(call["expires_in"]) <= num("call_expiry", 150.0) - 60.0:
				_expire(call)


func offline_report() -> Dictionary:
	if not _was_offline:
		return {}
	_was_offline = false
	var report := {"calls_waiting": calls.size(), "missed": _missed_offline, "calls": _calls_offline, "rep_orders": int(stats["rep_orders"]) - _rep_orders_before}
	_missed_offline = 0
	_calls_offline = 0
	return report if (calls.size() > 0 or int(report["missed"]) > 0 or int(report["rep_orders"]) > 0) else {}
