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
var _last_health: int = 100
var name_label: Label3D
var hide_tag: bool = false   # the spectator camera sits behind this player: its tag would fill the screen


func setup(p: Player, p_cfg: MovementConfig) -> void:
	player = p
	cfg = p_cfg
	var t0 := Time.get_ticks_usec()
	figure = Figure.new()
	figure.name = "Figure"
	add_child(figure)
	figure.build(player.colour, "arena", cfg.head_center_height, true)
	head_node = figure.head
	var t_fig := Time.get_ticks_usec()
	# Name over the head for everyone but yourself (you never see your own figure anyway).
	name_label = Label3D.new()
	name_label.text = player.display_name.to_upper()
	name_label.font_size = 40
	name_label.pixel_size = 0.005
	name_label.outline_size = 12
	name_label.modulate = Palette.hud_colour("paper")
	name_label.outline_modulate = Palette.map_colour("arena", "line")
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	name_label.no_depth_test = false
	name_label.position.y = cfg.head_center_height + 0.5
	add_child(name_label)
	Log.debug("perf", "Visual %s: figure %d ms, name tag %d ms" % [player.display_name, (t_fig - t0) / 1000, (Time.get_ticks_usec() - t_fig) / 1000])


## The final-kill cam drives this figure from the replay buffer instead of its body: a pose per
## frame, the walk cycle from how far it moved, down when it was down.
var _replay: bool = false
var _rp_pos: Vector3 = Vector3.ZERO
var _rp_yaw: float = 0.0
var _rp_pitch: float = 0.0
var _rp_alive: bool = true


func begin_replay() -> void:
	_replay = true
	top_level = true
	_rp_pos = global_position
	_last_pos = global_position


func replay_pose(pos: Vector3, yaw: float, pitch: float, alive: bool) -> void:
	_rp_pos = pos
	_rp_yaw = yaw
	_rp_pitch = pitch
	_rp_alive = alive


func end_replay() -> void:
	_replay = false
	top_level = _remote_mode
	if not _remote_mode:
		position = Vector3.ZERO
		rotation = Vector3.ZERO


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if _replay:
		global_position = _rp_pos
		global_rotation = Vector3(0.0, _rp_yaw, 0.0)
		if delta > 0.0:
			var d := global_position - _last_pos
			_speed = lerpf(_speed, minf(Vector2(d.x, d.z).length() / delta, 12.0), 0.3)
		_last_pos = global_position
		if figure != null:
			_wall_check(_rp_pitch, _rp_alive, delta)
			figure.animate(_speed, true, _rp_pitch, _rp_alive, delta)
		if name_label != null:
			name_label.visible = _rp_alive
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
		if player.health < _last_health and player.health > 0:
			figure.flinch()
		_last_health = player.health
		figure.set_weapon_slot(player.weapons.slot)
		_wall_check(pitch, player.health > 0, delta)
		figure.animate(_speed, on_floor, pitch, player.health > 0, delta)
	if name_label != null:
		name_label.visible = player.health > 0 and not hide_tag


## A barrel never pokes through a wall (Sean, 2026-09-23): a ray from the shoulder along the aim,
## as far as the held gun reaches (world geometry only, layer 1); where a wall is nearer, the gun
## comes up by the angle that clears it (reach · cos(raise) ≤ distance). Only for figures on
## screen; the figure eases the lift so it never pops.
func _wall_check(pitch: float, alive: bool, delta: float) -> void:
	if figure == null:
		return
	var raise := 0.0
	if alive and is_visible_in_tree():
		var reach := figure.gun_reach()
		var from := global_position + Vector3.UP * Figure.SHOULDER_Y
		var dir := -global_transform.basis.z * cos(pitch) + Vector3.UP * sin(pitch)
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * reach, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			raise = acos(clampf(from.distance_to(hit["position"]) / reach, 0.0, 1.0))
			if raise > 0.25 and figure._gun_raise <= 0.05:
				Log.info("figure", "DBG gun lifts %.2f rad off a wall %.2f m away (%s)" % [raise, from.distance_to(hit["position"]), player.display_name])
	figure.set_gun_raise(raise, delta)
