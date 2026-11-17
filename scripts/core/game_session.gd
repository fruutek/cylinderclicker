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
var sku_catalog: SkuCatalog          # what can be made and stored
var sales: SalesOffice               # customers, telephone orders, the sales rep
var port: StockPort                  # lets the contract book reserve and ship warehouse stock
var stock_default := false           # new games keep a warehouse and sell to customers (false = v0.5.1 direct sales, used by the legacy tests)
var _by_id: Dictionary = {}


## `p_stock` = new games run the warehouse economy; the tests that pin the older sell-on-completion
## rules leave it false.
func _init(p_data: GameData, p_stock: bool = false) -> void:
	data = p_data
	sku_catalog = SkuCatalog.new(data.skus)
	stock_default = p_stock and sku_catalog.enabled()
	port = StockPort.new()
	catalog = ProductCatalog.new(data.products)
	contract_rules = ContractRules.new(data.contracts)
	contracts = ContractBook.new(contract_rules)
	contracts.port = port
	sales = SalesOffice.new(data.customers, contract_rules)
	sales.book = contracts
	contracts.market = Callable(self, "_contract_market")
	contracts.completed.connect(_on_contract_completed)
	contracts.failed.connect(_on_contract_failed)
	contracts.shipment_left.connect(_on_shipment_left)
	contracts.order_ended.connect(sales.order_ended)
	for def in data.factories:
		var sim := FactorySim.new(def, catalog, sku_catalog)
		sim.contracts = contracts
		sim.sales = sales
		factories.append(sim)
		_by_id[def.id] = sim
		port.sims[def.id] = sim
		sales.sims[def.id] = sim
	new_game()


func new_game() -> void:
	state = GameState.new()
	state.stock_mode = stock_default
	contracts.reset()
	sales.reset()
	_bind_factories()


func load_state(d: Dictionary) -> void:
	state = GameState.new()
	state.from_dict(d)
	state.stock_mode = state.stock_mode and stock_default      # a direct-sales session (tests) never runs the warehouse economy
	contracts.from_dict(state.contracts)
	sales.from_dict(state.sales)
	_bind_factories()
	_apply_stock_migration()


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


## A save from before the warehouse existed has just been loaded: every factory gets a stock room
## sized to its output and automatic targets, so nothing stops earning. Happens once.
func _apply_stock_migration() -> void:
	if not state.stock_migrate:
		return
	state.stock_migrate = false
	if not state.stock_mode:
		return
	for sim in factories:
		if sim.state.unlocked:
			sim.migrate_to_stock()
	# Contracts that were being built from the old counters now hold real, reserved stock: nothing is lost
	# and nothing is paid twice (a lorry that was loading still pays once when it leaves).
	var books: Array[Contract] = []
	books.append_array(contracts.offers)
	books.append_array(contracts.active)
	for c in books:
		var sim := factory(c.factory)
		if sim == null or not sim.stock_enabled() or c.sku != "":
			continue
		c.sku = String(sim.skus[0]["id"])
		if c.status == Contract.Status.OFFER:
			continue
		var n := int(floorf(c.delivered + 1.0e-6))
		sim.warehouse.add_existing(c.sku, n, true)
		c.held = float(n)
		c.delivered = float(n)
		c.allocation = 0
		if c.status == Contract.Status.DISPATCHING:
			c.loading = float(n)
		if c.status == Contract.Status.ACTIVE and c.remaining() <= ContractBook.EPS:
			c.status = Contract.Status.READY


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
	state.sales = sales.to_dict()
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
	sales.tick(dt)
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
	if state.stock_mode:
		return _apply_offline_stock(elapsed_seconds)
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


const OFFLINE_STEP := 30.0


## Unattended time in the warehouse economy: every automated factory runs the same planner it uses live
## (targets, customers waiting, shelf space), stepped in half-minute slices, so stock, orders and
## wholesale sales stay consistent and nothing is counted twice.
func _apply_offline_stock(elapsed_seconds: float) -> Dictionary:
	contracts.offline_begin()
	var caps := {}
	var counted := 0.0
	var before := {}
	for sim in factories:
		if not sim.state.unlocked:
			continue
		var cap := float(sim.stats.get("offline_hours", 8.0)) * 3600.0
		caps[sim.data.id] = minf(elapsed_seconds, cap) if sim.steady_rate() > 0.0 else 0.0
		counted = maxf(counted, float(caps[sim.data.id]))
		before[sim.data.id] = {"made": sim.state.cylinders_made, "earned": sim.state.earned}
	var t := 0.0
	while t < counted - 1e-6:
		var dt := minf(OFFLINE_STEP, counted - t)
		for sim in factories:
			if sim.state.unlocked and t < float(caps.get(sim.data.id, 0.0)):
				sim.offline_produce(dt)
				sim.offline_wholesale(dt)
		sales.offline_step(dt)
		t += dt
	var trade := contracts.offline_end(counted)
	var parts: Array = []
	var total_cash := 0.0
	var total_made := 0.0
	var capped := false
	for sim in factories:
		if not before.has(sim.data.id) or float(caps[sim.data.id]) <= 0.0:
			continue
		var made := sim.state.cylinders_made - float(before[sim.data.id]["made"])
		var cash := sim.state.earned - float(before[sim.data.id]["earned"])
		if made <= 0.0 and cash <= 0.0:
			continue
		capped = capped or elapsed_seconds > float(caps[sim.data.id])
		total_cash += cash
		total_made += made
		parts.append({"factory": sim.data.id, "name": sim.data.name, "away_seconds": elapsed_seconds, "counted_seconds": caps[sim.data.id],
			"capped": elapsed_seconds > float(caps[sim.data.id]), "cylinders": made, "contracted": 0.0, "cash": cash})
	if parts.is_empty() and trade.is_empty():
		return {}
	var summary := {"away_seconds": elapsed_seconds, "counted_seconds": counted, "capped": capped, "cylinders": total_made, "cash": total_cash, "factories": parts}
	if not trade.is_empty():
		summary["contracts"] = trade
	var office := sales.offline_report()
	if not office.is_empty():
		summary["sales"] = office
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
		# warehouse orders were paid lorry by lorry as they left (see _on_shipment_left): only the bonus is new
		sim.credit_contract_payout(bonus if sim.stock_enabled() else base + bonus)


func _on_shipment_left(c: Contract, _units: float, amount: float) -> void:
	var sim := factory(c.factory)
	if sim != null:
		sim.credit_contract_payout(amount)


func _on_contract_failed(c: Contract, _reason: String, units: float) -> void:
	var sim := factory(c.factory)
	if sim != null and units > 0.0:
		sim.release_stock(units)
