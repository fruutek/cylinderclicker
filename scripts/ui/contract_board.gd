class_name ContractBoard
extends ModalDialog
## The Contract Board: customer offers to compare and accept, your accepted
## contracts with live progress, production share controls and the dispatch
## button, and a short history. The factories keep running behind it, so the
## bars fill while you watch. Every control is finger-sized on touch devices.

signal dispatched(id: String)

const ICONS := preload("res://assets/sprites/contract_icons.png")
const TAB_NAMES: Array[String] = ["AVAILABLE", "ACTIVE", "HISTORY"]
const HOLDER_H := 230
const TIER_ICON := {"trade": 0, "commercial": 1, "major": 2}
const GOLD_DARK := Color("a9760a")
const SHARE_PRESETS: Array[int] = [25, 50, 75, 100]

var company: GameSession
var book: ContractBook

var _tab := 0
var _keys: Array[String] = ["offers", "active", "history"]
var _stock_ui: BoardStockPages = null       # the warehouse-economy pages (stock mode only)
var _tab_buttons: Array[Button] = []
var _holder: Control
var _page: Control = null
var _message: Label
var _message_time := 0.0
var _rank_name: Label
var _rank_bar: PixelBar
var _rank_nums: Label
var _rank_next: Label
var _lockout: Label
var _stars: Control
var _timer := 0.0
var _signature := ""
var _offer_cards := {}      # offer id -> refs for live updates
var _active_cards := {}     # contract id -> refs for live updates
var _inner_w := 580


func _init(p_company: GameSession, p_tab: int = -1, p_key: String = "") -> void:
	super("CONTRACT BOARD", 616)
	company = p_company
	book = company.contracts
	var stocking := false
	for sim in company.factories:
		if sim.state.unlocked and sim.stock_enabled():
			stocking = true
	if stocking:
		_keys = ["offers", "active", "calls", "stock", "customers", "rep", "history"]
		_stock_ui = BoardStockPages.new(self)
	if p_key != "" and _keys.has(p_key):
		_tab = _keys.find(p_key)
	elif p_tab >= 0:
		_tab = _keys.find(["offers", "active", "history"][mini(p_tab, 2)]) if p_tab <= 2 else mini(p_tab, _keys.size() - 1)
	elif _stock_ui != null and company.sales.calls.size() > 0:
		_tab = _keys.find("calls")
	elif book.active.size() > 0:
		_tab = _keys.find("active")


func _tab_key() -> String:
	return _keys[clampi(_tab, 0, _keys.size() - 1)]


func _ready() -> void:
	var vp := get_viewport_rect().size
	var w := int(clampf(vp.x - 28.0, 560.0, 716.0))
	_panel.custom_minimum_size = Vector2(w, 0)
	_inner_w = w - 20
	_box.add_theme_constant_override("separation", 4)
	(_box.get_child(0) as Control).visible = false      # the stock heading and rule: the board has its own
	(_box.get_child(1) as Control).visible = false
	_build_header()
	_build_tabs()
	_holder = Control.new()
	_holder.custom_minimum_size = Vector2(_inner_w, HOLDER_H)
	_holder.clip_contents = true
	_holder.mouse_filter = Control.MOUSE_FILTER_PASS
	add_control(_holder)
	_message = UiTheme.label("", UiTheme.INK_SOFT)
	_message.custom_minimum_size = Vector2(_inner_w, 10)
	_message.clip_text = true
	add_control(_message)
	_refresh(true)
	book.rank_changed.connect(_on_rank_changed)


func _on_rank_changed(_index: int, _name: String) -> void:
	_signature = ""


func _process(delta: float) -> void:
	_timer -= delta
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			_set_default_message()
	if _timer <= 0.0:
		_timer = 0.2
		_refresh(false)
		if _message_time <= 0.0 and _tab_key() == "active" and _stock_ui == null:
			_set_default_message()      # the share warning follows the share buttons


