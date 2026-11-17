extends Control
## Root scene script: assembles the factory view, HUD, shop and dialogs and
## routes input. All nodes are created in code so the project has no fragile
## hand-edited scene files.

var company: GameSession         # the whole business (shared cash, every factory)
var session: FactorySim          # the factory currently on screen
var _factory: FactoryView
var _factory_area: Control
var _hud: Hud
var _shop: ShopPanel
var _rel_note := ""
var _deck: SideDeck             # the phone-first strip beside the factory (warehouse game)
var _shop_holder: Control
var _tip_layer: Control
var _flash: ColorRect
var _notified_buildable := {}
var _check_timer := 0.0
var _shop_size := Vector2i(ShopPanel.WIDTH, 330)
var _insets := Vector2.ZERO      # left/right safe-area insets in screen units
var _inset_timer := 0.0
var _test_inset := Vector2(-1, -1)   # dev flag --safe-inset=L,R
var _tutorial: Tutorial
var _dialog_layer: Control
var _pause_dialog: ModalDialog
var _save_toast: Label
var _toast_time := 0.0
var _board_unlocked_at := -10000     # msec when the contract board opened (to hush the opening batch of offers)


func _enter_tree() -> void:
	# Theme the whole window up-front so every control is measured with the pixel font.
	get_window().theme = UiTheme.theme()
	theme = UiTheme.theme()


func _ready() -> void:
	company = Game.session
	session = company.current()
	# This node keeps running while the game is paused (so the pause menu and
	# Escape work); the factory, HUD, shop and tutorial below are pausable.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_factory_area = Control.new()
	_factory_area.position = Vector2(0, Hud.HEIGHT)
	_factory_area.size = FactoryView.SIZE
	_factory_area.clip_contents = true
	_factory_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_factory_area.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_factory_area.gui_input.connect(_on_factory_input)
	add_child(_factory_area)

	_shop_holder = Control.new()
	_shop_holder.position = Vector2(640 - ShopPanel.WIDTH, Hud.HEIGHT)
	_shop_holder.size = Vector2(ShopPanel.WIDTH, 330)
	_shop_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shop_holder)

	_hud = Hud.new()
	add_child(_hud)
	_hud.setup(company)
	_hud.settings_pressed.connect(open_pause_menu)
	_hud.factories_pressed.connect(open_factory_overview)
	_hud.orders_pressed.connect(open_contract_board)
	if company.state.stock_mode:
		_hud.simplify()

	# The tutorial teaches the starting factory, so it lives there.
	_tutorial = Tutorial.new()
	add_child(_tutorial)
	_tutorial.setup(company.factories[0], company.state)

	_tip_layer = Control.new()
	_tip_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tip_layer)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_dialog_layer = Control.new()
	_dialog_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dialog_layer)

	# Save feedback sits above everything, so it is readable over the pause menu.
	_save_toast = UiTheme.label("", UiTheme.CREAM)
	_save_toast.position = Vector2(6, Hud.HEIGHT + 4)
	# A dark backing keeps toasts readable over the light factory wall.
	var toast_bg := UiTheme.flat(Color(0.17, 0.12, 0.17, 0.9), UiTheme.WOOD_DARK, 1, 1)
	toast_bg.content_margin_left = 4
	toast_bg.content_margin_right = 4
	_save_toast.add_theme_stylebox_override("normal", toast_bg)
	_save_toast.visible = false
	add_child(_save_toast)
	for node: Node in [_factory_area, _shop_holder, _hud, _tutorial]:
		node.process_mode = Node.PROCESS_MODE_PAUSABLE

	# Every factory keeps running; only the one on screen makes noise.
	for sim in company.factories:
		sim.shipped.connect(_on_factory_shipped.bind(sim))
		sim.station_finished.connect(_on_factory_station_finished.bind(sim))
	_connect_contracts()
	if company.contracts.unlocked:
		# Orders that arrived before this scene was built (loading a save) still count as new.
		_hud.unseen_offers = company.contracts.offers.size()
		var used: int = int(company.contracts.stats["completed"]) + int(company.contracts.stats["failed"])
		if used == 0 and company.contracts.active.is_empty() and not company.contracts.offers.is_empty():
			_toast(("Customers are sending in orders! Tap ORDERS." if UiTheme.touch else "Customers are sending in orders! Open ORDERS (C)."), UiTheme.GOLD, 6.0)
	Game.saved.connect(_toast.bind("Game saved", UiTheme.CREAM))
	Game.save_failed.connect(_toast.bind("SAVE FAILED - could not write the save file", Color("ff8a70")))

	Game.welcome_back.connect(_show_offline)
	Game.back_pressed.connect(_on_back)
	for arg in Game._user_args():
		if arg.begins_with("--safe-inset="):
			var parts := arg.trim_prefix("--safe-inset=").split(",")
			_test_inset = Vector2(float(parts[0]), float(parts[1]) if parts.size() > 1 else 0.0)
	get_viewport().size_changed.connect(_relayout)
	_layout()
	_show_factory(session)
	Game.apply_display()
	if not Game.pending_offline.is_empty():
		_show_offline(Game.pending_offline)
		Game.pending_offline = {}
	elif company.state.tutorial_step == 0:
		_show_intro()

	# Dev tooling: "-- --bot=res://tests/some_bot.gd" attaches an automation script.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bot="):
			var bot: Node = (load(arg.trim_prefix("--bot=")) as GDScript).new()
			bot.set("main", self)
			add_child(bot)


