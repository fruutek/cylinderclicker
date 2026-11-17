class_name ContractBook
extends RefCounted
## The company's trade business: reputation, the board of offers, accepted
## contracts, history and every rule that connects them to production.
## No nodes, no rendering and no reference to the session - money and stock
## effects leave through signals, and market information (what each factory
## can build and earns) comes in through the `market` callable, so the same
## code runs in the game, the tests and any future tools.
##
## How production reaches contracts
##   Every cylinder a factory ships goes through route(). Each accepted
##   contract has an allocation (a % of that factory's output) and receives
##   exactly that share of every shipment: 40% of a shipment of 1.25 cylinders
##   is 0.5. Whatever is not routed is sold as before, so a cylinder is either
##   sold or contracted - never both, and 100% means nothing is sold.

signal offer_added(c: Contract)
signal offer_removed(c: Contract, reason: String)      # "expired" or "accepted"
signal accepted(c: Contract)
signal delivered(c: Contract, units: float)            # cylinders just built for a contract
signal ready(c: Contract)                              # the order is complete and waiting for dispatch
signal dispatch_started(c: Contract)
signal completed(c: Contract, base: float, bonus: float, rep_gain: int)    # paid - handle the money here
signal failed(c: Contract, reason: String, units: float)  # "deadline" / "abandoned": release `units` of stock
signal rank_changed(index: int, rank_name: String)
signal allocation_changed(c: Contract)
signal board_unlocked
signal shipment_left(c: Contract, units: float, amount: float)   # a warehouse lorry has gone: this many cylinders, this much paid
signal order_ended(c: Contract, outcome: String)                 # a telephone order is over: "complete", "late_complete", "cancelled"

const STATE_VERSION := 1
const UNLOCK_CHECK_SECONDS := 0.5
const EPS := 1.0e-6                     # shipments are floating point: "complete" means within a millionth of a cylinder

var rules: ContractRules
var market: Callable = Callable()      # () -> {"earned": float, "factories": [{id, product_name, profit, rate, skus}]}
var auto_ship_board := false           # a finished board contract goes out by itself (the phone game: no dispatch screen)
var port: StockPort = null             # the warehouses (null / not stocking = the v0.5.1 "built-for-contract" counters)

var reputation := 0
var seed_value := 1
var serial := 0
var offer_timer := 0.0
var lockout := 0.0                     # seconds of premium-offer pause left after a failure
var unlocked := false
var offers: Array[Contract] = []
var active: Array[Contract] = []       # accepted: ACTIVE, READY and DISPATCHING, in acceptance order
var history: Array[Dictionary] = []    # newest first
var stats := {"completed": 0, "failed": 0, "units": 0.0, "paid": 0.0}

var _unlock_timer := 0.0
var _report: Dictionary = {}           # collected while applying offline progress
var _start_delivered := {}
var _lockout_before := 0.0             # premium pause when the offline catch-up began
var _lockout_from_failure := 0.0       # pause left from a failure during the catch-up


func _init(p_rules: ContractRules = null) -> void:
	rules = p_rules if p_rules != null else ContractRules.new()
	reset()


func reset(p_seed: int = -1) -> void:
	reputation = 0
	seed_value = p_seed if p_seed >= 0 else int(randi() & 0x7fffffff)
	serial = 0
	offer_timer = rules.num("offer_interval", 75.0)
	lockout = 0.0
	unlocked = false
	offers.clear()
	active.clear()
	history.clear()
	stats = {"completed": 0, "failed": 0, "units": 0.0, "paid": 0.0}
	_unlock_timer = 0.0
	_report = {}
	_start_delivered = {}


# ------------------------------------------------------------ persistence
func to_dict() -> Dictionary:
	var o: Array = []
	for c in offers:
		o.append(c.to_dict())
	var a: Array = []
	for c in active:
		a.append(c.to_dict())
	return {
		"v": STATE_VERSION, "reputation": reputation, "seed": seed_value, "serial": serial,
		"offer_timer": offer_timer, "lockout": lockout, "unlocked": unlocked,
		"offers": o, "active": a, "history": history.duplicate(true), "stats": stats.duplicate(),
	}


