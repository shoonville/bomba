class_name Figure
extends Node3D
## A humanoid from primitives, the same figure for other players in the arena, the pawns on
## the board and the results podium: built to Sean's Canti reference (FLCL's TV-headed robot,
## the late-90s mecha look he asked for on 2026-09-22), the identity colour on the armour.
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
var _katana: Node3D
var _guard: float = 0.0   # the katana held up in the guard (the reflect), eased 0..1
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
	# Built to Sean's Canti reference (FLCL's TV-headed robot, late-90s mecha lines): a boxy
	# head shaped like an iMac G3 in profile (his second picture: a flat bezel, a big rounded dome
	# behind it, no handle), a dark visor band with a lit slit, an ear piece on the right; broad rounded chest armour in the identity colour over a narrow dark mechanical
	# waist, a red collar trim and a small badge, a red pelvis plate with a buckle, a backpack
	# unit; ball shoulders under round pauldrons, dark upper arms, flared gauntlets with a pale
	# cuff, dark gloves with fingers; armoured thighs, ball knees with red kneecaps, flared shins
	# into big boots with red toe caps and dark soles.
	_has_gun = with_gun
	var col := Palette.under_ceiling(colour)
	var shadow := Palette.map_colour(map_id, "shadow_tint")
	var ink := Palette.map_colour(map_id, "line")
	var body_mat := CelMaterial.for_colour(col, shadow)
	var body_dark_mat := CelMaterial.for_colour(Color.from_hsv(col.h, minf(1.0, col.s * 1.1), col.v * 0.74), shadow)
	var body_light_mat := CelMaterial.for_colour(Color.from_hsv(col.h, col.s * 0.62, minf(1.0, col.v * 1.12)), shadow)
	var dark_mat := CelMaterial.for_colour(Color.from_hsv(ink.h, 0.45, 0.24), shadow)
	var metal_mat := CelMaterial.for_colour(Color.from_hsv(ink.h, 0.18, 0.58), shadow)
	var red_mat := CelMaterial.for_colour(Palette.hud_colour("danger"), shadow)
	var badge_mat := CelMaterial.for_colour(Palette.hud_colour("score"), shadow, 0.4)
	var cream_mat := CelMaterial.for_colour(Palette.hud_colour("paper"), shadow)
	var screen_mat := CelMaterial.for_colour(Color.from_hsv(ink.h, 0.5, 0.14), shadow)
	var glow_mat := CelMaterial.for_colour(Palette.hud_colour("meter"), shadow, 1.1)

	# Torso group (bobs and flinches as one): the chest armour, the waist, the pelvis, the pack.
	_torso = Node3D.new()
	_torso.position = Vector3(0, (SHOULDER_Y + HIP_Y) * 0.5, 0)
	add_child(_torso)
	var ty := -(SHOULDER_Y + HIP_Y) * 0.5   # torso-local offset so children can use world heights
	_box(_torso, Vector3(0.42, 0.32, 0.26), Vector3(0, ty + 1.27, 0.0), body_mat)             # chest armour
	_box(_torso, Vector3(0.34, 0.1, 0.30), Vector3(0, ty + 1.1, 0.0), body_mat)               # its lower rim
	_box(_torso, Vector3(0.46, 0.08, 0.28), Vector3(0, ty + 1.44, 0.0), body_dark_mat)        # clavicle plate
	_box(_torso, Vector3(0.28, 0.2, 0.05), Vector3(0, ty + 1.24, -0.155), body_light_mat)     # inner chest plate
	_box(_torso, Vector3(0.36, 0.05, 0.04), Vector3(0, ty + 1.39, -0.15), red_mat)            # collar trim
	_box(_torso, Vector3(0.08, 0.07, 0.02), Vector3(0, ty + 1.3, -0.185), badge_mat)          # badge
	_box(_torso, Vector3(0.02, 0.2, 0.01), Vector3(0, ty + 1.24, -0.185), body_dark_mat)         # centre seam
	for sx: float in [-1.0, 1.0]:
		_box(_torso, Vector3(0.05, 0.14, 0.03), Vector3(sx * 0.17, ty + 1.25, -0.15), body_dark_mat)   # chest seams
	_capsule(_torso, 0.095, 0.3, Vector3(0, ty + 1.03, 0.0), dark_mat)                       # mechanical waist
	for k in 3:
		_box(_torso, Vector3(0.21, 0.02, 0.2), Vector3(0, ty + 0.97 + 0.055 * k, 0), metal_mat)   # waist rings
	_box(_torso, Vector3(0.32, 0.11, 0.24), Vector3(0, ty + 0.93, 0.0), red_mat)              # pelvis plate
	_box(_torso, Vector3(0.09, 0.06, 0.02), Vector3(0, ty + 0.93, -0.14), cream_mat)          # buckle
	for sx: float in [-1.0, 1.0]:
		var guard := _box(_torso, Vector3(0.1, 0.17, 0.2), Vector3(sx * 0.19, ty + 0.9, 0.0), red_mat)   # hip guards
		guard.rotation.z = -sx * 0.18
	_box(_torso, Vector3(0.32, 0.28, 0.12), Vector3(0, ty + 1.25, 0.19), body_dark_mat)       # backpack unit
	for sx: float in [-1.0, 1.0]:
		_box(_torso, Vector3(0.08, 0.16, 0.03), Vector3(sx * 0.09, ty + 1.25, 0.26), metal_mat)   # pack vents
	_box(_torso, Vector3(0.2, 0.06, 0.06), Vector3(0, ty + 1.44, 0.2), metal_mat)             # pack handle
	for sx: float in [-1.0, 1.0]:
		_sphere(_torso, 0.11, Vector3(sx * 0.28, ty + 1.44, 0.0), body_mat)                   # pauldrons
		_box(_torso, Vector3(0.14, 0.04, 0.16), Vector3(sx * 0.29, ty + 1.52, 0.0), body_light_mat)   # pauldron caps
		_box(_torso, Vector3(0.15, 0.02, 0.17), Vector3(sx * 0.29, ty + 1.49, 0.0), red_mat)          # their red rim
	_cyl(self, 0.05, 0.14, Vector3(0, head_y - 0.14, 0), dark_mat)                           # neck
	_cyl(self, 0.075, 0.03, Vector3(0, head_y - 0.06, 0), metal_mat)                         # neck ring

	# Head: one piece (Sean: the bezel on the dome read as "a mask on a normal circle head; it
	# should be all 1 piece"), a single mesh in the identity colour shaped like an iMac G3 in
	# profile: a flat face with rounded corners at the front flowing into a dome behind, no
	# seam (head_mesh). On the face the dark visor band with its lit slit; the ear piece on the
	# right, the antenna and vent slots on the left. The bezel, its brow and cheek lines and the
	# chin plate are gone with the seam.
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, head_y, 0)
	add_child(head)
	_node(head, head_mesh(), Vector3(0, 0.07, 0.0), body_mat)                                 # the one-piece head
	_box(head, Vector3(0.36, 0.11, 0.03), Vector3(0, 0.06, -0.185), screen_mat)              # visor band
	_box(head, Vector3(0.3, 0.025, 0.01), Vector3(0, 0.065, -0.202), glow_mat)                # the lit slit
	_box(head, Vector3(0.07, 0.11, 0.12), Vector3(0.22, 0.05, -0.04), badge_mat)              # ear piece
	_cyl(head, 0.02, 0.02, Vector3(0.26, 0.05, -0.04), dark_mat).rotation.z = PI * 0.5        # its stud
	var ant := _cyl(head, 0.015, 0.14, Vector3(-0.2, 0.15, -0.02), dark_mat)                  # antenna
	ant.rotation.z = 0.35
	_sphere(head, 0.025, Vector3(-0.225, 0.22, -0.02), red_mat)                               # its tip
	for k in 3:
		_box(head, Vector3(0.012, 0.06, 0.05), Vector3(-0.19, 0.02, 0.0 + 0.05 * k), body_dark_mat)   # vent slots

	# Arms and legs on their pivots (the animation rotates the pivots).
	_l_arm = _arm(Vector3(-0.29, SHOULDER_Y, 0), body_mat, body_light_mat, dark_mat, metal_mat)
	_r_arm = _arm(Vector3(0.29, SHOULDER_Y, 0), body_mat, body_light_mat, dark_mat, metal_mat)
	_l_leg = _leg(Vector3(-0.11, HIP_Y, 0), body_mat, body_light_mat, body_dark_mat, dark_mat, metal_mat, red_mat)
	_r_leg = _leg(Vector3(0.11, HIP_Y, 0), body_mat, body_light_mat, body_dark_mat, dark_mat, metal_mat, red_mat)

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
		# The katana (FIREBALL): the handle through the glove, the guard past the fingers, the
		# blade on down the arm's line with its bright edge, hidden until set_weapon_kind asks.
		_katana = Node3D.new()
		_gun.add_child(_katana)
		var steel_mat := CelMaterial.for_colour(Color.from_hsv(0.58, 0.10, 0.84), shadow)
		var wrap_mat := CelMaterial.for_colour(Color.from_hsv(0.72, 0.4, 0.2), shadow)
		_capsule(_katana, 0.02, 0.26, Vector3(0.0, -0.09, 0.0), wrap_mat)                   # the handle
		for k in 5:
			var dmd := _box(_katana, Vector3(0.05, 0.016, 0.014), Vector3(0.0, -0.19 + 0.045 * k, 0.0), body_mat)
			dmd.rotation.y = 0.75 if k % 2 == 0 else -0.75
		_cyl(_katana, 0.052, 0.008, Vector3(0.0, -0.235, 0.0), dark_mat)                    # the guard
		_box(_katana, Vector3(0.014, 0.03, 0.04), Vector3(0.0, -0.26, 0.0), metal_mat)        # the collar
		_box(_katana, Vector3(0.014, 0.74, 0.05), Vector3(0.0, -0.64, 0.0), steel_mat)        # the blade (wide enough to read at 15 m)
		_box(_katana, Vector3(0.008, 0.72, 0.012), Vector3(0.0, -0.64, -0.028), cream_mat)    # its edge
		_box(_katana, Vector3(0.012, 0.06, 0.026), Vector3(0.0, -1.03, 0.008), steel_mat)     # the point
		_katana.visible = false


