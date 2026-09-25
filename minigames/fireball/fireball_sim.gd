class_name FireballSim
extends RefCounted
## The fireball's pure maths, so the tests can run it without a scene: where a reflect sends
## it, how fast it goes after n reflects, how it steers, and whether a step of its flight
## touches a player's hitboxes or passes a guard. Nothing here touches nodes or RNG.


## The player a reflect sends the ball to (Sean: "it reflects to the nearest person where your
## crosshair was aiming at"): of `candidates` ({id, point}), the one whose direction from `eye`
## is closest in angle to `aim`; 0 when there is nobody.
static func pick_reflect_target(eye: Vector3, aim: Vector3, candidates: Array) -> int:
	var best := 0
	var best_dot := -2.0
	for c in candidates:
		var to: Vector3 = (c["point"] as Vector3) - eye
		if to.length_squared() < 1e-6:
			continue
		var d := aim.dot(to.normalized())
		if d > best_dot:
			best_dot = d
			best = int(c["id"])
	return best


## The ball's speed after `level` reflects: the start plus the gain per reflect, capped.
static func speed_for(level: int, cfg: Dictionary) -> float:
	var start := float(cfg.get("speed_start_m_s", 9.0))
	var gain := float(cfg.get("speed_gain_per_reflect_m_s", 1.5))
	var cap := float(cfg.get("speed_max_m_s", 34.0))
	return minf(cap, start + gain * float(level))


## `dir` turned toward `to` by at most `max_angle` radians (both unit vectors).
static func steer(dir: Vector3, to: Vector3, max_angle: float) -> Vector3:
	if to.length_squared() < 1e-9 or dir.length_squared() < 1e-9:
		return dir
	var angle := dir.angle_to(to)
	if angle <= max_angle:
		return to.normalized()
	var axis := dir.cross(to)
	if axis.length_squared() < 1e-9:
		# Straight behind: turn about whichever axis is not the ball's own line.
		axis = dir.cross(Vector3.UP)
		if axis.length_squared() < 1e-9:
			axis = dir.cross(Vector3.RIGHT)
	return dir.rotated(axis.normalized(), max_angle).normalized()


## The closest distance between the segments a→b and c→d.
static func segment_distance(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> float:
	var u := b - a
	var v := d - c
	var w := a - c
	var uu := u.dot(u)
	var uv := u.dot(v)
	var vv := v.dot(v)
	var uw := u.dot(w)
	var vw := v.dot(w)
	var den := uu * vv - uv * uv
	var s := 0.0
	var t := 0.0
	if den > 1e-9:
		s = clampf((uv * vw - vv * uw) / den, 0.0, 1.0)
	t = (uv * s + vw) / vv if vv > 1e-9 else 0.0
	if t < 0.0:
		t = 0.0
		s = clampf(-uw / uu, 0.0, 1.0) if uu > 1e-9 else 0.0
	elif t > 1.0:
		t = 1.0
		s = clampf((uv - uw) / uu, 0.0, 1.0) if uu > 1e-9 else 0.0
	return (a + u * s - (c + v * t)).length()


## True when a ball of `radius` moving from `from` to `to` touches the player's body capsule or
## head sphere (`s`: a HitboxHistory.Sample).
static func step_hits(from: Vector3, to: Vector3, radius: float, s: HitboxHistory.Sample) -> bool:
	if segment_distance(from, to, s.body_a, s.body_b) <= radius + s.body_r:
		return true
	return HitscanMath.point_segment_distance(s.head, from, to) <= radius + s.head_r


## True when a ball moving from `from` to `to` passes inside a guard: within `range_m` of the
## eye at its closest, and within `cone` radians of the aim there.
static func step_guarded(from: Vector3, to: Vector3, eye: Vector3, aim: Vector3, range_m: float, cone: float) -> bool:
	var u := to - from
	var t := 0.0
	if u.length_squared() > 1e-9:
		t = clampf((eye - from).dot(u) / u.length_squared(), 0.0, 1.0)
	var closest := from + u * t
	var rel := closest - eye
	if rel.length() > range_m:
		return false
	if rel.length_squared() < 1e-6:
		return true
	return aim.angle_to(rel) <= cone
