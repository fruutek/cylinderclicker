extends Node
## Dev tool: end-to-end check of the real save -> quit -> load -> offline
## flow through the Game autoload. Run it twice with the same save path
## (tests/run_save_flow.sh does this and back-dates the save in between).

var main: Node


func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	var c: GameSession = Game.session
	var s: FactorySim = c.factory("copper")
	if Game.is_new_game:
		c.state.cash = 5000.0
		for m: Dictionary in s.data.machines:
			s.buy(m["id"])
			s.buy(m["id"])
		s.buy("finish")
		c.state.tutorial_step = 7
		await get_tree().create_timer(1.0).timeout
		print("PHASE1 cash=%.2f levels=%s" % [c.state.cash, JSON.stringify(s.state.upgrade_levels)])
		# Exercise the genuine window-close path (saves, then quits).
		get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	else:
		var dialogs: Node = main.get("_dialog_layer")
		print("PHASE2 cash=%.2f levels=%s cylinders=%.0f offline_dialog=%s rate=%.4f profit=%.2f" % [
			c.state.cash, JSON.stringify(s.state.upgrade_levels), s.state.cylinders_made,
			dialogs.get_child_count() > 0, s.steady_rate(), s.profit_per_cylinder()])
		get_tree().quit()
