class_name SeededRng
extends RefCounted
## Deterministic random number derivation. Nothing in gameplay calls randi()/randf() directly;
## every stream is derived from the match seed plus a name, and rollback code uses per-tick
## streams so a resimulated tick draws the same numbers as the first simulation.


static func derive_seed(match_seed: int, stream_name: String) -> int:
	return hash([match_seed, stream_name])


## A long-lived stream. Same (seed, name) → same sequence on every peer.
static func make_stream(match_seed: int, stream_name: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = derive_seed(match_seed, stream_name)
	return r


## A fresh generator for one tick. Same (seed, name, tick, peer) → same numbers, however many
## times the tick is simulated and on whichever peer.
static func make_tick(match_seed: int, stream_name: String, tick: int, peer: int = 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([match_seed, stream_name, tick, peer])
	return r
