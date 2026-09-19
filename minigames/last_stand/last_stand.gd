extends FpsMatch
## LAST STAND: one life each, last player standing wins. Survival scoring: the later you fell,
## the higher you rank; anyone still up when the clock ends ties for first.


func _respawns() -> bool:
	return false


func _score_for(pl: Player) -> int:
	if pl.is_alive():
		return 1 << 30
	return int(_dead_since.get(pl.peer_id, round_end_tick))  # a death on the final tick counts as the clock


func centre_text() -> String:
	var lp := get_local_player()
	if lp == null or lp.is_alive() or in_warmup():
		return ""
	var watching := spectating_name()
	if watching != "":
		return "OUT  ·  %d LEFT  ·  WATCHING %s" % [alive_count(), watching.to_upper()]
	return "OUT  ·  %d LEFT" % alive_count()


func _score_label(pl: Player) -> String:
	if pl.is_alive():
		return "SURVIVED"
	var secs := int(NetworkTime.seconds_between(round_start_tick, int(_dead_since.get(pl.peer_id, round_end_tick))))
	return "FELL AT %d:%02d" % [secs / 60, secs % 60]