# ----------------------------------------------------------------- header
func _build_header() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	var title := UiTheme.label("CONTRACT BOARD", UiTheme.COPPER.darkened(0.3), 16)
	top.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_lockout = UiTheme.label("", UiTheme.RED)
	top.add_child(_lockout)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(UiTheme.button_height(22) + 6, UiTheme.button_height(18))
	close_btn.pressed.connect(func() -> void:
		Sfx.play("blip")
		close())
	top.add_child(close_btn)
	add_control(top)

	var rep := HBoxContainer.new()
	rep.add_theme_constant_override("separation", 6)
	_stars = Control.new()
	_stars.custom_minimum_size = Vector2(Hud.RepStars.WIDTH, 7)
	_stars.draw.connect(_draw_stars)
	_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var star_box := CenterContainer.new()
	star_box.add_child(_stars)
	rep.add_child(star_box)
	_rank_name = UiTheme.label("", UiTheme.COPPER.darkened(0.3))
	rep.add_child(_rank_name)
	_rank_bar = PixelBar.new(8.0)
	_rank_bar.custom_minimum_size = Vector2(96, 8)
	_rank_bar.fill = UiTheme.TEAL
	var bar_box := CenterContainer.new()
	bar_box.add_child(_rank_bar)
	rep.add_child(bar_box)
	_rank_nums = UiTheme.label("", UiTheme.INK)
	rep.add_child(_rank_nums)
	_rank_next = UiTheme.label("", UiTheme.INK_SOFT)
	rep.add_child(_rank_next)
	add_control(rep)


func _draw_stars() -> void:
	var lit := book.rank_index()
	for i in 5:
		_stars.draw_texture_rect_region(Hud.RepStars.TEX, Rect2(i * 8, 0, 7, 7), Rect2(0 if i < lit else 7, 0, 7, 7))


func _update_header() -> void:
	var idx := book.rank_index()
	var prog := book.rank_progress()
	_rank_name.text = book.rank_name()
	_rank_bar.value = float(prog["fraction"])
	if int(prog["need"]) < 0:
		_rank_nums.text = "%d  (top rank)" % book.reputation
		_rank_next.text = ""
	else:
		_rank_nums.text = "%d / %d" % [int(prog["have"]), int(prog["need"])]
		_rank_next.text = "next: " + book.rules.rank_name(idx + 1)
	_lockout.text = ("Premium customers paused: %s" % NumFmt.duration(book.lockout)) if book.lockout > 0.0 else ""
	_stars.queue_redraw()


# ------------------------------------------------------------------- tabs
func _build_tabs() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	for i in _keys.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, UiTheme.button_height(18))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(show_tab.bind(i, true))
		row.add_child(b)
		_tab_buttons.append(b)
	add_control(row)


func show_tab(index: int, with_sound: bool = false) -> void:
	_tab = index
	_signature = ""
	if with_sound:
		Sfx.play("blip")
	_refresh(true)


func _style_tabs() -> void:
	var ready := book.count_status(Contract.Status.READY)
	var calls := company.sales.calls.size()
	var names := {
		"offers": "AVAILABLE (%d)" % book.offers.size(),
		"active": "ACTIVE (%d/%d%s)%s" % [book.board_active_count(), book.slots(), (" +%d" % book.call_active_count()) if book.call_active_count() > 0 else "", " !" if ready > 0 else ""],
		"calls": "CALLS (%d)%s" % [calls, " !" if calls > 0 else ""],
		"stock": "STOCK",
		"customers": "CUSTOMERS",
		"rep": "SALES REP",
		"history": "HISTORY",
	}
	for i in _tab_buttons.size():
		var key := _keys[i]
		var active := i == _tab
		var sb := UiTheme.flat(UiTheme.COPPER if active else UiTheme.PARCH_DARK, UiTheme.WOOD_DARK, 1, 2)
		for state: String in ["normal", "hover", "pressed"]:
			_tab_buttons[i].add_theme_stylebox_override(state, sb)
		var col := UiTheme.PARCH_LIGHT if active else (GOLD_DARK if ((key == "active" and ready > 0) or (key == "calls" and calls > 0)) else UiTheme.INK)
		_tab_buttons[i].add_theme_color_override("font_color", col)
		_tab_buttons[i].add_theme_color_override("font_hover_color", col)
		_tab_buttons[i].add_theme_color_override("font_pressed_color", col)
		_tab_buttons[i].text = names[key]


