class_name Figure
extends Node3D
## A humanoid from primitives, the same figure for other players in the arena, the pawns on
## the board and the results podium: built to Sean's FLCL references (Canti, the TV-headed
## robot: reference/char1.webp and char2.jpg.webp), the identity colour on the jacket and ears.
## Animated procedurally: walk swing from speed, a tuck in the air, arms up on a gun while
## aiming, and a tip-over when dead. No assets, no rig.

var head: Node3D            # pivot at the neck; rotate x for pitch
var _torso: Node3D
var _l_arm: Node3D
var _r_arm: Node3D
var _l_leg: Node3D
var _r_leg: Node3D
var _gun: Node3D
var _gun_long: Node3D
var _gun_short: Node3D
var _phase: float = 0.0
var _tilt: float = 0.0
var _flinch: float = 0.0
var _has_gun: bool = false

const SHOULDER_Y := 1.42
const HIP_Y := 0.98


var _skates: bool = false


## `skates`: rollerskates under the boots and the push-glide walk (the board pawns; Sean did not
## want them hopping across the board).
func build(colour: Color, map_id: String, head_y: float = 1.62, with_gun: bool = false, skates: bool = false) -> void:
	_skates = skates
	# Built to reference/char1.webp and char2.jpg.webp (Bomb Rush Cyberfunk's robots): a boxy
	# screen head with side ears on a thin neck, an open bomber jacket in the identity colour
	# over a dark mechanical core, a belt, thin jointed arms with cream forearm guards and dark
	# gloves, long thin legs with knee joints, chunky boots with red soles.
	_has_gun = with_gun
	var col := Palette.under_ceiling(colour)
	var shadow := Palette.map_colour(map_id, "shadow_tint")
	var ink := Palette.map_colour(map_id, "line")
	var body_mat := CelMaterial.for_colour(col, shadow)
	var body_dark_mat := CelMaterial.for_colour(Color.from_hsv(col.h, minf(1.0, col.s * 1.1), col.v * 0.72), shadow)
	var dark_mat := CelMaterial.for_colour(Color.from_hsv(ink.h, 0.45, 0.24), shadow)
	var cream_mat := CelMaterial.for_colour(Palette.hud_colour("paper"), shadow)
	var pants_mat := CelMaterial.for_colour(Color.from_hsv(ink.h, 0.5, 0.36), shadow)
	var metal_mat := CelMaterial.for_colour(Color.from_hsv(ink.h, 0.18, 0.58), shadow)
	var shirt_mat := CelMaterial.for_colour(Palette.hud_colour("score"), shadow)
	var sole_mat := CelMaterial.for_colour(Palette.hud_colour("danger"), shadow)
	var screen_mat := CelMaterial.for_colour(Color.from_hsv(ink.h, 0.5, 0.16), shadow)
	var glow_mat := CelMaterial.for_colour(Palette.hud_colour("meter"), shadow, 0.9)

	# Torso group (bobs and flinches as one): the core, the jacket, the belt.
	_torso = Node3D.new()
	_torso.position = Vector3(0, (SHOULDER_Y + HIP_Y) * 0.5, 0)
	add_child(_torso)
	var ty := -(SHOULDER_Y + HIP_Y) * 0.5   # torso-local offset so children can use world heights
	_capsule(_torso, 0.12, 0.40, Vector3(0, ty + 1.22, 0), dark_mat)                 # mechanical core
	for k in 4:
		_box(_torso, Vector3(0.2, 0.02, 0.22), Vector3(0, ty + 1.1 + 0.07 * k, 0), metal_mat)   # ribs
	_box(_torso, Vector3(0.1, 0.18, 0.05), Vector3(0, ty + 1.3, -0.12), shirt_mat)     # shirt in the opening
	for sx: float in [-1.0, 1.0]:
		_box(_torso, Vector3(0.14, 0.38, 0.11), Vector3(sx * 0.12, ty + 1.25, -0.1), body_mat)   # jacket fronts
		_box(_torso, Vector3(0.14, 0.05, 0.11), Vector3(sx * 0.12, ty + 1.05, -0.1), cream_mat)  # ribbed hem
		_box(_torso, Vector3(0.16, 0.09, 0.26), Vector3(sx * 0.2, ty + 1.43, 0.0), body_mat)     # shoulder caps
	_box(_torso, Vector3(0.38, 0.4, 0.12), Vector3(0, ty + 1.25, 0.1), body_mat)         # jacket back
	_box(_torso, Vector3(0.38, 0.05, 0.12), Vector3(0, ty + 1.05, 0.1), cream_mat)
	_box(_torso, Vector3(0.32, 0.07, 0.24), Vector3(0, ty + 1.47, 0.0), body_dark_mat)   # collar
	_box(_torso, Vector3(0.3, 0.07, 0.22), Vector3(0, ty + 1.0, 0.0), dark_mat)          # belt
	_box(_torso, Vector3(0.08, 0.05, 0.03), Vector3(0, ty + 1.0, -0.115), cream_mat)     # buckle
	_cyl(self, 0.045, 0.14, Vector3(0, head_y - 0.16, 0), dark_mat)                     # neck

	# Head: a boxy screen on a thin neck, tilted down a touch, ears in the identity colour.
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, head_y, 0)
	add_child(head)
	_box(head, Vector3(0.36, 0.26, 0.30), Vector3(0, 0.0, 0.0), cream_mat)              # shell
	_box(head, Vector3(0.28, 0.16, 0.02), Vector3(0, -0.01, -0.152), screen_mat)         # screen
	_box(head, Vector3(0.24, 0.02, 0.006), Vector3(0, 0.02, -0.163), glow_mat)           # scanline
	_box(head, Vector3(0.38, 0.05, 0.32), Vector3(0, 0.15, 0.0), body_dark_mat)          # top plate
	_box(head, Vector3(0.12, 0.03, 0.1), Vector3(0, 0.185, 0.04), dark_mat)              # vent
	for sx: float in [-1.0, 1.0]:
		var ear := _cyl(head, 0.055, 0.05, Vector3(sx * 0.2, 0.0, 0.02), body_mat)
		ear.rotation.z = PI * 0.5
		var ear_cap := _cyl(head, 0.03, 0.02, Vector3(sx * 0.235, 0.0, 0.02), dark_mat)
		ear_cap.rotation.z = PI * 0.5

	# Arms: shoulder ball, sleeve, elbow ball, dark forearm with a cream guard, dark glove.
	_l_arm = _arm(Vector3(-0.27, SHOULDER_Y, 0), body_mat, dark_mat, cream_mat, metal_mat)
	_r_arm = _arm(Vector3(0.27, SHOULDER_Y, 0), body_mat, dark_mat, cream_mat, metal_mat)
	# Legs: thin thigh, knee ball, shin, chunky boot with a red sole and a cream toe cap.
	_l_leg = _leg(Vector3(-0.11, HIP_Y, 0), pants_mat, metal_mat, dark_mat, cream_mat, sole_mat, body_mat)
	_r_leg = _leg(Vector3(0.11, HIP_Y, 0), pants_mat, metal_mat, dark_mat, cream_mat, sole_mat, body_mat)

	if with_gun:
		# The gun runs along the arm's own axis (local -Y, the hand direction), so when the arm
		# swings forward to aim, the gun points forward too.
		_gun = Node3D.new()
		_gun.position = Vector3(0, -0.62, 0)
		_r_arm.add_child(_gun)
		_gun_long = Node3D.new()
		_gun.add_child(_gun_long)
		_box(_gun_long, Vector3(0.06, 0.95, 0.08), Vector3(-0.1, -0.3, 0.0), cream_mat)
		_box(_gun_long, Vector3(0.05, 0.28, 0.05), Vector3(-0.1, -0.35, 0.075), dark_mat)
		_box(_gun_long, Vector3(0.05, 0.14, 0.05), Vector3(-0.1, 0.02, 0.0), dark_mat)
		_gun_short = Node3D.new()
		_gun.add_child(_gun_short)
		_box(_gun_short, Vector3(0.06, 0.5, 0.1), Vector3(-0.1, -0.12, 0.0), body_mat)
		_box(_gun_short, Vector3(0.05, 0.12, 0.05), Vector3(-0.1, -0.2, -0.08), dark_mat)
		_gun_short.visible = false


