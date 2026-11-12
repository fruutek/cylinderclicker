class_name ShopPanel
extends Control
## Right-hand shop: Upgrades, Machines and Products tabs, with a hover
## tooltip that explains each item. Entirely data-driven from GameData.

const WIDTH := 196
const ROW_H := 27
const TABS: Array[String] = ["UPGRADES", "MACHINES", "PRODUCTS"]

var session: FactorySim          # the factory whose shop this is
var company: GameState
var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _rows := {}                 # upgrade id -> row dictionary of nodes
var _footer: Label
var _tooltip: PanelContainer
var _tip_title: Label
var _tip_body: Label
var _tip_detail: Label
var _hover_id := ""
var _product_card: Label
var _current_tab := 0
var _refresh_timer := 0.0


func setup(p_session: FactorySim, p_company: GameState, tooltip_parent: Node) -> void:
	session = p_session
	company = p_company
	size = Vector2(WIDTH, 330)

	var bg := Panel.new()
	var sb := UiTheme.flat(UiTheme.PARCH, UiTheme.WOOD_DARK, 0, 0)
	sb.border_width_left = 2
	bg.add_theme_stylebox_override("panel", sb)
	bg.size = size
	add_child(bg)

	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.position = Vector2(4 + i * 63, 3)
		b.size = Vector2(62, 16)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Shortcut: %d" % (i + 1)
		b.pressed.connect(show_tab.bind(i, true))
		b.clip_text = true
		add_child(b)
		b.size = Vector2(62, 16)
		_tab_buttons.append(b)
		var page := Control.new()
		page.position = Vector2(4, 23)
		page.size = Vector2(WIDTH - 6, 330 - 23)
		add_child(page)
		_pages.append(page)

	_build_rows(_pages[0], session.data.upgrades)
	_build_rows(_pages[1], session.data.machines)
	_footer = UiTheme.label("", UiTheme.INK_SOFT)
	_footer.position = Vector2(2, session.data.machines.size() * (ROW_H + 2) + 4)
	_footer.size = Vector2(WIDTH - 12, 60)
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pages[1].add_child(_footer)
	_build_products(_pages[2])
	_build_tooltip(tooltip_parent)

	session.upgrade_purchased.connect(func(_id: String, _l: int) -> void: refresh())
	show_tab(0, false)
	refresh()


func show_tab(index: int, with_sound: bool = false) -> void:
	_current_tab = index
	for i in TABS.size():
		_pages[i].visible = i == index
		var active := i == index
		var sb := UiTheme.flat(UiTheme.COPPER if active else UiTheme.PARCH_DARK, UiTheme.WOOD_DARK, 1, 2)
		for state: String in ["normal", "hover", "pressed"]:
			_tab_buttons[i].add_theme_stylebox_override(state, sb)
		_tab_buttons[i].add_theme_color_override("font_color", UiTheme.PARCH_LIGHT if active else UiTheme.INK)
		_tab_buttons[i].add_theme_color_override("font_hover_color", UiTheme.PARCH_LIGHT if active else UiTheme.INK)
	_hide_tooltip()
	if with_sound:
		Sfx.play("blip")


# ------------------------------------------------------------------- rows
func _build_rows(page: Control, defs: Array) -> void:
	for i in defs.size():
		var def: Dictionary = defs[i]
		var id: String = def["id"]
		var btn := Button.new()
		btn.position = Vector2(0, i * (ROW_H + 2))
		btn.size = Vector2(WIDTH - 8, ROW_H)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_row_pressed.bind(id))
		btn.mouse_entered.connect(_on_row_hover.bind(id, btn))
		btn.mouse_exited.connect(_on_row_unhover.bind(id))
		page.add_child(btn)

		var icon := TextureRect.new()
		icon.position = Vector2(4, 5)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(icon)
		var name_label := UiTheme.label("")
		name_label.position = Vector2(24, 3)
		btn.add_child(name_label)
		var sub := UiTheme.label("", UiTheme.INK_SOFT)
		sub.position = Vector2(24, 14)
		btn.add_child(sub)
		var cost := UiTheme.label("")
		cost.position = Vector2(WIDTH - 8 - 74, 3)
		cost.size = Vector2(70, 10)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		btn.add_child(cost)
		var lvl := UiTheme.label("", UiTheme.INK_SOFT)
		lvl.position = Vector2(WIDTH - 8 - 54, 14)
		lvl.size = Vector2(50, 10)
		lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		btn.add_child(lvl)
		_rows[id] = {"btn": btn, "icon": icon, "name": name_label, "sub": sub, "cost": cost, "lvl": lvl, "flash": 0.0}


