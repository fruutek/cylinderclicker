class_name FactorySim
extends RefCounted
## One factory building minus presentation: its upgrades, derived stats,
## economy and production line. Every factory the company owns has one of
## these and they all keep running whether or not they are on screen.
## Money is paid into / taken from the shared company state.
## No dependency on the scene tree, so the game, the tests and the
## balancing bot all drive it in exactly the same way.

signal cash_changed
signal shipped(count: float, amount: float)
signal upgrade_purchased(id: String, level: int)
signal stats_changed
signal clicked(stations: Array)
signal station_finished(index: int)
signal stocked(count: float, sku_id: String)                  # finished cylinders went into the warehouse
signal dispatched(cylinders: float, money: float)           # the delivery van left with this load and was paid (classic game)
signal produced(count: float, variant_id: String)             # cylinders were made (live or while away)
signal line_full(stations: Array)                            # a tap found these stations holding a finished cylinder with nowhere to go
signal sold_stock(units: float, amount: float, how: String)   # cylinders left for money ("order", "contract" or "wholesale")

const OFFLINE_MIN_SECONDS := 60.0
const RATE_WINDOW := 10          # seconds averaged for the live rate read-out

var data: FactoryDef             # this factory's definition
var company: GameState           # shared company state (cash lives here)
var state: FactoryState          # this factory's own persistent state
var catalog: ProductCatalog
var layout: LineLayout
var line: ProductionLine
var contracts: ContractBook = null   # the company's trade contracts (set by GameSession); null = none
var stats: Dictionary = {}
var product: Dictionary = {}

var _buckets: Array[float] = []        # cylinders shipped per second (all of them)
var _sale_buckets: Array[float] = []   # ...of which sold (the rest went to contracts)
var _income_buckets: Array[float] = [] # money earned per second (stock mode)
var _bucket_time := 0.0

# --- stock keeping (Expansion 4)
var classic := false                   # the classic game: cylinder variants + a delivery van; no warehouse, contracts or customers
var bay := DispatchBay.new()           # the delivery van's bay (classic)
var order_variant := ""                 # what an accepted bonus order wants made right now ("" = none)
var sku_catalog: SkuCatalog = null
var skus: Array = []                   # this factory's SKUs (see SkuCatalog); a belt token carries an index into this
var warehouse := Warehouse.new()
var sales: SalesOffice = null
var current_sku := 0                   # what the first station was last loaded with (shown in the HUD)
var _planner_clock := 0.0
var _planner_idle_until := 0.0
var _offline_budget := 0.0
var _prod_ema := 0.0                   # cylinders a second actually made, smoothed over about two minutes (what customers sense)


func _init(p_def: FactoryDef, p_catalog: ProductCatalog, p_skus: SkuCatalog = null) -> void:
	data = p_def
	catalog = p_catalog
	sku_catalog = p_skus
	if sku_catalog != null:
		skus = sku_catalog.for_factory(data.id)
	layout = LineLayout.new(data)
	line = ProductionLine.new()
	line.setup(data.stations.size(), layout.belt_lengths)
	line.shipped.connect(_on_line_shipped)
	line.station_finished.connect(_on_line_station_finished)
	_buckets.resize(RATE_WINDOW)
	_buckets.fill(0.0)
	_sale_buckets.resize(RATE_WINDOW)
	_sale_buckets.fill(0.0)
	_income_buckets.resize(RATE_WINDOW)
	_income_buckets.fill(0.0)
	state = FactoryState.new()
	company = GameState.new()


## Attaches this factory to the company and its (new or loaded) state.
func bind(p_company: GameState, p_state: FactoryState) -> void:
	company = p_company
	state = p_state
	# Drop levels for upgrades that no longer exist; clamp to max level.
	for id: String in state.upgrade_levels.keys():
		if not data.upgrade_by_id.has(id):
			state.upgrade_levels.erase(id)
		else:
			var max_level := int(data.upgrade_by_id[id].get("max_level", 0))
			if max_level > 0:
				state.upgrade_levels[id] = mini(state.upgrade_levels[id], max_level)
	line.clear()
	_buckets.fill(0.0)
	_sale_buckets.fill(0.0)
	_income_buckets.fill(0.0)
	refresh()
	if not state.line.is_empty():
		line.from_dict(state.line)
	_bind_stock()


## Copies the cylinders currently on the line into the state, ready to save.
func snapshot() -> void:
	state.line = line.to_dict()
	if classic:
		state.bay = bay.to_dict()
	state.warehouse = warehouse.to_dict()


