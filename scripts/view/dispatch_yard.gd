class_name DispatchYard
extends Node2D
## The dispatch pad and the delivery sequence of one factory floor. A *view*
## of the contract book: it never changes the simulation. Everything it draws
## is derived from the contract on show (ContractBook.featured_for):
##
##   * while an order is being built, the pad below the bay fills with
##     pallets of boxed cylinders in step with its progress;
##   * when it is complete the pallets glow, ready for collection;
##   * while it is dispatching, the standing vehicle pulls out, a delivery
##     lorry reverses into the bay, a forklift loads the pallets one by one
##     and the lorry drives away. The simulation's dispatch timer runs the
##     whole thing, so the animation is the same however the view was reached
##     and the payment lands exactly when the lorry has gone.
##
## A large order is still at most four pallets and one forklift, so the
## cost does not grow with the number of cylinders.

const TEX_PALLET := preload("res://assets/sprites/pallet.png")
const TEX_FORKLIFT := preload("res://assets/sprites/forklift.png")
const TEX_LORRY := {
	"trade": preload("res://assets/sprites/lorry_trade.png"),
	"commercial": preload("res://assets/sprites/lorry_commercial.png"),
	"major": preload("res://assets/sprites/lorry_major.png"),
}

const PAD := Rect2(6, 288, 106, 41)       # painted outbound area below the dispatch bay
const PALLET_SIZE := Vector2(24, 22)
const PALLET_FRAME_BOXES := 6
const SLOT_X0 := 12.0
const SLOT_DX := 22.0
const PALLET_Y := 304.0
const REAR := Vector2(72, 262)            # where the forklift stands at the lorry's rear (just below the belt that feeds the bay)
const LIFT := 30.0                        # how far the mast raises a pallet to reach the trailer floor
const SLIDE := 28.0                       # how far it then slides into the trailer
const AISLE_Y := 307.0                    # forklift height while crossing the pad
const PARK_DX := 94.0                     # how far left a vehicle parks (out of sight through the door)
const PICK_DX := 16.0                     # forklift x offset from a pallet's x when picking it up
const CARRY := Vector2(-16.0, -3.0)       # carried pallet position relative to the forklift

# Seconds into the dispatch (see ContractBook.dispatch): the standing vehicle leaves, the
# lorry reverses in, one trip per pallet, the lorry leaves.
const T_VAN_OUT := 0.8
const T_LORRY_IN_FROM := 0.5
const T_LORRY_IN_TO := 1.9
const T_TRIP := 1.2
const T_LORRY_OUT := 1.3
const VAN_RETURN := 1.0

var sim: FactorySim
var book: ContractBook
var view: FactoryView

var _home := Vector2.ZERO
var _pad: Node2D
var _lorry: Sprite2D
var _time := 0.0
var _bump := 0.0
var _flash := 0.0
var _pending_units := 0.0
var _units_timer := 0.0
var _van_return := 0.0
var _last_t := -1.0
var _last_id := ""
var _van_dx := 0.0
var _featured: Contract = null


func setup(p_sim: FactorySim, p_view: FactoryView, home: Vector2) -> void:
	sim = p_sim
	view = p_view
	book = sim.contracts
	_home = home
	_pad = Node2D.new()
	_pad.draw.connect(_draw_pad)
	add_child(_pad)
	_lorry = Sprite2D.new()
	_lorry.centered = false
	_lorry.visible = false
	add_child(_lorry)
	if book != null:
		book.delivered.connect(_on_delivered)
		book.completed.connect(_on_completed)


## Horizontal shift of the factory's standing van/lorry (it drives out for a dispatch).
func van_dx() -> float:
	return _van_dx


