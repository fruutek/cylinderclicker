class_name DispatchBay
extends RefCounted
## Dispatch of one factory: a pad where finished cylinders wait, and the delivery van that collects them.
## Pure simulation; the view only animates this state.
##
## The pad has a FINITE capacity (`storage`, in cylinders). `try_add` takes as many cylinders as there is room
## for and refuses the rest, which is what makes the line back up when the van is away or too small.
##
##   LOADING  -> the van is at the pad and loads what is waiting there, up to its carrying `capacity`
##               (it never takes more than that). It leaves when it is full, or when the pad has run dry
##               for a moment, or after waiting a few seconds - but never empty-handed.
##   LEAVING  -> it drives off through the door; when it has gone the load is PAID
##   AWAY     -> out delivering (the turnaround, shortened by upgrades); the pad keeps filling meanwhile
##   ARRIVING -> back at the pad, reversing in
##
## Cylinders are conserved: made = delivered + on the pad + on the van (+ what is still on the line).

signal departed(cylinders: float, money: float)       # the van has left with this load: pay `money`
signal returned

enum State { LOADING, LEAVING, AWAY, ARRIVING }

const GATHER := 1.2            # seconds the van waits once the pad is empty before leaving with what it has
const MAX_WAIT := 5.0          # ...and the longest it waits for a fuller load
const LOAD_TIME := 2.0         # seconds a completely full van takes to load
const LEAVE_TIME := 3.0
const ARRIVE_TIME := 1.6
const MIN_AWAY := 2.5

var state: State = State.LOADING
var load := 0.0                # cylinders on the pad
var money := 0.0               # what they are worth
var carry_load := 0.0          # cylinders aboard the van (while it loads and leaves)
var carry_money := 0.0
var timer := 0.0               # seconds left in LEAVING / AWAY / ARRIVING
var waited := 0.0
var idle := 0.0
var trips := 0
var full_time := 0.0           # seconds the pad has been completely full
var capacity := 16.0           # what the van carries on one trip
var storage := 24.0            # what the pad holds
var away_time := 10.0          # turnaround
var bonus := 0.0               # delivery bonus on every trip (upgrades)


func set_stats(p_capacity: float, p_storage: float, p_away: float, p_bonus: float) -> void:
	capacity = maxf(p_capacity, 1.0)
	storage = maxf(p_storage, 1.0)
	away_time = maxf(p_away, MIN_AWAY)
	bonus = maxf(p_bonus, 0.0)


## Room left on the pad.
func room() -> float:
	return maxf(storage - load, 0.0)


func is_full() -> bool:
	return load >= storage - 1e-6


## 0..1 how full the pad is.
func fill() -> float:
	return clampf(load / maxf(storage, 1.0), 0.0, 1.0)


## Puts finished cylinders on the pad - as many as fit. Returns how many were accepted; the caller keeps
## the rest. `unit_value` is what each cylinder earns.
func try_add(count: float, unit_value: float) -> float:
	var n := minf(count, room())
	if n <= 1e-9:
		return 0.0
	load += n
	money += n * unit_value
	return n


## Puts cylinders on the pad regardless of room (older code and tests).
func add(count: float, amount: float) -> void:
	load += count
	money += amount


## 0..1 how far the van is through leaving / being away (for the animation).
func progress() -> float:
	match state:
		State.LEAVING:
			return clampf(1.0 - timer / LEAVE_TIME, 0.0, 1.0)
		State.AWAY:
			return clampf(1.0 - timer / maxf(away_time, 0.01), 0.0, 1.0)
		State.ARRIVING:
			return clampf(1.0 - timer / ARRIVE_TIME, 0.0, 1.0)
	return 0.0


## Seconds from the van arriving to arriving again when it always finds a full load waiting.
func cycle_time() -> float:
	return away_time + LEAVE_TIME + ARRIVE_TIME + LOAD_TIME


