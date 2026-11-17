class_name GameSession
extends RefCounted
## The company: shared cash and statistics plus one FactorySim per factory.
## Every unlocked factory is ticked every step, whichever one is on screen,
## so nothing is lost or double-counted when the player switches view.
## No dependency on the scene tree.

signal factory_unlocked(id: String)
signal current_changed(id: String)

var data: GameData
var state: GameState
var catalog: ProductCatalog
var factories: Array[FactorySim] = []
var contract_rules: ContractRules
var contracts: ContractBook          # trade contracts, reputation and dispatch
var _by_id: Dictionary = {}


func _init(p_data: GameData) -> void:
	data = p_data
	catalog = ProductCatalog.new(data.products)
	contract_rules = ContractRules.new(data.contracts)
	contracts = ContractBook.new(contract_rules)
	contracts.market = Callable(self, "_contract_market")
	contracts.completed.connect(_on_contract_completed)
	contracts.failed.connect(_on_contract_failed)
	for def in data.factories:
		var sim := FactorySim.new(def, catalog)
		sim.contracts = contracts
		factories.append(sim)
		_by_id[def.id] = sim
	new_game()


func new_game() -> void:
	state = GameState.new()
	contracts.reset()
	_bind_factories()


func load_state(d: Dictionary) -> void:
	state = GameState.new()
	state.from_dict(d)
	contracts.from_dict(state.contracts)
	_bind_factories()


## Gives every defined factory a state (loaded, or fresh if the save predates
## it) and makes sure the starting factory is always owned.
func _bind_factories() -> void:
	for id: String in state.factories.keys():
		if not _by_id.has(id):
			state.factories.erase(id)     # factory no longer exists in the data
	for sim in factories:
		var fs: FactoryState = state.factories.get(sim.data.id)
		if fs == null:
			fs = FactoryState.new()
			state.factories[sim.data.id] = fs
		if sim.data.starts_unlocked():
			fs.unlocked = true
		sim.bind(state, fs)
		if fs.unlocked:
			_mark_products_unlocked(sim.data)
	if not _by_id.has(state.current_factory) or not factory(state.current_factory).state.unlocked:
		state.current_factory = factories[0].data.id


func _mark_products_unlocked(def: FactoryDef) -> void:
	var ids: Array = [def.product_spec.get("material", ""), def.product_spec.get("range", "")]
	ids.append_array(def.product_spec.get("variants", []))
	for pid: Variant in ids:
		if pid != "" and not state.unlocked_products.has(pid):
			state.unlocked_products.append(pid)


## Everything that goes into a save file.
func save_data() -> Dictionary:
	for sim in factories:
		sim.snapshot()
	state.contracts = contracts.to_dict()
	return state.to_dict()


# -------------------------------------------------------------- factories
func factory(id: String) -> FactorySim:
	return _by_id.get(id)


func current() -> FactorySim:
	return factory(state.current_factory)


func set_current(id: String) -> bool:
	var sim := factory(id)
	if sim == null or not sim.state.unlocked:
		return false
	state.current_factory = id
	current_changed.emit(id)
	return true


func unlocked_factories() -> Array[FactorySim]:
	var out: Array[FactorySim] = []
	for sim in factories:
		if sim.state.unlocked:
			out.append(sim)
	return out


func tick(dt: float) -> void:
	state.play_seconds += dt
	for sim in factories:
		if sim.state.unlocked:
			sim.tick(dt)
	contracts.tick(dt)       # after the factories, so a contract finished this tick beats its deadline


## Hands-free earnings per second across the whole company.
func income_per_second() -> float:
	var total := 0.0
	for sim in factories:
		if sim.state.unlocked:
			total += sim.income_per_second()
	return total


## What the company is actually earning right now (includes clicking).
func recent_income_per_second() -> float:
	var total := 0.0
	for sim in factories:
		if sim.state.unlocked:
			total += sim.recent_income_per_second()
	return total


