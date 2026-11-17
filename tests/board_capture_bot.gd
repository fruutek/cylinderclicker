extends Node
## Dev tool: screenshots of the HUD, the Contract Board (all tabs), the
## welcome-back summary with contracts and the rank-up box, using offers made
## by the real generator.
## Run:  godot --path . -- --fresh --autostart --bot=res://tests/board_capture_bot.gd --capture=/some/folder
## Add --touch-ui for the phone presentation.

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
	c.state.cash = 12345.0
	var s := c.factory("copper")
	for m: Dictionary in s.data.machines:
		s.state.upgrade_levels[m["id"]] = 12
	s.state.upgrade_levels["finish"] = 3
	s.state.earned = 40000.0
	s.refresh()
	c.state.lifetime_earned = 40000.0
	c.contracts.reset(2468)
	c.contracts.reputation = 95
	c.contracts.history = [
		{"outcome": "delivered", "customer": "Larkfield Plumbing Supplies", "product": "Copper Cylinder", "tier": "trade", "quantity": 60, "delivered": 60, "payout": 740.0, "bonus": 48.0, "rep": 5},
		{"outcome": "delivered", "customer": "Kershaw & Sons Plumbing", "product": "Copper Cylinder", "tier": "trade", "quantity": 40, "delivered": 40, "payout": 410.0, "bonus": 0.0, "rep": 4},
		{"outcome": "deadline", "customer": "Highfield Homes", "product": "Copper Cylinder", "tier": "commercial", "quantity": 900, "delivered": 310, "payout": 0.0, "bonus": 0.0, "rep": -6},
	]
	c.contracts.stats = {"completed": 2, "failed": 1, "units": 100, "paid": 1198.0}
	_plan = [
		[0.5, func() -> void: _close_dialogs(); c.state.lifetime_earned = 40000.0],
		[1.2, func() -> void: c.contracts.refresh_board(); c.contracts.offer_timer = 1.0e9],
		[2.0, func() -> void: _shot("b01_hud_with_orders")],
		[2.2, func() -> void: main.call("open_contract_board", 0)],
		[2.9, func() -> void: _shot("b02_available")],
		[3.0, func() -> void: _accept_two(c)],
		[3.6, func() -> void: _shot("b03_active_two")],
		[3.8, func() -> void:
			var ids: Array = c.contracts.active.map(func(k: Contract) -> String: return k.id)
			c.contracts.set_allocation(ids[0], 60)
			c.contracts.set_allocation(ids[1], 25)],
		[9.0, func() -> void: _shot("b04_active_progress")],
		[9.1, func() -> void: _make_ready(c)],
		[9.8, func() -> void: _shot("b05_ready_to_dispatch")],
		[10.0, func() -> void: _reopen(2)],
		[10.6, func() -> void: _shot("b06_history")],
		[10.8, func() -> void: _close_dialogs(); main.call("_show_offline", _offline_summary())],
		[11.4, func() -> void: _shot("b07_welcome_back")],
		[11.6, func() -> void: _close_dialogs(); main.call("_show_rank_up", 3, "Regional Manufacturer")],
		[12.2, func() -> void: _shot("b08_rank_up")],
		[12.4, func() -> void: _reopen(0)],
		[12.8, func() -> void: _shot("b09_available_again")],
		[13.2, func() -> void: get_tree().quit()],
	]


func _accept_two(c: GameSession) -> void:
	# press the real ACCEPT button once so the interface is exercised, accept the next directly
	var btn := _find_button("ACCEPT")
	if btn != null:
		btn.pressed.emit()
	await get_tree().create_timer(0.3).timeout
	if c.contracts.offers.size() > 0:
		c.contracts.accept(c.contracts.offers[0].id)


## Close whatever is open and, a frame later (queue_free is deferred), open the board on a tab.
func _reopen(tab: int) -> void:
	_close_dialogs()
	await get_tree().process_frame
	await get_tree().process_frame
	main.call("open_contract_board", tab)


func _make_ready(c: GameSession) -> void:
	var first: Contract = c.contracts.active[0]
	first.delivered = first.quantity
	c.contracts._complete(first)


func _offline_summary() -> Dictionary:
	return {
		"away_seconds": 5400.0, "counted_seconds": 5400.0, "capped": false, "cylinders": 8200.0, "cash": 61000.0,
		"factories": [{"name": "Copper Cylinder Works", "cylinders": 8200.0, "cash": 61000.0}],
		"contracts": {
			"paid": [{"customer": "Pennine Plumbing Supplies", "amount": 18900.0}],
			"ready": ["Hartley Builders' Merchants"],
			"failed": [{"customer": "Highfield Homes", "units": 310}],
			"progress": [{"customer": "Redbrook Developments", "added": 2400, "delivered": 5100, "quantity": 9000, "time_left": 2300.0}],
			"new_offers": 3,
		},
	}


func _find_button(prefix: String, root: Node = null) -> Button:
	if root == null:
		root = get_tree().current_scene
	var found: Button = null
	for ch in root.get_children():
		if ch is Button and (ch as Button).text.begins_with(prefix):
			found = ch
		var deeper := _find_button(prefix, ch)
		if deeper != null:
			found = deeper
	return found


func _process(delta: float) -> void:
	_t += delta
	while not _plan.is_empty() and _t >= _plan[0][0]:
		var step: Array = _plan.pop_front()
		(step[1] as Callable).call()


func _close_dialogs() -> void:
	for ch in (main.get("_dialog_layer") as Node).get_children():
		ch.queue_free()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("captured ", shot_name)
