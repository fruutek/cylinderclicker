class_name VanYard
extends Node2D
## The dispatch end of the classic factory, as seen on the floor. A *view* of the factory's DispatchBay: it never
## changes the simulation.
##
## Cylinders that reach the end of the conveyor do not disappear: each one drops off the belt, lands on the
## DISPATCH YARD just below the belt end and the van's door, and the pile of boxes there grows. When the van
## loads, boxes hop from the pile onto it. The pile is exactly the dispatch pad: its height is the pad's fill
## (`bay.load / bay.storage`), and a Dispatch Storage upgrade adds pallets to the yard. While a dropped
## cylinder is still in the air it is not on the pile yet, so the pile and the simulation never disagree for
## longer than the drop takes.
##
## The van drives out through the door (that is when you are paid), stays away for its turnaround and reverses
## back in. Bigger-van upgrades change the vehicle: van -> trade lorry -> commercial lorry -> major lorry.

const TEX_PALLET := preload("res://assets/sprites/pallet.png")
const TEX_VEHICLES: Array[Texture2D] = [
	preload("res://assets/sprites/van.png"), preload("res://assets/sprites/lorry_trade.png"),
	preload("res://assets/sprites/lorry_commercial.png"), preload("res://assets/sprites/lorry_major.png"),
]
const PALLET_SIZE := Vector2(24, 22)
const BOXES := 6                      # boxes on a full pallet
const BASE_SLOTS := 8
const MAX_SLOTS := 12
## Where each pallet stands (top-left, local coordinates): the pile starts under the belt end and spreads out.
const SLOT_ORIGINS: Array[Vector2] = [
	Vector2(54, 268), Vector2(78, 268), Vector2(30, 268), Vector2(6, 268),
	Vector2(54, 292), Vector2(78, 292), Vector2(30, 292), Vector2(6, 292),
	Vector2(102, 292), Vector2(126, 292), Vector2(150, 292), Vector2(174, 292),
]
const BOX_SIZE := Vector2(7, 8)
const BOX_REGION := Rect2(2, 10, 7, 8)   # one box, cut from the pallet sheet
const PARK_DX := 94.0                 # how far left the vehicle parks (out of sight through the door)
const DROP_TIME := 0.34               # seconds a carton takes to drop from the belt end onto the pile
const HOP_TIME := 0.38                # ...and a box to hop from the pile onto the van
const MAX_FLIERS := 18
const FLUSH_EVERY := 0.09

var sim: FactorySim
var items_tex: Texture2D
var carton_region := Rect2(108, 0, 18, 22)   # the packed carton, as it rides the last belt (the items sheet's final frame)
var belt_end := Vector2(66, 256)      # where cartons leave the conveyor
var van_door := Vector2(62, 240)      # where boxes go aboard

var _in_flight := 0.0                 # boxes that have left the belt but not landed (not on the pile yet)
var _airborne := 0.0                  # ...of which already visible as flying cartons
var _pending := 0.0                   # boxes waiting for the next flier (arrivals within a few frames merge)
var _flush_cd := 0.0
var _fliers: Array[Dictionary] = []
var _last_shown := 0
var _last_carry := 0.0
var _blink := false
var _last_drawn := -1


func setup(p_sim: FactorySim, p_items: Texture2D, final_frame: int) -> void:
	sim = p_sim
	items_tex = p_items
	carton_region = Rect2(float(final_frame) * 18.0, 0.0, 18.0, 22.0)
	belt_end = sim.layout.dispatch_pos + Vector2(0, 4)
	sim.shipped.connect(_on_shipped)
	_last_shown = _shown()


# ------------------------------------------------------------------ the van
## 0 = vehicle at the bay, -PARK_DX = gone through the door.
func van_dx() -> float:
	if sim == null:
		return 0.0
	var p := sim.bay.progress()
	match sim.bay.state:
		DispatchBay.State.LEAVING:
			return -PARK_DX * _smooth((p - 0.7) / 0.3)
		DispatchBay.State.AWAY:
			return -PARK_DX
		DispatchBay.State.ARRIVING:
			return -PARK_DX * (1.0 - _smooth(p))
	return 0.0


