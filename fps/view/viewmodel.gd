class_name Viewmodel
extends Node3D
## Gray-box first-person weapons. Roboquest framing (lower-right quarter, angled, chunky),
## Bomb Rush shading (cel, ink, one small emissive detail). The scope-in animation duration is
## the tuning value scope_in_ticks — the same number the server uses for accuracy.

var player: Player
var models: Array[Node3D] = []
# Roboquest framing (STYLE.md appendix): lower-right quarter, ~40 % of frame width, pointing to
# the upper-left at ~20°, arm from the bottom-right corner.
# Per weapon: the sniper keeps a small yaw so its length still reads (STYLE.md §6), the AR sits
# more across the frame like the Roboquest guns.
# Sniper: held low and across, seen from the rear quarter so the scope's length reads and the
# barrel runs toward the crosshair (Sean: lower, whole scope visible).
# Positive yaw turns the muzzle left and swings the stock away to the right, so the scope is
# seen along its side from the rear-left-top instead of straight into the eyepiece.
# The original session-1 positions (lower-right quarter), restored on Sean's word after the
# Intervention experiments. The angles are no longer a hand-set pose: Sean (2026-09-23) "have
# the guns aim towards the reticle, they are too tilted", so each barrel is aimed at the point
# CONVERGE_M ahead on the camera axis (the reticle) from where it sits, and the cant is gone.
# The old angles were sniper pitch 3° / yaw −11° / roll −5°, AR 4° / −19° / −7°: both muzzles
# swung to the right, away from the axis the gun sits right of.
const CONVERGE_M := 20.0
# The sniper sat 7 cm further right (x 0.23) until Sean's 2026-09-23 note "move the gun to the
# left more so we can see the whole scope": its eyepiece, 21 cm from the eye, projected past the
# right edge of a 16:9 frame. The AR is where it was.
var hip_positions: Array[Vector3] = [Vector3(0.16, -0.19, -0.34), Vector3(0.25, -0.20, -0.38)]
var hip_rotations: Array[Vector3] = [_aim_at_reticle(hip_positions[0]), _aim_at_reticle(hip_positions[1])]


## The rotation that points a model's barrel (its −Z) from `pos` at the reticle: the point
## CONVERGE_M down the camera's own −Z. Godot's YXZ Euler: forward = (−sin yaw cos pitch, sin
## pitch, −cos yaw cos pitch), so yaw = atan2(−dx, −dz) and pitch = asin(dy); no roll.
static func _aim_at_reticle(pos: Vector3) -> Vector3:
	var dir := (Vector3(0.0, 0.0, -CONVERGE_M) - pos).normalized()
	return Vector3(asin(dir.y), atan2(-dir.x, -dir.z), 0.0)
# ADS: the sniper's scope tube sits 0.115 above the model origin, so the model goes to
# y = -0.115 and the eyepiece (z = +0.105) ends 5 cm in front of the eye: the view goes
# through the glass, not into the receiver (Sean's note 4).
# The AR's sight screen is at model y 0.125, so the ADS y is -0.125 × the 1.22 scale.
var ads_pos: Array[Vector3] = [Vector3(0.0, -0.115, -0.155), Vector3(0.0, -0.125 * 1.22, -0.34)]
var muzzles: Array[Vector3] = [Vector3(0.0, 0.02, -1.03), Vector3(0.0, 0.015, -0.52)]
var _kick: float = 0.0
var _bolt: float = 0.0
var _swap_dip: float = 0.0
var _last_slot: int = -1
var _sniper_fired_at: int = -1
var _bob_t: float = 0.0
var ghost_slot: int = -1   # the final-kill cam: show this slot, no bob
var ghost_ads: float = 0.0   # ... at this scope-in (the killer's, replayed; Sean, 2026-09-23)


## The recoil kick and, for the sniper, the bolt dip: the local shot, or the kill cam's replayed one.
func kick() -> void:
	_kick = 1.0
	if (player.weapons.slot if ghost_slot < 0 else ghost_slot) == 0:
		_bolt = 1.0


