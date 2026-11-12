class_name GameSession
extends RefCounted
## The whole game minus presentation: owns the persistent state, derived
## stats, the economy and the production line. It has no dependency on the
## scene tree, so it can be driven by the real game, by tests, or by a
## balancing bot in exactly the same way.

signal cash_changed
signal shipped(count: float, amount: float)
signal upgrade_purchased(id: String, level: int)
signal stats_changed
signal clicked(stations: Array)
signal station_finished(index: int)

const OFFLINE_MIN_SECONDS := 60.0
const RATE_WINDOW := 10          # seconds averaged for the live rate read-out

var data: GameData
var state: GameState
var catalog: ProductCatalog
var layout: LineLayout
var line: ProductionLine
var stats: Dictionary = {}
var product: Dictionary = {}

var _buckets: Array[float] = []
var _bucket_time := 0.0


func _init(p_data: GameData) -> void:
	data = p_data
	catalog = ProductCatalog.new(data.products)
	layout = LineLayout.new(data)
	line = ProductionLine.new()
	line.setup(data.stations.size(), layout.belt_lengths)
	line.shipped.connect(_on_line_shipped)
	line.station_finished.connect(_on_line_station_finished)
	_buckets.resize(RATE_WINDOW)
	_buckets.fill(0.0)
	new_game()


func new_game() -> void:
	state = GameState.new()
	state.current_product = catalog.starting_product()
	state.unlocked_products = ["copper", "standard"]
	line.clear()
	_buckets.fill(0.0)
	refresh()


func load_state(d: Dictionary) -> void:
	state = GameState.new()
	state.from_dict(d)
	if not catalog.is_valid(state.current_product):
		state.current_product = catalog.starting_product()
	if state.unlocked_products.is_empty():
		state.unlocked_products = ["copper", "standard"]
	# Drop levels for upgrades that no longer exist; clamp to max level.
	for id: String in state.upgrade_levels.keys():
		if not data.upgrade_by_id.has(id):
			state.upgrade_levels.erase(id)
		else:
			var max_level := int(data.upgrade_by_id[id].get("max_level", 0))
			if max_level > 0:
				state.upgrade_levels[id] = mini(state.upgrade_levels[id], max_level)
	line.clear()
	refresh()


## Recomputes every derived value after anything changes.
func refresh() -> void:
	stats = StatBlock.compute(data, state)
	product = catalog.compose(state.current_product)
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
	state.play_seconds += dt
	_bucket_time += dt
	while _bucket_time >= 1.0:
		_bucket_time -= 1.0
		_buckets.pop_front()
		_buckets.append(0.0)
	line.tick(dt)


func click() -> Array[int]:
	state.total_clicks += 1
	var hit := line.click()
	clicked.emit(hit)
	return hit


# ---------------------------------------------------------------- economy
func sale_price() -> float:
	return float(product["value"]) * float(stats.get("sell_value", 1.0))


func material_cost() -> float:
	return float(product["material_cost"]) * float(stats.get("material_cost", 1.0))


func profit_per_cylinder() -> float:
	return maxf(sale_price() - material_cost(), 0.0)


## Automatic cylinders per second (no clicking).
func steady_rate() -> float:
	return line.steady_rate()


func income_per_second() -> float:
	return steady_rate() * profit_per_cylinder()


## Average cylinders per minute actually shipped over the last few seconds.
func recent_rate_per_min() -> float:
	var total := 0.0
	for b in _buckets:
		total += b
	return total / float(RATE_WINDOW) * 60.0


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
	return state.lifetime_earned >= float(data.upgrade_by_id[id].get("unlock_at", 0)) or state.level(id) > 0


func can_afford(id: String) -> bool:
	return not is_maxed(id) and state.cash >= cost(id)


func buy(id: String) -> bool:
	if not data.upgrade_by_id.has(id) or not is_visible(id) or not can_afford(id):
		return false
	state.cash -= cost(id)
	state.upgrade_levels[id] = state.level(id) + 1
	refresh()
	cash_changed.emit()
	upgrade_purchased.emit(id, state.level(id))
	return true


func _on_line_shipped(count: float) -> void:
	var amount := count * profit_per_cylinder()
	_credit(count, amount)
	_buckets[_buckets.size() - 1] += count
	state.best_rate_per_min = maxf(state.best_rate_per_min, recent_rate_per_min())
	shipped.emit(count, amount)


func _on_line_station_finished(index: int) -> void:
	station_finished.emit(index)


func _credit(count: float, amount: float) -> void:
	state.cash = NumFmt.clamp_value(state.cash + amount)
	state.lifetime_earned = NumFmt.clamp_value(state.lifetime_earned + amount)
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
	if cylinders < 1.0:
		return {}
	var amount := cylinders * profit_per_cylinder()
	_credit(cylinders, amount)
	return {
		"away_seconds": elapsed_seconds,
		"counted_seconds": counted,
		"capped": elapsed_seconds > cap,
		"cylinders": cylinders,
		"cash": amount,
	}
