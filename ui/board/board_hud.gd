extends Control
## Board HUD in the menu language: turn strip (coins, Bombas, items; clickable as item targets),
## dice slam, prompts, intro and reward cards, and on-screen ROLL / fork / item buttons so a
## mouse works as well as the keys.

var director: BoardDirector
var _font: Font
var _dice_value: int = 0
var _dice_t: float = 0.0
var _fork_options: PackedStringArray = []
var _item_target_mode: String = ""
var _target_index: int = 0
var _flash: float = 0.0
var _intro: String = ""
var _intro_t: float = 0.0
var _reward_lines: Array = []
var _reward_t: float = 0.0
var _row_rects: Array = []
var _roll_btn: Button
var _fork_left: Button
var _fork_right: Button
var _item_btns: Array = []
var _item_box: HBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_roll_btn = UiStyle.button("ROLL", func(): _roll(), 30)
	_roll_btn.custom_minimum_size = Vector2(220, 56)
	_roll_btn.visible = false
	add_child(_roll_btn)
	_fork_left = UiStyle.button("◀  LEFT", func(): _choose_side(true), 24)
	_fork_right = UiStyle.button("RIGHT  ▶", func(): _choose_side(false), 24)
	_fork_left.visible = false
	_fork_right.visible = false
	_fork_left.mouse_entered.connect(func(): _hover_side(true))
	_fork_right.mouse_entered.connect(func(): _hover_side(false))
	_fork_left.mouse_exited.connect(_unhover)
	_fork_right.mouse_exited.connect(_unhover)
	add_child(_fork_left)
	add_child(_fork_right)
	_item_box = HBoxContainer.new()
	_item_box.add_theme_constant_override("separation", 8)
	add_child(_item_box)


func attach(p_director: BoardDirector) -> void:
	director = p_director
	director.state_changed.connect(func(_s): _rebuild_items())
	director.events_received.connect(_on_events)
	Events.board_dice_landed.connect(func(v: int):
		_dice_value = v
		_dice_t = 1.3
	)
	_rebuild_items()


func _on_events(events: Array) -> void:
	var rewards := []
	for e in events:
		match str(e.get("kind", "")):
			"roll":
				pass  # the number slams in when the 3D die lands (Events.board_dice_landed)
			"choose":
				_fork_options.clear()
				for o in e["options"]:
					_fork_options.append(str(o))
			"turn":
				_fork_options.clear()
				_item_target_mode = ""
				_unhover()
				var lp := director.local_player()
				if lp != null and int(e["peer"]) == lp.peer_id:
					Audio.play("round_start", -8.0)
					_flash = 1.0
			"minigame":
				_intro = "NEXT UP:  %s" % str(e.get("display_name", "MINIGAME"))
				_intro_t = 2.6
				_dice_t = 0.0
				Audio.play("round_end", -6.0)
			"coins":
				if e.has("rank"):
					rewards.append(e)
			"finished":
				_intro = "MATCH OVER"
				_intro_t = 2.0
	if not rewards.is_empty():
		_reward_lines.clear()
		for e in rewards:
			var p := director.state.player(int(e["peer"])) if director.state != null else null
			var name := p.display_name if p != null else "#%d" % int(e["peer"])
			_reward_lines.append("%s   %s   +%d" % [_ordinal(int(e["rank"])), name.to_upper(), int(e["delta"])])
		_reward_t = 3.0


func _ordinal(n: int) -> String:
	match n:
		1: return "1ST"
		2: return "2ND"
		3: return "3RD"
	return "%dTH" % n


func _process(delta: float) -> void:
	_dice_t = maxf(0.0, _dice_t - delta)
	_flash = maxf(0.0, _flash - delta * 2.0)
	_intro_t = maxf(0.0, _intro_t - delta)
	_reward_t = maxf(0.0, _reward_t - delta)
	_layout_buttons()
	queue_redraw()


