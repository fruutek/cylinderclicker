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
	return hit


# ---------------------------------------------------------------- economy
func sale_price() -> float:
	return float(product["value"]) * float(stats.get("sell_value", 1.0))


func material_cost() -> float:
	return float(product["material_cost"]) * float(stats.get("material_cost", 1.0))


## Labour, energy and consumables per cylinder (zero for simple products).
func manufacturing_cost() -> float:
	return float(product.get("manufacturing_cost", 0.0)) * float(stats.get("manufacturing_cost", 1.0))


## Every cost is deducted exactly once, here, when a cylinder is sold.
func profit_per_cylinder() -> float:
	return maxf(sale_price() - material_cost() - manufacturing_cost(), 0.0)


## Automatic cylinders per second (no clicking).
func steady_rate() -> float:
	return line.steady_rate()


func income_per_second() -> float:
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


func is_visible(id: String) -> bool:
	var def: Dictionary = data.upgrade_by_id[id]
	if bool(def.get("stock", false)) and not stock_enabled():
		return false             # warehouse and sales upgrades only exist when stock is kept
	return state.earned >= float(def.get("unlock_at", 0)) or state.level(id) > 0


func can_afford(id: String) -> bool:
	return not is_maxed(id) and company.cash >= cost(id)


func buy(id: String) -> bool:
	if not data.upgrade_by_id.has(id) or not is_visible(id) or not can_afford(id):
		return false
	company.cash -= cost(id)
	state.upgrade_levels[id] = state.level(id) + 1
	refresh()
	cash_changed.emit()
	upgrade_purchased.emit(id, state.level(id))
	return true


## Every cylinder that leaves the line is either sold or built for a contract,
## never both: contracts take their share first and only the rest earns sale
## revenue. With no active contract the whole shipment is sold, exactly as before.
func _on_line_shipped(count: float, sku_index: int = -1) -> void:
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
