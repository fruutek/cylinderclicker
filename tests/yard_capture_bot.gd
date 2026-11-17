extends Node
## Dev tool: screenshots of the dispatch pad and delivery sequence in both
## factories, by jumping the simulation's dispatch clock to chosen moments.
## Run:  godot --path . -- --fresh --autostart --bot=res://tests/yard_capture_bot.gd --capture=/some/folder
## (needs a display, e.g. xvfb-run)

var out_dir := ""
var main: Node
var _plan: Array = []
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			out_dir = arg.trim_prefix("--capture=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var c: GameSession = Game.session
	Game.save_enabled = false
	c.state.tutorial_step = 7
	c.state.cash = 5000.0
	c.state.lifetime_earned = 2000.0
	var s := c.factory("copper")
	for m: Dictionary in s.data.machines:
		s.state.upgrade_levels[m["id"]] = 6
	s.state.earned = 2000.0
	s.refresh()
	c.contracts.reset(2024)
	c.contracts.unlocked = true
	c.contracts.offer_timer = 1.0e9
	var o := _offer(c, "y1", "copper", 600, 9000.0, 3, "major")
	c.contracts.accept("y1")
	c.contracts.set_allocation("y1", 50)
	_plan = [
		[0.6, func() -> void: _close_dialogs(); _shot("y01_pad_empty_ish")],
		[0.7, func() -> void: _progress(c, 0.12)],
		[1.2, func() -> void: _shot("y02_pad_12pct")],
		[1.3, func() -> void: _progress(c, 0.55)],
		[1.8, func() -> void: _shot("y03_pad_55pct")],
		[1.9, func() -> void: _progress(c, 1.0)],
		[2.4, func() -> void: _shot("y04_ready")],
		[2.5, func() -> void: c.contracts.dispatch("y1")],
	]
	var times := [0.3, 0.9, 1.4, 2.0, 2.6, 3.2, 3.8, 4.6, 5.4, 6.2, 6.8]
	var base := 3.0
	for i in times.size():
		var tt: float = times[i]
		_plan.append([base + i * 0.9, func() -> void:
			var k := c.contracts.find("y1")
			if k != null:
				k.dispatch_left = k.dispatch_total - tt
			_shot_later("y%02d_dispatch_%03d" % [5 + i, int(tt * 10)])])
	var after := base + times.size() * 0.9 + 0.5
	_plan.append([after, func() -> void:
		var k := c.contracts.find("y1")
		if k != null:
			k.dispatch_left = 0.05])
	_plan.append([after + 0.9, func() -> void: _shot("y17_after_payout")])
	# stainless
	_plan.append([after + 1.6, func() -> void:
		var st := c.factory("stainless")
		st.state.unlocked = true
		for m: Dictionary in st.data.machines:
			st.state.upgrade_levels[m["id"]] = 3
		st.refresh()
		main.call("switch_factory", "stainless")
		_offer(c, "y2", "stainless", 40, 90000.0, 2, "commercial")
		c.contracts.accept("y2")
		c.contracts.set_allocation("y2", 50)
		_progress(c, 0.5, "y2")])
	_plan.append([after + 2.3, func() -> void: _shot("y18_stainless_pad_half")])
	_plan.append([after + 2.4, func() -> void:
		_progress(c, 1.0, "y2")
		c.contracts.dispatch("y2")])
	for i in [0.3, 1.4, 2.7, 3.6, 5.0]:
		var tt: float = i
		_plan.append([after + 2.6 + i * 0.5 + 0.8, func() -> void:
			var k := c.contracts.find("y2")
			if k != null:
				k.dispatch_left = k.dispatch_total - tt
			_shot_later("y19_stainless_dispatch_%03d" % int(tt * 10))])
	_plan.append([after + 9.0, func() -> void: get_tree().quit()])


func _offer(c: GameSession, id: String, factory: String, qty: int, value: float, pallets: int, tier: String) -> Contract:
	var o := Contract.new()
	o.id = id
	o.serial = 800 + c.contracts.offers.size()
	o.tier = tier
	o.customer = "Hartley Builders' Merchants" if factory == "copper" else "Pennine Plumbing Wholesale"
	o.archetype = "merchant"
	o.factory = factory
	o.product_name = "Copper Cylinder" if factory == "copper" else "Stainless Steel Cylinder"
	o.quantity = qty
	o.value = value
	o.bonus = value * 0.1
	o.bonus_by = 4000.0
	o.deadline = 7000.0
	o.est_full = 600.0
	o.rep = 40
	o.penalty = 20
	o.pallets = pallets
	o.expires_in = 900.0
	c.contracts.offers.append(o)
	return o


func _progress(c: GameSession, fraction: float, id: String = "y1") -> void:
	var k := c.contracts.find(id)
	if k == null:
		return
	k.delivered = int(float(k.quantity) * fraction)
	if fraction >= 1.0:
		k.delivered = k.quantity
		c.contracts._complete(k)


func _process(delta: float) -> void:
	_t += delta
	while not _plan.is_empty() and _t >= _plan[0][0]:
		var step: Array = _plan.pop_front()
		(step[1] as Callable).call()


func _close_dialogs() -> void:
	for c in (main.get("_dialog_layer") as Node).get_children():
		c.queue_free()


func _shot_later(shot_name: String) -> void:
	await get_tree().create_timer(0.25).timeout
	_shot(shot_name)


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("captured ", shot_name)