## An arm from the shoulder down: the ball joint, a dark upper arm, the elbow ball, a flared
## gauntlet with a pale cuff, a dark glove with three fingers and a thumb.
func _arm(pivot: Vector3, body_mat: Material, light_mat: Material, dark_mat: Material, joint_mat: Material) -> Node3D:
	var n := Node3D.new()
	n.position = pivot
	add_child(n)
	_sphere(n, 0.075, Vector3.ZERO, dark_mat)
	_capsule(n, 0.052, 0.3, Vector3(0, -0.17, 0), dark_mat)
	_box(n, Vector3(0.09, 0.14, 0.09), Vector3(0, -0.2, 0), body_mat)                # upper arm plate
	_sphere(n, 0.06, Vector3(0, -0.34, 0), joint_mat)
	_box(n, Vector3(0.11, 0.13, 0.11), Vector3(0, -0.42, 0), body_mat)               # gauntlet, narrow end
	_box(n, Vector3(0.13, 0.16, 0.13), Vector3(0, -0.55, 0), body_mat)               # gauntlet, flared
	_box(n, Vector3(0.145, 0.04, 0.145), Vector3(0, -0.635, 0), light_mat)           # cuff
	_box(n, Vector3(0.1, 0.1, 0.09), Vector3(0, -0.71, 0), dark_mat)                 # glove
	for k in 3:
		_box(n, Vector3(0.026, 0.07, 0.03), Vector3(-0.032 + 0.032 * k, -0.79, -0.02), dark_mat)   # fingers
	_box(n, Vector3(0.03, 0.05, 0.03), Vector3(0.0, -0.73, -0.06), dark_mat)          # thumb
	return n


