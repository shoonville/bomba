extends FpsMatch
## SNIPERS: bolt-action only, headshots count double. Added with nothing outside this folder.


func _score_for(pl: Player) -> int:
	var score := 0
	for k in kill_log:
		if int(k["killer"]) == pl.peer_id and int(k["victim"]) != pl.peer_id:
			score += 2 if bool(k["headshot"]) else 1
	return score
