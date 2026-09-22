class_name BoardPawn
extends Node3D
## A player on the board: the same humanoid Figure as in the arena, in the identity colour on
## a coloured base ring, hopping between spaces. Carries the laser gun (shown while aiming and
## for a moment after a shot) and bleeds when its HP is low.

var peer_id: int = 0
var colour: Color = Color.WHITE
var _hop_tween: Tween
var _body: Node3D
var _figure: Figure
var _last_pos: Vector3 = Vector3.ZERO
var _speed: float = 0.0
var _vspeed: float = 0.0
var _gun: Node3D
var _gun_tip: Node3D
var _bleeding: bool = false      # low HP: a slow drip until a respawn
var _bleed_until: float = 0.0    # a fast drip right after a hit
var _bleed_t: float = 0.0
var _clock: float = 0.0
var _blood_mat: Material
var _lean: Node3D
var _lean_amount: float = 0.0
var _lean_target: float = 0.0
var _claw: Node3D            # the retractable claw's head, in world space while it is out
var _claw_hand: Node3D       # the claw folded in the hand
var _cable: MeshInstance3D
var _claw_out: bool = false
var _aura: MeshInstance3D    # the shield's glow
var _aura_on: bool = false
var _aura_tween: Tween


func _process(delta: float) -> void:
	if _figure == null or delta <= 0.0:
		return
	_clock += delta
	_lean_amount = move_toward(_lean_amount, _lean_target, delta * 5.0)
	if _lean != null:
		_lean.rotation.x = -0.14 * _lean_amount   # into the glide
	var d := global_position - _last_pos
	_speed = lerpf(_speed, minf(Vector2(d.x, d.z).length() / delta, 12.0), 0.35)
	_vspeed = lerpf(_vspeed, d.y / delta, 0.35)
	_last_pos = global_position
	_figure.animate(_speed, absf(_vspeed) < 1.0, 0.0, true, delta)
	if _claw_out and _claw != null:
		_place_cable()
	if _aura_on and _aura != null and (_aura_tween == null or not _aura_tween.is_running()):
		_aura.scale = Vector3.ONE * (1.0 + 0.04 * sin(_clock * 3.2))
	if (_bleeding or _clock < _bleed_until) and not Game.headless:
		_bleed_t -= delta
		if _bleed_t <= 0.0:
			_bleed_t = randf_range(0.08, 0.2) if _clock < _bleed_until else randf_range(0.35, 0.8)
			_drop()