func _layout_buttons() -> void:
	var size := get_rect().size
	if director == null or not is_instance_valid(director) or not director.is_inside_tree():
		_roll_btn.visible = false
		_fork_left.visible = false
		_fork_right.visible = false
		_item_box.visible = false
		return
	var st := director.state
	var mine := st != null and director.is_local_turn()
	var can_roll := mine and st.phase == BoardState.PHASE_TURNS and _item_target_mode == "" and director.local_player() != null and not director.local_player().is_bot
	_roll_btn.visible = can_roll
	_roll_btn.position = Vector2((size.x - _roll_btn.size.x) * 0.5, size.y - 160)
	var forking := mine and st.phase == BoardState.PHASE_CHOOSING and _fork_options.size() >= 2
	_fork_left.visible = forking
	_fork_right.visible = forking
	if forking and Game.args.has("hover_fork"):
		_hover_side(str(Game.args["hover_fork"]) == "left")
	if forking:
		_fork_left.position = Vector2(size.x * 0.5 - _fork_left.size.x - 30, size.y - 160)
		_fork_right.position = Vector2(size.x * 0.5 + 30, size.y - 160)
	_item_box.visible = can_roll and _item_btns.size() > 0
	_item_box.position = Vector2((size.x - _item_box.size.x) * 0.5, size.y - 225)


func _rebuild_items() -> void:
	for b in _item_btns:
		b.queue_free()
	_item_btns.clear()
	var lp := director.local_player() if director != null else null
	if lp == null:
		return
	for i in lp.items.size():
		var item := str(lp.items[i])
		var def: Dictionary = (director.cfg.get("items", {}) as Dictionary).get(item, {})
		var b := UiStyle.button("%d  %s" % [i + 1, str(def.get("display_name", item.to_upper()))], func(): _use_item_index(i), 20, Palette.player_colour(5))
		_item_box.add_child(b)
		_item_btns.append(b)


## Options are space ids; map LEFT/RIGHT by where the tiles sit on screen.
func _side_index(left: bool) -> int:
	if _fork_options.size() < 2:
		return 0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0 if left else 1
	var x0 := cam.unproject_position(director.space_position(_fork_options[0])).x
	var x1 := cam.unproject_position(director.space_position(_fork_options[1])).x
	var left_index := 0 if x0 <= x1 else 1
	return left_index if left else 1 - left_index


## Hovering LEFT or RIGHT lights the tile that choice leads to (Sean's note).
func _hover_side(left: bool) -> void:
	if director == null or director.view == null or _fork_options.size() < 2:
		return
	var idx := _side_index(left)
	if director.view.has_method("highlight_space"):
		director.view.highlight_space(str(_fork_options[idx]))


func _unhover() -> void:
	if director != null and director.view != null and director.view.has_method("clear_highlight"):
		director.view.clear_highlight()


func _roll() -> void:
	if director != null and director.is_local_turn():
		director.request_roll()


func _choose_side(left: bool) -> void:
	if director != null and director.is_local_turn():
		director.request_choose(_side_index(left))
		_unhover()


func _use_item_index(idx: int) -> void:
	var lp := director.local_player()
	if lp == null or idx >= lp.items.size():
		return
	var item := str(lp.items[idx])
	match item:
		"turbo":
			director.request_item(item, lp.peer_id)
		"shield":
			pass
		_:
			_item_target_mode = item
			_target_index = 0
			_cycle_target(0)


func _cycle_target(dir: int) -> void:
	var st := director.state
	var lp := director.local_player()
	var n := st.players.size()
	if dir == 0:
		for i in n:
			if st.players[i] != lp:
				_target_index = i
				return
		return
	for i in n:
		_target_index = posmod(_target_index + dir, n)
		if st.players[_target_index] != lp:
			break


func _confirm_target() -> void:
	var st := director.state
	if _item_target_mode == "" or _target_index >= st.players.size():
		return
	director.request_item(_item_target_mode, st.players[_target_index].peer_id)
	_item_target_mode = ""


