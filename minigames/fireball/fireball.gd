extends FpsMatch
## FIREBALL (Sean, 2026-09-24: "I want it to play like Genji Ball minigame in OverWatch"): a
## round platform in the board's pink sky at half gravity, a katana each, and one fireball.
## Three seconds in (the GET READY countdown) the ball appears over the middle, hovers a beat and
## flies at a player; it homes on its target, and anyone it touches is out. A player with the
## reflect window open (right click, WeaponLogic's parry) whose guard the ball passes through
## sends it back along their crosshair at whoever is nearest that line, faster with every
## reflect. One life; the round ends when one player is left (or the clock runs out, a tie).
##
## The ball is simulated on the host inside the tick loop (NetworkRollback.after_process_tick,
## once per tick, after every player's tick), against the players' state as the host holds it:
## its kills go through Player.take_damage like a shot's, so the kill feed, the scoring and the
## final-kill cam are the shared match's. Clients get its state every tick (unreliable) and the
## events (reliable) for the look and the sounds; the view dead-reckons between states.

const HIT_FIREBALL := 4   # last_hit_info kinds of this minigame (HitscanResolver's stop at HEAD = 3)
const HIT_FALL := 5
enum Phase { NONE, HOVER, FLYING, GONE }

var cfg: Dictionary = {}
var ball_pos: Vector3 = Vector3.ZERO
var ball_vel: Vector3 = Vector3.ZERO
var ball_target: int = 0
var ball_level: int = 0        # reflects since the ball appeared
var ball_phase: int = Phase.NONE
var ball_holder: int = 0       # the last reflector: a kill is theirs

var _phase_tick: int = -1
var _immune_peer: int = 0      # the last reflector, not hit by the ball it just sent for a moment
var _immune_until: int = -1
var _reflect_window: int = -1  # ... and that reflect's window (its parry_since_tick): one press, one reflect
var _reflects: Dictionary = {} # peer → reflects made
var _hits: Dictionary = {}     # peer → {tick, killer, kind}: a hit that player's own tick applies (PlayerContext.hazard_at)
var _last_ball_tick: int = -1
var _view: FireballView
var _replay := PackedFloat32Array()   # per tick: x, y, z, shown, tick (the kill cam)
const REPLAY_STRIDE := 5
var _ball_r: float = 0.45
var _kill_y: float = -14.0
var _platform_r: float = 17.0
var _launch_ticks: int = 45
var _respawn_ticks: int = 90
var _turn_per_tick: float = 0.05
var _aim_height: float = 1.1
var _parry_range: float = 3.2
var _parry_cone: float = 1.3
var _immunity_ticks: int = 12


func _on_setup() -> void:
	cfg = Tuning.table("fireball")
	_ball_r = float(cfg.get("ball_radius_m", 0.45))
	_kill_y = float(cfg.get("kill_below_y", -14.0))
	_platform_r = float(cfg.get("platform_radius_m", 17.0))
	_launch_ticks = int(float(cfg.get("launch_delay_seconds", 0.75)) * NetworkTime.tickrate)
	_respawn_ticks = int(float(cfg.get("respawn_delay_seconds", 1.5)) * NetworkTime.tickrate)
	_turn_per_tick = deg_to_rad(float(cfg.get("homing_turn_deg_s", 160.0))) * NetworkTime.ticktime
	_aim_height = float(cfg.get("aim_height_m", 1.1))
	_parry_range = float(cfg.get("parry_range_m", 3.2))
	_parry_cone = deg_to_rad(float(cfg.get("parry_cone_deg", 75.0)))
	_immunity_ticks = int(cfg.get("reflect_immunity_ticks", 12))
	super._on_setup()
	NetworkRollback.after_process_tick.connect(_on_ball_tick)


func _exit_tree() -> void:
	if NetworkRollback.after_process_tick.is_connected(_on_ball_tick):
		NetworkRollback.after_process_tick.disconnect(_on_ball_tick)
	super._exit_tree()


