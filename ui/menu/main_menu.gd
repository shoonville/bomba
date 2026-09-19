extends Control
## Main menu + lobby (STYLE.md §7, the look Sean approved): swirl, angled title, skewed buttons,
## outlined caps. Host on LAN, host online through the relay with a friend code, join by
## address or code, pick a line profile, add bots, start.

var _name_edit: LineEdit
var _join_edit: LineEdit
var _profile: OptionButton
var _lobby: VBoxContainer
var _status: Label
var _code_label: Label
var _code_row: HBoxContainer
var _start_btn: Button
var _arena_btn: Button
var _bots_label: Label
var _host_btn: Button
var _online_btn: Button
var _join_btn: Button
var _leave_btn: Button
var _bot_plus: Button
var _bot_minus: Button
var _settings: SettingsPanel
var _busy: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	Session.registry_changed.connect(_refresh)
	Net.hosted.connect(func(_p): _refresh())
	Net.joined.connect(_refresh)
	Net.join_failed.connect(func(r: String): _set_status("JOIN FAILED: " + r.to_upper()))
	Session.rejected.connect(func(r: String):
		_on_leave()
		_set_status("NO SEAT: " + r.to_upper())
	)
	Net.left.connect(_refresh)
	Net.progress.connect(func(t: String): _set_status(t.to_upper()))
	Audio.music("music_menu")
	_refresh()


func _build() -> void:
	add_child(UiStyle.swirl_background())
	var title := UiStyle.logo("BOMBA", 118)
	title.position = Vector2(72, 40)
	add_child(title)
	UiStyle.slam(title)

	var col := VBoxContainer.new()
	col.position = Vector2(80, 270)
	col.custom_minimum_size = Vector2(520, 0)
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	var row1 := HBoxContainer.new()
	col.add_child(row1)
	row1.add_child(UiStyle.label("NAME"))
	_name_edit = UiStyle.line_edit(Session.local_name, 300)
	_name_edit.text_changed.connect(func(v: String): Session.local_name = v)
	_name_edit.focus_exited.connect(func(): Settings.set_value("player_name", _name_edit.text.strip_edges()))
	row1.add_child(_name_edit)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	col.add_child(row2)
	_host_btn = UiStyle.button("HOST LAN", _on_host)
	row2.add_child(_host_btn)
	_online_btn = UiStyle.button("HOST ONLINE", _on_host_online)
	row2.add_child(_online_btn)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 8)
	col.add_child(row3)
	_join_edit = UiStyle.line_edit("", 330)
	_join_edit.placeholder_text = "friend code or ip:port"
	_join_edit.text_submitted.connect(func(_v: String): _on_join())
	row3.add_child(_join_edit)
	_join_btn = UiStyle.button("JOIN", _on_join)
	row3.add_child(_join_btn)

	var row4 := HBoxContainer.new()
	row4.add_theme_constant_override("separation", 8)
	col.add_child(row4)
	row4.add_child(UiStyle.label("LINE", 20))
	_profile = OptionButton.new()
	for p in ["lan", "good", "bad", "awful"]:
		_profile.add_item(p.to_upper())
		if p == Settings.conditioner_profile:
			_profile.selected = _profile.item_count - 1
	_profile.custom_minimum_size = Vector2(150, 40)
	_profile.item_selected.connect(func(i: int): Settings.set_value("conditioner_profile", _profile.get_item_text(i).to_lower()))
	row4.add_child(_profile)
	row4.add_child(UiStyle.button("SETTINGS", _toggle_settings, 20))
	_leave_btn = UiStyle.button("LEAVE", _on_leave, 20, Palette.hud_colour("danger"))
	row4.add_child(_leave_btn)
	row4.add_child(UiStyle.button("QUIT", func(): get_tree().quit(), 20, Color.from_hsv(0.0, 0.0, 0.35)))

	_status = UiStyle.label("", 18, UiStyle.accent())
	col.add_child(_status)

	# Lobby column
	var lobby_col := VBoxContainer.new()
	lobby_col.position = Vector2(760, 270)
	lobby_col.add_theme_constant_override("separation", 10)
	add_child(lobby_col)
	var lobby_head := HBoxContainer.new()
	lobby_head.add_theme_constant_override("separation", 12)
	lobby_col.add_child(lobby_head)
	lobby_head.add_child(UiStyle.label("LOBBY", 30))
	_bot_minus = UiStyle.button("−", func(): Session.remove_bot(), 20)
	lobby_head.add_child(_bot_minus)
	_bots_label = UiStyle.label("0 BOTS", 20)
	lobby_head.add_child(_bots_label)
	_bot_plus = UiStyle.button("+", func(): Session.add_bot(str(Tuning.value("bots.default_difficulty", "normal"))), 20)
	lobby_head.add_child(_bot_plus)
	_code_row = HBoxContainer.new()
	_code_row.add_theme_constant_override("separation", 10)
	lobby_col.add_child(_code_row)
	_code_row.add_child(UiStyle.label("CODE", 20))
	_code_label = UiStyle.label("", 30, UiStyle.accent())
	_code_row.add_child(_code_label)
	_code_row.add_child(UiStyle.button("COPY", func():
		DisplayServer.clipboard_set(Net.host_code)
		_set_status("CODE COPIED")
	, 18))
	_lobby = VBoxContainer.new()
	_lobby.add_theme_constant_override("separation", 8)
	lobby_col.add_child(_lobby)
	_start_btn = UiStyle.button("START MATCH", func(): Session.start_board(str(Tuning.value("board.default_board", "main"))), 30)
	lobby_col.add_child(_start_btn)
	_arena_btn = UiStyle.button("QUICK ARENA", func(): Session.start_minigame("arena"), 20)
	lobby_col.add_child(_arena_btn)

	var hint := UiStyle.label("WASD MOVE · SPACE JUMP · LMB FIRE · RMB SCOPE · 1/2/Q WEAPONS · R RELOAD · ESC PAUSE", 15)
	hint.position = Vector2(80, 840)
	add_child(hint)