## Recomputes every derived value after anything changes.
func refresh() -> void:
	stats = StatBlock.compute(data, state)
	product = catalog.compose(data.product_spec)
	var works: Array[float] = []
	var rates: Array[float] = []
	for i in data.stations.size():
		works.append(station_work(i))
		rates.append(station_rate(i))
	line.set_params(works, rates, float(stats.get("belt_speed", 48.0)), float(stats.get("click_power", 1.0)), float(stats.get("click_boost", 0.0)))
	warehouse.capacity = maxi(int(floorf(float(stats.get("warehouse_capacity", 24.0)) + 1e-6)), 1)
	if classic:
		_apply_bay_stats()
	stats_changed.emit()
	planner_wake()


# ------------------------------------------------------------- production
func station_level(index: int) -> int:
	return state.level(GameData.machine_id(data.stations[index]["id"]))


func rate_for_level(index: int, lvl: int) -> float:
	if lvl <= 0:
		return 0.0
	return float(data.stations[index]["base_rate"]) * lvl * data.milestone_multiplier(lvl) * float(stats.get("machine_speed", 1.0))


func station_rate(index: int) -> float:
	return rate_for_level(index, station_level(index))


func station_work(index: int) -> float:
	return float(data.stations[index]["work"]) * float(product.get("work_mult", 1.0))


## Cylinders per minute a station could handle at a given machine level.
func station_capacity_per_min(index: int, lvl: int) -> float:
	return rate_for_level(index, lvl) / station_work(index) * 60.0


func all_automated() -> bool:
	for i in data.stations.size():
		if station_level(i) <= 0:
			return false
	return true


func automated_count() -> int:
	var n := 0
	for i in data.stations.size():
		if station_level(i) > 0:
			n += 1
	return n


func tick(dt: float) -> void:
	_bucket_time += dt
	while _bucket_time >= 1.0:
		_bucket_time -= 1.0
		_buckets.pop_front()
		_buckets.append(0.0)
		_sale_buckets.pop_front()
		_sale_buckets.append(0.0)
		_income_buckets.pop_front()
		_income_buckets.append(0.0)
	_planner_clock += dt
	if classic:
		bay.tick(dt)
	_prod_ema += (_buckets_last_rate() - _prod_ema) * minf(dt / 40.0, 1.0)
	line.tick(dt)
	if stock_enabled():
		state.wholesale_timer += dt
		if state.wholesale_timer >= sku_catalog.num("wholesale_interval", 15.0):
			state.wholesale_timer = 0.0
			collect_wholesale()


func click() -> Array[int]:
	company.total_clicks += 1
	var hit := line.click()
	clicked.emit(hit)
	if classic and not line.last_blocked.is_empty():
		line_full.emit(line.last_blocked.duplicate())
	return hit


# ---------------------------------------------------------------- economy
func sale_price() -> float:
	if variants_enabled():
		return sku_price(variant_index())
	return float(product["value"]) * float(stats.get("sell_value", 1.0))


func material_cost() -> float:
	if variants_enabled():
		return sku_material(variant_index())
	return float(product["material_cost"]) * float(stats.get("material_cost", 1.0))


## Labour, energy and consumables per cylinder (zero for simple products).
func manufacturing_cost() -> float:
	if variants_enabled():
		return sku_mfg(variant_index())
	return float(product.get("manufacturing_cost", 0.0)) * float(stats.get("manufacturing_cost", 1.0))


## Every cost is deducted exactly once, here, when a cylinder is sold.
func profit_per_cylinder() -> float:
	return maxf(sale_price() - material_cost() - manufacturing_cost(), 0.0)


## Automatic cylinders per second (no clicking).
func steady_rate() -> float:
	return line.steady_rate()


func income_per_second() -> float:
	if classic and variants_enabled():
		return effective_rate() * profit_per_cylinder() * (1.0 + bay.bonus)
	return steady_rate() * profit_per_cylinder()


## Cylinders per second a contract planner can rely on: the hands-free rate once
## the line is fully automated, otherwise an estimate that includes a player
## clicking now and then (scaled down, since a click rate is never guaranteed).
func planning_rate(clicks_per_second: float, click_factor: float) -> float:
	if all_automated():
		return steady_rate()
	return line.capacity_rate(clicks_per_second) * click_factor


## Average cylinders per minute actually shipped over the last few seconds.
func recent_rate_per_min() -> float:
	var total := 0.0
	for b in _buckets:
		total += b
	return total / float(RATE_WINDOW) * 60.0


## Average cylinders per minute actually sold (shipped minus those built for contracts).
func recent_sales_per_min() -> float:
	var total := 0.0
	for b in _sale_buckets:
		total += b
	return total / float(RATE_WINDOW) * 60.0


## What the factory is really earning from sales right now, per second.
func recent_income_per_second() -> float:
	if stock_enabled():
		var total := 0.0
		for b in _income_buckets:
			total += b
		return total / float(RATE_WINDOW)
	return recent_sales_per_min() / 60.0 * profit_per_cylinder()


func level(id: String) -> int:
	return state.level(id)


func cost(id: String) -> float:
	return cost_at_level(id, state.level(id))