# ---------------------------------------------------------------- refresh
## What the current page shows, as text: the page is rebuilt only when this changes, so
## nothing is replaced under a finger because of something happening on another tab.
func _make_signature() -> String:
	var sig := "%d|%s|" % [_tab, str(book.unlocked)]
	match _tab_key():
		"offers":
			for o in book.offers:
				sig += o.id + ","
		"active":
			for c in book.active:
				sig += "%s:%d," % [c.id, c.status]      # not progress: the bars and numbers update in place
		"calls":
			sig += _stock_ui.calls_signature()
		"stock":
			sig += _stock_ui.stock_signature()
		"customers":
			sig += _stock_ui.customers_signature()
		"rep":
			sig += _stock_ui.rep_signature()
		_:
			sig += str(book.history.size())
	return sig


func _refresh(force: bool) -> void:
	_update_header()
	_style_tabs()
	var sig := _make_signature()
	if force or sig != _signature:
		_signature = sig
		_rebuild_page()
		if _message_time <= 0.0:
			_set_default_message()
	_update_live()


func _set_default_message() -> void:
	_message_time = 0.0
	_message.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	if _stock_ui != null:
		_set_stock_message()
		return
	# Warn when a factory has promised nearly all its output: it will barely be selling.
	if _tab == 1:
		for sim in company.factories:
			var committed := book.committed_share(sim.data.id)
			if sim.state.unlocked and committed >= 90:
				_message.text = "Heads up: %d%% of the %s's output is promised to orders, so it is barely selling. Lower a share to keep cash coming in." % [committed, sim.data.short_name]
				_message.add_theme_color_override("font_color", Color("c47a00"))
				return
	if not book.unlocked:
		_message.text = "Customers start calling once your factory has made a few sales."
	elif int(book.stats["completed"]) == 0 and _tab == 0:
		_message.text = "Accept an order, choose how much production to commit to it, fill it up, then DISPATCH the lorry."
	elif _tab == 0:
		_message.text = "The % figure compares the pay with selling the same cylinders normally. Orders never stop your factory selling."
	elif _tab == 1:
		_message.text = "Share = how much of the factory's output goes to the order. The rest is sold as normal."
	else:
		_message.text = "Your last orders."


func _set_stock_message() -> void:
	match _tab_key():
		"offers":
			_message.text = "Board contracts are filled from your warehouse: stock on the shelves is put aside for it at once."
		"active":
			_message.text = "Phone orders ship by themselves. Press SHIP for a board contract: paid per lorry, bonus when complete."
		"calls":
			_message.text = "Answer before they hang up (else your rep takes it, cheaper). Refusing too often loses a customer."
		"stock":
			_message.text = "The line builds to your targets and to waiting customers. Surplus goes to the wholesaler, never thrown away."
		"customers":
			_message.text = "Good relationships mean bigger orders, better prices, more patience. Loyalty builds slowly."
		"rep":
			_message.text = "Your rep forecasts what customers will ask for: odds, not a promise. Training makes it sharper."
		_:
			_message.text = "Your last orders."
	_message.add_theme_color_override("font_color", UiTheme.INK_SOFT)


func _say(text: String, color: Color = UiTheme.INK, seconds: float = 5.0) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_message_time = seconds


func _rebuild_page() -> void:
	if is_instance_valid(_page):
		_page.queue_free()
	_offer_cards.clear()
	_active_cards.clear()
	match _tab_key():
		"offers":
			_page = _build_available()
		"active":
			_page = _build_active()
		"calls":
			_page = _stock_ui.build_calls()
		"stock":
			_page = _stock_ui.build_stock()
		"customers":
			_page = _stock_ui.build_customers()
		"rep":
			_page = _stock_ui.build_rep()
		_:
			_page = _build_history()
	_holder.add_child(_page)