func _set_status(text: String) -> void:
	_status.text = text


func _toggle_settings() -> void:
	if _settings != null:
		_settings.queue_free()
		_settings = null
		return
	_settings = SettingsPanel.new()
	_settings.position = Vector2(760, 250)
	_settings.closed.connect(func():
		_toggle_settings()
		_name_edit.text = Settings.player_name if Settings.player_name != "" else _name_edit.text
		Session.local_name = _name_edit.text
	)
	add_child(_settings)
	UiStyle.slam(_settings)


func _commit_name() -> void:
	Session.local_name = _name_edit.text.strip_edges()
	if Session.local_name == "":
		Session.local_name = "PLAYER"
	Settings.set_value("player_name", Session.local_name)


func _on_host() -> void:
	_commit_name()
	var port := Tuning.int_value("net.default_port")
	var err := Net.host(port, Tuning.int_value("arena.max_players", 6))
	if err != OK:
		_set_status("HOST FAILED: %s" % error_string(err).to_upper())
		return
	Session.host_session(Session.local_name)
	_fill_bots()
	_set_status("HOSTING ON LAN, PORT %d" % port)


## A fresh lobby starts with two bots so a solo host never lands in an empty 90 s minigame;
## the − button removes them and joining friends take the free seats.
func _fill_bots() -> void:
	while Session.players.size() < 3 and Session.players.size() < Tuning.int_value("arena.max_players", 6):
		Session.add_bot()


func _on_host_online() -> void:
	if _busy:
		return
	_commit_name()
	_busy = true
	_refresh()
	var err: Error = await Net.host_online(Tuning.int_value("arena.max_players", 6))
	_busy = false
	if err != OK:
		_set_status("ONLINE HOSTING FAILED: %s" % error_string(err).to_upper())
		_refresh()
		return
	Session.host_session(Session.local_name)
	_fill_bots()
	_set_status("HOSTING ONLINE. SHARE THE CODE.")
	_refresh()


func _on_join() -> void:
	if _busy:
		return
	_commit_name()
	var target := _join_edit.text.strip_edges()
	if target == "":
		_set_status("ENTER A CODE OR ADDRESS")
		return
	if target.contains(".") or target.contains(":"):
		var address := target
		var port := Tuning.int_value("net.default_port")
		if target.contains(":"):
			address = target.get_slice(":", 0)
			port = int(target.get_slice(":", 1))
		var profile := _profile.get_item_text(_profile.selected).to_lower()
		var err := Net.join(address, port, profile)
		if err != OK:
			_set_status("JOIN FAILED: %s" % error_string(err).to_upper())
			return
		Session.join_session(Session.local_name)
		_set_status("JOINING %s:%d (%s)" % [address, port, profile.to_upper()])
		return
	_busy = true
	_refresh()
	var err2: Error = await Net.join_code(target)
	_busy = false
	if err2 == OK:
		Session.join_session(Session.local_name)
		_set_status("CONNECTED BY CODE")
	_refresh()


func _on_leave() -> void:
	Net.leave()
	Session.players.clear()
	_set_status("")
	_refresh()


func _refresh() -> void:
	var online := Net.transport != null
	var host := Session.is_authority() and online
	_host_btn.disabled = online or _busy
	_online_btn.disabled = online or _busy
	_join_btn.disabled = online or _busy
	_leave_btn.disabled = not online
	_start_btn.visible = host
	_arena_btn.visible = host
	_bot_plus.visible = host
	_bot_minus.visible = host
	_code_row.visible = online and Net.host_code != ""
	_code_label.text = Net.host_code
	var bots := 0
	for child in _lobby.get_children():
		child.queue_free()
	var me := multiplayer.get_unique_id()
	for slot in Session.slot_list():
		if slot.is_bot:
			bots += 1
		var tags := PackedStringArray()
		if slot.peer_id == 1:
			tags.append("HOST")
		if slot.peer_id == me and not slot.is_bot:
			tags.append("YOU")
		if slot.is_bot:
			tags.append("BOT · " + slot.bot_difficulty.to_upper())
		var card := PlayerCard.new()
		_lobby.add_child(card)
		card.setup(slot.display_name, Palette.player_colour(slot.colour_index), Palette.player_name(slot.colour_index), tags)
		if slot.is_bot and host:
			# Click a bot's card to cycle its difficulty.
			card.mouse_filter = Control.MOUSE_FILTER_STOP
			var bot_id := slot.peer_id
			var current := slot.bot_difficulty
			card.gui_input.connect(func(ev: InputEvent):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					var order := ["easy", "normal", "hard"]
					var next: String = order[(order.find(current) + 1) % order.size()]
					Session.set_bot_difficulty(bot_id, next)
					Events.ui_sound.emit("ui_click")
			)
	_bots_label.text = "%d BOTS" % bots + ("   ·   CLICK A BOT TO SET EASY / NORMAL / HARD" if bots > 0 and host else "")
	if online and not host and Net.is_online() and _status.text == "":
		_set_status("CONNECTED. WAITING FOR THE HOST.")