func cost_at_level(id: String, lvl: int) -> float:
	var def: Dictionary = data.upgrade_by_id[id]
	return NumFmt.clamp_value(floorf(float(def["base_cost"]) * pow(float(def["cost_growth"]), lvl)))


func is_maxed(id: String) -> bool:
	var max_level := int(data.upgrade_by_id[id].get("max_level", 0))
	return max_level > 0 and state.level(id) >= max_level


## Whether this game ever offers the upgrade at all (a warehouse upgrade is never offered in the classic game):
## locked rows are only shown for upgrades that will eventually appear.
func is_offered(id: String) -> bool:
	var def: Dictionary = data.upgrade_by_id[id]
	if bool(def.get("stock", false)) and not stock_enabled():
		return false
	if bool(def.get("classic", false)) and not classic:
		return false
	return true


func is_visible(id: String) -> bool:
	var def: Dictionary = data.upgrade_by_id[id]
	if bool(def.get("stock", false)) and not stock_enabled():
		return false             # warehouse and sales upgrades only exist when stock is kept
	if bool(def.get("classic", false)) and not classic:
		return false             # vans and new products belong to the classic game
	return state.earned >= float(def.get("unlock_at", 0)) or state.level(id) > 0


func can_afford(id: String) -> bool:
	return not is_maxed(id) and company.cash >= cost(id)


func buy(id: String) -> bool:
	if not data.upgrade_by_id.has(id) or not is_visible(id) or not can_afford(id):
		return false
	company.cash -= cost(id)
	state.upgrade_levels[id] = state.level(id) + 1
	refresh()
	if classic and str(data.upgrade_by_id[id].get("variant", "")) != "":
		select_variant(str(data.upgrade_by_id[id]["variant"]))      # a new product is made as soon as it is bought
	cash_changed.emit()
	upgrade_purchased.emit(id, state.level(id))
	return true


## Every cylinder that leaves the line is either sold or built for a contract,
## never both: contracts take their share first and only the rest earns sale
## revenue. With no active contract the whole shipment is sold, exactly as before.
func _on_line_shipped(count: float, sku_index: int = -1) -> void:
	if variants_enabled():
		return              # the classic game hands cylinders to its dispatch pad as they arrive (_dispatch_accept)
	if stock_enabled():
		_receive_stock(count, sku_index)
		return
	var contracted := 0.0
	if contracts != null:
		contracted = contracts.route(data.id, count)
	var sold := count - contracted
	var amount := sold * profit_per_cylinder()
	_credit(count, amount)
	state.cylinders_sold += sold
	state.cylinders_contracted += contracted
	_buckets[_buckets.size() - 1] += count
	_sale_buckets[_sale_buckets.size() - 1] += sold
	state.best_rate_per_min = maxf(state.best_rate_per_min, recent_rate_per_min())
	shipped.emit(count, amount)


## A customer contract has been paid: add the money to the company and to this
## factory's earnings (the cylinders themselves were counted when built).
func credit_contract_payout(amount: float) -> void:
	company.cash = NumFmt.clamp_value(company.cash + amount)
	company.lifetime_earned = NumFmt.clamp_value(company.lifetime_earned + amount)
	state.earned = NumFmt.clamp_value(state.earned + amount)
	cash_changed.emit()


## A contract failed or was cancelled: the cylinders already built for it go
## back to general stock and are sold at today's price, so nothing is wasted.
func release_stock(units: float) -> float:
	if units <= 0.0:
		return 0.0
	var amount := units * profit_per_cylinder()
	state.cylinders_contracted -= units      # may dip below zero for a moment during an offline catch-up
	state.cylinders_sold += units
	credit_contract_payout(amount)
	return amount


func _on_line_station_finished(index: int) -> void:
	station_finished.emit(index)


func _credit(count: float, amount: float) -> void:
	company.cash = NumFmt.clamp_value(company.cash + amount)
	company.lifetime_earned = NumFmt.clamp_value(company.lifetime_earned + amount)
	state.earned = NumFmt.clamp_value(state.earned + amount)
	state.cylinders_made = NumFmt.clamp_value(state.cylinders_made + count)
	cash_changed.emit()


