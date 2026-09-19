class_name Figure
extends Node3D
## A humanoid from primitives, the same figure for other players in the arena and for the
## pawns on the board: chunky Bomb Rush proportions (big head, hoodie, big sneakers), the
## identity colour on the hoodie and cap, cream shoes and pack, ink for skin, gloves and pants.
## Animated procedurally: walk swing from speed, a tuck in the air, arms up on a gun while
## aiming, and a tip-over when dead. No assets, no rig.

var head: Node3D            # pivot at the neck; rotate x for pitch
var _torso: MeshInstance3D
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

const SHOULDER_Y := 1.38
const HIP_Y := 0.84


func build(colour: Color, map_id: String, head_y: float = 1.62, with_gun: bool = false) -> void:
	_has_gun = with_gun
	var col := Palette.under_ceiling(colour)
	var shadow := Palette.map_colour(map_id, "shadow_tint")
	var ink := Palette.map_colour(map_id, "line")
	var body_mat := CelMaterial.for_colour(col, shadow)
	var dark_mat := CelMaterial.for_colour(Color.from_hsv(ink.h, 0.45, 0.24), shadow)
	var cream_mat := CelMaterial.for_colour(Palette.hud_colour("paper"), shadow)
	var pants_mat := CelMaterial.for_colour(Color.from_hsv(ink.h, 0.5, 0.34), shadow)
	var visor_mat := CelMaterial.for_colour(Palette.hud_colour("meter"), shadow, 0.9)
	# torso: hoodie
	_torso = _capsule(self, 0.24, 0.66, Vector3(0, (SHOULDER_Y + HIP_Y) * 0.5, 0), body_mat)
	_sphere(self, 0.16, Vector3(0, SHOULDER_Y + 0.02, 0.13), body_mat)              # hood
	_box(self, Vector3(0.34, 0.36, 0.16), Vector3(0, 1.14, 0.27), cream_mat)          # pack
	_box(self, Vector3(0.36, 0.05, 0.03), Vector3(0, 1.3, 0.2), dark_mat)             # strap
	# head with cap and visor
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, head_y, 0)
	add_child(head)
	_sphere(head, 0.19, Vector3.ZERO, dark_mat)
	var cap := _cyl(head, 0.21, 0.09, Vector3(0, 0.12, 0.01), body_mat)
	cap.rotation.x = 0.0
	_box(head, Vector3(0.28, 0.03, 0.18), Vector3(0, 0.1, -0.2), body_mat)           # brim
	_box(head, Vector3(0.26, 0.06, 0.06), Vector3(0, -0.01, -0.19), visor_mat)        # visor
	# arms
	_l_arm = _limb(Vector3(-0.31, SHOULDER_Y, 0), 0.085, 0.56, body_mat, dark_mat, 0.1)
	_r_arm = _limb(Vector3(0.31, SHOULDER_Y, 0), 0.085, 0.56, body_mat, dark_mat, 0.1)
	# legs with sneakers
	_l_leg = _limb(Vector3(-0.13, HIP_Y, 0), 0.105, 0.62, pants_mat, null, 0.0)
	_r_leg = _limb(Vector3(0.13, HIP_Y, 0), 0.105, 0.62, pants_mat, null, 0.0)
	for leg in [_l_leg, _r_leg]:
		_box(leg, Vector3(0.24, 0.16, 0.4), Vector3(0, -0.76, -0.05), cream_mat)
		_box(leg, Vector3(0.25, 0.05, 0.41), Vector3(0, -0.83, -0.05), dark_mat)
		_box(leg, Vector3(0.26, 0.05, 0.12), Vector3(0, -0.74, 0.1), body_mat)
	if with_gun:
		# The gun runs along the arm's own axis (local -Y, the hand direction), so when the arm
		# swings forward to aim, the gun points forward too.
		_gun = Node3D.new()
		_gun.position = Vector3(0, -0.5, 0)
		_r_arm.add_child(_gun)
		# Two guns, one shown at a time: the long rifle with a scope, the short carbine.
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


## Which held gun shows: 0 the long rifle, anything else the short one.
func set_weapon_slot(slot: int) -> void:
	if _gun_long != null:
		_gun_long.visible = slot == 0
		_gun_short.visible = slot != 0


## A hit: the torso and head jerk back for a quarter second.
func flinch() -> void:
	_flinch = 1.0


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
	elif on_floor:
		_l_arm.rotation.x = -swing * 0.7
		_r_arm.rotation.x = swing * 0.7
	else:
		_l_arm.rotation.x = lerpf(_l_arm.rotation.x, -0.9, delta * 8.0)
		_r_arm.rotation.x = lerpf(_r_arm.rotation.x, -0.9, delta * 8.0)
	head.rotation.x = pitch * (0.35 if _has_gun else 1.0) + _flinch * 0.35
	_torso.rotation.x = _flinch * 0.22
	_torso.position.y = (SHOULDER_Y + HIP_Y) * 0.5 + sin(_phase * 0.45) * 0.008


func _limb(pivot: Vector3, radius: float, length: float, mat: Material, tip_mat: Material, tip_radius: float) -> Node3D:
	var n := Node3D.new()
	n.position = pivot
	add_child(n)
	_capsule(n, radius, length, Vector3(0, -length * 0.5 - radius * 0.2, 0), mat)
	if tip_mat != null:
		_sphere(n, tip_radius, Vector3(0, -length - radius * 0.1, 0), tip_mat)
	return n


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