## Restores a saved book. Missing or damaged parts fall back to defaults, so an
## old save (no contracts) or a hand-edited one never stops the game loading.
func from_dict(d: Dictionary) -> void:
	reset(int(d.get("seed", -1)) if d.has("seed") else -1)
	if d.is_empty():
		return
	reputation = maxi(int(d.get("reputation", 0)), 0)
	serial = maxi(int(d.get("serial", 0)), 0)
	offer_timer = clampf(float(d.get("offer_timer", rules.num("offer_interval", 75.0))), 0.0, 3600.0)
	lockout = maxf(float(d.get("lockout", 0.0)), 0.0)
	unlocked = bool(d.get("unlocked", false))
	for raw: Variant in _array(d.get("offers")):
		var c := Contract.from_dict(raw)
		if c != null:
			c.status = Contract.Status.OFFER
			offers.append(c)
	var share := {}
	for raw: Variant in _array(d.get("active")):
		var c := Contract.from_dict(raw)
		if c == null or c.status == Contract.Status.OFFER:
			continue
		if c.status == Contract.Status.ACTIVE:
			# Shares at one factory can never add up to more than 100%.
			var room := 100 - int(share.get(c.factory, 0))
			c.allocation = mini(c.allocation, maxi(room, 0))
			share[c.factory] = int(share.get(c.factory, 0)) + c.allocation
		else:
			c.allocation = 0
		if c.remaining() <= EPS and c.status == Contract.Status.ACTIVE and not c.is_call():
			c.status = Contract.Status.READY
			c.allocation = 0
		active.append(c)
	for raw: Variant in _array(d.get("history")):
		if typeof(raw) == TYPE_DICTIONARY:
			history.append((raw as Dictionary).duplicate(true))
	var max_history := int(rules.num("history_size", 12))
	while history.size() > max_history:
		history.pop_back()
	var s: Variant = d.get("stats")
	if typeof(s) == TYPE_DICTIONARY:
		for k: String in stats.keys():
			if s.has(k):
				stats[k] = float(s[k]) if (k == "paid" or k == "units") else int(s[k])


static func _array(v: Variant) -> Array:
	return v if typeof(v) == TYPE_ARRAY else []


# ------------------------------------------------------------- reputation
func rank_index() -> int:
	return rules.rank_index(reputation)


func rank_name() -> String:
	return rules.rank_name(rank_index())


func rank_def() -> Dictionary:
	return rules.rank(rank_index())


## Progress to the next rank as {have, need, fraction}; need = -1 at the top.
func rank_progress() -> Dictionary:
	var idx := rank_index()
	var base := int(rules.rank(idx)["at"])
	var nxt := rules.next_rank_at(idx)
	if nxt < 0:
		return {"have": reputation - base, "need": -1, "fraction": 1.0}
	return {"have": reputation - base, "need": nxt - base, "fraction": clampf(float(reputation - base) / float(nxt - base), 0.0, 1.0)}


func slots() -> int:
	return int(rank_def().get("slots", 3))


func board_capacity() -> int:
	return int(rank_def().get("offers", 3))


## Reputation a contract would earn right now (rank-scaled; +25% with its bonus).
func rep_reward(c: Contract, with_bonus: bool = false) -> int:
	var f := rules.rep_factor(c.tier, rank_index())
	if f <= 0.0:
		return 0
	var mult := rules.num("bonus_rep_mult", 1.25) if (with_bonus or c.bonus_earned) else 1.0
	return maxi(1, roundi(float(c.rep) * f * mult))


func _add_rep(delta: int) -> void:
	var before := rank_index()
	reputation = maxi(reputation + delta, 0)
	var after := rank_index()
	if after > before:
		offer_timer = minf(offer_timer, 8.0)      # new customers notice quickly
		rank_changed.emit(after, rules.rank_name(after))


# ----------------------------------------------------------------- lookup
func find_offer(id: String) -> Contract:
	for c in offers:
		if c.id == id:
			return c
	return null


func find(id: String) -> Contract:
	for c in active:
		if c.id == id:
			return c
	return null


## Accepted contracts of one factory, in acceptance order.
func for_factory(factory_id: String) -> Array[Contract]:
	var out: Array[Contract] = []
	for c in active:
		if c.factory == factory_id:
			out.append(c)
	return out


func count_status(s: Contract.Status) -> int:
	var n := 0
	for c in active:
		if c.status == s:
			n += 1
	return n


## What the factory-floor view should show on the dispatch pad.
func featured_for(factory_id: String) -> Contract:
	var best: Contract = null
	for c in active:
		if c.factory != factory_id:
			continue
		if c.status == Contract.Status.DISPATCHING:
			return c
		if best == null or _feature_rank(c) > _feature_rank(best):
			best = c
	return best


func _feature_rank(c: Contract) -> float:
	if c.status == Contract.Status.READY:
		return 2.0 + float(c.serial) * 1e-6
	return c.fraction() + (0.001 if c.allocation > 0 else 0.0)