## A leg from the hip down: the ball joint, an armoured thigh, the knee ball with a red cap, a
## flared shin, a big boot with a red toe cap, an ankle cuff and a dark sole (skates under it).
func _leg(pivot: Vector3, body_mat: Material, light_mat: Material, dark_body_mat: Material, dark_mat: Material, joint_mat: Material, red_mat: Material) -> Node3D:
	var n := Node3D.new()
	n.position = pivot
	add_child(n)
	_sphere(n, 0.075, Vector3.ZERO, dark_mat)
	_capsule(n, 0.062, 0.4, Vector3(0, -0.21, 0), body_mat)                           # thigh
	_box(n, Vector3(0.12, 0.28, 0.05), Vector3(0, -0.2, -0.065), light_mat)           # thigh plate
	_sphere(n, 0.075, Vector3(0, -0.43, 0), joint_mat)                                 # knee
	_box(n, Vector3(0.12, 0.1, 0.05), Vector3(0, -0.43, -0.085), red_mat)              # kneecap
	_box(n, Vector3(0.11, 0.16, 0.12), Vector3(0, -0.53, 0), body_mat)                 # shin, narrow
	_box(n, Vector3(0.14, 0.2, 0.15), Vector3(0, -0.7, 0), body_mat)                   # shin, flared
	_box(n, Vector3(0.16, 0.05, 0.18), Vector3(0, -0.79, 0), dark_body_mat)            # ankle cuff
	_box(n, Vector3(0.19, 0.15, 0.33), Vector3(0, -0.885, -0.04), body_mat)            # boot
	_box(n, Vector3(0.1, 0.06, 0.05), Vector3(0, -0.83, -0.16), light_mat)              # tongue
	_box(n, Vector3(0.19, 0.1, 0.11), Vector3(0, -0.905, -0.19), red_mat)              # toe cap
	_box(n, Vector3(0.2, 0.035, 0.34), Vector3(0, -0.965, -0.04), dark_mat)            # sole
	_box(n, Vector3(0.21, 0.03, 0.06), Vector3(0, -0.84, 0.14), light_mat)             # heel strap
	if _skates:
		# Rollerskates: a plate under the sole and two wheels each side, axles across the boot.
		_box(n, Vector3(0.16, 0.025, 0.3), Vector3(0, -0.99, -0.04), joint_mat)
		for wz: float in [-0.15, 0.07]:
			for wx: float in [-0.075, 0.075]:
				var wheel := _cyl(n, 0.045, 0.035, Vector3(wx, -1.03, wz), dark_mat)
				wheel.rotation.z = PI * 0.5
	return n


