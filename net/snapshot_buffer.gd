class_name SnapshotBuffer
extends RefCounted
## Jitter buffer for remote player presentation. Samples of (tick, origin, yaw, pitch) go in as
## state arrives; the render clock trails the newest sample by interp_delay_ticks and is rate
## adjusted rather than jumped. Past the newest sample it extrapolates for at most
## extrapolate_max_ticks, then holds. A jump larger than snap_distance is a teleport.


class Snap:
	var tick: int = 0
	var origin: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var pitch: float = 0.0


class Sampled:
	var valid: bool = false
	var origin: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var pitch: float = 0.0
	var extrapolated: bool = false
	var starved: bool = false


var interp_delay_ticks: float = 6.0
var extrapolate_max_ticks: float = 2.0
var snap_distance: float = 2.0
var max_rate_error: float = 0.1
var hard_snap_ticks: float = 60.0
var keep_ticks: int = 120

var _snaps: Array[Snap] = []
var _render_tick: float = -1.0


func push(tick: int, origin: Vector3, yaw: float, pitch: float) -> void:
	var s := Snap.new()
	s.tick = tick
	s.origin = origin
	s.yaw = yaw
	s.pitch = pitch
	# Replace an existing sample for the tick, otherwise insert sorted.
	var i := _snaps.size() - 1
	while i >= 0:
		if _snaps[i].tick == tick:
			_snaps[i] = s
			return
		if _snaps[i].tick < tick:
			break
		i -= 1
	_snaps.insert(i + 1, s)
	var min_tick := tick - keep_ticks
	while not _snaps.is_empty() and _snaps[0].tick < min_tick:
		_snaps.remove_at(0)


func latest_tick() -> int:
	return _snaps[-1].tick if not _snaps.is_empty() else -1


func render_tick() -> float:
	return _render_tick


func size() -> int:
	return _snaps.size()


## Advance the render clock by dt_ticks (frame delta × tickrate), steering toward the target.
func advance(dt_ticks: float) -> void:
	if _snaps.is_empty():
		return
	var target := float(latest_tick()) - interp_delay_ticks
	if _render_tick < 0.0:
		_render_tick = target
		return
	var err := target - _render_tick
	if absf(err) > hard_snap_ticks:
		_render_tick = target
		return
	var rate := 1.0 + clampf(err / 10.0, -max_rate_error, max_rate_error)
	_render_tick += dt_ticks * rate


func sample() -> Sampled:
	var out := Sampled.new()
	if _snaps.is_empty() or _render_tick < 0.0:
		return out
	out.valid = true
	var first := _snaps[0]
	var last := _snaps[-1]
	if _render_tick <= float(first.tick):
		_fill(out, first)
		return out
	if _render_tick >= float(last.tick):
		var ahead := _render_tick - float(last.tick)
		_fill(out, last)
		if ahead > 0.0 and _snaps.size() >= 2:
			var prev := _snaps[-2]
			var span := float(last.tick - prev.tick)
			if span > 0.0 and (last.origin - prev.origin).length() <= snap_distance:
				var vel_per_tick := (last.origin - prev.origin) / span
				var use := minf(ahead, extrapolate_max_ticks)
				out.origin = last.origin + vel_per_tick * use
				out.extrapolated = true
				out.starved = ahead > extrapolate_max_ticks
		return out
	# Find bracketing samples
	var hi_i := 1
	while hi_i < _snaps.size() and float(_snaps[hi_i].tick) < _render_tick:
		hi_i += 1
	var a := _snaps[hi_i - 1]
	var b := _snaps[hi_i]
	var span2 := float(b.tick - a.tick)
	var f := 0.0 if span2 <= 0.0 else clampf((_render_tick - float(a.tick)) / span2, 0.0, 1.0)
	if (b.origin - a.origin).length() > snap_distance:
		_fill(out, a if f < 1.0 else b)
		return out
	out.origin = a.origin.lerp(b.origin, f)
	out.yaw = lerp_angle(a.yaw, b.yaw, f)
	out.pitch = lerpf(a.pitch, b.pitch, f)
	return out


func _fill(out: Sampled, s: Snap) -> void:
	out.origin = s.origin
	out.yaw = s.yaw
	out.pitch = s.pitch
