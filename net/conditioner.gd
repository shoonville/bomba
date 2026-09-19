class_name NetConditioner
extends RefCounted
## The network conditioner: an in-process UDP proxy that adds latency, jitter and loss in both
## directions. Part of the engine, not the content (DESIGN.md §3).
##
## The client connects to 127.0.0.1:<proxy port>; the proxy forwards to the real host. Every
## drop and jitter decision comes from a seeded generator, so a run with the same seed makes the
## same decisions. Runs on its own thread so delays are not quantised to the frame rate.
## Profile numbers: rtt_ms is round trip (half applied per direction), jitter_ms is peak-to-peak
## per direction, loss_percent is per direction.


class Packet:
	var data: PackedByteArray
	var deliver_at_usec: int
	var client_port: int

	func _init(p_data: PackedByteArray, p_at: int, p_port: int) -> void:
		data = p_data
		deliver_at_usec = p_at
		client_port = p_port


var rtt_ms: float = 0.0
var jitter_ms: float = 0.0
var loss_percent: float = 0.0
var profile_name: String = "lan"

var _thread: Thread
var _running: bool = false
var _listen: PacketPeerUDP
var _upstream: Dictionary = {}
var _to_server: Array[Packet] = []
var _to_client: Array[Packet] = []
var _rng := RandomNumberGenerator.new()
var _host_address: String = ""
var _host_port: int = 0
var _stats_mutex := Mutex.new()
var _stats := {"forwarded_up": 0, "forwarded_down": 0, "dropped_up": 0, "dropped_down": 0}


func configure(profile: Dictionary, name: String, seed_value: int) -> void:
	profile_name = name
	rtt_ms = float(profile.get("rtt_ms", 0.0))
	jitter_ms = float(profile.get("jitter_ms", 0.0))
	loss_percent = float(profile.get("loss_percent", 0.0))
	_rng.seed = hash([seed_value, "conditioner", name])


func is_passthrough() -> bool:
	return rtt_ms <= 0.0 and jitter_ms <= 0.0 and loss_percent <= 0.0


## Bind the proxy and start forwarding to host_address:host_port. Returns the local proxy port
## (0 on failure).
func start(host_address: String, host_port: int, listen_port: int = 0) -> int:
	_host_address = IP.resolve_hostname(host_address, IP.TYPE_IPV4)
	_host_port = host_port
	_listen = PacketPeerUDP.new()
	var err := _listen.bind(listen_port, "127.0.0.1")
	if err != OK:
		push_error("NetConditioner: bind failed: %s" % error_string(err))
		return 0
	_running = true
	_thread = Thread.new()
	_thread.start(_loop)
	return _listen.get_local_port()


func stop() -> void:
	if not _running:
		return
	_running = false
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	if _listen != null:
		_listen.close()
	for up in _upstream.values():
		(up as PacketPeerUDP).close()
	_upstream.clear()


func get_stats() -> Dictionary:
	_stats_mutex.lock()
	var copy := _stats.duplicate()
	_stats_mutex.unlock()
	copy["profile"] = profile_name
	copy["rtt_ms"] = rtt_ms
	copy["jitter_ms"] = jitter_ms
	copy["loss_percent"] = loss_percent
	return copy


func _loop() -> void:
	while _running:
		_pump()
		OS.delay_usec(250)


func _pump() -> void:
	var now := Time.get_ticks_usec()
	# Client → proxy
	while _listen.get_available_packet_count() > 0:
		var data := _listen.get_packet()
		var port := _listen.get_packet_port()
		if not _upstream.has(port):
			var up := PacketPeerUDP.new()
			up.set_dest_address(_host_address, _host_port)
			_upstream[port] = up
		if _should_drop():
			_bump("dropped_up")
			continue
		_to_server.append(Packet.new(data, now + _delay_usec(), port))
	# Proxy → host, when due
	if not _to_server.is_empty():
		var keep: Array[Packet] = []
		for p in _to_server:
			if p.deliver_at_usec <= now:
				var up: PacketPeerUDP = _upstream[p.client_port]
				up.put_packet(p.data)
				_bump("forwarded_up")
			else:
				keep.append(p)
		_to_server = keep
	# Host → proxy
	for port in _upstream.keys():
		var up: PacketPeerUDP = _upstream[port]
		while up.get_available_packet_count() > 0:
			var data := up.get_packet()
			if _should_drop():
				_bump("dropped_down")
				continue
			_to_client.append(Packet.new(data, now + _delay_usec(), port))
	# Proxy → client, when due
	if not _to_client.is_empty():
		var keep: Array[Packet] = []
		for p in _to_client:
			if p.deliver_at_usec <= now:
				_listen.set_dest_address("127.0.0.1", p.client_port)
				_listen.put_packet(p.data)
				_bump("forwarded_down")
			else:
				keep.append(p)
		_to_client = keep


func _delay_usec() -> int:
	var base := rtt_ms * 0.5
	var j := 0.0
	if jitter_ms > 0.0:
		j = _rng.randf_range(-0.5, 0.5) * jitter_ms
	return int(maxf(0.0, base + j) * 1000.0)


func _should_drop() -> bool:
	if loss_percent <= 0.0:
		return false
	return _rng.randf() * 100.0 < loss_percent


func _bump(key: String) -> void:
	_stats_mutex.lock()
	_stats[key] = int(_stats[key]) + 1
	_stats_mutex.unlock()
