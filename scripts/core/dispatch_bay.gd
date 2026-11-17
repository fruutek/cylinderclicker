class_name DispatchBay
extends RefCounted
## The delivery van of one factory. Finished cylinders roll into the dispatch bay and wait on the pallets; the
## van loads them, drives away (that is when the money arrives) and comes back after a short turnaround. It
## runs by itself: there is nothing to schedule, and cylinders made while the van is away simply wait for the
## next trip, so the van never slows the factory down. Pure simulation: the view only animates its state.
##
##   LOADING  -> the van is at the bay, pallets fill; it leaves when the load is big enough, or when it has waited a few seconds
##   LEAVING  -> the pallets go aboard (a few seconds), then it drives off and the trip is PAID
##   AWAY     -> out delivering (turnaround, shortened by upgrades)
##   ARRIVING -> back at the bay and reversing in

signal departed(cylinders: float, money: float)       # the van has left with this load: pay `money`
signal returned

enum State { LOADING, LEAVING, AWAY, ARRIVING }

const MAX_WAIT := 5.0          # seconds a van waits for a full load before leaving with what it has
const LEAVE_TIME := 3.0
const ARRIVE_TIME := 1.6

var state: State = State.LOADING
var load := 0.0                # cylinders waiting in the bay
var money := 0.0               # what they are worth
var carry_load := 0.0          # the load that is on the van (while LEAVING)
var carry_money := 0.0
var timer := 0.0               # seconds left in LEAVING / AWAY / ARRIVING
var waited := 0.0
var trips := 0
var capacity := 10.0           # a load this big sends the van straight away
var away_time := 8.0           # turnaround
var bonus := 0.0               # delivery bonus on every trip (upgrades)


func set_stats(p_capacity: float, p_away: float, p_bonus: float) -> void:
	capacity = maxf(p_capacity, 1.0)
	away_time = maxf(p_away, 1.5)
	bonus = maxf(p_bonus, 0.0)


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


func tick(dt: float) -> void:
	match state:
		State.LOADING:
			if load >= capacity or (load > 0.0 and waited >= MAX_WAIT):
				_start_leaving()
			elif load > 0.0:
				waited += dt
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
				waited = 0.0
				returned.emit()


func _start_leaving() -> void:
	carry_load = load
	carry_money = money
	load = 0.0
	money = 0.0
	waited = 0.0
	state = State.LEAVING
	timer = LEAVE_TIME


## Everything that has not been paid yet (in the bay and on the van): saving or leaving must never lose it.
func unpaid() -> float:
	return (money + carry_money) * (1.0 + bonus)


func to_dict() -> Dictionary:
	return {"state": int(state), "load": load, "money": money, "carry_load": carry_load, "carry_money": carry_money, "timer": timer, "waited": waited, "trips": trips}


func from_dict(d: Dictionary) -> void:
	state = clampi(int(d.get("state", 0)), 0, 3) as State
	load = maxf(float(d.get("load", 0.0)), 0.0)
	money = maxf(float(d.get("money", 0.0)), 0.0)
	carry_load = maxf(float(d.get("carry_load", 0.0)), 0.0)
	carry_money = maxf(float(d.get("carry_money", 0.0)), 0.0)
	timer = maxf(float(d.get("timer", 0.0)), 0.0)
	waited = maxf(float(d.get("waited", 0.0)), 0.0)
	trips = maxi(int(d.get("trips", 0)), 0)