func _process(delta: float) -> void:
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.1
		refresh()
	for id: String in _rows:
		var row: Dictionary = _rows[id]
		if row["flash"] > 0.0:
			row["flash"] -= delta
			(row["cost"] as Label).position.x = WIDTH - 8 - 74 + (2 if int(row["flash"] * 40.0) % 2 == 0 else -2)
			if row["flash"] <= 0.0:
				(row["cost"] as Label).position.x = WIDTH - 8 - 74


func refresh() -> void:
	if session == null:
		return
	var bottleneck := session.line.bottleneck_index() if session.all_automated() else -1
	for id: String in _rows:
		var row: Dictionary = _rows[id]
		var def: Dictionary = session.data.upgrade_by_id[id]
		var btn: Button = row["btn"]
		var name_label: Label = row["name"]
		var sub: Label = row["sub"]
		var cost: Label = row["cost"]
		var lvl_label: Label = row["lvl"]
		var icon: TextureRect = row["icon"]
		var lvl := session.level(id)
		if not session.is_visible(id):
			icon.texture = UiTheme.icon("lock")
			name_label.text = "? ? ?"
			sub.text = ("Earn %s in total to reveal" if session.data.index == 0 else "Earn %s here to reveal") % NumFmt.money(float(def["unlock_at"]))
			cost.text = ""
			lvl_label.text = ""
			btn.modulate = Color(1, 1, 1, 0.6)
			continue
		btn.modulate = Color.WHITE
		icon.texture = UiTheme.icon(def["icon"])
		name_label.text = def["name"]
		lvl_label.text = ("Lv %d" % lvl) if lvl > 0 else ""
		if session.is_maxed(id):
			cost.text = "MAX"
			cost.add_theme_color_override("font_color", UiTheme.INK_SOFT)
		else:
			cost.text = NumFmt.money(session.cost(id))
			cost.add_theme_color_override("font_color", UiTheme.GREEN if session.can_afford(id) else UiTheme.RED)
		var affordable := session.can_afford(id)
		icon.modulate = Color.WHITE if affordable or session.is_maxed(id) else Color(1, 1, 1, 0.55)
		name_label.add_theme_color_override("font_color", UiTheme.INK if affordable or session.is_maxed(id) else UiTheme.INK_SOFT)
		sub.add_theme_color_override("font_color", UiTheme.INK_SOFT)
		if def["kind"] == "machine":
			var idx := int(def["station_index"])
			if lvl == 0:
				sub.text = "Automates %s" % session.data.stations[idx]["name"]
			else:
				sub.text = "%s/min" % NumFmt.number(session.station_capacity_per_min(idx, lvl), 1)
				if idx == bottleneck:
					sub.text = "SLOWEST - " + sub.text
					sub.add_theme_color_override("font_color", UiTheme.RED)
		else:
			sub.text = def.get("effect_text", "")
	_refresh_footer(bottleneck)
	_refresh_products()
	if _hover_id != "" and _tooltip.visible:
		_fill_tooltip(_hover_id)


func _refresh_footer(bottleneck: int) -> void:
	var n := session.automated_count()
	var total := session.data.stations.size()
	if n < total:
		_footer.text = "Stations automated: %d of %d.\nAutomate them all and the line runs by itself - even while the game is closed." % [n, total]
	else:
		_footer.text = "Line output: %s cylinders/min, earning %s/sec.\nHeld back by %s - upgrade the slowest machine to go faster." % [
			NumFmt.number(session.steady_rate() * 60.0, 1), NumFmt.money(session.income_per_second()),
			session.data.stations[bottleneck]["name"]]