func _unhandled_input(event: InputEvent) -> void:
	if director == null or not is_instance_valid(director) or not director.is_inside_tree() or director.state == null or not director.is_local_turn():
		return
	var st := director.state
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _item_target_mode != "":
		for i in _row_rects.size():
			if (_row_rects[i] as Rect2).has_point(event.position) and st.players[i] != director.local_player():
				_target_index = i
				_confirm_target()
				get_viewport().set_input_as_handled()
				return
	if st.phase == BoardState.PHASE_TURNS:
		if event.is_action_pressed("jump"):
			if _item_target_mode != "":
				_item_target_mode = ""
			else:
				_roll()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("weapon_1") or event.is_action_pressed("weapon_2"):
			_use_item_index(0 if event.is_action_pressed("weapon_1") else 1)
			get_viewport().set_input_as_handled()
		elif _item_target_mode != "" and (event.is_action_pressed("move_left") or event.is_action_pressed("move_right")):
			_cycle_target(-1 if event.is_action_pressed("move_left") else 1)
			get_viewport().set_input_as_handled()
		elif _item_target_mode != "" and event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
			_confirm_target()
			get_viewport().set_input_as_handled()
	elif st.phase == BoardState.PHASE_CHOOSING:
		if event.is_action_pressed("move_left"):
			_choose_side(true)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("move_right"):
			_choose_side(false)
			get_viewport().set_input_as_handled()


