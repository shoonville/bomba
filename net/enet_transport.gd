class_name EnetTransport
extends Transport
## ENet over UDP via Godot's ENetMultiplayerPeer.

var _peer: ENetMultiplayerPeer
var _bytes_sent: int = 0
var _bytes_received: int = 0
var _packets_sent: int = 0
var _packets_received: int = 0
var _what: String = "none"


func host(port: int, max_players: int) -> Error:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, max_players)
	if err != OK:
		_peer = null
		return err
	_what = "enet host :%d" % port
	return OK


func join(address: String, port: int) -> Error:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		_peer = null
		return err
	_what = "enet client %s:%d" % [address, port]
	return OK


func leave() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	_what = "none"


func get_peer() -> MultiplayerPeer:
	return _peer


func get_stats() -> Dictionary:
	if _peer != null and _peer.host != null:
		_bytes_sent += int(_peer.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
		_bytes_received += int(_peer.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA))
		_packets_sent += int(_peer.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS))
		_packets_received += int(_peer.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS))
	return {
		"bytes_sent": _bytes_sent,
		"bytes_received": _bytes_received,
		"packets_sent": _packets_sent,
		"packets_received": _packets_received,
	}


func describe() -> String:
	return _what
