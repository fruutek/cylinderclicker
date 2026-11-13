class_name Hud
extends Control
## Top bar: company cash and income, then the factory on screen (product,
## cylinders made, live rate), the Factories button and the menu button.

signal settings_pressed
signal factories_pressed

const HEIGHT := 30

var company: GameSession        # cash and income are company-wide
var session: FactorySim          # the factory currently on screen
var _factories: Button
var _factories_style: StyleBoxFlat
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

	_add_label(Vector2(150, 4), UiTheme.PARCH_DARK).text = "NOW MAKING"
	_product = _add_label(Vector2(150, 15), UiTheme.CREAM)
	_add_label(Vector2(264, 4), UiTheme.PARCH_DARK).text = "PROFIT EACH"
	_profit = _add_label(Vector2(264, 15), Color("9ff0a0"))

	var cyl := TextureRect.new()
	cyl.texture = preload("res://assets/sprites/cyl_icon.png")
	cyl.position = Vector2(336, 9)
	cyl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cyl)
	_add_label(Vector2(350, 4), UiTheme.PARCH_DARK).text = "CYLINDERS MADE"
	_made = _add_label(Vector2(350, 15), UiTheme.CREAM)
	_add_label(Vector2(446, 4), UiTheme.PARCH_DARK).text = "OUTPUT"
	_rate = _add_label(Vector2(446, 15), UiTheme.CREAM)

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
	_factories.position = Vector2(524, 5)
	_factories.size = Vector2(84, 20)

	if UiTheme.touch:
		# Finger-sized buttons.
		_gear.position = Vector2(606, 2)
		_gear.size = Vector2(30, 26)
		_factories.position = Vector2(516, 2)
		_factories.size = Vector2(86, 26)
	# Remember where everything sits on the 640-wide desktop bar.
	var bounds := [150.0, 264.0, 336.0, 446.0, 500.0]
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
	_product.text = session.data.hud_product if session.data.hud_product != "" else String(session.product["name"])
	_profit.text = NumFmt.money(session.profit_per_cylinder())
	_made.text = NumFmt.number(session.state.cylinders_made)
	_rate.text = "%s/min" % NumFmt.number(per_min, 1)

	# The Factories button glows when a new factory can be built.
	_blink += delta
	var buildable := false
	for sim in company.factories:
		if company.can_unlock(sim.data.id):
			buildable = true
	_factories_style.bg_color = UiTheme.GOLD.darkened(0.25) if buildable and int(_blink * 2.5) % 2 == 0 else UiTheme.WOOD_LIGHT