func _process(delta: float) -> void:
	if book == null:
		return
	_time += delta
	_bump = maxf(_bump - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	_van_return = maxf(_van_return - delta, 0.0)
	_featured = book.featured_for(sim.data.id)

	_units_timer -= delta
	if _pending_units >= 1.0 and _units_timer <= 0.0:
		_units_timer = 0.6
		view.add_float_text(Vector2(PAD.position.x + 54, PAD.position.y - 4), "+" + NumFmt.number(_pending_units), Color("9fd8ff"))
		_pending_units = fmod(_pending_units, 1.0)

	var c := _featured
	var dispatching := c != null and c.status == Contract.Status.DISPATCHING
	if dispatching:
		var t := c.dispatch_total - c.dispatch_left
		_play_cues(c, t)
		_last_t = t
		_last_id = c.id
		_pose_vehicles(c, t)
	else:
		_lorry.visible = false
		_last_t = -1.0
		if _van_return > 0.0:
			var k := 1.0 - _van_return / VAN_RETURN
			_van_dx = lerpf(-PARK_DX, 0.0, _ease_out(k))
		else:
			_van_dx = 0.0
	_pad.queue_redraw()


# ------------------------------------------------------------- sequence
static func _ease_out(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return 1.0 - (1.0 - k) * (1.0 - k)


static func _ease_in(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k


## Where each vehicle is `t` seconds into the dispatch.
func _pose_vehicles(c: Contract, t: float) -> void:
	# The standing van drives out through the door to make room...
	if t < T_VAN_OUT:
		_van_dx = lerpf(0.0, -PARK_DX, _ease_in(t / T_VAN_OUT))
	else:
		_van_dx = -PARK_DX
	# ...the delivery lorry reverses in (cab to the door, rear to the factory), loads, and drives off.
	var load_end := T_LORRY_IN_TO + T_TRIP * float(c.pallets)
	var dx: float
	if t < T_LORRY_IN_FROM:
		dx = -PARK_DX
	elif t < T_LORRY_IN_TO:
		dx = lerpf(-PARK_DX, 0.0, _ease_out((t - T_LORRY_IN_FROM) / (T_LORRY_IN_TO - T_LORRY_IN_FROM)))
	elif t < load_end:
		dx = 0.0
	else:
		dx = lerpf(0.0, -PARK_DX, _ease_in((t - load_end) / T_LORRY_OUT))
	_lorry.texture = TEX_LORRY.get(c.tier, TEX_LORRY["trade"])
	var rumble := 1.0 if (t > T_LORRY_IN_FROM and t < T_LORRY_IN_TO + 0.2 and int(_time * 14.0) % 2 == 0) else 0.0
	_lorry.position = _home + Vector2(dx, rumble)
	_lorry.visible = dx > -PARK_DX + 1.0
	if _van_dx < -PARK_DX + 0.5 and t >= T_VAN_OUT:
		_van_return = VAN_RETURN       # when the lorry has gone the van drives back in


## Sound and dust at the moments that matter, whatever the view was doing before.
func _play_cues(c: Contract, t: float) -> void:
	if _last_id != c.id:
		_last_t = -1.0
	var load_end := T_LORRY_IN_TO + T_TRIP * float(c.pallets)
	if _crossed(T_LORRY_IN_FROM, t):
		Sfx.play("beep", 0.0, -6.0)
		Sfx.play("engine", 0.0, -8.0)
	if _crossed(T_LORRY_IN_TO, t):
		view.burst(_home + Vector2(30, 40), 6, Color(0.9, 0.9, 0.9, 0.7), 22.0, -10.0, 0.5)
	for i in c.pallets:
		if _crossed(T_LORRY_IN_TO + T_TRIP * (float(i) + 0.9), t):      # pallet slides into the trailer
			Sfx.play("thunk", 0.05, -4.0)
			view.burst(Vector2(REAR.x - 4, REAR.y - 6), 4, Color("e8c88c"), 30.0, 80.0, 0.35)
	if _crossed(load_end, t):
		Sfx.play("engine", 0.0, -8.0)


func _crossed(mark: float, t: float) -> bool:
	return _last_t >= 0.0 and _last_t < mark and t >= mark


# --------------------------------------------------------------- events
func _on_delivered(c: Contract, units: float) -> void:
	if c.factory != sim.data.id:
		return
	_pending_units += units
	_bump = 0.14
	_flash = 0.25


func _on_completed(c: Contract, base: float, bonus: float, rep_gain: int) -> void:
	if c.factory != sim.data.id:
		return
	var at := _home + Vector2(112, -4)
	view.add_float_text(at, "+" + NumFmt.money(base + bonus), UiTheme.GOLD, 2.2)
	if bonus > 0.0:
		view.add_float_text(at + Vector2(0, 11), "BONUS " + NumFmt.money(bonus), Color("9ff0a0"), 2.2)
	if rep_gain > 0:
		view.add_float_text(at + Vector2(0, 22), "+%d REPUTATION" % rep_gain, Color("9fd8ff"), 2.2)
	view.burst(at, 30, UiTheme.GOLD, 110.0, 160.0, 1.2)
	view.burst(at, 14, Color("9fd8ff"), 80.0, 120.0, 1.0)
	_van_return = VAN_RETURN


# --------------------------------------------------------------- drawing
func _draw_pad() -> void:
	if book == null or not book.unlocked:
		return
	var c := _featured
	var ready := c != null and c.status == Contract.Status.READY
	# painted outbound area
	var floor_tint := Color(0.2, 0.15, 0.2, 0.12)
	_pad.draw_rect(PAD, floor_tint)
	var line_col := Color("f2b73c") if (ready and int(_time * 3.0) % 2 == 0) or _flash > 0.0 else Color("c48f2c")
	var x := PAD.position.x
	while x < PAD.end.x:
		var w := minf(5.0, PAD.end.x - x)
		_pad.draw_rect(Rect2(x, PAD.position.y, w, 1), line_col)
		_pad.draw_rect(Rect2(x, PAD.end.y - 1, w, 1), line_col)
		x += 8.0
	var y := PAD.position.y
	while y < PAD.end.y:
		var h := minf(5.0, PAD.end.y - y)
		_pad.draw_rect(Rect2(PAD.position.x, y, 1, h), line_col)
		_pad.draw_rect(Rect2(PAD.end.x - 1, y, 1, h), line_col)
		y += 8.0
	if c == null:
		UiTheme.draw_text(_pad, Vector2(PAD.position.x + 5, PAD.position.y + 3), "OUTBOUND", Color(1, 1, 1, 0.35), false, Color(0, 0, 0, 0))
		return

	var pallets := c.pallets
	var dispatching := c.status == Contract.Status.DISPATCHING
	var t := (c.dispatch_total - c.dispatch_left) if dispatching else 0.0
	var load_start := T_LORRY_IN_TO
	var trips_done := 0
	var trip := -1
	var u := 0.0
	if dispatching and t >= load_start:
		var tl := (t - load_start) / T_TRIP
		trip = mini(int(floorf(tl)), pallets)
		u = tl - floorf(tl) if trip < pallets else 1.0
		trips_done = mini(trip, pallets)
	# pallets still on the pad: the forklift takes the right-most one first
	var on_pad := pallets - trips_done
	if trip >= 0 and trip < pallets and u >= 0.38:
		on_pad -= 1           # this trip's pallet is already on the forks
	var boxes_total := pallets * PALLET_FRAME_BOXES
	var filled := boxes_total
	if c.status == Contract.Status.ACTIVE:
		filled = clampi(int(ceilf(c.fraction() * float(boxes_total))), 1 if c.delivered > 0.0 else 0, boxes_total)
	for s in on_pad:
		var in_slot := clampi(filled - s * PALLET_FRAME_BOXES, 0, PALLET_FRAME_BOXES)
		var lift := -1.0 if (_bump > 0.0 and in_slot > 0 and in_slot < PALLET_FRAME_BOXES and filled - s * PALLET_FRAME_BOXES == in_slot) else 0.0
		_draw_pallet(Vector2(SLOT_X0 + SLOT_DX * float(s), PALLET_Y + lift), in_slot)

	# label above the pallets
	var label := _short_name(c.customer, 17)
	if ready:
		UiTheme.draw_text(_pad, Vector2(PAD.position.x + 4, PAD.position.y + 3), "READY", UiTheme.GOLD if int(_time * 3.0) % 2 == 0 else Color.WHITE)
		UiTheme.draw_text(_pad, Vector2(PAD.position.x + 40, PAD.position.y + 3), label, UiTheme.CREAM)
	elif dispatching:
		UiTheme.draw_text(_pad, Vector2(PAD.position.x + 4, PAD.position.y + 3), "LOADING  " + label, UiTheme.CREAM)
	else:
		UiTheme.draw_text(_pad, Vector2(PAD.position.x + 4, PAD.position.y + 3), "%s %d%%" % [label, int(c.fraction() * 100.0)], UiTheme.CREAM)

	if dispatching and trip >= 0 and trip < pallets:
		_draw_forklift_trip(pallets, trip, u)


## A customer name cut at a word boundary to fit the pad label.
static func _short_name(name: String, max_chars: int) -> String:
	if name.length() <= max_chars:
		return name
	var cut := name.rfind(" ", max_chars)
	if cut < 6:
		cut = max_chars
	return name.substr(0, cut)


## One loading trip: drive empty to the pallet, lift it, drive to the lorry's
## rear, slide it in. `u` runs 0..1 through the trip.
func _draw_forklift_trip(pallets: int, trip: int, u: float) -> void:
	var slot := pallets - 1 - trip
	var slot_pos := Vector2(SLOT_X0 + SLOT_DX * float(slot) + PICK_DX, AISLE_Y)
	var aisle := Vector2(REAR.x, AISLE_Y)
	var pos: Vector2
	var carrying := false
	var insert := 0.0
	if u < 0.30:
		pos = _along([REAR, aisle, slot_pos], u / 0.30)
	elif u < 0.38:
		pos = slot_pos
	elif u < 0.70:
		pos = _along([slot_pos, aisle, REAR], (u - 0.38) / 0.32)
		carrying = true
	else:
		insert = (u - 0.70) / 0.30
		pos = REAR
		carrying = u < 0.97
	var frame := int(_time * 8.0) % 2 if (u < 0.30 or (u >= 0.38 and u < 0.70)) else 0
	# The forklift sprite faces right; a negative width mirrors it so its forks point at the pallets / lorry.
	_pad.draw_texture_rect_region(TEX_FORKLIFT, Rect2(pos.round(), Vector2(-28, 20)), Rect2(frame * 28, 0, 28, 20))
	if carrying:
		# At the lorry the mast lifts the pallet up to trailer height, then it slides in out of sight.
		var lift := minf(insert / 0.5, 1.0) * LIFT
		var slide := maxf(insert - 0.5, 0.0) / 0.5 * SLIDE
		_draw_pallet((pos + CARRY + Vector2(-slide, -lift)).round(), PALLET_FRAME_BOXES)


## Follows a polyline of waypoints at constant speed; k is 0..1 along its length.
func _along(points: Array, k: float) -> Vector2:
	var total := 0.0
	for i in range(1, points.size()):
		total += (points[i] as Vector2).distance_to(points[i - 1])
	var d := clampf(k, 0.0, 1.0) * total
	for i in range(1, points.size()):
		var seg := (points[i] as Vector2).distance_to(points[i - 1])
		if d <= seg or i == points.size() - 1:
			return (points[i - 1] as Vector2).move_toward(points[i], d)
		d -= seg
	return points[points.size() - 1]


func _draw_pallet(at: Vector2, boxes: int) -> void:
	_pad.draw_texture_rect_region(TEX_PALLET, Rect2(at.round(), PALLET_SIZE), Rect2(boxes * PALLET_SIZE.x, 0, PALLET_SIZE.x, PALLET_SIZE.y))