func _arm(pivot: Vector3, sleeve_mat: Material, dark_mat: Material, guard_mat: Material, joint_mat: Material) -> Node3D:
	var n := Node3D.new()
	n.position = pivot
	add_child(n)
	_sphere(n, 0.07, Vector3.ZERO, joint_mat)
	_capsule(n, 0.05, 0.3, Vector3(0, -0.17, 0), sleeve_mat)
	_sphere(n, 0.055, Vector3(0, -0.34, 0), joint_mat)
	_capsule(n, 0.042, 0.26, Vector3(0, -0.49, 0), dark_mat)
	_box(n, Vector3(0.1, 0.2, 0.11), Vector3(0, -0.47, 0), guard_mat)
	_box(n, Vector3(0.11, 0.12, 0.11), Vector3(0, -0.66, 0), dark_mat)
	return n


func _leg(pivot: Vector3, pants_mat: Material, joint_mat: Material, boot_mat: Material, cap_mat: Material, sole_mat: Material, stripe_mat: Material) -> Node3D:
	var n := Node3D.new()
	n.position = pivot
	add_child(n)
	_capsule(n, 0.065, 0.42, Vector3(0, -0.21, 0), pants_mat)
	_sphere(n, 0.075, Vector3(0, -0.42, 0), joint_mat)
	_capsule(n, 0.06, 0.38, Vector3(0, -0.61, 0), pants_mat)
	_box(n, Vector3(0.2, 0.13, 0.34), Vector3(0, -0.895, -0.04), boot_mat)
	_box(n, Vector3(0.21, 0.03, 0.35), Vector3(0, -0.965, -0.04), sole_mat)
	_box(n, Vector3(0.2, 0.08, 0.1), Vector3(0, -0.9, -0.18), cap_mat)
	_box(n, Vector3(0.21, 0.03, 0.12), Vector3(0, -0.84, -0.04), stripe_mat)
	if _skates:
		# Rollerskates: a plate under the sole and two wheels each side, axles across the boot.
		_box(n, Vector3(0.16, 0.025, 0.3), Vector3(0, -0.99, -0.04), joint_mat)
		for wz: float in [-0.15, 0.07]:
			for wx: float in [-0.075, 0.075]:
				var wheel := _cyl(n, 0.045, 0.035, Vector3(wx, -1.03, wz), boot_mat)
				wheel.rotation.z = PI * 0.5
	return n


