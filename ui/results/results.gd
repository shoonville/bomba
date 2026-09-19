extends Control
## Results screen: ranked list on the swirl, one accent, a button back to the lobby.

var _result: MinigameResult
var _list: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://art/shaders/swirl.gdshader")
	mat.set_shader_parameter("col_a", Palette.map_colour("menu", "counter"))
	mat.set_shader_parameter("col_b", Palette.map_colour("menu", "field"))
	mat.set_shader_parameter("col_c", Palette.map_colour("menu", "accent"))
	mat.set_shader_parameter("col_d", Palette.map_colour("menu", "line"))
	bg.material = mat
	add_child(bg)
	var title := Label.new()
	title.text = "RESULTS"
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Palette.hud_colour("paper"))
	title.add_theme_color_override("font_outline_color", Palette.map_colour("menu", "accent"))
	title.add_theme_constant_override("outline_size", 18)
	title.position = Vector2(64, 40)
	title.rotation = deg_to_rad(-6.0)
	add_child(title)
	_list = VBoxContainer.new()
	_list.position = Vector2(90, 220)
	_list.add_theme_constant_override("separation", 8)
	add_child(_list)
	var btn := Button.new()
	btn.text = "BACK TO LOBBY"
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_color_override("font_color", Palette.hud_colour("paper"))
	btn.add_theme_color_override("font_outline_color", Palette.map_colour("menu", "line"))
	btn.add_theme_constant_override("outline_size", 8)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.map_colour("menu", "accent")
	sb.border_color = Palette.map_colour("menu", "line")
	sb.set_border_width_all(3)
	sb.skew = Vector2(0.25, 0.0)
	sb.set_content_margin_all(12)
	btn.add_theme_stylebox_override("normal", sb)
	var sb2 := sb.duplicate()
	sb2.bg_color = Palette.hud_colour("paper")
	btn.add_theme_stylebox_override("hover", sb2)
	btn.add_theme_stylebox_override("pressed", sb2)
	btn.position = Vector2(90, 760)
	btn.pressed.connect(func():
		queue_free()
		Game.show_menu()
	)
	add_child(btn)


func show_result(result: MinigameResult) -> void:
	_result = result
	for r in result.rankings:
		var l := Label.new()
		l.text = "#%d   %s   %d" % [int(r["rank"]), str(r["display_name"]), int(r["score"])]
		l.add_theme_font_size_override("font_size", 40 if int(r["rank"]) == 1 else 30)
		l.add_theme_color_override("font_color", Palette.hud_colour("score") if int(r["rank"]) == 1 else Palette.hud_colour("paper"))
		l.add_theme_color_override("font_outline_color", Palette.map_colour("menu", "line"))
		l.add_theme_constant_override("outline_size", 10)
		_list.add_child(l)