## Builds the view and shop for one factory. Only presentation is rebuilt:
## the simulation of every factory carries on untouched.
func _show_factory(sim: FactorySim) -> void:
	session = sim
	if is_instance_valid(_factory):
		_factory.queue_free()
	if is_instance_valid(_shop):
		_shop.queue_free()
	if is_instance_valid(_deck):
		_deck.queue_free()
	_shop = null
	_deck = null
	_factory = FactoryView.new()
	_factory_area.add_child(_factory)
	_factory.setup(sim, company.state)
	if _simple_ui():
		_deck = SideDeck.new()
		_shop_holder.add_child(_deck)
		_deck.setup(sim, company, _shop_size.x, _shop_size.y)
		_deck.navigate.connect(open_screen)
		_deck.message.connect(_toast.bind(2.5))
		_deck.call_answered.connect(_on_call_answered)
	else:
		_shop = ShopPanel.new()
		_shop_holder.add_child(_shop)
		_shop.setup(sim, company.state, _tip_layer, _shop_size.x, _shop_size.y)
	_hud.set_factory(sim)


# ----------------------------------------------------------------- layout
## Left/right space to keep clear (rounded corners, camera cutout), in
## screen units. Always zero on desktop.
func _safe_insets() -> Vector2:
	if _test_inset.x >= 0.0:
		return _test_inset
	if not OS.has_feature("mobile"):
		return Vector2.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or safe.size.x <= 0:
		return Vector2.ZERO
	var k := get_viewport_rect().size.x / float(win.x)
	return Vector2(ceilf(maxf(safe.position.x, 0) * k), ceilf(maxf(win.x - safe.end.x, 0) * k))


## Places the HUD, factory and shop for the current screen size. On the
## 640x360 desktop window this gives exactly the original arrangement; on a
## wider phone screen the factory keeps its size, the shop widens into the
## spare room and everything stays inside the safe area.
func _layout() -> void:
	var vp := get_viewport_rect().size
	_insets = _safe_insets()
	_hud.layout(vp.x, _insets.x, _insets.y)
	var avail_w := vp.x - _insets.x - _insets.y
	var avail_h := vp.y - Hud.HEIGHT
	var shop_w := ShopPanel.WIDTH
	if UiTheme.touch:
		shop_w = int(clampf(avail_w - FactoryView.SIZE.x, ShopPanel.WIDTH, 340.0))
	var total := FactoryView.SIZE.x + shop_w
	var x0 := _insets.x + floorf(maxf(avail_w - total, 0.0) / 2.0)
	_factory_area.position = Vector2(x0, Hud.HEIGHT + floorf(maxf(avail_h - FactoryView.SIZE.y, 0.0) / 2.0))
	_shop_holder.position = Vector2(x0 + FactoryView.SIZE.x, Hud.HEIGHT)
	_shop_holder.size = Vector2(shop_w, avail_h)
	_shop_size = Vector2i(shop_w, int(avail_h))
	_tutorial.set_origin(_factory_area.position)
	_save_toast.position = Vector2(x0 + 6, Hud.HEIGHT + 4)


func _relayout() -> void:
	_layout()
	_show_factory(session)