func setup(p: Player) -> void:
	var t0 := Time.get_ticks_usec()
	player = p
	var colour := Palette.under_ceiling(player.colour)
	var ink := Palette.map_colour("arena", "line")
	var shadow := Palette.map_colour("arena", "shadow_tint")
	var body_mat := CelMaterial.for_colour(Color.from_hsv(colour.h, colour.s * 0.35, 0.62), shadow, 0.0, true)
	var dark_mat := CelMaterial.for_colour(Color.from_hsv(ink.h, 0.35, 0.28), shadow, 0.0, true)
	var accent_mat := CelMaterial.for_colour(colour, shadow, 0.0, true)
	var glow_mat := CelMaterial.for_colour(Palette.hud_colour("meter"), shadow, 1.2, true)
	var glass_mat := CelMaterial.for_colour(Color.from_hsv(ink.h, 0.5, 0.34), shadow, 0.15, true)
	# The sniper is cream with tan fittings (Sean: "cream instead of the purple"); the AR keeps
	# the player's colour. The sleeve on both is the player's outfit.
	var cream_mat := CelMaterial.for_colour(Palette.hud_colour("paper"), shadow, 0.0, true)
	# The hands: the identity colour, with the Figure's pale cuff tint at the wrist.
	var cuff_mat := CelMaterial.for_colour(Color.from_hsv(colour.h, colour.s * 0.62, minf(1.0, colour.v * 1.12)), shadow, 0.0, true)
	var tan_mat := CelMaterial.for_colour(Color.from_hsv(0.09, 0.5, 0.6), shadow, 0.0, true)
	# The scope is black (Sean): the tube, bell, eyepiece and mounts near-black, the rings a
	# charcoal step lighter so the shapes still separate under the cel bands.
	var scope_mat := CelMaterial.for_colour(Color(0.04, 0.035, 0.05), shadow, 0.0, true)
	var scope_ring_mat := CelMaterial.for_colour(Color(0.16, 0.15, 0.18), shadow, 0.0, true)
	var lens_mat := lens_material()
	# Sniper: long and thin. Barrel, receiver, scope, stock, bolt handle.
	var t_mats := Time.get_ticks_usec()
	var sniper := Node3D.new()
	sniper.name = "Sniper"
	# Intervention-shaped: long round barrel with a big brake and a folded bipod, a tube
	# receiver, a tapered stock with a cheek riser and butt pad, a capsule grip, a bolt with a
	# knob, and a telescopic sight. Rounded parts everywhere the real rifle is rounded (note 2).
	_cyl(sniper, 0.021, 0.95, Vector3(0, 0.02, -0.55), dark_mat)
	_cyl(sniper, 0.034, 0.11, Vector3(0, 0.02, -1.0), dark_mat)
	_cyl(sniper, 0.03, 0.06, Vector3(0, 0.02, -0.93), tan_mat)
	# The folded bipod (Sean: the line under the barrel was not connected to the rifle): a hinge
	# block clamped under the barrel near the brake and a clip near the receiver, with the two
	# legs running between them along the barrel's underside, so it hangs off the rifle.
	_box(sniper, Vector3(0.064, 0.03, 0.05), Vector3(0, -0.006, -0.79), dark_mat)
	_box(sniper, Vector3(0.064, 0.022, 0.03), Vector3(0, -0.006, -0.53), dark_mat)
	for bx: float in [-0.024, 0.024]:
		_cyl(sniper, 0.007, 0.26, Vector3(bx, -0.007, -0.66), dark_mat)
	_cyl(sniper, 0.052, 0.44, Vector3(0, 0.0, -0.1), cream_mat, Vector3(1.0, 0.9, 1.0))
	_capsule(sniper, 0.034, 0.18, Vector3(0, -0.058, -0.03), dark_mat)
	_cone(sniper, 0.046, 0.062, 0.36, Vector3(0, -0.02, 0.29), cream_mat)
	_cyl(sniper, 0.066, 0.03, Vector3(0, -0.02, 0.47), dark_mat)
	_capsule(sniper, 0.03, 0.17, Vector3(0, 0.05, 0.31), tan_mat)
	_capsule(sniper, 0.03, 0.15, Vector3(0, -0.115, 0.07), dark_mat, -0.4)
	_box(sniper, Vector3(0.03, 0.05, 0.03), Vector3(0, 0.075, -0.22), scope_mat)
	_box(sniper, Vector3(0.03, 0.05, 0.03), Vector3(0, 0.075, -0.02), scope_mat)
	_cyl(sniper, 0.024, 0.34, Vector3(0, 0.115, -0.12), scope_mat)
	_cyl(sniper, 0.038, 0.08, Vector3(0, 0.115, -0.32), scope_mat)
	_cyl(sniper, 0.032, 0.028, Vector3(0, 0.115, -0.22), scope_ring_mat)
	_cyl(sniper, 0.032, 0.028, Vector3(0, 0.115, -0.02), scope_ring_mat)
	# The eyepiece and its reflective glass stay exactly as they are (Sean: "the best feature").
	_cyl(sniper, 0.032, 0.07, Vector3(0, 0.115, 0.07), scope_mat)
	_cyl(sniper, 0.034, 0.02, Vector3(0, 0.115, 0.095), scope_ring_mat)  # eyepiece ring
	_cyl(sniper, 0.033, 0.016, Vector3(0, 0.115, -0.364), scope_mat)     # far end: black, like the scope
	_cyl(sniper, 0.026, 0.014, Vector3(0, 0.115, 0.108), lens_mat)       # eyepiece glass: the one we look through
	# No bolt handle: the tan bolt and its dark knob stood off the receiver's right side, and at
	# the hip they sat in the frame's bottom-right corner, a tan slab and a dark lump against the
	# ammo bar (Sean, 2026-09-22, with a picture: "the very right part... no idea what it is").
	# The bolt cycle is still the whole rifle's dip after a shot (bolt_off in _process).
	_hands(sniper, Vector3(0.0, -0.10, 0.07), Vector3(0.0, -0.047, -0.30), accent_mat, cuff_mat)
	add_child(sniper)
	var t_sniper := Time.get_ticks_usec()
	# AR (Sean: the body was a solid block; give it the shape of a real assault rifle). Same
	# footprint and the same grip point, so the pose is unchanged: an upper receiver stepped
	# over a lower, a vented handguard with a top rail and a front post, a round barrel with a
	# muzzle device, a charging handle, an ejection port, a trigger guard, a curved magazine, a
	# pistol grip, a buffer tube and a stock with a butt pad. The sight is as it was.
	var ar := Node3D.new()
	ar.name = "AR"
	_box(ar, Vector3(0.09, 0.07, 0.30), Vector3(0, 0.02, -0.02), body_mat)          # upper receiver
	_box(ar, Vector3(0.085, 0.06, 0.20), Vector3(0, -0.04, 0.02), dark_mat)         # lower receiver
	_box(ar, Vector3(0.002, 0.03, 0.06), Vector3(0.046, 0.025, -0.02), tan_mat)     # ejection port
	_box(ar, Vector3(0.05, 0.02, 0.03), Vector3(0, 0.05, 0.135), dark_mat)          # charging handle
	_box(ar, Vector3(0.075, 0.075, 0.24), Vector3(0, 0.01, -0.29), dark_mat)        # handguard
	_box(ar, Vector3(0.04, 0.012, 0.24), Vector3(0, 0.054, -0.29), body_mat)        # top rail
	for sx: float in [-0.039, 0.039]:
		for k in 3:
			_box(ar, Vector3(0.004, 0.014, 0.045), Vector3(sx, 0.022, -0.22 - k * 0.065), tan_mat)   # vents
	_box(ar, Vector3(0.02, 0.045, 0.02), Vector3(0, 0.07, -0.40), dark_mat)         # front post
	_cyl(ar, 0.016, 0.22, Vector3(0, 0.015, -0.52), dark_mat)                       # barrel
	_cyl(ar, 0.024, 0.06, Vector3(0, 0.015, -0.62), dark_mat)                       # muzzle device
	_box(ar, Vector3(0.03, 0.006, 0.07), Vector3(0, -0.085, 0.09), dark_mat)        # trigger guard
	_box(ar, Vector3(0.01, 0.03, 0.008), Vector3(0, -0.075, 0.075), tan_mat)        # trigger
	_box(ar, Vector3(0.05, 0.09, 0.075), Vector3(0, -0.11, -0.02), accent_mat)      # magazine
	_box(ar, Vector3(0.05, 0.09, 0.075), Vector3(0, -0.185, -0.035), accent_mat)    # its curve
	_box(ar, Vector3(0.052, 0.02, 0.078), Vector3(0, -0.235, -0.043), dark_mat)     # base plate
	_box(ar, Vector3(0.04, 0.14, 0.07), Vector3(0, -0.11, 0.14), dark_mat)          # pistol grip
	# The sight as it was, but its screen is a translucent pane with the red dot drawn in the
	# middle of it (Sean: "on the screen of the AR, in the middle"). At ADS the screen's centre
	# sits on the camera axis, so you aim through the tinted glass with the dot at the point.
	_box(ar, Vector3(0.06, 0.035, 0.16), Vector3(0, 0.0775, -0.02), dark_mat)   # the sight base, 30 % lower (Sean: bulky)
	_box(ar, Vector3(0.058, 0.008, 0.02), Vector3(0, 0.099, 0.03), dark_mat)   # screen base
	for sx: float in [-0.028, 0.028]:
		_box(ar, Vector3(0.006, 0.05, 0.02), Vector3(sx, 0.125, 0.03), dark_mat)   # screen posts
	var screen_mat := screen_material()
	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.05, 0.044, 0.003)
	screen.mesh = sm
	screen.position = Vector3(0, 0.125, 0.03)
	screen.material_override = screen_mat
	screen.layers = 2
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ar.add_child(screen)
	var dot_mat := dot_material()
	var dot := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.001715   # 30 % smaller again (Sean, twice): 0.0035 → 0.00245 → 0.001715
	dm.height = 0.00343
	dm.radial_segments = 10
	dm.rings = 5
	dot.mesh = dm
	dot.position = Vector3(0, 0.125, 0.03)
	dot.material_override = dot_mat
	dot.layers = 2
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ar.add_child(dot)
	_cyl(ar, 0.02, 0.14, Vector3(0, 0.01, 0.20), dark_mat)                          # buffer tube
	_box(ar, Vector3(0.06, 0.09, 0.12), Vector3(0, -0.02, 0.29), body_mat)          # stock
	_box(ar, Vector3(0.065, 0.1, 0.02), Vector3(0, -0.02, 0.36), dark_mat)          # butt pad
	_hands(ar, Vector3(0.0, -0.09, 0.14), Vector3(0.0, -0.028, -0.30), accent_mat, cuff_mat)
	add_child(ar)
	var t_ar := Time.get_ticks_usec()
	models = [sniper, ar]
	Log.info("perf", "Viewmodel built: materials %d ms, sniper %d ms, AR %d ms" % [(t_mats - t0) / 1000, (t_sniper - t_mats) / 1000, (t_ar - t_sniper) / 1000])
	scale = Vector3.ONE * 1.22
	Events.local_fired.connect(_on_fired)


