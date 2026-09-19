class_name NorayTransport
extends Transport
## Friends join by code, no port forwarding: register with a noray server, punch through NAT,
## fall back to the relay. Hosts listen on the port noray registered; clients bind the same
## way and handshake before ENet connects (netfox.noray docs). Async: use host_async / join_async.

signal progress(text: String)

var _peer: ENetMultiplayerPeer
var _tree: SceneTree
var _stats := EnetTransport.new()
var _what: String = "noray (idle)"
var _host_connects: int = 0
var _client_state: String = ""
var _client_result: Error = ERR_UNAVAILABLE
var _client_address: String = ""
var _client_port: int = 0
var code: String = ""
var used_relay: bool = false
var _bytes_sent: int = 0
var _bytes_received: int = 0


func _init(tree: SceneTree) -> void:
	_tree = tree


func _split(hostport: String) -> Array:
	var host := hostport
	var port := 8890
	if hostport.contains(":"):
		host = hostport.get_slice(":", 0)
		port = int(hostport.get_slice(":", 1))
	return [host, port]


func _register(noray_hostport: String) -> Error:
	var hp := _split(noray_hostport)
	progress.emit("Connecting to relay %s" % noray_hostport)
	var err: Error = await Noray.connect_to_host(hp[0], hp[1])
	if err != OK:
		return err
	Noray.register_host()
	var waited := 0.0
	while Noray.pid == "" and waited < 6.0:
		await _tree.create_timer(0.1).timeout
		waited += 0.1
	if Noray.pid == "":
		return ERR_TIMEOUT
	progress.emit("Registering address")
	err = await Noray.register_remote()
	return err


## Host: returns OK with `code` set (share it with friends).
func host_async(noray_hostport: String, max_players: int) -> Error:
	var err := await _register(noray_hostport)
	if err != OK:
		_what = "noray host failed: %s" % error_string(err)
		return err
	_peer = ENetMultiplayerPeer.new()
	err = _peer.create_server(Noray.local_port, max_players)
	if err != OK:
		_peer = null
		return err
	code = Noray.oid
	_what = "noray host, code %s, port %d" % [code, Noray.local_port]
	Noray.on_connect_nat.connect(_host_handle_connect)
	Noray.on_connect_relay.connect(_host_handle_connect)
	progress.emit("Hosting with code %s" % code)
	return OK


func _host_handle_connect(address: String, port: int) -> void:
	_host_connects += 1
	progress.emit("Player connecting from %s:%d" % [address, port])
	if _peer != null:
		PacketHandshake.over_enet_peer(_peer, address, port)


## Client: NAT punchthrough first, then the relay. Returns OK once ENet is connecting.
func join_async(noray_hostport: String, host_code: String, force_relay: bool = false) -> Error:
	var err := await _register(noray_hostport)
	if err != OK:
		_what = "noray join failed: %s" % error_string(err)
		return err
	Noray.on_connect_nat.connect(_client_handle_connect)
	Noray.on_connect_relay.connect(_client_handle_connect)
	var modes := ["relay"] if force_relay else ["nat", "relay"]
	for mode in modes:
		_client_state = "waiting"
		_client_result = ERR_UNAVAILABLE
		progress.emit("Connecting via %s…" % mode)
		if mode == "nat":
			Noray.connect_nat(host_code)
		else:
			Noray.connect_relay(host_code)
		var waited := 0.0
		var budget := 5.0 if mode == "nat" else 10.0
		while _client_state != "done" and waited < budget:
			await _tree.create_timer(0.1).timeout
			waited += 0.1
		if _client_state == "done" and _client_result == OK:
			used_relay = mode == "relay"
			_what = "noray client via %s to %s:%d" % [mode, _client_address, _client_port]
			return OK
		progress.emit("%s failed (%s)" % [mode, error_string(_client_result) if _client_state == "done" else "timeout"])
	return ERR_CANT_CONNECT


func _client_handle_connect(address: String, port: int) -> void:
	if _client_state != "waiting":
		return
	_client_state = "handshake"
	_client_address = address
	_client_port = port
	var udp := PacketPeerUDP.new()
	udp.bind(Noray.local_port)
	udp.set_dest_address(address, port)
	var err: Error = await PacketHandshake.over_packet_peer(udp, 4.0)
	udp.close()
	if err != OK and err != ERR_BUSY:
		_client_result = err
		_client_state = "done"
		return
	_peer = ENetMultiplayerPeer.new()
	err = _peer.create_client(address, port, 0, 0, 0, Noray.local_port)
	_client_result = err
	_client_state = "done"


func leave() -> void:
	if Noray.on_connect_nat.is_connected(_host_handle_connect):
		Noray.on_connect_nat.disconnect(_host_handle_connect)
		Noray.on_connect_relay.disconnect(_host_handle_connect)
	if Noray.on_connect_nat.is_connected(_client_handle_connect):
		Noray.on_connect_nat.disconnect(_client_handle_connect)
		Noray.on_connect_relay.disconnect(_client_handle_connect)
	if _peer != null:
		_peer.close()
	_peer = null
	Noray.disconnect_from_host()
	_what = "noray (idle)"


func get_peer() -> MultiplayerPeer:
	return _peer


func get_stats() -> Dictionary:
	if _peer != null and _peer.host != null:
		_bytes_sent += int(_peer.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
		_bytes_received += int(_peer.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA))
	var s := {"bytes_sent": _bytes_sent, "bytes_received": _bytes_received, "packets_sent": 0, "packets_received": 0}
	s["noray_code"] = code
	s["relay"] = used_relay
	return s


func describe() -> String:
	return _what
