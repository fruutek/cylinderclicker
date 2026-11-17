class_name BoardStockPages
extends RefCounted
## The warehouse-economy pages of the Contract Board (stock mode): telephone CALLS, the STOCK room, the
## CUSTOMERS' book, the SALES REP's report, and the order cards used by the ACTIVE tab. It only reads and
## changes the simulation through the same calls the rest of the game uses, and builds each page once:
## numbers are updated in place so nothing is replaced under a finger.

const OPTION_ORDER := ["partial", "available", "delayed", "full", "decline"]

var b: ContractBoard
var company: GameSession
var sales: SalesOffice
var book: ContractBook
var factory_id := ""

var _calls := {}          # call id -> refs
var _stock := {}          # refs of the STOCK page
var _rep := {}            # refs of the SALES REP page
var _customers := {}      # customer id -> refs
var _orders := {}         # contract id -> refs (warehouse order cards on the ACTIVE tab)


func _init(board: ContractBoard) -> void:
	b = board
	company = board.company
	sales = company.sales
	book = company.contracts
	var list := factories()
	if not list.is_empty():
		factory_id = list[0].data.id


# ---------------------------------------------------------------- helpers
func factories() -> Array[FactorySim]:
	var out: Array[FactorySim] = []
	for sim in company.factories:
		if sim.state.unlocked and sim.stock_enabled():
			out.append(sim)
	return out


func factory() -> FactorySim:
	var sim := company.factory(factory_id)
	if sim == null or not sim.stock_enabled() or not sim.state.unlocked:
		var list := factories()
		if list.is_empty():
			return null
		factory_id = list[0].data.id
		return list[0]
	return sim