## Share of a factory's output not yet promised to a contract (0-100).
func free_share(factory_id: String, except_id: String = "") -> int:
	var used := 0
	for c in active:
		if c.factory == factory_id and c.status == Contract.Status.ACTIVE and c.id != except_id:
			used += c.allocation
	return maxi(100 - used, 0)


## Output share going to contracts at a factory (0-100).
func committed_share(factory_id: String) -> int:
	return 100 - free_share(factory_id)


## Seconds to finish at the given production rate (cylinders/second of the
## whole factory), or -1 if the contract gets no production.
func eta_seconds(c: Contract, factory_rate: float) -> float:
	var r := factory_rate * float(c.allocation) / 100.0
	if r <= 0.0:
		return -1.0
	return c.remaining() / r


# ------------------------------------------------------------- accepting
## Why a contract cannot be accepted right now, or "" if it can.
func accept_problem(c: Contract) -> String:
	if board_active_count() >= slots():
		return "All %d contract slots are in use. Dispatch or finish one first." % slots()
	if _stock(c):
		return ""
	if free_share(c.factory) - int(rules.num("sales_reserve", 20.0)) < int(rules.num("allocation_step", 5)):
		return "Keep some of that factory's output for sales: lower another contract's share first."
	return ""


func accept(id: String) -> String:
	var c := find_offer(id)
	if c == null:
		return "That offer is no longer available."
	var problem := accept_problem(c)
	if problem != "":
		return problem
	offers.erase(c)
	c.status = Contract.Status.ACTIVE
	c.elapsed = 0.0
	c.time_left = c.deadline
	c.delivered = 0.0
	c.allocation = 0 if _stock(c) else default_allocation(c, free_share(c.factory))
	active.append(c)
	offer_removed.emit(c, "accepted")
	accepted.emit(c)
	if _stock(c):
		fulfil_from_stock(c)         # whatever is on the shelves is put aside straight away
	return ""


## A sensible starting share: half the factory, or more if a deadline needs it.
func default_allocation(c: Contract, free: int) -> int:
	var step := int(rules.num("allocation_step", 5))
	var share := int(rules.num("default_allocation", 50))
	if c.has_deadline() and c.est_full > 0.0:
		var need := c.est_full / (0.6 * c.deadline)      # fraction needed to finish in 60% of the time
		share = maxi(share, mini(int(ceilf(need * 100.0 / float(step))) * step, 100))
	share = mini(share, free - int(rules.num("sales_reserve", 20.0)))      # a new order never takes the last of the factory's output
	return maxi(share - share % step, mini(step, free))


## Sets a contract's share, limited by what the factory has left. Returns the share applied.
func set_allocation(id: String, pct: int) -> int:
	var c := find(id)
	if c == null or c.status != Contract.Status.ACTIVE:
		return 0
	var step := int(rules.num("allocation_step", 5))
	pct = clampi(pct - pct % step, 0, free_share(c.factory, c.id))
	if pct != c.allocation:
		c.allocation = pct
		allocation_changed.emit(c)
	return c.allocation


# ------------------------------------------------------------- production
## Called for every shipment a factory makes. Returns how many cylinders went
## to contracts; the caller sells the rest.
func route(factory_id: String, count: float) -> float:
	if active.is_empty():
		return 0.0
	var taken := 0.0
	for c in active:
		if c.status != Contract.Status.ACTIVE or c.factory != factory_id or c.allocation <= 0:
			continue
		var take := minf(minf(count * float(c.allocation) / 100.0, c.remaining()), count - taken)
		if take > 0.0:
			c.delivered += take
			taken += take
			delivered.emit(c, take)
		if c.remaining() <= EPS:
			c.delivered = float(c.quantity)
			_complete(c)
	return taken


func _complete(c: Contract) -> void:
	c.status = Contract.Status.READY
	c.allocation = 0
	c.built = true
	c.bonus_earned = c.bonus > 0.0 and c.bonus_by > 0.0 and c.elapsed <= c.bonus_by + 1e-6
	if not _report.is_empty():
		_report["ready"].append(c.customer)
	ready.emit(c)


# --------------------------------------------------------------- dispatch
func dispatch_problem(c: Contract) -> String:
	if c.status == Contract.Status.DISPATCHING:
		return "The lorry is already loading."
	if _stock(c):
		if c.held <= 0.0:
			return "Nothing is set aside for it yet."
	elif c.status != Contract.Status.READY:
		return "Not finished yet."
	for o in active:
		if o != c and o.status == Contract.Status.DISPATCHING and o.factory == c.factory:
			return "A lorry is already loading at this factory. Wait for it to leave."
	return ""