static var _lens_mat: StandardMaterial3D
static var _screen_mat: StandardMaterial3D
static var _dot_mat: StandardMaterial3D


## The three StandardMaterial3Ds of the viewmodel, built once and kept for the run. Godot frees a
## StandardMaterial3D's compiled shader with its last user, so a fresh material per match meant
## a shader compile on the switch frame (the lens, the screen and the dot: 22 ms together,
## measured 2026-09-22); the pipeline warm-up draws these same instances at boot.
## Lens glass: translucent, metallic and smooth so it catches the sky and the sun (the one
## place the viewmodel is not cel-shaded).
static func lens_material() -> StandardMaterial3D:
	if _lens_mat == null:
		_lens_mat = StandardMaterial3D.new()
		_lens_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_lens_mat.albedo_color = Color(0.55, 0.85, 1.0, 0.5)
		_lens_mat.metallic = 0.85
		_lens_mat.roughness = 0.12
		_lens_mat.metallic_specular = 0.9
		_lens_mat.emission_enabled = true
		_lens_mat.emission = Color(0.25, 0.6, 0.85)
		_lens_mat.emission_energy_multiplier = 0.35
		_lens_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		# The cel viewmodel parts squash their depth toward the near plane (so they never clip
		# into walls); a normal-depth lens would lose that test and hide behind the eyepiece cap.
		# The glass sits at the very ends of the scope, so drawing it without the depth test is safe.
		_lens_mat.no_depth_test = true
		_lens_mat.render_priority = 2
	return _lens_mat


