extends Node
## Dev tool: screenshots of the classic game - the factory with its delivery van, the cylinder picker, the shop, the
## bonus order and the stainless plant.
## Run:  xvfb-run -a godot --path . --resolution 960x540 -- --fresh --autostart --bot=res://tests/classic_capture_bot.gd --capture=/some/folder

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
	c.state.cash = 9000.0
	c.state.lifetime_earned = 40000.0
	var s := c.factory("copper")
	for m: Dictionary in s.data.machines:
		s.state.upgrade_levels[m["id"]] = 7
	s.state.upgrade_levels["variant_cu_dir"] = 1
	s.state.upgrade_levels["variant_cu_ind"] = 1
	s.state.upgrade_levels["van_speed"] = 2
	s.state.earned = 40000.0
	s.select_variant("CU-IND")
	s.refresh()
	c.bonus_orders.reset(5)
	c.bonus_orders.timer = 0.0
	main = get_tree().current_scene
	_plan = [
		[1.0, func() -> void: _close_dialogs()],
		[2.5, func() -> void: _shot("c01_factory_order_offer")],
		[2.7, func() -> void: main.get("_shop").show_tab(2)],
		[3.3, func() -> void: _shot("c02_cylinders_tab")],
		[3.5, func() -> void:
			main.get("_shop").show_tab(0)
			c.bonus_orders.accept()],
		[4.3, func() -> void: _shot("c03_upgrades_order_active")],
		[4.5, func() -> void:
			var bay := c.factory("copper").bay
			bay.add(18.0, 200.0)
			bay.state = DispatchBay.State.LEAVING
			bay.carry_load = 18.0
			bay.carry_money = 200.0
			bay.timer = 1.4],
		[5.2, func() -> void: _shot("c04_van_loading")],
		[6.2, func() -> void: _shot("c05_van_leaving")],
		[8.0, func() -> void: _shot("c06_van_away")],
		[9.0, func() -> void:
			var st := c.factory("stainless")
			st.state.unlocked = true
			for m: Dictionary in st.data.machines:
				st.state.upgrade_levels[m["id"]] = 3
			st.state.upgrade_levels["variant_st_dir"] = 1
			st.state.upgrade_levels["variant_st_ind"] = 1
			st.state.upgrade_levels["variant_st_twn"] = 1
			st.state.earned = 3.0e7
			st.select_variant("ST-TWN")
			st.refresh()
			main.call("switch_factory", "stainless")],
		[10.3, func() -> void: _shot("c07_stainless_premium")],
		[10.5, func() -> void: main.get("_shop").show_tab(2)],
		[11.1, func() -> void: _shot("c08_stainless_cylinders")],
		[11.5, func() -> void: get_tree().quit()],
	]


func _process(delta: float) -> void:
	_t += delta
	while not _plan.is_empty() and _t >= _plan[0][0]:
		var step: Array = _plan.pop_front()
		(step[1] as Callable).call()


func _close_dialogs() -> void:
	for c in (main.get("_dialog_layer") as Node).get_children():
		c.queue_free()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("captured ", shot_name)