# ---------------------------------------------------------------- offline
## Credits production for time spent away. Only a fully automated line earns
## offline, at its steady (bottleneck) rate, capped at `offline_hours`.
## Returns {} if nothing was earned, else a summary for the welcome-back box.
func apply_offline(elapsed_seconds: float) -> Dictionary:
	if stock_enabled():
		return {}            # in stock mode the company steps every factory together (GameSession.apply_offline)
	if elapsed_seconds < OFFLINE_MIN_SECONDS:
		return {}
	if variants_enabled():
		return _apply_offline_classic(elapsed_seconds)
	var rate := steady_rate()
	if rate <= 0.0:
		return {}
	var cap := float(stats.get("offline_hours", 8.0)) * 3600.0
	var counted := minf(elapsed_seconds, cap)
	var cylinders := floorf(rate * counted)
	# Contracts take their share of the unattended output first (stepping through
	# completions and deadlines); the rest is sold as it always was.
	var contracted := 0.0
	if contracts != null:
		contracted = contracts.offline_factory(data.id, rate, counted)
	cylinders = maxf(cylinders, contracted)
	if cylinders < 1.0:
		return {}
	var sold := cylinders - contracted
	var amount := sold * profit_per_cylinder()
	_credit(cylinders, amount)
	state.cylinders_sold += sold
	state.cylinders_contracted += contracted
	if variants_enabled():
		produced.emit(cylinders, sku_id(variant_index()))
	return {
		"factory": data.id,
		"name": data.name,
		"away_seconds": elapsed_seconds,
		"counted_seconds": counted,
		"capped": elapsed_seconds > cap,
		"cylinders": cylinders,
		"contracted": contracted,
		"cash": amount,
	}


# ============================================================ stock keeping
func stock_enabled() -> bool:
	return company.stock_mode and not skus.is_empty()


func sku_id(i: int) -> String:
	return str(skus[i]["id"])


func sku_index(id: String) -> int:
	for i in skus.size():
		if skus[i]["id"] == id:
			return i
	return -1


## Specialist machinery for this SKU has been bought (and the factory is open).
func sku_available(i: int) -> bool:
	for req: Dictionary in skus[i].get("requires", []):
		if state.level(str(req["upgrade"])) < int(req.get("level", 1)):
			return false
	return true


func sku_requirement_text(i: int) -> String:
	for req: Dictionary in skus[i].get("requires", []):
		if state.level(str(req["upgrade"])) < int(req.get("level", 1)):
			var up: Dictionary = data.upgrade_by_id.get(str(req["upgrade"]), {})
			return "Needs: %s" % str(up.get("name", req["upgrade"]))
	return ""


func sku_work(i: int) -> float:
	return float(skus[i].get("work_mult", 1.0))


func sku_price(i: int) -> float:
	return float(product["value"]) * float(skus[i].get("value_mult", 1.0)) * float(stats.get("sell_value", 1.0))


func sku_material(i: int) -> float:
	return float(product["material_cost"]) * float(skus[i].get("material_mult", 1.0)) * float(stats.get("material_cost", 1.0))


func sku_mfg(i: int) -> float:
	return float(product.get("manufacturing_cost", 0.0)) * float(skus[i].get("mfg_mult", 1.0)) * float(stats.get("manufacturing_cost", 1.0))


## What one cylinder of this SKU nets when sold at list price (costs are consumed here, exactly once).
func sku_profit(i: int) -> float:
	return maxf(sku_price(i) - sku_material(i) - sku_mfg(i), 0.0)


## Cylinders per minute of this SKU the factory can make (hands-free, or click-assisted before it is automated).
func sku_rate_per_min(i: int) -> float:
	return planning_rate(1.5, 0.85) * 60.0 / sku_work(i)


func priority_rank(id: String) -> int:
	var r := state.priority.find(id)
	return r if r >= 0 else 1000 + sku_index(id)


## The stock level automatic production works towards for this SKU.
func effective_target(i: int) -> int:
	if auto_targets_active():
		return recommended_target(i)
	return int(state.targets.get(sku_id(i), 0))


func auto_targets_active() -> bool:
	return state.auto_targets or float(stats.get("auto_targets", 0.0)) > 0.0 or (sales != null and sales.auto_targets())


func recommended_target(i: int) -> int:
	if sales != null:
		var r := sales.recommended(data.id, sku_id(i))
		if r > 0:
			return r
	return cover_target(i)


## Without a sales rep's forecast: enough stock to cover a few minutes of this factory's output, split by how
## often customers ask for each product, never less than the starting target.
func cover_target(i: int) -> int:
	var total_weight := 0.0
	for j in skus.size():
		if sku_available(j):
			total_weight += float(skus[j].get("weight", 1.0))
	var share := float(skus[i].get("weight", 1.0)) / maxf(total_weight, 1.0)
	var rate := maxf(steady_rate(), demand_rate()) * 60.0       # cylinders a minute
	var units := sku_catalog.num("target_cover_minutes", 3.0) * rate
	var limit := float(warehouse.capacity) * sku_catalog.num("target_fill_max", 0.8)
	units = minf(units, limit)                                   # never plan to hold more than the shelves take
	return maxi(int(ceilf(units * share)), int(skus[i].get("default_target", 0)))


## Cylinders customers are waiting for that are not yet in stock or on the line.
func backlog(i: int) -> float:
	return sales.backlog(data.id, sku_id(i)) if sales != null else 0.0


## Line time (in "baseline cylinders") the factory still owes its customers and the cylinders on the belts:
## every product shares the same line, so a promise has to count all of it.
func owed_work() -> float:
	var work := 0.0
	for i in skus.size():
		work += (backlog(i) - float(warehouse.wip.get(sku_id(i), 0.0))) * sku_work(i)
	return maxf(work, 0.0)


