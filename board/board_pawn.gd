class_name BoardPawn
extends Node3D
## A player on the board: the arena silhouette (capsule, dark head, visor) in the identity
## colour on a coloured base ring, hopping between spaces.

var peer_id: int = 0
var colour: Color = Color.WHITE
var _hop_tween: Tween
var _body: Node3D


func setup(p_peer_id: int, p_colour: Color, p_name: String) -> void:
	peer_id = p_peer_id
	colour = Palette.under_ceiling(p_colour)
	var shadow := Palette.map_colour("board", "shadow_tint")
	var ink := Palette.map_colour("board", "line")
	var body_mat := CelMaterial.for_colour(colour, shadow)
	var dark_mat := CelMaterial.for_colour(Color.from_hsv(ink.h, 0.45, 0.24), shadow)
	var visor_mat := CelMaterial.for_colour(Palette.hud_colour("meter"), shadow, 0.9)
	_body = Node3D.new()
	add_child(_body)
	var cap := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.34
	cm.height = 1.44
	cap.mesh = cm
	cap.position.y = 0.42 + 0.72
	cap.material_override = body_mat
	_body.add_child(cap)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	head.mesh = sm
	head.position.y = 1.72
	head.material_override = dark_mat
	_body.add_child(head)
	var visor := MeshInstance3D.new()
	var vb := BoxMesh.new()
	vb.size = Vector3(0.24, 0.06, 0.06)
	visor.mesh = vb
	visor.position = Vector3(0, 1.74, -0.18)
	visor.material_override = visor_mat
	_body.add_child(visor)
	var legs := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.36, 0.42, 0.26)
	legs.mesh = lb
	legs.position.y = 0.21
	legs.material_override = dark_mat
	_body.add_child(legs)
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
	var label := Label3D.new()
	label.text = p_name.to_upper()
	label.font_size = 48
	label.pixel_size = 0.006
	label.outline_size = 14
	label.modulate = Palette.hud_colour("paper")
	label.outline_modulate = ink
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.25
	label.no_depth_test = true
	add_child(label)


## Hop to a world position over `seconds`, facing the direction of travel.
func hop_to(target: Vector3, seconds: float) -> void:
	if _hop_tween != null and _hop_tween.is_valid():
		_hop_tween.kill()
	var from := global_position
	var flat := target - from
	flat.y = 0.0
	if flat.length() > 0.01:
		_body.look_at(global_position + flat, Vector3.UP)
		_body.rotate_y(PI)
	_hop_tween = create_tween()
	_hop_tween.set_parallel(true)
	_hop_tween.tween_property(self, "global_position:x", target.x, seconds)
	_hop_tween.tween_property(self, "global_position:z", target.z, seconds)
	var peak := maxf(from.y, target.y) + 0.9
	var up := _hop_tween.tween_property(self, "global_position:y", peak, seconds * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_hop_tween.chain().tween_property(self, "global_position:y", target.y, seconds * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	var squash := _hop_tween.parallel()
	_body.scale = Vector3(1.15, 0.85, 1.15)
	_hop_tween.parallel().tween_property(_body, "scale", Vector3.ONE, seconds * 0.6)


func snap_to(target: Vector3) -> void:
	if _hop_tween != null and _hop_tween.is_valid():
		_hop_tween.kill()
	global_position = target
	_body.scale = Vector3.ONE
