extends "res://tests/touch_flow_bot.gd"
## The traffic-jam story, watched on screen at the phone's screen shape: the line running, the van going away, finished
## cartons piling up at the end of the conveyor, the pile filling, the conveyor behind it filling, the jam creeping back
## through the machines (each one stopping), and then the van returning and the whole backlog moving forward again.
## Every step is checked against what is DRAWN (the view's own state and the pixels of the screenshot), not only the
## simulation, and each is saved as a screenshot.
## Run by tests/run_jam_story.sh.

var _farthest_flier := 0
var _exits := 0
var _exits_unexplained := 0
var _known: Dictionary = {}
var _watched: FactoryView = null
var _blocked_since: Array[float] = []      # per machine: when it last became blocked (-1 = not blocked)
var _clock := 0.0


func _run() -> void:
	await _story()
	print("JAM STORY: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	Game.save_enabled = false
	get_tree().quit(1 if _fails > 0 else 0)


func _process(delta: float) -> void:
	_clock += delta
	_watch_exits()
	var main := _scene()
	if main != null and main.has_method("switch_factory") and main.get("_factory") != null:
		var line: ProductionLine = (main.get("_factory") as FactoryView).session.line
		while _blocked_since.size() < line.stations.size():
			_blocked_since.append(-1.0)
		var blocked := line.blocked_stations()
		for i in line.stations.size():
			if blocked.has(i):
				if _blocked_since[i] < 0.0:
					_blocked_since[i] = _clock
			else:
				_blocked_since[i] = -1.0


## Every cylinder that leaves the end of the belt must be seen to drop onto the pile: a carton has to be in the air (or
## about to be) in the same frame the token disappears.
func _watch_exits() -> void:
	var main := _scene()
	if main == null or not main.has_method("switch_factory"):
		return
	var view: FactoryView = main.get("_factory")
	if view == null or view._vans == null:
		return
	if view != _watched:
		_watched = view          # another factory is on screen: its cartons are not the ones we were following
		_known = {}
	var line := view.session.line
	var last := line.stations.size() - 1
	var now: Dictionary = {}
	for t in line.belts[last].tokens:
		now[t.id] = t.count
	for id: int in _known.keys():
		if not now.has(id):
			_exits += 1
			var drop := view._vans._pending > 0.0
			for f in view._vans._fliers:
				drop = drop or (f["kind"] == "drop" and f["age"] < 0.15)
			if not drop:
				_exits_unexplained += 1
	_known = now
	_farthest_flier = maxi(_farthest_flier, view._vans._fliers.size())


## Dark outline pixels in a screen rectangle: a measure of how many boxes are standing in it.
func _dark_pixels(img: Image, rect: Rect2i) -> int:
	var n := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := img.get_pixel(x, y)
			if c.r < 0.3 and c.g < 0.25 and c.b < 0.32:
				n += 1
	return n


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _yard_rect(view: FactoryView) -> Rect2i:
	var o := view.get_global_transform_with_canvas().origin
	return Rect2i(int(o.x) + 4, int(o.y) + 266, 186, 56)


func _story() -> void:
	var c: GameSession = Game.session
	Game.save_enabled = false
	check(UiTheme.touch and c.classic, "phone layout, classic game")
	for d in (_scene().get("_dialog_layer") as Node).get_children():
		d.queue_free()
	await _frames(3)
	var main := _scene()
	c.state.tutorial_step = 7
	c.bonus_orders.enabled = false
	var copper := c.factory("copper")
	# machines of equal speed (two units of work per second per unit of effort), so that only the jam blocks anything
	for i in copper.data.stations.size():
		copper.state.upgrade_levels[GameData.machine_id(copper.data.stations[i]["id"])] = int(copper.data.stations[i]["work"]) * 2
	copper.refresh()
	var view: FactoryView = main.get("_factory")
	check(view != null and view._vans != null, "the factory view has its dispatch yard")
	var yard := _yard_rect(view)
	await _wait(2.0)
	# ---- 1. the line running, van at the bay (the first cylinders take a few seconds to reach the end)
	var empty := _dark_pixels(await _grab(), yard)
	await _wait(18.0)
	await _shot("j01_running")
	check(copper.state.cylinders_sold > 0.0 or copper.bay.held() > 0.0, "cylinders are being made and delivered")
	# ---- 2. the van goes away for a long time
	copper.bay.state = DispatchBay.State.AWAY
	copper.bay.timer = 90.0
	var pile0 := copper.bay.load
	await _wait(6.0)
	await _shot("j02_van_away_pile_starting")
	var img := await _grab()
	var dark_a := _dark_pixels(img, yard)
	check(copper.bay.load > pile0 + 3.0, "while the van is away the pad fills (%d cylinders)" % copper.bay.load)
	check(view._vans._shown() >= 1, "and a pile of boxes is drawn at the end of the conveyor (%d boxes)" % view._vans._shown())
	await _wait(8.0)
	await _shot("j03_pile_growing")
	var dark_b := _dark_pixels(await _grab(), yard)
	check(dark_b > dark_a, "the pile keeps growing on screen (%d -> %d outline pixels)" % [dark_a, dark_b])
	# the drawn pile always matches the simulation
	var target := view._vans.target_boxes()
	check(absf(float(view._vans._shown()) - ceilf(maxf(target - view._vans._in_flight, 0.0))) <= 1.0, "the pile drawn is the pad's real fill (%d boxes of %d)" % [view._vans._shown(), view._vans.total_boxes()])
	# ---- 3. the pad fills up; the belt behind it starts to fill
	for i in 60:
		await _wait(1.0)
		if copper.bay.is_full():
			break
	await _wait(0.5)
	await _shot("j04_pad_full")
	check(copper.bay.is_full(), "the pad is full")
	var dark_full := _dark_pixels(await _grab(), yard)
	check(dark_full > empty + 400, "the yard is full of boxes on screen (%d outline pixels, empty yard %d)" % [dark_full, empty])
	check(view._vans._shown() == view._vans.total_boxes(), "every pallet slot is loaded (%d boxes)" % view._vans._shown())
	await _wait(5.0)
	await _shot("j05_belt_backing_up")
	var last := copper.line.stations.size() - 1
	check(copper.line.belts[last].tokens.size() >= 3, "the last conveyor is filling with waiting cartons (%d)" % copper.line.belts[last].tokens.size())
	# the head carton sits ON the belt: its left edge is inside the drawn belt
	var head: ProductionLine.Token = copper.line.belts[last].tokens[0]
	var head_x: float = view._token_pos[head.id].x
	check(head_x - 9.0 >= copper.layout.dispatch_pos.x - FactoryView.BELT_OVERRUN - 0.5, "the front carton is wholly on the belt (left edge %.0f, belt ends %.0f)" % [head_x - 9.0, copper.layout.dispatch_pos.x - FactoryView.BELT_OVERRUN])
	# ---- 4. the jam creeps backwards: machines stop one after another
	var order: Array[int] = []
	for i in 90:
		await _wait(1.0)
		for s in copper.line.blocked_stations():
			if not order.has(s):
				order.append(s)
		if order.size() == copper.line.stations.size():
			break
	await _shot("j06_jam_spreading")
	await _wait(1.0)
	var since := _blocked_since.duplicate()
	var in_order := true
	for i in range(since.size() - 1):
		in_order = in_order and since[i + 1] >= 0.0 and since[i] >= since[i + 1]
	var times: Array[String] = []
	for i in since.size():
		times.append("%s %.1fs" % [copper.data.stations[i]["name"], since[i]])
	check(in_order and since[0] >= 0.0, "the jam spread from packing backwards through every machine, each stopping in turn: %s" % [times])
	await _shot("j07_everything_stopped")
	# every machine really has stopped: its sprite frame does not change, and it is dimmed
	var frames_before: Array[int] = []
	for f in view._fronts:
		frames_before.append(f.frame)
	var dim := true
	for f in view._fronts:
		dim = dim and f.modulate.r < 0.9
	await _wait(1.0)
	var still := true
	for i in view._fronts.size():
		still = still and view._fronts[i].frame == frames_before[i]
	check(dim and still, "all machines are dimmed and standing still")
	# and the conveyors have stopped moving: the belt surface is frozen
	var phases: Array[float] = view._belt_phase.duplicate()
	await _wait(1.0)
	var frozen := 0
	for i in copper.line.belts.size():
		if not copper.line.belts[i].tokens.is_empty() and view._belt_phase[i] == phases[i]:
			frozen += 1
	check(frozen >= copper.line.belts.size() - 1, "the conveyors under the stuck cartons have stopped (%d of %d)" % [frozen, copper.line.belts.size()])
	# ---- 5. the van returns and the backlog moves forward again
	copper.bay.timer = 0.3
	var made0 := copper.state.cylinders_made
	await _wait(2.0)
	await _shot("j08_van_back_loading")
	var dark_loading := _dark_pixels(await _grab(), yard)
	await _wait(2.5)
	await _shot("j09_backlog_moving")
	var dark_after := _dark_pixels(await _grab(), yard)
	check(dark_after < dark_full, "the pile on screen got smaller as the van loaded it (%d -> %d)" % [dark_full, dark_after])
	await _wait(6.0)
	await _shot("j10_clearing")
	check(copper.bay.trips >= 1 and c.state.cash > 0.0, "the van collected a load and was paid")
	check(copper.line.blocked_stations().size() < copper.line.stations.size(), "machines are running again")
	check(copper.state.cylinders_made > made0, "production has resumed (%d more made)" % (copper.state.cylinders_made - made0))
	var moving := 0
	phases = view._belt_phase.duplicate()
	await _wait(1.0)
	for i in copper.line.belts.size():
		if view._belt_phase[i] != phases[i]:
			moving += 1
	check(moving >= 1, "the conveyors are moving again (%d of %d)" % [moving, copper.line.belts.size()])
	# ---- 6. the player buys the fix: the whole backlog flows forward into the bigger yard
	await _wait(8.0)                                  # back to a full line with the van away again
	copper.bay.state = DispatchBay.State.AWAY
	copper.bay.timer = 90.0
	for i in 60:
		await _wait(1.0)
		if copper.bay.is_full() and copper.line.blocked_stations().size() == copper.line.stations.size():
			break
	var tokens_jammed := copper.line.all_tokens().size()
	await _shot("k00_jammed_again")
	copper.state.upgrade_levels["dispatch_store"] = 4
	copper.refresh()
	var pile_before := view._vans._shown()
	var seen_moving := false
	for i in 8:
		await _wait(0.9)
		await _shot("k%02d_flowing_forward" % (i + 1))
	var slots_now: int = view._vans.slots()
	check(slots_now == 12, "Dispatch Storage added pallets to the yard (%d)" % slots_now)
	check(copper.line.blocked_stations().size() < copper.line.stations.size(), "the backlog is moving into the extra room")
	check(view._vans._shown() > pile_before or view._vans._shown() == view._vans.total_boxes(), "and the pile on the new pallets grows")
	# ---- 7. the stainless plant has the same yard, with its own cartons
	var steel := c.factory("stainless")
	steel.state.unlocked = true
	for i in steel.data.stations.size():
		steel.state.upgrade_levels[GameData.machine_id(steel.data.stations[i]["id"])] = maxi(int(float(steel.data.stations[i]["work"]) / 4.0), 1) * 2
	steel.refresh()
	steel.bay.state = DispatchBay.State.AWAY
	steel.bay.timer = 200.0
	check(main.call("switch_factory", "stainless"), "switched to the stainless plant")
	await _wait(1.0)
	view = main.get("_factory")
	check(view != null and view._vans != null and view.session == steel, "the stainless view has its own dispatch yard")
	for i in 70:
		await _wait(1.0)
		if steel.bay.load >= steel.bay.storage * 0.7:
			break
	await _shot("s01_stainless_pile")
	check(steel.bay.load > 5.0 and view._vans._shown() >= 4, "cartons pile up at the end of the stainless conveyor (%d cylinders, %d boxes)" % [steel.bay.load, view._vans._shown()])
	await _wait(25.0)
	await _shot("s02_stainless_backing_up")
	check(steel.line.blocked_stations().size() >= 1 and steel.line.belts[steel.line.stations.size() - 1].tokens.size() >= 3, "and the stainless line backs up behind it")
	check(absf(steel.line.injected - steel.line.released - steel.line.on_line()) < 1e-6, "stainless cylinders are all accounted for")
	# ---- the whole story: nothing fell off the end
	check(_exits >= 10, "many cartons left the end of the belt during the story (%d)" % _exits)
	check(_exits_unexplained == 0, "every one of them dropped onto the pile - none just vanished (%d unexplained)" % _exits_unexplained)
	check(absf(copper.line.injected - copper.line.released - copper.line.on_line()) < 1e-6, "no cylinder was lost or invented")
