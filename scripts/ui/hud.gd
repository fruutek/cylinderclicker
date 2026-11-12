class_name Hud
extends Control
## Top bar: cash, income, current product, cylinders made and live rate.

signal settings_pressed

const HEIGHT := 30

var session: GameSession
var _cash: Label
var _income: Label
var _product: Label
var _profit: Label
var _made: Label
var _rate: Label
var _shown_cash := 0.0
var _cash_flash := 0.0


func setup(p_session: GameSession) -> void:
	session = p_session
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
	var shine := ColorRect.new()
	shine.color = UiTheme.WOOD_LIGHT
	shine.position = Vector2(0, 1)
	shine.size = Vector2(640, 1)
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shine)

	var coin := TextureRect.new()
	coin.texture = preload("res://assets/sprites/coin.png")
	coin.position = Vector2(6, 9)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(coin)
	_cash = _add_label(Vector2(22, 3), UiTheme.GOLD, 16)
	_income = _add_label(Vector2(23, 19), UiTheme.CREAM)

	_add_label(Vector2(160, 4), UiTheme.PARCH_DARK).text = "NOW MAKING"
	_product = _add_label(Vector2(160, 15), UiTheme.CREAM)
	_add_label(Vector2(290, 4), UiTheme.PARCH_DARK).text = "PROFIT EACH"
	_profit = _add_label(Vector2(290, 15), Color("9ff0a0"))

	var cyl := TextureRect.new()
	cyl.texture = preload("res://assets/sprites/cyl_icon.png")
	cyl.position = Vector2(376, 9)
	cyl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cyl)
	_add_label(Vector2(390, 4), UiTheme.PARCH_DARK).text = "CYLINDERS MADE"
	_made = _add_label(Vector2(390, 15), UiTheme.CREAM)
	_add_label(Vector2(500, 4), UiTheme.PARCH_DARK).text = "OUTPUT"
	_rate = _add_label(Vector2(500, 15), UiTheme.CREAM)

	var gear := Button.new()
	gear.icon = preload("res://assets/sprites/gear.png")
	gear.tooltip_text = "Settings (Esc)"
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

	_shown_cash = session.state.cash
	session.shipped.connect(func(_c: float, _a: float) -> void: _cash_flash = 0.25)


func _add_label(pos: Vector2, color: Color, font_size: int = UiTheme.FONT_SIZE) -> Label:
	var l := UiTheme.label("", color, font_size)
	l.position = pos
	add_child(l)
	return l


func _process(delta: float) -> void:
	if session == null:
		return
	# Roll the counter towards the real value so earnings feel alive.
	var cash := session.state.cash
	var diff := cash - _shown_cash
	if absf(diff) < 0.5:
		_shown_cash = cash
	else:
		_shown_cash += diff * minf(1.0, delta * 12.0)
	_cash.text = NumFmt.money(floorf(_shown_cash) if _shown_cash >= 100.0 else _shown_cash)
	_cash_flash = maxf(_cash_flash - delta, 0.0)
	_cash.add_theme_color_override("font_color", Color.WHITE if _cash_flash > 0.15 else UiTheme.GOLD)

	var per_min := session.recent_rate_per_min()
	var live_income := per_min / 60.0 * session.profit_per_cylinder()
	_income.text = "%s/sec" % NumFmt.money(live_income)
	_product.text = String(session.product["name"])
	_profit.text = NumFmt.money(session.profit_per_cylinder())
	_made.text = NumFmt.number(session.state.cylinders_made)
	_rate.text = "%s/min" % NumFmt.number(per_min, 1)
