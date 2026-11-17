class_name CallCard
extends PanelContainer
## A customer is on the telephone. One card, plain words: who, what they want, what is in stock and what is
## missing, and at most three buttons - FULFIL ORDER; or SEND n + MAKE m / SEND n ONLY / DECLINE.
## The production queue, reservations and lorries are all handled behind the buttons.

signal answered(result: Dictionary, option: String)

var office: SalesOffice
var call_id := ""
var _sig := ""
var _who: Label
var _want: Label
var _stock: Label
var _bar: PixelBar
var _buttons: VBoxContainer


func setup(p_office: SalesOffice, call: Dictionary) -> void:
	office = p_office
	call_id = str(call["id"])
	var sb := UiTheme.flat(UiTheme.PARCH_LIGHT, UiTheme.TEAL, 1, 4)
	sb.border_width_left = 3
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var col := SimpleUi.vbox(3)
	add_child(col)
	_who = SimpleUi.clip("", UiTheme.COPPER.darkened(0.3), 8)
	col.add_child(_who)
	_want = SimpleUi.clip("", UiTheme.INK)
	col.add_child(_want)
	_stock = SimpleUi.clip("", UiTheme.INK_SOFT)
	col.add_child(_stock)
	_bar = SimpleUi.bar(8.0, UiTheme.TEAL)
	col.add_child(_bar)
	_buttons = SimpleUi.vbox(3)
	col.add_child(_buttons)
	refresh()


## Updates the numbers in place; rebuilds the buttons only when the choices themselves change.
## Returns false when the call is over (answered, or taken by the rep).
func refresh() -> bool:
	var call := office.find_call(call_id)
	if call.is_empty():
		return false
	var offer := office.simple_offer(call)
	if offer.is_empty():
		return false
	_who.text = "%s  (%s)" % [str(offer["customer"]).to_upper(), str(offer["mood"]).to_lower()]
	_want.text = "Wants %d x %s" % [offer["wants"], offer["product"]]
	var missing := int(offer["missing"])
	_stock.text = "In stock %d     Missing %d" % [offer["in_stock"], missing]
	_stock.add_theme_color_override("font_color", UiTheme.GREEN if missing == 0 else Color("b5651d"))
	_bar.value = clampf(float(offer["expires_in"]) / office.num("call_expiry", 150.0), 0.0, 1.0)
	_bar.text = ""
	var sig := ""
	for b: Dictionary in offer["buttons"]:
		sig += str(b["id"]) + str(b["label"]) + ","
	if sig != _sig:
		_sig = sig
		for child in _buttons.get_children():
			child.queue_free()
		for b: Dictionary in offer["buttons"]:
			var text := str(b["label"])
			if str(b["hint"]) != "":
				text += "\n" + str(b["hint"]).to_lower()
			var btn := SimpleUi.button(text, _answer.bind(str(b["id"])), bool(b["primary"]))
			if str(b["id"]) == "decline":
				btn.modulate = Color(1, 1, 1, 0.85)
			_buttons.add_child(btn)
	return true


func _answer(option: String) -> void:
	var r: Dictionary = office.answer(call_id, option)
	answered.emit(r, option)
