class_name BoardPawn
extends Node3D
## A player on the board: the same humanoid Figure as in the arena, in the identity colour on
## a coloured base ring, hopping between spaces.

var peer_id: int = 0
var colour: Color = Color.WHITE
var _hop_tween: Tween
var _body: Node3D
var _figure: Figure
var _last_pos: Vector3 = Vector3.ZERO
var _speed: float = 0.0
var _vspeed: float = 0.0


func _process(delta: float) -> void:
	if _figure == null or delta <= 0.0:
		return
	var d := global_position - _last_pos
	_speed = lerpf(_speed, minf(Vector2(d.x, d.z).length() / delta, 12.0), 0.35)
	_vspeed = lerpf(_vspeed, d.y / delta, 0.35)
	_last_pos = global_position
	_figure.animate(_speed, absf(_vspeed) < 1.0, 0.0, true, delta)


func setup(p_peer_id: int, p_colour: Color, p_name: String) -> void:
	peer_id = p_peer_id
	colour = Palette.under_ceiling(p_colour)
	var shadow := Palette.map_colour("board", "shadow_tint")
	var ink := Palette.map_colour("board", "line")
	_body = Node3D.new()
	add_child(_body)
	_figure = Figure.new()
	_figure.name = "Figure"
	_body.add_child(_figure)
	_figure.build(colour, "board", 1.62, false)
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
	# The name tag is drawn by the board HUD (projected, de-overlapped), not as a Label3D.


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
