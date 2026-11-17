extends Node
## Dev tool: screenshots of the warehouse economy - factory floor with stock, the stock tab, calls,
## orders, customers and the sales rep.
## Run:  xvfb-run -a godot --path . --resolution 960x540 -- --fresh --autostart --bot=res://tests/stock_capture_bot.gd --capture=/some/folder

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
	c.state.lifetime_earned = 20000.0
	var s := c.factory("copper")
	for m: Dictionary in s.data.machines:
		s.state.upgrade_levels[m["id"]] = 7
	s.state.upgrade_levels["warehouse"] = 3
	s.state.upgrade_levels["horizontal_tooling"] = 1
	s.state.earned = 20000.0
	s.refresh()
	c.contracts.reset(2024)
	c.contracts.unlocked = true
	c.contracts.offer_timer = 1.0e9
	c.contracts.refresh_board()
	c.sales.reset(2024)
	c.sales.advance(0.1)
	c.sales.timers["copper"] = 1.0e9
	main = get_tree().current_scene
	var w := s.warehouse
	w.receive("CU-IND", 31.0)
	w.receive("CU-DIR", 9.0)
	c.sales.customers[0]["rel"] = 62.0
	c.sales.customers[0]["completed"] = 9
	c.sales.customers[1]["rel"] = 34.0
	c.sales.customers[2]["rel"] = 12.0
	c.sales.customers[3]["rel"] = 81.0
	c.sales.customers[3]["completed"] = 14
	c.sales.customers[3]["spent"] = 18420.0
	c.sales.observed["copper"] = ["CU-IND", "CU-IND", "CU-DIR", "CU-IND", "CU-DIR", "CU-IND", "CU-IND", "CU-HOR"]
	c.sales.lost["CU-DIR"] = 14.0
	_call(c, "CU-IND", 18, 0)
	_call(c, "CU-DIR", 24, 1)
	_call(c, "CU-HOR", 6, 3)
	_plan = [
		[1.0, func() -> void: _close_dialogs(); _shot("s01_factory")],
		[5.0, func() -> void: _board("calls")],
		[5.8, func() -> void: _shot("s02_calls")],
		[6.0, func() -> void:
			var call: Dictionary = c.sales.calls[0]
			c.sales.customers[0]["rel"] = 80.0
			print(c.sales.answer(str(call["id"]), "full"))
			var call2: Dictionary = c.sales.calls[0]
			print(c.sales.answer(str(call2["id"]), "partial"))],
		[6.5, func() -> void: _board("active")],
		[7.3, func() -> void: _shot("s03_active")],
		[7.5, func() -> void: _board("stock")],
		[8.3, func() -> void: _shot("s04_stock")],
		[8.5, func() -> void: _board("customers")],
		[9.3, func() -> void: _shot("s05_customers")],
		[9.5, func() -> void: _board("rep")],
		[10.3, func() -> void: _shot("s06_rep")],
		[10.5, func() -> void: _close_dialogs(); main.call("switch_factory", "copper")],
		[11.1, func() -> void: _shot("s07_factory_after")],
		[11.3, func() -> void:
			c.factory("copper").warehouse.receive("CU-IND", 60.0)
			c.factory("copper").warehouse.receive("CU-DIR", 20.0)],
		[12.1, func() -> void: _shot("s08_factory_full")],
		[12.6, func() -> void:
			var st := c.factory("stainless")
			st.state.unlocked = true
			for m in st.data.machines:
				st.state.upgrade_levels[m["id"]] = 3
			st.state.upgrade_levels["warehouse"] = 1
			st.refresh()
			st.warehouse.receive("ST-IND", 9.0)
			st.warehouse.receive("ST-DIR", 5.0)
			main.call("switch_factory", "stainless")],
		[14.2, func() -> void: _shot("s09_stainless_stock")],
		[14.6, func() -> void: get_tree().quit()],
	]


func _call(c: GameSession, sku: String, qty: int, who: int) -> void:
	c.sales.serial += 1
	var cust: Dictionary = c.sales.customers[who]
	c.sales.calls.append({"id": "call%d" % c.sales.serial, "serial": c.sales.serial, "customer": cust["id"], "factory": "copper", "sku": sku,
		"qty": qty, "factor": c.sales.price_factor(cust), "expires_in": 120.0 - who * 30.0, "line": 0.1 * float(who + 1)})


func _board(key: String) -> void:
	_close_dialogs()
	var board := ContractBoard.new(Game.session, -1, key)
	main.call("_open", board)


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