## Which held gun shows: 0 the long rifle, anything else the short one.
func set_weapon_slot(slot: int) -> void:
	if _gun_long != null:
		_gun_long.visible = slot == 0
		_gun_short.visible = slot != 0
		if _katana != null:
			_katana.visible = false


## Which held weapon shows, by its id: the sniper, the katana, or the short gun for the rest.
func set_weapon_kind(kind: String) -> void:
	if _gun_long == null:
		return
	_gun_long.visible = kind == "sniper"
	_katana.visible = kind == "katana"
	_gun_short.visible = not (_gun_long.visible or _katana.visible)


## The katana up in front (the reflect window open): both arms rise and the blade points up.
func set_guard(on: bool, delta: float) -> void:
	_guard = move_toward(_guard, 1.0 if on else 0.0, delta * (12.0 if on else 7.0))


## How far the held gun's muzzle reaches from the shoulder along the aim, for the wall check.
func gun_reach() -> float:
	if _katana != null and _katana.visible:
		return 1.3
	return 1.45 if (_gun_long != null and _gun_long.visible) else 1.05


## The angle the gun is lifted so its barrel stays out of a wall (PlayerVisual measures it with a
## ray every frame; Sean, 2026-09-23: "the sniper barrel peeking from the other side of the
## wall"), eased so it never pops.
var _gun_raise: float = 0.0


func set_gun_raise(target: float, delta: float) -> void:
	_gun_raise = move_toward(_gun_raise, target, delta * 8.0)


## A hit: the torso and head jerk back for a quarter second.
func flinch() -> void:
	_flinch = 1.0


