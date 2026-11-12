class_name FactoryView
extends Node2D
## Draws one factory floor. This is purely a *view* of a FactorySim: it reads
## the simulation every frame and never changes it. Tokens are drawn from a
## single canvas item (no node per cylinder), and because the simulation
## batches cylinders at high output, the draw count stays small forever.

const TEX_BELT_H := preload("res://assets/sprites/belt_h.png")
const TEX_BELT_V := preload("res://assets/sprites/belt_v.png")
const TEX_CORNER := preload("res://assets/sprites/belt_corner.png")
const TEX_CABINET := preload("res://assets/sprites/cabinet.png")
const TEX_BEACON := preload("res://assets/sprites/beacon.png")
const TEX_WARN := preload("res://assets/sprites/warn.png")

const SIZE := Vector2(444, 330)
const MACHINE_ORIGIN := Vector2(-24, -46)
const ITEM_SIZE := Vector2(18, 22)
const MAX_PARTICLES := 240

var session: FactorySim          # the factory being shown
var company: GameState           # for the company/factory name on the sign
var layout: LineLayout

var _tex_items: Texture2D
var _van_pos := Vector2(-2, 218)
var _batch_label_pos := Vector2(26, 60)
var _sign_fill := Color8(138, 90, 48)
var _sign_text := Color8(250, 188, 120)
var _sign_shadow := Color8(98, 62, 34)
var _stage_max := 6
var _first_update := true

var _belt_layer: Node2D
var _token_layer: Node2D
var _overlay_layer: Node2D
var _fx_layer: Node2D
var _van: Sprite2D
var _fronts: Array[Sprite2D] = []
var _workers: Array[Sprite2D] = []
var _cabinets: Array[Sprite2D] = []
var _beacons: Array[Sprite2D] = []
var _worker_timers: Array[float] = []

var _token_pos := {}            # token id -> visual position
var _belt_scroll := 0.0
var _time := 0.0
var _van_bob := 0.0
var _particles: Array[Dictionary] = []
var _float_texts: Array[Dictionary] = []
var _pending_cash := 0.0
var _pending_timer := 0.0
var _path: Array[Vector2] = []   # full conveyor centre line, station to station


func _sprite(key: String, fallback: String) -> Texture2D:
	return load("res://assets/sprites/%s.png" % session.data.view.get(key, fallback))


static func _rgb(a: Array) -> Color:
	return Color8(int(a[0]), int(a[1]), int(a[2]))


func setup(p_session: FactorySim, p_company: GameState) -> void:
	session = p_session
	company = p_company
	layout = session.layout
	# Each factory can name its own sprites and sign colours in its stations
	# file ("view"); the defaults are the original copper works.
	var view: Dictionary = session.data.view
	_tex_items = _sprite("items", "items")
	_stage_max = session.data.stations.size()
	if view.has("vehicle_pos"):
		_van_pos = Vector2(float(view["vehicle_pos"][0]), float(view["vehicle_pos"][1]))
	if view.has("batch_label_pos"):
		_batch_label_pos = Vector2(float(view["batch_label_pos"][0]), float(view["batch_label_pos"][1]))
	var sign_style: Dictionary = view.get("sign", {})
	if sign_style.has("fill"):
		_sign_fill = _rgb(sign_style["fill"])
		_sign_text = _rgb(sign_style["text"])
		_sign_shadow = _rgb(sign_style["shadow"])

	var bg := Sprite2D.new()
	bg.texture = _sprite("background", "factory_bg")
	bg.centered = false
	add_child(bg)

	_belt_layer = _make_layer(_draw_belts)

	for i in session.data.stations.size():
		var back := Sprite2D.new()
		back.texture = load("res://assets/sprites/machine_%s_back.png" % session.data.stations[i]["sprite"])
		back.centered = false
		back.position = layout.station_positions[i] + MACHINE_ORIGIN
		add_child(back)

	_van = Sprite2D.new()
	_van.texture = _sprite("vehicle", "van")
	_van.centered = false
	_van.position = _van_pos
	add_child(_van)

	_token_layer = _make_layer(_draw_tokens)

	for i in session.data.stations.size():
		var pos := layout.station_positions[i]
		var front := Sprite2D.new()
		front.texture = load("res://assets/sprites/machine_%s_front.png" % session.data.stations[i]["sprite"])
		front.centered = false
		front.hframes = 4
		front.position = pos + MACHINE_ORIGIN
		add_child(front)
		_fronts.append(front)
		_workers.append(_make_sprite(_sprite("worker", "worker"), 3, pos + Vector2(-27, 12)))
		_cabinets.append(_make_sprite(TEX_CABINET, 2, pos + Vector2(-27, 12)))
		_beacons.append(_make_sprite(TEX_BEACON, 2, pos + Vector2(12, -53)))
		_worker_timers.append(0.0)

	_overlay_layer = _make_layer(_draw_overlay)
	_fx_layer = _make_layer(_draw_fx)

	# Full belt centre line for drawing (belts run underneath the machines).
	_path.append(layout.station_positions[0] + Vector2(-22, 0))
	for i in session.data.stations.size():
		_path.append(layout.station_positions[i])
		for p: Array in session.data.stations[i].get("path_after", []):
			_path.append(Vector2(float(p[0]), float(p[1])))
	_path.append(layout.dispatch_pos)

	session.clicked.connect(_on_clicked)
	session.shipped.connect(_on_shipped)
	session.station_finished.connect(_on_station_finished)
	session.upgrade_purchased.connect(_on_upgrade_purchased)
	_refresh_automation()


