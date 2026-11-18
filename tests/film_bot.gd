extends Node
## Dev probe: a frame-by-frame film strip of the conveyor end - a cylinder leaving the belt and landing on the pile,
## and (second strip) the van loading it away.
## Run:  xvfb-run -a godot --path . --resolution 960x540 -- --fresh --autostart --bot=res://tests/film_bot.gd --capture=/some/folder

var out_dir := ""
var main: Node
var _s: FactorySim
var _c: GameSession
var _t := 0.0
var _phase := 0
var _frames: Array[Image] = []
var _grab := 0
var _region := Rect2i(0, 215, 260, 145)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			out_dir = arg.trim_prefix("--capture=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_c = Game.session
	Game.save_enabled = false
	_c.state.tutorial_step = 7
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
	match _phase:
		0:
			# wait until a carton is about to leave the belt (a token at the very end of the last belt)
			if _t > 14.0:
				var last := _s.line.stations.size() - 1
				for tk in _s.line.belts[last].tokens:
					if tk.pos > 42.0:
						_phase = 1
		1:
			if _grab < 22:
				_capture()
			else:
				_save_strip("film_drop")
				_frames.clear()
				_grab = 0
				_phase = 2
				_s.bay.timer = 0.3          # the van comes back to collect
		2:
			# once the van is loading, film it
			if _s.bay.state == DispatchBay.State.LOADING and _s.bay.carry_load > 0.5 and _grab < 22:
				_capture()
			elif _grab >= 22:
				_save_strip("film_load")
				get_tree().quit()


var _skip := 0


func _capture() -> void:
	_skip += 1
	if _skip % 2 != 0:
		return
	_grab += 1
	await RenderingServer.frame_post_draw
	_frames.append(get_viewport().get_texture().get_image().get_region(_region))


func _save_strip(strip_name: String) -> void:
	var cols := 6
	var rows := int(ceil(float(_frames.size()) / cols))
	var w := _region.size.x
	var h := _region.size.y
	var sheet := Image.create(cols * w, rows * h, false, Image.FORMAT_RGBA8)
	for i in _frames.size():
		sheet.blit_rect(_frames[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(out_dir.path_join(strip_name + ".png"))
	print("saved ", strip_name, " frames=", _frames.size())
