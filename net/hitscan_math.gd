class_name HitscanMath
extends RefCounted
## Analytic ray tests used by hit registration. All functions return the ray parameter t
## (distance along a unit direction) or -1.0 for a miss. Origins inside a shape return 0.0.


static func ray_sphere(origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> float:
	var oc := origin - center
	var c := oc.dot(oc) - radius * radius
	if c <= 0.0:
		return 0.0
	var b := oc.dot(dir)
	if b > 0.0:
		return -1.0  # sphere behind the ray
	var h := b * b - c
	if h < 0.0:
		return -1.0
	var t := -b - sqrt(h)
	return t if t >= 0.0 else -1.0


## Distance from point p to segment ab.
static func point_segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-12:
		return (p - a).length()
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return (p - (a + ab * t)).length()


## Capsule with axis a→b and the given radius (Inigo Quilez's formulation).
static func ray_capsule(origin: Vector3, dir: Vector3, a: Vector3, b: Vector3, radius: float) -> float:
	if point_segment_distance(origin, a, b) <= radius:
		return 0.0
	var ba := b - a
	var oa := origin - a
	var baba := ba.dot(ba)
	if baba < 1e-12:
		return ray_sphere(origin, dir, a, radius)
	var bard := ba.dot(dir)
	var baoa := ba.dot(oa)
	var rdoa := dir.dot(oa)
	var oaoa := oa.dot(oa)
	var a2 := baba - bard * bard
	var b2 := baba * rdoa - baoa * bard
	var c2 := baba * oaoa - baoa * baoa - radius * radius * baba
	if a2 > 1e-9:
		var h := b2 * b2 - a2 * c2
		if h >= 0.0:
			var t := (-b2 - sqrt(h)) / a2
			var y := baoa + t * bard
			if y > 0.0 and y < baba and t >= 0.0:
				return t
	# End caps
	var t_a := ray_sphere(origin, dir, a, radius)
	var t_b := ray_sphere(origin, dir, b, radius)
	if t_a < 0.0:
		return t_b
	if t_b < 0.0:
		return t_a
	return minf(t_a, t_b)


## Rotate a direction by a small yaw/pitch offset in degrees (recoil, spread).
static func offset_direction(dir: Vector3, yaw_deg: float, pitch_deg: float) -> Vector3:
	var d := dir
	var right := d.cross(Vector3.UP)
	if right.length_squared() < 1e-6:
		right = Vector3.RIGHT
	right = right.normalized()
	d = d.rotated(right, deg_to_rad(pitch_deg))
	d = d.rotated(Vector3.UP, deg_to_rad(yaw_deg))
	return d.normalized()


## Deterministic spread offset inside a cone, from a per-tick generator.
static func spread_offset(rng: RandomNumberGenerator, cone_deg: float) -> Vector2:
	if cone_deg <= 0.0:
		return Vector2.ZERO
	var ang := rng.randf() * TAU
	var r := sqrt(rng.randf()) * cone_deg
	return Vector2(cos(ang) * r, sin(ang) * r)
