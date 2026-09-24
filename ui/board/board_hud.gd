extends Control
## Board HUD in the menu language: turn strip (tickets, Bombas, items; clickable as item targets),
## dice slam, prompts, intro and reward cards, and on-screen ROLL / fork / item buttons so a
## mouse works as well as the keys.

var director: BoardDirector
var _font: Font
var _dice_value: int = 0
var _dice_t: float = 0.0
var _fork_options: PackedStringArray = []
var _shuttle_offer: bool = false     # the choice on offer is the rocket (stay or fly), not a fork
var _shuttle_price: int = 10
var _item_target_mode: String = ""
var _aim_item: String = "laser"   # what the aim mode is for: the laser's beam or the bomb's throw
var _hint: String = ""             # a short line under the bar (NOBODY IN RANGE)
var _hint_t: float = 0.0
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
# The item hotbar (Sean): Q opens it on your turn, 1–9 or the wheel pick a slot, E uses it;
# the laser then aims with the mouse and fires on a click.
var _hotbar_open: bool = false
var _hotbar_sel: int = 0
var _hotbar_rects: Array = []
var _aiming: bool = false
var _item_pops: Array = []   # [{peer, item, t}]: an item's icon rising over the pawn that picked it up
var _turn_pops: Dictionary = {}   # peer → item: a minigame reward waiting for that player's turn
var _turn_shown_for: int = 0      # whose turn the view last showed
var _test_done: bool = false
var _pop_test_done: bool = false
var _pop_test_t: float = 0.0


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


func attach(p_director: BoardDirector) -> void:
	director = p_director
	director.state_changed.connect(_on_state)
	director.events_received.connect(_on_events)
	director.social.connect(_on_social)
	Events.board_dice_landed.connect(func(v: int):
		_dice_value = v
		_dice_t = 1.3
	)
	Events.board_item_picked.connect(func(peer_id: int, item: String, at_turn: bool):
		if at_turn:
			# A minigame reward: shown when that player's turn comes (Sean). The reward's turn
			# event follows the item in the same batch, and the winner rolls first now, so it
			# usually comes a fraction of a second later; if that turn was already shown (the
			# view plays the turn ahead of the item pop on a rebuilt board), pop it now.
			if _turn_shown_for == peer_id:
				_item_pops.append({"peer": peer_id, "item": item, "t": 2.4, "life": 2.4, "rise": 0.1})
			else:
				_turn_pops[peer_id] = item
		else:
			_item_pops.append({"peer": peer_id, "item": item, "t": 1.6})
	)
	Events.board_turn_shown.connect(func(peer_id: int):
		_turn_shown_for = peer_id
		if _turn_pops.has(peer_id):
			_item_pops.append({"peer": peer_id, "item": str(_turn_pops[peer_id]), "t": 2.4, "life": 2.4, "rise": 0.1})
			_turn_pops.erase(peer_id)
	)