# ---------------------------------------------------------------- unlocks
## The conditions for building a factory, as [{text, met}] for the UI.
func unlock_requirements(id: String) -> Array:
	var out: Array = []
	var def: FactoryDef = data.factory(id)
	for req: Dictionary in def.unlock.get("requires", []):
		var other := factory(req.get("factory", ""))
		match req.get("type", ""):
			"all_automated":
				out.append({
					"text": "Automate all %d stations at %s" % [other.data.stations.size(), other.data.short_name],
					"met": other.state.unlocked and other.all_automated(),
				})
			"earned":
				var amount := float(req.get("amount", 0.0))
				out.append({
					"text": "Earn %s at %s (%s so far)" % [NumFmt.money(amount), other.data.short_name, NumFmt.money(minf(other.state.earned, amount))],
					"met": other.state.earned >= amount,
				})
			_:
				push_warning("GameSession: unknown unlock requirement in %s" % id)
	return out


func requirements_met(id: String) -> bool:
	for r: Dictionary in unlock_requirements(id):
		if not r["met"]:
			return false
	return true


func can_unlock(id: String) -> bool:
	var sim := factory(id)
	return sim != null and not sim.state.unlocked and requirements_met(id) and state.cash >= sim.data.unlock_cost()


## Buys a factory: pays the construction cost once and opens it for good.
func unlock_factory(id: String) -> bool:
	if not can_unlock(id):
		return false
	var sim := factory(id)
	state.cash -= sim.data.unlock_cost()
	sim.state.unlocked = true
	_mark_products_unlocked(sim.data)
	factory_unlocked.emit(id)
	return true


# ---------------------------------------------------------------- offline
## Credits every fully automated factory for time spent away.
## Returns {} if nothing was earned, else a summary with a per-factory list.
func apply_offline(elapsed_seconds: float) -> Dictionary:
	if elapsed_seconds < FactorySim.OFFLINE_MIN_SECONDS:
		return {}
	contracts.offline_begin()        # lorries that were loading have long since left
	var parts: Array = []
	var total_cash := 0.0
	var total_cylinders := 0.0
	var capped := false
	var counted := 0.0
	for sim in factories:
		if not sim.state.unlocked:
			continue
		var r := sim.apply_offline(elapsed_seconds)
		if r.is_empty():
			continue
		parts.append(r)
		total_cash += float(r["cash"])
		total_cylinders += float(r["cylinders"])
		capped = capped or bool(r["capped"])
		counted = maxf(counted, float(r["counted_seconds"]))
	var trade := contracts.offline_end(counted)
	if parts.is_empty() and trade.is_empty():
		return {}
	var summary := {
		"away_seconds": elapsed_seconds,
		"counted_seconds": counted,
		"capped": capped,
		"cylinders": total_cylinders,
		"cash": total_cash,
		"factories": parts,
	}
	if not trade.is_empty():
		summary["contracts"] = trade
	return summary


# -------------------------------------------------------------- contracts
## What the contract book needs to know about the company: for each factory it
## owns, what it makes, what a cylinder nets today and how fast it can really
## build them. Contracts are sized and priced from this, nothing else.
func _contract_market() -> Dictionary:
	var cps := contract_rules.num("planning_clicks_per_second", 1.5)
	var factor := contract_rules.num("planning_factor", 0.85)
	var list: Array = []
	for sim in factories:
		if sim.state.unlocked:
			list.append({
				"id": sim.data.id,
				"product_name": String(sim.product["name"]),
				"product_key": sim.data.product_key(),
				"profit": sim.profit_per_cylinder(),
				"rate": sim.planning_rate(cps, factor),
			})
	return {"earned": state.lifetime_earned, "factories": list}


func _on_contract_completed(c: Contract, base: float, bonus: float, _rep: int) -> void:
	var sim := factory(c.factory)
	if sim != null:
		sim.credit_contract_payout(base + bonus)


func _on_contract_failed(c: Contract, _reason: String, units: float) -> void:
	var sim := factory(c.factory)
	if sim != null and units > 0.0:
		sim.release_stock(units)
