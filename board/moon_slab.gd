class_name MoonSlab
extends RefCounted
## The moon chunk's outline round a centre. Three shapes: an ellipse (n = 2, the loop board of
## 2026-09-19), a superellipse |x/rx|^n + |z/rz|^n = 1 (the district of 2026-09-24) and, since
## Sean's hand-drawn board (2026-09-24, later that day), a rounded hull: the convex hull of the
## spaces pushed out by a margin, kept as the rim's radius per degree. Everything that asks "is
## this on the slab", "where is the rim on this ray" or "a spot this far out on this ray" goes
## through here, so the view, the dressing, the annex plan and the machine spot marker agree on
## one shape. No dependencies: the tools run it as a --script without the autoloads.

var centre := Vector3.ZERO
var rx := 20.0
var rz := 20.0
var n := 2.0
var radii := PackedFloat32Array()   # the rim's radius per degree (360 entries) when the outline is a hull


static func from_dict(d: Dictionary) -> MoonSlab:
	if d.is_empty():
		return null
	var s := MoonSlab.new()
	var c: Array = d.get("centre", [0.0, 0.0])
	s.centre = Vector3(float(c[0]), 0.0, float(c[1]))
	s.rx = float(d.get("rx", 20.0))
	s.rz = float(d.get("rz", 20.0))
	s.n = float(d.get("n", 2.0))
	for r in d.get("radii", []):
		s.radii.append(float(r))
	if s.radii.size() != 360:
		s.radii = PackedFloat32Array()
	return s


## The ellipse round a set of points (Vector3, y ignored) with a margin: the slab as the view
## built it before board files carried one.
static func around(points: Array, margin_x: float, margin_z: float) -> MoonSlab:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in points:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var s := MoonSlab.new()
	s.centre = Vector3((lo.x + hi.x) * 0.5, 0.0, (lo.y + hi.y) * 0.5)
	s.rx = (hi.x - lo.x) * 0.5 + margin_x
	s.rz = (hi.y - lo.y) * 0.5 + margin_z
	s.n = 2.0
	return s


## A rounded hull: every point within `margin` of the convex hull of `points` (Vector2, x and
## z), so the corners come out as arcs of that radius. The centre is the hull's centroid.
static func from_hull(points: Array, margin: float) -> MoonSlab:
	var hull := _hull(points)
	var c := _centroid(hull)
	var s := MoonSlab.new()
	s.centre = Vector3(c.x, 0.0, c.y)
	s.n = 2.0
	var max_x := 0.0
	var max_z := 0.0
	for i in 360:
		var a := deg_to_rad(float(i))
		var dir := Vector2(cos(a), sin(a))
		var t0 := 0.0
		var t1 := 600.0
		for k in 40:
			var tm := (t0 + t1) * 0.5
			if _dist_to_hull(c + dir * tm, hull) <= margin:
				t0 = tm
			else:
				t1 = tm
		s.radii.append(t0)
		max_x = maxf(max_x, absf(dir.x * t0))
		max_z = maxf(max_z, absf(dir.y * t0))
	s.rx = max_x
	s.rz = max_z
	return s


func to_dict() -> Dictionary:
	var d := {"centre": [snappedf(centre.x, 0.01), snappedf(centre.z, 0.01)],
		"rx": snappedf(rx, 0.01), "rz": snappedf(rz, 0.01), "n": snappedf(n, 0.01)}
	if radii.size() == 360:
		var out := []
		for r in radii:
			out.append(snappedf(r, 0.01))
		d["radii"] = out
	return d


## How far out a point sits: 0 at the centre, 1 on the rim, more beyond it.
func f_of(x: float, z: float) -> float:
	if radii.size() == 360:
		var d := Vector2(x - centre.x, z - centre.z)
		if d.length() < 1e-6:
			return 0.0
		return d.length() / rim_offset(d.angle()).length()
	var dx := absf(x - centre.x) / rx
	var dz := absf(z - centre.z) / rz
	return pow(pow(dx, n) + pow(dz, n), 1.0 / n)


func inside(x: float, z: float, f_max: float = 1.0) -> bool:
	return f_of(x, z) <= f_max


