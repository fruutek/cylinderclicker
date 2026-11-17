class_name UpgradesScreen
extends ScreenFrame
## UPGRADES: one list, the most useful first. Tap a row to buy it. Short plain explanations; the full
## description is behind the small ? button.

var _rows := {}


func _init(p_company: GameSession) -> void:
	super(p_company, "upgrades")


## Every upgrade the player can see in this factory, machines included.
func _defs(f: FactorySim) -> Array:
	var out: Array = []
	out.append_array(f.data.machines)
	out.append_array(f.data.upgrades)
	return out


func _signature() -> String:
	var f := sim()
	var s := "%s|%s|" % [f.data.id, f.next_upgrade()]
	for d: Dictionary in _defs(f):
		var id := str(d["id"])
		if f.is_visible(id) and not f.is_maxed(id):
			s += id + ("+" if f.can_afford(id) else "-") + ","
	return s


func _build() -> void:
	_rows.clear()
	var f := sim()
	factory_picker()
	var best := f.next_upgrade()
	var ready: Array = []
	var later: Array = []
	var hidden := 0
	for d: Dictionary in _defs(f):
		var id := str(d["id"])
		if not f.is_visible(id):
			hidden += 1
			continue
		if f.is_maxed(id) or id == best:
			continue
		if f.can_afford(id):
			ready.append(d)
		else:
			later.append(d)
	var by_cost := func(a: Dictionary, b: Dictionary) -> bool: return f.cost(str(a["id"])) < f.cost(str(b["id"]))
	ready.sort_custom(by_cost)
	later.sort_custom(by_cost)
	if best != "":
		section("BEST NEXT BUY")
		_list.add_child(_row(f, f.data.upgrade_by_id[best], true))
	if not ready.is_empty():
		section("YOU CAN BUY")
		for d: Dictionary in ready:
			_list.add_child(_row(f, d, false))
	if not later.is_empty():
		section("SAVING UP FOR")
		for d: Dictionary in later.slice(0, 6):
			_list.add_child(_row(f, d, false))
	if hidden > 0:
		note("%d more upgrades will appear as you earn more." % hidden)


func _row(f: FactorySim, d: Dictionary, best: bool) -> Control:
	var id := str(d["id"])
	var col := SimpleUi.vbox(2)
	var line := SimpleUi.hbox(4)
	col.add_child(line)
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 50 if UiTheme.touch else 32)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.clip_contents = true
	btn.pressed.connect(_buy.bind(id))
	if best:
		SimpleUi.gold(btn)
	line.add_child(btn)
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 6
	inner.offset_right = -6
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(inner)
	var icon := TextureRect.new()
	icon.texture = UiTheme.icon(str(d["icon"]))
	icon.custom_minimum_size = Vector2(20, 20)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(text)
	var name_l := SimpleUi.clip(str(d["name"]), UiTheme.INK)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(name_l)
	var sub := SimpleUi.clip(simple_text(f, d), UiTheme.INK_SOFT)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(sub)
	var price := UiTheme.label("", UiTheme.GREEN, 8)
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(price)
	var info := SimpleUi.button("?", _toggle_info.bind(id), false, float(SimpleUi.btn_h()))
	info.modulate = Color(1, 1, 1, 0.7)
	line.add_child(info)
	var desc := UiTheme.label(str(d.get("desc", "")), UiTheme.INK_SOFT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(_inner_w - 60, 0)
	desc.visible = false
	col.add_child(desc)
	_rows[id] = {"price": price, "btn": btn, "desc": desc, "name": name_l}
	return col


## "Faster Welding - +20% speed": what the upgrade does, in a few words.
static func simple_text(f: FactorySim, d: Dictionary) -> String:
	var id := str(d["id"])
	if d.get("kind", "") == "machine":
		var idx := int(d["station_index"])
		if f.level(id) == 0:
			return "Runs %s by itself" % str(f.data.stations[idx]["name"]).to_lower()
		return "Makes %s a minute" % NumFmt.number(f.station_capacity_per_min(idx, f.level(id)), 1)
	if id == "warehouse":
		return "+%d capacity" % int(roundf(float(f.warehouse.capacity) * 0.75))
	if id == "sales_rep":
		return "Better demand forecasts"
	return str(d.get("effect_text", ""))


func _toggle_info(id: String) -> void:
	var r: Dictionary = _rows.get(id, {})
	if not r.is_empty():
		(r["desc"] as Label).visible = not (r["desc"] as Label).visible
		Sfx.play("blip")


func _buy(id: String) -> void:
	var f := sim()
	if f.buy(id):
		Sfx.play("buy")
		say("Bought %s!" % str(f.data.upgrade_by_id[id]["name"]), UiTheme.GREEN)
		_sig = "?"
	else:
		Sfx.play("deny")
		say("You need %s more for that." % NumFmt.money(maxf(f.cost(id) - company.state.cash, 0.0)), UiTheme.RED)


func _update() -> void:
	var f := sim()
	for id: String in _rows:
		var r: Dictionary = _rows[id]
		var p := r["price"] as Label
		p.text = "MAX" if f.is_maxed(id) else NumFmt.money(f.cost(id))
		p.add_theme_color_override("font_color", UiTheme.GREEN if f.can_afford(id) else UiTheme.RED)
		(r["btn"] as Button).modulate = Color.WHITE if f.can_afford(id) else Color(1, 1, 1, 0.7)
