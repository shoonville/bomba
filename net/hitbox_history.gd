class_name HitboxHistory
extends RefCounted
## Per-player ring of hitbox samples keyed by tick, written from inside _rollback_tick so a
## resimulated tick overwrites its entry. sample_at() interpolates between ticks so a fractional
## view tick (what the shooter was rendering) rewinds exactly.


class Sample:
	var head: Vector3 = Vector3.ZERO
	var body_a: Vector3 = Vector3.ZERO
	var body_b: Vector3 = Vector3.ZERO
	var feet: Vector3 = Vector3.ZERO
	var head_r: float = 0.16
	var body_r: float = 0.34
	var alive: bool = true

	func lerp_to(other: Sample, f: float) -> Sample:
		var s := Sample.new()
		s.head = head.lerp(other.head, f)
		s.body_a = body_a.lerp(other.body_a, f)
		s.body_b = body_b.lerp(other.body_b, f)
		s.feet = feet.lerp(other.feet, f)
		s.head_r = head_r
		s.body_r = body_r
		s.alive = alive and other.alive
		return s

	func duplicate_sample() -> Sample:
		return lerp_to(self, 0.0)


var capacity: int = 128
var teleport_distance: float = 2.0
var _samples: Dictionary = {}
var _latest: int = -1
var _earliest: int = -1


func record(tick: int, s: Sample) -> void:
	_samples[tick] = s
	if _latest < 0 or tick > _latest:
		_latest = tick
	if _earliest < 0 or tick < _earliest:
		_earliest = tick
	if _samples.size() > capacity:
		trim(_latest - capacity + 1)


func has(tick: int) -> bool:
	return _samples.has(tick)


func get_tick(tick: int) -> Sample:
	return _samples.get(tick, null)


func latest_tick() -> int:
	return _latest


func earliest_tick() -> int:
	return _earliest


func is_empty() -> bool:
	return _samples.is_empty()


## All recorded (tick, feet) pairs, sorted by tick. For diagnostics.
func dump() -> Array:
	var out := []
	var keys := _samples.keys()
	keys.sort()
	for k in keys:
		out.append([int(k), (_samples[k] as Sample).feet])
	return out


func trim(min_tick: int) -> void:
	var keys := _samples.keys()
	for k in keys:
		if int(k) < min_tick:
			_samples.erase(k)
	_earliest = -1
	for k in _samples.keys():
		if _earliest < 0 or int(k) < _earliest:
			_earliest = int(k)
	if _samples.is_empty():
		_latest = -1


## Sample at a fractional tick, clamped to what is recorded. Missing ticks inside the range are
## bridged by interpolating between the nearest recorded neighbours.
func sample_at(t: float) -> Sample:
	if _samples.is_empty():
		return null
	var tc := clampf(t, float(_earliest), float(_latest))
	var lo_tick := _tick_at_or_below(int(floor(tc)))
	var hi_tick := _tick_at_or_above(int(ceil(tc)))
	if lo_tick < 0:
		return _samples[hi_tick]
	if hi_tick < 0 or hi_tick == lo_tick:
		return _samples[lo_tick]
	var f := (tc - float(lo_tick)) / float(hi_tick - lo_tick)
	if f <= 1e-6:
		return _samples[lo_tick]
	if f >= 1.0 - 1e-6:
		return _samples[hi_tick]
	var lo_s: Sample = _samples[lo_tick]
	var hi_s: Sample = _samples[hi_tick]
	if (hi_s.feet - lo_s.feet).length() > teleport_distance:
		# A respawn: never place the player half way along the teleport.
		return lo_s if f < 0.5 else hi_s
	return lo_s.lerp_to(hi_s, f)


func _tick_at_or_below(tick: int) -> int:
	var t := tick
	while t >= _earliest:
		if _samples.has(t):
			return t
		t -= 1
	return -1


func _tick_at_or_above(tick: int) -> int:
	var t := tick
	while t <= _latest:
		if _samples.has(t):
			return t
		t += 1
	return -1
