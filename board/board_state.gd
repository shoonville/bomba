class_name BoardState
extends RefCounted
## The whole board match as plain data (BOARDPLAN.md §2). Serialises to a Dictionary for the
## state RPC; nothing here references nodes.

const PHASE_TURNS := "TURNS"
const PHASE_CHOOSING := "CHOOSING"
const PHASE_MINIGAME := "MINIGAME"
const PHASE_FINISHED := "FINISHED"


class PlayerState:
	var peer_id: int = 0
	var display_name: String = ""
	var colour_index: int = 0
	var is_bot: bool = false
	var space: String = ""
	var coins: int = 0
	var toys: int = 0
	var items: Array = []
	var roll_bonus: int = 0
	var hp: int = 30

	func to_dict() -> Dictionary:
		return {"peer_id": peer_id, "display_name": display_name, "colour_index": colour_index,
			"is_bot": is_bot, "space": space, "coins": coins, "toys": toys,
			"items": items.duplicate(), "roll_bonus": roll_bonus, "hp": hp}

	static func from_dict(d: Dictionary) -> PlayerState:
		var p := PlayerState.new()
		p.peer_id = int(d.get("peer_id", 0))
		p.display_name = str(d.get("display_name", ""))
		p.colour_index = int(d.get("colour_index", 0))
		p.is_bot = bool(d.get("is_bot", false))
		p.space = str(d.get("space", ""))
		p.coins = int(d.get("coins", 0))
		p.toys = int(d.get("toys", 0))
		p.items = Array(d.get("items", []))
		p.roll_bonus = int(d.get("roll_bonus", 0))
		p.hp = int(d.get("hp", 30))
		return p


var board_id: String = ""
var players: Array[PlayerState] = []
var round: int = 1
var rounds: int = 5
var phase: String = PHASE_TURNS
var active: int = 0
var dice: int = 0
var steps_left: int = 0
var pending_options: PackedStringArray = []
var goal: String = ""
var seed_value: int = 0
var rng_counter: int = 0
var turn_serial: int = 0
var last_ranking: Array = []
# Blood on the board: {n, space, a, r, seed} per laser hit, newest last, capped; every peer
# draws the same splats from this, so they survive the view being rebuilt after a minigame.
var blood: Array = []
var blood_serial: int = 0


func active_player() -> PlayerState:
	if players.is_empty():
		return null
	return players[clampi(active, 0, players.size() - 1)]


func player(peer_id: int) -> PlayerState:
	for p in players:
		if p.peer_id == peer_id:
			return p
	return null


func index_of(peer_id: int) -> int:
	for i in players.size():
		if players[i].peer_id == peer_id:
			return i
	return -1


## Toys first, coins second, then name so ties are stable on every peer.
func standings() -> Array[PlayerState]:
	var out := players.duplicate()
	out.sort_custom(func(a: PlayerState, b: PlayerState):
		if a.toys != b.toys:
			return a.toys > b.toys
		if a.coins != b.coins:
			return a.coins > b.coins
		return a.display_name < b.display_name)
	return out


func to_dict() -> Dictionary:
	var ps := []
	for p in players:
		ps.append(p.to_dict())
	return {"board_id": board_id, "players": ps, "round": round, "rounds": rounds, "phase": phase,
		"active": active, "dice": dice, "steps_left": steps_left, "pending_options": Array(pending_options),
		"goal": goal, "seed": seed_value, "rng_counter": rng_counter, "turn_serial": turn_serial,
		"last_ranking": last_ranking.duplicate(), "blood": blood.duplicate(true), "blood_serial": blood_serial}


static func from_dict(d: Dictionary) -> BoardState:
	var s := BoardState.new()
	s.board_id = str(d.get("board_id", ""))
	for pd in d.get("players", []):
		s.players.append(PlayerState.from_dict(pd))
	s.round = int(d.get("round", 1))
	s.rounds = int(d.get("rounds", 5))
	s.phase = str(d.get("phase", PHASE_TURNS))
	s.active = int(d.get("active", 0))
	s.dice = int(d.get("dice", 0))
	s.steps_left = int(d.get("steps_left", 0))
	for o in d.get("pending_options", []):
		s.pending_options.append(str(o))
	s.goal = str(d.get("goal", ""))
	s.seed_value = int(d.get("seed", 0))
	s.rng_counter = int(d.get("rng_counter", 0))
	s.turn_serial = int(d.get("turn_serial", 0))
	s.last_ranking = Array(d.get("last_ranking", []))
	s.blood = Array(d.get("blood", []))
	s.blood_serial = int(d.get("blood_serial", 0))
	return s