func _on_row_pressed(id: String) -> void:
	if not session.is_visible(id):
		Sfx.play("deny")
		return
	if session.buy(id):
		var def: Dictionary = session.data.upgrade_by_id[id]
		Sfx.play("fanfare" if def["kind"] == "machine" and session.level(id) == 1 else "buy", 0.03)
	else:
		Sfx.play("deny")
		if not session.is_maxed(id):
			_rows[id]["flash"] = 0.25


# ---------------------------------------------------------------- tooltip
func _build_tooltip(parent: Node) -> void:
	_tooltip = PanelContainer.new()
	var sb := UiTheme.flat(UiTheme.PARCH_LIGHT, UiTheme.WOOD_DARK, 1, 5)
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 2
	sb.shadow_offset = Vector2(1, 2)
	_tooltip.add_theme_stylebox_override("panel", sb)
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.custom_minimum_size = Vector2(176, 0)
	_tooltip.visible = false
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(vb)
	_tip_title = UiTheme.label("", UiTheme.COPPER.darkened(0.25))
	_tip_body = UiTheme.label("")
	_tip_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_body.custom_minimum_size = Vector2(164, 0)
	_tip_detail = UiTheme.label("", UiTheme.GREEN)
	_tip_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_detail.custom_minimum_size = Vector2(164, 0)
	vb.add_child(_tip_title)
	vb.add_child(_tip_body)
	vb.add_child(_tip_detail)
	parent.add_child(_tooltip)


func _on_row_hover(id: String, anchor: Control) -> void:
	_hover_id = id
	_fill_tooltip(id)
	_show_tooltip_at(anchor)


func _on_row_unhover(id: String) -> void:
	if _hover_id == id:
		_hide_tooltip()


func _show_tooltip_at(anchor: Control) -> void:
	_tooltip.visible = true
	_tooltip.reset_size()
	var y := anchor.global_position.y
	_tooltip.global_position = Vector2(global_position.x - _tooltip.size.x - 3, clampf(y, 33.0, 356.0 - _tooltip.size.y))


func _hide_tooltip() -> void:
	_hover_id = ""
	if _tooltip != null:
		_tooltip.visible = false


func _fill_tooltip(id: String) -> void:
	if id.begins_with("product:"):
		var entry: Dictionary = _product_entries[id]
		_tip_title.text = String(entry["name"]).to_upper()
		_tip_body.text = entry["desc"]
		if company.unlocked_products.has(entry["id"]):
			_tip_detail.text = "In production."
			_tip_detail.add_theme_color_override("font_color", UiTheme.GREEN)
		else:
			_tip_detail.text = "Locked - build the factory that makes it (see FACTORIES)." if entry.has("factory") else "Locked - arrives in a future update."
			_tip_detail.add_theme_color_override("font_color", UiTheme.RED)
		return
	var def: Dictionary = session.data.upgrade_by_id[id]
	if not session.is_visible(id):
		_tip_title.text = "LOCKED"
		_tip_body.text = "Keep shipping cylinders to discover this upgrade."
		_tip_detail.text = "Earned here: %s / %s" % [NumFmt.money(session.state.earned), NumFmt.money(float(def["unlock_at"]))]
		_tip_detail.add_theme_color_override("font_color", UiTheme.INK_SOFT)
		return
	var lvl := session.level(id)
	_tip_title.text = String(def["name"]).to_upper()
	_tip_body.text = def["desc"]
	_tip_detail.add_theme_color_override("font_color", UiTheme.GREEN)
	var lines: Array[String] = []
	if def["kind"] == "machine":
		var idx := int(def["station_index"])
		var now := session.station_capacity_per_min(idx, lvl)
		var next := session.station_capacity_per_min(idx, lvl + 1)
		if lvl == 0:
			lines.append("Runs %s for you at %s cylinders/min." % [session.data.stations[idx]["name"], NumFmt.number(next, 1)])
		else:
			lines.append("Level %d > %d" % [lvl, lvl + 1])
			lines.append("Capacity %s > %s per min" % [NumFmt.number(now, 1), NumFmt.number(next, 1)])
		var ms := session.data.next_milestone(lvl)
		if ms > 0:
			lines.append("Speed doubles at level %d." % ms)
	else:
		lines.append(String(def.get("effect_text", "")) + " per level")
		var max_level := int(def.get("max_level", 0))
		lines.append("Owned: %d%s" % [lvl, (" / %d" % max_level) if max_level > 0 else ""])
	if session.is_maxed(id):
		lines.append("Fully upgraded.")
	else:
		lines.append("Cost: %s" % NumFmt.money(session.cost(id)))
	_tip_detail.text = "\n".join(lines)


