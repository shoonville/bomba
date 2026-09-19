class_name MinigamePlayer
extends RefCounted
## What a minigame is told about each participant. Deliberately not the session's PlayerSlot:
## the SDK never reaches into session state.

var peer_id: int = 0
var display_name: String = ""
var colour_index: int = 0
var colour: Color = Color.WHITE
var is_bot: bool = false
var bot_difficulty: String = "normal"


static func from_dict(d: Dictionary) -> MinigamePlayer:
	var p := MinigamePlayer.new()
	p.peer_id = int(d.get("peer_id", 0))
	p.display_name = str(d.get("display_name", ""))
	p.colour_index = int(d.get("colour_index", 0))
	p.is_bot = bool(d.get("is_bot", false))
	p.bot_difficulty = str(d.get("bot_difficulty", "normal"))
	return p


func to_dict() -> Dictionary:
	return {
		"peer_id": peer_id, "display_name": display_name, "colour_index": colour_index,
		"is_bot": is_bot, "bot_difficulty": bot_difficulty,
	}