func _on_events(events: Array) -> void:
	var rewards := []
	for e in events:
		match str(e.get("kind", "")):
			"choose":
				_fork_options.clear()
				for o in e["options"]:
					_fork_options.append(str(o))
				_shuttle_offer = bool(e.get("shuttle", false))
				_shuttle_price = int(e.get("price", 10))
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
					_flash = 1.0
			"minigame":
				_intro = "NEXT UP:  %s" % str(e.get("display_name", "MINIGAME"))
				_intro_small = false
				_intro_t = 2.6
				_dice_t = 0.0
				_turn_shown_for = 0   # the next turn shown is the round's first, after the reward
			"laser":
				for h in e.get("hits", []):
					_row_flash[int(h["peer"])] = 1.0
			"bomb":
				for h in e.get("hits", []):
					_row_flash[int(h["peer"])] = 1.0
			"claw":
				if int(e.get("target", 0)) != 0:
					_row_flash[int(e["target"])] = 1.0
			"tickets", "heal":
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
	for i in range(_item_pops.size() - 1, -1, -1):
		_item_pops[i]["t"] = float(_item_pops[i]["t"]) - delta
		if float(_item_pops[i]["t"]) <= 0.0:
			_item_pops.remove_at(i)
	_layout_buttons()
	if Game.args.has("pop_test") and not _pop_test_done and director != null and director.local_player() != null:
		# Harness: a bomb icon pops over the local pawn 3 s in, for a screenshot of the pickup pop.
		_pop_test_t += delta
		if _pop_test_t > 3.0:
			_pop_test_done = true
			_item_pops.append({"peer": director.local_player().peer_id, "item": str(Game.args["pop_test"]), "t": 1.6})
	if Game.args.has("target_test") and not _test_done and _can_use_items():
		# Harness: the portal's target mode open (the camera on the first target) for a screenshot.
		var lp := director.local_player()
		if lp != null and lp.items.has("portal"):
			_test_done = true
			_use_item_index(lp.items.find("portal"))
	if Game.args.has("hotbar_test") and not _hotbar_open and not _aiming and _can_use_items():
		# Harness: the bar open on the laser slot (or the first item) for a screenshot.
		var lp := director.local_player()
		if lp != null and not lp.items.is_empty():
			_hotbar_sel = maxi(0, lp.items.find("laser"))
			_hotbar_open = true
	if Game.args.has("aim_test") and not _aiming and _can_use_items():
		# Harness: the laser drawn at a fixed angle (degrees) for a screenshot.
		var lp := director.local_player()
		if lp != null and lp.items.has("laser"):
			_begin_aim()
	if Game.args.has("claw_test") and not _aiming and _can_use_items():
		# Harness: the claw aimed at a fixed angle (degrees) for a screenshot.
		var lp := director.local_player()
		if lp != null and lp.items.has("claw"):
			_begin_aim("claw")
	if Game.args.has("throw_test") and not _aiming and _can_use_items():
		# Harness: the bomb's throw aimed at a fixed angle (degrees) for a screenshot.
		var lp := director.local_player()
		if lp != null and lp.items.has("bomb"):
			_begin_throw()
	_hint_t = maxf(0.0, _hint_t - delta)
	queue_redraw()


func _layout_buttons() -> void:
	var size := get_rect().size
	if director == null or not is_instance_valid(director) or not director.is_inside_tree():
		_roll_btn.visible = false
		_fork_left.visible = false
		_fork_right.visible = false
		return
	var st := director.state
	var settled: bool = director.view == null or not director.view.has_method("is_animating") or not bool(director.view.is_animating())
	var mine: bool = st != null and director.is_local_turn() and settled
	var can_roll := mine and st.phase == BoardState.PHASE_TURNS and _item_target_mode == "" and director.local_player() != null and not director.local_player().is_bot
	_roll_btn.visible = can_roll and not _aiming
	_roll_btn.position = Vector2((size.x - _roll_btn.size.x) * 0.5, size.y - 160)
	var forking := mine and st.phase == BoardState.PHASE_CHOOSING and _fork_options.size() >= 2
	_fork_left.visible = forking
	_fork_right.visible = forking
	if forking and Game.args.has("hover_fork"):
		_hover_side(str(Game.args["hover_fork"]) == "left")
	if forking:
		# The rocket's offer wears its own labels; a fork keeps LEFT and RIGHT.
		_fork_left.text = "NO THANKS" if _shuttle_offer else "◀  LEFT"
		_fork_right.text = ("TAKE THE ROCKET  ·  %d TICKETS  ▶" % _shuttle_price) if _shuttle_offer else "RIGHT  ▶"
		# Out to the sides, near the path each one leads down; the pawn sits bottom-centre now
		# that the camera stands behind it at a fork.
		_fork_left.position = Vector2(size.x * 0.24 - _fork_left.size.x * 0.5, size.y * 0.56)
		_fork_right.position = Vector2(size.x * 0.76 - _fork_right.size.x * 0.5, size.y * 0.56)


## A state landed: the hotbar and the aim only live on the local player's own turn.
func _on_state(_st: BoardState) -> void:
	if director == null or not director.is_local_turn():
		_hotbar_open = false
		_end_aim()
	var lp := director.local_player() if director != null else null
	if lp != null and _hotbar_sel >= lp.items.size():
		_hotbar_sel = maxi(0, lp.items.size() - 1)


## Items can be used on the local player's turn, before the roll, once the view has settled.
func _can_use_items() -> bool:
	if director == null or not is_instance_valid(director) or not director.is_inside_tree() or director.state == null:
		return false
	var st := director.state
	var lp := director.local_player()
	var settled: bool = director.view == null or not director.view.has_method("is_animating") or not bool(director.view.is_animating())
	return lp != null and not lp.is_bot and director.is_local_turn() and settled and st.phase == BoardState.PHASE_TURNS and st.dice == 0 and _item_target_mode == ""


