class_name SoakRecorder
extends Node
## Records the numbers NETPLAN.md §11 asks for and writes them at the end of a soak:
##   <label>_traj.csv     per-tick position/health/score of every player (from _rollback_tick)
##   <label>_summary.json counters, rollback depth, RTT, bandwidth, kills, conditioner stats
## Created by Game when --soak, --soak_ticks or --report is given. With --scripted, every input
## this peer owns is driven by ScriptedInputDriver instead of a human or a bot.

var label: String = "soak"
var report_dir: String = ""
var soak_ticks: int = 0

var _arena: Node
var _rollback_depths: PackedInt32Array = []
var _loop_ms: PackedFloat32Array = []
var _rtt_samples: PackedFloat32Array = []
var _last_sample_tick: int = -1
var _started_tick: int = -1
var _done: bool = false
var _remote_log: Dictionary = {}  # peer -> {tick: feet}
var _local_rows: PackedStringArray = []
var _bw_rows: Array = []
var _prop_full: PackedFloat32Array = []
var _prop_sent: PackedFloat32Array = []
var _last_bytes_in: int = 0
var _last_bytes_out: int = 0
var _sent_rows: PackedStringArray = []


func _ready() -> void:
	Events.minigame_started.connect(_on_started)
	NetworkTime.after_tick_loop.connect(_after_loop)
	if Game.active_minigame != null:
		_on_started("")


func _on_started(_id: String) -> void:
	_arena = Game.active_minigame
	_started_tick = NetworkTime.tick
	if _arena == null or not _arena.has_method("all_player_nodes"):
		return
	var scripted: bool = Game.args.has("scripted")
	var seed_value: int = Rng.get_match_seed()
	for p in _arena.all_player_nodes():
		var pl := p as Player
		pl.record_trajectory = true
		if scripted and pl.input.is_multiplayer_authority():
			if pl.input.brain != null:
				pl.input.brain.queue_free()
				pl.input.brain = null
			var drv := ScriptedInputDriver.new()
			drv.name = "Scripted"
			pl.input.add_child(drv)
			drv.setup(pl.input, seed_value, pl.peer_id)
	# Host side: what is transmitted per tick for every non-local human player (state size).
	if multiplayer.is_server():
		for p in _arena.all_player_nodes():
			var pl := p as Player
			if pl.is_bot or pl.is_local():
				continue
			var tx = pl.rollback_synchronizer.get("_history_transmitter")
			if tx != null and tx.has_signal("_on_transmit_state"):
				tx.connect("_on_transmit_state", func(state, tick: int):
					_sent_rows.append("%d,%d,%d,%d,%d" % [pl.peer_id, tick, state.size(),
						1 if state.has(":transform") else 0, 1 if state.has(":health") else 0]))
	Log.info("soak", "Recording %d players (scripted=%s, soak_ticks=%d)" % [_arena.all_player_nodes().size(), scripted, soak_ticks])


func _after_loop() -> void:
	if _done:
		return
	var depth := int(Performance.get_custom_monitor("netfox/Rollback ticks simulated")) if Performance.has_custom_monitor("netfox/Rollback ticks simulated") else 0
	var ms := float(Performance.get_custom_monitor("netfox/Network loop duration (ms)")) if Performance.has_custom_monitor("netfox/Network loop duration (ms)") else 0.0
	_rollback_depths.append(depth)
	_loop_ms.append(ms)
	if Performance.has_custom_monitor("netfox/Full state properties count"):
		_prop_full.append(float(Performance.get_custom_monitor("netfox/Full state properties count")))
		_prop_sent.append(float(Performance.get_custom_monitor("netfox/Sent state properties count")))
	if _arena != null and is_instance_valid(_arena) and _arena.has_method("all_player_nodes"):
		for p in _arena.all_player_nodes():
			var pl := p as Player
			if pl._is_remote_on_client():
				if not _remote_log.has(pl.peer_id):
					_remote_log[pl.peer_id] = {}
				for e in pl.hitbox_history.dump():
					_remote_log[pl.peer_id][e[0]] = e[1]
	if _arena != null and is_instance_valid(_arena) and _arena.has_method("get_local_player"):
		var lp = _arena.get_local_player()
		if lp != null and not multiplayer.is_server():
			_local_rows.append("%d,%d,%d,%d,%.3f,%.3f,%.3f,%d" % [NetworkTime.tick, lp.rollback_synchronizer.get_last_known_state(),
				lp.health, lp.deaths, lp.global_position.x, lp.global_position.y, lp.global_position.z, depth])
	if NetworkTime.tick - _last_sample_tick >= NetworkTime.tickrate:
		_last_sample_tick = NetworkTime.tick
		_rtt_samples.append(Net.rtt_ms())
		var st := Net.get_stats()
		var bin := int(st.get("bytes_received", 0))
		var bout := int(st.get("bytes_sent", 0))
		_bw_rows.append([NetworkTime.tick, bin - _last_bytes_in, bout - _last_bytes_out])
		_last_bytes_in = bin
		_last_bytes_out = bout
	if soak_ticks > 0 and _started_tick >= 0 and NetworkTime.tick - _started_tick >= soak_ticks:
		_done = true
		Log.info("soak", "Soak tick budget reached (%d ticks)" % soak_ticks)
		Game.finish_soak()