# --------------------------------------------------------------- products
var _product_entries := {}
var _product_rows := {}


func _build_products(page: Control) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.PARCH_LIGHT, UiTheme.WOOD_DARK, 1, 4))
	card.position = Vector2(0, 0)
	card.size = Vector2(WIDTH - 8, 68)
	card.clip_contents = true
	page.add_child(card)
	_product_card = UiTheme.label("")
	card.add_child(_product_card)

	var y := 72.0
	var cat := session.catalog
	for section: Array in [["MATERIALS", cat.materials()], ["RANGES", cat.ranges()], ["VARIANTS", cat.variants()]]:
		var head := UiTheme.label(section[0], UiTheme.COPPER.darkened(0.25))
		head.position = Vector2(2, y)
		page.add_child(head)
		y += 11.0
		for entry: Dictionary in section[1]:
			var key := "product:" + String(entry["id"])
			_product_entries[key] = entry
			var row := Button.new()
			row.position = Vector2(0, y)
			row.size = Vector2(WIDTH - 8, 14)
			row.focus_mode = Control.FOCUS_NONE
			row.add_theme_stylebox_override("normal", UiTheme.flat(UiTheme.PARCH, UiTheme.PARCH_DARK, 1, 1))
			row.add_theme_stylebox_override("hover", UiTheme.flat(UiTheme.PARCH_LIGHT, UiTheme.COPPER, 1, 1))
			row.add_theme_stylebox_override("pressed", UiTheme.flat(UiTheme.PARCH, UiTheme.PARCH_DARK, 1, 1))
			row.mouse_entered.connect(_on_row_hover.bind(key, row))
			row.mouse_exited.connect(_on_row_unhover.bind(key))
			page.add_child(row)
			var name_label := UiTheme.label(entry["name"])
			name_label.position = Vector2(5, 2)
			row.add_child(name_label)
			var status := UiTheme.label("")
			status.position = Vector2(WIDTH - 8 - 74, 2)
			status.size = Vector2(70, 10)
			status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(status)
			_product_rows[key] = {"name": name_label, "status": status}
			y += 15.0
		y += 3.0


func _refresh_products() -> void:
	if _product_card == null or _current_tab != 2:
		return
	var making := session.manufacturing_cost()
	_product_card.text = "%s\nSale price   %s\nMaterials   -%s%s\nProfit each  %s" % [
		String(session.product["name"]).to_upper(), NumFmt.money(session.sale_price()),
		NumFmt.money(session.material_cost()), ("\nMaking      -%s" % NumFmt.money(making)) if making > 0.0 else "",
		NumFmt.money(session.profit_per_cylinder())]
	for key: String in _product_rows:
		var unlocked: bool = company.unlocked_products.has(_product_entries[key]["id"])
		var row: Dictionary = _product_rows[key]
		(row["status"] as Label).text = "IN PRODUCTION" if unlocked else "LOCKED"
		(row["status"] as Label).add_theme_color_override("font_color", UiTheme.GREEN if unlocked else UiTheme.INK_SOFT)
		(row["name"] as Label).add_theme_color_override("font_color", UiTheme.INK if unlocked else UiTheme.INK_SOFT)