func _scroll_list() -> Array:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(b._inner_w, ContractBoard.HOLDER_H)
	scroll.size = Vector2(b._inner_w, ContractBoard.HOLDER_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.custom_minimum_size = Vector2(b._inner_w, 0)
	list.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(list)
	return [scroll, list]


func _factory_picker(list: VBoxContainer) -> void:
	var all := factories()
	if all.size() < 2:
		return
	var r := b._row(3)
	r.add_child(UiTheme.label("FACTORY", UiTheme.INK_SOFT))
	for sim in all:
		var btn := b._btn(sim.data.short_name.to_upper(), 90, _pick_factory.bind(sim.data.id))
		if sim.data.id == factory_id:
			b._gold_button(btn)
		r.add_child(btn)
	list.add_child(r)


func _pick_factory(id: String) -> void:
	factory_id = id
	Sfx.play("blip")
	b._signature = ""


## A button that is a fingertip wide on touch screens.
func _tbtn(text: String, width: float, action: Callable) -> Button:
	return b._btn(text, maxf(width, 40.0) if UiTheme.touch else width, action)


func _cell(text: String, width: float, color: Color = UiTheme.INK, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := b._clip(text, color)
	if width > 0.0:
		l.custom_minimum_size = Vector2(width, 0)
	else:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = align as HorizontalAlignment
	return l


func tier_color(rel: float) -> Color:
	if rel >= 80.0:
		return Color("a9760a")
	if rel >= 60.0:
		return UiTheme.GREEN
	if rel >= 40.0:
		return UiTheme.TEAL.darkened(0.15)
	if rel >= 20.0:
		return UiTheme.INK
	return UiTheme.INK_SOFT


static func _step_for(n: int) -> int:
	if n < 20:
		return 1
	if n < 100:
		return 5
	if n < 500:
		return 10
	return 50


# ------------------------------------------------------------------ CALLS
func calls_signature() -> String:
	var sig := ""
	for call in sales.calls:
		sig += str(call["id"]) + ":"
		for o: Dictionary in sales.options_for(call):
			sig += str(o["id"]).substr(0, 2)
		sig += ","
	return sig


func build_calls() -> Control:
	_calls.clear()
	if sales.calls.is_empty():
		return b._empty_note("The telephone is quiet. Customers ring when they want stock - and they ring more often when you have looked after them." if sales.unlocked
			else "Customers start telephoning once you have some cylinders on the shelves.")
	var sl := _scroll_list()
	for call in sales.calls:
		(sl[1] as VBoxContainer).add_child(_call_card(call))
	return sl[0]


func _call_card(call: Dictionary) -> Control:
	var cust := sales.find_customer(str(call["customer"]))
	var card := b._card(false, UiTheme.TEAL)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(col)
	var l1 := b._row(5)
	var who := b._clip("%s" % cust.get("name", "?"), UiTheme.COPPER.darkened(0.3))
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l1.add_child(who)
	var rel := float(cust.get("rel", 0.0))
	l1.add_child(UiTheme.label("%s  %d" % [sales.relationship_tier(rel).to_upper(), int(rel)], tier_color(rel)))
	col.add_child(l1)
	var say := b._clip("\"%s\"" % sales.call_text(call), UiTheme.INK)
	say.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(say)
	var refs := {"call": call}
	refs["info"] = b._clip("", UiTheme.INK_SOFT)
	(refs["info"] as Label).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(refs["info"])
	var bar := PixelBar.new(9.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.fill = UiTheme.TEAL
	refs["bar"] = bar
	col.add_child(bar)
	var opts := b._row(3)
	refs["buttons"] = {}
	var all: Array = sales.options_for(call)
	all.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return OPTION_ORDER.find(x["id"]) < OPTION_ORDER.find(y["id"]))
	for o: Dictionary in all:
		var btn := b._btn("", 0, _answer.bind(str(call["id"]), str(o["id"])))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, UiTheme.button_height(18) + 12)
		btn.clip_text = true
		if o["id"] == "decline":
			btn.modulate = Color(1, 1, 1, 0.85)
		elif o["id"] == "partial" or o["id"] == "full":
			b._gold_button(btn)
		opts.add_child(btn)
		refs["buttons"][o["id"]] = btn
	col.add_child(opts)
	_calls[str(call["id"])] = refs
	_update_call(refs)
	return card


func _opt_text(o: Dictionary) -> String:
	match str(o["id"]):
		"partial":
			return "PART DELIVERY\n%d now, %d later  %s" % [o["ship_now"], o["backorder"], o["verdict"]]
		"available":
			return "ONLY WHAT WE HAVE\n%d now, no more  %s" % [o["ship_now"], o["verdict"]]
		"delayed":
			return "FULL ORDER, LATER\nall in %s  %s" % [ContractBoard._time_est(float(o["eta"])), o["verdict"]]
		"full":
			return "SUPPLY IN FULL\nships now"
	return "DECLINE\nmay ring less"


func _update_call(refs: Dictionary) -> void:
	var call: Dictionary = refs["call"]
	var sim := company.factory(str(call["factory"]))
	if sim == null:
		return
	var i := sim.sku_index(str(call["sku"]))
	var avail := sim.warehouse.available(str(call["sku"]))
	var unit := sim.sku_profit(i) * float(call["factor"])
	(refs["info"] as Label).text = "%d wanted  •  %d free in stock  •  %d being made  •  pays %s each (%+d%% on list)" % [
		int(call["qty"]), avail, int(float(sim.warehouse.wip.get(str(call["sku"]), 0.0))), NumFmt.money(unit), int(roundf((float(call["factor"]) - 1.0) * 100.0))]
	var bar := refs["bar"] as PixelBar
	var cfg := sales.num("call_expiry", 150.0)
	bar.value = clampf(float(call["expires_in"]) / cfg, 0.0, 1.0)
	bar.text = "will hang up in %s" % ContractBoard._time(float(call["expires_in"]))
	for o: Dictionary in sales.options_for(call):
		var btn: Button = refs["buttons"].get(o["id"])
		if btn != null:
			btn.text = _opt_text(o)


func _answer(call_id: String, option: String) -> void:
	var r: Dictionary = sales.answer(call_id, option)
	b._say(str(r.get("text", "")), UiTheme.GREEN if bool(r.get("accepted", false)) else (UiTheme.INK if option == "decline" else Color("c47a00")), 7.0)
	Sfx.play("ding" if bool(r.get("accepted", false)) else ("blip" if option == "decline" else "deny"))
	b._signature = ""


# ------------------------------------------------------------------ STOCK
func stock_signature() -> String:
	var sim := factory()
	if sim == null:
		return "none"
	var sig := "%s|%d|" % [sim.data.id, factories().size()]
	for i in sim.skus.size():
		sig += "1" if sim.sku_available(i) else "0"
	return sig


func build_stock() -> Control:
	_stock = {}
	var sim := factory()
	if sim == null:
		return b._empty_note("Your factory is not keeping stock yet.")
	var sl := _scroll_list()
	var list: VBoxContainer = sl[1]
	_factory_picker(list)
	# capacity and controls
	var head := b._card(false, UiTheme.WOOD_DARK)
	var hc := VBoxContainer.new()
	hc.add_theme_constant_override("separation", 3)
	hc.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(hc)
	var bar := PixelBar.new(12.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.fill = UiTheme.TEAL
	bar.segments = 0
	_stock["bar"] = bar
	hc.add_child(bar)
	var ctl := b._row(3)
	_stock["auto"] = b._btn("", 0, _toggle.bind("auto_production"))
	_stock["targets"] = b._btn("", 0, _toggle.bind("auto_targets"))
	_stock["wholesale"] = b._btn("", 0, _toggle.bind("wholesale_on"))
	for key: String in ["auto", "targets", "wholesale"]:
		(_stock[key] as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ctl.add_child(_stock[key])
	hc.add_child(ctl)
	var act := b._row(3)
	_stock["sell"] = b._btn("SELL SURPLUS NOW", 0, _sell_now)
	_stock["space"] = b._btn("", 0, _buy_space)
	for key: String in ["sell", "space"]:
		(_stock[key] as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		act.add_child(_stock[key])
	hc.add_child(act)
	list.add_child(head)
	# the table
	var hdr := b._row(4)
	for pair: Array in [["PRODUCT", 0], ["FREE", 38], ["HELD", 38], ["TOTAL", 40], ["MAKING", 46], ["OWED", 38], ["DEMAND/m", 52], ["TARGET", 112 if not UiTheme.touch else 150], ["", 26 if not UiTheme.touch else 40]]:
		hdr.add_child(_cell(pair[0], float(pair[1]), UiTheme.INK_SOFT, HORIZONTAL_ALIGNMENT_RIGHT if pair[0] != "PRODUCT" and pair[0] != "" else HORIZONTAL_ALIGNMENT_LEFT))
	list.add_child(hdr)
	_stock["rows"] = []
	for i in sim.skus.size():
		list.add_child(_stock_row(sim, i))
	var note := UiTheme.label("TARGET = what the line keeps on the shelves. Customers waiting always come first. Star = build this next.", UiTheme.INK_SOFT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(b._inner_w - 8, 0)
	list.add_child(note)
	_update_stock()
	return sl[0]


func _stock_row(sim: FactorySim, i: int) -> Control:
	var card := b._card(false, UiTheme.PARCH_DARK)
	var r := b._row(4)
	card.add_child(r)
	var refs := {"i": i}
	refs["name"] = _cell("", 0.0)
	r.add_child(refs["name"])
	for key: String in ["free", "held", "total", "making", "owed", "demand"]:
		var w := 38.0 if key != "making" and key != "total" else (46.0 if key == "making" else 40.0)
		if key == "demand":
			w = 52.0
		refs[key] = _cell("", w, UiTheme.INK, HORIZONTAL_ALIGNMENT_RIGHT)
		r.add_child(refs[key])
	var tr := b._row(2)
	tr.custom_minimum_size = Vector2(112 if not UiTheme.touch else 150, 0)
	refs["minus"] = _tbtn("-", 28, _target.bind(i, -1))
	refs["value"] = _cell("", 40.0, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER)
	refs["plus"] = _tbtn("+", 28, _target.bind(i, 1))
	tr.add_child(refs["minus"])
	tr.add_child(refs["value"])
	tr.add_child(refs["plus"])
	r.add_child(tr)
	refs["star"] = _tbtn("*", 26, _prioritise.bind(i))
	r.add_child(refs["star"])
	(_stock["rows"] as Array).append(refs)
	return card


func _update_stock() -> void:
	var sim := factory()
	if sim == null or _stock.is_empty():
		return
	var w := sim.warehouse
	var bar := _stock["bar"] as PixelBar
	bar.value = w.usage_fraction()
	bar.fill = UiTheme.RED if w.usage_fraction() >= 0.95 else (Color("c47a00") if w.usage_fraction() >= 0.8 else UiTheme.TEAL)
	var held := 0
	for s in sim.skus:
		held += w.reserved_units(str(s["id"]))
	bar.text = "WAREHOUSE  %d / %d  (%d%% full, %d reserved for customers)" % [w.total_units(), w.capacity, int(w.usage_fraction() * 100.0), held]
	_set_toggle(_stock["auto"], "AUTO-PRODUCE", sim.state.auto_production)
	_set_toggle(_stock["targets"], "AUTO TARGETS", sim.auto_targets_active())
	_set_toggle(_stock["wholesale"], "WHOLESALE SURPLUS", sim.state.wholesale_on)
	var sell := _stock["sell"] as Button
	var surplus := 0
	for i in sim.skus.size():
		surplus += maxi(w.available(sim.sku_id(i)) - sim.effective_target(i), 0)
	sell.text = "SELL SURPLUS NOW (%d)" % surplus
	sell.disabled = surplus <= 0
	sell.modulate = Color(1, 1, 1, 0.5) if sell.disabled else Color.WHITE
	var space := _stock["space"] as Button
	space.text = "MORE SPACE  %s  (+%d)" % [NumFmt.money(sim.cost("warehouse")), int(roundf(float(w.capacity) * 0.75))]
	space.disabled = not sim.can_afford("warehouse")
	space.modulate = Color(1, 1, 1, 0.5) if space.disabled else Color.WHITE
	var first_prio: String = sim.state.priority[0] if not sim.state.priority.is_empty() else ""
	var per_min := {}
	for fr: Dictionary in sales.forecast(sim, false):
		per_min[fr["sku"]] = float(fr["per_min"])
	for refs: Dictionary in _stock["rows"]:
		var i: int = refs["i"]
		var id := sim.sku_id(i)
		var avail := sim.sku_available(i)
		var name_l := refs["name"] as Label
		name_l.text = String(sim.skus[i]["name"]) if avail else "%s  (%s)" % [sim.skus[i]["short"], sim.sku_requirement_text(i)]
		name_l.add_theme_color_override("font_color", UiTheme.INK if avail else UiTheme.INK_SOFT)
		(refs["free"] as Label).text = str(w.available(id)) if avail else "-"
		(refs["held"] as Label).text = str(w.reserved_units(id)) if avail else "-"
		(refs["total"] as Label).text = str(w.total(id)) if avail else "-"
		(refs["making"] as Label).text = str(int(roundf(float(w.wip.get(id, 0.0))))) if avail else "-"
		(refs["demand"] as Label).text = NumFmt.number(float(per_min.get(id, 0.0)), 1) if avail else "-"
		var owed := sim.backlog(i)
		(refs["owed"] as Label).text = str(int(roundf(owed))) if avail else "-"
		(refs["owed"] as Label).add_theme_color_override("font_color", UiTheme.RED if owed > 0.5 else UiTheme.INK)
		var auto_t := sim.auto_targets_active()
		(refs["value"] as Label).text = str(sim.effective_target(i)) if avail else "-"
		for key: String in ["minus", "plus", "star"]:
			var btn := refs[key] as Button
			btn.disabled = not avail or (auto_t and key != "star")
			if key != "star":
				btn.modulate = Color(1, 1, 1, 0.4) if btn.disabled else Color.WHITE
		(refs["star"] as Button).modulate = Color("f2c14e") if id == first_prio else Color.WHITE


func _set_toggle(btn: Button, label: String, on: bool) -> void:
	btn.text = "%s: %s" % [label, "ON" if on else "OFF"]
	btn.modulate = Color.WHITE if on else Color(1, 1, 1, 0.7)


func _toggle(key: String) -> void:
	var sim := factory()
	if sim == null:
		return
	match key:
		"auto_production":
			sim.state.auto_production = not sim.state.auto_production
		"auto_targets":
			sim.state.auto_targets = not sim.state.auto_targets
			if sim.state.auto_targets:
				b._say("Targets now follow your sales rep's recommendation (the better the rep, the better the stock levels).", UiTheme.INK_SOFT, 6.0)
		"wholesale_on":
			sim.state.wholesale_on = not sim.state.wholesale_on
			if not sim.state.wholesale_on:
				b._say("Wholesale off: when the shelves are full the line simply stops. Nothing is ever thrown away.", UiTheme.INK_SOFT, 6.0)
	sim.planner_wake()
	Sfx.play("blip")
	_update_stock()


func _sell_now() -> void:
	var sim := factory()
	if sim == null:
		return
	var earned := sim.sell_surplus_now()
	Sfx.play("sale")
	b._say("The wholesaler took the surplus for %s (about 85%% of normal profit)." % NumFmt.money(earned), UiTheme.GREEN)
	_update_stock()


func _buy_space() -> void:
	var sim := factory()
	if sim != null and sim.buy("warehouse"):
		Sfx.play("buy")
		b._say("Warehouse extended: room for %d cylinders." % sim.warehouse.capacity, UiTheme.GREEN)
	else:
		Sfx.play("deny")
	_update_stock()


func _target(i: int, dir: int) -> void:
	var sim := factory()
	if sim == null:
		return
	var id := sim.sku_id(i)
	var cur := int(sim.state.targets.get(id, 0))
	var step := _step_for(cur if dir > 0 else maxi(cur - 1, 0))
	sim.set_target(id, maxi(cur + dir * step, 0))
	Sfx.play("blip")
	_update_stock()


func _prioritise(i: int) -> void:
	var sim := factory()
	if sim == null:
		return
	sim.prioritise(sim.sku_id(i))
	Sfx.play("blip")
	b._say("%s will be built first when several products are short." % sim.skus[i]["name"], UiTheme.INK_SOFT)
	_update_stock()


# -------------------------------------------------------------- CUSTOMERS
func customers_signature() -> String:
	return "%d|%s" % [sales.customers.size(), str(sales.unlocked)]


func build_customers() -> Control:
	_customers.clear()
	if sales.customers.is_empty():
		return b._empty_note("Your customers will be listed here, with how they feel about you, once the telephone starts ringing.")
	var sl := _scroll_list()
	var list: VBoxContainer = sl[1]
	var sorted: Array = sales.customers.duplicate()
	sorted.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["rel"]) > float(y["rel"]))
	for cust: Dictionary in sorted:
		list.add_child(_customer_card(cust))
	return sl[0]


func _customer_card(cust: Dictionary) -> Control:
	var card := b._card(false, UiTheme.PARCH_DARK)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(col)
	var refs := {}
	var l1 := b._row(5)
	refs["name"] = _cell(str(cust["name"]), 0.0, UiTheme.COPPER.darkened(0.3))
	l1.add_child(refs["name"])
	l1.add_child(UiTheme.label(str(cust["label"]), UiTheme.INK_SOFT))
	refs["tier"] = UiTheme.label("", UiTheme.INK)
	refs["tier"].custom_minimum_size = Vector2(64, 0)
	l1.add_child(refs["tier"])
	var bar := PixelBar.new(9.0)
	bar.custom_minimum_size = Vector2(110, 9)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	refs["bar"] = bar
	l1.add_child(bar)
	col.add_child(l1)
	refs["info"] = _cell("", 0.0, UiTheme.INK_SOFT)
	col.add_child(refs["info"])
	refs["likes"] = _cell("", 0.0, UiTheme.INK_SOFT)
	col.add_child(refs["likes"])
	_customers[str(cust["id"])] = refs
	_update_customer(str(cust["id"]), refs)
	return card


func _update_customer(id: String, refs: Dictionary) -> void:
	var cust := sales.find_customer(id)
	if cust.is_empty():
		return
	var rel := float(cust["rel"])
	var tier := sales.relationship_tier(rel)
	var state := ""
	if float(cust["dormant_until"]) > sales.clock:
		state = "  •  NOT CALLING (turned away too often)"
	var tl := refs["tier"] as Label
	tl.text = tier.to_upper()
	tl.add_theme_color_override("font_color", tier_color(rel))
	var bar := refs["bar"] as PixelBar
	bar.value = rel / 100.0
	bar.fill = tier_color(rel) if rel >= 20.0 else Color("8a6a52")
	bar.text = "%d" % int(rel)
	(refs["info"] as Label).text = "%d orders done  •  spent %s  •  usually %d cylinders  •  ceiling %d for now%s" % [
		int(cust["completed"]), NumFmt.money(float(cust["spent"])), maxi(int(roundf(float(cust["size"]) * 12.0)), 2), int(sales.relationship_cap(cust)), state]
	var prefs: Dictionary = cust["prefer"]
	var fam: Array = prefs.keys()
	fam.sort_custom(func(x: String, y: String) -> bool: return float(prefs[x]) > float(prefs[y]))
	var likes := "Likes %s" % ", ".join(PackedStringArray(fam.slice(0, 2)))
	var hist: Array = cust["history"]
	if not hist.is_empty():
		var h: Dictionary = hist[0]
		likes += "  •  last: %d × %s (%s)" % [int(h["qty"]), str(h["sku"]), str(h["outcome"]).replace("_", " ")]
	likes += "  •  patience %d min  •  %s" % [int(roundf(float(cust["patience"]))), "picky about price" if float(cust["price_sens"]) > 0.6 else "pays for trust"]
	(refs["likes"] as Label).text = likes


# -------------------------------------------------------------- SALES REP
func rep_signature() -> String:
	var sim := factory()
	if sim == null:
		return "none"
	var sig := "%s|" % sim.data.id
	for i in sim.skus.size():
		sig += "1" if sim.sku_available(i) else "0"
	return sig


func build_rep() -> Control:
	_rep = {}
	var sim := factory()
	if sim == null:
		return b._empty_note("The sales rep joins once your factory keeps stock.")
	var sl := _scroll_list()
	var list: VBoxContainer = sl[1]
	_factory_picker(list)
	var head := b._card(false, UiTheme.WOOD_DARK)
	var hc := VBoxContainer.new()
	hc.add_theme_constant_override("separation", 3)
	hc.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(hc)
	var q := b._row(4)
	_rep["quality"] = _cell("", 0.0, UiTheme.INK)
	q.add_child(_rep["quality"])
	_rep["train"] = b._btn("", 150, _buy_training)
	q.add_child(_rep["train"])
	_rep["apply"] = b._btn("APPLY RECOMMENDED STOCK", 150, _apply_recommended)
	b._gold_button(_rep["apply"])
	q.add_child(_rep["apply"])
	hc.add_child(q)
	_rep["summary"] = _cell("", 0.0, UiTheme.INK_SOFT)
	hc.add_child(_rep["summary"])
	list.add_child(head)
	var hdr := b._row(4)
	for pair: Array in [["PRODUCT", 0], ["LIKELY SHARE", 100], ["PER MIN", 46], ["BEST STOCK", 66], ["IN STOCK", 56], ["SHORT", 44], ["LOST", 40]]:
		hdr.add_child(_cell(pair[0], float(pair[1]), UiTheme.INK_SOFT, HORIZONTAL_ALIGNMENT_LEFT if pair[0] == "PRODUCT" else HORIZONTAL_ALIGNMENT_RIGHT))
	list.add_child(hdr)
	_rep["rows"] = {}
	for i in sim.skus.size():
		if sim.sku_available(i):
			list.add_child(_rep_row(sim.sku_id(i)))
	var note := UiTheme.label("Shares are the chance a call asks for each product: odds, not a promise. Training the rep makes them follow what customers really ask for.", UiTheme.INK_SOFT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(b._inner_w - 8, 0)
	list.add_child(note)
	_update_rep()
	return sl[0]


func _rep_row(sku: String) -> Control:
	var card := b._card(false, UiTheme.PARCH_DARK)
	var r := b._row(4)
	card.add_child(r)
	var refs := {}
	refs["name"] = _cell("", 0.0)
	r.add_child(refs["name"])
	var bar := PixelBar.new(10.0)
	bar.custom_minimum_size = Vector2(100, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.fill = UiTheme.COPPER
	refs["bar"] = bar
	r.add_child(bar)
	for pair: Array in [["per", 46], ["rec", 66], ["stock", 56], ["short", 44], ["lost", 40]]:
		refs[pair[0]] = _cell("", float(pair[1]), UiTheme.INK, HORIZONTAL_ALIGNMENT_RIGHT)
		r.add_child(refs[pair[0]])
	_rep["rows"][sku] = refs
	return card


func _update_rep() -> void:
	var sim := factory()
	if sim == null or _rep.is_empty():
		return
	var quality := sales.forecast_quality(sim)
	(_rep["quality"] as Label).text = "SALES REP   forecast quality %d%%   %s" % [int(roundf(quality * 100.0)), "guessing" if quality < 0.4 else ("learning" if quality < 0.7 else "sharp")]
	var train := _rep["train"] as Button
	if sim.data.upgrade_by_id.has("sales_rep"):
		train.visible = true
		if sim.is_maxed("sales_rep"):
			train.text = "FULLY TRAINED"
			train.disabled = true
		else:
			train.text = "TRAIN  %s" % NumFmt.money(sim.cost("sales_rep"))
			train.disabled = not sim.can_afford("sales_rep")
	var rows: Array = sales.forecast(sim)
	var shown_lost := 0.0
	var best_name := ""
	var best_share := 0.0
	var shortfalls := 0
	var dead: Array[String] = []
	for r: Dictionary in rows:
		var refs: Dictionary = _rep["rows"].get(r["sku"], {})
		if refs.is_empty():
			continue
		(refs["name"] as Label).text = str(r["name"])
		(refs["bar"] as PixelBar).value = float(r["share"])
		(refs["bar"] as PixelBar).text = "%d%%" % int(roundf(float(r["share"]) * 100.0))
		(refs["per"] as Label).text = NumFmt.number(float(r["per_min"]), 1)
		(refs["rec"] as Label).text = str(r["recommended"])
		(refs["stock"] as Label).text = str(r["stock"])
		(refs["short"] as Label).text = str(r["shortfall"]) if int(r["shortfall"]) > 0 else "-"
		(refs["short"] as Label).add_theme_color_override("font_color", UiTheme.RED if int(r["shortfall"]) > 0 else UiTheme.INK)
		(refs["lost"] as Label).text = str(int(roundf(float(r["lost"])))) if float(r["lost"]) > 0.4 else "-"
		(refs["name"] as Label).add_theme_color_override("font_color", Color("a9760a") if bool(r["dead"]) else UiTheme.INK)
		shown_lost += float(r["lost"])
		shortfalls += int(r["shortfall"])
		if float(r["share"]) > best_share:
			best_share = float(r["share"])
			best_name = str(r["name"])
		if bool(r["dead"]):
			dead.append(str(r["short"]))
	var s := "Most requested: %s (%d%%)  •  Expected shortfall: %d cylinders  •  Lost sales so far: %d" % [best_name, int(roundf(best_share * 100.0)), shortfalls, int(roundf(shown_lost))]
	if not dead.is_empty():
		s += "  •  Not selling: %s" % ", ".join(PackedStringArray(dead))
	(_rep["summary"] as Label).text = s


func _buy_training() -> void:
	var sim := factory()
	if sim != null and sim.buy("sales_rep"):
		Sfx.play("buy")
		b._say("Your sales rep has been on a course: forecasts are sharper.", UiTheme.GREEN)
	else:
		Sfx.play("deny")
	_update_rep()


func _apply_recommended() -> void:
	var sim := factory()
	if sim == null:
		return
	for r: Dictionary in sales.forecast(sim, false):
		sim.set_target(str(r["sku"]), int(r["recommended"]))
	sim.state.auto_targets = false
	Sfx.play("buy")
	b._say("Stock targets set to the sales rep's recommendations. Raise or lower any of them on the STOCK tab.", UiTheme.GREEN, 6.0)
	_update_rep()


# ----------------------------------------------------- ACTIVE order cards
func active_card(c: Contract) -> Control:
	var is_call := c.is_call()
	var card := b._card(c.premium, UiTheme.TEAL if is_call else b._tier_color(c))
	var row := b._row(6)
	card.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 2)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(left)
	var refs := {"contract": c, "stock": true}
	var l1 := b._row(5)
	var who := b._clip(c.customer, UiTheme.COPPER.darkened(0.3))
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l1.add_child(who)
	l1.add_child(UiTheme.label("PHONE ORDER" if is_call else b._tier_tag(c), UiTheme.TEAL.darkened(0.15) if is_call else b._tier_color(c)))
	refs["pays"] = UiTheme.label("", UiTheme.GREEN)
	l1.add_child(refs["pays"])
	left.add_child(l1)
	var l2 := b._row(5)
	refs["qty"] = UiTheme.label("", UiTheme.INK)
	l2.add_child(refs["qty"])
	l2.add_child(b._spacer())
	refs["bonus"] = UiTheme.label("", ContractBoard.GOLD_DARK)
	l2.add_child(refs["bonus"])
	left.add_child(l2)
	var bar := PixelBar.new(12.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.segments = c.pallets
	refs["bar"] = bar
	left.add_child(bar)
	refs["note"] = b._clip("", UiTheme.INK_SOFT)
	(refs["note"] as Label).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(refs["note"])
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	right.custom_minimum_size = Vector2(118, 0)
	right.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(right)
	refs["time"] = UiTheme.label("", UiTheme.INK)
	(refs["time"] as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(refs["time"])
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	if not is_call:
		var go := b._btn("SHIP NOW", 0, _ship.bind(c.id))
		go.custom_minimum_size = Vector2(0, UiTheme.button_height(18) + 6)
		b._gold_button(go)
		refs["ship"] = go
		right.add_child(go)
		if c.status == Contract.Status.ACTIVE:
			right.add_child(b._btn("Give up", 0, b._on_abandon.bind(c.id)))
	_orders[c.id] = refs
	update_order(refs)
	return card


func update_all_orders() -> void:
	for id: String in _orders:
		update_order(_orders[id])


func update_order(refs: Dictionary) -> void:
	var c: Contract = refs["contract"]
	var sim := company.factory(c.factory)
	(refs["qty"] as Label).text = "shipped %d  •  ready %d  •  owed %d  of %d × %s" % [int(c.shipped), int(c.held), int(c.remaining()), c.quantity, ContractBoard._short_product(c.product_name)]
	(refs["pays"] as Label).text = "Pays " + NumFmt.money(float(c.quantity) * book.unit_net(c)) if book.port != null else ""
	var bar := refs["bar"] as PixelBar
	bar.value = clampf((c.shipped + c.held) / float(maxi(c.quantity, 1)), 0.0, 1.0)
	bar.fill = UiTheme.COPPER if c.shipped + c.held < float(c.quantity) else UiTheme.GREEN
	var eta_text := ""
	var late := false
	if c.status == Contract.Status.DISPATCHING:
		eta_text = "lorry loading"
		bar.fill = UiTheme.TEAL
	elif c.remaining() > ContractBook.EPS and sim != null:
		var i := sim.sku_index(c.sku)
		var rate := sim.sku_rate_per_min(i) / 60.0
		var secs := sim.owed_work() / maxf(sim.planning_rate(1.5, 0.85), 0.0001)
		eta_text = "rest in about %s" % ContractBoard._time_est(secs)
		late = c.has_deadline() and secs > c.time_left
		if rate <= 0.0 or not sim.sku_available(i):
			eta_text = "cannot be made yet"
	else:
		eta_text = "complete - ready to go"
	bar.text = "%d%%   %s" % [int((c.shipped + c.held) / float(maxi(c.quantity, 1)) * 100.0), eta_text]
	bar.text_color = Color("ffb0a0") if late else Color.WHITE
	(refs["bonus"] as Label).text = ("Bonus %s if complete in %s" % [NumFmt.money(book.bonus_quote(c)), ContractBoard._time(maxf(c.bonus_by - c.elapsed, 0.0))]) if (c.bonus > 0.0 and c.bonus_by > c.elapsed and not c.built) else ""
	var time := refs["time"] as Label
	if c.is_call():
		if c.has_deadline():
			time.text = ("promised in " + ContractBoard._time(c.time_left)) if c.time_left >= 0.0 else "LATE  (they will wait %s more)" % ContractBoard._time(c.time_left + c.patience)
			time.add_theme_color_override("font_color", UiTheme.RED if c.time_left < 0.0 else UiTheme.INK)
		else:
			time.text = ""
		var mode_text := {"partial": "Next lorry when a quarter is ready or all of it is.", "delayed": "Ships in one lorry when complete.", "full": "Ships as soon as the bay is free."}
		(refs["note"] as Label).text = str(mode_text.get(c.mode, ""))
	else:
		time.text = ("%s left" % ContractBoard._time(c.time_left)) if (c.has_deadline() and c.status == Contract.Status.ACTIVE) else ""
		time.add_theme_color_override("font_color", UiTheme.INK)
		(refs["note"] as Label).text = "Send what is ready any time: you are paid for each lorry. A complete order earns the bonus and reputation."
	var go := refs.get("ship") as Button
	if go != null:
		go.visible = c.status != Contract.Status.DISPATCHING
		go.text = "SHIP %d NOW" % int(c.held) if c.held > 0.0 else "NOTHING READY"
		go.disabled = c.held <= 0.0


func _ship(id: String) -> void:
	var problem := book.dispatch(id)
	if problem != "":
		b._say(problem, UiTheme.RED)
		Sfx.play("deny")
		return
	Sfx.play("engine", 0.0, -4.0)
	b.dispatched.emit(id)
	b.close()


# ------------------------------------------------------------------- live
func update_calls() -> void:
	for id: String in _calls:
		_update_call(_calls[id])


func update_customers() -> void:
	for id: String in _customers:
		_update_customer(id, _customers[id])
