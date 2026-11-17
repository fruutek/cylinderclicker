class_name OrdersScreen
extends ScreenFrame
## ORDERS: customers on the phone (answer with one tap), the orders in progress with a progress bar each, and
## big orders you can accept. Lorries, reservations and production are automatic.

signal order_answered(result: Dictionary, option: String)

var _calls := {}         # call id -> CallCard
var _open := {}          # contract id -> refs


func _init(p_company: GameSession) -> void:
	super(p_company, "orders")


func _signature() -> String:
	var s := ""
	for call in company.sales.calls:
		s += str(call["id"]) + ","
	s += "|"
	for c in company.contracts.active:
		s += "%s:%d," % [c.id, c.status]
	s += "|"
	for o in company.contracts.offers:
		s += o.id + ","
	return s


func _build() -> void:
	_calls.clear()
	_open.clear()
	var sales := company.sales
	var book := company.contracts
	for call in sales.calls:
		var card := CallCard.new()
		card.setup(sales, call)
		card.answered.connect(_on_answered)
		_list.add_child(card)
		_calls[str(call["id"])] = card
	if not book.active.is_empty():
		section("IN PROGRESS")
		for c in book.active:
			_list.add_child(_order_card(c))
	if not book.offers.is_empty():
		section("BIG ORDERS")
		for o in book.offers:
			_list.add_child(_offer_card(o))
	if sales.calls.is_empty() and book.active.is_empty() and book.offers.is_empty():
		note("No orders right now. Customers ring when you have stock to talk about - keep the shelves filled and the phone will go.")
	details_button("history")


func _on_answered(result: Dictionary, option: String) -> void:
	order_answered.emit(result, option)
	say(str(result.get("text", "")), UiTheme.GREEN if bool(result.get("accepted", false)) else UiTheme.INK, 5.0)
	_sig = "?"


func _order_card(c: Contract) -> Control:
	var card := SimpleUi.card(UiTheme.TEAL if c.is_call() else UiTheme.COPPER)
	var col := SimpleUi.vbox(2)
	card.add_child(col)
	var top := SimpleUi.hbox(4)
	var who := SimpleUi.clip(c.customer, UiTheme.COPPER.darkened(0.3))
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(who)
	var status := UiTheme.label("", UiTheme.INK)
	top.add_child(status)
	col.add_child(top)
	var what := SimpleUi.clip("%d x %s" % [c.quantity, c.product_name], UiTheme.INK)
	col.add_child(what)
	var bar := SimpleUi.bar(12.0)
	col.add_child(bar)
	_open[c.id] = {"contract": c, "status": status, "bar": bar}
	return card


func _offer_card(o: Contract) -> Control:
	var card := SimpleUi.card(UiTheme.WOOD_DARK)
	var row := SimpleUi.hbox(6)
	card.add_child(row)
	var col := SimpleUi.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(SimpleUi.clip(o.customer, UiTheme.COPPER.darkened(0.3)))
	col.add_child(SimpleUi.clip("%d x %s" % [o.quantity, o.product_name], UiTheme.INK))
	var pays := "Pays %s" % NumFmt.money(company.contracts.quote(o))
	if o.has_deadline():
		pays += "   in %s" % SalesOffice.short_time(o.deadline)
	col.add_child(SimpleUi.clip(pays, UiTheme.GREEN))
	var accept := SimpleUi.button("ACCEPT", _accept.bind(o.id), true, 96.0)
	row.add_child(accept)
	return card


func _accept(id: String) -> void:
	var problem := company.contracts.accept(id)
	if problem != "":
		Sfx.play("deny")
		say(problem, UiTheme.RED, 5.0)
		return
	Sfx.play("stamp")
	say("Accepted! Anything on the shelves is put aside; the line builds the rest and the lorry goes by itself.", UiTheme.GREEN, 5.0)
	_sig = "?"


func _update() -> void:
	for id: String in _calls:
		var card: CallCard = _calls[id]
		if is_instance_valid(card):
			card.refresh()
	for id: String in _open:
		var refs: Dictionary = _open[id]
		var c: Contract = refs["contract"]
		var bar := refs["bar"] as PixelBar
		bar.value = clampf((c.shipped + c.held) / float(maxi(c.quantity, 1)), 0.0, 1.0)
		bar.text = "%d sent   %d ready   %d to make" % [int(c.shipped), int(c.held), int(ceilf(c.remaining()))]
		bar.fill = UiTheme.TEAL if c.status == Contract.Status.DISPATCHING else UiTheme.COPPER
		var st := refs["status"] as Label
		if c.status == Contract.Status.DISPATCHING:
			st.text = "LORRY LOADING"
			st.add_theme_color_override("font_color", UiTheme.TEAL.darkened(0.2))
		elif c.is_call() and c.late:
			st.text = "LATE!"
			st.add_theme_color_override("font_color", UiTheme.RED)
		elif c.remaining() > ContractBook.EPS:
			st.text = "making the rest"
			st.add_theme_color_override("font_color", UiTheme.INK_SOFT)
		else:
			st.text = "ready to go"
			st.add_theme_color_override("font_color", UiTheme.GREEN)