func dispatch(id: String) -> String:
	var c := find(id)
	if c == null:
		return "That contract is not active."
	var problem := dispatch_problem(c)
	if problem != "":
		return problem
	if _stock(c):
		c.loading = c.held
		c.pallets = pallets_for(c.loading)
	_start_loading(c)
	return ""


## What an order pays right now. The price follows the factory's list price (a
## price-adjustment clause): quantity x what a cylinder nets today x the margin
## agreed, so a contract's premium over selling stays the same however fast the
## company grows. A contract with no margin is a fixed price (its `value`).
func quote(c: Contract) -> float:
	if c.margin <= 0.0:
		return c.value
	var profit := _profit_now(c.factory, c.sku)
	if profit <= 0.0:
		return c.value
	return roundf(float(c.quantity) * profit * c.margin)


## The completion bonus at today's price (0 if this order has none).
func bonus_quote(c: Contract) -> float:
	if c.bonus_pct > 0.0:
		return roundf(quote(c) * c.bonus_pct)
	return c.bonus


## The lorry has left: pay out, award reputation, record it. Runs exactly once
## per contract because it removes the contract from `active`.
func _settle(c: Contract) -> void:
	if not active.has(c):
		return
	if _stock(c):
		_settle_shipment(c)
		return
	active.erase(c)
	var base := quote(c)
	var bonus := bonus_quote(c) if c.bonus_earned else 0.0
	var rep_gain := rep_reward(c)
	stats["completed"] = int(stats["completed"]) + 1
	stats["units"] = float(stats["units"]) + c.delivered
	stats["paid"] = float(stats["paid"]) + base + bonus
	_log(c, "delivered", base + bonus, bonus, rep_gain)
	if not _report.is_empty():
		_report["paid"].append({"customer": c.customer, "amount": base + bonus})
	completed.emit(c, base, bonus, rep_gain)
	_add_rep(rep_gain)


# ----------------------------------------------------------------- failing
## Gives a contract up. Free within the first moments if nothing was built;
## otherwise it counts as a failure (the customer is let down).
func abandon(id: String) -> String:
	var c := find(id)
	if c == null or c.status != Contract.Status.ACTIVE:
		return "Only a contract still being built can be cancelled."
	if c.delivered <= 0.0 and c.elapsed <= rules.num("free_cancel_seconds", 30.0):
		active.erase(c)
		_log(c, "cancelled", 0.0, 0.0, 0)
		failed.emit(c, "cancelled", 0)
		return ""
	if _stock(c) and c.elapsed <= rules.num("free_cancel_seconds", 30.0):
		active.erase(c)           # changed your mind straight away: the reserved stock simply goes back on the shelves
		_release_held(c)
		_log(c, "cancelled", 0.0, 0.0, 0)
		failed.emit(c, "cancelled", 0)
		return ""
	_fail(c, "abandoned")
	return ""


func _fail(c: Contract, reason: String) -> void:
	if not active.has(c):
		return
	active.erase(c)
	var units := c.delivered
	var stocked := _stock(c)
	if stocked:
		units = 0.0
		_release_held(c)
	var floor_points := int(rules.rank(rank_index())["at"])       # a rank, once earned, is kept
	reputation = maxi(reputation - c.penalty, floor_points)
	lockout = rules.num("premium_lockout", 900.0)
	stats["failed"] = int(stats["failed"]) + 1
	_log(c, reason, 0.0, 0.0, -c.penalty)
	if not _report.is_empty():
		_report["failed"].append({"customer": c.customer, "units": units if not stocked else c.delivered, "stocked": stocked})
	failed.emit(c, reason, units)


func _log(c: Contract, outcome: String, payout: float, bonus: float, rep_change: int) -> void:
	history.push_front({
		"outcome": outcome, "customer": c.customer, "product": c.product_name, "tier": c.tier,
		"quantity": c.quantity, "delivered": c.delivered, "payout": payout, "bonus": bonus, "rep": rep_change,
	})
	var max_history := int(rules.num("history_size", 12))
	while history.size() > max_history:
		history.pop_back()