# -------------------------------------------------------------- helpers
func _btn(text: String, width: float, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(width, UiTheme.button_height(18))
	b.pressed.connect(action)
	return b


func _gold_button(b: Button) -> void:
	var sb := UiTheme.flat(Color("f2c14e"), UiTheme.WOOD_DARK, 1, 3)
	sb.border_width_bottom = 2
	var hover := UiTheme.flat(Color("ffd978"), UiTheme.COPPER, 1, 3)
	hover.border_width_bottom = 2
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hover)


func _tier_color(c: Contract) -> Color:
	match c.tier:
		"commercial":
			return UiTheme.GREEN
		"major":
			return UiTheme.RED
	return UiTheme.TEAL.darkened(0.15)


func _tier_tag(c: Contract) -> String:
	return str(book.rules.tier(c.tier).get("tag", c.tier.to_upper()))


func _icon(tier: String) -> TextureRect:
	var t := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = ICONS
	atlas.region = Rect2(int(TIER_ICON.get(tier, 0)) * 16, 0, 16, 16)
	t.texture = atlas
	t.custom_minimum_size = Vector2(16, 16)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## A label that is cut off rather than forcing its container wider.
func _clip(text: String, color: Color) -> Label:
	var l := UiTheme.label(text, color)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	return l


func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _row(sep: int = 4) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", sep)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r


func _card(premium: bool = false, accent: Color = UiTheme.WOOD_DARK) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiTheme.flat(UiTheme.PARCH_LIGHT, Color("c9a227") if premium else accent, 2 if premium else 1, 3)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p