## The AR sight's translucent screen pane.
static func screen_material() -> StandardMaterial3D:
	if _screen_mat == null:
		_screen_mat = StandardMaterial3D.new()
		_screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_screen_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var tint := Palette.hud_colour("meter")
		_screen_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.32)
		_screen_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_screen_mat.no_depth_test = true
		_screen_mat.render_priority = 2
	return _screen_mat


## The red dot on the AR's screen.
static func dot_material() -> StandardMaterial3D:
	if _dot_mat == null:
		_dot_mat = StandardMaterial3D.new()
		_dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dot_mat.albedo_color = Palette.hud_colour("danger")
		_dot_mat.no_depth_test = true
		_dot_mat.render_priority = 3
	return _dot_mat


func _mesh_node(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	mi.layers = 2
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A cylinder along the weapon's length (local Z); `squash` scales it (y < 1 flattens it).
func _cyl(parent: Node3D, radius: float, length: float, pos: Vector3, mat: Material, squash: Vector3 = Vector3.ONE) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 14
	cm.rings = 1
	var mi := _mesh_node(parent, cm, pos, mat)
	mi.rotation.x = PI * 0.5
	mi.scale = Vector3(squash.x, squash.z, squash.y)


## A tapered cylinder along Z: front radius at -Z, back radius at +Z.
func _cone(parent: Node3D, front_radius: float, back_radius: float, length: float, pos: Vector3, mat: Material) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = front_radius
	cm.bottom_radius = back_radius
	cm.height = length
	cm.radial_segments = 14
	cm.rings = 1
	var mi := _mesh_node(parent, cm, pos, mat)
	mi.rotation.x = -PI * 0.5


## A capsule along Z, optionally tilted about X (radians).
func _capsule(parent: Node3D, radius: float, length: float, pos: Vector3, mat: Material, tilt: float = 0.0) -> void:
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = maxf(length, radius * 2.0)
	cm.radial_segments = 14
	cm.rings = 4
	var mi := _mesh_node(parent, cm, pos, mat)
	mi.rotation.x = PI * 0.5 + tilt


func _sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material) -> void:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 14
	sm.rings = 7
	_mesh_node(parent, sm, pos, mat)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	mi.layers = 2
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Both hands on the weapon, in the character's own colour (Sean, 2026-09-22: "hands holding the
## gun... the same color as their character"), built like the Figure's arms: a flared gauntlet
## with a pale cuff, a palm, four fingers and a thumb. The trigger hand wraps the grip with its
## forearm running to the bottom-right corner of the frame; the support hand cups the fore-end
## from below with its forearm running to the bottom-left. Sizes in model metres before the
## viewmodel's 1.22 scale.
func _hands(parent: Node3D, grip: Vector3, support: Vector3, skin_mat: Material, cuff_mat: Material) -> void:
	# Trigger hand: the palm on the grip's right and rear, fingers curled round its front, the
	# thumb over its left, the index finger a touch higher (on the trigger).
	var palm := grip + Vector3(0.035, 0.02, 0.015)
	_box(parent, Vector3(0.05, 0.095, 0.065), palm, skin_mat)                                    # palm
	for k in 4:
		var y := grip.y + 0.045 - 0.026 * k
		var z := grip.z - 0.047 + (0.008 if k == 0 else 0.0)
		_box(parent, Vector3(0.07, 0.021, 0.026), Vector3(grip.x + 0.01, y, z), skin_mat)          # fingers round the front
	_box(parent, Vector3(0.026, 0.026, 0.065), grip + Vector3(-0.03, 0.045, -0.005), skin_mat)  # thumb over the left
	_forearm(parent, palm + Vector3(0.0, -0.04, 0.02), Vector3(0.20, -0.34, 0.34), skin_mat, cuff_mat)
	# Support hand: the palm under the fore-end, fingers up its right side, the thumb up its left.
	var spalm := support + Vector3(-0.005, -0.045, 0.0)
	_box(parent, Vector3(0.065, 0.045, 0.085), spalm, skin_mat)                                  # palm
	for k in 4:
		var z := support.z - 0.04 + 0.027 * k
		_box(parent, Vector3(0.026, 0.06, 0.022), Vector3(support.x + 0.046, support.y - 0.01, z), skin_mat)   # fingers up the right side
	_box(parent, Vector3(0.026, 0.06, 0.026), Vector3(support.x - 0.046, support.y - 0.005, support.z - 0.01), skin_mat)   # thumb up the left
	_forearm(parent, spalm + Vector3(-0.01, -0.02, 0.02), Vector3(-0.32, -0.42, 0.38), skin_mat, cuff_mat)


