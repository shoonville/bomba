class_name Transport
extends RefCounted
## The transport interface. ENet today; Steam sockets later. Nothing outside net/ touches a
## MultiplayerPeer directly.


func host(_port: int, _max_players: int) -> Error:
	return ERR_UNAVAILABLE


func join(_address: String, _port: int) -> Error:
	return ERR_UNAVAILABLE


func leave() -> void:
	pass


func get_peer() -> MultiplayerPeer:
	return null


## Cumulative bytes/packets for the report; keys: bytes_sent, bytes_received, packets_sent,
## packets_received.
func get_stats() -> Dictionary:
	return {}


func describe() -> String:
	return "none"
