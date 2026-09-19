class_name Minigame
extends Node3D
## Base class of every minigame. The contract (DESIGN.md §4):
##   declares  — via manifest.json
##   receives  — N players and a seed, through setup()
##   returns   — a ranked MinigameResult, through finished
##   never     — reaches into board, session or item state.

signal finished(result: MinigameResult)

var manifest: MinigameManifest
var players: Array[MinigamePlayer] = []
var match_seed: int = 0
var config: Dictionary = {}

var _finished: bool = false


func setup(p_players: Array[MinigamePlayer], p_seed: int, p_config: Dictionary) -> void:
	players = p_players
	match_seed = p_seed
	config = p_config
	_on_setup()


## Override. Called once every peer has the same players and seed.
func _on_setup() -> void:
	pass


func is_authority() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func local_peer_id() -> int:
	return multiplayer.get_unique_id()


func player_by_id(peer_id: int) -> MinigamePlayer:
	for p in players:
		if p.peer_id == peer_id:
			return p
	return null


func finish(result: MinigameResult) -> void:
	if _finished:
		return
	_finished = true
	if manifest != null:
		result.minigame_id = manifest.id
	result.finalize()
	finished.emit(result)