func switch_factory(id: String) -> bool:
	if id == company.state.current_factory or not company.set_current(id):
		return false
	_show_factory(company.current())
	return true


func _on_factory_shipped(_count: float, amount: float, sim: FactorySim) -> void:
	if sim == session and amount > 0.0:      # cylinders built for a contract earn nothing until dispatched
		Sfx.play("sale", 0.06, -4.0)


func _on_factory_station_finished(_index: int, sim: FactorySim) -> void:
	if sim == session:
		Sfx.play("thunk", 0.1, -10.0)


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_save_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
		if _toast_time <= 0.0:
			_save_toast.text = ""
			_save_toast.visible = false
	# A phone can be flipped to the other landscape direction, which moves
	# the camera cutout to the other side without changing the screen size.
	_inset_timer -= delta
	if _inset_timer <= 0.0:
		_inset_timer = 1.0
		if _safe_insets() != _insets:
			_relayout()
	if _flash.color.a > 0.0:
		_flash.color.a = maxf(_flash.color.a - delta * 1.6, 0.0)
	# Tell the player once when a new factory becomes buildable.
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = 0.5
		for sim in company.factories:
			var id := sim.data.id
			if company.can_unlock(id) and not _notified_buildable.has(id):
				_notified_buildable[id] = true
				_toast(("You can now build the %s! Tap FACTORIES." if UiTheme.touch else "You can now build the %s! Open FACTORIES (F).") % sim.data.name, UiTheme.GOLD)
				_toast_time = 6.0
				Sfx.play("buy")


func _toast(text: String, color: Color, seconds: float = 2.5) -> void:
	for c in _dialog_layer.get_children():
		if c is ScreenFrame:
			(c as ScreenFrame).say(text, color, seconds + 1.5)      # a screen is open: its own message line shows it
			return
	if _is_board_open():
		return        # the board shows the same news itself, and the toast would cover its title
	_save_toast.text = text
	_save_toast.visible = true
	_save_toast.reset_size()
	_save_toast.add_theme_color_override("font_color", color)
	_save_toast.modulate.a = 1.0
	_toast_time = seconds


# ------------------------------------------------------------------ input
func _on_factory_input(event: InputEvent) -> void:
	# Touchscreen: every finger that lands counts once, so two thumbs can
	# tap alternately. The mouse event the engine also synthesises for the
	# first finger is ignored, so a tap is never counted twice.
	if event is InputEventScreenTouch:
		if event.pressed:
			do_click(event.position)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.device == InputEvent.DEVICE_ID_EMULATION or Input.emulate_touch_from_mouse:
			return
		do_click(event.position)


func do_click(at: Vector2) -> void:
	session.click()
	_factory.click_feedback(at)
	Sfx.play("click", 0.12, -3.0)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	var modal_open := _dialog_layer.get_child_count() > 0
	match event.keycode:
		KEY_SPACE, KEY_ENTER:
			if not modal_open:
				do_click(_factory.layout.station_positions[0] + Vector2(120, 60))
		KEY_ESCAPE:
			_on_back()
		KEY_F11:
			company.state.settings["fullscreen"] = not bool(company.state.settings.get("fullscreen", false))
			Game.apply_display()
			Game.save_settings()
		KEY_F:
			if not modal_open:
				open_factory_overview()
		KEY_C:
			if not modal_open and (company.contracts.unlocked or (company.state.stock_mode and company.sales.unlocked)):
				if _simple_ui():
					open_screen("orders")
				else:
					open_contract_board()
		KEY_1, KEY_2, KEY_3:
			if not modal_open and _shop != null:
				_shop.show_tab(event.keycode - KEY_1, true)
			elif not modal_open and _simple_ui():
				open_screen(["orders", "stock", "upgrades"][event.keycode - KEY_1])
	get_viewport().set_input_as_handled()


## Escape on a keyboard, or the Back button/gesture on a phone: closes the
## dialog on top, or opens the pause menu.
func _on_back() -> void:
	if _dialog_layer.get_child_count() > 0:
		var top := _dialog_layer.get_child(_dialog_layer.get_child_count() - 1) as ModalDialog
		if top != null and top.esc_closes:
			top.close()
	else:
		open_pause_menu()


# ---------------------------------------------------------------- dialogs
func _open(d: ModalDialog) -> void:
	_dialog_layer.add_child(d)


