class_name MoonSlab
extends RefCounted
## The moon chunk's outline: a superellipse |x/rx|^n + |z/rz|^n = 1 round a centre. n = 2 is the
## ellipse the loop board stood on (2026-09-19); the district's slab (2026-09-24) is a rounded
## plot, n about 3, written into the board file by tools/gen_board.gd. Everything that asks "is
## this on the slab", "where is the rim on this ray" or "a spot this far out on this ray" goes
## through here, so the view, the dressing, the annex plan and the machine spot marker agree on
## one shape. No dependencies: the tools run it as a --script without the autoloads.

var centre := Vector3.ZERO
var rx := 20.0
var rz := 20.0
var n := 2.0


static func from_dict(d: Dictionary) -> MoonSlab:
	if d.is_empty():
		return null
	var s := MoonSlab.new()
	var c: Array = d.get("centre", [0.0, 0.0])
	s.centre = Vector3(float(c[0]), 0.0, float(c[1]))
	s.rx = float(d.get("rx", 20.0))
	s.rz = float(d.get("rz", 20.0))
	s.n = float(d.get("n", 2.0))
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


func to_dict() -> Dictionary:
	return {"centre": [snappedf(centre.x, 0.01), snappedf(centre.z, 0.01)],
		"rx": snappedf(rx, 0.01), "rz": snappedf(rz, 0.01), "n": snappedf(n, 0.01)}


## How far out a point sits: 0 at the centre, 1 on the rim, more beyond it.
func f_of(x: float, z: float) -> float:
	var dx := absf(x - centre.x) / rx
	var dz := absf(z - centre.z) / rz
	return pow(pow(dx, n) + pow(dz, n), 1.0 / n)


func inside(x: float, z: float, f_max: float = 1.0) -> bool:
	return f_of(x, z) <= f_max


## The rim on the ray at angle `a` (from +x toward +z), as an offset from the centre.
func rim_offset(a: float) -> Vector2:
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


## The area, for feature counts that keep a density (the superellipse's closed form).
func area() -> float:
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