static func _smooth(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Which vehicle the factory has earned: a van, then ever bigger lorries as the vans are upgraded.
func van_texture() -> Texture2D:
	var lvl := sim.level("van_load") if sim != null else 0
	return TEX_VEHICLES[0 if lvl < 2 else (1 if lvl < 5 else (2 if lvl < 8 else 3))]


# ----------------------------------------------------------------- the yard
## How many pallets the yard has: more with every Dispatch Storage upgrade (up to MAX_SLOTS).
func slots() -> int:
	return clampi(BASE_SLOTS + (sim.level("dispatch_store") if sim != null else 0), BASE_SLOTS, MAX_SLOTS)


## Where pallet `i` stands (local coordinates), for effects.
func slot_pos(i: int) -> Vector2:
	return SLOT_ORIGINS[clampi(i, 0, SLOT_ORIGINS.size() - 1)]


func total_boxes() -> int:
	return slots() * BOXES


## The simulation's pad fill, in boxes (fractional).
func target_boxes() -> float:
	if sim.bay.load <= 1e-6:
		return 0.0
	return clampf(float(total_boxes()) * sim.bay.fill(), 0.05, float(total_boxes()))


## Boxes on the pile right now: the pad's fill, less what is still in the air.
func _shown() -> int:
	return clampi(int(ceilf(target_boxes() - _in_flight - 0.001)), 0, total_boxes())


## Centre of box number `idx` on the pile (0 = first box of the first pallet).
func box_center(idx: int) -> Vector2:
	idx = clampi(idx, 0, total_boxes() - 1)
	var slot := idx / BOXES
	var k := idx % BOXES
	var front := k < 3
	var col := k % 3
	return slot_pos(slot) + Vector2(2.0 + 7.0 * float(col) + 3.5, (10.0 if front else 2.0) + 4.0)


## The simulation handed `count` finished cylinders to the pad: they leave the belt now, and will be on the pile
## when the carton has dropped.
func _on_shipped(count: float, _amount: float) -> void:
	if sim == null or count <= 0.0 or sim.bay.storage <= 0.0:
		return
	var boxes := count / sim.bay.storage * float(total_boxes())
	_in_flight += boxes
	_pending += boxes


func _process(delta: float) -> void:
	if sim == null:
		return
	_flush_cd -= delta
	# a carton drops from the belt end for what has arrived (arrivals within a few frames share one carton)
	if _pending > 0.0 and _flush_cd <= 0.0 and _fliers.size() < MAX_FLIERS:
		_flush_cd = FLUSH_EVERY
		var land := int(floorf(maxf(target_boxes() - _in_flight, 0.0) + _airborne))
		_fliers.append({"kind": "drop", "from": belt_end, "to": box_center(land), "age": 0.0, "life": DROP_TIME, "boxes": _pending})
		_airborne += _pending
		_pending = 0.0
	elif _pending > 0.0 and _fliers.size() >= MAX_FLIERS:
		_land(_pending)            # far too many in the air: let them land at once
		_pending = 0.0
	# the pile shrank (the van is loading): boxes hop from its top onto the van
	var shown := _shown()
	var loading := sim.bay.state == DispatchBay.State.LOADING and sim.bay.carry_load > _last_carry + 1e-6
	_last_carry = sim.bay.carry_load
	if shown < _last_shown and loading:       # (a bigger yard just re-draws the same pile: no boxes fly then)
		var n := 0
		for idx in range(_last_shown - 1, shown - 1, -1):
			if _fliers.size() < MAX_FLIERS and n < 6:
				_fliers.append({"kind": "load", "from": box_center(idx), "to": van_door + Vector2(float(n) * 1.5, 0.0), "age": 0.0, "life": HOP_TIME, "boxes": 0.0})
				n += 1
	_last_shown = shown
	# move the fliers
	var landed := false
	for f in _fliers:
		f["age"] += delta
		if f["age"] >= f["life"] and f["kind"] == "drop":
			_land(float(f["boxes"]))
			landed = true
	_fliers = _fliers.filter(func(f: Dictionary) -> bool: return f["age"] < f["life"])
	var blink := sim.bay.is_full() and int(Time.get_ticks_msec() / 400) % 2 == 0
	if blink != _blink or landed or not _fliers.is_empty() or shown != _last_drawn:
		_blink = blink
		_last_drawn = shown
		queue_redraw()


func _land(boxes: float) -> void:
	_in_flight = maxf(_in_flight - boxes, 0.0)
	_airborne = maxf(_airborne - boxes, 0.0)


func _draw() -> void:
	if sim == null:
		return
	var shown := _shown()
	for i in slots():
		var origin := slot_pos(i)
		# floor markings: the yard's capacity is readable even when it is empty
		draw_rect(Rect2(origin + Vector2(1, 3), Vector2(PALLET_SIZE.x - 3, 18)), Color(0.98, 0.82, 0.25, 0.4), false, 1.0)
		var on_pallet := clampi(shown - i * BOXES, 0, BOXES)
		draw_texture_rect_region(TEX_PALLET, Rect2(origin, PALLET_SIZE), Rect2(float(on_pallet) * PALLET_SIZE.x, 0.0, PALLET_SIZE.x, PALLET_SIZE.y))
	for f in _fliers:
		var t := clampf(f["age"] / f["life"], 0.0, 1.0)
		var from: Vector2 = f["from"]
		var to: Vector2 = f["to"]
		if f["kind"] == "drop":
			# off the end of the belt and down onto the pile, shrinking into a box as it lands
			var p := from.lerp(to, t * t) + Vector2(0.0, -sin(t * PI) * 5.0)
			var s := lerpf(1.0, 0.42, t)
			var size := Vector2(18, 22) * s
			if items_tex != null:
				draw_texture_rect_region(items_tex, Rect2((p + Vector2(-size.x / 2.0, 3.0 - size.y)).round(), size), carton_region)
		else:
			var p := from.lerp(to, _smooth(t)) + Vector2(0.0, -sin(t * PI) * 14.0)
			draw_texture_rect_region(TEX_PALLET, Rect2((p - BOX_SIZE / 2.0).round(), BOX_SIZE), BOX_REGION)
	if sim.bay.is_full() and _blink:
		UiTheme.draw_text(self, Vector2(8, 316), "PAD FULL", Color("ff7a66"), false)
