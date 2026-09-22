class_name BoardDirector
extends Node
## Runs one board match (BOARDPLAN.md §2). Lives under Game for the whole match, across the
## minigames. The server owns the BoardState and applies intents; every peer renders the last
## state and plays the event queue. Turn-based, so plain reliable RPCs, no rollback.

signal state_changed(state: BoardState)
signal events_received(events: Array)
signal match_finished(state: BoardState)
signal social(peer_id: int, kind: String, payload: String)   # a ping on a space or an emote

const EMOTES := ["GG", "NICE!", "OH NO", "HURRY UP"]
var _social_last: Dictionary = {}

const VIEW_SCRIPT := preload("res://board/board_view.gd")

var graph: BoardGraph
var state: BoardState
var cfg: Dictionary = {}
var board_id: String = "first"
var view: Node3D
var local_choice_options: PackedStringArray = []

var _players_data: Array = []
var _seed: int = 0
var _timer: float = 0.0
var _busy_until: float = 0.0
var _clock: float = 0.0
var _minigame_started: bool = false
var _finished_emitted: bool = false
var _last_serial_seen: int = -1
var _next_minigame: String = "arena"
var _last_minigame: String = ""


func is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func start(players_data: Array, seed_value: int, p_board_id: String) -> void:
	board_id = p_board_id
	# Tuning with the host's MATCH SETTINGS laid over it (toys to win, turn time, round cap,
	# toy price); the config arrived with the start RPC on every peer.
	cfg = Session.config.apply_to(Tuning.table("board"))
	if Game.args.has("board_rounds"):
		cfg["rounds"] = int(Game.args["board_rounds"])
	if Game.args.has("toys_to_win"):
		cfg["toys_to_win"] = int(Game.args["toys_to_win"])
	if Game.args.has("toy_price"):
		cfg["toy_price"] = int(Game.args["toy_price"])
	graph = BoardGraph.load_file("res://board/boards/%s.json" % board_id)
	if graph == null:
		Log.error("board", "Board '%s' missing" % board_id)
		return
	var errors := graph.validate()
	for e in errors:
		Log.error("board", "Board '%s': %s" % [board_id, e])
	_players_data = players_data
	_seed = seed_value
	Events.minigame_finished.connect(_on_minigame_finished)
	if is_server():
		state = BoardState.new()
		var events := BoardRules.setup(state, graph, players_data, seed_value, cfg)
		if Game.args.has("give_item"):
			# Harness: hand the host's seat an item so the item UI can be exercised from a fresh match.
			var me := state.player(multiplayer.get_unique_id())
			if me != null:
				for id in str(Game.args["give_item"]).split(","):   # a list, for a frame of the whole bar
					me.items.append(id.strip_edges())
		if Game.args.has("give_bots_item"):
			for p in state.players:
				if p.is_bot:
					p.items.append(str(Game.args["give_bots_item"]))
		if Game.args.has("machine_at"):
			# Harness: pin the first machine spot so a purchase can be framed from a fresh match.
			for c in graph.goal_candidates():
				if str(c) == str(Game.args["machine_at"]):
					state.goal = str(c)
		_broadcast(events)
	else:
		state = null
	_show_board()
	Log.info("board", "Board match on '%s' with %d players (server=%s), machine at %s, first to %d toys at %d coins" % [
		board_id, players_data.size(), is_server(), state.goal if state != null else "?", int(cfg.get("toys_to_win", 0)), int(cfg.get("toy_price", 0))])


func _show_board() -> void:
	if view != null and is_instance_valid(view):
		return
	view = VIEW_SCRIPT.new()
	view.name = "Board"
	Game.world.add_child(view)
	view.setup(self)
	if state != null:
		state_changed.emit(state)
	Audio.music("music_menu")
	if not Game.headless:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _hide_board() -> void:
	if view != null and is_instance_valid(view):
		Game.world.remove_child(view)
		view.queue_free()
	view = null


