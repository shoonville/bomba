class_name MatchConfig
extends RefCounted
## What the host configured in the lobby. Sent to every peer with the minigame start.

var max_players: int = 6
var minigame_id: String = "arena"
var round_seconds: int = 0  # 0 = use the minigame's own tuning
var bot_difficulty: String = "normal"


func to_dict() -> Dictionary:
	return {
		"max_players": max_players, "minigame_id": minigame_id,
		"round_seconds": round_seconds, "bot_difficulty": bot_difficulty,
	}


static func from_dict(d: Dictionary) -> MatchConfig:
	var c := MatchConfig.new()
	c.max_players = int(d.get("max_players", 6))
	c.minigame_id = str(d.get("minigame_id", "arena"))
	c.round_seconds = int(d.get("round_seconds", 0))
	c.bot_difficulty = str(d.get("bot_difficulty", "normal"))
	return c