## The upgrade most worth buying next, in plain terms: more shelves when they are full, then the machine that
## limits the line (or the cheapest one still to automate), then the cheapest of the rest. "" = nothing to buy.
func next_upgrade() -> String:
	if stock_enabled() and data.upgrade_by_id.has("warehouse") and warehouse.usage_fraction() >= 0.85 and is_visible("warehouse") and not is_maxed("warehouse"):
		return "warehouse"
	var machine := ""
	if all_automated():
		var idx := line.bottleneck_index()
		for m: Dictionary in data.machines:
			if int(m["station_index"]) == idx and is_visible(str(m["id"])) and not is_maxed(str(m["id"])):
				machine = str(m["id"])
	else:
		var cheapest := INF
		for m: Dictionary in data.machines:
			var id := str(m["id"])
			if level(id) == 0 and is_visible(id) and cost(id) < cheapest:
				cheapest = cost(id)
				machine = id
	if machine != "" and not can_afford(machine):
		# While the machine is still out of reach, a cheap boost you can buy right now is the better next step.
		var cheap := ""
		for u: Dictionary in data.upgrades:
			var cid := str(u["id"])
			if bool(u.get("stock", false)) or not is_visible(cid) or is_maxed(cid) or not can_afford(cid):
				continue
			if cost(cid) <= cost(machine) * 0.5 and (cheap == "" or cost(cid) < cost(cheap)):
				cheap = cid
		if cheap != "":
			return cheap
	if machine != "":
		return machine
	var pick := ""
	for u: Dictionary in data.upgrades:
		var uid := str(u["id"])
		if u.get("kind", "") == "machine" or not is_visible(uid) or is_maxed(uid) or uid == "warehouse":
			continue
		if pick == "" or cost(uid) < cost(pick):
			pick = uid
	return pick


func planner_wake() -> void:
	_planner_idle_until = 0.0


## What the first station should make next, or -1 for nothing. Customers waiting come first (earliest
## promise first); then the SKU furthest below its target; a person clicking may stockpile beyond target.
func planner_pick(manual: bool) -> int:
	var best := -1
	var best_key := INF
	var any_backlog := owed_work() > 0.0
	if state.focus_backlog and not any_backlog:
		state.focus_backlog = false            # everybody has been served: back to normal
	for i in skus.size():
		if not sku_available(i):
			continue
		var id := sku_id(i)
		var spill := manual and state.wholesale_on          # a person is working the line and the wholesaler will take the surplus
		if not spill and int(floorf(warehouse.free_space() / warehouse.space_of(id) + 1e-9)) < 1:
			continue
		var wip := float(warehouse.wip.get(id, 0.0))
		var key := INF
		if backlog(i) - wip > 0.5:
			key = (sales.due_rank(data.id, id) if sales != null else 0.0)
		elif (state.auto_production or manual) and not state.focus_backlog:
			var target := effective_target(i)
			var have := float(warehouse.available(id)) + wip
			if float(target) - have > 0.5:
				key = 1.0e12 + have / float(maxi(target, 1)) + 0.001 * float(priority_rank(id))
			elif manual:
				key = 2.0e12 + float(priority_rank(id))
		if key < best_key:
			best_key = key
			best = i
	return best


## How many cylinders of that SKU are wanted right now (at least 1).
func planner_need(i: int, _manual: bool) -> float:
	var id := sku_id(i)
	var wip := float(warehouse.wip.get(id, 0.0))
	var owed := backlog(i) - wip
	if owed > 0.5:
		return owed
	var shortfall := float(effective_target(i)) - (float(warehouse.available(id)) + wip)
	return maxf(shortfall, 1.0)


func _spawn(manual: bool) -> Dictionary:
	if not manual and _planner_clock < _planner_idle_until:
		return {}
	var pick := planner_pick(manual)
	if pick < 0:
		_planner_idle_until = _planner_clock + 0.25
		return {}
	var id := sku_id(pick)
	var room := floorf(warehouse.free_space() / warehouse.space_of(id) + 1e-9)
	if manual and state.wholesale_on:
		room = maxf(room, line.batch)
	var count := clampf(line.batch, 1.0, maxf(1.0, minf(planner_need(pick, manual), room)))
	warehouse.wip[id] = float(warehouse.wip.get(id, 0.0)) + count
	current_sku = pick
	return {"sku": pick, "work_mult": sku_work(pick), "count": count}


## Instantaneous output of the last few seconds (cylinders a second), the input to the smoothed rate.
func _buckets_last_rate() -> float:
	var total := 0.0
	for b in _buckets:
		total += b
	return total / float(RATE_WINDOW)