func _make_layer(draw_fn: Callable) -> Node2D:
	var n := Node2D.new()
	n.draw.connect(draw_fn)
	add_child(n)
	return n


func _make_sprite(tex: Texture2D, frames: int, pos: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.hframes = frames
	s.position = pos
	add_child(s)
	return s


func _refresh_automation() -> void:
	for i in _workers.size():
		var automated := session.station_level(i) > 0
		_workers[i].visible = not automated
		_cabinets[i].visible = automated
		_beacons[i].visible = automated


func _process(delta: float) -> void:
	if session == null:
		return
	_time += delta
	_belt_scroll += session.line.belt_speed * delta
	_update_tokens(delta)

	var line := session.line
	for i in line.stations.size():
		var st := line.stations[i]
		_fronts[i].frame = int(st.cycles * 8.0) % 4
		if _worker_timers[i] > 0.0:
			_worker_timers[i] -= delta
			_workers[i].frame = 1 if _worker_timers[i] > 0.08 else 2
		else:
			_workers[i].frame = 0
		var working := st.state() == ProductionLine.State.WORKING
		_cabinets[i].frame = int(_time * 2.0 + i) % 2
		_beacons[i].frame = (int(_time * 3.0 + i) % 2) if working else 0

	_van_bob = maxf(_van_bob - delta, 0.0)
	_van.position = _van_pos + Vector2(0, 1 if _van_bob > 0.08 else 0)

	_pending_timer -= delta
	if _pending_cash > 0.0 and _pending_timer <= 0.0:
		_pending_timer = 0.3
		_float_texts.append({
			"pos": layout.dispatch_pos + Vector2(randf_range(-22, -6), -34),
			"text": "+" + NumFmt.money(_pending_cash), "age": 0.0, "life": 1.1, "color": UiTheme.GOLD,
		})
		_pending_cash = 0.0

	for p in _particles:
		p["age"] += delta
		p["vel"] += Vector2(0, p["gravity"]) * delta
		p["pos"] += p["vel"] * delta
	_particles = _particles.filter(func(p: Dictionary) -> bool: return p["age"] < p["life"])
	for f in _float_texts:
		f["age"] += delta
		f["pos"] += Vector2(0, -16.0) * delta
	_float_texts = _float_texts.filter(func(f: Dictionary) -> bool: return f["age"] < f["life"])

	_belt_layer.queue_redraw()
	_token_layer.queue_redraw()
	_overlay_layer.queue_redraw()
	_fx_layer.queue_redraw()


# ----------------------------------------------------------------- tokens
func _token_target(t: ProductionLine.Token) -> Vector2:
	if t.station >= 0:
		return layout.station_positions[t.station]
	return layout.point_on_belt(t.belt, t.pos)


func _update_tokens(delta: float) -> void:
	var seen := {}
	var max_step := maxf(session.line.belt_speed * 2.5, 140.0) * delta
	for t in session.line.all_tokens():
		var target := _token_target(t)
		var pos: Vector2
		if _token_pos.has(t.id):
			pos = _token_pos[t.id]
			pos = target if pos.distance_to(target) > 90.0 else pos.move_toward(target, max_step)
		else:
			# Fresh raw sheets slide in from the stock pallet (but when the view
			# has only just opened, everything simply appears where it is).
			pos = layout.stock_pos if t.stage == 0 and not _first_update else target
		_token_pos[t.id] = pos
		seen[t.id] = true
	for id: int in _token_pos.keys():
		if not seen.has(id):
			_token_pos.erase(id)
	_first_update = false


func _draw_tokens() -> void:
	var tokens: Array[ProductionLine.Token] = []
	for t in session.line.all_tokens():
		if _token_pos.has(t.id):   # tokens created since the last update appear next frame
			tokens.append(t)
	tokens.sort_custom(func(a: ProductionLine.Token, b: ProductionLine.Token) -> bool:
		return _token_pos[a.id].y < _token_pos[b.id].y)
	for t in tokens:
		var pos: Vector2 = _token_pos[t.id].round()
		var stage := t.stage
		if t.station >= 0 and session.line.stations[t.station].fraction() >= 0.55:
			stage += 1   # show the result once the station is mostly done
		stage = clampi(stage, 0, _stage_max)
		_token_layer.draw_texture_rect_region(
			_tex_items, Rect2(pos + Vector2(-9, 6 - ITEM_SIZE.y), ITEM_SIZE), Rect2(stage * ITEM_SIZE.x, 0, ITEM_SIZE.x, ITEM_SIZE.y))


## Redraws the wall sign straight away (used when renaming while paused).
func queue_sign_redraw() -> void:
	_belt_layer.queue_redraw()


## Paints the factory's name onto the timber sign on the back wall, in the
## same style as the sign's original lettering.
func _draw_sign() -> void:
	var f := UiTheme.font()
	var board_w := f.get_string_size(GameState.LEGACY_FACTORY_NAME.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_SIZE).x - 1.0
	var left := floorf((SIZE.x - board_w) / 2.0) - 6.0
	_belt_layer.draw_rect(Rect2(left + 3, 8, board_w + 6, 11), _sign_fill)
	var text := company.factory_name.to_upper()
	var x := floorf((SIZE.x - (f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_SIZE).x - 1.0)) / 2.0)
	_belt_layer.draw_string(f, Vector2(x, 18), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_SIZE, _sign_shadow)
	_belt_layer.draw_string(f, Vector2(x, 17), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_SIZE, _sign_text)