func _toggle_hotbar() -> void:
	if _aiming:
		_end_aim()
		return
	_hotbar_open = not _hotbar_open and _can_use_items()
	if _hotbar_open:
		Audio.play("ui_click", -6.0)


## Slot `i` (0-based) opens the bar on it when it holds an item.
func _select_slot(i: int) -> void:
	var lp := director.local_player()
	if lp == null or i < 0 or i >= lp.items.size() or not _can_use_items():
		return
	_hotbar_sel = i
	_hotbar_open = true
	Audio.play("ui_hover", -8.0)


func _cycle_slot(dir: int) -> void:
	var lp := director.local_player()
	if lp == null or lp.items.is_empty():
		return
	_hotbar_sel = posmod(_hotbar_sel + dir, lp.items.size())
	Audio.play("ui_hover", -8.0)


func _use_selected() -> void:
	if not _hotbar_open or not _can_use_items():
		return
	_use_item_index(_hotbar_sel)


## The laser, or the claw: the view turns the pawn with the mouse and shows the line; a click
## fires or grabs.
func _begin_aim(kind: String = "laser") -> void:
	var lp := director.local_player()
	if lp == null or director.view == null or not director.view.has_method("begin_aim"):
		return
	_aiming = true
	_aim_item = kind
	_hotbar_open = false
	var length := BoardRules.claw_length(director.graph, director.cfg) if kind == "claw" else BoardRules.laser_length(director.graph, director.cfg)
	director.view.begin_aim(lp.peer_id, length, kind)


## The bomb: a ring of range round the pawn, a reticle the size of the blast under the mouse; a
## click throws it there.
func _begin_throw() -> void:
	var lp := director.local_player()
	if lp == null or director.view == null or not director.view.has_method("begin_throw"):
		return
	_aiming = true
	_aim_item = "bomb"
	_hotbar_open = false
	director.view.begin_throw(lp.peer_id, BoardRules.bomb_range(director.graph, director.cfg), BoardRules.bomb_radius(director.graph, director.cfg))


func _end_aim() -> void:
	if not _aiming:
		return
	_aiming = false
	if director != null and director.view != null and director.view.has_method("end_aim"):
		director.view.end_aim()


func _fire() -> void:
	if not _aiming or director.view == null:
		return
	if _aim_item == "bomb":
		var p: Vector3 = director.view.throw_point()
		_end_aim()
		director.request_item("bomb", 0, {"x": snappedf(p.x, 0.01), "z": snappedf(p.z, 0.01)})
		return
	var aim: float = director.view.aim_angle()
	var kind := _aim_item
	_end_aim()
	director.request_item(kind, 0, {"aim": snappedf(aim, 0.001)})


## Options are space ids; map LEFT/RIGHT by where the tiles sit on screen.
func _side_index(left: bool) -> int:
	if _fork_options.size() < 2:
		return 0
	if _shuttle_offer:
		return 0 if left else 1   # stay on the left, fly on the right
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
	_hotbar_open = false
	_end_aim()
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
		"shield":
			pass
		"laser":
			_begin_aim()
		"bomb":
			_begin_throw()
		"claw":
			_begin_aim("claw")
		_:
			_hotbar_open = false
			_item_target_mode = item
			_target_index = 0
			_cycle_target(0)


## Whether row `i` can be the target of the item being aimed: never yourself.
func _target_ok(i: int) -> bool:
	var st := director.state
	var lp := director.local_player()
	if i < 0 or i >= st.players.size() or st.players[i] == lp:
		return false
	return true


func _cycle_target(dir: int) -> void:
	var st := director.state
	var n := st.players.size()
	if dir == 0:
		for i in n:
			if _target_ok(i):
				_target_index = i
				break
	else:
		for i in n:
			_target_index = posmod(_target_index + dir, n)
			if _target_ok(_target_index):
				break
	_focus_target()


## The camera goes to whoever is targeted (Sean: A/D switch targets and the camera follows).
func _focus_target() -> void:
	var st := director.state
	if director.view != null and director.view.has_method("focus_peer") and _target_index < st.players.size():
		director.view.focus_peer(st.players[_target_index].peer_id)


## Back to your own pawn when the target mode ends.
func _refocus_local() -> void:
	var lp := director.local_player()
	if lp != null and director.view != null and director.view.has_method("focus_peer"):
		director.view.focus_peer(lp.peer_id)