var _aiming: bool = false
var _throw_t: float = 0.0
const THROW_SECONDS := 0.6


## Board aiming (the laser gun): the right arm comes up straight out in front, the hand leading,
## and stays there while `on`; the left arm keeps its walk swing.
func set_aiming(on: bool) -> void:
	_aiming = on


## Board throw (the bomb): the right arm winds back, whips over the head and settles again,
## THROW_SECONDS long; the bomb leaves the hand as the arm passes the top.
func throw() -> void:
	_throw_t = THROW_SECONDS


func _throw_arm() -> float:
	var k := 1.0 - _throw_t / THROW_SECONDS
	if k < 0.35:
		return lerpf(0.0, -1.2, smoothstep(0.0, 0.35, k))
	if k < 0.6:
		return lerpf(-1.2, 2.4, smoothstep(0.35, 0.6, k))
	return lerpf(2.4, 0.0, smoothstep(0.6, 1.0, k))


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
		if _throw_t > 0.0:
			_throw_t -= delta
			_r_arm.rotation.x = _throw_arm()
		elif _aiming:
			_r_arm.rotation.x = PI * 0.5   # the gun or the claw held out in front
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
		# Both arms up on the gun, following the look pitch; the gun points where the head looks,
		# lifted by whatever keeps the barrel out of a wall.
		var aim := PI * 0.5 + pitch + _gun_raise + _guard * 0.9
		_r_arm.rotation.x = aim
		_l_arm.rotation.x = aim
		_l_arm.rotation.y = -0.55 - _guard * 0.15   # the left hand reaches in to the gun
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


static var _head_mesh_cache: ArrayMesh


## The head as one mesh: an iMac G3 in profile. A superellipsoid whose exponent runs from boxy
## at the front (a flat face with rounded corners, 42 cm wide, 32 tall, 18.5 ahead of the centre)
## to round at the back (a dome 24.5 cm deep), so the face flows into the dome with no seam.
## Front is -Z. Built once and shared by every figure.
static func head_mesh() -> ArrayMesh:
	if _head_mesh_cache != null:
		return _head_mesh_cache
	const ROWS := 20   # latitude steps, pole to pole
	const COLS := 40   # longitude steps around
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in ROWS + 1:
		var u := -PI * 0.5 + PI * float(i) / float(ROWS)
		for j in COLS + 1:
			var v := TAU * float(j) / float(COLS)
			verts.append(_head_point(u, v))
			normals.append(_head_normal(u, v))
	for i in ROWS:
		for j in COLS:
			var a := i * (COLS + 1) + j
			var b := a + COLS + 1
			# Clockwise seen from outside, Godot's front-face winding.
			indices.append_array(PackedInt32Array([a, a + 1, b + 1, a, b + 1, b]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	_head_mesh_cache = ArrayMesh.new()
	_head_mesh_cache.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _head_mesh_cache


static func _se(w: float, e: float) -> float:
	return signf(w) * pow(absf(w), e)


## A point of the head surface: u is the latitude (-PI/2 the bottom, PI/2 the top), v the
## longitude (sin v < 0 is the front). The exponent and the depth blend from the face to the dome.
static func _head_point(u: float, v: float) -> Vector3:
	var t := smoothstep(-0.55, 0.55, sin(v))   # 0 at the face's centre, 1 at the back of the dome
	var e := lerpf(0.36, 1.0, t)               # boxy at the front, round at the back
	var depth := lerpf(0.185, 0.245, t)
	var cu := _se(cos(u), e)
	return Vector3(0.21 * cu * _se(cos(v), e), 0.16 * _se(sin(u), e), depth * cu * _se(sin(v), e))


static func _head_normal(u: float, v: float) -> Vector3:
	const D := 0.002
	if absf(cos(u)) < 0.005:
		return Vector3(0.0, signf(sin(u)), 0.0)
	var du := _head_point(u + D, v) - _head_point(u - D, v)
	var dv := _head_point(u, v + D) - _head_point(u, v - D)
	var n := du.cross(dv)
	if n.length_squared() < 1e-14:
		return _head_point(u, v).normalized()
	return n.normalized()


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