## The rim on the ray at angle `a` (from +x toward +z), as an offset from the centre.
func rim_offset(a: float) -> Vector2:
	if radii.size() == 360:
		var deg := fposmod(rad_to_deg(a), 360.0)
		var i := int(floor(deg))
		var r := lerpf(radii[i % 360], radii[(i + 1) % 360], deg - float(i))
		return Vector2(cos(a), sin(a)) * r
	var c := absf(cos(a))
	var s := absf(sin(a))
	var r := pow(pow(c / rx, n) + pow(s / rz, n), -1.0 / n)
	return Vector2(cos(a) * r, sin(a) * r)


func rim(a: float) -> Vector2:
	return Vector2(centre.x, centre.z) + rim_offset(a)


## The point `f` of the way out along the ray at angle `a`.
func point(a: float, f: float) -> Vector2:
	return Vector2(centre.x, centre.z) + rim_offset(a) * f


## The ray angle of a point.
func angle_of(x: float, z: float) -> float:
	return atan2(z - centre.z, x - centre.x)


## The area, for feature counts that keep a density.
func area() -> float:
	if radii.size() == 360:
		var total := 0.0
		for i in 360:
			total += 0.5 * radii[i] * radii[(i + 1) % 360] * sin(deg_to_rad(1.0))
		return total
	var g := _gamma(1.0 + 1.0 / n)
	return 4.0 * rx * rz * g * g / _gamma(1.0 + 2.0 / n)


## The outline as `count` rim points at even angles, each pushed in or out by up to `wobble` of
## its radius (seeded), for the slab mesh.
func outline(count: int, wobble: float = 0.0, rng: RandomNumberGenerator = null) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in count:
		var a := TAU * i / count
		var f := 1.0
		if rng != null and wobble > 0.0:
			f += rng.randf_range(-wobble, wobble)
		out.append(rim_offset(a) * f)
	return out


## The convex hull of Vector2 points (monotone chain), counter-clockwise in x-right, z-down terms.
static func _hull(points: Array) -> Array:
	var pts: Array = []
	for p in points:
		pts.append(Vector2(p.x, p.y))
	pts.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x or (a.x == b.x and a.y < b.y))
	if pts.size() < 3:
		return pts
	var lower: Array = []
	for p in pts:
		while lower.size() >= 2 and _cross(lower[-2], lower[-1], p) <= 0.0:
			lower.pop_back()
		lower.append(p)
	var upper: Array = []
	for i in range(pts.size() - 1, -1, -1):
		var p: Vector2 = pts[i]
		while upper.size() >= 2 and _cross(upper[-2], upper[-1], p) <= 0.0:
			upper.pop_back()
		upper.append(p)
	lower.pop_back()
	upper.pop_back()
	return lower + upper


static func _cross(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)


static func _centroid(hull: Array) -> Vector2:
	var area2 := 0.0
	var c := Vector2.ZERO
	for i in hull.size():
		var a: Vector2 = hull[i]
		var b: Vector2 = hull[(i + 1) % hull.size()]
		var w := a.x * b.y - b.x * a.y
		area2 += w
		c += (a + b) * w
	if absf(area2) < 1e-6:
		var m := Vector2.ZERO
		for p in hull:
			m += p
		return m / maxf(1.0, hull.size())
	return c / (3.0 * area2)


## Distance from a point to the hull: 0 inside, else to the nearest edge.
static func _dist_to_hull(p: Vector2, hull: Array) -> float:
	var inside_all := true
	var best := 1e9
	for i in hull.size():
		var a: Vector2 = hull[i]
		var b: Vector2 = hull[(i + 1) % hull.size()]
		if _cross(a, b, p) < 0.0:
			inside_all = false
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		best = minf(best, (a + ab * t).distance_to(p))
	return 0.0 if inside_all else best


## Lanczos approximation, enough for the area.
static func _gamma(x: float) -> float:
	if x < 0.5:
		return PI / (sin(PI * x) * _gamma(1.0 - x))
	x -= 1.0
	var g := 7.0
	var coef := [0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313,
		-176.61502916214059, 12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6,
		1.5056327351493116e-7]
	var a: float = coef[0]
	var t := x + g + 0.5
	for i in range(1, 9):
		a += float(coef[i]) / (x + i)
	return sqrt(2.0 * PI) * pow(t, x + 0.5) * exp(-t) * a