# ------------------------------------------------------------------- time
func tick(dt: float) -> void:
	if not rules.enabled:
		return
	if lockout > 0.0:
		lockout = maxf(lockout - dt, 0.0)
	for c in active.duplicate():
		match c.status:
			Contract.Status.ACTIVE:
				c.elapsed += dt
				if c.is_call():
					_age_call_order(c, dt)
				elif c.has_deadline():
					c.time_left -= dt
					if c.time_left <= 0.0:
						_fail(c, "deadline")
			Contract.Status.DISPATCHING:
				c.dispatch_left -= dt
				if c.dispatch_left <= 0.0:
					_settle(c)
	if port != null:
		auto_dispatch(false)
	if not unlocked:
		_unlock_timer -= dt
		if _unlock_timer <= 0.0:
			_unlock_timer = UNLOCK_CHECK_SECONDS
			_check_unlock()
		return
	for o in offers.duplicate():
		o.expires_in -= dt
		if o.expires_in <= 0.0:
			offers.erase(o)
			offer_removed.emit(o, "expired")
	if offers.size() < board_capacity():
		offer_timer -= dt
		if offer_timer <= 0.0:
			offer_timer = rules.num("offer_interval", 75.0)
			_fill_board(1)
	else:
		offer_timer = rules.num("offer_interval", 75.0)


func _check_unlock() -> void:
	if unlocked or not market.is_valid():
		return
	if float(_market().get("earned", 0.0)) >= rules.num("unlock_earned", 50.0):
		unlocked = true
		board_unlocked.emit()
		_fill_board(board_capacity())


func _market() -> Dictionary:
	if not market.is_valid():
		return {}
	var m: Variant = market.call()
	return m if typeof(m) == TYPE_DICTIONARY else {}


func _profit_now(factory_id: String, sku: String = "") -> float:
	if sku != "" and port != null and port.has_stock(factory_id):
		return port.unit_profit(factory_id, sku)
	for f: Dictionary in _market().get("factories", []):
		if f["id"] == factory_id:
			return float(f["profit"])
	return 0.0


func _context() -> Dictionary:
	var names: Array = []
	for c in offers:
		names.append(c.customer)
	for c in active:
		names.append(c.customer)
	return {
		"rank": rank_index(), "premium_allowed": lockout <= 0.0, "exclude": names,
		"factories": _market().get("factories", []),
	}


## Adds up to `max_new` offers (never above the board's capacity). Returns how many.
func _fill_board(max_new: int) -> int:
	var ctx := _context()
	var added := 0
	while offers.size() < board_capacity() and added < max_new:
		serial += 1
		var c := ContractGenerator.generate(rules, ctx, seed_value, serial)
		if c == null:
			break
		_assign_sku(c)
		offers.append(c)
		(ctx["exclude"] as Array).append(c.customer)
		added += 1
		offer_added.emit(c)
	return added


## Test/dev hook: top the board up now.
func refresh_board() -> int:
	return _fill_board(board_capacity())


# --------------------------------------------------------------- offline
## Start of an offline catch-up (the game was closed or in the background):
## a lorry that was loading when the game closed has long since left.
func offline_begin() -> void:
	_report = {"progress": [], "ready": [], "failed": [], "paid": [], "new_offers": 0}
	_start_delivered = {}
	_lockout_before = lockout
	_lockout_from_failure = 0.0
	for c in active:
		_start_delivered[c.id] = c.delivered
	for c in active.duplicate():
		if c.status == Contract.Status.DISPATCHING:
			_settle(c)


## Builds the offline production of one factory into its contracts, stepping
## from event to event (a contract finishing, or a deadline passing) so each
## contract's progress, the shares freed afterwards and the deadline rules are
## exact. `rate` is the factory's hands-free output (cylinders/second) and
## `counted` the seconds it ran. Returns the whole cylinders built for contracts.
## Deadlines only run while the factory does, so a factory that cannot run
## unattended (rate 0) never reaches here and its deadlines wait for you.
func offline_factory(factory_id: String, rate: float, counted: float) -> float:
	if rate <= 0.0 or counted <= 0.0:
		return 0.0
	var contracted := 0.0
	var t := 0.0
	for guard in 64:
		var open: Array[Contract] = []
		for c in active:
			if c.factory == factory_id and c.status == Contract.Status.ACTIVE:
				open.append(c)
		if open.is_empty() or t >= counted - 1e-9:
			break
		var left := counted - t
		var t_complete := INF
		var who_complete: Contract = null
		var t_dead := INF
		var who_dead: Contract = null
		for c in open:
			if c.allocation > 0:
				var dt := c.remaining() / (rate * float(c.allocation) / 100.0)
				if dt < t_complete:
					t_complete = dt
					who_complete = c
			if c.has_deadline() and maxf(c.time_left, 0.0) < t_dead:
				t_dead = maxf(c.time_left, 0.0)
				who_dead = c
		var step := left
		var event := 0
		if t_complete <= left and t_complete <= t_dead:
			step = t_complete
			event = 1
		elif t_dead < left and t_dead < t_complete:
			step = t_dead
			event = 2
		for c in open:
			c.elapsed += step
			if c.has_deadline():
				c.time_left -= step
			if c.allocation > 0:
				var add := minf(rate * step * float(c.allocation) / 100.0, c.remaining())
				c.delivered += add
				contracted += add
		t += step
		if event == 1:
			contracted += who_complete.remaining()      # absorbs floating point rounding
			who_complete.delivered = float(who_complete.quantity)
		for c in open:
			if c.remaining() <= EPS:
				c.delivered = float(c.quantity)
				_complete(c)
		if event == 2 and who_dead.status == Contract.Status.ACTIVE:
			_fail(who_dead, "deadline")
			# The pause started when the deadline passed, not when the player returned.
			_lockout_from_failure = maxf(_lockout_from_failure, rules.num("premium_lockout", 900.0) - (counted - t))
	return contracted