## What customers believe the factory can supply: its planning rate, or what it has really been making if that is more
## (a person clicking hard builds more than the cautious estimate). Orders and calls are sized from this.
func demand_rate() -> float:
	return maxf(planning_rate(1.5, 0.85), _prod_ema)


## Finished cylinders come off the line into the warehouse. Nothing is sold here.
func _receive_stock(count: float, sku_index_on_token: int) -> void:
	var i := sku_index_on_token if sku_index_on_token >= 0 and sku_index_on_token < skus.size() else 0
	var id := sku_id(i)
	warehouse.wip[id] = maxf(float(warehouse.wip.get(id, 0.0)) - count, 0.0)
	state.cylinders_made = NumFmt.clamp_value(state.cylinders_made + count)
	var overflow := warehouse.receive(id, count)
	if overflow > 0:
		# No room: the surplus goes to the wholesaler, it is never lost and never stored past capacity.
		_sell_units(i, overflow, "wholesale", true)
	_buckets[_buckets.size() - 1] += count
	state.best_rate_per_min = maxf(state.best_rate_per_min, recent_rate_per_min())
	stocked.emit(count, id)
	if sales != null:
		sales.on_stock(data.id, id)
	shipped.emit(count, 0.0)


## Money for cylinders that left: the cash side of a sale. `net` is already net of the cylinders' costs.
func credit_sale(net: float, units: float) -> void:
	company.cash = NumFmt.clamp_value(company.cash + net)
	company.lifetime_earned = NumFmt.clamp_value(company.lifetime_earned + net)
	state.earned = NumFmt.clamp_value(state.earned + net)
	state.cylinders_sold = NumFmt.clamp_value(state.cylinders_sold + units)
	_income_buckets[_income_buckets.size() - 1] += net
	cash_changed.emit()


## Sells units straight to the wholesaler: `diverted` = they never reached the shelves.
func _sell_units(i: int, units: int, how: String, diverted: bool = false) -> float:
	var id := sku_id(i)
	if diverted:
		warehouse.note_overflow_sale(id, units)
	else:
		units = warehouse.sell_wholesale(id, units)
	if units <= 0:
		return 0.0
	var net := float(units) * sku_profit(i) * sku_catalog.num("wholesale_share", 0.8)
	credit_sale(net, float(units))
	sold_stock.emit(float(units), net, how)
	return net


## The wholesaler collects surplus above target (never reserved stock), a limited amount each visit.
func collect_wholesale() -> float:
	if not stock_enabled() or not state.wholesale_on:
		return 0.0
	var cap := maxi(int(float(warehouse.capacity) * sku_catalog.num("wholesale_cap_fraction", 0.15)), 1)
	var earned := 0.0
	for i in skus.size():
		if cap <= 0:
			break
		var id := sku_id(i)
		var surplus := warehouse.available(id) - effective_target(i)
		if surplus > 0:
			var n := mini(surplus, cap)
			cap -= n
			earned += _sell_units(i, n, "wholesale")
	if earned > 0.0:
		planner_wake()
	return earned


## Sells every unreserved cylinder above target right now (the player pressed the button).
func sell_surplus_now() -> float:
	var earned := 0.0
	for i in skus.size():
		var surplus := warehouse.available(sku_id(i)) - effective_target(i)
		if surplus > 0:
			earned += _sell_units(i, surplus, "wholesale")
	planner_wake()
	return earned


func set_target(id: String, value: int) -> void:
	state.targets[id] = maxi(value, 0)
	planner_wake()


## Moves a SKU to the top of the production priority list.
func prioritise(id: String) -> void:
	state.priority.erase(id)
	state.priority.push_front(id)
	planner_wake()


func _bind_stock() -> void:
	if classic:
		_bind_classic()
		return
	warehouse = Warehouse.new()
	if skus.is_empty():
		return
	warehouse.from_dict(state.warehouse)
	for s: Dictionary in skus:
		warehouse.space[s["id"]] = float(s.get("space", 1.0))
		if not state.targets.has(s["id"]):
			state.targets[s["id"]] = int(s.get("default_target", 0))
		if not state.priority.has(s["id"]):
			state.priority.append(s["id"])
	warehouse.capacity = maxi(int(floorf(float(stats.get("warehouse_capacity", 24.0)) + 1e-6)), 1)
	# Cylinders still on the belts count against the shelf space they will need.
	for t in line.all_tokens():
		var i := t.sku if t.sku >= 0 and t.sku < skus.size() else 0
		warehouse.wip[sku_id(i)] = float(warehouse.wip.get(sku_id(i), 0.0)) + t.count
	line.spawn_cb = Callable(self, "_spawn") if company.stock_mode else Callable()
	planner_wake()