func _draw() -> void:
	if director == null or not is_instance_valid(director) or not director.is_inside_tree() or director.state == null:
		return
	var st := director.state
	var size := get_rect().size
	var ink := UiStyle.ink()
	var paper := UiStyle.paper()
	var accent := UiStyle.accent()
	var lp := director.local_player()
	_row_rects.clear()
	var y := 30.0
	for i in st.players.size():
		var p := st.players[i]
		var col := Palette.player_colour(p.colour_index)
		var active := i == st.active
		var targeted := _item_target_mode != "" and i == _target_index
		var w := 400.0
		var h := 44.0
		var x := 24.0 + (14.0 if active else 0.0)
		var skew := 12.0
		_row_rects.append(Rect2(x, y, w, h))
		draw_colored_polygon(PackedVector2Array([Vector2(x + skew, y), Vector2(x + w, y), Vector2(x + w - skew, y + h), Vector2(x, y + h)]), Color(ink, 0.9 if active else 0.7))
		draw_colored_polygon(PackedVector2Array([Vector2(x + skew, y), Vector2(x + skew + 34, y), Vector2(x + 34, y + h), Vector2(x, y + h)]), col)
		if active or targeted:
			draw_polyline(PackedVector2Array([Vector2(x + skew, y), Vector2(x + w, y), Vector2(x + w - skew, y + h), Vector2(x, y + h), Vector2(x + skew, y)]), Palette.hud_colour("danger") if targeted else accent, 3.0)
		_text(Vector2(x + 48, y + 29), p.display_name.to_upper(), 20, paper if p != lp else accent)
		_text(Vector2(x + 220, y + 29), "%d" % p.coins, 20, Palette.player_colour(3))
		_text(Vector2(x + 268, y + 29), "◆ %d" % p.bombas, 20, Palette.hud_colour("score"))
		var chips := ""
		for it in p.items:
			chips += str(it).substr(0, 2).to_upper() + " "
		if chips != "":
			_text(Vector2(x + 330, y + 29), chips.strip_edges(), 14, Palette.player_colour(5))
		y += h + 8.0
	_text(Vector2(size.x - 250, 52), "ROUND %d / %d" % [mini(st.round, st.rounds), st.rounds], 26, paper)
	_text(Vector2(size.x - 250, 84), "GOAL COSTS %d" % int(director.cfg.get("goal_cost", 10)), 18, Palette.hud_colour("score"))
	if _dice_t > 0.0:
		var s := 120 + int(24.0 * clampf(_dice_t - 1.3, 0.0, 0.3) / 0.3)
		var txt := "%d" % _dice_value
		var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, s).x
		_text(Vector2((size.x - tw) * 0.5, size.y * 0.42), txt, s, Color(Palette.hud_colour("score"), clampf(_dice_t * 2.0, 0.0, 1.0)), 10.0, -0.22)
	if _intro_t > 0.0:
		var a := clampf(_intro_t * 1.5, 0.0, 1.0)
		var tw := _font.get_string_size(_intro, HORIZONTAL_ALIGNMENT_CENTER, -1, 54).x
		_card(Vector2((size.x - tw) * 0.5 - 40, size.y * 0.30 - 50), Vector2(tw + 80, 90), a)
		_text(Vector2((size.x - tw) * 0.5, size.y * 0.30 + 16), _intro, 54, Color(accent, a), 8.0)
	if _reward_t > 0.0 and not _reward_lines.is_empty():
		var a := clampf(_reward_t * 1.5, 0.0, 1.0)
		var cw := 520.0
		var ch := 60.0 + 34.0 * _reward_lines.size()
		var cx := (size.x - cw) * 0.5
		var cy := size.y * 0.28
		_card(Vector2(cx, cy), Vector2(cw, ch), a)
		_text(Vector2(cx + 30, cy + 40), "MINIGAME RESULTS", 26, Color(accent, a))
		for i in _reward_lines.size():
			_text(Vector2(cx + 30, cy + 76 + 34 * i), str(_reward_lines[i]), 24, Color(Palette.hud_colour("score") if i == 0 else paper, a))
	var prompt := ""
	var ap := st.active_player()
	if st.phase == BoardState.PHASE_TURNS:
		if director.is_local_turn():
			if _item_target_mode != "":
				var target := st.players[clampi(_target_index, 0, st.players.size() - 1)]
				prompt = "%s → %s   ·   CLICK A PLAYER OR A/D + ENTER   ·   SPACE CANCELS" % [_item_target_mode.to_upper(), target.display_name.to_upper()]
			else:
				prompt = "YOUR TURN"
		elif ap != null:
			prompt = "%s IS ROLLING" % ap.display_name.to_upper()
	elif st.phase == BoardState.PHASE_CHOOSING:
		prompt = "PICK A PATH" if director.is_local_turn() else "%s IS CHOOSING" % (ap.display_name.to_upper() if ap != null else "")
	elif st.phase == BoardState.PHASE_MINIGAME:
		prompt = "MINIGAME!"
	elif st.phase == BoardState.PHASE_FINISHED:
		prompt = "MATCH OVER"
	if prompt != "":
		var pw := _font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_CENTER, -1, 26).x
		var pc := accent if director.is_local_turn() else paper
		if _flash > 0.0:
			pc = pc.lerp(Color.WHITE, _flash * 0.6)
		_text(Vector2((size.x - pw) * 0.5, size.y - 52), prompt, 26, pc, 7.0)


func _card(pos: Vector2, size: Vector2, alpha: float) -> void:
	var skew := 22.0
	draw_colored_polygon(PackedVector2Array([pos + Vector2(skew, 0), pos + Vector2(size.x, 0), pos + Vector2(size.x - skew, size.y), pos + Vector2(0, size.y)]), Color(UiStyle.ink(), 0.88 * alpha))
	draw_polyline(PackedVector2Array([pos + Vector2(skew, 0), pos + Vector2(size.x, 0), pos + Vector2(size.x - skew, size.y), pos + Vector2(0, size.y), pos + Vector2(skew, 0)]), Color(UiStyle.accent(), alpha), 3.0)


func _text(pos: Vector2, text: String, size: int, col: Color, outline: float = 5.0, shear: float = -0.16) -> void:
	var ink := UiStyle.ink()
	ink.a = col.a
	draw_set_transform_matrix(Transform2D(Vector2(1.0, 0.0), Vector2(shear, 1.0), pos))
	draw_string_outline(_font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, int(outline), ink)
	draw_string(_font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	draw_set_transform_matrix(Transform2D())
