class_name MatchConfig
extends RefCounted
## What the host configured in the lobby. Sent to every peer with the minigame or board start.
## The board fields default to tuning/board.json and are what MATCH SETTINGS in the lobby edits.

var max_players: int = 6
var minigame_id: String = "arena"
var round_seconds: int = 0  # 0 = use the minigame's own tuning
var bot_difficulty: String = "normal"
var toys_to_win: int = 4    # first to this many toys ends the board match (0 = only the round cap)
var turn_seconds: int = 20  # seconds a human has to roll before the server rolls for them
var rounds: int = 10        # the round cap (0 = none): after it, most toys wins, tickets break ties
var toy_price: int = 10     # tickets the vending machine takes for a toy


## The lobby's starting values come from tuning/board.json (Session reads them once it is up).
static func from_tuning() -> MatchConfig:
	var c := MatchConfig.new()
	var t: Dictionary = Tuning.table("board")
	c.toys_to_win = int(t.get("toys_to_win", c.toys_to_win))
	c.turn_seconds = int(t.get("turn_timeout_seconds", c.turn_seconds))
	c.rounds = int(t.get("rounds", c.rounds))
	c.toy_price = int(t.get("toy_price", c.toy_price))
	return c


func to_dict() -> Dictionary:
	return {
		"max_players": max_players, "minigame_id": minigame_id,
		"round_seconds": round_seconds, "bot_difficulty": bot_difficulty,
		"toys_to_win": toys_to_win, "turn_seconds": turn_seconds, "rounds": rounds, "toy_price": toy_price,
	}


static func from_dict(d: Dictionary) -> MatchConfig:
	var c := MatchConfig.new()
	c.max_players = int(d.get("max_players", 6))
	c.minigame_id = str(d.get("minigame_id", "arena"))
	c.round_seconds = int(d.get("round_seconds", 0))
	c.bot_difficulty = str(d.get("bot_difficulty", "normal"))
	c.toys_to_win = int(d.get("toys_to_win", c.toys_to_win))
	c.turn_seconds = int(d.get("turn_seconds", c.turn_seconds))
	c.rounds = int(d.get("rounds", c.rounds))
	c.toy_price = int(d.get("toy_price", c.toy_price))
	return c


## The board rules' config: tuning with the lobby's choices laid over it.
func apply_to(cfg: Dictionary) -> Dictionary:
	var out := cfg.duplicate(true)
	out["toys_to_win"] = toys_to_win
	out["turn_timeout_seconds"] = float(turn_seconds)
	out["rounds"] = rounds
	out["toy_price"] = toy_price
	return out