# --- the match's hooks ---------------------------------------------------------------------

func _respawns() -> bool:
	return false


func _layout() -> Dictionary:
	return PlatformLayout.build(cfg, players.size())


func _palette_map() -> String:
	return "fireball"


func _dress_map() -> bool:
	return false


## Half gravity (Sean: "so we can jump higher as well"): the jump is 6.1 m/s as everywhere, so
## it goes twice as high and hangs twice as long.
func _movement_overrides() -> Dictionary:
	var g := float(Tuning.table("movement").get("gravity", 12.5)) * float(cfg.get("gravity_multiplier", 0.5))
	return {"gravity": g}


func _make_brain() -> Node:
	return FireballBrain.new()


func _kill_weapon_id(_victim: Player, kind: int, weapon_slot: int) -> String:
	match kind:
		HIT_FIREBALL:
			return "fireball"
		HIT_FALL:
			return "fell"
	return super._kill_weapon_id(_victim, kind, weapon_slot)


func _score_for(pl: Player) -> int:
	if pl.is_alive():
		return 1 << 30
	return int(_dead_since.get(pl.peer_id, round_end_tick))


func _score_label(pl: Player) -> String:
	if pl.is_alive():
		return "SURVIVED"
	var secs := int(NetworkTime.seconds_between(round_start_tick, int(_dead_since.get(pl.peer_id, round_end_tick))))
	return "OUT AT %d:%02d" % [secs / 60, secs % 60]


func centre_text() -> String:
	var lp := get_local_player()
	if lp == null or lp.is_alive() or in_warmup():
		return ""
	var watching := spectating_name()
	if watching != "":
		return "OUT  ·  %d LEFT  ·  WATCHING %s" % [alive_count(), watching.to_upper()]
	return "OUT  ·  %d LEFT" % alive_count()


func hud_status() -> Array:
	if in_warmup() or _over_tick >= 0 or (ball_phase != Phase.FLYING and ball_phase != Phase.HOVER):
		return []
	return [{"text": "%d LEFT   ·   FIREBALL %d m/s" % [alive_count(), int(round(FireballSim.speed_for(ball_level, cfg)))], "size": 18, "colour": Palette.hud_colour("paper")}]


func reflects_for(peer: int) -> int:
	return int(_reflects.get(peer, 0))


func hud_score(pl: Player) -> String:
	return "%d" % reflects_for(pl.peer_id)


func hud_score_header() -> String:
	return "R"


# --- the look ------------------------------------------------------------------------------

func build_visuals() -> void:
	await super.build_visuals()
	if not is_inside_tree():
		return
	await _next_frame()
	if not is_inside_tree():
		return
	var t := Time.get_ticks_usec()
	_view = FireballView.new()
	_view.name = "FireballView"
	add_child(_view)
	_view.build(_palette_map())
	if ball_phase == Phase.HOVER or ball_phase == Phase.FLYING:
		_view.set_state(ball_pos, ball_vel, ball_phase == Phase.FLYING, ball_level)
	Log.info("perf", "Fireball look built: %d ms" % [(Time.get_ticks_usec() - t) / 1000])


# --- the ball, on the host ------------------------------------------------------------------

func _on_ball_tick(tick: int) -> void:
	if not is_inside_tree() or not is_authority() or _finished_sent:
		return
	if tick <= _last_ball_tick:
		return   # a resimulated tick: the ball flew it already
	_last_ball_tick = tick
	if round_start_tick < 0 or tick < round_start_tick or _is_frozen(tick):
		return
	_check_falls(tick)
	match ball_phase:
		Phase.NONE:
			_spawn_ball(tick)
		Phase.HOVER:
			if tick - _phase_tick >= _launch_ticks:
				_launch(tick)
		Phase.FLYING:
			_fly(tick)
		Phase.GONE:
			if tick - _phase_tick >= _respawn_ticks:
				_spawn_ball(tick)