## The phone-first interface is used whenever the factory keeps a warehouse (the default game).
func _simple_ui() -> bool:
	return company.state.stock_mode and session.stock_enabled()


## FACTORY | ORDERS | STOCK | UPGRADES. Opening one closes whichever screen was open.
func open_screen(key: String) -> void:
	for c in _dialog_layer.get_children():
		if c is ScreenFrame:
			c.queue_free()
		else:
			return                       # some other dialog is on top (pause, welcome back...): leave it
	if key == "factory":
		return
	var screen: ScreenFrame
	match key:
		"orders":
			screen = OrdersScreen.new(company)
			(screen as OrdersScreen).order_answered.connect(_on_call_answered)
			_hud.unseen_offers = 0
		"stock":
			screen = StockScreen.new(company)
		"upgrades":
			screen = UpgradesScreen.new(company)
		_:
			return
	Sfx.play("blip")
	screen.navigate.connect(open_screen)
	screen.details_requested.connect(_open_details)
	_toast_time = 0.01
	_open(screen)


## The advanced view (the full Contract Board) for anyone who wants every number.
func _open_details(tab: String) -> void:
	for c in _dialog_layer.get_children():
		c.queue_free()
	var board := ContractBoard.new(company, -1, tab if tab != "" else "offers")
	board.dispatched.connect(_on_dispatched)
	_open(board)


func _on_call_answered(result: Dictionary, option: String) -> void:
	var accepted := bool(result.get("accepted", false))
	Sfx.play("ding" if accepted else ("blip" if option == "decline" else "deny"))
	_toast(str(result.get("text", "")), UiTheme.GOLD if accepted else UiTheme.CREAM, 3.5)


func _show_intro() -> void:
	var d := ModalDialog.new("CYLINDER CLICKER", 300)
	d.esc_closes = false
	d.add_text("Welcome to %s!\n\nYou have just taken on a small British hot water cylinder factory: one production line, six hand-worked stations and a van waiting at the door." % company.state.factory_name)
	d.add_text("• CLICK the factory floor to work every station.\n• Finished cylinders roll to the van and earn money.\n• Spend it on upgrades and machines until the line runs itself.", UiTheme.INK_SOFT)
	d.add_button("Open the factory!", func() -> void: company.state.tutorial_step = 1)
	_open(d)


func _show_offline(summary: Dictionary) -> void:
	var trade: Dictionary = summary.get("contracts", {})
	var office: Dictionary = summary.get("sales", {})
	var d := ModalDialog.new("WELCOME BACK!", (330 if not trade.is_empty() else 280) + (36 if not office.is_empty() else 0))
	d.esc_closes = false
	var built := float(summary["cylinders"]) > 0.0
	d.add_text("You were away for %s.%s" % [NumFmt.duration(summary["away_seconds"]), " Your machines kept the line running." if built else ""])
	var parts: Array = summary.get("factories", [])
	if parts.size() > 1 and not _simple_ui():
		var lines := ""
		for part: Dictionary in parts:
			lines += "%s:  %s cylinders,  %s\n" % [part["name"], NumFmt.number(part["cylinders"]), NumFmt.money(part["cash"])]
		d.add_text(lines.strip_edges(), UiTheme.INK_SOFT)
	if built:
		d.add_text("Cylinders built:  %s\nSold for:  %s" % [NumFmt.number(summary["cylinders"]), NumFmt.money(summary["cash"])] if not trade.is_empty() else "Cylinders built:  %s\nMoney earned:  %s" % [NumFmt.number(summary["cylinders"]), NumFmt.money(summary["cash"])], UiTheme.GREEN)
	if summary["capped"]:
		d.add_text("(The factory runs unattended for up to %s.)" % NumFmt.duration(summary["counted_seconds"]), UiTheme.INK_SOFT)
	if not office.is_empty():
		var waiting := int(office.get("calls_waiting", 0))
		var missed := int(office.get("missed", 0))
		if waiting > 0:
			d.add_text("%d customer%s waiting for you." % [waiting, "s are" if waiting != 1 else " is"], Color("a9760a"))
		if missed > 0:
			d.add_text("%d call%s lapsed while you were away." % [missed, "s" if missed != 1 else ""], UiTheme.INK_SOFT)
	if not trade.is_empty() and _simple_ui():
		var sent := (trade.get("paid", []) as Array).size()
		if sent > 0:
			d.add_text("%d order%s delivered while you were away." % [sent, "s" if sent != 1 else ""], UiTheme.GREEN)
		for f: Dictionary in trade.get("failed", []):
			d.add_text("%s gave up waiting." % f["customer"], UiTheme.RED)
	elif not trade.is_empty():
		_add_contract_summary(d, trade)
	if int(office.get("rep_orders", 0)) > 0:
		d.add_text("Your sales rep took %d order%s for you." % [int(office["rep_orders"]), "s" if int(office["rep_orders"]) != 1 else ""], UiTheme.INK_SOFT)
	d.add_button("Lovely!", func() -> void: Sfx.play("sale"))
	_open(d)
	if company.state.tutorial_step == 0:
		company.state.tutorial_step = 1


