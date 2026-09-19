extends Control
## Main menu + lobby. Typographic, angled, on the marbled swirl (STYLE.md §7). Host, join,
## add bots, pick a conditioner profile, start. The lobby list mirrors the session registry.

var _bg: ColorRect
var _title: Label
var _name_edit: LineEdit
var _address_edit: LineEdit
var _profile: OptionButton
var _lobby_list: VBoxContainer
var _status: Label
var _start_btn: Button
var _bots_label: Label
var _host_btn: Button
var _join_btn: Button
var _leave_btn: Button
var _bot_plus: Button
var _bot_minus: Button
var _font: Font
var _ink: Color
var _accent: Color
var _paper: Color


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	_ink = Palette.map_colour("menu", "line")
	_accent = Palette.map_colour("menu", "accent")
	_paper = Palette.hud_colour("paper")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	Session.registry_changed.connect(_refresh)
	Net.hosted.connect(func(_p): _refresh())
	Net.joined.connect(_refresh)
	Net.join_failed.connect(func(r: String): _status.text = "JOIN FAILED: " + r)
	Net.left.connect(_refresh)
	_refresh()


func _build() -> void:
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://art/shaders/swirl.gdshader")
	mat.set_shader_parameter("col_a", Palette.map_colour("menu", "field"))
	mat.set_shader_parameter("col_b", Palette.map_colour("menu", "counter"))
	mat.set_shader_parameter("col_c", Palette.map_colour("menu", "accent"))
	mat.set_shader_parameter("col_d", _ink)
	_bg.material = mat
	add_child(_bg)

	_title = Label.new()
	_title.text = "BOMBA"
	_title.add_theme_font_size_override("font_size", 132)
	_title.add_theme_color_override("font_color", _paper)
	_title.add_theme_color_override("font_outline_color", _accent)
	_title.add_theme_constant_override("outline_size", 22)
	_title.position = Vector2(64, 40)
	_title.rotation = deg_to_rad(-6.0)
	add_child(_title)
	var sub := Label.new()
	sub.text = "SIX FRIENDS. ONE BOARD. TOO MANY MINIGAMES."
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", _paper)
	sub.add_theme_color_override("font_outline_color", _ink)
	sub.add_theme_constant_override("outline_size", 8)
	sub.position = Vector2(90, 214)
	sub.rotation = deg_to_rad(-6.0)
	add_child(sub)

	var panel := VBoxContainer.new()
	panel.position = Vector2(80, 300)
	panel.custom_minimum_size = Vector2(520, 0)
	panel.add_theme_constant_override("separation", 10)
	add_child(panel)

	var row1 := HBoxContainer.new()
	panel.add_child(row1)
	row1.add_child(_label("NAME"))
	_name_edit = LineEdit.new()
	_name_edit.text = Session.local_name
	_name_edit.custom_minimum_size = Vector2(260, 40)
	row1.add_child(_name_edit)

	var row2 := HBoxContainer.new()
	panel.add_child(row2)
	_host_btn = _button("HOST", _on_host)
	row2.add_child(_host_btn)
	_address_edit = LineEdit.new()
	_address_edit.text = "127.0.0.1:%d" % Tuning.int_value("net.default_port")
	_address_edit.custom_minimum_size = Vector2(240, 40)
	row2.add_child(_address_edit)
	_join_btn = _button("JOIN", _on_join)
	row2.add_child(_join_btn)

	var row3 := HBoxContainer.new()
	panel.add_child(row3)
	row3.add_child(_label("LINE"))
	_profile = OptionButton.new()
	for p in ["lan", "good", "bad", "awful"]:
		_profile.add_item(p.to_upper())
	_profile.custom_minimum_size = Vector2(160, 40)
	row3.add_child(_profile)
	_leave_btn = _button("LEAVE", _on_leave)
	row3.add_child(_leave_btn)

	var row4 := HBoxContainer.new()
	panel.add_child(row4)
	row4.add_child(_label("BOTS"))
	_bot_minus = _button("-", func(): Session.remove_bot())
	row4.add_child(_bot_minus)
	_bots_label = _label("0")
	row4.add_child(_bots_label)
	_bot_plus = _button("+", func(): Session.add_bot(str(Tuning.value("bots.default_difficulty", "normal"))))
	row4.add_child(_bot_plus)
	_start_btn = _button("START ARENA", func(): Session.start_minigame("arena"))
	row4.add_child(_start_btn)

	_status = _label("")
	panel.add_child(_status)
	panel.add_child(_label("LOBBY"))
	_lobby_list = VBoxContainer.new()
	panel.add_child(_lobby_list)

	var hint := _label("WASD move · SPACE jump · LMB fire · RMB scope · 1/2/Q weapons · R reload · ESC mouse")
	hint.position = Vector2(80, 840)
	hint.add_theme_font_size_override("font_size", 16)
	add_child(hint)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", _paper)
	l.add_theme_color_override("font_outline_color", _ink)
	l.add_theme_constant_override("outline_size", 8)
	l.custom_minimum_size = Vector2(0, 40)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", _paper)
	b.add_theme_color_override("font_outline_color", _ink)
	b.add_theme_constant_override("outline_size", 8)
	var sb := StyleBoxFlat.new()
	sb.bg_color = _accent
	sb.border_color = _ink
	sb.set_border_width_all(3)
	sb.skew = Vector2(0.25, 0.0)
	sb.set_content_margin_all(10)
	b.add_theme_stylebox_override("normal", sb)
	var sb2 := sb.duplicate()
	sb2.bg_color = _paper
	b.add_theme_stylebox_override("hover", sb2)
	b.add_theme_stylebox_override("pressed", sb2)
	b.pressed.connect(on_pressed)
	return b


