class_name PlayerVisual
extends Node3D
## What other players see: a capsule body in the player's identity colour, a dark head, a visor
## strip for facing. Remote players are placed by the SnapshotBuffer (100 ms behind, NETPLAN §7);
## players simulated locally follow their body node.

var player: Player
var cfg: MovementConfig
var head_node: Node3D
var _remote_mode: bool = false


func setup(p: Player, p_cfg: MovementConfig) -> void:
	player = p
	cfg = p_cfg
	var colour := Palette.under_ceiling(player.colour)
	var shadow := Palette.map_colour("arena", "shadow_tint")
	var ink := Palette.map_colour("arena", "line")
	var body_mat := CelMaterial.for_colour(colour, shadow)
	var dark_mat := CelMaterial.for_colour(Color.from_hsv(ink.h, 0.45, 0.24), shadow)
	var visor_mat := CelMaterial.for_colour(Palette.hud_colour("meter"), shadow, 0.9)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = cfg.body_capsule_radius
	cap.height = (cfg.body_capsule_top - cfg.body_capsule_bottom) + 2.0 * cfg.body_capsule_radius
	body.mesh = cap
	body.position.y = (cfg.body_capsule_top + cfg.body_capsule_bottom) * 0.5
	body.material_override = body_mat
	add_child(body)
	head_node = Node3D.new()
	head_node.position.y = cfg.head_center_height
	add_child(head_node)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = cfg.head_radius
	sph.height = cfg.head_radius * 2.0
	head.mesh = sph
	head.material_override = dark_mat
	head_node.add_child(head)
	var visor := MeshInstance3D.new()
	var vb := BoxMesh.new()
	vb.size = Vector3(0.2, 0.05, 0.06)
	visor.mesh = vb
	visor.position = Vector3(0, 0.02, -cfg.head_radius + 0.01)
	visor.material_override = visor_mat
	head_node.add_child(visor)
	var legs := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.36, cfg.body_capsule_bottom, 0.26)
	legs.mesh = lb
	legs.position.y = cfg.body_capsule_bottom * 0.5
	legs.material_override = dark_mat
	add_child(legs)


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var remote := player._is_remote_on_client()
	if remote != _remote_mode:
		_remote_mode = remote
		top_level = remote
	if remote:
		var sb := player.snapshot_buffer
		sb.advance(delta * NetworkTime.tickrate)
		var s := sb.sample()
		if s.valid:
			global_position = s.origin
			global_rotation = Vector3(0.0, s.yaw, 0.0)
			head_node.rotation.x = s.pitch
	else:
		head_node.rotation.x = player.head_pitch