## The contract part of the welcome-back box: what was built for each order,
## what is ready to dispatch, what was missed, and who called while you were away.
func _add_contract_summary(d: ModalDialog, trade: Dictionary) -> void:
	var rule := ColorRect.new()
	rule.color = UiTheme.WOOD_LIGHT
	rule.custom_minimum_size = Vector2(0, 1)
	d.add_control(rule)
	d.add_text("CONTRACTS", UiTheme.COPPER.darkened(0.3))
	var shown := 0
	var more := 0
	var add := func(text: String, color: Color) -> void:
		if shown >= 7:
			more += 1
			return
		shown += 1
		d.add_text(text, color)
	for p: Dictionary in trade.get("paid", []):
		add.call("Lorry left for %s:  +%s" % [p["customer"], NumFmt.money(p["amount"])], UiTheme.GREEN)
	for name: String in trade.get("ready", []):
		add.call("READY TO DISPATCH:  %s" % name, Color("a9760a"))
	for f: Dictionary in trade.get("failed", []):
		add.call("MISSED:  %s - deadline passed. The %s cylinders built were sold." % [f["customer"], NumFmt.number(f["units"])], UiTheme.RED)
	for p: Dictionary in trade.get("progress", []):
		var left := ""
		if float(p["time_left"]) >= 0.0:
			left = "  (%s left)" % NumFmt.duration(p["time_left"])
		add.call("%s:  %s / %s  (+%s)%s" % [p["customer"], NumFmt.number(p["delivered"]), NumFmt.number(p["quantity"]), NumFmt.number(p["added"]), left], UiTheme.INK)
	if more > 0:
		d.add_text("...and %d more." % more, UiTheme.INK_SOFT)
	if int(trade.get("new_offers", 0)) > 0:
		d.add_text("%d new customer orders are waiting on the board." % int(trade["new_offers"]), UiTheme.INK_SOFT)
	if trade.get("ready", []).size() > 0 or int(trade.get("new_offers", 0)) > 0:
		_hud.unseen_offers += int(trade.get("new_offers", 0))


# ------------------------------------------------------------- contracts
func _connect_contracts() -> void:
	# Method callables (not lambdas): the contract book lives in Game.session and outlives this
	# scene, and Godot drops a method connection as soon as this node is freed.
	var book := company.contracts
	book.board_unlocked.connect(_on_board_unlocked)
	book.offer_added.connect(_on_offer_added)
	book.ready.connect(_on_contract_ready)
	book.completed.connect(_on_contract_completed)
	book.failed.connect(_on_contract_failed)
	book.rank_changed.connect(_on_rank_changed)
	book.shipment_left.connect(_on_shipment_left)
	book.order_ended.connect(_on_order_ended)
	company.sales.call_arrived.connect(_on_call_arrived)
	company.sales.relationship_moved.connect(_on_relationship_moved)


func _on_board_unlocked() -> void:
	_board_unlocked_at = Time.get_ticks_msec()
	_toast(("A customer has sent in an order! Tap ORDERS." if UiTheme.touch else "A customer has sent in an order! Open ORDERS (C)."), UiTheme.GOLD, 6.0)
	Sfx.play("buy")


func _on_offer_added(o: Contract) -> void:
	if _is_board_open() or _simple_ui():
		return
	_hud.unseen_offers += 1
	if Time.get_ticks_msec() - _board_unlocked_at > 1500:
		_toast("New %s from %s" % [str(company.contract_rules.tier(o.tier).get("name", "order")).to_lower(), o.customer], UiTheme.CREAM, 3.0)