func _on_host() -> void:
	Session.local_name = _name_edit.text
	var port := Tuning.int_value("net.default_port")
	var err := Net.host(port, Tuning.int_value("arena.max_players", 6))
	if err != OK:
		_status.text = "HOST FAILED: %s" % error_string(err)
		return
	Session.host_session(Session.local_name)
	_status.text = "HOSTING ON PORT %d" % port


func _on_join() -> void:
	Session.local_name = _name_edit.text
	var target := _address_edit.text.strip_edges()
	var address := target
	var port := Tuning.int_value("net.default_port")
	if target.contains(":"):
		address = target.get_slice(":", 0)
		port = int(target.get_slice(":", 1))
	var profile := _profile.get_item_text(_profile.selected).to_lower()
	var err := Net.join(address, port, profile)
	if err != OK:
		_status.text = "JOIN FAILED: %s" % error_string(err)
		return
	Session.join_session(Session.local_name)
	_status.text = "JOINING %s:%d (%s)" % [address, port, profile.to_upper()]


func _on_leave() -> void:
	Net.leave()
	Session.players.clear()
	_status.text = ""
	_refresh()


func _refresh() -> void:
	var online := Net.transport != null
	var host := Session.is_authority() and online
	_host_btn.disabled = online
	_join_btn.disabled = online
	_leave_btn.disabled = not online
	_start_btn.visible = host
	_bot_plus.visible = host
	_bot_minus.visible = host
	var bots := 0
	for child in _lobby_list.get_children():
		child.queue_free()
	for slot in Session.slot_list():
		if slot.is_bot:
			bots += 1
		var l := _label("%s  %s%s" % [Palette.player_name(slot.colour_index), slot.display_name, "  (BOT)" if slot.is_bot else ""])
		l.add_theme_color_override("font_color", Palette.player_colour(slot.colour_index))
		_lobby_list.add_child(l)
	_bots_label.text = str(bots)
	if online and not host:
		_status.text = "CONNECTED — WAITING FOR HOST" if Net.is_online() else _status.text


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
