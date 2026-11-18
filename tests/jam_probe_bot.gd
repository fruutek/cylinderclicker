extends Node
## Dev probe: watches the end of the conveyor while the van is away, printing the simulation's view (pad, tokens on the
## last belt) next to what is drawn, and taking screenshots.
## Run:  xvfb-run -a godot --path . --resolution 960x540 -- --fresh --autostart --bot=res://tests/jam_probe_bot.gd --capture=/some/folder

var out_dir := ""
var main: Node
var _t := 0.0
var _next := 0
var _times := [2.0, 6.0, 10.0, 14.0, 18.0, 22.0, 26.0, 32.0, 40.0, 50.0, 60.0]
var _s: FactorySim
var _c: GameSession


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			out_dir = arg.trim_prefix("--capture=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_c = Game.session
	Game.save_enabled = false
	_c.state.tutorial_step = 7
	_c.state.lifetime_earned = 60000.0
	_c.bonus_orders.enabled = false
	_s = _c.factory("copper")
	for i in _s.data.stations.size():
		_s.state.upgrade_levels[GameData.machine_id(_s.data.stations[i]["id"])] = int(_s.data.stations[i]["work"]) * 2
	_s.refresh()
	_s.bay.state = DispatchBay.State.AWAY
	_s.bay.timer = 70.0
	main = get_tree().current_scene


func _process(delta: float) -> void:
	_t += delta
	if _t < 1.0:
		for c in (main.get("_dialog_layer") as Node).get_children():
			c.queue_free()
	if _next < _times.size() and _t >= _times[_next]:
		var name := "p%02d" % _next
		_next += 1
		_report(name)
		_shot(name)
		if _next >= _times.size():
			get_tree().quit()


func _report(tag: String) -> void:
	var line := _s.line
	var last := line.stations.size() - 1
	var toks: Array[String] = []
	for tk in line.belts[last].tokens:
		toks.append("%.0f" % tk.pos)
	var view: FactoryView = main.get("_factory")
	var vis: Array[String] = []
	for tk in line.belts[last].tokens:
		if view._token_pos.has(tk.id):
			var v: Vector2 = view._token_pos[tk.id]
			vis.append("(%.0f,%.0f)" % [v.x, v.y])
	print("%s t=%.1f pad %.1f/%.1f belt_len %.0f tokens_on_last_belt %s visual %s blocked %s released %.1f" % [tag, _t, _s.bay.load, _s.bay.storage, line.belts[last].length, toks, vis, line.blocked_stations(), line.released])


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
