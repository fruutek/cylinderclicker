class_name StockScreen
extends ScreenFrame
## STOCK: how full the warehouse is, what is on the shelves (product icons and quantities), AUTO STOCK or
## MANUAL, and the sales rep's advice with one-tap actions. No tables.

var _tiles := {}       # sku id -> refs
var _refs := {}


func _init(p_company: GameSession) -> void:
	super(p_company, "stock")


func _signature() -> String:
	var f := sim()
	if f == null or not f.stock_enabled():
		return "none"
	var s := "%s|%d|%s|" % [f.data.id, stock_factories().size(), str(f.auto_targets_active())]
	for i in f.skus.size():
		s += "1" if f.sku_available(i) else "0"
	for a: Dictionary in company.sales.advice(f):
		s += "|" + str(a["action"]) + str(a["sku"])
	return s


func _build() -> void:
	_tiles.clear()
	_refs = {}
	var f := sim()
	if f == null or not f.stock_enabled():
		note("Your factory is not keeping stock yet.")
		return
	factory_picker()
	# capacity + mode
	var top := SimpleUi.card()
	var col := SimpleUi.vbox(4)
	top.add_child(col)
	_refs["bar"] = SimpleUi.bar(16.0, UiTheme.TEAL)
	col.add_child(_refs["bar"])
	var seg := SimpleUi.hbox(3)
	_refs["auto"] = SimpleUi.button("AUTO STOCK", _set_mode.bind(true))
	_refs["manual"] = SimpleUi.button("MANUAL", _set_mode.bind(false))
	for k: String in ["auto", "manual"]:
		(_refs[k] as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.add_child(_refs[k])
	col.add_child(seg)
	_refs["mode_note"] = SimpleUi.clip("", UiTheme.INK_SOFT)
	col.add_child(_refs["mode_note"])
	_list.add_child(top)
	_list.add_child(_advisor(f))
	# tiles
	var grid := GridContainer.new()
	grid.columns = 3 if _inner_w >= 560 else 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	var tile_w := (_inner_w - 12 - 4 * (grid.columns - 1)) / grid.columns
	for i in f.skus.size():
		grid.add_child(_tile(f, i, tile_w))
	_list.add_child(grid)
	details_button("stock")


func _tile(f: FactorySim, i: int, w: int) -> Control:
	var id := f.sku_id(i)
	var avail := f.sku_available(i)
	var card := SimpleUi.card(UiTheme.WOOD_DARK if avail else UiTheme.PARCH_DARK, UiTheme.PARCH_LIGHT if avail else UiTheme.PARCH)
	card.custom_minimum_size = Vector2(w, 0)
	var col := SimpleUi.vbox(2)
	card.add_child(col)
	var refs := {"i": i}
	var head := SimpleUi.hbox(4)
	refs["icon"] = SimpleUi.product_icon(i, 0 if avail else 0)
	head.add_child(refs["icon"])
	var name_l := SimpleUi.clip(String(f.skus[i].get("short", f.skus[i]["name"])), UiTheme.INK if avail else UiTheme.INK_SOFT)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_l)
	col.add_child(head)
	if not avail:
		col.add_child(SimpleUi.clip(f.sku_requirement_text(i).replace("Needs: ", "Needs "), UiTheme.INK_SOFT))
		_tiles[id] = refs
		return card
	refs["qty"] = UiTheme.label("", UiTheme.INK, 16)
	col.add_child(refs["qty"])
	refs["sub"] = SimpleUi.clip("", UiTheme.INK_SOFT)
	col.add_child(refs["sub"])
	var tr := SimpleUi.hbox(2)
	refs["target_row"] = tr
	refs["minus"] = SimpleUi.button("-", _target.bind(i, -1), false, 34.0)
	refs["value"] = SimpleUi.clip("", UiTheme.INK)
	refs["value"].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	refs["value"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refs["plus"] = SimpleUi.button("+", _target.bind(i, 1), false, 34.0)
	tr.add_child(refs["minus"])
	tr.add_child(refs["value"])
	tr.add_child(refs["plus"])
	col.add_child(tr)
	_tiles[id] = refs
	return card


func _advisor(f: FactorySim) -> Control:
	var card := SimpleUi.card(UiTheme.COPPER)
	var col := SimpleUi.vbox(4)
	card.add_child(col)
	col.add_child(UiTheme.label("YOUR SALES REP SAYS", UiTheme.COPPER.darkened(0.3)))
	for a: Dictionary in company.sales.advice(f):
		var l := UiTheme.label("\"%s\"" % a["text"], UiTheme.INK)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(_inner_w - 40, 0)
		col.add_child(l)
		if str(a["action"]) != "":
			col.add_child(SimpleUi.button(str(a["label"]), _do_advice.bind(a), true))
	return card


func _do_advice(item: Dictionary) -> void:
	var f := sim()
	var msg := company.sales.do_advice(f, item)
	Sfx.play("buy" if msg != "" else "deny")
	if msg != "":
		say(msg, UiTheme.GREEN)
	_sig = "?"


func _set_mode(auto: bool) -> void:
	var f := sim()
	if f == null or f.state.auto_targets == auto:
		return
	if not auto:
		for i in f.skus.size():                      # start MANUAL from what the rep recommends, not from stale numbers
			f.state.targets[f.sku_id(i)] = f.effective_target(i)
	f.state.auto_targets = auto
	f.planner_wake()
	Sfx.play("blip")
	_sig = "?"


func _target(i: int, dir: int) -> void:
	var f := sim()
	if f == null:
		return
	var id := f.sku_id(i)
	var cur := int(f.state.targets.get(id, 0))
	var step := 1 if cur < 20 else (5 if cur < 100 else (10 if cur < 500 else 50))
	f.set_target(id, maxi(cur + dir * step, 0))
	Sfx.play("blip")


func _update() -> void:
	var f := sim()
	if f == null or _refs.is_empty():
		return
	var w := f.warehouse
	var bar := _refs["bar"] as PixelBar
	bar.value = w.usage_fraction()
	bar.fill = SimpleUi.usage_color(w.usage_fraction())
	bar.text = "WAREHOUSE  %d / %d" % [w.total_units(), w.capacity]
	var auto := f.auto_targets_active()
	for pair: Array in [["auto", auto], ["manual", not auto]]:
		var b := _refs[pair[0]] as Button
		if pair[1]:
			SimpleUi.gold(b)
		else:
			for st: String in ["normal", "hover", "pressed"]:
				b.remove_theme_stylebox_override(st)
			b.remove_theme_color_override("font_color")
	(_refs["auto"] as Button).text = "AUTO STOCK  (recommended)" if _inner_w >= 480 else "AUTO STOCK"
	(_refs["mode_note"] as Label).text = "The sales rep keeps the shelves stocked for you." if auto else "You choose how many of each to keep. Tap + and -."
	for id: String in _tiles:
		var r: Dictionary = _tiles[id]
		if not r.has("qty"):
			continue
		var i: int = r["i"]
		var total := w.total(id)
		var target := f.effective_target(i)
		(r["qty"] as Label).text = str(total)
		var held := w.reserved_units(id)
		var making := int(roundf(float(w.wip.get(id, 0.0))))
		var sub := ""
		if held > 0:
			sub += "%d for customers  " % held
		if making > 0:
			sub += "making %d" % making
		(r["sub"] as Label).text = sub if sub != "" else "keeping %d" % target
		SimpleUi.set_icon_boxes(r["icon"], int(ceilf(6.0 * float(total) / maxf(float(target), 1.0))) if total > 0 else 0)
		(r["target_row"] as Control).visible = not auto
		(r["value"] as Label).text = "keep %d" % target