func setup(p_peer_id: int, p_colour: Color, p_name: String) -> void:
	peer_id = p_peer_id
	colour = Palette.under_ceiling(p_colour)
	var shadow := Palette.map_colour("board", "shadow_tint")
	var ink := Palette.map_colour("board", "line")
	_body = Node3D.new()
	add_child(_body)
	_lean = Node3D.new()
	_body.add_child(_lean)
	_figure = Figure.new()
	_figure.name = "Figure"
	_lean.add_child(_figure)
	_figure.build(colour, "board", 1.62, false, true)
	_figure.position.y = 0.05   # up on the skates' wheels
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.48
	tm.outer_radius = 0.6
	tm.rings = 24
	tm.ring_segments = 8
	ring.mesh = tm
	ring.position.y = 0.06
	ring.material_override = CelMaterial.for_colour(colour, shadow, 0.5)
	add_child(ring)
	_blood_mat = CelMaterial.for_colour(Color.from_hsv(355.0 / 360.0, 0.85, 0.42), shadow)
	# The laser gun in the right hand: a boxy pistol, the barrel along the arm's local -Y (the
	# hand direction, forward when the arm is raised), a red emitter at the muzzle, the grip in
	# the player's colour. Hidden until it is drawn.
	var hand := _figure.hand_node()
	_gun = Node3D.new()
	_gun.position = Vector3(0, -0.62, 0)
	_gun.visible = false
	hand.add_child(_gun)
	var dark := CelMaterial.for_colour(Color.from_hsv(ink.h, 0.45, 0.24), shadow)
	var red := CelMaterial.for_colour(Palette.hud_colour("danger"), shadow, 1.4)
	_prop(_gun, Vector3(0.08, 0.28, 0.1), Vector3(-0.1, -0.08, 0.0), dark)                # body
	_prop(_gun, Vector3(0.05, 0.18, 0.03), Vector3(-0.1, -0.1, -0.06), CelMaterial.for_colour(colour, shadow))   # top rail
	_prop(_gun, Vector3(0.07, 0.1, 0.09), Vector3(-0.1, 0.06, 0.07), CelMaterial.for_colour(colour, shadow))    # grip
	_prop(_gun, Vector3(0.05, 0.05, 0.06), Vector3(-0.1, -0.24, 0.0), red)                # emitter
	_prop(_gun, Vector3(0.1, 0.04, 0.12), Vector3(-0.1, -0.16, 0.0), dark)                 # muzzle ring
	_gun_tip = Node3D.new()
	_gun_tip.position = Vector3(-0.1, -0.27, 0.0)
	_gun.add_child(_gun_tip)
	# The retractable claw (MAGNET): folded in the hand like the gun, and a head on a cable that
	# flies out to the mark and back. Hidden until it is used.
	var tint := CelMaterial.for_colour(colour, shadow)
	_claw_hand = _build_claw(dark, tint)
	_claw_hand.position = Vector3(0, -0.62, 0)
	_claw_hand.rotation.x = -PI * 0.5   # its jaws along the arm's -Y, forward when the arm is up
	_claw_hand.visible = false
	hand.add_child(_claw_hand)
	_claw = _build_claw(dark, tint)
	_claw.visible = false
	add_child(_claw)
	_cable = MeshInstance3D.new()
	var cbm := BoxMesh.new()
	cbm.size = Vector3(0.045, 0.045, 1.0)
	_cable.mesh = cbm
	_cable.material_override = dark
	_cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cable.visible = false
	add_child(_cable)
	# The shield's aura (Sean: a glowing aura round the character): a translucent sphere in the
	# safe spot's cyan, drawn after the outline quad, pulsing while the shield is held.
	_aura = MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = 0.95
	am.height = 1.9
	am.radial_segments = 20
	am.rings = 10
	_aura.mesh = am
	_aura.position.y = 0.95
	var aura_mat := StandardMaterial3D.new()
	aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aura_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aura_mat.albedo_color = Color(Palette.hud_colour("meter"), 0.24)
	aura_mat.render_priority = 2
	_aura.material_override = aura_mat
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.visible = false
	add_child(_aura)
	# The name tag is drawn by the board HUD (projected, de-overlapped), not as a Label3D.


