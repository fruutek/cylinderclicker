class_name ProductionLine
extends RefCounted
## Deterministic simulation of one production line. No nodes, no rendering.
##
## Model: stations are joined by conveyor belts. A station holds one token,
## adds work to it (from its machine and from player clicks) and, when done,
## pushes it onto its outgoing belt - but only if there is room. Belts are
## the buffers: tokens queue nose-to-tail, so a slow station visibly backs
## the line up behind it (a bottleneck) and starves the stations after it.
##
## Scaling: a token is a *batch* of cylinders. While the line is slow every
## token is exactly one cylinder. Once machines could push more than
## MAX_TOKENS_PER_SECOND, new tokens carry proportionally more cylinders, so
## the number of simulated/drawn objects stays small however large the
## factory's output becomes.

signal shipped(count: float)
signal station_finished(index: int)

const TOKEN_SPACING := 15.0
const MAX_TOKENS_PER_SECOND := 2.0

enum State { WAITING, WORKING, BLOCKED }


class Token:
	var id: int = 0
	var stage: int = 0          # number of stations completed
	var count: float = 1.0      # cylinders represented by this token
	var station: int = -1       # station index while being processed, else -1
	var belt: int = -1          # belt index while travelling, else -1
	var pos: float = 0.0        # distance along the belt


class Station:
	var work: float = 1.0       # work needed per cylinder
	var rate: float = 0.0       # automatic work per second (0 = manual)
	var token: Token = null
	var progress: float = 0.0
	var need: float = 1.0
	var cycles: float = 0.0     # total cylinders-worth of work done (drives animation)
	var carry: float = 0.0
	var carry_tick: int = -10

	func state() -> int:
		if token == null:
			return State.WAITING
		return State.BLOCKED if progress >= need else State.WORKING

	func fraction() -> float:
		if token == null:
			return 0.0
		return clampf(progress / need, 0.0, 1.0)


class Belt:
	var length: float = 100.0
	var tokens: Array[Token] = []   # front (nearest the exit) first


var stations: Array[Station] = []
var belts: Array[Belt] = []
var belt_speed := 48.0
var click_power := 1.0
var click_boost := 0.0
var batch := 1.0

var _next_id := 1
var _tick := 0


func setup(station_count: int, belt_lengths: Array[float]) -> void:
	stations.clear()
	belts.clear()
	for i in station_count:
		stations.append(Station.new())
		var b := Belt.new()
		b.length = belt_lengths[i]
		belts.append(b)


func set_params(works: Array[float], rates: Array[float], p_belt_speed: float, p_click_power: float, p_click_boost: float) -> void:
	for i in stations.size():
		stations[i].work = maxf(works[i], 0.001)
		stations[i].rate = maxf(rates[i], 0.0)
		if stations[i].token != null:
			stations[i].need = stations[i].work * stations[i].token.count
	belt_speed = p_belt_speed
	click_power = p_click_power
	click_boost = p_click_boost
	batch = maxf(1.0, steady_rate() / MAX_TOKENS_PER_SECOND)


## Sustainable cylinders per second with no clicking: the slowest machine
## sets the pace. Zero until every station is automated.
func steady_rate() -> float:
	var r := INF
	for s in stations:
		if s.rate <= 0.0:
			return 0.0
		r = minf(r, s.rate / s.work)
	return 0.0 if r == INF else r


## Index of the slowest automated station (-1 if nothing is automated).
func bottleneck_index() -> int:
	var best := -1
	var best_rate := INF
	for i in stations.size():
		var s := stations[i]
		if s.rate > 0.0 and s.rate / s.work < best_rate:
			best_rate = s.rate / s.work
			best = i
	return best


func clear() -> void:
	for s in stations:
		s.token = null
		s.progress = 0.0
	for b in belts:
		b.tokens.clear()


func all_tokens() -> Array[Token]:
	var out: Array[Token] = []
	for s in stations:
		if s.token != null:
			out.append(s.token)
	for b in belts:
		out.append_array(b.tokens)
	return out


func tick(dt: float) -> void:
	_tick += 1
	var last := stations.size() - 1
	_advance_belt(last, dt)
	var out_belt := belts[last]
	while not out_belt.tokens.is_empty() and out_belt.tokens[0].pos >= out_belt.length - 0.01:
		var t: Token = out_belt.tokens.pop_front()
		shipped.emit(t.count)
	# Work back-to-front so space freed downstream is usable in the same tick.
	for i in range(last, -1, -1):
		_tick_station(i, dt)
		if i > 0:
			_advance_belt(i - 1, dt)


## One player click: every station with a cylinder in it gets a burst of work.
## Returns the indices of the stations that were helped.
func click() -> Array[int]:
	var hit: Array[int] = []
	for i in stations.size():
		var s := stations[i]
		if s.token == null:
			_try_load(i)
		if s.token != null and s.progress < s.need:
			_add_work(s, click_power + click_boost * s.rate)
			hit.append(i)
	return hit


func _add_work(s: Station, amount: float) -> void:
	s.progress += amount
	s.cycles += amount / s.need


func _tick_station(i: int, dt: float) -> void:
	var s := stations[i]
	if s.token == null:
		_try_load(i)
	if s.token == null:
		return
	if s.rate > 0.0 and s.progress < s.need:
		_add_work(s, s.rate * dt)
	if s.progress >= s.need:
		_try_unload(i)


func _try_load(i: int) -> void:
	var s := stations[i]
	var t: Token = null
	if i == 0:
		t = Token.new()       # raw stock is always on hand at the first station
		t.id = _next_id
		_next_id += 1
		t.count = batch
	else:
		var b := belts[i - 1]
		if b.tokens.is_empty() or b.tokens[0].pos < b.length - 0.01:
			return
		t = b.tokens.pop_front()
	t.station = i
	t.belt = -1
	s.token = t
	s.need = s.work * t.count
	# Keep work that overshot the previous cylinder (only if we never idled).
	s.progress = minf(s.carry, s.need * 0.9) if s.carry_tick == _tick - 1 else 0.0
	s.carry = 0.0


func _try_unload(i: int) -> void:
	var s := stations[i]
	var b := belts[i]
	if not b.tokens.is_empty() and b.tokens[b.tokens.size() - 1].pos < TOKEN_SPACING:
		return   # outgoing belt is full: blocked
	var t := s.token
	t.stage = i + 1
	t.station = -1
	t.belt = i
	t.pos = 0.0
	b.tokens.append(t)
	s.carry = s.progress - s.need
	s.carry_tick = _tick
	s.token = null
	s.progress = 0.0
	station_finished.emit(i)


func _advance_belt(index: int, dt: float) -> void:
	var b := belts[index]
	var limit := b.length
	var step := belt_speed * dt
	for t in b.tokens:
		t.pos = maxf(t.pos, minf(t.pos + step, limit))
		limit = t.pos - TOKEN_SPACING
