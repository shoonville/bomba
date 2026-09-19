class_name PlayerVisual
extends Node3D
## What other players see: the Figure (a chunky humanoid) in the player's identity colour,
## walking, jumping, aiming its gun and tipping over when dead. Remote players are placed by the SnapshotBuffer (100 ms behind, NETPLAN §7);
## players simulated locally follow their body node.

var player: Player
var cfg: MovementConfig
var head_node: Node3D
var figure: Figure
var _remote_mode: bool = false
var _last_pos: Vector3 = Vector3.ZERO
var _speed: float = 0.0
var _vspeed: float = 0.0


func setup(p: Player, p_cfg: MovementConfig) -> void:
	player = p
	cfg = p_cfg
	figure = Figure.new()
	figure.name = "Figure"
	add_child(figure)
	figure.build(player.colour, "arena", cfg.head_center_height, true)
	head_node = figure.head


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var remote := player._is_remote_on_client()
	if remote != _remote_mode:
		_remote_mode = remote
		top_level = remote
	var pitch := 0.0
	var on_floor := true
	if remote:
		var sb := player.snapshot_buffer
		sb.advance(delta * NetworkTime.tickrate)
		var s := sb.sample()
		if s.valid:
			global_position = s.origin
			global_rotation = Vector3(0.0, s.yaw, 0.0)
			pitch = s.pitch
		# Speed from the played-back positions (smoothed): the walk cycle for remote players.
		if delta > 0.0:
			var d := global_position - _last_pos
			var horizontal := Vector2(d.x, d.z).length() / delta
			_speed = lerpf(_speed, minf(horizontal, 12.0), 0.3)
			_vspeed = lerpf(_vspeed, d.y / delta, 0.3)
		on_floor = absf(_vspeed) < 1.2
		_last_pos = global_position
	else:
		pitch = player.head_pitch
		_speed = Vector2(player.velocity.x, player.velocity.z).length()
		on_floor = player.is_on_floor()
	if figure != null:
		figure.animate(_speed, on_floor, pitch, player.health > 0, delta)