func _cancel_target() -> void:
	if _item_target_mode == "":
		return
	_item_target_mode = ""
	_refocus_local()


func _confirm_target() -> void:
	var st := director.state
	if _item_target_mode == "" or _target_index >= st.players.size():
		return
	director.request_item(_item_target_mode, st.players[_target_index].peer_id)
	_item_target_mode = ""
	_refocus_local()


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
	# Aiming the laser: a click fires, right click / Q / Esc put it away; nothing else gets through.
	if _aiming:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_fire()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_end_aim()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("inventory") or event.is_action_pressed("pause"):
			_end_aim()
			get_viewport().set_input_as_handled()
		return
	# The item hotbar: Q opens it on your turn, 1–9 or the wheel pick a slot, E uses it.
	if event.is_action_pressed("inventory"):
		_toggle_hotbar()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and _can_use_items():
		var kc: int = event.keycode if event.keycode != 0 else event.physical_keycode
		if kc >= KEY_1 and kc <= KEY_9:
			_select_slot(kc - KEY_1)
			get_viewport().set_input_as_handled()
			return
	if _hotbar_open and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_slot(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			for i in _hotbar_rects.size():
				if (_hotbar_rects[i] as Rect2).has_point(event.position):
					_hotbar_sel = i
					_use_selected()
					get_viewport().set_input_as_handled()
					return
	# Pings and emotes work on anyone's turn; E uses the selected item while the bar is open.
	if event.is_action_pressed("ping"):
		if _hotbar_open:
			_use_selected()
		elif director.view != null and director.view.has_method("tile_at_screen"):
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
			if (_row_rects[i] as Rect2).has_point(event.position) and _target_ok(i):
				_target_index = i
				_confirm_target()
				get_viewport().set_input_as_handled()
				return
	var free_ok := st.phase == BoardState.PHASE_TURNS and _item_target_mode == "" and director.view != null and director.view.has_method("toggle_free_cam")
	if free_ok and event.is_action_pressed("reload"):
		# R (the reload key, idle on the board) toggles the free camera on your turn (Sean, 2026-09-24).
		director.view.toggle_free_cam()
		get_viewport().set_input_as_handled()
		return
	if st.phase == BoardState.PHASE_TURNS:
		if event.is_action_pressed("jump"):
			if _item_target_mode != "":
				_cancel_target()
			elif _hotbar_open:
				_hotbar_open = false
			else:
				_roll()
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
		var w := 500.0   # was 600: the steps to the machine are gone (Sean, 2026-09-24)
		var h := 44.0
		var x := 24.0 + (14.0 if active else 0.0)
		var skew := 12.0
		_row_rects.append(Rect2(x, y, w, h))
		var flash: float = float(_row_flash.get(p.peer_id, 0.0))
		draw_colored_polygon(PackedVector2Array([Vector2(x + skew, y), Vector2(x + w, y), Vector2(x + w - skew, y + h), Vector2(x, y + h)]), Color(ink, 0.9 if active else 0.7).lerp(Color(paper, 0.9), flash * 0.6))
		draw_colored_polygon(PackedVector2Array([Vector2(x + skew, y), Vector2(x + skew + 34, y), Vector2(x + 34, y + h), Vector2(x, y + h)]), col)
		if active or targeted:
			draw_polyline(PackedVector2Array([Vector2(x + skew, y), Vector2(x + w, y), Vector2(x + w - skew, y + h), Vector2(x, y + h), Vector2(x + skew, y)]), Palette.hud_colour("danger") if targeted else accent, 3.0)
		_text(Vector2(x + 48, y + 29), p.display_name.to_upper(), 18, paper if p != lp else accent)
		# Tickets (Sean: arcade tickets, not coins): a stub before the count. The name gets 180 px
		# (BOT TANGERINE at 18 px is 160); the steps to the machine are gone (Sean, 2026-09-24:
		# "you don't need to put '41 to'").
		_ticket_icon(Vector2(x + 240, y + 21), 1.0, ink)
		_text(Vector2(x + 256, y + 29), "%d" % p.tickets, 20, Palette.player_colour(3))
		_text(Vector2(x + 300, y + 29), "● %d" % p.toys, 20, Palette.hud_colour("score"))
		# HP: a small shaped bar, cyan while healthy and the danger red once a laser would finish it.
		var hp_max := maxi(1, int(director.cfg.get("hp", 30)))
		var hp_f := clampf(float(p.hp) / float(hp_max), 0.0, 1.0)
		var hx := x + 340.0
		var hy := y + 17.0
		draw_colored_polygon(PackedVector2Array([Vector2(hx + 3, hy), Vector2(hx + 57, hy), Vector2(hx + 54, hy + 9), Vector2(hx, hy + 9)]), Color(paper, 0.22))
		if hp_f > 0.0:
			var hw := 54.0 * hp_f
			draw_colored_polygon(PackedVector2Array([Vector2(hx + 3, hy), Vector2(hx + 3 + hw, hy), Vector2(hx + hw, hy + 9), Vector2(hx, hy + 9)]),
				Palette.hud_colour("danger") if hp_f <= 0.34 else Palette.hud_colour("meter"))
		_text(Vector2(x + 402, y + 29), "%d" % p.hp, 14, Color(paper, 0.9))
		var chips := ""
		for it in p.items:
			chips += str(it).substr(0, 2).to_upper() + " "
		if chips != "":
			_text(Vector2(x + 466, y + 29), chips.strip_edges(), 14, Palette.player_colour(5))
		if not active and st.players.size() > 1 and i == (st.active + 1) % st.players.size() and st.phase != BoardState.PHASE_FINISHED:
			_text(Vector2(x + 428, y + 27), "NEXT", 13, Color(accent, 0.9))
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
	_text(Vector2(size.x - 250, 112), "HOLD TAB · MAP    R · FREE CAM", 14, Color(paper, 0.7))
	_text(Vector2(size.x - 250, 134), "Q · ITEMS    E · PING    F1-F4 · EMOTE", 14, Color(paper, 0.7))
	_draw_hotbar(lp, size)
	_draw_item_pops()
	if _dice_t > 0.0:
		var s := 120 + int(24.0 * clampf(_dice_t - 1.3, 0.0, 0.3) / 0.3)
		var txt := "%d" % _dice_value
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
			if _aiming:
				var verb := "THROW" if _aim_item == "bomb" else ("GRAB" if _aim_item == "claw" else "FIRE")
				prompt = "AIM WITH THE MOUSE   ·   CLICK TO %s   ·   RIGHT CLICK PUTS IT AWAY" % verb
			elif _item_target_mode != "":
				var target := st.players[clampi(_target_index, 0, st.players.size() - 1)]
				prompt = "%s → %s   ·   CLICK A PLAYER OR A/D + ENTER   ·   SPACE CANCELS" % [_item_target_mode.to_upper(), target.display_name.to_upper()]
			else:
				prompt = "YOUR TURN"
				var left := director.turn_seconds_left()
				if left >= 0.0 and left <= 10.0:
					prompt = "YOUR TURN   ·   AUTO-ROLL IN %d" % ceili(left)
				if director.view != null and director.view.has_method("free_cam") and bool(director.view.free_cam()):
					prompt = "FREE CAM   ·   WASD MOVE   ·   R BACK   ·   SPACE ROLLS"
		elif ap != null:
			prompt = "%s IS ROLLING" % ap.display_name.to_upper()
	elif st.phase == BoardState.PHASE_CHOOSING:
		if _shuttle_offer:
			prompt = ("TAKE THE ROCKET FOR %d TICKETS?" % _shuttle_price) if director.is_local_turn() else "%s IS AT THE ROCKET" % (ap.display_name.to_upper() if ap != null else "")
		else:
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


## The item hotbar: nine angled slots above the ROLL button, the held items drawn as icons, the
## selected one lifted and outlined in the accent colour with its name over it (STYLE.md §5:
## shaped, edge-anchored, no boxes).
func _draw_hotbar(lp: BoardState.PlayerState, size: Vector2) -> void:
	_hotbar_rects.clear()
	if not _hotbar_open or lp == null or not _can_use_items():
		return
	var ink := UiStyle.ink()
	var paper := UiStyle.paper()
	var accent := UiStyle.accent()
	var n := 9
	var slot := 60.0
	var gap := 8.0
	var skew := 10.0
	var total := n * slot + (n - 1) * gap
	var x0 := (size.x - total) * 0.5
	var y0 := size.y - 300.0
	var defs: Dictionary = director.cfg.get("items", {})
	for i in n:
		var x := x0 + i * (slot + gap)
		var has := i < lp.items.size()
		var sel := has and i == _hotbar_sel
		var y := y0 - (8.0 if sel else 0.0)
		_hotbar_rects.append(Rect2(x, y, slot, slot))
		var poly := PackedVector2Array([Vector2(x + skew, y), Vector2(x + slot, y), Vector2(x + slot - skew, y + slot), Vector2(x, y + slot)])
		draw_colored_polygon(poly, Color(ink, 0.88 if has else 0.45))
		if sel:
			draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]]), accent, 3.0)
		_text(Vector2(x + 14, y + 16), "%d" % (i + 1), 12, Color(paper, 0.7 if has else 0.35), 3.0)
		if has:
			var item := str(lp.items[i])
			_draw_item_icon(item, Vector2(x + slot * 0.5, y + slot * 0.56), 15.0)
			if sel:
				var def: Dictionary = defs.get(item, {})
				var label: String = str(def.get("display_name", item.to_upper()))
				var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 22).x
				_text(Vector2(x + slot * 0.5 - tw * 0.5, y - 14), label, 22, accent, 6.0)
	var hint := "Q · CLOSE     1-9 / WHEEL · SELECT     E · USE"
	var hw := _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x
	_text(Vector2((size.x - hw) * 0.5, y0 + slot + 24), hint, 14, Color(paper, 0.75))
	if _hint_t > 0.0:
		var hint_w := _font.get_string_size(_hint, HORIZONTAL_ALIGNMENT_CENTER, -1, 20).x
		_text(Vector2((size.x - hint_w) * 0.5, y0 - 34), _hint, 20, Color(Palette.hud_colour("danger"), clampf(_hint_t * 2.0, 0.0, 1.0)), 5.0)


