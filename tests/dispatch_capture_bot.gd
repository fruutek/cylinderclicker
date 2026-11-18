extends Node
## Dev tool: screenshots of the production-bottleneck story - a flowing line, the pad filling while the van is away,
## the whole line backed up (machines dimmed, queues full, LINE FULL on tap), and the same factory after the dispatch
## upgrades. Also drives the real shop rows.
## Run:  xvfb-run -a godot --path . --resolution 960x540 -- --fresh --autostart --bot=res://tests/dispatch_capture_bot.gd --capture=/some/folder

var out_dir := ""
var main: Node
var _plan: Array = []
var _t := 0.0
var _c: GameSession
var _s: FactorySim


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			out_dir = arg.trim_prefix("--capture=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_c = Game.session
	Game.save_enabled = false
	_c.state.tutorial_step = 7
	_c.state.cash = 3000.0
	_c.state.lifetime_earned = 60000.0
	_c.bonus_orders.enabled = false
	_s = _c.factory("copper")
	# machines of equal speed so the jam spreads cleanly from the dispatch end
	for i in _s.data.stations.size():
		_s.state.upgrade_levels[GameData.machine_id(_s.data.stations[i]["id"])] = int(_s.data.stations[i]["work"]) * 2
	_s.state.upgrade_levels["variant_cu_dir"] = 1
	_s.state.earned = 60000.0
	_s.select_variant("CU-DIR")
	_s.refresh()
	main = get_tree().current_scene
	_plan = [
		[0.8, func() -> void: _close_dialogs()],
		[3.0, func() -> void: _shot("d01_flowing")],
		[3.1, func() -> void:
			# the van is out for a long time: cylinders pile up on the pad
			_s.bay.set_stats(12.0, 16.0, 40.0, 0.0)
			_s.bay.state = DispatchBay.State.AWAY
			_s.bay.timer = 40.0],
		[9.0, func() -> void: _shot("d02_pad_filling")],
		[16.0, func() -> void: _shot("d03_backing_up")],
		[30.0, func() -> void: _shot("d04_line_full")],
		[30.2, func() -> void: _tap_factory()],
		[30.5, func() -> void: _shot("d05_tap_says_line_full")],
		[30.6, func() -> void:
			main.get("_shop").show_tab(0)],
		[31.2, func() -> void: _shot("d06_shop_flags_fix")],
		[31.4, func() -> void:
			# the fix: three dispatch upgrades
			_s.state.upgrade_levels["dispatch_store"] = 4
			_s.state.upgrade_levels["van_load"] = 3
			_s.state.upgrade_levels["van_speed"] = 3
			_s.refresh()
			_s.bay.state = DispatchBay.State.ARRIVING
			_s.bay.timer = 0.4],
		[36.0, func() -> void: _shot("d07_after_upgrades_loading")],
		[41.0, func() -> void: _shot("d08_flowing_again")],
		[41.5, func() -> void: get_tree().quit()],
	]


func _process(delta: float) -> void:
	_t += delta
	while not _plan.is_empty() and _t >= _plan[0][0]:
		var step: Array = _plan.pop_front()
		(step[1] as Callable).call()


func _tap_factory() -> void:
	for i in 3:
		_s.click()


func _close_dialogs() -> void:
	for c in (main.get("_dialog_layer") as Node).get_children():
		c.queue_free()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("captured ", shot_name)
