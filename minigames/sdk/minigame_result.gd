class_name MinigameResult
extends RefCounted
## A ranked result. rankings[0] is the winner. Ties share a rank.

var minigame_id: String = ""
var rankings: Array[Dictionary] = []  # {peer_id, score, rank, display_name[, label]}


## `label` is what the results screen prints instead of the raw score when it is not a plain
## number (survival ticks, coins and Bombas); the score still decides the rank.
func add(peer_id: int, score: int, display_name: String = "", label: String = "") -> void:
	var row := {"peer_id": peer_id, "score": score, "rank": 0, "display_name": display_name}
	if label != "":
		row["label"] = label
	rankings.append(row)


## Sort by score descending and assign ranks (ties share).
func finalize() -> void:
	rankings.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	var rank := 0
	var last_score := -2147483648
	for i in rankings.size():
		if int(rankings[i]["score"]) != last_score:
			rank = i + 1
			last_score = int(rankings[i]["score"])
		rankings[i]["rank"] = rank


func winner_id() -> int:
	if rankings.is_empty():
		return 0
	return int(rankings[0]["peer_id"])


func summary() -> String:
	var parts := PackedStringArray()
	for r in rankings:
		parts.append("#%d %s(%d)=%d" % [int(r["rank"]), str(r["display_name"]), int(r["peer_id"]), int(r["score"])])
	return "%s [%s]" % [minigame_id, ", ".join(parts)]


func to_dict() -> Dictionary:
	return {"minigame_id": minigame_id, "rankings": rankings.duplicate(true)}


static func from_dict(d: Dictionary) -> MinigameResult:
	var r := MinigameResult.new()
	r.minigame_id = str(d.get("minigame_id", ""))
	for e in d.get("rankings", []):
		r.rankings.append(e)
	return r