# ------------------------------------------------------------------ belts
func _draw_belts() -> void:
	_draw_sign()
	var frame := int(_belt_scroll / 2.0) % 4
	for j in range(1, _path.size()):
		var a := _path[j - 1]
		var b := _path[j]
		if is_equal_approx(a.y, b.y):
			var x0 := minf(a.x, b.x)
			var x1 := maxf(a.x, b.x)
			var fr := frame if b.x > a.x else 3 - frame
			var x := x0
			while x < x1:
				var w := minf(16.0, x1 - x)
				_belt_layer.draw_texture_rect_region(TEX_BELT_H, Rect2(x, a.y - 10, w, 22), Rect2(fr * 16, 0, w, 22))
				x += 16.0
		else:
			var y0 := minf(a.y, b.y) + 10.0
			var y1 := maxf(a.y, b.y) - 10.0
			var fr := frame if b.y > a.y else 3 - frame
			var y := y0
			while y < y1:
				var h := minf(16.0, y1 - y)
				_belt_layer.draw_texture_rect_region(TEX_BELT_V, Rect2(a.x - 11, y, 22, h), Rect2(fr * 22, 0, 22, h))
				y += 16.0
	# corner plates sit on top of the belt ends
	for i in session.data.stations.size():
		for p: Array in session.data.stations[i].get("path_after", []):
			_belt_layer.draw_texture(TEX_CORNER, Vector2(float(p[0]) - 11, float(p[1]) - 10))


