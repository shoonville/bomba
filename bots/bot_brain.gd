class_name BotBrain
extends Node
## Reusable bot: writes a PlayerInput every tick loop from what it can see through PlayerContext.
## Hunts along the minigame's waypoint graph, acquires enemies by distance + line of sight,
## aims with a reaction delay and a per-burst error, quickscopes at range, sprays up close.
## Everything random comes from a seeded stream so a soak is reproducible.

var player: Player
var ctx: PlayerContext
var diff: Dictionary = {}
var rng: RandomNumberGenerator

var waypoints: Array = []
var adjacency: Dictionary = {}
var path: Array = []
var target_wp: int = -1
var repath_at_tick: int = 0
var reach_m: float = 1.2

var enemy: Player = null
var enemy_since_tick: int = -1
var aim_err: Vector2 = Vector2.ZERO
var cur_yaw: float = 0.0
var cur_pitch: float = 0.0
var burst_left: int = 0
var pause_left: int = 0
var scope_hold: int = 0
var strafe_dir: float = 0.0
var strafe_change_tick: int = 0
var last_pos: Vector3 = Vector3.ZERO
var stuck_ticks: int = 0
var scan_tick: int = -100

var reaction_ticks: int = 15
var turn_speed: float = 6.0
var engage_range: float = 40.0
var sniper_min_range: float = 14.0
var burst_ticks: int = 14
var burst_pause_ticks: int = 12
var jump_chance: float = 0.25
var strafe_change_ticks: int = 60
var scope_hold_ticks: int = 22
var aim_error_deg: float = 3.0
var stuck_limit_ticks: int = 90


func setup(p_player: Player, p_ctx: PlayerContext, difficulty: String) -> void:
	player = p_player
	ctx = p_ctx
	var bots := Tuning.table("bots")
	var diffs: Dictionary = bots.get("difficulties", {})
	diff = diffs.get(difficulty, diffs.get("normal", {}))
	rng = Rng.stream("bot_%d" % player.peer_id)
	var tr := float(NetworkTime.tickrate)
	reaction_ticks = int(float(diff.get("reaction_ms", 280)) / 1000.0 * tr)
	turn_speed = deg_to_rad(float(diff.get("turn_speed_deg_s", 360.0)))
	engage_range = float(diff.get("engage_range_m", 40.0))
	sniper_min_range = float(diff.get("sniper_min_range_m", 14.0))
	burst_ticks = int(diff.get("burst_ticks", 14))
	burst_pause_ticks = int(diff.get("burst_pause_ticks", 12))
	jump_chance = float(diff.get("jump_chance_per_s", 0.25))
	strafe_change_ticks = int(float(diff.get("strafe_change_s", 1.0)) * tr)
	scope_hold_ticks = int(diff.get("scope_hold_ticks", 22))
	aim_error_deg = float(diff.get("aim_error_deg", 3.0))
	reach_m = float(bots.get("waypoint_reach_m", 1.2))
	stuck_limit_ticks = int(float(bots.get("stuck_seconds", 1.5)) * tr)
	waypoints = ctx.waypoints()
	for e in ctx.waypoint_edges():
		var a := int(e[0])
		var b := int(e[1])
		if not adjacency.has(a):
			adjacency[a] = []
		if not adjacency.has(b):
			adjacency[b] = []
		adjacency[a].append(b)
		adjacency[b].append(a)
	cur_yaw = player.rotation.y
	last_pos = player.global_position


func gather_into(input: PlayerInput) -> void:
	var tick := NetworkTime.tick
	var dt := NetworkTime.ticktime
	if not player.is_alive():
		_write(input, Vector2.ZERO, false, false, false, false, false, input.weapon)
		return
	var pos := player.global_position
	var eye := player.eye_position()
	_update_enemy(tick, eye)
	_update_nav(tick, pos)

	var move_dir := Vector3.ZERO
	if target_wp >= 0 and target_wp < waypoints.size():
		var to: Vector3 = waypoints[target_wp] - pos
		to.y = 0.0
		if to.length() > 0.1:
			move_dir = to.normalized()

	var desired_yaw := cur_yaw
	var desired_pitch := 0.0
	var dist := 0.0
	if enemy != null:
		var to_e := (enemy.eye_position() - Vector3.UP * 0.08) - eye
		dist = to_e.length()
		desired_yaw = atan2(-to_e.x, -to_e.z) + aim_err.x
		desired_pitch = atan2(to_e.y, Vector2(to_e.x, to_e.z).length()) + aim_err.y
	elif move_dir != Vector3.ZERO:
		desired_yaw = atan2(-move_dir.x, -move_dir.z)
	var max_step := turn_speed * dt
	cur_yaw = _rotate_toward(cur_yaw, desired_yaw, max_step)
	cur_pitch = clampf(move_toward(cur_pitch, desired_pitch, max_step), -1.5, 1.5)

	var wish := Vector2.ZERO
	if move_dir != Vector3.ZERO:
		wish = Vector2(move_dir.dot(MovementModel.right_from_yaw(cur_yaw)), move_dir.dot(MovementModel.forward_from_yaw(cur_yaw)))
	if enemy != null:
		if tick >= strafe_change_tick:
			strafe_dir = [-1.0, 0.0, 1.0][rng.randi_range(0, 2)]
			strafe_change_tick = tick + strafe_change_ticks
		wish.x += strafe_dir * 0.8
		wish = wish.limit_length(1.0)

	var want_slot := player.weapons.slot
	if enemy != null:
		want_slot = 0 if dist >= sniper_min_range else 1
	want_slot = clampi(want_slot, 0, maxi(0, player.weapons.defs.size() - 1))
	var fire := false
	var fire_pressed := false
	var ads := false
	if enemy != null and tick - enemy_since_tick >= reaction_ticks and player.weapons.slot == want_slot:
		if want_slot == 0 and player.weapons.defs.size() > 0 and player.weapons.defs[0].is_sniper():
			ads = true
			scope_hold += 1
			if scope_hold >= scope_hold_ticks:
				fire_pressed = true
				scope_hold = 0
				_new_aim_error()
		else:
			if burst_left > 0:
				fire = true
				burst_left -= 1
				if burst_left == 0:
					pause_left = burst_pause_ticks
					_new_aim_error()
			elif pause_left > 0:
				pause_left -= 1
			else:
				burst_left = burst_ticks
	else:
		scope_hold = 0

	var jump := rng.randf() < jump_chance * dt
	if (pos - last_pos).length() < 0.02 and move_dir != Vector3.ZERO:
		stuck_ticks += 1
	else:
		stuck_ticks = 0
	last_pos = pos
	if stuck_ticks > stuck_limit_ticks:
		jump = true
		stuck_ticks = 0
		_pick_destination(pos, true)
	var reload := player.weapons.ammo_for_slot(player.weapons.slot) <= 0 and enemy == null
	_write(input, wish, jump, fire, fire_pressed, ads, reload, want_slot)


