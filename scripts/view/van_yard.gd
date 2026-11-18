class_name VanYard
extends Node2D
## The delivery van of the classic game, as seen on the factory floor. A *view* of the factory's DispatchBay: it
## never changes the simulation. Finished cylinders pile up as boxes on the pallets of the outbound pad; when the
## van leaves the pallets go aboard and it drives out through the door (that is when you are paid), stays away
## for its turnaround and reverses back in. Bigger-van upgrades change the vehicle: van -> trade lorry ->
## commercial lorry -> major lorry. Dispatch Storage upgrades add pallets to the pad, so a bigger pad is visible, and
## a pad that has no room left says FULL.

const TEX_PALLET := preload("res://assets/sprites/pallet.png")
const TEX_VEHICLES: Array[Texture2D] = [
	preload("res://assets/sprites/van.png"), preload("res://assets/sprites/lorry_trade.png"),
	preload("res://assets/sprites/lorry_commercial.png"), preload("res://assets/sprites/lorry_major.png"),
]
const PALLET_SIZE := Vector2(24, 22)
const SLOT_X0 := 12.0
const SLOT_DX := 22.0
const PALLET_Y := 304.0
const PARK_DX := 94.0                 # how far left the vehicle parks (out of sight through the door)
const MIN_SLOTS := 4
const MAX_SLOTS := 14
const BOXES := 6

var sim: FactorySim
var _key := ""
var _timer := 0.0


func setup(p_sim: FactorySim) -> void:
	sim = p_sim


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


## How many pallets the pad has: more with every Dispatch Storage upgrade.
func slots() -> int:
	return clampi(MIN_SLOTS + (sim.level("dispatch_store") if sim != null else 0), MIN_SLOTS, MAX_SLOTS)


## Where pallet `i` stands (local coordinates), for effects.
func slot_pos(i: int) -> Vector2:
	return Vector2(SLOT_X0 + float(i) * SLOT_DX, PALLET_Y)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or sim == null:
		return
	_timer = 0.1
	var k := "%d|%d|%d|%d" % [_boxes(), slots(), int(sim.bay.state), (int(Time.get_ticks_msec() / 400) % 2) if sim.bay.is_full() else 2]
	if k != _key:
		_key = k
		queue_redraw()


## How many boxes are on the pad (0 .. slots * BOXES): the pad's fill, shown as boxes on its pallets.
func _boxes() -> int:
	var b := sim.bay
	var total := slots() * BOXES
	if b.load <= 1e-6:
		return 0
	return clampi(int(ceilf(float(total) * b.fill())), 1, total)


func _draw() -> void:
	if sim == null:
		return
	var left := _boxes()
	var n := slots()
	for i in n:
		# floor markings: the pad's capacity is readable even when it is empty
		draw_rect(Rect2(slot_pos(i) + Vector2(1, 3), Vector2(PALLET_SIZE.x - 3, 18)), Color(0.98, 0.82, 0.25, 0.4), false, 1.0)
		var in_slot := clampi(left - i * BOXES, 0, BOXES)
		draw_texture_rect_region(TEX_PALLET, Rect2(slot_pos(i), PALLET_SIZE), Rect2(float(in_slot) * PALLET_SIZE.x, 0.0, PALLET_SIZE.x, PALLET_SIZE.y))
	if sim.bay.is_full():
		# no room left: the line is about to back up
		if int(Time.get_ticks_msec() / 400) % 2 == 0:
			UiTheme.draw_text(self, slot_pos(0) + Vector2(0, -11), "PAD FULL", Color("ff7a66"), false)