func _on_contract_ready(c: Contract) -> void:
	_toast("Order ready for %s! Send the lorry from ORDERS." % c.customer, UiTheme.GOLD, 6.0)
	Sfx.play("buy")


func _on_contract_completed(c: Contract, base: float, bonus: float, rep_gain: int) -> void:
	Sfx.play("ding")
	var text := "Delivered to %s: +%s" % [c.customer, NumFmt.money(base + bonus)]
	if rep_gain > 0:
		text += "  (+%d reputation)" % rep_gain
	_toast(text, UiTheme.GOLD, 5.0)


func _on_contract_failed(c: Contract, reason: String, units: float) -> void:
	if reason == "cancelled":
		return
	Sfx.play("deny")
	if company.factory(c.factory).stock_enabled():
		_toast("%s: %s. The stock set aside went back on the shelves, reputation -%d." % [c.customer, "deadline missed" if reason == "deadline" else "order given up", c.penalty], Color("ff8a70"), 6.0)
		return
	_toast("%s: %s. %s cylinders sold, reputation -%d." % [c.customer, "deadline missed" if reason == "deadline" else "order given up", NumFmt.number(units), c.penalty], Color("ff8a70"), 6.0)


## The telephone rings: a customer wants stock. Answer it on the CALLS tab of the board.
func _on_call_arrived(call: Dictionary) -> void:
	if _is_board_open():
		Sfx.play("ring", 0.0, -8.0)
		return
	Sfx.play("ring", 0.0, -4.0)
	if _simple_ui():
		return                           # the customer is already on the side deck, with the buttons
	var cust := company.sales.find_customer(str(call["customer"]))
	_toast("The phone is ringing: %s. Tap ORDERS." % str(cust.get("name", "a customer")) if UiTheme.touch else "The phone is ringing: %s. Open ORDERS (C)." % str(cust.get("name", "a customer")), UiTheme.GOLD, 5.0)


## A warehouse lorry has left: money for the cylinders on it.
func _on_shipment_left(c: Contract, units: float, amount: float) -> void:
	if _simple_ui():
		Sfx.play("sale")
		return
	if c.shipped < float(c.quantity) - ContractBook.EPS:        # the last lorry has its own "delivered" message
		Sfx.play("sale")
		_toast("Lorry to %s: %s cylinders, +%s" % [c.customer, NumFmt.number(units), NumFmt.money(amount)], UiTheme.GOLD, 4.0)


func _on_order_ended(c: Contract, outcome: String) -> void:
	var note := _rel_note
	_rel_note = ""
	match outcome:
		"complete", "late_complete":
			Sfx.play("ding")
			var line := "Delivered to %s: %s paid" % [c.customer, NumFmt.money(c.paid_total)]
			if note != "":
				line += "  -  " + note
			_toast(line, UiTheme.GOLD, 5.0)
		_:
			Sfx.play("deny")
			_toast("%s gave up waiting! %s" % [c.customer, note], Color("ff8a70"), 6.0)


## How a customer feels about how it went, in a few words. Order results add it to their message;
## everything else (turning a customer down) says it straight away.
func _on_relationship_moved(_id: String, customer_name: String, delta: float, reason: String) -> void:
	match reason:
		"happy":
			_rel_note = "Customer happy! +%d relationship" % maxi(1, roundi(delta))
		"late":
			_rel_note = "Delivery late! Customer unhappy."
		"gave_up":
			_rel_note = "Relationship %d" % roundi(delta)
		"declined":
			_toast("%s is disappointed (%d)" % [customer_name, roundi(delta)], Color("ffb08a"), 3.0)


func _on_rank_changed(index: int, rank_name: String) -> void:
	_show_rank_up.call_deferred(index, rank_name)


func _is_board_open() -> bool:
	for c in _dialog_layer.get_children():
		if c is ContractBoard:
			return true
	return false


func open_contract_board(tab: int = -1) -> void:
	if _dialog_layer.get_child_count() > 0:
		return
	Sfx.play("blip")
	_hud.unseen_offers = 0
	_toast_time = 0.01       # clear any lingering toast
	var board := ContractBoard.new(company, tab)
	board.dispatched.connect(_on_dispatched)
	_open(board)


## The player sent a lorry: close the board and go to the factory it is loading at.
func _on_dispatched(id: String) -> void:
	var c := company.contracts.find(id)
	if c != null and c.factory != company.state.current_factory:
		switch_factory(c.factory)