## End of an offline catch-up: offers age (and new customers call) for as long
## as the factories ran. Returns a summary of what changed, or {} if nothing did.
func offline_end(counted: float) -> Dictionary:
	if _report.is_empty():
		return {}
	var report := _report
	_report = {}
	if rules.enabled and counted > 0.0:
		lockout = maxf(maxf(_lockout_before - counted, 0.0), _lockout_from_failure)
		if not unlocked:
			_check_unlock()
		else:
			for o in offers.duplicate():
				o.expires_in -= counted
				if o.expires_in <= 0.0:
					offers.erase(o)
					offer_removed.emit(o, "expired")
			var want := int(counted / rules.num("offer_interval", 75.0))
			report["new_offers"] = _fill_board(want) if want > 0 else 0
	for c in active:
		var before := float(_start_delivered.get(c.id, c.delivered))
		if c.delivered > before + EPS and c.status == Contract.Status.ACTIVE:
			report["progress"].append({
				"customer": c.customer, "product": c.product_name, "added": c.delivered - before,
				"delivered": c.delivered, "quantity": c.quantity, "time_left": c.time_left if c.has_deadline() else -1.0,
			})
	_start_delivered = {}
	var any := false
	for k: String in report:
		if (report[k] is Array and not (report[k] as Array).is_empty()) or (report[k] is int and int(report[k]) > 0):
			any = true
	return report if any else {}


# ================================================================ warehouse orders
## Whether this order is filled from a warehouse (rather than the v0.5.1 build counters).
func _stock(c: Contract) -> bool:
	return port != null and port.has_stock(c.factory)


func board_active_count() -> int:
	var n := 0
	for c in active:
		if not c.is_call():
			n += 1
	return n


func call_active_count() -> int:
	return active.size() - board_active_count()


func pallets_for(units: float) -> int:
	return clampi(int(ceilf(units / 8.0)), 1, 4)


func _start_loading(c: Contract) -> void:
	c.status = Contract.Status.DISPATCHING
	c.dispatch_total = rules.num("dispatch_base_seconds", 3.4) + rules.num("dispatch_seconds_per_pallet", 0.9) * float(c.pallets)
	c.dispatch_left = c.dispatch_total
	dispatch_started.emit(c)


## Gives a board offer one of its factory's products (weighted by how often customers ask for it) and
## re-sizes it for that product: slower products get longer deadlines, the payout follows its profit.
func _assign_sku(c: Contract) -> void:
	if port == null or not port.has_stock(c.factory):
		return
	var sim: FactorySim = port.sims.get(c.factory)
	var total := 0.0
	var pool: Array[int] = []
	for i in sim.skus.size():
		if sim.sku_available(i):
			pool.append(i)
			total += float(sim.skus[i].get("weight", 1.0))
	if pool.is_empty():
		return
	var roll := float(hash([seed_value, c.serial, "sku"]) & 0xffff) / 65536.0 * total
	var pick: int = pool[0]
	for i in pool:
		roll -= float(sim.skus[i].get("weight", 1.0))
		if roll < 0.0:
			pick = i
			break
	c.sku = sim.sku_id(pick)
	c.product_name = String(sim.skus[pick]["name"])
	var work := sim.sku_work(pick)
	var base_profit := sim.profit_per_cylinder()
	var profit := sim.sku_profit(pick)
	c.est_full *= work
	c.deadline *= work
	c.bonus_by *= work
	c.time_left = c.deadline
	if base_profit > 0.0:
		var scale := profit / base_profit
		c.unit_ref = profit
		c.value = roundf(c.value * scale)
		c.bonus = roundf(c.bonus * scale)


