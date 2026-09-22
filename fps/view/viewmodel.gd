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
# The original session-1 pose, restored on Sean's word after the Intervention experiments:
# lower-right quarter, a small yaw so the length reads, barely canted.
var hip_positions: Array[Vector3] = [Vector3(0.23, -0.19, -0.34), Vector3(0.25, -0.20, -0.38)]
var hip_rotations: Array[Vector3] = [
	Vector3(deg_to_rad(3.0), deg_to_rad(-11.0), deg_to_rad(-5.0)),
	Vector3(deg_to_rad(4.0), deg_to_rad(-19.0), deg_to_rad(-7.0)),
]
# ADS: the sniper's scope tube sits 0.115 above the model origin, so the model goes to
# y = -0.115 and the eyepiece (z = +0.105) ends 5 cm in front of the eye: the view goes
# through the glass, not into the receiver (Sean's note 4).
var ads_pos: Array[Vector3] = [Vector3(0.0, -0.115, -0.155), Vector3(0.0, -0.14 * 1.22, -0.34)]
var muzzles: Array[Vector3] = [Vector3(0.0, 0.02, -1.03), Vector3(0.0, 0.015, -0.52)]
var _kick: float = 0.0
var _bolt: float = 0.0
var _swap_dip: float = 0.0
var _last_slot: int = -1
var _sniper_fired_at: int = -1
var _bob_t: float = 0.0


func setup(p: Player) -> void:
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
	var tan_mat := CelMaterial.for_colour(Color.from_hsv(0.09, 0.5, 0.6), shadow, 0.0, true)
	# The scope is black (Sean): the tube, bell, eyepiece and mounts near-black, the rings a
	# charcoal step lighter so the shapes still separate under the cel bands.
	var scope_mat := CelMaterial.for_colour(Color(0.04, 0.035, 0.05), shadow, 0.0, true)
	var scope_ring_mat := CelMaterial.for_colour(Color(0.16, 0.15, 0.18), shadow, 0.0, true)
	# Lens glass: translucent, metallic and smooth so it catches the sky and the sun (a
	# StandardMaterial3D, the one place the viewmodel is not cel-shaded).
	var lens_mat := StandardMaterial3D.new()
	lens_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lens_mat.albedo_color = Color(0.55, 0.85, 1.0, 0.5)
	lens_mat.metallic = 0.85
	lens_mat.roughness = 0.12
	lens_mat.metallic_specular = 0.9
	lens_mat.emission_enabled = true
	lens_mat.emission = Color(0.25, 0.6, 0.85)
	lens_mat.emission_energy_multiplier = 0.35
	lens_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The cel viewmodel parts squash their depth toward the near plane (so they never clip into
	# walls); a normal-depth lens would lose that test and hide behind the eyepiece cap. The
	# glass sits at the very ends of the scope, so drawing it without the depth test is safe.
	lens_mat.no_depth_test = true
	lens_mat.render_priority = 2
	# Sniper: long and thin. Barrel, receiver, scope, stock, bolt handle.
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
	_cyl(sniper, 0.032, 0.07, Vector3(0, 0.115, 0.07), scope_mat)
	_cyl(sniper, 0.032, 0.028, Vector3(0, 0.115, -0.22), scope_ring_mat)
	_cyl(sniper, 0.032, 0.028, Vector3(0, 0.115, -0.02), scope_ring_mat)
	_cyl(sniper, 0.034, 0.02, Vector3(0, 0.115, 0.095), scope_ring_mat)  # eyepiece ring
	_cyl(sniper, 0.033, 0.016, Vector3(0, 0.115, -0.364), scope_mat)     # far end: black, like the scope
	_cyl(sniper, 0.026, 0.014, Vector3(0, 0.115, 0.108), lens_mat)       # eyepiece glass: the one we look through
	var bolt := MeshInstance3D.new()
	var bolt_mesh := CylinderMesh.new()
	bolt_mesh.top_radius = 0.011
	bolt_mesh.bottom_radius = 0.011
	bolt_mesh.height = 0.075
	bolt_mesh.radial_segments = 10
	bolt.mesh = bolt_mesh
	bolt.position = Vector3(0.065, 0.028, 0.03)
	bolt.rotation.z = PI * 0.5
	bolt.material_override = tan_mat
	bolt.layers = 2
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sniper.add_child(bolt)
	_sphere(sniper, 0.02, Vector3(0.105, 0.028, 0.03), dark_mat)
	_arm(sniper, Vector3(0.0, -0.12, 0.05), accent_mat, dark_mat)
	add_child(sniper)
	# AR: compact. Receiver, short barrel, magazine, grip, a screen.
	var ar := Node3D.new()
	ar.name = "AR"
	_box(ar, Vector3(0.10, 0.12, 0.40), Vector3(0, 0, -0.05), body_mat)
	_box(ar, Vector3(0.05, 0.05, 0.28), Vector3(0, 0.015, -0.38), dark_mat)
	_box(ar, Vector3(0.05, 0.16, 0.08), Vector3(0, -0.13, -0.02), accent_mat)
	_box(ar, Vector3(0.04, 0.14, 0.07), Vector3(0, -0.11, 0.14), dark_mat)
	# The sight as it was, but its screen is a translucent pane with the red dot drawn in the
	# middle of it (Sean: "on the screen of the AR, in the middle"). At ADS the screen's centre
	# sits on the camera axis, so you aim through the tinted glass with the dot at the point.
	_box(ar, Vector3(0.06, 0.05, 0.16), Vector3(0, 0.085, -0.02), dark_mat)
	_box(ar, Vector3(0.058, 0.008, 0.02), Vector3(0, 0.114, 0.03), dark_mat)   # screen base
	for sx: float in [-0.028, 0.028]:
		_box(ar, Vector3(0.006, 0.05, 0.02), Vector3(sx, 0.14, 0.03), dark_mat)   # screen posts
	var screen_mat := StandardMaterial3D.new()
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tint := Palette.hud_colour("meter")
	screen_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.32)
	screen_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	screen_mat.no_depth_test = true
	screen_mat.render_priority = 2
	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.05, 0.044, 0.003)
	screen.mesh = sm
	screen.position = Vector3(0, 0.14, 0.03)
	screen.material_override = screen_mat
	screen.layers = 2
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ar.add_child(screen)
	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot_mat.albedo_color = Palette.hud_colour("danger")
	dot_mat.no_depth_test = true
	dot_mat.render_priority = 3
	var dot := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.0035
	dm.height = 0.007
	dm.radial_segments = 10
	dm.rings = 5
	dot.mesh = dm
	dot.position = Vector3(0, 0.14, 0.03)
	dot.material_override = dot_mat
	dot.layers = 2
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ar.add_child(dot)
	_box(ar, Vector3(0.07, 0.07, 0.18), Vector3(0, -0.02, 0.22), body_mat)
	_arm(ar, Vector3(0.0, -0.11, 0.14), accent_mat, dark_mat)
	add_child(ar)
	models = [sniper, ar]
	scale = Vector3.ONE * 1.22
	Events.local_fired.connect(_on_fired)


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


