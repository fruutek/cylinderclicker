class_name PixelBar
extends Control
## A chunky pixel-art progress bar: dark outline, recessed track, a lit fill
## with a highlight line, and optional text centred over it.

var value := 0.0:
	set(v):
		v = clampf(v, 0.0, 1.0)
		if v != value:
			value = v
			queue_redraw()
var fill := UiTheme.COPPER:
	set(c):
		fill = c
		queue_redraw()
var track := Color("5a4a52")
var text := "":
	set(t):
		if t != text:
			text = t
			queue_redraw()
var text_color := Color.WHITE
var segments := 0               # >0 draws tick marks (e.g. one per pallet)


func _init(p_height: float = 10.0) -> void:
	custom_minimum_size = Vector2(40, p_height)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), UiTheme.OUTLINE)
	draw_rect(Rect2(1, 1, w - 2, h - 2), track)
	var inner := w - 2.0
	var filled := roundf(inner * value)
	if filled > 0.0:
		draw_rect(Rect2(1, 1, filled, h - 2), fill)
		draw_rect(Rect2(1, 1, filled, 1), fill.lightened(0.45))
		draw_rect(Rect2(1, h - 2, filled, 1), fill.darkened(0.3))
	if segments > 1:
		for i in range(1, segments):
			var x := 1.0 + roundf(inner * float(i) / float(segments))
			draw_rect(Rect2(x, 1, 1, h - 2), UiTheme.OUTLINE)
	if text != "":
		var f := UiTheme.font()
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_SIZE).x
		UiTheme.draw_text(self, Vector2(floorf((w - tw) / 2.0), floorf((h - 8.0) / 2.0)), text, text_color)
