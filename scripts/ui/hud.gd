class_name Hud
extends Control
## Top bar: company cash and income, then the factory on screen (product,
## cylinders made, live rate), the Factories button and the menu button.

signal settings_pressed
signal factories_pressed
signal orders_pressed

const HEIGHT := 30

var company: GameSession        # cash and income are company-wide
var session: FactorySim          # the factory currently on screen
var _factories: Button
var _factories_style: StyleBoxFlat
var _orders: Button
var _orders_style: StyleBoxFlat
var _badge: Label
var _stars: Control
var simple := false              # phone-first bar: money and what is being made, nothing else
var unseen_offers := 0           # new customer orders the player has not looked at yet (set by the game scene)
var _badge_shown := -1
var _rep_shown := -1
var _blink := 0.0
var _bg: Panel
var _shine: ColorRect
var _gear: Button
var _groups: Array = []          # [node, base x, group] for every item, so the bar can stretch
var _cash: Label
var _income: Label
var _product: Label
var _profit: Label
var _made: Label
var _rate: Label
var _shown_cash := 0.0
var _cash_flash := 0.0


func setup(p_company: GameSession) -> void:
	company = p_company
	session = company.current()
	custom_minimum_size = Vector2(640, HEIGHT)
	size = Vector2(640, HEIGHT)

	var bg := Panel.new()
	var sb := UiTheme.flat(UiTheme.WOOD, UiTheme.WOOD_DARK, 0, 0)
	sb.border_width_bottom = 2
	sb.border_width_top = 1
	sb.border_color = UiTheme.WOOD_DARK
	bg.add_theme_stylebox_override("panel", sb)
	bg.size = size
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	_bg = bg
	var shine := ColorRect.new()
	shine.color = UiTheme.WOOD_LIGHT
	shine.position = Vector2(0, 1)
	shine.size = Vector2(640, 1)
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shine)
	_shine = shine

	var coin := TextureRect.new()
	coin.texture = preload("res://assets/sprites/coin.png")
	coin.position = Vector2(6, 9)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(coin)
	_cash = _add_label(Vector2(22, 3), UiTheme.GOLD, 16)
	_income = _add_label(Vector2(23, 19), UiTheme.CREAM)

	# Company reputation: five stars under the cash, lit as the rank rises.
	_stars = RepStars.new()
	_stars.position = Vector2(106, 19)
	_stars.size = Vector2(RepStars.WIDTH, 7)
	_stars.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_stars)

	_add_label(Vector2(142, 4), UiTheme.PARCH_DARK).text = "NOW MAKING"
	_product = _add_label(Vector2(142, 15), UiTheme.CREAM)
	_add_label(Vector2(232, 4), UiTheme.PARCH_DARK).text = "PROFIT EACH"
	_profit = _add_label(Vector2(232, 15), Color("9ff0a0"))

	var cyl := TextureRect.new()
	cyl.texture = preload("res://assets/sprites/cyl_icon.png")
	cyl.position = Vector2(302, 9)
	cyl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cyl)
	_add_label(Vector2(315, 4), UiTheme.PARCH_DARK).text = "CYLINDERS MADE"
	_made = _add_label(Vector2(315, 15), UiTheme.CREAM)
	_add_label(Vector2(404, 4), UiTheme.PARCH_DARK).text = "OUTPUT"
	_rate = _add_label(Vector2(404, 15), UiTheme.CREAM)

	var gear := Button.new()
	gear.icon = preload("res://assets/sprites/gear.png")
	gear.tooltip_text = "Menu (Esc)"
	gear.position = Vector2(614, 5)
	gear.size = Vector2(22, 20)
	gear.focus_mode = Control.FOCUS_NONE
	var gsb := UiTheme.flat(UiTheme.WOOD_LIGHT, UiTheme.WOOD_DARK, 1, 2)
	var gsb_hover := UiTheme.flat(UiTheme.COPPER, UiTheme.WOOD_DARK, 1, 2)
	gear.add_theme_stylebox_override("normal", gsb)
	gear.add_theme_stylebox_override("hover", gsb_hover)
	gear.add_theme_stylebox_override("pressed", gsb)
	gear.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gear.pressed.connect(func() -> void: settings_pressed.emit())
	add_child(gear)
	_gear = gear

	# Factories button: opens the overview of every factory the company owns.
	_factories = Button.new()
	_factories.text = "FACTORIES"
	_factories.icon = preload("res://assets/sprites/factories_icon.png")
	_factories.tooltip_text = "Factory overview (F)"
	_factories.focus_mode = Control.FOCUS_NONE
	_factories_style = UiTheme.flat(UiTheme.WOOD_LIGHT, UiTheme.WOOD_DARK, 1, 2)
	_factories.add_theme_stylebox_override("normal", _factories_style)
	_factories.add_theme_stylebox_override("hover", gsb_hover)
	_factories.add_theme_stylebox_override("pressed", _factories_style)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_factories.add_theme_color_override(c, UiTheme.CREAM)
	_factories.pressed.connect(func() -> void: factories_pressed.emit())
	add_child(_factories)
	_factories.position = Vector2(530, 5)
	_factories.size = Vector2(78, 20)

	# Orders button: opens the Contract Board. Hidden until the first customer calls.
	_orders = Button.new()
	_orders.text = "ORDERS"
	_orders.icon = preload("res://assets/sprites/orders_icon.png")
	_orders.tooltip_text = "Contract Board (C)"
	_orders.focus_mode = Control.FOCUS_NONE
	_orders_style = UiTheme.flat(UiTheme.WOOD_LIGHT, UiTheme.WOOD_DARK, 1, 2)
	_orders.add_theme_stylebox_override("normal", _orders_style)
	_orders.add_theme_stylebox_override("hover", gsb_hover)
	_orders.add_theme_stylebox_override("pressed", _orders_style)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_orders.add_theme_color_override(c, UiTheme.CREAM)
	_orders.pressed.connect(func() -> void: orders_pressed.emit())
	add_child(_orders)
	_orders.position = Vector2(458, 5)
	_orders.size = Vector2(68, 20)
	_orders.visible = false
	_badge = Label.new()
	_badge.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE)
	_badge.add_theme_color_override("font_color", Color.WHITE)
	var badge_style := UiTheme.flat(Color("c0392b"), UiTheme.OUTLINE, 1, 1)
	badge_style.content_margin_top = 0
	badge_style.content_margin_bottom = 0
	_badge.add_theme_stylebox_override("normal", badge_style)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.visible = false
	_orders.add_child(_badge)

	if UiTheme.touch:
		# Finger-sized buttons.
		_gear.position = Vector2(606, 2)
		_gear.size = Vector2(30, 26)
		_factories.position = Vector2(526, 2)
		_factories.size = Vector2(78, 26)
		_orders.position = Vector2(456, 2)
		_orders.size = Vector2(66, 26)
	# Remember where everything sits on the 640-wide desktop bar.
	var bounds := [142.0, 232.0, 302.0, 404.0, 450.0]
	for c in get_children():
		if c == _bg or c == _shine:
			continue
		var x := (c as Control).position.x
		var group := 0
		for b: float in bounds:
			if x >= b:
				group += 1
		_groups.append([c, x, group])

	_shown_cash = company.state.cash
	for sim in company.factories:
		sim.shipped.connect(_on_any_shipped.bind(sim))
	(_stars as RepStars).book = company.contracts


