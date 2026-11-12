class_name ModalDialog
extends Control
## A simple centred pop-up with a dimmed backdrop. Build it with the add_*
## helpers; it frees itself when closed.

signal closed

var esc_closes := true   # whether Escape dismisses this dialog

var _panel: PanelContainer
var _box: VBoxContainer
var _buttons: HBoxContainer


func _init(title: String, width: int = 260) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.07, 0.1, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	var sb := UiTheme.flat(UiTheme.PARCH, UiTheme.WOOD_DARK, 2, 8)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(2, 3)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	_panel.add_child(_box)
	var head := UiTheme.label(title, UiTheme.COPPER.darkened(0.3), 16)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(head)
	var rule := ColorRect.new()
	rule.color = UiTheme.WOOD_LIGHT
	rule.custom_minimum_size = Vector2(0, 1)
	_box.add_child(rule)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 8)


func add_text(text: String, color: Color = UiTheme.INK) -> Label:
	var l := UiTheme.label(text, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(_panel.custom_minimum_size.x - 24, 0)
	_box.add_child(l)
	return l


func add_control(c: Control) -> void:
	_box.add_child(c)


func add_button(text: String, action: Callable = Callable(), closes: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(64, 18)
	b.pressed.connect(func() -> void:
		Sfx.play("blip")
		if action.is_valid():
			action.call()
		if closes:
			close())
	if _buttons.get_parent() == null:
		_box.add_child(_buttons)
	_buttons.add_child(b)
	return b


## A full-width button stacked vertically (used for menu-style dialogs).
func add_menu_button(text: String, action: Callable = Callable(), closes: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 18)
	b.pressed.connect(func() -> void:
		Sfx.play("blip")
		if action.is_valid():
			action.call()
		if closes:
			close())
	_box.add_child(b)
	return b


func close() -> void:
	closed.emit()
	queue_free()