## Puts available stock aside for an order. Returns how many cylinders were reserved.
func fulfil_from_stock(c: Contract) -> int:
	if not _stock(c) or (c.status != Contract.Status.ACTIVE and c.status != Contract.Status.DISPATCHING):
		return 0
	var owed := int(floorf(float(c.quantity) - c.delivered + EPS))
	if owed <= 0:
		return 0
	var got := port.reserve(c.factory, c.sku, mini(owed, port.available(c.factory, c.sku)))
	if got <= 0:
		return 0
	c.held += float(got)
	c.delivered += float(got)
	delivered.emit(c, float(got))
	if not c.is_call() and c.remaining() <= EPS and c.status == Contract.Status.ACTIVE:
		c.delivered = float(c.quantity)
		_complete(c)
	elif c.remaining() <= EPS:
		c.built = true
	return got


## New stock has arrived: orders get it most urgent first (earliest promise, then oldest).
func allocate_stock(factory_id: String, sku: String) -> void:
	if port == null or not port.has_stock(factory_id):
		return
	var waiting: Array[Contract] = []
	for c in active:
		if (c.status == Contract.Status.ACTIVE or c.status == Contract.Status.DISPATCHING) and c.factory == factory_id and c.sku == sku and c.remaining() > EPS:
			waiting.append(c)
	waiting.sort_custom(func(a: Contract, b: Contract) -> bool: return urgency(a) < urgency(b))
	for c in waiting:
		if port.available(factory_id, sku) <= 0:
			break
		fulfil_from_stock(c)


## Smaller = more urgent. Orders with no deadline wait behind everything that has one.
func urgency(c: Contract) -> float:
	var t := c.time_left if c.has_deadline() else 1.0e9
	return t + float(c.serial) * 1.0e-6


## Cylinders customers are still waiting for at this factory (not yet in stock or on the line).
func backlog(factory_id: String, sku: String) -> float:
	var n := 0.0
	for c in active:
		if (c.status == Contract.Status.ACTIVE or c.status == Contract.Status.DISPATCHING) and c.factory == factory_id and c.sku == sku and _stock(c):
			n += c.remaining()
	return n


## How soon the most urgent waiting order needs its cylinders (0 = nobody waiting).
func due_rank(factory_id: String, sku: String) -> float:
	var best := 1.0e18
	for c in active:
		if (c.status == Contract.Status.ACTIVE or c.status == Contract.Status.DISPATCHING) and c.factory == factory_id and c.sku == sku and c.remaining() > EPS and _stock(c):
			best = minf(best, urgency(c))
	return best


func _release_held(c: Contract) -> void:
	var n := int(roundf(c.held))
	if n > 0 and port != null:
		port.release(c.factory, c.sku, n)
	c.delivered = maxf(c.delivered - c.held, 0.0)
	c.held = 0.0
	c.loading = 0.0


# ------------------------------------------------------------ telephone orders
## Adds a telephone order that a customer has agreed to. Not limited by the board's contract slots.
func add_order(c: Contract) -> void:
	c.source = "call"
	c.status = Contract.Status.ACTIVE
	c.allocation = 0
	c.elapsed = 0.0
	c.time_left = c.deadline
	c.delivered = 0.0
	c.shipped = 0.0
	c.held = 0.0
	active.append(c)
	accepted.emit(c)
	fulfil_from_stock(c)
	if port != null:
		auto_dispatch(false)


func _age_call_order(c: Contract, dt: float) -> void:
	if not c.has_deadline():
		return
	c.time_left -= dt
	if c.time_left < 0.0 and not c.late:
		c.late = true
	if c.time_left < -c.patience:
		_cancel_order(c, "cancelled")


## The customer gives up waiting. Cylinders already shipped were paid for; the reserved rest go back on the shelves.
func _cancel_order(c: Contract, outcome: String) -> void:
	if not active.has(c):
		return
	active.erase(c)
	_release_held(c)
	_log(c, outcome, c.paid_total, 0.0, 0)
	if not _report.is_empty():
		_report["failed"].append({"customer": c.customer, "units": c.shipped, "stocked": true, "partial": c.shipped > 0.0})
	order_ended.emit(c, outcome)