## Fits the bar to the screen width. At 640 wide with no insets this is
## exactly the desktop layout; on wider phone screens the groups spread out
## and everything stays clear of rounded corners and the camera cutout.
func layout(total_width: float, inset_left: float, inset_right: float) -> void:
	size = Vector2(total_width, HEIGHT)
	_bg.size = size
	_shine.size = Vector2(total_width, 1)
	var extra := maxf(total_width - inset_left - inset_right - 640.0, 0.0)
	for item: Array in _groups:
		var node: Control = item[0]
		var group: int = item[2]
		if group >= 5:
			node.position.x = float(item[1]) + (total_width - 640.0) - inset_right
		else:
			node.position.x = float(item[1]) + inset_left + floorf(extra * group / 5.0)


## The phone-first bar: cash, what is being made, the factory switcher and the menu. Statistics, the orders
## button and the reputation stars move to the screens behind the four destinations.
func simplify() -> void:
	simple = true
	for item: Array in _groups:
		if int(item[2]) in [2, 3, 4]:
			(item[0] as Control).visible = false
	_stars.visible = false
	_orders.visible = false


## Points the factory part of the bar at a different factory.
func set_factory(sim: FactorySim) -> void:
	session = sim


func _on_any_shipped(_count: float, _amount: float, sim: FactorySim) -> void:
	if sim == session:
		_cash_flash = 0.25