## The most cylinders per second this dispatch can move for a line making `line_rate` cylinders a second, worked out
## for one whole round trip (no frame-by-frame simulation, so it is cheap enough for offline time and shop text):
## the pad fills while the van is away (never beyond `storage`); the van takes that, then keeps loading what the line
## makes for up to MAX_WAIT seconds, but never carries more than `capacity`. Returns at most `line_rate`.
func throughput(line_rate: float) -> float:
	if line_rate <= 0.0:
		return 0.0
	var away_span := away_time + LEAVE_TIME + ARRIVE_TIME
	var waiting := minf(storage, line_rate * away_span)         # on the pad when the van is back
	var carry := minf(waiting, capacity)
	var extra := 0.0                                           # time spent loading what is still being made
	if carry < capacity:
		extra = minf(MAX_WAIT, (capacity - carry) / line_rate)
		carry = minf(capacity, carry + line_rate * extra)
	var span := away_span + maxf(extra, carry / (capacity / LOAD_TIME))
	return minf(line_rate, carry / span)


## The ceiling of `throughput` for any speed of line: a full van per cycle.
func max_throughput() -> float:
	return capacity / cycle_time()


func tick(dt: float) -> void:
	full_time = full_time + dt if is_full() else 0.0
	match state:
		State.LOADING:
			_load(dt)
		State.LEAVING:
			timer -= dt
			if timer <= 0.0:
				var paid := carry_money * (1.0 + bonus)
				var cyl := carry_load
				carry_load = 0.0
				carry_money = 0.0
				trips += 1
				state = State.AWAY
				timer = away_time
				departed.emit(cyl, paid)
		State.AWAY:
			timer -= dt
			if timer <= 0.0:
				state = State.ARRIVING
				timer = ARRIVE_TIME
		State.ARRIVING:
			timer -= dt
			if timer <= 0.0:
				state = State.LOADING
				timer = 0.0
				waited = 0.0
				idle = 0.0
				returned.emit()


## Loads from the pad, at a pace that fills the whole van in LOAD_TIME.
func _load(dt: float) -> void:
	var room := capacity - carry_load
	if room > 1e-6 and load > 1e-9:
		var n := minf(minf(load, room), capacity / LOAD_TIME * dt)
		var m := money * (n / load)
		load -= n
		money = maxf(money - m, 0.0)
		if load <= 1e-9:
			load = 0.0
		carry_load += n
		carry_money += m
		idle = 0.0
	elif load <= 1e-9:
		idle += dt
	if carry_load <= 1e-9:
		return                  # the van never leaves empty: it waits for the first cylinders
	waited += dt
	if carry_load >= capacity - 1e-6 or idle >= GATHER or waited >= MAX_WAIT:
		state = State.LEAVING
		timer = LEAVE_TIME
		waited = 0.0
		idle = 0.0


## Everything that has not been paid yet (on the pad and on the van): saving or leaving must never lose it.
func unpaid() -> float:
	return (money + carry_money) * (1.0 + bonus)


## Cylinders that are on the pad or aboard the van.
func held() -> float:
	return load + carry_load


## Unattended time: the van has long since delivered everything that was waiting. Empties the pad and the van
## and returns {"count", "money"} (the bonus included) for the caller to credit.
func settle() -> Dictionary:
	var out := {"count": load + carry_load, "money": unpaid()}
	load = 0.0
	money = 0.0
	carry_load = 0.0
	carry_money = 0.0
	state = State.LOADING
	timer = 0.0
	waited = 0.0
	idle = 0.0
	full_time = 0.0
	return out


func to_dict() -> Dictionary:
	return {"state": int(state), "load": load, "money": money, "carry_load": carry_load, "carry_money": carry_money, "timer": timer,
		"waited": waited, "idle": idle, "trips": trips}


## Restores a snapshot. Saves from before the pad had a limit hold more than it can now: they keep it all (the
## pad simply refuses more until the van has taken some).
func from_dict(d: Dictionary) -> void:
	state = clampi(int(d.get("state", 0)), 0, 3) as State
	load = maxf(float(d.get("load", 0.0)), 0.0)
	money = maxf(float(d.get("money", 0.0)), 0.0)
	carry_load = maxf(float(d.get("carry_load", 0.0)), 0.0)
	carry_money = maxf(float(d.get("carry_money", 0.0)), 0.0)
	timer = maxf(float(d.get("timer", 0.0)), 0.0)
	waited = maxf(float(d.get("waited", 0.0)), 0.0)
	idle = maxf(float(d.get("idle", 0.0)), 0.0)
	trips = maxi(int(d.get("trips", 0)), 0)
	full_time = 0.0
	# A load that was on its way out in the old format sits in carry already; nothing else to convert.