## A forearm from the wrist at `wrist` along `dir` (toward the elbow, off the frame): the pale
## cuff, the gauntlet's narrow end, then its flare, as on the Figure.
func _forearm(parent: Node3D, wrist: Vector3, dir: Vector3, skin_mat: Material, cuff_mat: Material) -> void:
	var d := dir.normalized()
	var basis := Basis.looking_at(d, Vector3.UP)
	for part in [[0.035, Vector3(0.125, 0.125, 0.035), cuff_mat], [0.15, Vector3(0.10, 0.10, 0.17), skin_mat], [0.33, Vector3(0.125, 0.125, 0.21), skin_mat]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[1]
		mi.mesh = bm
		mi.material_override = part[2]
		mi.layers = 2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = wrist + d * float(part[0])
		mi.basis = basis
		parent.add_child(mi)


## World position of the active weapon's muzzle, for tracers and the muzzle burst.
func muzzle_world() -> Vector3:
	var slot := clampi(player.weapons.slot if player != null else 0, 0, models.size() - 1)
	return models[slot].to_global(muzzles[slot])


func _on_fired(weapon: String) -> void:
	_kick = 1.0
	if weapon == "sniper":
		_bolt = 1.0


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var tick := NetworkTime.tick
	var ghost := ghost_slot >= 0
	var slot := ghost_slot if ghost else player.weapons.slot
	if slot != _last_slot:
		_last_slot = slot
		_swap_dip = 0.0 if ghost else 1.0
	var progress := ghost_ads if ghost else Game.ads_progress_override(player.weapons.ads_progress(tick))
	for i in models.size():
		# The sniper leaves the frame once its eyepiece fills the view and the iris takes over.
		models[i].visible = (i == slot) and not (i == 0 and progress >= 0.64)
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	var hi := mini(slot, hip_positions.size() - 1)
	var target_pos := hip_positions[hi].lerp(ads_pos[mini(slot, ads_pos.size() - 1)], eased)
	var target_rot := hip_rotations[hi].lerp(Vector3.ZERO, eased)
	# Weapon bob from horizontal speed, only from the hip.
	var speed := 0.0 if ghost else Vector2(player.velocity.x, player.velocity.z).length()
	_bob_t += delta * speed * 1.6
	var bob := Vector3(sin(_bob_t) * 0.006, absf(cos(_bob_t)) * 0.005, 0.0) * (1.0 - eased) * clampf(speed / 5.0, 0.0, 1.0)
	_kick = maxf(0.0, _kick - delta * 9.0)
	_bolt = maxf(0.0, _bolt - delta * 1.4)
	_swap_dip = maxf(0.0, _swap_dip - delta * 3.5)
	var kick_off := Vector3(0.0, 0.008, 0.06) * _kick
	var bolt_off := Vector3(0.0, -0.01, 0.03) * sin(_bolt * PI) * (1.0 if slot == 0 else 0.0)
	var dip := Vector3(0.0, -0.25, 0.0) * _swap_dip
	position = target_pos + bob + kick_off + bolt_off + dip
	rotation = target_rot + Vector3(-_kick * 0.06, 0.0, 0.0)
