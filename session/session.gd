extends Node
## Lobby, player registry and match config. Autoload `Session`. The server owns the registry and
## broadcasts it; clients only ever ask.

signal registry_changed()
signal minigame_start_requested(id: String, seed_value: int, players: Array, config: Dictionary)
signal board_start_requested(board_id: String, seed_value: int, players: Array, config: Dictionary)
signal rejected(reason: String)
signal result_received(result: MinigameResult)

var players: Dictionary = {}
var config := MatchConfig.new()


func _ready() -> void:
	# The lobby's starting match settings come from tuning; the host turns them in MATCH SETTINGS.
	config = MatchConfig.from_tuning()
var local_name: String = "Player"
var last_result: MinigameResult

var _next_bot_id: int = -1
var _hooked: bool = false


func is_authority() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id()


func human_count() -> int:
	var n := 0
	for p in players.values():
		if not (p as PlayerSlot).is_bot:
			n += 1
	return n


func slot_list() -> Array[PlayerSlot]:
	var out: Array[PlayerSlot] = []
	var ids := players.keys()
	ids.sort()
	for id in ids:
		out.append(players[id])
	return out


# --- Host ---------------------------------------------------------------------------------------

func host_session(name: String) -> void:
	players.clear()
	_next_bot_id = -1
	_hook_events()
	_add(PlayerSlot.make_human(1, name, _free_colour()))
	_broadcast_registry()


func add_bot(difficulty: String = "normal") -> int:
	if not is_authority():
		return 0
	if players.size() >= config.max_players:
		Log.warn("session", "Lobby full, not adding bot")
		return 0
	var id := _next_bot_id
	_next_bot_id -= 1
	var colour := _free_colour()
	var bot_name := "BOT " + Palette.player_name(colour)
	_add(PlayerSlot.make_bot(id, bot_name, colour, difficulty))
	_broadcast_registry()
	return id


## Host only: cycle a bot's difficulty (easy → normal → hard) and tell everyone.
func set_bot_difficulty(peer_id: int, difficulty: String) -> void:
	if not is_authority() or not players.has(peer_id):
		return
	var slot: PlayerSlot = players[peer_id]
	if not slot.is_bot:
		return
	slot.bot_difficulty = difficulty
	_broadcast_registry()


func remove_bot() -> void:
	if not is_authority():
		return
	var bots := players.keys().filter(func(id): return (players[id] as PlayerSlot).is_bot)
	if bots.is_empty():
		return
	bots.sort()
	players.erase(bots[0])
	_broadcast_registry()


func start_minigame(id: String) -> void:
	if not is_authority():
		Log.warn("session", "Only the host starts minigames")
		return
	config.minigame_id = id
	var seed_value := Rng.get_match_seed()
	var data: Array = []
	for slot in slot_list():
		data.append(slot.to_dict())
	Log.info("session", "Starting %s with %d players (seed %d)" % [id, data.size(), seed_value])
	Game.transition(func(): _rpc_start_minigame.rpc(id, seed_value, data, config.to_dict()))


func start_board(board_id: String = "first") -> void:
	if not is_authority():
		Log.warn("session", "Only the host starts a match")
		return
	var seed_value := Rng.get_match_seed()
	var data: Array = []
	for slot in slot_list():
		data.append(slot.to_dict())
	Log.info("session", "Starting board '%s' with %d players (seed %d)" % [board_id, data.size(), seed_value])
	Game.transition(func(): _rpc_start_board.rpc(board_id, seed_value, data, config.to_dict()))


@rpc("authority", "call_local", "reliable")
func _rpc_start_board(board_id: String, seed_value: int, data: Array, cfg: Dictionary) -> void:
	Rng.set_match_seed(seed_value)
	config = MatchConfig.from_dict(cfg)
	board_start_requested.emit(board_id, seed_value, data, cfg)


func report_result(result: MinigameResult) -> void:
	if not is_authority():
		return
	last_result = result
	_rpc_result.rpc(result.to_dict())


# --- Client -------------------------------------------------------------------------------------

func join_session(name: String) -> void:
	local_name = name
	players.clear()
	_hook_events()
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_register_with_host()
	else:
		Net.joined.connect(_register_with_host, CONNECT_ONE_SHOT)


func _register_with_host() -> void:
	_rpc_register.rpc_id(1, local_name)


# --- Internals ----------------------------------------------------------------------------------

func _hook_events() -> void:
	if _hooked:
		return
	_hooked = true
	NetworkEvents.on_peer_leave.connect(_on_peer_leave)


func _on_peer_leave(id: int) -> void:
	if not is_authority():
		return
	if players.has(id):
		Log.info("session", "Peer %d left" % id)
		players.erase(id)
		_broadcast_registry()


func _add(slot: PlayerSlot) -> void:
	players[slot.peer_id] = slot


func _free_colour() -> int:
	var used := {}
	for p in players.values():
		used[(p as PlayerSlot).colour_index] = true
	for i in 6:
		if not used.has(i):
			return i
	return players.size() % 6


func _broadcast_registry() -> void:
	registry_changed.emit()
	Events.session_changed.emit()
	if is_authority() and Net.is_online():
		var data: Array = []
		for slot in slot_list():
			data.append(slot.to_dict())
		_rpc_registry.rpc(data)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_register(name: String) -> void:
	if not is_authority():
		return
	var id := multiplayer.get_remote_sender_id()
	if Game.active_minigame != null or Game.board != null:
		Log.warn("session", "Peer %d rejected: match in progress" % id)
		_rpc_rejected.rpc_id(id, "MATCH IN PROGRESS")
		return
	if players.size() >= config.max_players:
		Log.warn("session", "Peer %d rejected: lobby full" % id)
		_rpc_rejected.rpc_id(id, "LOBBY FULL")
		return
	_add(PlayerSlot.make_human(id, name, _free_colour()))
	Log.info("session", "Peer %d registered as '%s'" % [id, name])
	_broadcast_registry()


## Host → one joiner: no seat for you (a match is running, or the lobby is full). The joiner
## leaves; joining mid-match is not supported yet (a late seat needs a mid-match spawn).
@rpc("authority", "call_remote", "reliable")
func _rpc_rejected(reason: String) -> void:
	Log.warn("session", "Join rejected: %s" % reason)
	rejected.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_registry(data: Array) -> void:
	players.clear()
	for d in data:
		var slot := PlayerSlot.from_dict(d)
		players[slot.peer_id] = slot
	registry_changed.emit()
	Events.session_changed.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_start_minigame(id: String, seed_value: int, data: Array, cfg: Dictionary) -> void:
	Rng.set_match_seed(seed_value)
	config = MatchConfig.from_dict(cfg)
	minigame_start_requested.emit(id, seed_value, data, cfg)


@rpc("authority", "call_remote", "reliable")
func _rpc_result(data: Dictionary) -> void:
	last_result = MinigameResult.from_dict(data)
	result_received.emit(last_result)
