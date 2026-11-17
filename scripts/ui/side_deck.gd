class_name SideDeck
extends Control
## The strip beside the factory in the phone-first layout. From top to bottom: how full the warehouse is,
## ONE obvious thing to do (a customer on the phone, otherwise the best next upgrade), and the four places
## you can go: FACTORY | ORDERS | STOCK | UPGRADES. Nothing else lives on the main screen.

signal navigate(key: String)
signal message(text: String, color: Color)
signal call_answered(result: Dictionary, option: String)

var company: GameSession
var sim: FactorySim
var width := 200
var height := 330

var _wh_bar: PixelBar
var _wh_label: Label
var _holder: VBoxContainer
var _mode := ""
var _card: CallCard = null
var _up := {}
var _nav := {}
var _timer := 0.0
var _blink := 0.0


func setup(p_sim: FactorySim, p_company: GameSession, w: int, h: int) -> void:
	sim = p_sim
	company = p_company
	width = w
	height = h
	size = Vector2(w, h)
	var bg := Panel.new()
	var sb := UiTheme.flat(UiTheme.PARCH, UiTheme.WOOD_DARK, 0, 0)
	sb.border_width_left = 2
	bg.add_theme_stylebox_override("panel", sb)
	bg.size = size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.position = Vector2(6, 5)
	col.size = Vector2(w - 12, h - 10)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(col)
	# warehouse: tap to open the stock screen
	var wh := Button.new()
	wh.focus_mode = Control.FOCUS_NONE
	wh.custom_minimum_size = Vector2(0, 38 if UiTheme.touch else 30)
	wh.pressed.connect(func() -> void:
		Sfx.play("blip")
		navigate.emit("stock"))
	var inner := VBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 5
	inner.offset_right = -5
	inner.offset_top = 3
	inner.offset_bottom = -3
	inner.add_theme_constant_override("separation", 2)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wh.add_child(inner)
	_wh_label = UiTheme.label("", UiTheme.INK)
	inner.add_child(_wh_label)
	_wh_bar = SimpleUi.bar(10.0, UiTheme.TEAL)
	inner.add_child(_wh_bar)
	col.add_child(wh)
	# the one obvious thing
	_holder = SimpleUi.vbox(4)
	_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_holder)
	# navigation
	var grid := GridContainer.new()
	grid.columns = 4 if w >= 280 else 2
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	for pair: Array in ScreenFrame.NAV:
		var b := SimpleUi.button(str(pair[1]), _go.bind(str(pair[0])), pair[0] == "factory")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, SimpleUi.btn_h() if grid.columns == 4 else 26)
		grid.add_child(b)
		_nav[pair[0]] = b
	col.add_child(grid)
	_refresh(true)


func _go(key: String) -> void:
	if key == "factory":
		return
	Sfx.play("blip")
	navigate.emit(key)


func _process(delta: float) -> void:
	_blink += delta
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.2
	_refresh(false)


func _refresh(force: bool) -> void:
	if sim == null:
		return
	var w := sim.warehouse
	if sim.stock_enabled():
		_wh_bar.value = w.usage_fraction()
		_wh_bar.fill = SimpleUi.usage_color(w.usage_fraction())
		_wh_label.text = "WAREHOUSE  %d / %d%s" % [w.total_units(), w.capacity, "  FULL" if w.usage_fraction() >= 0.95 else ""]
	var calls := company.sales.calls
	var want := ""
	if not calls.is_empty():
		want = "call:" + str(calls[0]["id"])
	else:
		var nu := sim.next_upgrade()
		want = "up:" + nu
	if force or want != _mode or (_mode.begins_with("call:") and (_card == null or not is_instance_valid(_card))):
		_mode = want
		_rebuild_action(calls)
	if _card != null and is_instance_valid(_card):
		if not _card.refresh():
			_mode = ""
	if not _up.is_empty():
		_update_upgrade()
	# the ORDERS button glows while somebody is waiting
	var orders := _nav["orders"] as Button
	orders.text = "ORDERS (%d)" % calls.size() if not calls.is_empty() and width >= 280 else ("ORDERS!" if not calls.is_empty() else "ORDERS")
	orders.modulate = Color("ffe08a") if (not calls.is_empty() and int(_blink * 2.5) % 2 == 0) else Color.WHITE


func _rebuild_action(calls: Array) -> void:
	for c in _holder.get_children():
		c.queue_free()
	_card = null
	_up = {}
	if not calls.is_empty():
		_card = CallCard.new()
		_card.setup(company.sales, calls[0])
		_card.answered.connect(_on_answered)
		_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_holder.add_child(_card)
		if calls.size() > 1:
			_holder.add_child(UiTheme.label("+%d more waiting" % (calls.size() - 1), UiTheme.INK_SOFT))
		return
	var id := sim.next_upgrade()
	if id == "":
		var l := UiTheme.label("Everything bought here - nice!", UiTheme.GREEN)
		_holder.add_child(l)
		return
	var d: Dictionary = sim.data.upgrade_by_id[id]
	var card := SimpleUi.card(SimpleUi.GOLD_DARK)
	var col := SimpleUi.vbox(3)
	card.add_child(col)
	col.add_child(UiTheme.label("NEXT UPGRADE", SimpleUi.GOLD_DARK))
	var row := SimpleUi.hbox(5)
	var icon := TextureRect.new()
	icon.texture = UiTheme.icon(str(d["icon"]))
	icon.custom_minimum_size = Vector2(20, 20)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var text := SimpleUi.vbox(1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(SimpleUi.clip(str(d["name"]), UiTheme.INK))
	text.add_child(SimpleUi.clip(UpgradesScreen.simple_text(sim, d), UiTheme.INK_SOFT))
	row.add_child(text)
	col.add_child(row)
	var bar := SimpleUi.bar(10.0, UiTheme.COPPER)
	col.add_child(bar)
	var buy := SimpleUi.button("", _buy.bind(id), true)
	col.add_child(buy)
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_holder.add_child(card)
	_up = {"id": id, "bar": bar, "buy": buy}


func _update_upgrade() -> void:
	var id := str(_up["id"])
	var cost := sim.cost(id)
	var cash := company.state.cash
	var bar := _up["bar"] as PixelBar
	bar.value = clampf(cash / maxf(cost, 0.01), 0.0, 1.0)
	bar.text = "" if cash >= cost else "%s / %s" % [NumFmt.money(cash), NumFmt.money(cost)]
	var buy := _up["buy"] as Button
	var can := sim.can_afford(id)
	buy.text = "BUY  %s" % NumFmt.money(cost)
	buy.modulate = Color.WHITE if can else Color(1, 1, 1, 0.55)


func _buy(id: String) -> void:
	if sim.buy(id):
		Sfx.play("buy")
		message.emit("Bought %s!" % str(sim.data.upgrade_by_id[id]["name"]), UiTheme.GOLD)
		_mode = ""
	else:
		Sfx.play("deny")
		message.emit("Need %s more." % NumFmt.money(maxf(sim.cost(id) - company.state.cash, 0.0)), Color("ff8a70"))


func _on_answered(result: Dictionary, option: String) -> void:
	call_answered.emit(result, option)
	_mode = ""