func _prop(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Skate to a world position over `seconds`, facing the direction of travel: a level glide (no
## arc; Sean: the hops looked like flying up and down), leaning into it, the figure's push-glide
## legs doing the rest. Consecutive calls run into one another, so a move reads as one skate.
## `turn` false keeps the pawn facing where it was (a shove backwards).
func hop_to(target: Vector3, seconds: float, turn: bool = true) -> void:
	if _hop_tween != null and _hop_tween.is_valid():
		_hop_tween.kill()
	var from := global_position
	var flat := target - from
	flat.y = 0.0
	if turn and flat.length() > 0.01:
		_body.look_at(global_position + flat, Vector3.UP)
		_body.rotate_y(PI)
	_lean_target = 1.0
	_hop_tween = create_tween()
	_hop_tween.set_parallel(true)
	_hop_tween.tween_property(self, "global_position:x", target.x, seconds).set_trans(Tween.TRANS_LINEAR)
	_hop_tween.tween_property(self, "global_position:z", target.z, seconds).set_trans(Tween.TRANS_LINEAR)
	_hop_tween.tween_property(self, "global_position:y", target.y, seconds).set_trans(Tween.TRANS_LINEAR)
	_hop_tween.chain().tween_callback(func(): _lean_target = 0.0)


func snap_to(target: Vector3) -> void:
	if _hop_tween != null and _hop_tween.is_valid():
		_hop_tween.kill()
	global_position = target
	_lean_target = 0.0
	_body.scale = Vector3.ONE


## Turn to face an aim angle (radians in the XZ plane, atan2(dz, dx)): the figure's front, and
## the raised gun, point that way.
func face_angle(a: float) -> void:
	_body.look_at(global_position + Vector3(cos(a), 0.0, sin(a)), Vector3.UP)


## The laser gun out (the arm comes up) or away.
func show_gun(on: bool) -> void:
	if _gun != null:
		_gun.visible = on
	if _figure != null:
		_figure.set_aiming(on)


## Where the beam starts: the gun's muzzle, in world space (the pawn's chest when the gun is
## not built yet).
func gun_tip() -> Vector3:
	if _gun_tip != null:
		return _gun_tip.global_position
	return global_position + Vector3(0, 1.3, 0)


func flinch() -> void:
	if _figure != null:
		_figure.flinch()


## A claw: a base block, a hinge and two jaws opening along -Z, the tips in the player's colour.
func _build_claw(dark: Material, tint: Material) -> Node3D:
	var root := Node3D.new()
	_prop(root, Vector3(0.14, 0.1, 0.12), Vector3(0, 0, 0.04), dark)
	_prop(root, Vector3(0.18, 0.06, 0.06), Vector3(0, 0, -0.03), tint)
	for side: float in [-1.0, 1.0]:
		var jaw := Node3D.new()
		jaw.position = Vector3(side * 0.06, 0, -0.05)
		jaw.rotation.y = side * 0.55
		root.add_child(jaw)
		_prop(jaw, Vector3(0.035, 0.05, 0.16), Vector3(0, 0, -0.08), dark)
		_prop(jaw, Vector3(0.04, 0.05, 0.05), Vector3(0, 0, -0.17), tint)
	return root


## The claw out in the hand (the arm comes up) or folded away.
func show_claw(on: bool) -> void:
	if _claw_hand != null:
		_claw_hand.visible = on
	if _figure != null:
		_figure.set_aiming(on)


## The claw's head flies out on its cable to a world point.
func claw_to(target: Vector3, seconds: float) -> void:
	if _claw == null:
		return
	_claw_hand.visible = false
	_claw_out = true
	_claw.visible = true
	_cable.visible = true
	_claw.global_position = hand_position()
	if _claw.global_position.distance_to(target) > 0.05:
		_claw.look_at(target, Vector3.UP)
	_place_cable()
	var tw := create_tween()
	tw.tween_property(_claw, "global_position", target, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished


## ...and retracts into the hand.
func claw_back(seconds: float) -> void:
	if _claw == null or not _claw_out:
		return
	var tw := create_tween()
	tw.tween_property(_claw, "global_position", hand_position(), seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	_claw_out = false
	_claw.visible = false
	_cable.visible = false
	_claw_hand.visible = true


func _place_cable() -> void:
	var from := hand_position()
	var to := _claw.global_position
	var d := from.distance_to(to)
	_cable.global_position = (from + to) * 0.5
	if d > 0.02:
		_cable.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
		_cable.scale = Vector3(1.0, 1.0, d)


## Where the right hand is, in world space (0.62 down the arm from the shoulder).
func hand_position() -> Vector3:
	if _figure == null:
		return global_position + Vector3(0, 1.3, 0)
	return _figure.hand_node().to_global(Vector3(0, -0.62, 0))


## The bomb throw: the figure's arm winds up and whips over.
func throw() -> void:
	if _figure != null:
		_figure.throw()


## The shield's aura on (pops in) or off (shrinks away).
func set_shield(on: bool) -> void:
	if _aura == null or on == _aura_on:
		return
	_aura_on = on
	if _aura_tween != null and _aura_tween.is_valid():
		_aura_tween.kill()
	_aura_tween = create_tween()
	if on:
		_aura.visible = true
		_aura.scale = Vector3.ONE * 0.15
		_aura_tween.tween_property(_aura, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_aura_tween.tween_property(_aura, "scale", Vector3.ONE * 0.05, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_aura_tween.tween_callback(func(): _aura.visible = false)


## A hit: a fast drip for a couple of seconds.
func hit_bleed(seconds: float = 2.5) -> void:
	_bleed_until = _clock + seconds


## Low HP: a slow drip that stays until the state says otherwise.
func set_bleeding(on: bool) -> void:
	_bleeding = on


## One drop: a small dark-red blob from somewhere on the torso, falling to the ground and gone.
func _drop() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	var r := randf_range(0.035, 0.06)
	sm.radius = r
	sm.height = r * 2.6
	sm.radial_segments = 6
	sm.rings = 3
	mi.mesh = sm
	mi.material_override = _blood_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var start := Vector3(randf_range(-0.16, 0.16), randf_range(0.95, 1.4), randf_range(-0.12, 0.12))
	mi.position = start
	var tw := create_tween()
	tw.tween_property(mi, "position:y", 0.03, randf_range(0.28, 0.4)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(mi, "scale", Vector3(1.6, 0.2, 1.6), 0.08)
	tw.tween_interval(randf_range(0.6, 1.4))
	tw.tween_callback(mi.queue_free)
