class_name VanYard
extends Node2D
## The delivery van of the classic game, as seen on the factory floor. A *view* of the factory's DispatchBay: it
## never changes the simulation. Finished cylinders pile up as boxes on the pallets of the outbound pad; when the
## van leaves the pallets go aboard and it drives out through the door (that is when you are paid), stays away
## for its turnaround and reverses back in. Bigger-van upgrades change the vehicle: van -> trade lorry ->
## commercial lorry -> major lorry.

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
const SLOTS := 4
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


## Which vehicle the factory has earned.
func van_texture() -> Texture2D:
	var lvl := sim.level("van_load") if sim != null else 0
	return TEX_VEHICLES[0 if lvl < 2 else (1 if lvl < 4 else (2 if lvl < 5 else 3))]


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or sim == null:
		return
	_timer = 0.1
	var k := "%d|%d" % [_boxes(), int(sim.bay.state)]
	if k != _key:
		_key = k
		queue_redraw()


## How many boxes are on the pad (0 .. SLOTS*BOXES).
func _boxes() -> int:
	var b := sim.bay
	var cap := maxf(b.capacity, 1.0)
	var total := float(SLOTS * BOXES)
	match b.state:
		DispatchBay.State.LEAVING:
			var frac := clampf(b.carry_load / cap, 0.0, 1.0)
			return int(ceilf(total * frac * (1.0 - clampf(b.progress() / 0.7, 0.0, 1.0))))
		_:
			return int(ceilf(total * clampf(b.load / cap, 0.0, 1.0)))


func _draw() -> void:
	if sim == null:
		return
	var left := _boxes()
	for i in SLOTS:
		var in_slot := clampi(left - i * BOXES, 0, BOXES)
		if in_slot <= 0 and i > 0:
			continue
		draw_texture_rect_region(TEX_PALLET, Rect2(Vector2(SLOT_X0 + float(i) * SLOT_DX, PALLET_Y), PALLET_SIZE), Rect2(float(in_slot) * PALLET_SIZE.x, 0.0, PALLET_SIZE.x, PALLET_SIZE.y))
