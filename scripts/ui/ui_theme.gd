class_name UiTheme
extends RefCounted
## Builds the game's pixel-art UI theme in code: one font, flat pixel-perfect
## style boxes and a small shared palette.

const INK := Color("3a2618")
const INK_SOFT := Color("7a5a3c")
const WOOD_DARK := Color("3a2618")
const WOOD := Color("6b4428")
const WOOD_LIGHT := Color("94663a")
const PARCH := Color("f1dfb6")
const PARCH_LIGHT := Color("fbf1d6")
const PARCH_DARK := Color("d9c292")
const CREAM := Color("f7ecd0")
const GOLD := Color("ffd75e")
const GREEN := Color("2f7d3a")
const RED := Color("b0402c")
const COPPER := Color("de8036")
const TEAL := Color("349690")
const OUTLINE := Color("2b1f2b")

const FONT_SIZE := 8
const ICON_NAMES: Array[String] = [
	"hand_tools", "finish", "conveyor", "whistle", "lean", "cut", "roll", "weld", "test", "foam", "pack", "lock", "product",
	"s_prep", "s_laser", "s_form", "s_tig", "s_coil", "s_qa", "s_case", "s_ship", "s_finish", "s_steel", "s_energy",
]

static var _font: FontFile
static var _theme: Theme
static var _icons := {}


static func font() -> FontFile:
	if _font == null:
		_font = load("res://assets/fonts/pixel.fnt")
		_font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	return _font


static func icon(icon_name: String) -> Texture2D:
	if not _icons.has(icon_name):
		var atlas := AtlasTexture.new()
		atlas.atlas = load("res://assets/sprites/icons.png")
		var idx := maxi(ICON_NAMES.find(icon_name), 0)
		atlas.region = Rect2(idx * 16, 0, 16, 16)
		_icons[icon_name] = atlas
	return _icons[icon_name]


static func flat(bg: Color, border: Color, border_width: int = 1, pad: int = 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_content_margin_all(pad + border_width)
	sb.anti_aliasing = false
	return sb


static func framed(bg: Color, pad: int = 4) -> StyleBoxFlat:
	var sb := flat(bg, WOOD_DARK, 1, pad)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 0
	sb.expand_margin_bottom = 0
	return sb


static func _solid_tex(w: int, h: int, fill: Color, border: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(border)
	img.fill_rect(Rect2i(1, 1, w - 2, h - 2), fill)
	return ImageTexture.create_from_image(img)


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = FONT_SIZE

	t.set_color("font_color", "Label", INK)
	t.set_constant("line_spacing", "Label", 1)

	var btn := flat(PARCH_LIGHT, WOOD_DARK, 1, 3)
	btn.border_width_bottom = 2
	var btn_hover := flat(Color("fffbe8"), COPPER, 1, 3)
	btn_hover.border_width_bottom = 2
	var btn_pressed := flat(PARCH_DARK, WOOD_DARK, 1, 3)
	btn_pressed.border_width_top = 2
	var btn_disabled := flat(PARCH_DARK, INK_SOFT, 1, 3)
	btn_disabled.border_width_bottom = 2
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", btn_hover)
	t.set_stylebox("pressed", "Button", btn_pressed)
	t.set_stylebox("disabled", "Button", btn_disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", INK)
	t.set_color("font_disabled_color", "Button", INK_SOFT)

	var panel := flat(PARCH, WOOD_DARK, 1, 5)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	var track := flat(PARCH_DARK, WOOD_DARK, 1, 0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	var fill := flat(COPPER, WOOD_DARK, 1, 0)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var grab := _solid_tex(6, 12, PARCH_LIGHT, WOOD_DARK)
	var grab_hi := _solid_tex(6, 12, Color.WHITE, COPPER)
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", grab_hi)
	t.set_icon("grabber_disabled", "HSlider", grab)

	t.set_stylebox("normal", "LineEdit", flat(PARCH_LIGHT, WOOD_DARK, 1, 3))
	t.set_stylebox("focus", "LineEdit", flat(Color("fffbe8"), COPPER, 1, 3))
	t.set_stylebox("read_only", "LineEdit", flat(PARCH_DARK, INK_SOFT, 1, 3))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_selected_color", "LineEdit", PARCH_LIGHT)
	t.set_color("selection_color", "LineEdit", COPPER)
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", INK_SOFT)

	t.set_constant("separation", "VBoxContainer", 3)
	t.set_constant("separation", "HBoxContainer", 4)
	_theme = t
	return t


static func label(text: String, color: Color = INK, size: int = FONT_SIZE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if size != FONT_SIZE:
		l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Draws text with a 1px dark outline (bitmap fonts have no outline of their own).
static func draw_text(canvas: CanvasItem, pos: Vector2, text: String, color: Color, centered: bool = false, outline: Color = OUTLINE) -> void:
	var f := font()
	var p := pos
	if centered:
		p.x -= floorf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x / 2.0)
	p.y += 7.0   # baseline
	if outline.a > 0.0:
		for o: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			canvas.draw_string(f, p + o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, outline)
	canvas.draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