func _empty_note(text: String) -> Control:
	var page := CenterContainer.new()
	page.custom_minimum_size = Vector2(_inner_w, HOLDER_H)
	var l := UiTheme.label(text, UiTheme.INK_SOFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(_inner_w * 0.7, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(l)
	return page


func _profit_now(factory_id: String) -> float:
	var sim := company.factory(factory_id)
	return sim.profit_per_cylinder() if sim != null else 0.0


func _factory_rate(c: Contract) -> float:
	var sim := company.factory(c.factory)
	if sim == null:
		return 0.0
	return maxf(sim.recent_rate_per_min() / 60.0, sim.steady_rate())


## A rough duration for estimates ("45s", "12m", "2h 10m").
static func _time_est(seconds: float) -> String:
	if seconds < 90.0:
		return "%ds" % int(seconds)
	if seconds < 3600.0:
		return "%dm" % int(roundf(seconds / 60.0))
	if seconds >= 86400.0 * 2.0:
		return ">%dd" % int(seconds / 86400.0)
	return "%dh %dm" % [int(seconds / 3600.0), int(fmod(seconds, 3600.0) / 60.0)]


static func _time(seconds: float) -> String:
	if seconds >= 86400.0 * 2.0:
		return ">%dd" % int(seconds / 86400.0)
	return NumFmt.duration(maxf(seconds, 0.0))


# -------------------------------------------------------------- AVAILABLE
func _build_available() -> Control:
	if book.offers.is_empty():
		return _empty_note("No customers are calling right now. New orders arrive every minute or so - and the better your reputation, the more of them there are." if book.unlocked
			else "Customers start calling once your factory has made a few sales.")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	var card_w := (_inner_w - 4) / 2
	for o in book.offers:
		grid.add_child(_offer_card(o, card_w))
	return grid


func _offer_card(o: Contract, card_w: int) -> Control:
	var card := _card(o.premium, _tier_color(o))
	card.custom_minimum_size = Vector2(card_w, 0)
	var row := _row(5)
	card.add_child(row)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(col)

	var l1 := _row(3)
	l1.add_child(_icon(o.tier))
	var who := _clip(o.customer, UiTheme.COPPER.darkened(0.3))
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l1.add_child(who)
	if o.premium:
		l1.add_child(UiTheme.label("PREMIUM", GOLD_DARK))
	col.add_child(l1)

	var l2 := _row(4)
	var what := _clip("%s × %s" % [NumFmt.number(o.quantity), _short_product(o.product_name)], UiTheme.INK)
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l2.add_child(what)
	l2.add_child(UiTheme.label(_tier_tag(o), _tier_color(o)))
	col.add_child(l2)

	var l3 := _row(4)
	var pays := UiTheme.label("", UiTheme.GREEN)
	l3.add_child(pays)
	var bonus := _clip("", GOLD_DARK)
	bonus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l3.add_child(bonus)
	var vs := UiTheme.label("", UiTheme.GREEN)
	l3.add_child(vs)
	col.add_child(l3)

	var l4 := _clip("", UiTheme.INK_SOFT)
	l4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(l4)

	var accept := _btn("ACCEPT", 58, _on_accept.bind(o.id))
	accept.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(accept)
	_offer_cards[o.id] = {"vs": vs, "info": l4, "contract": o, "pays": pays, "bonus": bonus}
	return card


static func _short_product(name: String) -> String:
	return name.replace(" Cylinder", " Cyl.") if name.length() > 20 else name


func _update_offer_cards() -> void:
	for id: String in _offer_cards:
		var refs: Dictionary = _offer_cards[id]
		var o: Contract = refs["contract"]
		(refs["pays"] as Label).text = "Pays " + NumFmt.money(book.quote(o))
		(refs["bonus"] as Label).text = ("+" + NumFmt.money(book.bonus_quote(o)) + " bonus") if o.bonus > 0.0 else ""
		var market := float(o.quantity) * _profit_now(o.factory)
		var vs: Label = refs["vs"]
		if market > 0.0:
			var pct := (book.quote(o) / market - 1.0) * 100.0      # the price follows your list price, so this stays put as you grow
			vs.text = "%+.0f%%" % pct
			vs.add_theme_color_override("font_color", UiTheme.GREEN if pct >= 1.0 else (UiTheme.INK_SOFT if pct > -3.0 else UiTheme.RED))
		var sim := company.factory(o.factory)
		var share := book.default_allocation(o, book.free_share(o.factory))
		var build := ""
		if book.active.size() >= book.slots():
			build = "no free slot"
		elif book.accept_problem(o) != "":
			build = "factory fully committed"
		elif sim != null and share > 0:
			var rate := sim.planning_rate(book.rules.num("planning_clicks_per_second", 1.5), book.rules.num("planning_factor", 0.85))
			if rate > 0.0:
				build = "~%s at %d%%" % [_time_est(float(o.quantity) / (rate * float(share) / 100.0)), share]
		if build == "":
			build = "no capacity"
		var deadline := "No deadline" if not o.has_deadline() else "Deadline " + _time_est(o.deadline)
		(refs["info"] as Label).text = "%s  •  %s  •  Rep +%d" % [deadline, build, book.rep_reward(o)]


func _on_accept(id: String) -> void:
	var o := book.find_offer(id)
	if o == null:
		_say("That customer has gone elsewhere.", UiTheme.RED)
		Sfx.play("deny")
		return
	var problem := book.accept(id)
	if problem != "":
		_say(problem, UiTheme.RED)
		Sfx.play("deny")
		return
	Sfx.play("stamp")
	_tab = _keys.find("active")
	_signature = ""
	_refresh(true)
	if _stock_ui != null:
		_say("Contract accepted! Anything already on the shelves has been put aside for it; the line builds the rest.", UiTheme.GREEN)
	else:
		_say("Contract accepted! Choose how much of the factory to commit with the share buttons.", UiTheme.GREEN)


# ----------------------------------------------------------------- ACTIVE
func _build_active() -> Control:
	if book.active.is_empty():
		return _empty_note("No open orders. Answer a telephone call on the CALLS tab or accept a contract on AVAILABLE." if _stock_ui != null
			else "No contracts yet. Accept an order on the AVAILABLE tab, then come back here to set how much production goes to it.")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(_inner_w, HOLDER_H)
	scroll.size = Vector2(_inner_w, HOLDER_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.custom_minimum_size = Vector2(_inner_w, 0)
	list.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(list)
	# finished orders first: they are waiting for you
	var ordered: Array[Contract] = []
	for c in book.active:
		if c.status == Contract.Status.READY:
			ordered.append(c)
	for c in book.active:
		if c.status == Contract.Status.DISPATCHING:
			ordered.append(c)
	for c in book.active:
		if c.status == Contract.Status.ACTIVE:
			ordered.append(c)
	for c in ordered:
		list.add_child(_active_card(c))
	return scroll


func _active_card(c: Contract) -> Control:
	if _stock_ui != null and book._stock(c):
		return _stock_ui.active_card(c)
	var card := _card(c.premium, _tier_color(c))
	var row := _row(6)
	card.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 2)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(left)

	var refs := {"contract": c}
	var l1 := _row(5)
	var who := _clip(c.customer, UiTheme.COPPER.darkened(0.3))
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l1.add_child(who)
	l1.add_child(UiTheme.label(_tier_tag(c), _tier_color(c)))
	if c.premium:
		l1.add_child(UiTheme.label("PREMIUM", GOLD_DARK))
	refs["pays"] = UiTheme.label("", UiTheme.GREEN)
	l1.add_child(refs["pays"])
	left.add_child(l1)

	var l2 := _row(5)
	refs["qty"] = UiTheme.label("", UiTheme.INK)
	l2.add_child(refs["qty"])
	l2.add_child(_spacer())
	refs["bonus"] = UiTheme.label("", GOLD_DARK)
	l2.add_child(refs["bonus"])
	left.add_child(l2)

	var bar := PixelBar.new(12.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.segments = c.pallets if c.status != Contract.Status.DISPATCHING else 0
	refs["bar"] = bar
	left.add_child(bar)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	right.custom_minimum_size = Vector2(112, 0)
	right.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(right)

	match c.status:
		Contract.Status.ACTIVE:
			left.add_child(_share_row(c, refs))
			refs["time"] = UiTheme.label("", UiTheme.INK)
			refs["time"].horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(refs["time"])
			var rep_line := UiTheme.label("Rep +%d" % book.rep_reward(c), UiTheme.INK_SOFT)
			rep_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(rep_line)
			var spacer := Control.new()
			spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
			right.add_child(spacer)
			right.add_child(_btn("Give up", 0, _on_abandon.bind(c.id)))
		Contract.Status.READY:
			var hint := UiTheme.label("Pallets are waiting on the dispatch pad.", UiTheme.INK_SOFT)
			left.add_child(hint)
			var spacer2 := Control.new()
			spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
			right.add_child(spacer2)
			var go := _btn("DISPATCH", 0, _on_dispatch.bind(c.id))
			go.custom_minimum_size = Vector2(0, UiTheme.button_height(18) + 10)
			_gold_button(go)
			right.add_child(go)
		_:
			left.add_child(UiTheme.label("The lorry is loading - watch the factory floor. You are paid when it leaves.", UiTheme.INK_SOFT))
			refs["time"] = UiTheme.label("", UiTheme.TEAL.darkened(0.2))
			refs["time"].horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(refs["time"])
	_active_cards[c.id] = refs
	return card


func _share_row(c: Contract, refs: Dictionary) -> Control:
	var r := _row(3)
	r.add_child(UiTheme.label("SHARE", UiTheme.INK_SOFT))
	var minus := _btn("-", 28, _on_share.bind(c.id, -10))
	r.add_child(minus)
	var value := UiTheme.label("", UiTheme.INK, 8)
	value.custom_minimum_size = Vector2(28, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	refs["share"] = value
	var value_box := CenterContainer.new()
	value_box.add_child(value)
	r.add_child(value_box)
	r.add_child(_btn("+", 28, _on_share.bind(c.id, 10)))
	refs["sales"] = UiTheme.label("", UiTheme.INK_SOFT)
	var sales_box := CenterContainer.new()
	sales_box.add_child(refs["sales"])
	r.add_child(sales_box)
	r.add_child(_spacer())
	for p in SHARE_PRESETS:
		r.add_child(_btn("ALL" if p == 100 else "%d" % p, 30, _on_preset.bind(c.id, p)))
	return r


func _on_share(id: String, delta: int) -> void:
	var c := book.find(id)
	if c == null:
		return
	var want := c.allocation + delta
	var got := book.set_allocation(id, want)
	Sfx.play("blip")
	if got != clampi(want, 0, 100) and delta > 0:
		_say("Only %d%% of this factory's output is free - your other contracts hold the rest." % got, UiTheme.INK_SOFT)
	_update_live()


func _on_preset(id: String, pct: int) -> void:
	var c := book.find(id)
	if c == null:
		return
	var got := book.set_allocation(id, pct)
	Sfx.play("blip")
	if got < pct:
		_say("Only %d%% of this factory's output is free - your other contracts hold the rest." % got, UiTheme.INK_SOFT)
	_update_live()


func _on_dispatch(id: String) -> void:
	var problem := book.dispatch(id)
	if problem != "":
		_say(problem, UiTheme.RED)
		Sfx.play("deny")
		return
	Sfx.play("engine", 0.0, -4.0)
	dispatched.emit(id)
	close()


func _on_abandon(id: String) -> void:
	var c := book.find(id)
	if c == null:
		return
	if c.delivered <= 0.0 and c.elapsed <= book.rules.num("free_cancel_seconds", 30.0):
		book.abandon(id)
		Sfx.play("blip")
		_say("Cancelled - no harm done.", UiTheme.INK)
		return
	var d := ModalDialog.new("GIVE UP THIS ORDER?", 280)
	d.add_text("%s will be let down." % c.customer)
	d.add_text("You lose %d reputation and premium customers pause for %s. The %s cylinders already built are not wasted: they are sold at the normal price." % [
		c.penalty, NumFmt.duration(book.rules.num("premium_lockout", 900.0)), NumFmt.number(c.delivered)], UiTheme.INK_SOFT)
	d.add_button("Keep going")
	d.add_button("Give up", func() -> void:
		book.abandon(id)
		_say("Order cancelled. The stock built so far was sold.", UiTheme.INK))
	get_parent().add_child(d)


func _update_active_cards() -> void:
	for id: String in _active_cards:
		var refs: Dictionary = _active_cards[id]
		var c: Contract = refs["contract"]
		(refs["qty"] as Label).text = "%s / %s × %s" % [NumFmt.number(c.delivered), NumFmt.number(c.quantity), _short_product(c.product_name)]
		var bar: PixelBar = refs["bar"]
		var bonus := refs["bonus"] as Label
		(refs["pays"] as Label).text = "Pays " + NumFmt.money(book.quote(c))
		match c.status:
			Contract.Status.ACTIVE:
				bar.value = c.fraction()
				bar.fill = UiTheme.COPPER
				var eta := book.eta_seconds(c, _factory_rate(c))
				var late := c.has_deadline() and (eta < 0.0 or eta > c.time_left)
				var eta_text := "ETA " + _time(eta)
				if eta < 0.0:
					eta_text = "no production share - raise it" if c.allocation <= 0 else "waiting for the factory to produce"
				bar.text = "%d%%   %s" % [int(c.fraction() * 100.0), eta_text]
				bar.text_color = Color("ffb0a0") if late else Color.WHITE
				(refs["share"] as Label).text = "%d%%" % c.allocation
				(refs["sales"] as Label).text = "sales %d%%" % (100 - book.committed_share(c.factory))
				var time := refs["time"] as Label
				if c.has_deadline():
					var frac := c.time_left / c.deadline
					time.text = "%s left" % _time(c.time_left)
					time.add_theme_color_override("font_color", UiTheme.GREEN if frac > 0.5 else (Color("c47a00") if frac > 0.25 else UiTheme.RED))
					if late and frac <= 0.5:
						time.text = "%s - TOO SLOW" % _time(c.time_left)
						time.add_theme_color_override("font_color", UiTheme.RED)
				else:
					time.text = "No deadline"
					time.add_theme_color_override("font_color", UiTheme.INK_SOFT)
				if c.bonus > 0.0 and c.bonus_by > 0.0:
					if c.elapsed <= c.bonus_by:
						bonus.text = "+%s bonus if done in %s" % [NumFmt.money(book.bonus_quote(c)), _time(c.bonus_by - c.elapsed)]
					else:
						bonus.text = "bonus missed"
				else:
					bonus.text = ""
			Contract.Status.READY:
				bar.value = 1.0
				bar.fill = Color("f2c14e")
				bar.text = "COMPLETE - READY FOR DISPATCH"
				bar.text_color = Color.WHITE
				bonus.text = ("+%s bonus earned" % NumFmt.money(book.bonus_quote(c))) if c.bonus_earned else ""
			_:
				bar.value = c.dispatch_progress()
				bar.fill = UiTheme.TEAL
				bar.text = "LORRY LOADING"
				bar.text_color = Color.WHITE
				bonus.text = ("+%s bonus" % NumFmt.money(book.bonus_quote(c))) if c.bonus_earned else ""
				(refs["time"] as Label).text = "pay: " + NumFmt.money(book.quote(c) + (book.bonus_quote(c) if c.bonus_earned else 0.0))


# ---------------------------------------------------------------- HISTORY
func _build_history() -> Control:
	if book.history.is_empty():
		return _empty_note("Delivered and missed orders will be listed here.")
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	list.mouse_filter = Control.MOUSE_FILTER_PASS
	var head := _row(6)
	head.custom_minimum_size = Vector2(_inner_w, 0)
	for pair: Array in [["", 20], ["CUSTOMER", 170], ["ORDER", 130], ["RESULT", 0]]:
		var l := UiTheme.label(pair[0], UiTheme.INK_SOFT)
		if int(pair[1]) > 0:
			l.custom_minimum_size = Vector2(pair[1], 0)
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(l)
	list.add_child(head)
	var shown := 0
	for h: Dictionary in book.history:
		if shown >= 9:
			break
		shown += 1
		list.add_child(_history_row(h))
	var stats := UiTheme.label("Delivered %d  •  Missed %d  •  Cylinders supplied %s  •  Paid by customers %s" % [
		int(book.stats["completed"]), int(book.stats["failed"]), NumFmt.number(float(book.stats["units"])), NumFmt.money(float(book.stats["paid"]))], UiTheme.INK_SOFT)
	list.add_child(stats)
	return list


func _history_row(h: Dictionary) -> Control:
	var panel := _card(false, UiTheme.PARCH_DARK)
	var r := _row(6)
	panel.add_child(r)
	var outcome := str(h.get("outcome", ""))
	var good := outcome == "delivered"
	var icon := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = ICONS
	atlas.region = Rect2((5 if good else (6 if outcome != "cancelled" else 7)) * 16, 0, 16, 16)
	icon.texture = atlas
	icon.custom_minimum_size = Vector2(16, 16)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(icon)
	var who := UiTheme.label(str(h.get("customer", "")), UiTheme.COPPER.darkened(0.3))
	who.custom_minimum_size = Vector2(170, 0)
	who.clip_text = true
	r.add_child(who)
	var what := UiTheme.label("%s × %s" % [NumFmt.number(float(h.get("quantity", 0))), _short_product(str(h.get("product", "")))], UiTheme.INK)
	what.custom_minimum_size = Vector2(130, 0)
	what.clip_text = true
	r.add_child(what)
	var result := ""
	var col := UiTheme.GREEN
	var rep := int(h.get("rep", 0))
	if good:
		result = "Paid %s%s  •  Rep %+d" % [NumFmt.money(float(h.get("payout", 0.0))), (" (incl. %s bonus)" % NumFmt.money(float(h.get("bonus", 0.0)))) if float(h.get("bonus", 0.0)) > 0.0 else "", rep]
	elif outcome == "cancelled":
		result = "Cancelled"
		col = UiTheme.INK_SOFT
	else:
		result = ("Deadline missed" if outcome == "deadline" else "Given up") + "  •  Rep %+d" % rep
		col = UiTheme.RED
	var res := UiTheme.label(result, col)
	res.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res.clip_text = true
	r.add_child(res)
	return panel


# ------------------------------------------------------------------- live
func _update_live() -> void:
	_update_offer_cards()
	_update_active_cards()
	if _stock_ui != null:
		match _tab_key():
			"active":
				_stock_ui.update_all_orders()
			"calls":
				_stock_ui.update_calls()
			"stock":
				_stock_ui._update_stock()
			"customers":
				_stock_ui.update_customers()
			"rep":
				_stock_ui._update_rep()
