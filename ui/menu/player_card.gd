class_name PlayerCard
extends Control
## One lobby seat: an angled ink card with the identity colour block, the name in outlined caps
## and HOST / YOU / BOT tags. Slams in when created.

var slot_name: String = ""
var colour: Color = Color.WHITE
var colour_name: String = ""
var tags: PackedStringArray = []
var _font: Font


func setup(p_name: String, p_colour: Color, p_colour_name: String, p_tags: PackedStringArray) -> void:
	slot_name = p_name
	colour = p_colour
	colour_name = p_colour_name
	tags = p_tags
	custom_minimum_size = Vector2(420, 60)
	size = custom_minimum_size
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.slam(self)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var skew := h * 0.28
	var ink := UiStyle.ink()
	var body := PackedVector2Array([Vector2(skew, 0), Vector2(w, 0), Vector2(w - skew, h), Vector2(0, h)])
	draw_colored_polygon(body, Color(ink, 0.85))
	var block := PackedVector2Array([Vector2(skew, 0), Vector2(skew + 70, 0), Vector2(70, h), Vector2(0, h)])
	draw_colored_polygon(block, Palette.under_ceiling(colour))
	draw_polyline(PackedVector2Array([Vector2(skew, 0), Vector2(w, 0), Vector2(w - skew, h), Vector2(0, h), Vector2(skew, 0)]), colour, 2.0)
	draw_set_transform_matrix(Transform2D(Vector2(1.0, 0.0), Vector2(-0.16, 1.0), Vector2(92, 40)))
	draw_string_outline(_font, Vector2.ZERO, slot_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, ink)
	draw_string(_font, Vector2.ZERO, slot_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UiStyle.paper())
	draw_set_transform_matrix(Transform2D())
	var x := w - skew - 12.0
	for i in range(tags.size() - 1, -1, -1):
		var t: String = tags[i]
		var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_RIGHT, -1, 15).x
		x -= tw + 14.0
		draw_string_outline(_font, Vector2(x, 24), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, ink)
		draw_string(_font, Vector2(x, 24), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, colour)
	draw_string_outline(_font, Vector2(92, 54), colour_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, ink)
	draw_string(_font, Vector2(92, 54), colour_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(colour, 0.9))