## What one cylinder of this order pays: today's profit on it times the agreed margin (a fixed-price
## contract pays its value split over its cylinders).
func unit_net(c: Contract) -> float:
	if c.margin > 0.0:
		return port.unit_profit(c.factory, c.sku) * c.margin
	return c.value / float(maxi(c.quantity, 1))


## A lorry has left with `loading` cylinders: take them out of the warehouse and pay for exactly those.
## Board contracts add their completion bonus and reputation when the last lorry has gone.
func _settle_shipment(c: Contract) -> void:
	var n := int(roundf(c.loading))
	var sent := port.ship(c.factory, c.sku, n)
	var pay := float(sent) * unit_net(c)
	c.shipped += float(sent)
	c.held = maxf(c.held - float(sent), 0.0)
	c.loading = 0.0
	c.dispatch_left = 0.0
	c.dispatch_total = 0.0
	c.shipments += 1
	c.paid_total += pay
	stats["units"] = float(stats["units"]) + float(sent)
	stats["paid"] = float(stats["paid"]) + pay
	if not _report.is_empty():
		_report["paid"].append({"customer": c.customer, "amount": pay})
	shipment_left.emit(c, float(sent), pay)
	var done := c.shipped >= float(c.quantity) - EPS
	if not done:
		c.status = Contract.Status.READY if (c.built or c.remaining() <= EPS) and not c.is_call() else Contract.Status.ACTIVE
		if not c.built and c.remaining() <= EPS and not c.is_call():
			_complete(c)
		return
	active.erase(c)
	if c.is_call():
		_log(c, "delivered", c.paid_total, 0.0, 0)
		order_ended.emit(c, "late_complete" if c.late else "complete")
		return
	var bonus := bonus_quote(c) if c.bonus_earned else 0.0
	var rep_gain := rep_reward(c)
	stats["completed"] = int(stats["completed"]) + 1
	stats["paid"] = float(stats["paid"]) + bonus
	_log(c, "delivered", c.paid_total + bonus, bonus, rep_gain)
	if not _report.is_empty():
		_report["paid"].append({"customer": c.customer, "amount": bonus})
	completed.emit(c, c.paid_total, bonus, rep_gain)
	_add_rep(rep_gain)


## Telephone orders ship by themselves when a lorry bay is free: the first load of a part-delivery goes at
## once, later loads when a quarter of the order is ready or everything still owed is on the shelves,
## and a delayed order goes as one load when it is complete. With `instant` the lorry leaves at once (offline).
func auto_dispatch(instant: bool) -> void:
	var busy := {}
	for c in active:
		if c.status == Contract.Status.DISPATCHING:
			busy[c.factory] = true
	var ready_orders: Array[Contract] = []
	for c in active:
		if (c.status == Contract.Status.ACTIVE or c.status == Contract.Status.READY) and c.held > 0.0 and _stock(c) and _wants_lorry(c):
			ready_orders.append(c)
	ready_orders.sort_custom(func(a: Contract, b: Contract) -> bool: return urgency(a) < urgency(b))
	for c in ready_orders:
		if busy.has(c.factory) and not instant:
			continue
		busy[c.factory] = true
		c.loading = c.held
		c.pallets = pallets_for(c.loading)
		_start_loading(c)
		if instant:
			_settle(c)
			busy.erase(c.factory)


func _wants_lorry(c: Contract) -> bool:
	var blocked := port.free_space(c.factory) < 1.0          # reserved stock has filled the shelves and stopped the line
	if not c.is_call():
		# A board contract waits for you to send it (a complete load earns its bonus) unless the line is blocked
		# - or the game sends finished orders by itself.
		return blocked or (auto_ship_board and c.remaining() <= EPS and c.held >= float(c.quantity) - c.shipped - EPS)
	if blocked:
		return true
	var owed := float(c.quantity) - c.shipped
	var all_ready := c.held >= owed - EPS
	match c.mode:
		"partial":
			return c.shipments == 0 or all_ready or c.held >= ceilf(float(c.quantity) * 0.25)
		_:
			return all_ready


## Unattended time for the order side: promises run out, customers give up, lorries leave. Deadlines of the
## board contracts also keep running (as they do when you play).
func offline_stock_step(dt: float) -> void:
	for c in active.duplicate():
		if c.status != Contract.Status.ACTIVE:
			continue
		c.elapsed += dt
		if c.is_call():
			_age_call_order(c, dt)
		elif c.has_deadline() and _stock(c):
			c.time_left -= dt
			if c.time_left <= 0.0:
				_fail(c, "deadline")
	if port != null:
		auto_dispatch(true)