## What the factory makes unattended: the same planner as live play, stepped. Returns {sku id: units}.
func offline_produce(dt: float) -> Dictionary:
	var out := {}
	var rate := steady_rate()
	if rate <= 0.0 or not stock_enabled():
		return out
	_offline_budget += rate * dt
	for guard in 60:
		var i := planner_pick(false)
		if i < 0:
			_offline_budget = 0.0          # nothing is wanted: idle time is not banked
			break
		var id := sku_id(i)
		var room := int(floorf(warehouse.free_space() / warehouse.space_of(id) + 1e-9))
		var n := mini(mini(int(ceilf(planner_need(i, false))), room), int(floorf(_offline_budget / sku_work(i) + 1e-9)))
		if n < 1:
			break
		_offline_budget -= float(n) * sku_work(i)
		warehouse.receive(id, float(n))
		state.cylinders_made = NumFmt.clamp_value(state.cylinders_made + float(n))
		out[id] = int(out.get(id, 0)) + n
		stocked.emit(float(n), id)
		if sales != null:
			sales.on_stock(data.id, id)
	return out


## The wholesaler's visits that fell inside `dt` seconds of unattended time.
func offline_wholesale(dt: float) -> void:
	if not stock_enabled():
		return
	var interval := sku_catalog.num("wholesale_interval", 15.0)
	state.wholesale_timer += dt
	var guard := 0
	while state.wholesale_timer >= interval and guard < 4:
		state.wholesale_timer -= interval
		collect_wholesale()
		guard += 1
	if state.wholesale_timer >= interval:
		state.wholesale_timer = fmod(state.wholesale_timer, interval)


## Brings an older save across: a warehouse big enough for the factory's output, automatic targets,
## and the cylinders that were counted as "built for contracts" become stock reserved for them.
func migrate_to_stock() -> void:
	if skus.is_empty():
		return
	var cover := sku_catalog.num("migration_cover_minutes", 8.0) * 60.0 * maxf(steady_rate(), planning_rate(1.5, 0.85))
	for guard in 60:
		if float(warehouse.capacity) >= cover or not data.upgrade_by_id.has("warehouse"):
			break
		state.upgrade_levels["warehouse"] = state.level("warehouse") + 1
		refresh()
	state.auto_targets = true
	state.auto_production = true
	state.wholesale_on = true


# ============================================================ classic game: variants and the delivery van
func variants_enabled() -> bool:
	return classic and not skus.is_empty()


## The cylinder the line is making: an accepted bonus order's product first, otherwise the player's choice.
func variant_index() -> int:
	if skus.is_empty():
		return 0
	if order_variant != "":
		var o := sku_index(order_variant)
		if o >= 0 and sku_available(o):
			return o
	var i := sku_index(state.variant)
	return i if i >= 0 and sku_available(i) else 0


## The player picks what to make. Returns false if that product is not unlocked.
func select_variant(id: String) -> bool:
	var i := sku_index(id)
	if i < 0 or not sku_available(i):
		return false
	state.variant = id
	stats_changed.emit()
	return true


func _bind_classic() -> void:
	bay = DispatchBay.new()
	bay.from_dict(state.bay)
	bay.departed.connect(_on_bay_departed)
	_apply_bay_stats()
	line.spawn_cb = Callable(self, "_spawn_variant") if not skus.is_empty() else Callable()
	line.exit_cb = Callable(self, "_dispatch_accept") if not skus.is_empty() else Callable()


func _apply_bay_stats() -> void:
	bay.set_stats(float(stats.get("van_capacity", 16.0)), float(stats.get("dispatch_storage", 24.0)),
		float(stats.get("van_away", 10.0)), float(stats.get("delivery_bonus", 0.0)))


func _spawn_variant(_manual: bool) -> Dictionary:
	var i := variant_index()
	return {"sku": i, "work_mult": sku_work(i), "count": line.batch}


## The end of the line offers finished cylinders to dispatch. The pad takes what fits and the rest waits on the
## belt (so the line backs up); returns how many were taken.
func _dispatch_accept(count: float, sku_index_on_token: int) -> float:
	var i := sku_index_on_token if sku_index_on_token >= 0 and sku_index_on_token < skus.size() else variant_index()
	var n := bay.try_add(count, sku_profit(i))
	if n <= 0.0:
		return 0.0
	state.cylinders_made = NumFmt.clamp_value(state.cylinders_made + n)
	_buckets[_buckets.size() - 1] += n
	_sale_buckets[_sale_buckets.size() - 1] += n
	state.best_rate_per_min = maxf(state.best_rate_per_min, recent_rate_per_min())
	produced.emit(n, sku_id(i))
	shipped.emit(n, 0.0)
	return n


func _on_bay_departed(cylinders: float, money: float) -> void:
	company.cash = NumFmt.clamp_value(company.cash + money)
	company.lifetime_earned = NumFmt.clamp_value(company.lifetime_earned + money)
	state.earned = NumFmt.clamp_value(state.earned + money)
	state.cylinders_sold = NumFmt.clamp_value(state.cylinders_sold + cylinders)
	cash_changed.emit()
	dispatched.emit(cylinders, money)


