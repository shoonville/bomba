class_name BoardDice
extends Node3D
## The roll as an object: an eight-sided die (octahedron) in the score colour with ink numbers
## tumbles up from the active pawn, lands beside it with the rolled face on top, holds, then
## leaves. Presentation only: the value came from the rules, the tumble is a seeded show so
## screenshots repeat. Opposite faces sum to 9, like a real d8.

signal landed(value: int)

const RADIUS := 0.8                    # centre to vertex
const INRADIUS := RADIUS / sqrt(3.0)   # centre to a face: the resting height
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


## Sign triple of the face that carries `v`: the octahedron's faces are the octants.
static func face_signs(v: int) -> Vector3:
	match v:
		1: return Vector3(1, 1, 1)
		2: return Vector3(1, 1, -1)
		3: return Vector3(-1, 1, 1)
		4: return Vector3(-1, 1, -1)
		5: return Vector3(1, -1, 1)
		6: return Vector3(1, -1, -1)
		7: return Vector3(-1, -1, 1)
		8: return Vector3(-1, -1, -1)
	return Vector3(1, 1, 1)


static func face_normal(v: int) -> Vector3:
	return face_signs(v).normalized()


## The rotation that brings face `v` to the top.
static func face_up_basis(v: int) -> Basis:
	var n := face_normal(v)
	if n.is_equal_approx(Vector3.UP):
		return Basis()
	return Basis(Quaternion(n, Vector3.UP))


## Text "up" on face `v` in die space: from the face centroid toward its Y vertex.
static func face_text_up(v: int) -> Vector3:
	var sg := face_signs(v)
	var centroid := sg * RADIUS / 3.0
	return (Vector3(0, sg.y * RADIUS, 0) - centroid).normalized()


func setup(colour: Color, ink: Color, shadow: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in range(1, 9):
		var sg := face_signs(v)
		var a := Vector3(sg.x * RADIUS, 0, 0)
		var b := Vector3(0, sg.y * RADIUS, 0)
		var c := Vector3(0, 0, sg.z * RADIUS)
		# (b-a)x(c-a) points outward when the signs multiply to +1; Godot wants clockwise front
		# faces, so that case takes a, c, b and the other takes a, b, c.
		var tri := [a, c, b] if sg.x * sg.y * sg.z > 0.0 else [a, b, c]
		st.set_normal(face_normal(v))
		for p in tri:
			st.add_vertex(p)
	var body := MeshInstance3D.new()
	body.mesh = st.commit()
	body.material_override = CelMaterial.for_colour(colour, shadow)
	add_child(body)
	for v in range(1, 9):
		var n := face_normal(v)
		var label := Label3D.new()
		label.text = "%d" % v
		label.font_size = 84
		label.pixel_size = 0.0054
		label.outline_size = 0
		label.modulate = ink
		label.double_sided = false
		label.alpha_cut = Label3D.ALPHA_CUT_DISCARD   # opaque pass: under the outline post quad
		label.position = face_signs(v) * RADIUS / 3.0 + n * 0.012
		label.basis = Basis.looking_at(-n, face_text_up(v))
		add_child(label)


## `text_dir` (flat, world) is where the top of the landed number should point: away from the
## viewer, so it reads upright from the camera.
func roll(from: Vector3, to: Vector3, p_value: int, rng: RandomNumberGenerator, text_dir: Vector3 = Vector3.FORWARD) -> void:
	value = clampi(p_value, 1, 8)
	_from = from
	_to = to
	global_position = from
	_spin_axis = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	if _spin_axis.length() < 0.3:
		_spin_axis = Vector3(1.0, 0.3, 0.2)
	_spin_axis = _spin_axis.normalized()
	_spin_speed = rng.randf_range(11.0, 16.0)
	var up_basis := face_up_basis(value)
	var text_up := up_basis * face_text_up(value)
	text_up.y = 0.0
	var want := Vector3(text_dir.x, 0.0, text_dir.z)
	var yaw := 0.0
	if text_up.length() > 0.01 and want.length() > 0.01:
		text_up = text_up.normalized()
		want = want.normalized()
		yaw = atan2(text_up.cross(want).y, text_up.dot(want))
	_final = Basis(Vector3.UP, yaw) * up_basis
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
