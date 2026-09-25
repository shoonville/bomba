class_name FireballBrain
extends Node
## FIREBALL's bot (and the --autoplay seat): no hunting, no guns. It wanders the platform well
## inside the rim, keeps its eyes on the ball, and when the ball turns on it and is a beat away
## it either turns to someone and brings the blade up to reflect it at them, or sidesteps and
## jumps, or (the easy ones, some of the time) does nothing and burns. Every roll comes from a
## seeded stream, so a soak is reproducible. Reads the match through PlayerContext.arena.

var player: Player
var ctx: PlayerContext
var arena: Node
var rng: RandomNumberGenerator
var cur_yaw: float = 0.0
var cur_pitch: float = 0.0
var turn_speed: float = 6.0
var press_seconds: float = 0.24
var reaction_ticks: int = 8
var parry_chance: float = 0.8
var dodge_chance: float = 0.15
var jump_chance: float = 0.3
var wander_frac: float = 0.7
var wander_ticks: int = 150
var platform_r: float = 17.0
var wander_target: Vector3 = Vector3.ZERO
var wander_until: int = -1
var threat_since: int = -1     # the tick the ball turned on this bot
var decision: int = 0          # 0 undecided, 1 reflect, 2 dodge, 3 freeze
var victim: Player = null
var dodge_dir: float = 1.0


func setup(p_player: Player, p_ctx: PlayerContext, difficulty: String) -> void:
	player = p_player
	ctx = p_ctx
	arena = ctx.get("arena")
	rng = Rng.stream("fireball_bot_%d" % player.peer_id)
	var cfg: Dictionary = Tuning.table("fireball")
	var bots: Dictionary = cfg.get("bots", {})
	var diff: Dictionary = bots.get(difficulty, bots.get("normal", {}))
	var tr := float(NetworkTime.tickrate)
	turn_speed = deg_to_rad(float(diff.get("turn_speed_deg_s", 360.0)))
	press_seconds = float(diff.get("press_seconds", 0.24))
	reaction_ticks = int(float(diff.get("reaction_ms", 120)) / 1000.0 * tr)
	parry_chance = float(diff.get("parry_chance", 0.8))
	dodge_chance = float(diff.get("dodge_chance", 0.15))
	jump_chance = float(diff.get("jump_chance_per_s", 0.3))
	wander_frac = float(bots.get("wander_radius_frac", 0.7))
	wander_ticks = int(float(bots.get("wander_seconds", 2.5)) * tr)
	platform_r = float(cfg.get("platform_radius_m", 17.0))
	cur_yaw = player.rotation.y


