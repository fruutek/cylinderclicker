class_name ScreenFrame
extends ModalDialog
## A full-height phone screen: the four destinations along the top (FACTORY | ORDERS | STOCK | UPGRADES), one
## scrolling page of big cards below, and a one-line message at the bottom. Pages rebuild only when what they
## list changes; numbers update in place, so nothing moves under a finger.

signal navigate(key: String)
signal details_requested(tab: String)

const NAV := [["factory", "FACTORY"], ["orders", "ORDERS"], ["stock", "STOCK"], ["upgrades", "UPGRADES"]]

var company: GameSession
var key := ""
var factory_id := ""

var _nav_buttons := {}
var _scroll: ScrollContainer
var _list: VBoxContainer
var _msg: Label
var _msg_time := 0.0
var _sig := "?"
var _timer := 0.0
var _inner_w := 520


func _init(p_company: GameSession, p_key: String) -> void:
	super("", 600)
	company = p_company
	key = p_key
	factory_id = company.state.current_factory


func _ready() -> void:
	var vp := get_viewport_rect().size
	var w := int(clampf(vp.x - 20.0, 440.0, 780.0))
	_panel.custom_minimum_size = Vector2(w, 0)
	_inner_w = w - 24
	_box.add_theme_constant_override("separation", 4)
	(_box.get_child(0) as Control).visible = false
	(_box.get_child(1) as Control).visible = false
	var head := SimpleUi.hbox(3)
	for pair: Array in NAV:
		var b := SimpleUi.button(str(pair[1]), _go.bind(str(pair[0])), pair[0] == key)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(b)
		_nav_buttons[pair[0]] = b
	var close_btn := SimpleUi.button("X", close, false, float(SimpleUi.btn_h()))
	head.add_child(close_btn)
	add_control(head)
	_scroll = ScrollContainer.new()
	var h := clampf(vp.y - (float(SimpleUi.btn_h()) * 2.0 + 40.0), 150.0, 270.0)
	_scroll.custom_minimum_size = Vector2(_inner_w, h)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_control(_scroll)
	_list = SimpleUi.vbox(4)
	_list.custom_minimum_size = Vector2(_inner_w - 6, 0)
	_scroll.add_child(_list)
	_msg = SimpleUi.clip("", UiTheme.INK_SOFT)
	_msg.custom_minimum_size = Vector2(_inner_w, 10)
	add_control(_msg)
	_rebuild()


func _go(target: String) -> void:
	Sfx.play("blip")
	if target != key:
		navigate.emit(target)


func _process(delta: float) -> void:
	_msg_time -= delta
	if _msg_time <= 0.0 and _msg.text != "":
		_msg.text = ""
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.25
	var s := _signature()
	if s != _sig:
		_rebuild()
	else:
		_update()


func _rebuild() -> void:
	_sig = _signature()
	for c in _list.get_children():
		c.queue_free()
	_build()
	_update()


## Plain text that changes only when the page's structure does. Subclasses override.
func _signature() -> String:
	return ""


func _build() -> void:
	pass


func _update() -> void:
	pass


func say(text: String, color: Color = UiTheme.INK, seconds: float = 4.0) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", color)
	_msg_time = seconds


func section(text: String) -> Label:
	var l := UiTheme.label(text, UiTheme.COPPER.darkened(0.3))
	_list.add_child(l)
	return l


func note(text: String) -> Label:
	var l := UiTheme.label(text, UiTheme.INK_SOFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(_inner_w - 12, 0)
	_list.add_child(l)
	return l


func stock_factories() -> Array[FactorySim]:
	var out: Array[FactorySim] = []
	for sim in company.factories:
		if sim.state.unlocked and sim.stock_enabled():
			out.append(sim)
	return out


func sim() -> FactorySim:
	var s := company.factory(factory_id)
	if s == null or not s.state.unlocked:
		s = company.current()
		factory_id = s.data.id
	return s


## Buttons to pick which factory the page is about (only when there is a choice).
func factory_picker() -> void:
	var all := stock_factories()
	if all.size() < 2:
		return
	var r := SimpleUi.hbox(3)
	for f in all:
		var b := SimpleUi.button(f.data.short_name.to_upper(), _pick.bind(f.data.id), f.data.id == factory_id)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(b)
	_list.add_child(r)


func _pick(id: String) -> void:
	factory_id = id
	Sfx.play("blip")
	_sig = "?"


func details_button(tab: String) -> void:
	var b := SimpleUi.button("MORE DETAILS", func() -> void: details_requested.emit(tab))
	b.modulate = Color(1, 1, 1, 0.75)
	_list.add_child(b)
