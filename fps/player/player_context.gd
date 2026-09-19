class_name PlayerContext
extends RefCounted
## What a minigame gives each player (and each bot brain) to see the world through. The fps/
## and bots/ modules only ever talk to the minigame through this object, never through its
## folder.


## Authority-only: a player's health reached zero on this tick. The minigame scores and respawns.
## False while the round has not started (warmup): weapons stay locked, movement is free.
func can_fire_at(_tick: int) -> bool:
	return true


func on_player_died(_player: Node, _tick: int) -> void:
	pass


## Every other player as a HitscanResolver.Target, for lag-compensated hit tests.
func targets_for(_shooter: Node) -> Array:
	return []


## All player nodes (bots use this to hunt).
func all_players() -> Array:
	return []


func space_state() -> PhysicsDirectSpaceState3D:
	return null


## The tick this peer is currently rendering remote players at (fractional).
func remote_render_tick() -> float:
	return float(NetworkTime.tick)


func lag_comp_max_ticks() -> int:
	return 15


func world_mask() -> int:
	return 1


## Bot navigation graph: [positions: Array[Vector3], edges: Array[Array[int]]].
func waypoints() -> Array:
	return []


func waypoint_edges() -> Array:
	return []


## Authority-only: a shot resolved (for tracers seen by other players).
func notify_shot(_shooter: Node, _tick: int, _origin: Vector3, _end_point: Vector3, _hit_kind: int) -> void:
	pass
