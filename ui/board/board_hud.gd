extends Control
## Board HUD in the menu language: turn strip (coins, Bombas, items; clickable as item targets),
## dice slam, prompts, intro and reward cards, and on-screen ROLL / fork / item buttons so a
## mouse works as well as the keys.

var director: BoardDirector
var _font: Font
var _dice_value: int = 0
var _dice_bonus: int = 0
var _dice_t: float = 0.0
var _fork_options: PackedStringArray = []
var _item_target_mode: String = ""
var _target_index: int = 0
var _flash: float = 0.0
var _intro: String = ""
var _intro_small: bool = false   # the round banner sits high and small, clear of the die number
var _intro_t: float = 0.0
var _reward_lines: Array = []
var _reward_t: float = 0.0
var _row_rects: Array = []
var _row_flash: Dictionary = {}
var _row_delta: Dictionary = {}   # peer → {delta, t}: the minigame reward beside the row
var _social_test_stage: int = 0
var _social_test_t: float = 0.0
var _last_round: int = 0
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
	director.social.connect(_on_social)
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
				_dice_bonus = int(e.get("bonus", 0))   # the number slams in when the die lands
			"choose":
				_fork_options.clear()
				for o in e["options"]:
					_fork_options.append(str(o))
			"turn":
				_fork_options.clear()
				_item_target_mode = ""
				_unhover()
				if director.state != null and director.state.round != _last_round:
					_last_round = director.state.round
					_intro = "ROUND %d / %d" % [director.state.round, director.state.rounds]
					_intro_small = true
					_intro_t = 1.3
				var lp := director.local_player()
				if lp != null and int(e["peer"]) == lp.peer_id:
					Audio.play("round_start", -8.0)
					_flash = 1.0
			"minigame":
				_intro = "NEXT UP:  %s" % str(e.get("display_name", "MINIGAME"))
				_intro_small = false
				_intro_t = 2.6
				_dice_t = 0.0
				Audio.play("round_end", -6.0)
			"coins":
				_row_flash[int(e["peer"])] = 1.0
				if e.has("rank"):
					rewards.append(e)
					_row_delta[int(e["peer"])] = {"delta": int(e["delta"]), "t": 3.2}
			"finished":
				_intro = "MATCH OVER"
				_intro_small = false
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
	for k in _row_flash.keys():
		_row_flash[k] = maxf(0.0, float(_row_flash[k]) - delta * 1.6)
	for k in _row_delta.keys():
		_row_delta[k]["t"] = float(_row_delta[k]["t"]) - delta
	if Game.args.has("social_test") and _social_test_stage < 2 and director != null and director.state != null and director.view != null and director.local_player() != null:
		# Harness: ping two spaces ahead, then emote half a second later (the rate limit allows
		# one social per 0.4 s), so a screenshot can catch both.
		_social_test_t += delta
		if _social_test_stage == 0 and _social_test_t > 0.3:
			_social_test_stage = 1
			# Through the real picker: the tile nearest the lower middle of the screen.
			var sid: String = director.view.tile_at_screen(get_viewport().get_visible_rect().size * Vector2(0.5, 0.82), 600.0)
			Log.info("board", "Social test: ping %s" % sid)
			if sid != "":
				director.send_ping(sid)
		elif _social_test_stage == 1 and _social_test_t > 0.9:
			_social_test_stage = 2
			director.send_emote("GG")
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
	var settled: bool = director.view == null or not director.view.has_method("is_animating") or not bool(director.view.is_animating())
	var mine: bool = st != null and director.is_local_turn() and settled
	var can_roll := mine and st.phase == BoardState.PHASE_TURNS and _item_target_mode == "" and director.local_player() != null and not director.local_player().is_bot
	_roll_btn.visible = can_roll
	_roll_btn.position = Vector2((size.x - _roll_btn.size.x) * 0.5, size.y - 160)
	var forking := mine and st.phase == BoardState.PHASE_CHOOSING and _fork_options.size() >= 2
	_fork_left.visible = forking
	_fork_right.visible = forking
	if forking and Game.args.has("hover_fork"):
		_hover_side(str(Game.args["hover_fork"]) == "left")
	if forking:
		# Out to the sides, near the path each one leads down; the pawn sits bottom-centre now
		# that the camera stands behind it at a fork.
		_fork_left.position = Vector2(size.x * 0.24 - _fork_left.size.x * 0.5, size.y * 0.56)
		_fork_right.position = Vector2(size.x * 0.76 - _fork_right.size.x * 0.5, size.y * 0.56)
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
	if director.view.has_method("highlight_path"):
		director.view.highlight_path(_preview_path(idx))