## Which held gun shows: 0 the long rifle, anything else the short one.
func set_weapon_slot(slot: int) -> void:
	if _gun_long != null:
		_gun_long.visible = slot == 0
		_gun_short.visible = slot != 0


## A hit: the torso and head jerk back for a quarter second.
func flinch() -> void:
	_flinch = 1.0


var _aiming: bool = false


## Board aiming (the laser gun): the right arm comes up straight out in front, the hand leading,
## and stays there while `on`; the left arm keeps its walk swing.
func set_aiming(on: bool) -> void:
	_aiming = on


## The right hand's node, for a held prop; the hand is 0.62 down the arm's local -Y.
func hand_node() -> Node3D:
	return _r_arm


## Speed in m/s, on_floor, look pitch (radians, up positive), alive. Call every frame.
func animate(speed: float, on_floor: bool, pitch: float, alive: bool, delta: float) -> void:
	_flinch = maxf(0.0, _flinch - delta * 4.5)
	if not alive:
		_tilt = move_toward(_tilt, 1.0, delta * 3.5)
	else:
		_tilt = move_toward(_tilt, 0.0, delta * 6.0)
	rotation.x = -_tilt * 1.45
	position.y = _tilt * 0.12
	var run := clampf(speed / 6.0, 0.0, 1.0)
	_phase += delta * (5.0 + speed * 1.7)
	var swing := sin(_phase) * 0.8 * run
	if _skates:
		# The push-glide: one leg sweeps back and out to the side while the other carries the
		# weight, then they swap; the arms swing against the legs and the torso leans in.
		var t := _phase * 0.5
		var push_l := maxf(0.0, sin(t)) * run
		var push_r := maxf(0.0, -sin(t)) * run
		_l_leg.rotation.x = -0.9 * push_l + 0.15 * run * (1.0 - push_l)
		_r_leg.rotation.x = -0.9 * push_r + 0.15 * run * (1.0 - push_r)
		_l_leg.rotation.z = -0.28 * push_l
		_r_leg.rotation.z = 0.28 * push_r
		_l_arm.rotation.x = 0.55 * (push_r - push_l)
		_r_arm.rotation.x = 0.55 * (push_l - push_r)
		head.rotation.x = -0.1 + _flinch * 0.35
		_torso.rotation.x = _flinch * 0.22 - 0.22 * run
		_torso.position.y = (SHOULDER_Y + HIP_Y) * 0.5 + sin(_phase * 0.45) * 0.008
		return
	if on_floor:
		_l_leg.rotation.x = swing
		_r_leg.rotation.x = -swing
	else:
		_l_leg.rotation.x = lerpf(_l_leg.rotation.x, 0.6, delta * 8.0)
		_r_leg.rotation.x = lerpf(_r_leg.rotation.x, -0.3, delta * 8.0)
	if _has_gun:
		# Both arms up on the gun, following the look pitch; the gun points where the head looks.
		var aim := PI * 0.5 + pitch
		_r_arm.rotation.x = aim
		_l_arm.rotation.x = aim
		_l_arm.rotation.y = -0.55   # the left hand reaches in to the gun
		_l_arm.rotation.z = 0.0
	elif _aiming:
		_l_arm.rotation.x = -swing * 0.7
		_r_arm.rotation.x = lerpf(_r_arm.rotation.x, PI * 0.5, minf(1.0, delta * 10.0))
	elif on_floor:
		_l_arm.rotation.x = -swing * 0.7
		_r_arm.rotation.x = swing * 0.7
	else:
		_l_arm.rotation.x = lerpf(_l_arm.rotation.x, -0.9, delta * 8.0)
		_r_arm.rotation.x = lerpf(_r_arm.rotation.x, -0.9, delta * 8.0)
	head.rotation.x = -0.1 + pitch * (0.35 if _has_gun else 1.0) + _flinch * 0.35
	_torso.rotation.x = _flinch * 0.22
	_torso.position.y = (SHOULDER_Y + HIP_Y) * 0.5 + sin(_phase * 0.45) * 0.008


func _node(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _capsule(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = maxf(height, radius * 2.0)
	cm.radial_segments = 12
	cm.rings = 4
	return _node(parent, cm, pos, mat)


func _sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	return _node(parent, sm, pos, mat)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _node(parent, bm, pos, mat)


func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 12
	return _node(parent, cm, pos, mat)