# ---------------------------------------------------------------- overlay
func _draw_overlay() -> void:
	var line := session.line
	if line.batch > 1.05:
		# At high output each item on the belt stands for a whole batch.
		UiTheme.draw_text(_overlay_layer, _batch_label_pos, "Each item = %s cylinders" % NumFmt.number(line.batch, 1), UiTheme.CREAM)
	for i in line.stations.size():
		var st := line.stations[i]
		var pos := layout.station_positions[i]
		var bar := Rect2(pos + Vector2(-8, 20), Vector2(30, 5))
		_overlay_layer.draw_rect(bar, UiTheme.OUTLINE)
		_overlay_layer.draw_rect(bar.grow(-1), Color("5a4a52"))
		var state := st.state()
		var frac := st.fraction()
		if frac > 0.0:
			var col := UiTheme.COPPER
			if state == ProductionLine.State.BLOCKED:
				col = Color("e0553a")
			elif st.rate > 0.0:
				col = Color("6cc070")
			_overlay_layer.draw_rect(Rect2(bar.position + Vector2(1, 1), Vector2(roundf(28.0 * frac), 3)), col)
		UiTheme.draw_text(_overlay_layer, pos + Vector2(7, 27), String(session.data.stations[i]["name"]), UiTheme.CREAM, true)
		if state == ProductionLine.State.BLOCKED:
			var bob := 1.0 if int(_time * 3.0) % 2 == 0 else 0.0
			_overlay_layer.draw_texture(TEX_WARN, pos + Vector2(-5, -58 - bob))


# --------------------------------------------------------------------- fx
func _draw_fx() -> void:
	for p in _particles:
		var k: float = 1.0 - p["age"] / p["life"]
		var c: Color = p["color"]
		c.a = clampf(k * 2.0, 0.0, 1.0)
		var s: float = p["size"]
		_fx_layer.draw_rect(Rect2((p["pos"] as Vector2).round(), Vector2(s, s)), c)
	for f in _float_texts:
		var c: Color = f["color"]
		var fade := clampf((f["life"] - f["age"]) * 3.0, 0.0, 1.0)
		c.a = fade
		var oc := UiTheme.OUTLINE
		oc.a = fade
		UiTheme.draw_text(_fx_layer, (f["pos"] as Vector2).round(), f["text"], c, true, oc)


func burst(at: Vector2, count: int, color: Color, speed: float = 60.0, gravity: float = 160.0, life: float = 0.4) -> void:
	for n in count:
		if _particles.size() >= MAX_PARTICLES:
			return
		var ang := randf() * TAU
		_particles.append({
			"pos": at, "vel": Vector2(cos(ang), sin(ang) * 0.8 - 0.5) * speed * randf_range(0.4, 1.0),
			"gravity": gravity, "age": 0.0, "life": life * randf_range(0.6, 1.0), "color": color, "size": 1.0 if randf() < 0.6 else 2.0,
		})


## Confetti for a grand opening.
func celebrate() -> void:
	var colours: Array[Color] = [UiTheme.GOLD, Color("8fc8e8"), Color("9ff0a0"), Color("ff8a70"), Color.WHITE]
	for n in 5:
		burst(Vector2(60 + n * 80, 90), 34, colours[n], 150.0, 170.0, 1.6)


## Feedback for a click on the factory floor at `at` (local coordinates).
func click_feedback(at: Vector2) -> void:
	burst(at, 5, Color("fff4be"), 50.0, 120.0, 0.3)


func _on_clicked(stations: Array) -> void:
	for i: int in stations:
		_worker_timers[i] = 0.16
		var pos := layout.station_positions[i]
		var manual := session.station_level(i) == 0
		burst(pos + Vector2(0, -6), 3 if manual else 2, Color("ffe9a0") if manual else Color("b8f0ff"), 55.0)


func _on_shipped(_count: float, amount: float) -> void:
	_pending_cash += amount
	_van_bob = 0.16
	burst(layout.dispatch_pos + Vector2(-4, -8), 4, UiTheme.GOLD, 40.0, 90.0, 0.5)


func _on_station_finished(index: int) -> void:
	burst(layout.station_positions[index] + Vector2(14, -4), 2, Color(1, 1, 1, 0.8), 25.0, -20.0, 0.35)


func _on_upgrade_purchased(id: String, lvl: int) -> void:
	var def: Dictionary = session.data.upgrade_by_id[id]
	if def["kind"] != "machine":
		return
	_refresh_automation()
	var pos := layout.station_positions[int(def["station_index"])]
	burst(pos + Vector2(0, -20), 26 if lvl == 1 else 10, UiTheme.GOLD, 90.0, 60.0, 0.8)
	_float_texts.append({
		"pos": pos + Vector2(0, -62), "text": "AUTOMATED!" if lvl == 1 else "Lv %d" % lvl,
		"age": 0.0, "life": 1.4, "color": Color("9ff0a0"),
	})