## The tiles the rest of this move would cover down option `idx` (steps_left counts the step
## onto the option itself). Later forks follow their first branch for the preview.
func _preview_path(idx: int) -> Array:
	var ids: Array = []
	if director.state == null or director.graph == null:
		return ids
	var cur := str(_fork_options[idx])
	ids.append(cur)
	for _k in range(1, maxi(director.state.steps_left, 1)):
		var nx := director.graph.next_of(cur)
		if nx.is_empty():
			break
		cur = str(nx[0])
		ids.append(cur)
	return ids


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


func _on_social(peer_id: int, kind: String, payload: String) -> void:
	Log.info("board", "Social: peer %d %s %s" % [peer_id, kind, payload])
	if director.view == null:
		return
	if kind == "ping":
		director.view.show_ping(peer_id, payload)
		Audio.play("ping", -6.0)
	elif kind == "emote":
		director.view.show_emote(peer_id, payload)
		Audio.play("emote", -6.0)


func _unhandled_input(event: InputEvent) -> void:
	if director == null or not is_instance_valid(director) or not director.is_inside_tree() or director.state == null:
		return
	# Pings and emotes work on anyone's turn.
	if event.is_action_pressed("ping"):
		if director.view != null and director.view.has_method("tile_at_screen"):
			var sid: String = director.view.tile_at_screen(get_viewport().get_mouse_position())
			if sid != "":
				director.send_ping(sid)
		get_viewport().set_input_as_handled()
		return
	for k in BoardDirector.EMOTES.size():
		if event.is_action_pressed("emote_%d" % (k + 1)):
			director.send_emote(BoardDirector.EMOTES[k])
			get_viewport().set_input_as_handled()
			return
	if not director.is_local_turn():
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
		var w := 480.0
		var h := 44.0
		var x := 24.0 + (14.0 if active else 0.0)
		var skew := 12.0
		_row_rects.append(Rect2(x, y, w, h))
		var flash: float = float(_row_flash.get(p.peer_id, 0.0))
		draw_colored_polygon(PackedVector2Array([Vector2(x + skew, y), Vector2(x + w, y), Vector2(x + w - skew, y + h), Vector2(x, y + h)]), Color(ink, 0.9 if active else 0.7).lerp(Color(paper, 0.9), flash * 0.6))
		draw_colored_polygon(PackedVector2Array([Vector2(x + skew, y), Vector2(x + skew + 34, y), Vector2(x + 34, y + h), Vector2(x, y + h)]), col)
		if active or targeted:
			draw_polyline(PackedVector2Array([Vector2(x + skew, y), Vector2(x + w, y), Vector2(x + w - skew, y + h), Vector2(x, y + h), Vector2(x + skew, y)]), Palette.hud_colour("danger") if targeted else accent, 3.0)
		_text(Vector2(x + 48, y + 29), p.display_name.to_upper(), 20, paper if p != lp else accent)
		_text(Vector2(x + 220, y + 29), "%d" % p.coins, 20, Palette.player_colour(3))
		_text(Vector2(x + 268, y + 29), "● %d" % p.toys, 20, Palette.hud_colour("score"))
		# Steps to the vending machine, so everyone can plan; the leader's distance is what matters.
		if st.goal != "" and director.graph != null:
			var d := director.graph.distance(p.space, st.goal)
			if d >= 0:
				_text(Vector2(x + 325, y + 29), "%d TO ●" % d, 14, Color(paper, 0.85))
		var chips := ""
		for it in p.items:
			chips += str(it).substr(0, 2).to_upper() + " "
		if chips != "":
			_text(Vector2(x + 396, y + 29), chips.strip_edges(), 14, Palette.player_colour(5))
		if not active and st.players.size() > 1 and i == (st.active + 1) % st.players.size() and st.phase != BoardState.PHASE_FINISHED:
			_text(Vector2(x + w - 62, y + 27), "NEXT", 13, Color(accent, 0.9))
		if _row_delta.has(p.peer_id) and float(_row_delta[p.peer_id]["t"]) > 0.0:
			# The minigame reward, beside the row, drifting up and fading with the reward card.
			var rt: float = _row_delta[p.peer_id]["t"]
			var rd: int = _row_delta[p.peer_id]["delta"]
			var ra := clampf(rt * 1.5, 0.0, 1.0)
			_text(Vector2(x + w + 14, y + 31 - (3.2 - rt) * 4.0), ("+%d" if rd >= 0 else "%d") % rd, 26, Color(Palette.player_colour(3), ra), 6.0)
		y += h + 8.0
	_draw_name_tags(st)
	_text(Vector2(size.x - 250, 52), "ROUND %d / %d" % [mini(st.round, st.rounds), st.rounds], 26, paper)
	var to_win := int(director.cfg.get("toys_to_win", 4))
	_text(Vector2(size.x - 250, 84), "TOY COSTS %d%s" % [int(director.cfg.get("toy_price", 10)), ("  ·  FIRST TO %d" % to_win) if to_win > 0 else ""], 18, Palette.hud_colour("score"))
	_text(Vector2(size.x - 250, 112), "HOLD TAB · MAP", 14, Color(paper, 0.7))
	_text(Vector2(size.x - 250, 134), "E · PING    F1-F4 · EMOTE", 14, Color(paper, 0.7))
	if _dice_t > 0.0:
		var s := 120 + int(24.0 * clampf(_dice_t - 1.3, 0.0, 0.3) / 0.3)
		var txt := "%d" % _dice_value if _dice_bonus <= 0 else "%d +%d" % [_dice_value - _dice_bonus, _dice_bonus]
		var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, s).x
		# Over the die, which lands to the camera's right of the pawn, clear of the name tags.
		_text(Vector2(size.x * 0.61 - tw * 0.5, size.y * 0.36), txt, s, Color(Palette.hud_colour("score"), clampf(_dice_t * 2.0, 0.0, 1.0)), 10.0, -0.22)
	if _intro_t > 0.0:
		var a := clampf(_intro_t * 1.5, 0.0, 1.0)
		var fs := 38 if _intro_small else 54
		var cy := size.y * (0.16 if _intro_small else 0.30)
		var tw := _font.get_string_size(_intro, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		_card(Vector2((size.x - tw) * 0.5 - 40, cy - fs * 0.95), Vector2(tw + 80, fs * 1.7), a)
		_text(Vector2((size.x - tw) * 0.5, cy + fs * 0.3), _intro, fs, Color(accent, a), 8.0)
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
				var left := director.turn_seconds_left()
				if left >= 0.0 and left <= 10.0:
					prompt = "YOUR TURN   ·   AUTO-ROLL IN %d" % ceili(left)
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


## Name tags over the pawns, projected from the 3D view and pushed apart when they would
## overprint (pawns share tiles; depth makes a fixed lift useless). The active player's tag is
## in the accent colour; far pawns get smaller type.
func _draw_name_tags(st: BoardState) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or director.view == null or not director.view.has_method("pawn_tag_anchor"):
		return
	var tags: Array = []
	for i in st.players.size():
		var p := st.players[i]
		var a: Vector3 = director.view.pawn_tag_anchor(p.peer_id)
		if a == Vector3.INF or cam.is_position_behind(a):
			continue
		var sp := cam.unproject_position(a)
		var dist := cam.global_position.distance_to(a)
		var fs := clampi(int(230.0 / maxf(dist, 1.0)), 12, 22)
		var text := p.display_name.to_upper()
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		tags.append({"pos": sp, "size": fs, "text": text, "w": w, "active": i == st.active,
			"col": Palette.player_colour(p.colour_index)})
	tags.sort_custom(func(a, b): return a["pos"].y < b["pos"].y)
	# Push the upper tag of any overlapping pair further up, a few passes.
	for _pass in 4:
		for i in range(1, tags.size()):
			for j in i:
				var upper: Dictionary = tags[j]
				var lower: Dictionary = tags[i]
				var ux: float = upper["pos"].x
				var lx: float = lower["pos"].x
				if absf(ux - lx) < (float(upper["w"]) + float(lower["w"])) * 0.5 + 10.0:
					var gap := (float(upper["size"]) + float(lower["size"])) * 0.5 + 8.0
					if float(lower["pos"].y) - float(upper["pos"].y) < gap:
						upper["pos"] = Vector2(ux, float(lower["pos"].y) - gap)
	# The player rows own the top-left; a tag that would print over them (a pawn under that
	# corner of the screen, seen at 1080p) drops just below the panel instead.
	var panel := Rect2()
	for r in _row_rects:
		panel = r.grow(8.0) if panel.size == Vector2.ZERO else panel.merge(r.grow(8.0))
	for t in tags:
		var pos: Vector2 = t["pos"]
		var w := float(t["w"])
		var fs := int(t["size"])
		if panel.size != Vector2.ZERO and panel.intersects(Rect2(pos.x - w * 0.5, pos.y - fs, w, fs + 4.0)):
			pos.y = panel.end.y + fs + 4.0
		var col: Color = UiStyle.accent() if bool(t["active"]) else Color(t["col"]).lightened(0.35)
		_text(Vector2(pos.x - w * 0.5, pos.y), str(t["text"]), fs, col, 4.0, -0.12)


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