func local_player() -> BoardState.PlayerState:
	if state == null or not is_inside_tree():
		return null
	return state.player(multiplayer.get_unique_id())


func is_local_turn() -> bool:
	var lp := local_player()
	return lp != null and not lp.is_bot and state.active_player() == lp


# --- social (any peer → everyone, cosmetic, rate-limited) --------------------------------

func send_ping(space_id: String) -> void:
	if is_inside_tree():
		_rpc_social.rpc("ping", space_id)


func send_emote(text: String) -> void:
	if is_inside_tree():
		_rpc_social.rpc("emote", text)


@rpc("any_peer", "call_local", "reliable")
func _rpc_social(kind: String, payload: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var now := Time.get_ticks_msec()
	if now - int(_social_last.get(sender, -100000)) < 400:
		return
	_social_last[sender] = now
	if kind == "ping" and (graph == null or graph.get_space(payload) == null):
		return
	if kind == "emote" and not EMOTES.has(payload):
		return
	social.emit(sender, kind, payload)


# --- intents (any peer → server) ---------------------------------------------------------

func request_roll() -> void:
	_rpc_intent_roll.rpc_id(1)


func request_choose(index: int) -> void:
	_rpc_intent_choose.rpc_id(1, index)


func request_item(item: String, target_peer: int, payload: Dictionary = {}) -> void:
	_rpc_intent_item.rpc_id(1, item, target_peer, payload)


@rpc("any_peer", "call_local", "reliable")
func _rpc_intent_roll() -> void:
	if not is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if not BoardRules.can_act(state, sender) or state.phase != BoardState.PHASE_TURNS or _clock < _busy_until:
		return
	_do_roll()


@rpc("any_peer", "call_local", "reliable")
func _rpc_intent_choose(index: int) -> void:
	if not is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if not BoardRules.can_act(state, sender) or state.phase != BoardState.PHASE_CHOOSING:
		return
	_do_choose(index)


@rpc("any_peer", "call_local", "reliable")
func _rpc_intent_item(item: String, target_peer: int, payload: Dictionary) -> void:
	if not is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if not BoardRules.can_act(state, sender):
		return
	var events := BoardRules.use_item(state, graph, cfg, sender, item, target_peer, payload)
	if not events.is_empty():
		_broadcast(events)


# --- server flow ---------------------------------------------------------------------------

func _do_roll() -> void:
	var events := BoardRules.roll(state, graph, cfg)
	_broadcast(events)
	_timer = 0.0


func _do_choose(index: int) -> void:
	var events := BoardRules.choose(state, graph, cfg, index)
	_broadcast(events)
	_timer = 0.0


func _process(delta: float) -> void:
	_clock += delta
	if not is_server() or state == null:
		return
	match state.phase:
		BoardState.PHASE_TURNS:
			if _clock < _busy_until:
				return
			_timer += delta
			var ap := state.active_player()
			if ap.is_bot or Game.args.has("autoplay"):
				if _timer >= float(cfg.get("bot_think_seconds", 1.2)):
					var pick := BoardRules.bot_item(state, graph, cfg)
					if not pick.is_empty():
						var payload: Dictionary = pick[2] if pick.size() > 2 else {}
						_broadcast(BoardRules.use_item(state, graph, cfg, ap.peer_id, str(pick[0]), int(pick[1]), payload))
						_timer = 0.0
						return
					_do_roll()
			elif Game.args.has("board_auto_roll") and _timer >= 1.0:
				_do_roll()  # harness: the human seat rolls by itself but keeps its fork and item choices
			elif _timer >= float(cfg.get("turn_timeout_seconds", 20.0)):
				Log.info("board", "%s timed out, auto-rolling" % ap.display_name)
				_do_roll()
		BoardState.PHASE_CHOOSING:
			if _clock < _busy_until:
				return
			_timer += delta
			var ap := state.active_player()
			if ap.is_bot or Game.args.has("autoplay"):
				if _timer >= 0.8:
					_do_choose(BoardRules.bot_choose(state, graph))
			elif _timer >= float(cfg.get("choice_timeout_seconds", 8.0)):
				_do_choose(0)
		BoardState.PHASE_MINIGAME:
			if not _minigame_started and _clock >= _busy_until:
				_minigame_started = true
				_start_minigame()
		BoardState.PHASE_FINISHED:
			if not _finished_emitted and _clock >= _busy_until:
				_finished_emitted = true
				match_finished.emit(state)


## Pick the round's minigame from whatever folders the registry found, never the same twice
## in a row when there is a choice. Seeded so the host's pick is reproducible.
func _pick_minigame() -> String:
	if Game.args.has("minigame"):
		return str(Game.args["minigame"])
	var n := state.players.size() if state != null else 0
	var ids: Array = []
	for id in MinigameRegistry.ids():
		var m := MinigameRegistry.get_manifest(str(id))
		if m == null or (n > 0 and (n < m.min_players or n > m.max_players)):
			continue
		ids.append(str(id))
	ids.sort()
	if ids.is_empty():
		return "arena"
	if ids.size() > 1 and _last_minigame != "":
		ids.erase(_last_minigame)
	var r := Rng.stream("board_minigames")
	return str(ids[r.randi_range(0, ids.size() - 1)])


func _start_minigame() -> void:
	var secs := int(cfg.get("minigame_round_seconds", 90))
	if Game.args.has("board_minigame_seconds"):
		secs = int(Game.args["board_minigame_seconds"])
	Session.config.round_seconds = secs
	_last_minigame = _next_minigame
	Log.info("board", "Round %d minigame: %s for %d s" % [state.round, _next_minigame, secs])
	Session.start_minigame(_next_minigame)


func _on_minigame_finished(result: MinigameResult) -> void:
	if state == null and not is_server():
		_show_board()
		return
	if is_server():
		var ranking := []
		for r in result.rankings:
			ranking.append(int(r["peer_id"]))
		var events := BoardRules.apply_minigame(state, cfg, ranking)
		_minigame_started = false
		_show_board()
		_broadcast(events)
	else:
		_show_board()


# --- replication ----------------------------------------------------------------------------

func _broadcast(events: Array) -> void:
	for e in events:
		if str(e.get("kind", "")) == "minigame":
			_next_minigame = _pick_minigame()
			var m := MinigameRegistry.get_manifest(_next_minigame)
			e["id"] = _next_minigame
			e["display_name"] = m.display_name if m != null else _next_minigame.to_upper()
	for e in events:
		if str(e.get("kind", "")) == "laser":
			var shooter := state.player(int(e["peer"]))
			var parts := []
			for h in e.get("hits", []):
				var v := state.player(int(h["peer"]))
				parts.append("%s -%d%s" % [v.display_name if v != null else "?", int(h["damage"]), " DOWN" if bool(h.get("dead", false)) else ""])
			Log.info("board", "%s fires the laser at %.2f rad: %s" % [shooter.display_name if shooter != null else "?", float(e["aim"]), ", ".join(parts) if not parts.is_empty() else "no hit"])
		elif str(e.get("kind", "")) == "bomb":
			var thrower := state.player(int(e["peer"]))
			var parts := []
			for h in e.get("hits", []):
				var v := state.player(int(h["peer"]))
				parts.append("%s %s%s%s" % [v.display_name if v != null else "?", "shielded" if bool(h.get("shielded", false)) else "-%d" % int(h["damage"]), " DOWN" if bool(h.get("dead", false)) else "", " back %d" % (h.get("knock", []) as Array).size() if not (h.get("knock", []) as Array).is_empty() else ""])
			var at: Array = e["at"]
			Log.info("board", "%s throws the bomb to (%.1f, %.1f): %s" % [thrower.display_name if thrower != null else "?", float(at[0]), float(at[2]), ", ".join(parts) if not parts.is_empty() else "no hit"])
		elif str(e.get("kind", "")) == "portal":
			var u := state.player(int(e["peer"]))
			var m := state.player(int(e["target"]))
			Log.info("board", "%s portals to %s: %s -> %s" % [u.display_name if u != null else "?", m.display_name if m != null else "?", str(e["from"]), str(e["to"])])
		elif str(e.get("kind", "")) == "magnet":
			var thief := state.player(int(e["peer"]))
			var mark := state.player(int(e["target"]))
			var what := "nothing (shielded)" if bool(e.get("shielded", false)) else (str(e["item"]).to_upper() if str(e["item"]) != "" else "%d coins" % int(e["coins"]))
			Log.info("board", "%s grabs %s from %s" % [thief.display_name if thief != null else "?", what, mark.display_name if mark != null else "?"])
	var pause := _estimate_pause(events)
	_busy_until = _clock + pause
	_rpc_state.rpc(state.to_dict())
	if not events.is_empty():
		_rpc_events.rpc(events)


func _estimate_pause(events: Array) -> float:
	var t := 0.0
	var hop := float(cfg.get("hop_seconds", 0.32))
	for e in events:
		match str(e.get("kind", "")):
			"roll": t += 0.7
			"move": t += hop * (e["path"] as Array).size()
			"coins", "item", "item_used": t += 0.55
			"toy": t += 1.4
			"laser":
				t += 1.5
				for h in e.get("hits", []):
					if bool(h.get("dead", false)):
						t += 0.9
			"bomb":
				t += 1.8
				for h in e.get("hits", []):
					t += 0.9 if bool(h.get("dead", false)) else 0.35 * (h.get("knock", []) as Array).size()
			"portal": t += 2.8
			"magnet": t += 1.3
			"teleport": t += 1.1
			"turn": t += 0.35
			"minigame": t += 2.4
			"finished": t += 1.0
	if events.any(func(e): return e.get("kind") == "coins" and e.has("rank")):
		t += 2.4  # the reward card
	return t + float(cfg.get("land_pause_seconds", 0.9)) * 0.3


@rpc("authority", "call_local", "reliable")
func _rpc_state(data: Dictionary) -> void:
	state = BoardState.from_dict(data)
	if state.phase == BoardState.PHASE_MINIGAME:
		if not is_server():
			pass
	state_changed.emit(state)


@rpc("authority", "call_local", "reliable")
func _rpc_events(events: Array) -> void:
	for e in events:
		match str(e.get("kind", "")):
			"turn":
				_last_serial_seen = int(e.get("serial", 0))
			"minigame":
				_hide_board_soon()
			"finished":
				if not is_server():
					_finished_emitted = true
					match_finished.emit(state)
	events_received.emit(events)


func _hide_board_soon() -> void:
	# The minigame start RPC arrives after the pause; clear the board just before it.
	if not is_inside_tree():
		return
	var wait := maxf(0.0, _busy_until - _clock - 0.05) if is_server() else 1.0
	get_tree().create_timer(wait).timeout.connect(func():
		if is_inside_tree():
			_hide_board()
	)


## Seconds before the server auto-rolls the active human (the host's HUD counts it down);
## -1 when unknown (clients) or not applicable.
func turn_seconds_left() -> float:
	if not is_server() or state == null or state.phase != BoardState.PHASE_TURNS:
		return -1.0
	if _clock < _busy_until:
		return float(cfg.get("turn_timeout_seconds", 20.0))
	return maxf(0.0, float(cfg.get("turn_timeout_seconds", 20.0)) - _timer)


func space_position(space_id: String) -> Vector3:
	var s := graph.get_space(space_id) if graph != null else null
	return s.position if s != null else Vector3.ZERO


func _exit_tree() -> void:
	if Events.minigame_finished.is_connected(_on_minigame_finished):
		Events.minigame_finished.disconnect(_on_minigame_finished)
	_hide_board()
