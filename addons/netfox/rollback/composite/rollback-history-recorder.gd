extends RefCounted
class_name _RollbackHistoryRecorder

# Provided externally by RBS
var _state_history: _PropertyHistoryBuffer
var _input_history: _PropertyHistoryBuffer

var _state_property_config: _PropertyConfig
var _input_property_config: _PropertyConfig

var _property_cache: PropertyCache

var _latest_state_tick: int
var _skipset: _Set
# BOMBA patch (see addons/netfox/PATCHES.md): set by RollbackSynchronizer before record_state().
var _simulated_this_tick: bool = true

func configure(
		p_state_history: _PropertyHistoryBuffer, p_input_history: _PropertyHistoryBuffer,
		p_state_property_config: _PropertyConfig, p_input_property_config: _PropertyConfig,
		p_property_cache: PropertyCache,
		p_skipset: _Set
	) -> void:
	_state_history = p_state_history
	_input_history = p_input_history
	_state_property_config = p_state_property_config
	_input_property_config = p_input_property_config
	_property_cache = p_property_cache
	_skipset = p_skipset

func set_latest_state_tick(p_latest_state_tick: int) -> void:
	_latest_state_tick = p_latest_state_tick

## BOMBA patch: whether any managed node was simulated for the tick about to be recorded.
func set_simulated_this_tick(p_simulated: bool) -> void:
	_simulated_this_tick = p_simulated

func apply_state(tick: int) -> void:
	# Apply state for tick
	var state = _state_history.get_history(tick)
	state.apply(_property_cache)

func apply_display_state() -> void:
	# BOMBA patch #2 (see addons/netfox/PATCHES.md): never display older than the newest known
	# state. If this peer's clock runs behind the state owner's, received states carry ticks
	# greater than display_tick and get_history() would fall back to the *oldest* entry.
	apply_state(maxi(NetworkRollback.display_tick, _latest_state_tick))

func apply_tick(tick: int) -> void:
	var state := _state_history.get_history(tick)
	var input := _input_history.get_history(tick)

	state.apply(_property_cache)
	input.apply(_property_cache)

func trim_history() -> void:
	# Trim history
	_state_history.trim()
	_input_history.trim()

func record_input(tick: int) -> void:
	# Record input
	if not _get_recorded_input_props().is_empty():
		var input = _PropertySnapshot.extract(_get_recorded_input_props())
		var input_tick: int = tick + NetworkRollback.input_delay
		_input_history.set_snapshot(input_tick, input)

func record_state(tick: int) -> void:
	# Record state for specified tick ( current + 1 )
	# Check if any of the managed nodes were mutated
	var is_mutated := _get_recorded_state_props().any(func(pe):
		return NetworkRollback.is_mutated(pe.node, tick - 1))

	var record_state := _PropertySnapshot.extract(_get_state_props_to_record(tick))
	if record_state.size():
		var merge_state := _state_history.get_history(tick - 1)
		_state_history.set_snapshot(tick, merge_state.merge(record_state))

func _should_record_tick(tick: int) -> bool:
	if _get_recorded_state_props().is_empty():
		# Don't record tick if there's no props to record
		return false

	if _get_recorded_state_props().any(func(pe):
		return NetworkRollback.is_mutated(pe.node, tick - 1)):
		# If there's any node that was mutated, there's something to record
		return true

	# Otherwise, record only if we don't have authoritative state for the tick
	# BOMBA patch: ...and only if something was simulated for it. A node in pure state playback
	# (a remote player on a client with input broadcast off) must not overwrite received states
	# with copies of an older state under newer tick numbers; that makes get_history(display_tick)
	# return the stale copy instead of the newest received state.
	return tick > _latest_state_tick and _simulated_this_tick

func _get_state_props_to_record(tick: int) -> Array[PropertyEntry]:
	if not _should_record_tick(tick):
		return []
	if _skipset.is_empty():
		return _get_recorded_state_props()

	return _get_recorded_state_props().filter(func(pe): return _should_record_property(pe, tick))

func _should_record_property(property_entry: PropertyEntry, tick: int) -> bool:
	if NetworkRollback.is_mutated(property_entry.node, tick - 1):
		return true
	if _skipset.has(property_entry.node):
		return false
	return true

# =============================================================================
# Shared utils, extract later

func _get_recorded_state_props() -> Array[PropertyEntry]:
	return _state_property_config.get_properties()

func _get_owned_state_props() -> Array[PropertyEntry]:
	return _state_property_config.get_owned_properties()

func _get_recorded_input_props() -> Array[PropertyEntry]:
	return _input_property_config.get_owned_properties()

func _get_owned_input_props() -> Array[PropertyEntry]:
	return _input_property_config.get_owned_properties()