func gather_into(input: PlayerInput) -> void:
	var tick := NetworkTime.tick
	var dt := NetworkTime.ticktime
	if not player.is_alive() or arena == null:
		_write(input, Vector2.ZERO, false, false, cur_yaw, cur_pitch)
		return
	var pos := player.global_position
	var eye := player.eye_position()
	var phase: int = arena.ball_phase
	var flying: bool = phase == arena.Phase.FLYING
	var ball_pos: Vector3 = arena.ball_pos
	var ball_vel: Vector3 = arena.ball_vel

	# Wander: a fresh spot inside the rim every few seconds, or once this one is reached.
	if wander_until < 0 or tick >= wander_until or Vector2(wander_target.x - pos.x, wander_target.z - pos.z).length() < 1.0:
		_new_wander(tick, pos)
	var move_dir := wander_target - pos
	move_dir.y = 0.0
	move_dir = move_dir.normalized() if move_dir.length() > 0.5 else Vector3.ZERO

	# Eyes on the ball while it is up; on the middle of the platform otherwise.
	var look_at := ball_pos if (phase == arena.Phase.HOVER or flying) else Vector3(0.0, 6.0, 0.0)
	var to_look := look_at - eye
	var desired_yaw := atan2(-to_look.x, -to_look.z)
	var desired_pitch := atan2(to_look.y, Vector2(to_look.x, to_look.z).length())

	var ads := false
	var jump := rng.randf() < jump_chance * dt
	if flying:
		var to_me := eye - ball_pos
		var dist := to_me.length()
		var closing := ball_vel.dot(to_me.normalized()) if dist > 0.01 else 0.0
		var eta := dist / closing if closing > 0.5 else 99.0
		var threatened: bool = int(arena.ball_target) == player.peer_id or (closing > 3.0 and eta < 1.5)
		if threatened:
			if threat_since < 0:
				threat_since = tick
		else:
			threat_since = -1
			decision = 0
		if threat_since >= 0 and decision == 0 and tick - threat_since >= reaction_ticks:
			var roll := rng.randf()
			if roll < parry_chance:
				decision = 1
			elif roll < parry_chance + dodge_chance:
				decision = 2
			else:
				decision = 3
			victim = _pick_victim(eye, ball_pos)
			dodge_dir = 1.0 if rng.randf() < 0.5 else -1.0
		if decision == 1:
			# Turn to the victim as the ball closes, press when it is a beat out and the blade is ready.
			if victim != null and is_instance_valid(victim) and victim.is_alive() and eta < press_seconds * 3.0:
				var to_v := (victim.global_position + Vector3.UP * 1.1) - eye
				desired_yaw = atan2(-to_v.x, -to_v.z)
				desired_pitch = atan2(to_v.y, Vector2(to_v.x, to_v.z).length())
			if eta <= press_seconds and player.weapons.parry_ready_in(tick) == 0:
				ads = true
		elif decision == 2 and eta < 0.7:
			# A sidestep and a jump, away from the rim.
			var side := MovementModel.right_from_yaw(cur_yaw) * dodge_dir
			if Vector2(pos.x + side.x * 3.0, pos.z + side.z * 3.0).length() > platform_r * 0.85:
				dodge_dir = -dodge_dir
				side = -side
			move_dir = side
			jump = true
	else:
		threat_since = -1
		decision = 0

	var max_step := turn_speed * dt
	cur_yaw = _rotate_toward(cur_yaw, desired_yaw, max_step)
	cur_pitch = clampf(move_toward(cur_pitch, desired_pitch, max_step), -1.5, 1.5)
	var wish := Vector2.ZERO
	if move_dir != Vector3.ZERO:
		wish = Vector2(move_dir.dot(MovementModel.right_from_yaw(cur_yaw)), move_dir.dot(MovementModel.forward_from_yaw(cur_yaw))).limit_length(1.0)
	_write(input, wish, jump, ads, cur_yaw, cur_pitch)


## The player to send the ball at: one whose direction keeps the ball inside the guard's cone
## (within 70° of where the ball is), the nearest of them; nobody means aim at the ball itself
## and let the reflect find whoever is nearest that line.
func _pick_victim(eye: Vector3, ball_pos: Vector3) -> Player:
	var best: Player = null
	var best_d := 1e9
	var to_ball := (ball_pos - eye).normalized()
	for p in ctx.all_players():
		var other := p as Player
		if other == null or other == player or not other.is_alive():
			continue
		var to := (other.global_position + Vector3.UP * 1.1) - eye
		if to_ball.angle_to(to.normalized()) > deg_to_rad(70.0):
			continue
		if to.length() < best_d:
			best_d = to.length()
			best = other
	return best


func _new_wander(tick: int, pos: Vector3) -> void:
	var r := platform_r * wander_frac * sqrt(rng.randf())
	var a := rng.randf() * TAU
	wander_target = Vector3(cos(a) * r, 0.0, sin(a) * r)
	if Vector2(wander_target.x - pos.x, wander_target.z - pos.z).length() < 2.0:
		wander_target = Vector3(-wander_target.x, 0.0, -wander_target.z)
	wander_until = tick + wander_ticks + rng.randi_range(0, wander_ticks)


func _write(input: PlayerInput, wish: Vector2, jump: bool, ads: bool, yaw: float, pitch: float) -> void:
	input.move = wish
	input.yaw = yaw
	input.pitch = pitch
	input.look_yaw = yaw
	input.look_pitch = pitch
	input.jump = jump
	input.fire = false
	input.fire_pressed = false
	input.ads = ads
	input.reload = false
	input.weapon = 0


static func _rotate_toward(from: float, to: float, max_step: float) -> float:
	var diff := wrapf(to - from, -PI, PI)
	return from + clampf(diff, -max_step, max_step)