func _add_label(pos: Vector2, color: Color, font_size: int = UiTheme.FONT_SIZE) -> Label:
	var l := UiTheme.label("", color, font_size)
	l.position = pos
	add_child(l)
	return l


func _process(delta: float) -> void:
	if session == null:
		return
	# Roll the counter towards the real value so earnings feel alive.
	var cash := company.state.cash
	var diff := cash - _shown_cash
	if absf(diff) < 0.5:
		_shown_cash = cash
	else:
		_shown_cash += diff * minf(1.0, delta * 12.0)
	_cash.text = NumFmt.money(floorf(_shown_cash) if _shown_cash >= 100.0 else _shown_cash)
	_cash_flash = maxf(_cash_flash - delta, 0.0)
	_cash.add_theme_color_override("font_color", Color.WHITE if _cash_flash > 0.15 else UiTheme.GOLD)

	var per_min := session.recent_rate_per_min()
	_income.text = "%s/sec" % NumFmt.money(company.recent_income_per_second())
	if session.stock_enabled():
		_product.text = String(session.skus[session.current_sku]["name"])
		_profit.text = NumFmt.money(session.sku_profit(session.current_sku))
	else:
		_product.text = session.data.hud_product if session.data.hud_product != "" else String(session.product["name"])
		_profit.text = NumFmt.money(session.profit_per_cylinder())
	_made.text = NumFmt.number(session.state.cylinders_made)
	_rate.text = "%s/min" % NumFmt.number(per_min, 1)

	# Orders: appears once customers start calling, with a badge for anything waiting for you
	# (orders ready to dispatch, new offers) and a gold glow when a lorry can be sent.
	var book := company.contracts
	var calls := company.sales.calls.size() if company.state.stock_mode else 0
	_orders.visible = (book.unlocked or (company.state.stock_mode and company.sales.unlocked)) and not simple
	if _orders.visible:
		var ready := book.count_status(Contract.Status.READY) + (1 if calls > 0 else 0)
		var waiting := ready - (1 if calls > 0 else 0) + unseen_offers + calls
		if waiting != _badge_shown:
			_badge_shown = waiting
			_badge.visible = waiting > 0
			if waiting > 0:
				_badge.text = str(mini(waiting, 9)) + ("+" if waiting > 9 else "")
				_badge.reset_size()
				_badge.position = Vector2(_orders.size.x - _badge.size.x + 3.0, -3.0)
		_orders_style.bg_color = UiTheme.GOLD.darkened(0.25) if ready > 0 and int(_blink * 2.5) % 2 == 0 else UiTheme.WOOD_LIGHT
	if book.reputation != _rep_shown:
		_rep_shown = book.reputation
		_stars.tooltip_text = "Company reputation: %s (%d)" % [book.rank_name(), book.reputation]

	# The Factories button glows when a new factory can be built.
	_blink += delta
	var buildable := false
	for sim in company.factories:
		if company.can_unlock(sim.data.id):
			buildable = true
	_factories_style.bg_color = UiTheme.GOLD.darkened(0.25) if buildable and int(_blink * 2.5) % 2 == 0 else UiTheme.WOOD_LIGHT


## Five small stars showing the company's reputation rank at a glance.
class RepStars extends Control:
	const WIDTH := 39
	const TEX := preload("res://assets/sprites/stars.png")
	var book: ContractBook
	var _lit := -1

	func _process(_delta: float) -> void:
		if book != null and book.rank_index() != _lit:
			queue_redraw()

	func _draw() -> void:
		if book == null:
			return
		var lit := book.rank_index()
		_lit = lit
		for i in 5:
			draw_texture_rect_region(TEX, Rect2(i * 8, 0, 7, 7), Rect2(0 if i < lit else 7, 0, 7, 7))