## Cylinders per second dispatch can move for this line (see DispatchBay.throughput).
func dispatch_rate() -> float:
	return bay.throughput(steady_rate())


## What a fully automated line really delivers: the slower of its machines and its dispatch.
func effective_rate() -> float:
	return dispatch_rate() if classic else steady_rate()


## True while production is held up because the pad is full (for the shop's hint): the line has been refused
## at the end for a couple of seconds.
func backed_up() -> bool:
	return classic and line.exit_wait > 2.0


## Unattended time in the classic game. The van keeps making trips, so what was waiting at the pad is delivered
## first; after that the factory can deliver no more than its dispatch can carry (a load per round trip), however
## fast its machines are. Worked out in one step, with no per-frame simulation.
func _apply_offline_classic(elapsed_seconds: float) -> Dictionary:
	var waiting := bay.settle()
	var rate := effective_rate()
	var cap := float(stats.get("offline_hours", 8.0)) * 3600.0
	var counted := minf(elapsed_seconds, cap)
	var made := floorf(rate * counted) if rate > 0.0 else 0.0
	var amount := made * profit_per_cylinder() * (1.0 + bay.bonus) + float(waiting["money"])
	var delivered := made + float(waiting["count"])
	if delivered < 1.0 and amount <= 0.0:
		return {}
	company.cash = NumFmt.clamp_value(company.cash + amount)
	company.lifetime_earned = NumFmt.clamp_value(company.lifetime_earned + amount)
	state.earned = NumFmt.clamp_value(state.earned + amount)
	state.cylinders_made = NumFmt.clamp_value(state.cylinders_made + made)
	state.cylinders_sold = NumFmt.clamp_value(state.cylinders_sold + delivered)
	cash_changed.emit()
	if made > 0.0:
		produced.emit(made, sku_id(variant_index()))
	return {
		"factory": data.id,
		"name": data.name,
		"away_seconds": elapsed_seconds,
		"counted_seconds": counted,
		"capped": elapsed_seconds > cap,
		"cylinders": delivered,
		"contracted": 0.0,
		"cash": amount,
		"dispatch_limited": steady_rate() > dispatch_rate() * 1.02,
	}


## The dispatch upgrade that would move the most extra cylinders for the line as it runs now ("" if none would help).
## The shop flags this row while the line is backed up, so the way out is always one obvious tap.
func dispatch_advice() -> String:
	if not classic:
		return ""
	var p := maxf(steady_rate(), recent_rate_per_min() / 60.0 * 1.5)
	var base := bay.throughput(p)
	var best := ""
	var best_gain := 1e-6
	for id: String in ["van_load", "dispatch_store", "van_speed"]:
		if not data.upgrade_by_id.has(id) or is_maxed(id) or not is_offered(id):
			continue
		var probe := DispatchBay.new()
		probe.set_stats(bay.capacity, bay.storage, bay.away_time, 0.0)
		match id:
			"van_load":
				probe.capacity *= _stat_at(id, "van_capacity", 1.7)
			"dispatch_store":
				probe.storage *= _stat_at(id, "dispatch_storage", 1.8)
			"van_speed":
				probe.away_time = maxf(probe.away_time * _stat_at(id, "van_away", 0.85), DispatchBay.MIN_AWAY)
		var gain := probe.throughput(p) - base
		if gain > best_gain:
			best_gain = gain
			best = id
	return best


## Plain-words effect of the three dispatch upgrades: "Van carries 16 -> 27 a trip". Empty for any other upgrade.
func dispatch_text(id: String) -> String:
	if not classic:
		return ""
	var lvl := level(id)
	var max_level := int(data.upgrade_by_id.get(id, {}).get("max_level", 0))
	var maxed := max_level > 0 and lvl >= max_level
	match id:
		"van_load":
			return "Van carries %s a trip" % _grow_text(bay.capacity, _stat_at(id, "van_capacity", 1.7), maxed, "")
		"dispatch_store":
			return "Pad holds %s" % _grow_text(bay.storage, _stat_at(id, "dispatch_storage", 1.7), maxed, "")
		"van_speed":
			return "Van away %s" % _grow_text(bay.away_time, _stat_at(id, "van_away", 0.85), maxed, " s", 1)
	return ""


func _stat_at(id: String, stat: String, fallback: float) -> float:
	for e: Dictionary in data.upgrade_by_id.get(id, {}).get("effects", []):
		if e.get("stat") == stat:
			return float(e["value"])
	return fallback


func _grow_text(now: float, per_level: float, maxed: bool, unit: String, decimals: int = 0) -> String:
	if maxed:
		return NumFmt.number(now, decimals) + unit
	var next := now * per_level
	if unit != "":
		next = maxf(next, DispatchBay.MIN_AWAY)
	return "%s > %s%s" % [NumFmt.number(now, decimals), NumFmt.number(next, decimals), unit]
