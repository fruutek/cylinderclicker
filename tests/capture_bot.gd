extends Node
## Dev tool: plays the game automatically and saves screenshots, so the
## visuals can be checked on machines with no display attached.
## Run:  godot --path . -- --fresh --autostart --bot=res://tests/capture_bot.gd --capture=/some/folder

var out_dir := ""
var main: Node
var _t := 0.0
var _click_acc := 0.0
var _shots := 0
var _plan: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			out_dir = arg.trim_prefix("--capture=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var s: GameSession = Game.session
	_plan = [
		[0.5, func() -> void: _shot("01_intro")],
		[0.7, func() -> void: _close_dialogs(); s.state.tutorial_step = 1],
		[6.0, func() -> void: _shot("02_first_clicks")],
		[22.0, func() -> void: _shot("03_selling")],
		[22.1, func() -> void:
			s.state.cash += 400.0
			s.state.lifetime_earned += 400.0
			s.buy("hand_tools"); s.buy("machine_cut"); s.buy("machine_roll")
			main.get("_shop").show_tab(1)],
		[34.0, func() -> void: _shot("04_part_automated")],
		[34.1, func() -> void:
			for m: Dictionary in s.data.machines:
				s.state.upgrade_levels[m["id"]] = 4
			s.state.upgrade_levels["machine_weld"] = 1
			s.state.lifetime_earned += 5000.0
			s.refresh()
			s.upgrade_purchased.emit("machine_weld", 1)],
		[60.0, func() -> void: _hover_row("machine_weld"); _shot_later("05_bottleneck_tooltip")],
		[62.0, func() -> void: main.get("_shop").show_tab(0); _hover_row("finish"); _shot_later("06_upgrades_tab")],
		[64.0, func() -> void: main.get("_shop").show_tab(2); _shot_later("07_products_tab")],
		[66.0, func() -> void: main.call("open_pause_menu"); _shot_later("08_pause_menu")],
		[68.0, func() -> void:
			_close_dialogs()
			get_tree().paused = false
			main.call("_show_offline", {"away_seconds": 7400.0, "counted_seconds": 7400.0, "capped": false, "cylinders": 925.0, "cash": 7400.0})
			_shot_later("09_offline")],
		[70.0, func() -> void:
			_close_dialogs()
			for m: Dictionary in s.data.machines:
				s.state.upgrade_levels[m["id"]] = 60
			s.refresh()
			main.get("_shop").show_tab(1)],
		[84.0, func() -> void: _shot("10_high_volume")],
		[84.5, func() -> void: get_tree().quit()],
	]


func _process(delta: float) -> void:
	_t += delta
	if _t > 1.0 and _t < 34.0:
		_click_acc += delta * 5.0
		while _click_acc >= 1.0:
			_click_acc -= 1.0
			main.call("do_click", Vector2(randf_range(120, 380), randf_range(160, 220)))
	while not _plan.is_empty() and _t >= _plan[0][0]:
		var step: Array = _plan.pop_front()
		(step[1] as Callable).call()


func _close_dialogs() -> void:
	for c in (main.get("_dialog_layer") as Node).get_children():
		c.queue_free()


func _hover_row(id: String) -> void:
	var shop: ShopPanel = main.get("_shop")
	shop.call("_on_row_hover", id, shop.get("_rows")[id]["btn"])


func _shot_later(shot_name: String) -> void:
	await get_tree().create_timer(0.4).timeout
	_shot(shot_name)


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	_shots += 1
	print("captured ", shot_name)
