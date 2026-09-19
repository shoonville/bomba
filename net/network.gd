extends Node
## Owns the transport and the conditioner. Autoload `Net`.

signal hosted(port: int)
signal joined()
signal join_failed(reason: String)
signal left()
signal progress(text: String)

var transport: Transport
var host_code: String = ""
var conditioner: NetConditioner
var conditioner_profile: String = "lan"

var _stats_timer: float = 0.0


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func is_online() -> bool:
	return transport != null and transport.get_peer() != null \
		and transport.get_peer().get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func local_id() -> int:
	return multiplayer.get_unique_id()


func host(port: int, max_players: int = 6) -> Error:
	leave()
	transport = EnetTransport.new()
	var err := transport.host(port, max_players)
	if err != OK:
		transport = null
		return err
	multiplayer.multiplayer_peer = transport.get_peer()
	Log.info("net", "Hosting: %s (max %d players)" % [transport.describe(), max_players])
	hosted.emit(port)
	return OK


## Join a host. A non-lan profile routes the connection through the seeded conditioner.
func join(address: String, port: int, profile: String = "lan", net_seed: int = 0) -> Error:
	leave()
	conditioner_profile = profile
	var target_address := address
	var target_port := port
	var prof: Dictionary = Tuning.value("net.conditioner.%s" % profile, {})
	if profile != "lan":
		if prof.is_empty():
			Log.error("net", "Unknown conditioner profile '%s'" % profile)
			return ERR_INVALID_PARAMETER
		conditioner = NetConditioner.new()
		if net_seed == 0:
			net_seed = hash([Time.get_ticks_usec(), OS.get_process_id()])
		conditioner.configure(prof, profile, net_seed)
		var proxy_port := conditioner.start(address, port)
		if proxy_port == 0:
			conditioner = null
			return ERR_CANT_CREATE
		target_address = "127.0.0.1"
		target_port = proxy_port
		Log.info("net", "Conditioner '%s' (rtt %.0f ms, jitter %.0f ms, loss %.1f%%, seed %d) on 127.0.0.1:%d → %s:%d" % [
			profile, conditioner.rtt_ms, conditioner.jitter_ms, conditioner.loss_percent, net_seed, proxy_port, address, port])
	transport = EnetTransport.new()
	var err := transport.join(target_address, target_port)
	if err != OK:
		transport = null
		_stop_conditioner()
		return err
	multiplayer.multiplayer_peer = transport.get_peer()
	Log.info("net", "Joining: %s" % transport.describe())
	return OK


## Host through noray so friends can join by code. Coroutine; emits progress.
func host_online(max_players: int = 6) -> Error:
	leave()
	var t := NorayTransport.new(get_tree())
	t.progress.connect(func(text: String): progress.emit(text))
	transport = t
	var err: Error = await t.host_async(Settings.noray_host, max_players)
	if err != OK:
		Log.error("net", "Online hosting failed: %s" % error_string(err))
		transport = null
		return err
	host_code = t.code
	multiplayer.multiplayer_peer = t.get_peer()
	Log.info("net", "Hosting online: %s" % t.describe())
	print("HOST_CODE=%s" % host_code)
	hosted.emit(Noray.local_port)
	return OK


## Join a host by its noray code. Coroutine.
func join_code(code: String, force_relay: bool = false) -> Error:
	leave()
	var t := NorayTransport.new(get_tree())
	t.progress.connect(func(text: String): progress.emit(text))
	transport = t
	var err: Error = await t.join_async(Settings.noray_host, code.strip_edges(), force_relay)
	if err != OK:
		Log.error("net", "Join by code failed: %s" % error_string(err))
		transport = null
		join_failed.emit(error_string(err))
		return err
	multiplayer.multiplayer_peer = t.get_peer()
	Log.info("net", "Joining online: %s" % t.describe())
	return OK


func leave() -> void:
	host_code = ""
	if transport != null:
		transport.leave()
		transport = null
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		left.emit()
	_stop_conditioner()


func rtt_ms() -> float:
	if is_server():
		return 0.0
	return NetworkTimeSynchronizer.rtt * 1000.0


func get_stats() -> Dictionary:
	var s := {}
	if transport != null:
		s = transport.get_stats()
	s["rtt_ms"] = rtt_ms()
	s["peer_id"] = local_id()
	s["is_server"] = is_server()
	if conditioner != null:
		s["conditioner"] = conditioner.get_stats()
	return s


func _process(delta: float) -> void:
	_stats_timer += delta
	if _stats_timer >= 1.0:
		_stats_timer = 0.0
		if transport != null:
			Events.net_stats.emit(get_stats())


func _stop_conditioner() -> void:
	if conditioner != null:
		conditioner.stop()
		conditioner = null


func _on_connected() -> void:
	Log.info("net", "Connected as peer %d" % local_id())
	joined.emit()


func _on_connection_failed() -> void:
	Log.warn("net", "Connection failed")
	join_failed.emit("connection failed")
	leave()


func _on_server_disconnected() -> void:
	Log.warn("net", "Server disconnected")
	leave()


func _exit_tree() -> void:
	_stop_conditioner()
