class_name Tutorial
extends PanelContainer
## A gentle, self-advancing hint banner along the bottom of the factory.
## Progress is stored in GameState.tutorial_step so it survives saving.

const DONE_STEP := 7
const HINTS := {
	1: "CLICK anywhere on the factory floor (or tap SPACE). Every click works all six stations at once.",
	2: "SOLD! Each cylinder that reaches the van earns its profit. Keep clicking - your first upgrade costs £15.",
	3: "You can afford BETTER HAND TOOLS. Buy it in the UPGRADES tab on the right.",
	4: "Nice. Now save up for a machine in the MACHINES tab - each one runs a station without you.",
	5: "It runs by itself! Automate all six stations and the factory earns hands-free. If cylinders queue up, the next station is too slow.",
	6: "FULLY AUTOMATED! Upgrade the slowest machine to lift the bottleneck. Clicking still speeds everything up. Enjoy!",
}

var session: FactorySim          # the starting factory the hints talk about
var company: GameState
var _label: Label
var _timer := 0.0
var _shown_step := -1
var _final_time := 0.0


func setup(p_session: FactorySim, p_company: GameState) -> void:
	session = p_session
	company = p_company
	var sb := UiTheme.flat(Color("fbf1d6f2"), UiTheme.WOOD_DARK, 1, 5)
	sb.border_width_left = 4
	sb.border_color = UiTheme.COPPER.darkened(0.2)
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiTheme.label("")
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(404, 0)
	add_child(_label)
	_update()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.2
		_advance(0.2)
		_update()


func _advance(dt: float) -> void:
	var st := company
	var any_upgrade := false
	for u: Dictionary in session.data.upgrades:
		if session.level(u["id"]) > 0:
			any_upgrade = true
	match st.tutorial_step:
		1:
			if session.state.cylinders_made >= 1.0:
				st.tutorial_step = 2
		2:
			if any_upgrade or session.automated_count() > 0:
				st.tutorial_step = 4
			elif session.can_afford("hand_tools"):
				st.tutorial_step = 3
		3:
			if any_upgrade or session.automated_count() > 0:
				st.tutorial_step = 4
		4:
			if session.automated_count() > 0:
				st.tutorial_step = 5
		5:
			if session.all_automated():
				st.tutorial_step = 6
		6:
			_final_time += dt
			if _final_time > 25.0:
				st.tutorial_step = DONE_STEP


func _update() -> void:
	var step := company.tutorial_step
	visible = HINTS.has(step) and company.current_factory == session.data.id
	if step != _shown_step and visible:
		if _shown_step != -1:
			Sfx.play("blip")
		_label.text = HINTS[step]
		reset_size()
		position = Vector2(8, Hud.HEIGHT + 330 - size.y - 10)
	_shown_step = step
