class_name StockYard
extends Node2D
## The finished-goods racking on a factory floor: a grid of pallet bays whose number grows with the
## warehouse (and then stacks higher), filled with pallets of boxed cylinders as stock arrives and
## emptied as it ships. Pallets set aside for a customer carry a gold tag. A *view* of the warehouse:
## it never changes the simulation, and it redraws only when the stock picture changes.

const TEX_PALLET := preload("res://assets/sprites/pallet.png")
const PALLET := Vector2(24, 22)
const BOXES := 6
const COLS := 7
const DX := 27.0
const DY := 15.0                # rows overlap: the back row stands behind the front one
const TIER_LIFT := 6.0
const HEADROOM := 11.0          # space above the first row for the label
const TINTS: Array[Color] = [Color.WHITE, Color("cfe0ff"), Color("ffd9a6"), Color("d4f2c8")]
const FLOOR_LINE := Color(0.95, 0.80, 0.30, 0.4)
const TAG := Color("f2c14e")

var sim: FactorySim
var _key := ""
var _timer := 0.0


func setup(p_sim: FactorySim, rect: Rect2) -> void:
	sim = p_sim
	position = rect.position
	z_index = 0


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or sim == null:
		return
	_timer = 0.15
	var k := _make_key()
	if k != _key:
		_key = k
		queue_redraw()


func _make_key() -> String:
	var w := sim.warehouse
	var k := "%d" % w.capacity
	for s in sim.skus:
		var id := str(s["id"])
		k += "|%d.%d" % [w.total(id), w.reserved_units(id)]
	return k


## [bays, tiers] for the current capacity: bays first, then a second and third tier once they are all in use.
func _grid() -> Array[int]:
	var per := maxi(int(sim.sku_catalog.num("per_pallet", 6.0)), 1)
	var spaces := int(ceilf(float(sim.warehouse.capacity) / float(per)))
	var bays_max := int(sim.sku_catalog.num("bays_max", 14.0))
	var bays := clampi(spaces, 1, bays_max)
	var tiers := clampi(int(ceilf(float(spaces) / float(bays_max))), 1, 4)
	return [bays, tiers]


func _draw() -> void:
	if sim == null:
		return
	var grid := _grid()
	var bays := grid[0]
	var tiers := grid[1]
	var w := sim.warehouse
	# The pallets in stock, in product order: {boxes, tint, held}
	var pallets: Array[Dictionary] = []
	for n in sim.skus.size():
		var id := str(sim.skus[n]["id"])
		var units := w.total(id)
		var held := int(ceilf(float(w.reserved_units(id)) / float(BOXES)))
		var count := int(ceilf(float(units) / float(BOXES)))
		for p in count:
			var boxes := BOXES if (p < count - 1 or units % BOXES == 0) else units % BOXES
			pallets.append({"boxes": boxes, "tint": TINTS[n % TINTS.size()], "held": p < held})
	var rows := int(ceilf(float(bays) / float(COLS)))
	var top := HEADROOM + float(tiers - 1) * TIER_LIFT
	# floor markings for every bay the warehouse has room for
	for b in bays:
		var pos := Vector2(float(b % COLS) * DX, top + float(b / COLS) * DY)
		draw_rect(Rect2(pos, PALLET), FLOOR_LINE, false, 1.0)
	# back row to front row; within a row the ground pallets, then whatever is stacked on them
	for row in rows:
		for t in tiers:
			for col in COLS:
				var b := row * COLS + col
				if b >= bays:
					break
				var slot := t * bays + b
				if slot >= pallets.size():
					break
				var pal: Dictionary = pallets[slot]
				var pos2 := Vector2(float(col) * DX, top + float(row) * DY - float(t) * TIER_LIFT).round()
				draw_texture_rect_region(TEX_PALLET, Rect2(pos2, PALLET), Rect2(float(pal["boxes"]) * PALLET.x, 0.0, PALLET.x, PALLET.y), pal["tint"])
				if pal["held"]:
					draw_rect(Rect2(pos2 + Vector2(1, 1), Vector2(5, 3)), UiTheme.OUTLINE)
					draw_rect(Rect2(pos2 + Vector2(2, 2), Vector2(3, 1)), TAG)
	var text := "STOCK  %d / %d" % [w.total_units(), w.capacity]
	UiTheme.draw_text(self, Vector2(0, 8), text, UiTheme.CREAM, false)
	if w.usage_fraction() >= 0.95:
		UiTheme.draw_text(self, Vector2(112, 8), "FULL", Color("ff8a70"), false)