## A picked-up item pops as its icon over the pawn's head (Sean: an icon, not the name): a
## sticker plate that scales in, rises and fades, projected from the pawn like the name tags.
func _draw_item_pops() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or director.view == null or not director.view.has_method("pawn_tag_anchor"):
		return
	for pop in _item_pops:
		var a: Vector3 = director.view.pawn_tag_anchor(int(pop["peer"]))
		if a == Vector3.INF or cam.is_position_behind(a):
			continue
		var t: float = pop["t"]
		var age := float(pop.get("life", 1.6)) - t
		var grow := clampf(age / 0.14, 0.0, 1.0)
		var scale := 1.0 + 0.35 * sin(grow * PI)   # a little overshoot as it lands
		var alpha := clampf(t / 0.35, 0.0, 1.0)
		# A pickup drifts up 0.35 m/s; the longer reward pop at a turn only 0.1, so it stays
		# over the head while the player rolls.
		var sp := cam.unproject_position(a + Vector3(0, 0.55 + age * float(pop.get("rise", 0.35)), 0))
		var r := 34.0 * scale * grow
		draw_circle(sp, r + 4.0, Color(UiStyle.accent(), alpha))
		draw_circle(sp, r, Color(UiStyle.ink(), 0.92 * alpha))
		_draw_item_icon(str(pop["item"]), sp + Vector2(0, 2), 16.0 * scale * grow, alpha)