## The players still in it: alive and not hit yet (a hit is applied by its victim's own tick, a
## tick or more after the ball's; the ball is done with them the moment it lands).
func _alive_sorted() -> Array:
	var out := []
	for p in _players.values():
		if (p as Player).is_alive() and not _hits.has((p as Player).peer_id):
			out.append(p)
	out.sort_custom(func(a: Player, b: Player): return a.peer_id < b.peer_id)
	return out


func _aim_point(pl: Player) -> Vector3:
	return pl.global_position + Vector3.UP * _aim_height


func _spawn_ball(tick: int) -> void:
	var alive := _alive_sorted()
	if alive.is_empty():
		return
	ball_pos = Vector3(0.0, float(cfg.get("spawn_height_m", 6.0)), 0.0)
	ball_vel = Vector3.ZERO
	ball_level = 0
	ball_holder = 0
	_immune_peer = 0
	_immune_until = -1
	_reflect_window = -1
	var rng := Rng.tick_stream("fireball", tick)
	rng.randi()   # the first draw of a fresh per-tick stream leaned on the middle values (400 spawns: 79/86/125/110 of 4); the second is even
	ball_target = (alive[rng.randi_range(0, alive.size() - 1)] as Player).peer_id
	ball_phase = Phase.HOVER
	_phase_tick = tick
	_rpc_ball_event.rpc("spawn", 0, ball_pos, tick)
	Log.info("fireball", "Ball up at tick %d, hunting %s" % [tick, _name_of(ball_target)])


func _launch(tick: int) -> void:
	var target := _alive_target()
	if target == null:
		return
	ball_vel = (_aim_point(target) - ball_pos).normalized() * FireballSim.speed_for(ball_level, cfg)
	ball_phase = Phase.FLYING
	_phase_tick = tick
	_rpc_ball_event.rpc("launch", ball_target, ball_pos, tick)


## The target, re-picked (the nearest living player) when it died or fell.
func _alive_target() -> Player:
	var t := get_player(ball_target)
	if t != null and t.is_alive():
		return t
	var best: Player = null
	var best_d := 1e18
	for p in _alive_sorted():
		var d := (_aim_point(p) - ball_pos).length_squared()
		if d < best_d:
			best_d = d
			best = p
	ball_target = best.peer_id if best != null else 0
	return best


func _fly(tick: int) -> void:
	var dt := NetworkTime.ticktime
	var speed := FireballSim.speed_for(ball_level, cfg)
	var target := _alive_target()
	var dir := ball_vel.normalized() if ball_vel.length_squared() > 1e-6 else Vector3.FORWARD
	if target != null:
		dir = FireballSim.steer(dir, (_aim_point(target) - ball_pos).normalized(), _turn_per_tick)
	ball_vel = dir * speed
	var prev := ball_pos
	ball_pos = prev + ball_vel * dt
	if _try_reflect(tick, prev):
		return
	if _try_hit(tick, prev):
		return
	if ball_pos.y < _kill_y or Vector2(ball_pos.x, ball_pos.z).length() > _platform_r * 3.0:
		_vanish(tick)