## Glove on the grip and a sleeve running to the bottom-right corner of the frame.
func _arm(parent: Node3D, grip: Vector3, sleeve_mat: Material, glove_mat: Material) -> void:
	_box(parent, Vector3(0.09, 0.09, 0.09), grip + Vector3(0.0, -0.02, 0.0), glove_mat)
	var dir := Vector3(0.20, -0.34, 0.34).normalized()
	var sleeve := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.10, 0.10, 0.50)
	sleeve.mesh = bm
	sleeve.material_override = sleeve_mat
	sleeve.layers = 2
	sleeve.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sleeve.position = grip + dir * 0.27
	sleeve.basis = Basis.looking_at(dir, Vector3.UP)
	parent.add_child(sleeve)
	var cuff := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.12, 0.12, 0.06)
	cuff.mesh = cm
	cuff.material_override = glove_mat
	cuff.layers = 2
	cuff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cuff.position = grip + dir * 0.06
	cuff.basis = Basis.looking_at(dir, Vector3.UP)
	parent.add_child(cuff)


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
	var slot := player.weapons.slot
	if slot != _last_slot:
		_last_slot = slot
		_swap_dip = 1.0
	var progress := Game.ads_progress_override(player.weapons.ads_progress(tick))
	for i in models.size():
		# The sniper leaves the frame once its eyepiece fills the view and the iris takes over.
		models[i].visible = (i == slot) and not (i == 0 and progress >= 0.64)
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	var hi := mini(slot, hip_positions.size() - 1)
	var target_pos := hip_positions[hi].lerp(ads_pos[mini(slot, ads_pos.size() - 1)], eased)
	var target_rot := hip_rotations[hi].lerp(Vector3.ZERO, eased)
	# Weapon bob from horizontal speed, only from the hip.
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
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