func _write(input: PlayerInput, wish: Vector2, jump: bool, fire: bool, fire_pressed: bool,
		ads: bool, reload: bool, weapon: int) -> void:
	input.move = wish
	input.yaw = cur_yaw
	input.pitch = cur_pitch
	input.look_yaw = cur_yaw
	input.look_pitch = cur_pitch
	input.jump = jump
	input.fire = fire
	input.fire_pressed = fire_pressed
	input.ads = ads
	input.reload = reload
	input.weapon = weapon


func _new_aim_error() -> void:
	aim_err = Vector2(deg_to_rad(rng.randf_range(-aim_error_deg, aim_error_deg)),
		deg_to_rad(rng.randf_range(-aim_error_deg, aim_error_deg)))


func _update_enemy(tick: int, eye: Vector3) -> void:
	if enemy != null and (not is_instance_valid(enemy) or not enemy.is_alive()):
		enemy = null
	if tick - scan_tick < 6 and enemy != null and _can_see(eye, enemy):
		return
	scan_tick = tick
	var best: Player = null
	var best_d := engage_range
	for p in ctx.all_players():
		var other := p as Player
		if other == null or other == player or not other.is_alive():
			continue
		var d := (other.eye_position() - eye).length()
		if d > best_d:
			continue
		if _can_see(eye, other):
			best = other
			best_d = d
	if best != enemy:
		enemy = best
		enemy_since_tick = tick
		scope_hold = 0
		burst_left = 0
		pause_left = 0
		_new_aim_error()


func _can_see(eye: Vector3, other: Player) -> bool:
	var space := ctx.space_state()
	if space == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(eye, other.eye_position(), ctx.world_mask())
	return space.intersect_ray(q).is_empty()


func _update_nav(tick: int, pos: Vector3) -> void:
	if waypoints.is_empty():
		return
	if target_wp >= 0:
		var to: Vector3 = waypoints[target_wp] - pos
		to.y = 0.0
		if to.length() < reach_m:
			if path.is_empty():
				target_wp = -1
			else:
				target_wp = int(path.pop_front())
	if target_wp < 0 or tick >= repath_at_tick:
		_pick_destination(pos, false)


func _pick_destination(pos: Vector3, force_new: bool) -> void:
	var start := _nearest_waypoint(pos)
	var dest := start
	var tries := 0
	while (dest == start or (force_new and dest == target_wp)) and tries < 8:
		dest = rng.randi_range(0, waypoints.size() - 1)
		tries += 1
	path = _bfs(start, dest)
	if path.is_empty():
		target_wp = dest
	else:
		target_wp = int(path.pop_front())
	repath_at_tick = NetworkTime.tick + int(float(Tuning.value("bots.repath_seconds", 2.5)) * NetworkTime.tickrate * 4.0)


func _nearest_waypoint(pos: Vector3) -> int:
	var best := 0
	var best_d := 1e18
	for i in waypoints.size():
		var d: float = (waypoints[i] - pos).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


func _bfs(start: int, dest: int) -> Array:
	if start == dest:
		return []
	var prev := {start: -1}
	var queue := [start]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == dest:
			break
		for n in adjacency.get(cur, []):
			if not prev.has(n):
				prev[n] = cur
				queue.append(n)
	if not prev.has(dest):
		return [dest]
	var out := []
	var c := dest
	while c != start and c != -1:
		out.push_front(c)
		c = int(prev[c])
	return out


static func _rotate_toward(from: float, to: float, max_step: float) -> float:
	var diff := wrapf(to - from, -PI, PI)
	return from + clampf(diff, -max_step, max_step)