## A ball passing through an open guard (WeaponLogic.parry_active) goes where that player's
## crosshair points, at whoever is nearest that line, one step faster.
func _try_reflect(tick: int, prev: Vector3) -> bool:
	for p in _alive_sorted():
		var pl := p as Player
		if not pl.weapons.parry_active(tick):
			continue
		if pl.peer_id == _immune_peer and (tick < _immune_until or pl.weapons.parry_since_tick == _reflect_window):
			continue   # the window that just sent it (the ball was still inside 3 m twelve ticks on, 2026-09-24)
		var eye := pl.eye_position()
		var aim := pl.aim_direction(pl.yaw, pl.head_pitch)
		if not FireballSim.step_guarded(prev, ball_pos, eye, aim, _parry_range, _parry_cone):
			continue
		var candidates := []
		for q in _alive_sorted():
			if q != pl:
				candidates.append({"id": (q as Player).peer_id, "point": _aim_point(q)})
		var next_target := FireballSim.pick_reflect_target(eye, aim, candidates)
		ball_level += 1
		ball_holder = pl.peer_id
		ball_target = next_target
		ball_pos = eye + aim * 1.0
		ball_vel = aim * FireballSim.speed_for(ball_level, cfg)
		_immune_peer = pl.peer_id
		_immune_until = tick + _immunity_ticks
		_reflect_window = pl.weapons.parry_since_tick
		_reflects[pl.peer_id] = reflects_for(pl.peer_id) + 1
		_rpc_ball_event.rpc("reflect", pl.peer_id, ball_pos, tick)
		Log.info("fireball", "REFLECT by %s at tick %d → %s, %d m/s (reflect %d)" % [pl.display_name, tick, _name_of(next_target), int(round(ball_vel.length())), ball_level])
		return true
	return false


func _try_hit(tick: int, prev: Vector3) -> bool:
	for p in _alive_sorted():
		var pl := p as Player
		if pl.peer_id == _immune_peer and tick < _immune_until:
			continue
		var sample := Hitboxes.sample_from(pl.global_position, move_cfg, true)
		if not FireballSim.step_hits(prev, ball_pos, _ball_r, sample):
			continue
		_hits[pl.peer_id] = {"tick": tick, "killer": ball_holder, "kind": HIT_FIREBALL}
		var at := (pl.global_position + Vector3.UP * _aim_height + ball_pos) * 0.5
		ball_phase = Phase.GONE
		_phase_tick = tick
		_rpc_ball_event.rpc("hit", pl.peer_id, at, tick)
		Log.info("fireball", "HIT %s at tick %d by %s's ball (%d m/s)" % [pl.display_name, tick, _name_of(ball_holder), int(round(ball_vel.length()))])
		return true
	return false


func _vanish(tick: int) -> void:
	ball_phase = Phase.GONE
	_phase_tick = tick
	_rpc_ball_event.rpc("vanish", 0, ball_pos, tick)


## Off the platform is out (the platform floats; there is nothing under it).
func _check_falls(tick: int) -> void:
	for p in _alive_sorted():
		var pl := p as Player
		if pl.global_position.y < _kill_y:
			_hits[pl.peer_id] = {"tick": tick, "killer": 0, "kind": HIT_FALL}
			Log.info("fireball", "%s fell at tick %d" % [pl.display_name, tick])


## The kill, applied inside the victim's own rollback tick (Player._rollback_tick_body through
## PlayerContext.hazard_at) from the tick the ball landed: written from the ball's tick instead,
## the host's next resimulation for a late client input re-ran the victim from before the hit and
## recorded it healthy (a seat took four hits before it died, 2026-09-24).
func _hazard_at(pl: Player, tick: int) -> Dictionary:
	var h: Dictionary = _hits.get(pl.peer_id, {})
	if h.is_empty() or tick < int(h["tick"]):
		return {}
	return {"killer": int(h["killer"]), "kind": int(h["kind"]), "amount": pl.max_health}


func _after_tick_loop() -> void:
	super._after_tick_loop()
	if not is_inside_tree():
		return
	if is_authority():
		_rpc_ball.rpc(NetworkTime.tick, ball_pos, ball_vel, ball_target, ball_level, ball_phase, ball_holder)
		_apply_ball(ball_pos, ball_vel, ball_target, ball_level, ball_phase, ball_holder)
	_record_replay(NetworkTime.tick)


# --- every peer: the state, the events, the look -------------------------------------------

@rpc("authority", "call_remote", "unreliable")
func _rpc_ball(_tick: int, pos: Vector3, vel: Vector3, target: int, level: int, phase: int, holder: int) -> void:
	ball_pos = pos
	ball_vel = vel
	ball_target = target
	ball_level = level
	ball_phase = phase
	ball_holder = holder
	_apply_ball(pos, vel, target, level, phase, holder)