## Drawn item icons, `s` about half the icon's width (Sean: more detail). Every one is inked, with
## a shine or a band so it reads at hotbar size and in the pickup pop: a ray pistol with a slide
## band, a grip inset and a lit emitter; a bomb with a cap, a rope fuse and a spark; an oval portal
## with a swirl and sparks; a shield with a rim band and a boss; the claw with its cable and spool.
func _draw_item_icon(kind: String, c: Vector2, s: float, alpha: float = 1.0) -> void:
	var ink := Color(UiStyle.ink(), alpha)
	var paper := Color(Palette.hud_colour("paper"), alpha)
	var danger := Color(Palette.hud_colour("danger"), alpha)
	var score := Color(Palette.hud_colour("score"), alpha)
	match kind:
		"laser":
			var body := PackedVector2Array([c + Vector2(-s, -s * 0.45), c + Vector2(s * 0.85, -s * 0.45), c + Vector2(s * 0.85, s * 0.05),
				c + Vector2(-s * 0.15, s * 0.05), c + Vector2(-s * 0.3, s * 0.9), c + Vector2(-s * 0.9, s * 0.9), c + Vector2(-s * 0.75, s * 0.05), c + Vector2(-s, s * 0.05)])
			_icon_poly(body, paper, ink, c)
			draw_rect(Rect2(c + Vector2(-s * 0.9, -s * 0.38), Vector2(s * 1.35, s * 0.15)), Color(ink, alpha * 0.5))
			draw_rect(Rect2(c + Vector2(-s * 0.72, s * 0.22), Vector2(s * 0.3, s * 0.5)), Color(ink, alpha * 0.5))
			draw_rect(Rect2(c + Vector2(-s * 0.05, -s * 0.2), Vector2(s * 0.5, s * 0.08)), Color(ink, alpha * 0.35))
			draw_circle(c + Vector2(s * 0.92, -s * 0.2), s * 0.26, ink)
			draw_circle(c + Vector2(s * 0.92, -s * 0.2), s * 0.17, danger)
			draw_line(c + Vector2(s * 1.18, -s * 0.2), c + Vector2(s * 1.55, -s * 0.2), danger, 3.0)
			draw_circle(c + Vector2(s * 1.6, -s * 0.2), s * 0.1, danger)
		"bomb":
			var centre := c + Vector2(0, s * 0.22)
			draw_circle(centre, s * 0.8, ink)
			draw_circle(centre, s * 0.68, Color(UiStyle.ink().lightened(0.22), alpha))
			draw_circle(centre + Vector2(-s * 0.24, -s * 0.26), s * 0.17, Color(paper, alpha * 0.75))
			draw_rect(Rect2(centre + Vector2(-s * 0.17, -s * 0.92), Vector2(s * 0.34, s * 0.24)), ink)
			draw_rect(Rect2(centre + Vector2(-s * 0.1, -s * 0.88), Vector2(s * 0.2, s * 0.14)), Color(paper, alpha * 0.6))
			draw_line(centre + Vector2(0, -s * 0.88), centre + Vector2(s * 0.3, -s * 1.16), ink, 5.5)
			draw_line(centre + Vector2(s * 0.3, -s * 1.16), centre + Vector2(s * 0.58, -s * 1.1), ink, 5.5)
			draw_line(centre + Vector2(0, -s * 0.88), centre + Vector2(s * 0.3, -s * 1.16), paper, 3.0)
			draw_line(centre + Vector2(s * 0.3, -s * 1.16), centre + Vector2(s * 0.58, -s * 1.1), paper, 3.0)
			_icon_spark(centre + Vector2(s * 0.74, -s * 1.16), s * 0.24, score, paper)
		"portal":
			var col := Color(Palette.player_colour(5), alpha)
			draw_set_transform(c, 0.0, Vector2(0.72, 1.0))
			draw_arc(Vector2.ZERO, s * 0.9, 0.0, TAU, 40, ink, 7.0)
			draw_circle(Vector2.ZERO, s * 0.72, Color(col.darkened(0.55), alpha * 0.95))
			draw_arc(Vector2.ZERO, s * 0.9, 0.0, TAU, 40, col, 4.0)
			draw_arc(Vector2.ZERO, s * 0.46, 0.5, 3.9, 18, col, 3.0)
			draw_arc(Vector2.ZERO, s * 0.24, 2.8, 6.4, 14, Color(col.lightened(0.3), alpha), 2.5)
			draw_set_transform_matrix(Transform2D())
			_icon_spark(c + Vector2(s * 0.78, -s * 0.78), s * 0.13, paper, paper)
			_icon_spark(c + Vector2(-s * 0.72, s * 0.62), s * 0.1, paper, paper)
		"shield":
			var meter := Color(Palette.hud_colour("meter"), alpha)
			var shape := PackedVector2Array([c + Vector2(-s * 0.85, -s * 0.5), c + Vector2(0, -s * 0.9), c + Vector2(s * 0.85, -s * 0.5),
				c + Vector2(s * 0.7, s * 0.25), c + Vector2(0, s * 0.95), c + Vector2(-s * 0.7, s * 0.25)])
			_icon_poly(shape, meter, ink, c)
			var band := PackedVector2Array()
			for p in shape:
				band.append(c + (p - c) * 0.74)
			band.append(band[0])
			draw_polyline(band, Color(paper, alpha * 0.85), 2.5)
			var boss := PackedVector2Array()
			for k in 6:
				var a := PI / 6.0 + float(k) * PI / 3.0
				boss.append(c + Vector2(cos(a), sin(a)) * s * 0.3)
			draw_colored_polygon(boss, paper)
			draw_circle(c, s * 0.12, meter)
			draw_line(c + Vector2(-s * 0.5, -s * 0.3), c + Vector2(-s * 0.22, -s * 0.62), Color(paper, alpha * 0.9), 3.0)
		"claw":
			var steel := Color(paper, alpha)
			var accent := Color(Palette.player_colour(1), alpha)
			draw_line(c + Vector2(0, -s * 1.15), c + Vector2(0, -s * 0.35), ink, 5.0)
			draw_line(c + Vector2(0, -s * 1.15), c + Vector2(0, -s * 0.35), steel, 2.5)
			draw_rect(Rect2(c + Vector2(-s * 0.4, -s * 1.38), Vector2(s * 0.8, s * 0.26)), ink)
			draw_rect(Rect2(c + Vector2(-s * 0.32, -s * 1.32), Vector2(s * 0.64, s * 0.14)), Color(ink.lightened(0.3), alpha))
			for side: float in [-1.0, 1.0]:
				var jaw := PackedVector2Array([c + Vector2(0, -s * 0.3), c + Vector2(side * s * 0.5, -s * 0.05), c + Vector2(side * s * 0.72, s * 0.5), c + Vector2(side * s * 0.5, s * 0.9)])
				draw_polyline(jaw, ink, 7.0)
				draw_polyline(jaw, steel, 4.0)
				draw_colored_polygon(PackedVector2Array([c + Vector2(side * s * 0.5, s * 0.9), c + Vector2(side * s * 0.72, s * 0.62), c + Vector2(side * s * 0.36, s * 0.72)]), accent)
			draw_circle(c + Vector2(0, -s * 0.3), s * 0.32, ink)
			draw_circle(c + Vector2(0, -s * 0.3), s * 0.22, accent)
			draw_circle(c + Vector2(0, -s * 0.3), s * 0.08, ink)
		_:
			_text(c + Vector2(-s * 0.6, s * 0.4), kind.substr(0, 2).to_upper(), 18, paper)


