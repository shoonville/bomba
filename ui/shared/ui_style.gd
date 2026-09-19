class_name UiStyle
extends RefCounted
## The menu language Sean approved: outlined caps, skewed accent buttons with ink borders,
## angled panels. Every screen uses these helpers so the look stays one thing (STYLE.md §7).


static func ink() -> Color:
	return Palette.map_colour("menu", "line")


static func accent() -> Color:
	return Palette.map_colour("menu", "accent")


static func paper() -> Color:
	return Palette.hud_colour("paper")


static func label(text: String, size: int = 22, colour: Color = Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", paper() if colour.a == 0.0 else colour)
	l.add_theme_color_override("font_outline_color", ink())
	l.add_theme_constant_override("outline_size", maxi(6, size / 3))
	l.custom_minimum_size = Vector2(0, size + 18)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


static func skewed_box(fill: Color, border: Color, skew: float = 0.25, margin: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.skew = Vector2(skew, 0.0)
	sb.set_content_margin_all(margin)
	return sb


static func button(text: String, on_pressed: Callable, size: int = 22, fill: Color = Color(0, 0, 0, 0)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, size + 18)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", paper())
	b.add_theme_color_override("font_hover_color", ink())
	b.add_theme_color_override("font_pressed_color", ink())
	b.add_theme_color_override("font_outline_color", ink())
	b.add_theme_constant_override("outline_size", maxi(6, size / 3))
	var base := accent() if fill.a == 0.0 else fill
	b.add_theme_stylebox_override("normal", skewed_box(base, ink()))
	b.add_theme_stylebox_override("hover", skewed_box(paper(), ink()))
	b.add_theme_stylebox_override("pressed", skewed_box(paper(), ink()))
	b.add_theme_stylebox_override("focus", skewed_box(base, paper()))
	var disabled := skewed_box(Color.from_hsv(base.h, base.s * 0.3, base.v * 0.6), ink())
	b.add_theme_stylebox_override("disabled", disabled)
	b.pressed.connect(func():
		Events.ui_sound.emit("ui_click")
		on_pressed.call()
	)
	b.mouse_entered.connect(func():
		if not b.disabled:
			Events.ui_sound.emit("ui_hover")
	)
	return b


static func line_edit(text: String, width: float = 260.0) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.custom_minimum_size = Vector2(width, 40)
	e.add_theme_font_size_override("font_size", 20)
	e.add_theme_stylebox_override("normal", skewed_box(Color(ink(), 0.75), Color(paper(), 0.35), 0.15, 8))
	e.add_theme_stylebox_override("focus", skewed_box(Color(ink(), 0.85), accent(), 0.15, 8))
	e.add_theme_color_override("font_color", paper())
	return e


static func swirl_background(field_key: String = "field", counter_key: String = "counter") -> ColorRect:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://art/shaders/swirl.gdshader")
	mat.set_shader_parameter("col_a", Palette.map_colour("menu", field_key))
	mat.set_shader_parameter("col_b", Palette.map_colour("menu", counter_key))
	mat.set_shader_parameter("col_c", accent())
	mat.set_shader_parameter("col_d", ink())
	bg.material = mat
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bg


## A screen title: paper fill, thick accent outline, upright (Sean: no slanted lettering).
static func title(text: String, size: int = 96, outline_colour: Color = Color(0, 0, 0, 0)) -> Label:
	var t := Label.new()
	t.text = text
	t.add_theme_font_size_override("font_size", size)
	t.add_theme_color_override("font_color", paper())
	t.add_theme_color_override("font_outline_color", accent() if outline_colour.a == 0.0 else outline_colour)
	t.add_theme_constant_override("outline_size", maxi(12, size / 6))
	return t


## The logo treatment: fill + ink outline over a white sticker border (STYLE.md §3 key-art
## outlines). Colours come from palette.json menu.logo_fill / logo_ink / logo_sticker.
static func logo(text: String, size: int = 132) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := Palette.map_colour("menu", "logo_fill")
	var logo_ink := Palette.map_colour("menu", "logo_ink")
	var sticker := Palette.map_colour("menu", "logo_sticker")
	var ink_w := maxi(10, size / 9)
	var sticker_w := ink_w + maxi(10, size / 9)
	var back := Label.new()
	back.text = text
	back.add_theme_font_size_override("font_size", size)
	back.add_theme_color_override("font_color", sticker)
	back.add_theme_color_override("font_outline_color", sticker)
	back.add_theme_constant_override("outline_size", sticker_w)
	root.add_child(back)
	var front := Label.new()
	front.text = text
	front.add_theme_font_size_override("font_size", size)
	front.add_theme_color_override("font_color", fill)
	front.add_theme_color_override("font_outline_color", logo_ink)
	front.add_theme_constant_override("outline_size", ink_w)
	root.add_child(front)
	root.custom_minimum_size = front.get_minimum_size()
	root.size = root.custom_minimum_size
	return root


## Slam a control in: from 1.35× settling in 0.22 s. No rotation: lettering stays upright.
static func slam(c: Control, delay: float = 0.0) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(1.35, 1.35)
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, 0.22).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.08).set_delay(delay)
