class_name SimpleUi
extends RefCounted
## Building blocks of the phone-first interface: big buttons, cards, product icons and short money/time text.
## Everything here is presentation only; the game's rules live in scripts/core.

const PALLET := preload("res://assets/sprites/pallet.png")
const TINTS: Array[Color] = [Color.WHITE, Color("cfe0ff"), Color("ffd9a6"), Color("d4f2c8")]
const GOLD_FILL := Color("f2c14e")
const GOLD_DARK := Color("a9760a")


## The height of a main button: a comfortable fingertip on a phone, compact on a desktop.
static func btn_h() -> int:
	return 40 if UiTheme.touch else 22


static func button(text: String, action: Callable, primary: bool = false, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.custom_minimum_size = Vector2(min_w, btn_h())
	if primary:
		gold(b)
	if action.is_valid():
		b.pressed.connect(action)
	return b


static func gold(b: Button) -> void:
	var sb := UiTheme.flat(GOLD_FILL, UiTheme.WOOD_DARK, 1, 3)
	sb.border_width_bottom = 2
	var hover := UiTheme.flat(Color("ffd978"), UiTheme.COPPER, 1, 3)
	hover.border_width_bottom = 2
	var pressed := UiTheme.flat(Color("e0aa38"), UiTheme.WOOD_DARK, 1, 3)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", UiTheme.INK)
	b.add_theme_color_override("font_hover_color", UiTheme.INK)
	b.add_theme_color_override("font_pressed_color", UiTheme.INK)


static func card(accent: Color = UiTheme.WOOD_DARK, fill: Color = UiTheme.PARCH_LIGHT) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiTheme.flat(fill, accent, 1, 4)
	sb.border_width_left = 3
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p


static func clip(text: String, color: Color = UiTheme.INK, size: int = UiTheme.FONT_SIZE) -> Label:
	var l := UiTheme.label(text, color, size)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	return l


static func vbox(sep: int = 3) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	return v


static func hbox(sep: int = 4) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	return h


static func spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


## A pallet of boxed cylinders as a product icon (boxes 0-6), tinted by product.
static func product_icon(index: int, boxes: int = 6) -> TextureRect:
	var t := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = PALLET
	atlas.region = Rect2(float(clampi(boxes, 0, 6)) * 24.0, 0, 24, 22)
	t.texture = atlas
	t.modulate = TINTS[index % TINTS.size()]
	t.custom_minimum_size = Vector2(24, 22)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func set_icon_boxes(icon: TextureRect, boxes: int) -> void:
	(icon.texture as AtlasTexture).region = Rect2(float(clampi(boxes, 0, 6)) * 24.0, 0, 24, 22)


## "£1.2K" style short money for tight places.
static func money(v: float) -> String:
	return NumFmt.money(v)


static func bar(h: float, fill: Color = UiTheme.COPPER) -> PixelBar:
	var b := PixelBar.new(h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.fill = fill
	return b


static func usage_color(fraction: float) -> Color:
	return UiTheme.RED if fraction >= 0.95 else (Color("c47a00") if fraction >= 0.8 else UiTheme.TEAL)