func _apply_ball(pos: Vector3, vel: Vector3, _target: int, level: int, phase: int, _holder: int) -> void:
	if _view == null or not is_instance_valid(_view) or Game.headless:
		return
	if phase == Phase.HOVER or phase == Phase.FLYING:
		_view.set_state(pos, vel, phase == Phase.FLYING, level)
	elif _view.is_shown():
		_view.hide_ball()


@rpc("authority", "call_local", "reliable")
func _rpc_ball_event(kind: String, peer: int, at: Vector3, _tick: int) -> void:
	if Game.headless or not is_inside_tree():
		return
	match kind:
		"spawn":
			if _view != null and is_instance_valid(_view):
				_view.show_ball(at)
			Audio.play_at("portal", at, -6.0, 1.3)
		"launch":
			Audio.play_at("fireball_launch", at, -2.0)
		"reflect":
			if _view != null and is_instance_valid(_view):
				_view.reflected(at, effects_root)
			Audio.play_at("fireball_reflect", at, 0.0)
			if peer == local_peer_id():
				Events.local_hit_predicted.emit(HitscanResolver.BODY, ball_target)   # the hitmarker and its tick
		"hit":
			if _view != null and is_instance_valid(_view):
				_view.burst(at, effects_root)
			Audio.play_at("fireball_hit", at, 0.0)
		"vanish":
			if _view != null and is_instance_valid(_view):
				_view.hide_ball()


## The ball's position per tick on this peer, for the final-kill cam (Player keeps the same for
## the bodies).
func _record_replay(tick: int) -> void:
	if _replay.is_empty():
		_replay.resize(Player.REPLAY_TICKS * REPLAY_STRIDE)
		_replay.fill(-1.0)
	var i := posmod(tick, Player.REPLAY_TICKS) * REPLAY_STRIDE
	_replay[i] = ball_pos.x
	_replay[i + 1] = ball_pos.y
	_replay[i + 2] = ball_pos.z
	_replay[i + 3] = 1.0 if (ball_phase == Phase.HOVER or ball_phase == Phase.FLYING) else 0.0
	_replay[i + 4] = float(tick)


func _replay_at(tick: int) -> Dictionary:
	if _replay.is_empty():
		return {}
	for back in 8:
		var tk := tick - back
		var i := posmod(tk, Player.REPLAY_TICKS) * REPLAY_STRIDE
		if int(_replay[i + 4]) == tk:
			return {"pos": Vector3(_replay[i], _replay[i + 1], _replay[i + 2]), "shown": _replay[i + 3] > 0.5}
	return {}


func killcam_place(pt: float) -> void:
	if _view == null or not is_instance_valid(_view):
		return
	var a := _replay_at(int(floor(pt)))
	if a.is_empty():
		_view.replay_at(Vector3.ZERO, false)
		return
	var b := _replay_at(int(floor(pt)) + 1)
	var pos: Vector3 = a["pos"]
	if not b.is_empty() and bool(b["shown"]):
		pos = pos.lerp(b["pos"], pt - floor(pt))
	_view.replay_at(pos, bool(a["shown"]))


func killcam_fire(weapon: String) -> bool:
	if weapon != "fireball":
		return false
	if _view != null and is_instance_valid(_view):
		_view.burst(_view.global_position, effects_root)
	Audio.play("fireball_hit", -2.0)
	return true


func killcam_end() -> void:
	if _view == null or not is_instance_valid(_view):
		return
	if ball_phase == Phase.HOVER or ball_phase == Phase.FLYING:
		_view.show_ball(ball_pos)
		_view.set_state(ball_pos, ball_vel, ball_phase == Phase.FLYING, ball_level)
	else:
		_view.hide_ball()
