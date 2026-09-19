class_name PlayerSlot
extends RefCounted
## One seat in the session. Bots have negative ids so they never collide with peer ids.

var peer_id: int = 0
var display_name: String = ""
var colour_index: int = 0
var is_bot: bool = false
var bot_difficulty: String = "normal"
var ready: bool = false


static func make_human(p_id: int, p_name: String, p_colour: int) -> PlayerSlot:
	var s := PlayerSlot.new()
	s.peer_id = p_id
	s.display_name = p_name
	s.colour_index = p_colour
	return s


static func make_bot(p_id: int, p_name: String, p_colour: int, p_difficulty: String) -> PlayerSlot:
	var s := make_human(p_id, p_name, p_colour)
	s.is_bot = true
	s.bot_difficulty = p_difficulty
	s.ready = true
	return s


func to_dict() -> Dictionary:
	return {
		"peer_id": peer_id, "display_name": display_name, "colour_index": colour_index,
		"is_bot": is_bot, "bot_difficulty": bot_difficulty, "ready": ready,
	}


static func from_dict(d: Dictionary) -> PlayerSlot:
	var s := PlayerSlot.new()
	s.peer_id = int(d.get("peer_id", 0))
	s.display_name = str(d.get("display_name", ""))
	s.colour_index = int(d.get("colour_index", 0))
	s.is_bot = bool(d.get("is_bot", false))
	s.bot_difficulty = str(d.get("bot_difficulty", "normal"))
	s.ready = bool(d.get("ready", false))
	return s
