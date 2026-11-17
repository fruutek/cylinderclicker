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

const STATE_VERSION := 1
const UNLOCK_CHECK_SECONDS := 0.5
const EPS := 1.0e-6                     # shipments are floating point: "complete" means within a millionth of a cylinder

var rules: ContractRules
var market: Callable = Callable()      # () -> {"earned": float, "factories": [{id, product_name, profit, rate}]}

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
		if c.remaining() <= EPS and c.status == Contract.Status.ACTIVE:
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
	if active.size() >= slots():
		return "All %d contract slots are in use. Dispatch or finish one first." % slots()
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
	c.allocation = default_allocation(c, free_share(c.factory))
	active.append(c)
	offer_removed.emit(c, "accepted")
	accepted.emit(c)
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
	c.bonus_earned = c.bonus > 0.0 and c.bonus_by > 0.0 and c.elapsed <= c.bonus_by + 1e-6
	if not _report.is_empty():
		_report["ready"].append(c.customer)
	ready.emit(c)


# --------------------------------------------------------------- dispatch
func dispatch_problem(c: Contract) -> String:
	if c.status == Contract.Status.DISPATCHING:
		return "The lorry is already loading."
	if c.status != Contract.Status.READY:
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
	c.status = Contract.Status.DISPATCHING
	c.dispatch_total = rules.num("dispatch_base_seconds", 3.4) + rules.num("dispatch_seconds_per_pallet", 0.9) * float(c.pallets)
	c.dispatch_left = c.dispatch_total
	dispatch_started.emit(c)
	return ""


## What an order pays right now. The price follows the factory's list price (a
## price-adjustment clause): quantity x what a cylinder nets today x the margin
## agreed, so a contract's premium over selling stays the same however fast the
## company grows. A contract with no margin is a fixed price (its `value`).
func quote(c: Contract) -> float:
	if c.margin <= 0.0:
		return c.value
	var profit := _profit_now(c.factory)
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
	_fail(c, "abandoned")
	return ""


func _fail(c: Contract, reason: String) -> void:
	if not active.has(c):
		return
	active.erase(c)
	var units := c.delivered
	var floor_points := int(rules.rank(rank_index())["at"])       # a rank, once earned, is kept
	reputation = maxi(reputation - c.penalty, floor_points)
	lockout = rules.num("premium_lockout", 900.0)
	stats["failed"] = int(stats["failed"]) + 1
	_log(c, reason, 0.0, 0.0, -c.penalty)
	if not _report.is_empty():
		_report["failed"].append({"customer": c.customer, "units": units})
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
				if c.has_deadline():
					c.time_left -= dt
					if c.time_left <= 0.0:
						_fail(c, "deadline")
			Contract.Status.DISPATCHING:
				c.dispatch_left -= dt
				if c.dispatch_left <= 0.0:
					_settle(c)
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


func _profit_now(factory_id: String) -> float:
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