## A filled shape with an ink outline: the outline is the shape inflated from its centre.
func _icon_poly(points: PackedVector2Array, fill: Color, ink: Color, c: Vector2) -> void:
	var fat := PackedVector2Array()
	for p in points:
		fat.append(c + (p - c) * 1.16)
	draw_colored_polygon(fat, ink)
	draw_colored_polygon(points, fill)


## A four-ray spark with a bright core.
func _icon_spark(at: Vector2, r: float, col: Color, core: Color) -> void:
	draw_line(at + Vector2(-r, 0), at + Vector2(r, 0), col, 3.0)
	draw_line(at + Vector2(0, -r), at + Vector2(0, r), col, 3.0)
	draw_line(at + Vector2(-r * 0.6, -r * 0.6), at + Vector2(r * 0.6, r * 0.6), col, 2.0)
	draw_line(at + Vector2(-r * 0.6, r * 0.6), at + Vector2(r * 0.6, -r * 0.6), col, 2.0)
	draw_circle(at, r * 0.4, core)


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


## The currency's icon: a little mecha head (paper helmet, gold V-fin, green eyes, red chin), as on
## the tiles.
func _ticket_icon(at: Vector2, scale: float, ink: Color) -> void:
	var paper := UiStyle.paper()
	var gold := Color.from_hsv(46.0 / 360.0, 0.8, 0.9)
	var w := 11.0 * scale
	var h := 13.0 * scale
	draw_rect(Rect2(at.x - w * 0.5, at.y - h * 0.4, w, h), paper)
	draw_rect(Rect2(at.x - w * 0.5, at.y - h * 0.1, w, 3.0 * scale), ink)
	draw_rect(Rect2(at.x - 3.5 * scale, at.y - h * 0.05, 2.0 * scale, 2.0 * scale), Palette.map_colour("board", "alien"))
	draw_rect(Rect2(at.x + 1.5 * scale, at.y - h * 0.05, 2.0 * scale, 2.0 * scale), Palette.map_colour("board", "alien"))
	draw_rect(Rect2(at.x - 1.5 * scale, at.y + h * 0.42, 3.0 * scale, 2.5 * scale), Palette.hud_colour("danger"))
	draw_line(Vector2(at.x, at.y - h * 0.4), Vector2(at.x - 6.0 * scale, at.y - h * 0.4 - 6.0 * scale), gold, 1.6 * scale)
	draw_line(Vector2(at.x, at.y - h * 0.4), Vector2(at.x + 6.0 * scale, at.y - h * 0.4 - 6.0 * scale), gold, 1.6 * scale)
