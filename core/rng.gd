extends Node
## The seeded RNG service. Autoload `Rng`. Holds the match seed and hands out streams.
## The server decides the match seed and sends it with the minigame start; clients set it there.

var _match_seed: int = 0
var _streams: Dictionary = {}


func _ready() -> void:
	# A boot seed so pre-match code (menus, bot names) is still reproducible per process.
	set_match_seed(hash([Time.get_unix_time_from_system(), OS.get_process_id()]))


func set_match_seed(seed_value: int) -> void:
	_match_seed = seed_value
	_streams.clear()
	Log.debug("rng", "Match seed set to %d" % seed_value)


func get_match_seed() -> int:
	return _match_seed


## Persistent named stream (lobby shuffles, bot personalities). Not for rollback code.
func stream(stream_name: String) -> RandomNumberGenerator:
	if not _streams.has(stream_name):
		_streams[stream_name] = SeededRng.make_stream(_match_seed, stream_name)
	return _streams[stream_name]


## Per-tick stream for rollback code (spread, spawn tie-breaks). Cheap; do not cache.
func tick_stream(stream_name: String, tick: int, peer: int = 0) -> RandomNumberGenerator:
	return SeededRng.make_tick(_match_seed, stream_name, tick, peer)