func write_report() -> void:
	_done = true
	if report_dir == "":
		report_dir = ProjectSettings.globalize_path("res://reports")
	DirAccess.make_dir_recursive_absolute(report_dir)
	var traj_path := report_dir.path_join("%s_traj.csv" % label)
	var f := FileAccess.open(traj_path, FileAccess.WRITE)
	var players := []
	if _arena != null and is_instance_valid(_arena) and _arena.has_method("all_player_nodes"):
		players = _arena.all_player_nodes()
	var summary := {
		"label": label,
		"peer_id": multiplayer.get_unique_id(),
		"is_server": multiplayer.is_server(),
		"tickrate": NetworkTime.tickrate,
		"ticks_recorded": 0,
		"start_tick": _started_tick,
		"end_tick": NetworkTime.tick,
		"players": {},
		"kills": [],
		"rollback_ticks_mean": _mean_i(_rollback_depths),
		"rollback_ticks_max": _max_i(_rollback_depths),
		"tick_loop_ms_mean": _mean_f(_loop_ms),
		"tick_loop_ms_p95": _p95_f(_loop_ms),
		"rtt_ms_mean": _mean_f(_rtt_samples),
		"rtt_ms_max": _max_f(_rtt_samples),
		"net": Net.get_stats(),
		"bandwidth_per_second": _bw_rows,
		"state_props_full_mean": _mean_f(_prop_full),
		"state_props_sent_mean": _mean_f(_prop_sent),
	}
	if f != null:
		f.store_line("peer,tick,x,y,z,health,kills,deaths,yaw")
		var rows := 0
		for p in players:
			var pl := p as Player
			var ticks := pl.trajectory.keys()
			ticks.sort()
			for t in ticks:
				var e: Array = pl.trajectory[t]
				var pos: Vector3 = e[0]
				f.store_line("%d,%d,%.5f,%.5f,%.5f,%d,%d,%d,%.5f" % [pl.peer_id, int(t), pos.x, pos.y, pos.z, int(e[1]), int(e[2]), int(e[3]), float(e[4])])
				rows += 1
			summary["players"][str(pl.peer_id)] = {
				"name": pl.display_name, "is_bot": pl.is_bot, "local": pl.is_local(),
				"kills": pl.kills, "deaths": pl.deaths, "shots_fired": pl.shots_fired,
				"hits_predicted": pl.hits_predicted, "hits_landed": pl.hits_landed,
				"correction_snaps": pl.correction_snaps, "ticks": ticks.size(),
			}
		summary["ticks_recorded"] = rows
		f.close()
	if _arena != null and is_instance_valid(_arena) and "kill_log" in _arena:
		summary["kills"] = _arena.kill_log
	if not _remote_log.is_empty():
		var rf := FileAccess.open(report_dir.path_join("%s_remote.csv" % label), FileAccess.WRITE)
		if rf != null:
			rf.store_line("peer,tick,x,y,z")
			for peer in _remote_log.keys():
				var ticks: Array = _remote_log[peer].keys()
				ticks.sort()
				for t in ticks:
					var v: Vector3 = _remote_log[peer][t]
					rf.store_line("%d,%d,%.5f,%.5f,%.5f" % [int(peer), int(t), v.x, v.y, v.z])
			rf.close()
	if not _local_rows.is_empty():
		var lf := FileAccess.open(report_dir.path_join("%s_local.csv" % label), FileAccess.WRITE)
		if lf != null:
			lf.store_line("tick,latest_state,health,deaths,x,y,z,rollback_depth")
			for row in _local_rows:
				lf.store_line(row)
			lf.close()
	if not _sent_rows.is_empty():
		var sf2 := FileAccess.open(report_dir.path_join("%s_sent.csv" % label), FileAccess.WRITE)
		if sf2 != null:
			sf2.store_line("peer,tick,props,has_transform,has_health")
			for row in _sent_rows:
				sf2.store_line(row)
			sf2.close()
	var sp := report_dir.path_join("%s_summary.json" % label)
	var sf := FileAccess.open(sp, FileAccess.WRITE)
	if sf != null:
		sf.store_string(JSON.stringify(summary, "  "))
		sf.close()
	Log.info("soak", "Report written: %s and %s" % [traj_path, sp])
	print("SOAK_SUMMARY " + JSON.stringify(summary))


func _mean_i(a: PackedInt32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0
	for v in a:
		s += v
	return float(s) / float(a.size())


func _max_i(a: PackedInt32Array) -> int:
	var m := 0
	for v in a:
		m = maxi(m, v)
	return m


func _mean_f(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / float(a.size())


func _max_f(a: PackedFloat32Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, v)
	return m


func _p95_f(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var arr := Array(a)
	arr.sort()
	return float(arr[int(floor((arr.size() - 1) * 0.95))])
