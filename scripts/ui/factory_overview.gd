class_name FactoryOverview
extends ModalDialog
## The company's factories at a glance: one card per factory building with
## its earnings, output and automation, a button to walk into it, and for
## locked factories the requirements and price to build it. The game keeps
## running behind this dialog, so the numbers are live.

signal enter_requested(id: String)
signal build_requested(id: String)

var company: GameSession
var _summary: Label
var _cards: Array[Dictionary] = []
var _timer := 0.0


func _init(p_company: GameSession) -> void:
	super("YOUR FACTORIES", 436)
	company = p_company
	_summary = add_text("")
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	add_control(grid)
	for sim in company.factories:
		grid.add_child(_build_card(sim))
	add_button("Close")
	_refresh()


func _build_card(sim: FactorySim) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.PARCH_LIGHT, UiTheme.WOOD_DARK, 1, 5))
	card.custom_minimum_size = Vector2(204, 150)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	box.add_child(top)
	var thumb := TextureRect.new()
	thumb.texture = load("res://assets/sprites/%s.png" % sim.data.thumbnail)
	thumb.custom_minimum_size = Vector2(64, 44)
	thumb.stretch_mode = TextureRect.STRETCH_KEEP
	top.add_child(thumb)
	var lock := TextureRect.new()
	lock.texture = preload("res://assets/sprites/padlock.png")
	lock.position = Vector2(27, 16)
	thumb.add_child(lock)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 2)
	top.add_child(heading)
	heading.add_child(UiTheme.label("FACTORY %d" % (sim.data.index + 1), UiTheme.INK_SOFT))
	heading.add_child(UiTheme.label(sim.data.name.to_upper(), UiTheme.COPPER.darkened(0.3)))
	var status := UiTheme.label("")
	heading.add_child(status)

	var body := UiTheme.label("")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(190, 0)
	box.add_child(body)
	var reqs := VBoxContainer.new()
	reqs.add_theme_constant_override("separation", 1)
	box.add_child(reqs)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, UiTheme.button_height())
	button.pressed.connect(_on_card_button.bind(sim.data.id))
	box.add_child(button)
	_cards.append({"sim": sim, "thumb": thumb, "lock": lock, "status": status, "body": body, "reqs": reqs, "button": button})
	return card


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.25
		_refresh()


func _refresh() -> void:
	_summary.text = "%s   -   Cash %s   -   Earning %s/sec across all factories" % [
		company.state.factory_name, NumFmt.money(company.state.cash), NumFmt.money(company.recent_income_per_second())]
	for card in _cards:
		var sim: FactorySim = card["sim"]
		var status: Label = card["status"]
		var body: Label = card["body"]
		var button: Button = card["button"]
		var reqs: VBoxContainer = card["reqs"]
		var unlocked := sim.state.unlocked
		(card["lock"] as TextureRect).visible = not unlocked
		(card["thumb"] as TextureRect).modulate = Color.WHITE if unlocked else Color(0.45, 0.45, 0.5)
		for c in reqs.get_children():
			c.queue_free()
		if unlocked:
			var here := company.state.current_factory == sim.data.id
			status.text = "OPEN - you are here" if here else "OPEN"
			status.add_theme_color_override("font_color", UiTheme.GREEN)
			var n := sim.automated_count()
			var total := sim.data.stations.size()
			body.text = "Earning %s/sec\nOutput %s/min\nCylinders made: %s\nAutomation: %s" % [
				NumFmt.money(sim.recent_rate_per_min() / 60.0 * sim.profit_per_cylinder()),
				NumFmt.number(sim.recent_rate_per_min(), 1), NumFmt.number(sim.state.cylinders_made),
				"fully automated" if n == total else "%d of %d stations" % [n, total]]
			button.text = "You are here" if here else "Enter factory"
			button.disabled = here
		else:
			status.text = "LOCKED"
			status.add_theme_color_override("font_color", UiTheme.RED)
			body.text = sim.data.description
			for r: Dictionary in company.unlock_requirements(sim.data.id):
				var l := UiTheme.label(("✓ " if r["met"] else "• ") + String(r["text"]), UiTheme.GREEN if r["met"] else UiTheme.RED)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				l.custom_minimum_size = Vector2(190, 0)
				reqs.add_child(l)
			var cost := sim.data.unlock_cost()
			var affordable := company.state.cash >= cost
			reqs.add_child(UiTheme.label(("✓ " if affordable else "• ") + "Construction cost: %s" % NumFmt.money(cost),
				UiTheme.GREEN if affordable else UiTheme.RED))
			button.text = "Build factory - %s" % NumFmt.money(cost)
			button.disabled = not company.can_unlock(sim.data.id)


func _on_card_button(id: String) -> void:
	Sfx.play("blip")
	if company.factory(id).state.unlocked:
		enter_requested.emit(id)
	else:
		build_requested.emit(id)