func _show_rank_up(index: int, rank_name: String) -> void:
	var rules := company.contract_rules
	var rank := rules.rank(index)
	Sfx.play("fanfare")
	_flash.color.a = 0.5
	var d := ModalDialog.new("NEW REPUTATION RANK!", 290)
	d.esc_closes = false
	d.add_text(rank_name.to_upper(), UiTheme.COPPER.darkened(0.3)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.add_text(str(rank.get("perk", "")), UiTheme.GREEN)
	d.add_text("Orders on the board: %d    Contracts at once: %d" % [int(rank["offers"]), int(rank["slots"])], UiTheme.INK_SOFT)
	d.add_button("Good news!")
	var existing := _dialog_layer.get_child_count()
	_open(d)


# ------------------------------------------------------------- pause menu
func open_pause_menu() -> void:
	if _dialog_layer.get_child_count() > 0:
		return
	Sfx.play("blip")
	get_tree().paused = true   # stops the simulation, autosave timer and factory animation
	var d := ModalDialog.new("PAUSED", 210)
	_pause_dialog = d
	var name_label := d.add_text(company.state.factory_name, UiTheme.INK_SOFT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.add_menu_button("Resume Game")
	d.add_menu_button("Save Game", func() -> void: Game.save_now(), false)
	d.add_menu_button("Settings", func() -> void: _open(Dialogs.settings(true)), false)
	d.add_menu_button("Rename Factory", func() -> void:
		_open(Dialogs.name_factory("RENAME FACTORY", company.state.factory_name, "Rename", func(new_name: String) -> void:
			company.state.factory_name = new_name
			name_label.text = new_name
			_factory.queue_sign_redraw())), false)
	d.add_menu_button("Save & Return to Main Menu", func() -> void: Game.return_to_menu(), false)
	d.add_menu_button("Quit Game" if OS.has_feature("mobile") else "Quit to Desktop", func() -> void: Game.quit_game(), false)
	d.closed.connect(func() -> void: get_tree().paused = false)
	_open(d)


# ------------------------------------------------------ factory navigation
func open_factory_overview() -> void:
	if _dialog_layer.get_child_count() > 0:
		return
	Sfx.play("blip")
	var d := FactoryOverview.new(company)
	d.enter_requested.connect(func(id: String) -> void:
		d.close()
		switch_factory(id))
	d.build_requested.connect(_confirm_build)
	_open(d)


func _confirm_build(id: String) -> void:
	var def: FactoryDef = company.data.factory(id)
	var cost := def.unlock_cost()
	var d := ModalDialog.new("BUILD NEW FACTORY?", 290)
	d.add_text("Build the %s for %s?" % [def.name, NumFmt.money(cost)])
	d.add_text("You have %s. After building you will have %s left to equip it." % [
		NumFmt.money(company.state.cash), NumFmt.money(company.state.cash - cost)], UiTheme.INK_SOFT)
	d.add_text("It is yours for good, and your other factories keep running while you work in it.", UiTheme.INK_SOFT)
	d.add_button("Not yet")
	d.add_button("Build it!", func() -> void: _build_factory.call_deferred(id))
	_open(d)


func _build_factory(id: String) -> void:
	if not company.unlock_factory(id):
		Sfx.play("deny")
		return
	for c in _dialog_layer.get_children():
		(c as ModalDialog).close()
	Sfx.play("fanfare")
	_toast_time = 0.01
	_flash.color.a = 0.9
	switch_factory(id)
	_factory.celebrate()
	var def: FactoryDef = company.data.factory(id)
	var d := ModalDialog.new("GRAND OPENING!", 300)
	d.esc_closes = false
	d.add_text("The %s is open for business!" % def.name, UiTheme.GREEN)
	d.add_text(def.description)
	d.add_text("\u2022 It has its own machines and upgrades - start by %s, then automate each of its %d stations.\n\u2022 Everything it sells is paid into the same company account.\n\u2022 Your other factories carry on earning. Switch between them any time with the FACTORIES button." % ["tapping" if UiTheme.touch else "clicking", def.stations.size()], UiTheme.INK_SOFT)
	d.add_button("Cut the ribbon!", func() -> void: _factory.celebrate())
	_open.call_deferred(d)
	Game.save_now()
