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
	c.state.cash = 320.0
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
		[1.0, func() -> void: _close_dialogs(); _shot("n01_factory_idle")],
		[1.5, func() -> void:
			c.sales.calls.clear()
			_call(c, "CU-DIR", 24, 1)],
		[2.2, func() -> void: _shot("n02_factory_call")],
		[2.5, func() -> void: main.call("open_screen", "orders")],
		[3.2, func() -> void: _shot("n03_orders_call")],
		[3.4, func() -> void: main.call("open_screen", "stock")],
		[4.1, func() -> void: _shot("n04_stock_auto")],
		[4.3, func() -> void:
			var f: FactorySim = c.factory("copper")
			for i in f.skus.size():
				f.state.targets[f.sku_id(i)] = f.effective_target(i)
			f.state.auto_targets = false],
		[5.0, func() -> void: _shot("n05_stock_manual")],
		[5.2, func() -> void:
			c.factory("copper").state.auto_targets = true
			main.call("open_screen", "upgrades")],
		[5.9, func() -> void: _shot("n06_upgrades")],
		[6.1, func() -> void:
			c.sales.calls.clear()
			var k := Contract.new()
			k.id = "o1"; k.serial = 1000001; k.tier = "call"; k.customer = "Dalton Heating & Plumbing"; k.customer_id = c.sales.customers[0]["id"]
			k.factory = "copper"; k.sku = "CU-IND"; k.product_name = "Copper Indirect"; k.quantity = 30; k.asked = 30; k.margin = 1.05; k.mode = "partial"
			k.shipped = 10.0; k.held = 8.0; k.pallets = 2; k.promised = 400.0; k.deadline = 400.0
			c.contracts.add_order(k)
			main.call("open_screen", "orders")],
		[6.9, func() -> void: _shot("n07_orders_progress")],
		[7.1, func() -> void: _close_dialogs()],
		[7.8, func() -> void: _shot("n08_factory_upgrade")],
		[8.2, func() -> void: get_tree().quit()],
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
