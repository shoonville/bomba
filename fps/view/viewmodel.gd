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
var hip_positions: Array[Vector3] = [Vector3(0.23, -0.19, -0.34), Vector3(0.25, -0.20, -0.38)]
var hip_rotations: Array[Vector3] = [
	Vector3(deg_to_rad(3.0), deg_to_rad(-11.0), deg_to_rad(-5.0)),
	Vector3(deg_to_rad(4.0), deg_to_rad(-19.0), deg_to_rad(-7.0)),
]
var ads_pos: Array[Vector3] = [Vector3(0.0, -0.068, -0.30), Vector3(0.0, -0.11, -0.36)]
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
	# Sniper: long and thin. Barrel, receiver, scope, stock, bolt handle.
	var sniper := Node3D.new()
	sniper.name = "Sniper"
	_box(sniper, Vector3(0.05, 0.05, 0.95), Vector3(0, 0.02, -0.55), dark_mat)
	_box(sniper, Vector3(0.09, 0.11, 0.42), Vector3(0, 0, -0.1), body_mat)
	_box(sniper, Vector3(0.07, 0.10, 0.34), Vector3(0, -0.03, 0.26), body_mat)
	_box(sniper, Vector3(0.06, 0.07, 0.30), Vector3(0, 0.105, -0.12), dark_mat)
	_box(sniper, Vector3(0.075, 0.075, 0.05), Vector3(0, 0.105, 0.04), accent_mat)
	_box(sniper, Vector3(0.075, 0.075, 0.05), Vector3(0, 0.105, -0.28), accent_mat)
	_box(sniper, Vector3(0.05, 0.02, 0.05), Vector3(0.06, 0.02, 0.02), accent_mat)
	_box(sniper, Vector3(0.02, 0.02, 0.06), Vector3(0.0, 0.045, -0.05), glow_mat)
	_box(sniper, Vector3(0.04, 0.16, 0.08), Vector3(0, -0.12, 0.05), dark_mat)
	_arm(sniper, Vector3(0.0, -0.12, 0.05), accent_mat, dark_mat)
	add_child(sniper)
	# AR: compact. Receiver, short barrel, magazine, grip, a screen.
	var ar := Node3D.new()
	ar.name = "AR"
	_box(ar, Vector3(0.10, 0.12, 0.40), Vector3(0, 0, -0.05), body_mat)
	_box(ar, Vector3(0.05, 0.05, 0.28), Vector3(0, 0.015, -0.38), dark_mat)
	_box(ar, Vector3(0.05, 0.16, 0.08), Vector3(0, -0.13, -0.02), accent_mat)
	_box(ar, Vector3(0.04, 0.14, 0.07), Vector3(0, -0.11, 0.14), dark_mat)
	_box(ar, Vector3(0.06, 0.05, 0.16), Vector3(0, 0.085, -0.02), dark_mat)
	_box(ar, Vector3(0.05, 0.03, 0.06), Vector3(0, 0.09, 0.03), glow_mat)
	_box(ar, Vector3(0.07, 0.07, 0.18), Vector3(0, -0.02, 0.22), body_mat)
	_arm(ar, Vector3(0.0, -0.11, 0.14), accent_mat, dark_mat)
	add_child(ar)
	models = [sniper, ar]
	scale = Vector3.ONE * 1.22
	Events.local_fired.connect(_on_fired)


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
	var progress := player.weapons.ads_progress(tick)
	for i in models.size():
		# The sniper leaves the frame once the drawn scope takes over.
		models[i].visible = (i == slot) and not (i == 0 and progress >= 0.95)
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
