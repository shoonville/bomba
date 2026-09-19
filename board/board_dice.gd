class_name BoardDice
extends Node3D
## The roll as an object: a cube in the score colour with ink pips tumbles up from the active
## pawn, lands beside it showing the rolled face, holds, then leaves. Presentation only: the
## value came from the rules, the tumble is a seeded show so screenshots repeat.

signal landed(value: int)

const SIZE := 1.0
const PIP := 0.26
const T_AIR := 0.55
const T_SETTLE := 0.22
const T_HOLD := 0.8

var value: int = 1
var _t: float = 0.0
var _from: Vector3
var _to: Vector3
var _spin_axis: Vector3 = Vector3.UP
var _spin_speed: float = 14.0
var _final: Basis
var _tumble: Basis
var _landed: bool = false
var _done: bool = false


static func face_up_basis(v: int) -> Basis:
	match v:
		6: return Basis(Vector3.RIGHT, PI)          # -Y face up
		2: return Basis(Vector3.BACK, PI * 0.5)     # +X → +Y
		5: return Basis(Vector3.BACK, -PI * 0.5)    # -X → +Y
		3: return Basis(Vector3.RIGHT, -PI * 0.5)   # +Z → +Y
		4: return Basis(Vector3.RIGHT, PI * 0.5)    # -Z → +Y
	return Basis()                                  # 1: +Y already up


static func pips(v: int) -> Array:
	match v:
		1: return [Vector2(0, 0)]
		2: return [Vector2(-1, -1), Vector2(1, 1)]
		3: return [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)]
		4: return [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
		5: return [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)]
		6: return [Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1)]
	return []


static func _basis_with_y(n: Vector3) -> Basis:
	if n.is_equal_approx(Vector3.UP):
		return Basis()
	if n.is_equal_approx(Vector3.DOWN):
		return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, n))


func setup(colour: Color, ink: Color, shadow: Color) -> void:
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * SIZE
	body.mesh = bm
	body.material_override = CelMaterial.for_colour(colour, shadow)
	add_child(body)
	var pip_mat := CelMaterial.for_colour(ink, shadow)
	# face value → [normal, u axis, v axis]; opposite faces sum to 7
	var faces := {
		1: [Vector3.UP, Vector3.RIGHT, Vector3.BACK],
		6: [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		2: [Vector3.RIGHT, Vector3.FORWARD, Vector3.UP],
		5: [Vector3.LEFT, Vector3.BACK, Vector3.UP],
		3: [Vector3.BACK, Vector3.RIGHT, Vector3.UP],
		4: [Vector3.FORWARD, Vector3.LEFT, Vector3.UP],
	}
	for v in faces:
		var n: Vector3 = faces[v][0]
		var u: Vector3 = faces[v][1]
		var w: Vector3 = faces[v][2]
		for o in pips(v):
			var pip := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.09
			cm.bottom_radius = 0.09
			cm.height = 0.02
			cm.radial_segments = 10
			pip.mesh = cm
			pip.material_override = pip_mat
			pip.position = n * (SIZE * 0.5 + 0.006) + u * (o.x * PIP) + w * (o.y * PIP)
			pip.basis = _basis_with_y(n)
			add_child(pip)


func roll(from: Vector3, to: Vector3, p_value: int, rng: RandomNumberGenerator) -> void:
	value = clampi(p_value, 1, 6)
	_from = from
	_to = to
	global_position = from
	_spin_axis = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	if _spin_axis.length() < 0.3:
		_spin_axis = Vector3(1.0, 0.3, 0.2)
	_spin_axis = _spin_axis.normalized()
	_spin_speed = rng.randf_range(11.0, 16.0)
	_final = Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * face_up_basis(value)
	basis = Basis(_spin_axis, rng.randf_range(0.0, TAU))
	_tumble = basis
	_t = 0.0


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t < T_AIR:
		var k := _t / T_AIR
		var pos := _from.lerp(_to, k)
		pos.y = lerpf(_from.y, _to.y, k) + 1.3 * sin(k * PI)
		global_position = pos
		basis = (Basis(_spin_axis, _spin_speed * delta) * basis).orthonormalized()
		_tumble = basis
	elif _t < T_AIR + T_SETTLE:
		var k := (_t - T_AIR) / T_SETTLE
		var e := 1.0 - pow(1.0 - k, 3.0)
		basis = _tumble.slerp(_final, e)
		global_position = _to + Vector3.UP * (0.22 * sin(k * PI) * (1.0 - k))
		if not _landed:
			_landed = true
			landed.emit(value)
	elif _t < T_AIR + T_SETTLE + T_HOLD:
		basis = _final
		global_position = _to
	else:
		_done = true
		queue_free()
