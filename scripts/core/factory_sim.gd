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
var _bucket_time := 0.0


func _init(p_def: FactoryDef, p_catalog: ProductCatalog) -> void:
	data = p_def
	catalog = p_catalog
	layout = LineLayout.new(data)
	line = ProductionLine.new()
	line.setup(data.stations.size(), layout.belt_lengths)
	line.shipped.connect(_on_line_shipped)
	line.station_finished.connect(_on_line_station_finished)
	_buckets.resize(RATE_WINDOW)
	_buckets.fill(0.0)
	_sale_buckets.resize(RATE_WINDOW)
	_sale_buckets.fill(0.0)
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
	refresh()
	if not state.line.is_empty():
		line.from_dict(state.line)


## Copies the cylinders currently on the line into the state, ready to save.
func snapshot() -> void:
	state.line = line.to_dict()


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
	stats_changed.emit()


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
	line.tick(dt)


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
	return state.earned >= float(data.upgrade_by_id[id].get("unlock_at", 0)) or state.level(id) > 0


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
func _on_line_shipped(count: float) -> void:
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
