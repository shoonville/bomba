extends Control
## Board HUD in the menu language: turn strip of player rows (coins, Bombas, items), the dice as
## a slammed numeral, the roll prompt, fork arrows, item buttons, round counter.

var director: BoardDirector
var _font: Font
var _dice_value: int = 0
var _dice_t: float = 0.0
var _prompt: String = ""
var _fork_options: PackedStringArray = []
var _item_target_mode: String = ""
var _flash: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func attach(p_director: BoardDirector) -> void:
	director = p_director
	director.state_changed.connect(func(_s): queue_redraw())
	director.events_received.connect(_on_events)
	queue_redraw()


func _on_events(events: Array) -> void:
	for e in events:
		match str(e.get("kind", "")):
			"roll":
				_dice_value = int(e["value"])
				_dice_t = 1.6
				Audio.play("dice", -2.0)
			"choose":
				_fork_options.clear()
				for o in e["options"]:
					_fork_options.append(str(o))
			"turn":
				_fork_options.clear()
				_item_target_mode = ""
				var lp := director.local_player()
				if lp != null and int(e["peer"]) == lp.peer_id:
					Audio.play("round_start", -8.0)
					_flash = 1.0


func _process(delta: float) -> void:
	_dice_t = maxf(0.0, _dice_t - delta)
	_flash = maxf(0.0, _flash - delta * 2.0)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if director == null or director.state == null or not director.is_local_turn():
		return
	var st := director.state
	if st.phase == BoardState.PHASE_TURNS:
		if event.is_action_pressed("jump") or event.is_action_pressed("fire"):
			if _item_target_mode != "":
				_item_target_mode = ""
				return
			director.request_roll()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("weapon_1") or event.is_action_pressed("weapon_2"):
			var lp := director.local_player()
			var idx := 0 if event.is_action_pressed("weapon_1") else 1
			if lp != null and idx < lp.items.size():
				var item := str(lp.items[idx])
				if item == "turbo":
					director.request_item(item, lp.peer_id)
				else:
					_item_target_mode = item
			get_viewport().set_input_as_handled()
		elif _item_target_mode != "" and (event.is_action_pressed("move_left") or event.is_action_pressed("move_right")):
			_cycle_target(-1 if event.is_action_pressed("move_left") else 1)
			get_viewport().set_input_as_handled()
	elif st.phase == BoardState.PHASE_CHOOSING:
		if event.is_action_pressed("move_left"):
			director.request_choose(0)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("move_right"):
			director.request_choose(1)
			get_viewport().set_input_as_handled()


var _target_index: int = 0


func _cycle_target(dir: int) -> void:
	var st := director.state
	var lp := director.local_player()
	var n := st.players.size()
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


func _input(event: InputEvent) -> void:
	if _item_target_mode != "" and event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		_confirm_target()


func _draw() -> void:
	if director == null or director.state == null:
		return
	var st := director.state
	var size := get_rect().size
	var ink := UiStyle.ink()
	var paper := UiStyle.paper()
	var accent := UiStyle.accent()
	# Turn strip
	var y := 30.0
	var lp := director.local_player()
	for i in st.players.size():
		var p := st.players[i]
		var col := Palette.player_colour(p.colour_index)
		var active := i == st.active
		var w := 380.0
		var h := 44.0
		var x := 24.0 + (14.0 if active else 0.0)
		var skew := 12.0
		var body := PackedVector2Array([Vector2(x + skew, y), Vector2(x + w, y), Vector2(x + w - skew, y + h), Vector2(x, y + h)])
		draw_colored_polygon(body, Color(ink, 0.9 if active else 0.7))
		draw_colored_polygon(PackedVector2Array([Vector2(x + skew, y), Vector2(x + skew + 34, y), Vector2(x + 34, y + h), Vector2(x, y + h)]), col)
		if active:
			draw_polyline(PackedVector2Array([Vector2(x + skew, y), Vector2(x + w, y), Vector2(x + w - skew, y + h), Vector2(x, y + h), Vector2(x + skew, y)]), accent, 3.0)
		_text(Vector2(x + 48, y + 29), p.display_name.to_upper(), 20, paper if p != lp else accent)
		_text(Vector2(x + 210, y + 29), "%d" % p.coins, 20, Palette.player_colour(3))
		_text(Vector2(x + 258, y + 29), "◆ %d" % p.bombas, 20, Palette.hud_colour("score"))
		var items := ""
		for it in p.items:
			items += str(it).substr(0, 1).to_upper()
		if items != "":
			_text(Vector2(x + 320, y + 29), items, 16, Palette.player_colour(5))
		y += h + 8.0
	# Round + goal
	_text(Vector2(size.x - 250, 52), "ROUND %d / %d" % [st.round, st.rounds], 26, paper)
	_text(Vector2(size.x - 250, 84), "GOAL COSTS %d" % int(director.cfg.get("goal_cost", 10)), 18, Palette.hud_colour("score"))
	# Dice
	if _dice_t > 0.0:
		var s := 120 + int(24.0 * clampf(_dice_t - 1.3, 0.0, 0.3) / 0.3)
		var txt := "%d" % _dice_value
		var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, s).x
		var c := Color(Palette.hud_colour("score"), clampf(_dice_t * 2.0, 0.0, 1.0))
		_text(Vector2((size.x - tw) * 0.5, size.y * 0.42), txt, s, c, 10.0, -0.22)
	# Prompt
	var prompt := ""
	var ap := st.active_player()
	if st.phase == BoardState.PHASE_TURNS:
		if director.is_local_turn():
			if _item_target_mode != "":
				var target := st.players[clampi(_target_index, 0, st.players.size() - 1)]
				prompt = "%s → %s   (A/D PICK · ENTER CONFIRM · SPACE CANCEL)" % [_item_target_mode.to_upper(), target.display_name.to_upper()]
			else:
				prompt = "YOUR TURN — SPACE TO ROLL"
				if lp != null and not lp.items.is_empty():
					prompt += "   ·   ITEMS: " + " ".join(range(lp.items.size()).map(func(i): return "%d:%s" % [i + 1, str(lp.items[i]).to_upper()]))
		elif ap != null:
			prompt = "%s IS ROLLING" % ap.display_name.to_upper()
	elif st.phase == BoardState.PHASE_CHOOSING:
		if director.is_local_turn():
			prompt = "◀ A        FORK        D ▶"
		elif ap != null:
			prompt = "%s IS CHOOSING" % ap.display_name.to_upper()
	elif st.phase == BoardState.PHASE_MINIGAME:
		prompt = "MINIGAME!"
	elif st.phase == BoardState.PHASE_FINISHED:
		prompt = "MATCH OVER"
	if prompt != "":
		var pw := _font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_CENTER, -1, 26).x
		var pc := accent if director.is_local_turn() else paper
		if _flash > 0.0:
			pc = pc.lerp(Color.WHITE, _flash * 0.6)
		_text(Vector2((size.x - pw) * 0.5, size.y - 60), prompt, 26, pc, 7.0)


func _text(pos: Vector2, text: String, size: int, col: Color, outline: float = 5.0, shear: float = -0.16) -> void:
	var ink := UiStyle.ink()
	ink.a = col.a
	draw_set_transform_matrix(Transform2D(Vector2(1.0, 0.0), Vector2(shear, 1.0), pos))
	draw_string_outline(_font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, int(outline), ink)
	draw_string(_font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	draw_set_transform_matrix(Transform2D())
