class_name Arena
extends Minigame
## The first minigame: first-person free-for-all, timed, most kills wins, instant respawn with
## spawn protection. Self-contained: it builds its own map, spawns players from the SDK's
## player list, drives bots through PlayerContext, and returns a ranked result.

const PLAYER_SCENE := preload("res://fps/player/player.tscn")


class ArenaContext:
	extends PlayerContext
	var arena: Arena

	func on_player_died(player: Node, tick: int) -> void:
		arena._on_player_died(player, tick)

	func targets_for(shooter: Node) -> Array:
		return arena._targets_for(shooter)

	func all_players() -> Array:
		return arena._players.values()

	func space_state() -> PhysicsDirectSpaceState3D:
		return arena.get_world_3d().direct_space_state

	func remote_render_tick() -> float:
		return arena.remote_render_tick()

	func lag_comp_max_ticks() -> int:
		return arena.lag_comp_ticks

	func world_mask() -> int:
		return 1

	func waypoints() -> Array:
		return arena.layout.get("waypoints", [])

	func waypoint_edges() -> Array:
		return arena.layout.get("edges", [])

	func notify_shot(shooter: Node, tick: int, origin: Vector3, end_point: Vector3, hit_kind: int) -> void:
		arena._notify_shot(shooter, tick, origin, end_point, hit_kind)


var arena_cfg: Dictionary = {}
var move_cfg: MovementConfig
var weapon_defs: Array[WeaponDef] = []
var swap_ticks: int = 20
var layout: Dictionary = {}
var spawn_selector := SpawnSelector.new()
var round_start_tick: int = -1
var round_end_tick: int = -1
var lag_comp_ticks: int = 15
var kill_log: Array = []

var _players: Dictionary = {}
var _ctx: ArenaContext
var _pending_kills: Array = []
var _kill_sent: Dictionary = {}
var _shot_sent: Dictionary = {}
var _pending_shots: Array = []
var _finished_sent: bool = false
var _camera_rig: Node3D

@onready var players_root: Node3D = $Players
@onready var map_root: Node3D = $Map
@onready var effects_root: Node3D = $Effects


func _on_setup() -> void:
	arena_cfg = Tuning.table("arena")
	move_cfg = MovementConfig.from_dict(Tuning.table("movement"))
	var wt := Tuning.table("weapons")
	weapon_defs = WeaponDef.load_all(wt)
	swap_ticks = int(wt.get("swap_ticks", 20))
	lag_comp_ticks = int(round(Tuning.float_value("net.lag_comp_max_ms", 250.0) / 1000.0 * NetworkTime.tickrate))

	layout = ArenaLayout.build()
	MapBuilder.build(map_root, layout, "arena")
	_build_environment()
	spawn_selector.configure(layout["spawns"], arena_cfg, move_cfg.eye_height)
	_ctx = ArenaContext.new()
	_ctx.arena = self

	var sorted := players.duplicate()
	sorted.sort_custom(func(a: MinigamePlayer, b: MinigamePlayer): return a.peer_id < b.peer_id)
	for i in sorted.size():
		_spawn_player(sorted[i], i)

	NetworkTime.on_tick.connect(_on_tick)
	NetworkTime.after_tick_loop.connect(_after_tick_loop)
	Events.local_shot_fx.connect(_on_local_shot_fx)
	_attach_camera()

	if is_authority():
		if multiplayer.multiplayer_peer is OfflineMultiplayerPeer and not NetworkTime.is_initial_sync_done():
			# Offline (harness) run: nothing started the clock.
			NetworkTime.start()
		var warm := int(float(arena_cfg.get("warmup_seconds", 3)) * NetworkTime.tickrate)
		var secs := int(config.get("round_seconds", 0))
		if secs <= 0:
			secs = int(arena_cfg.get("round_seconds", 180))
		var start := NetworkTime.tick + warm
		_rpc_round.rpc(start, start + secs * NetworkTime.tickrate)
	Log.info("arena", "Setup: %d players, %d boxes, %d spawns" % [_players.size(), layout["boxes"].size(), layout["spawns"].size()])


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://art/shaders/sky_clouds.gdshader")
	sky_mat.set_shader_parameter("sky_top", Palette.map_colour("arena", "sky_top"))
	sky_mat.set_shader_parameter("sky_horizon", Palette.map_colour("arena", "sky_bottom"))
	sky_mat.set_shader_parameter("cloud_lit", Palette.map_colour("arena", "cloud_lit"))
	sky_mat.set_shader_parameter("cloud_shadow", Palette.map_colour("arena", "cloud_shadow"))
	sky_mat.set_shader_parameter("ink", Palette.map_colour("arena", "line"))
	sky_mat.set_shader_parameter("cloud_coverage", Tuning.float_value("palette.maps.arena.cloud_coverage", 0.44))
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Palette.map_colour("arena", "counter")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 90.0
	sun.light_angular_distance = 0.0
	sun.shadow_bias = 0.03
	sun.rotation_degrees = Vector3(-52.0, 35.0, 0.0)
	add_child(sun)


func _spawn_player(mp: MinigamePlayer, index: int) -> void:
	var p: Player = PLAYER_SCENE.instantiate()
	p.name = "Player_%d" % mp.peer_id
	var spawns: Array = layout["spawns"]
	var sp: Dictionary = spawns[index % spawns.size()]
	p.position = sp["pos"]
	p.yaw = float(sp["yaw"])
	p.rotation = Vector3(0.0, float(sp["yaw"]), 0.0)
	players_root.add_child(p)
	p.configure(mp, _ctx, move_cfg, weapon_defs, swap_ticks, int(arena_cfg.get("health", 100)))
	p.input.set_look(float(sp["yaw"]), 0.0)
	_players[mp.peer_id] = p
	var vis := PlayerVisual.new()
	p.visual.add_child(vis)
	vis.setup(p, move_cfg)
	var wants_brain := false
	if mp.is_bot and is_authority():
		wants_brain = true
	elif not mp.is_bot and mp.peer_id == local_peer_id() and Game.args.has("autoplay"):
		wants_brain = true
	if wants_brain:
		var brain := BotBrain.new()
		brain.name = "Brain"
		p.input.add_child(brain)
		brain.setup(p, _ctx, mp.bot_difficulty if mp.is_bot else str(Game.args.get("autoplay_difficulty", "normal")))
		p.input.brain = brain
	Log.debug("arena", "Spawned %s (peer %d, bot=%s) at %s" % [p.name, mp.peer_id, mp.is_bot, p.position])


func _attach_camera() -> void:
	if Game.headless:
		return
	if Game.args.has("spectate"):
		# Showcase/spectator camera: a fixed vantage over the map with the post stack.
		var cam := Camera3D.new()
		cam.name = "SpectatorCamera"
		cam.fov = 55.0
		add_child(cam)
		cam.global_position = Vector3(-14.0, 11.0, 24.0)
		cam.look_at(Vector3(1.0, 2.5, -2.0), Vector3.UP)
		cam.current = true
		var post := PostStack.new()
		cam.add_child(post)
		post.setup("arena")
		return
	var local := get_local_player()
	if local == null:
		return
	_camera_rig = CameraRig.new()
	_camera_rig.name = "CameraRig"
	add_child(_camera_rig)
	_camera_rig.attach(local)


var _fx_test_timer: float = 0.0


func _process(delta: float) -> void:
	# --fx_test: keep spawning drawn bursts and tracers so a screenshot can catch them.
	if not Game.args.has("fx_test") or Game.headless:
		return
	_fx_test_timer += delta
	if _fx_test_timer < 0.22:
		return
	_fx_test_timer = 0.0
	var rng := Rng.stream("fx_test")
	# In front of whatever camera is current, 3–7 m out, so the shapes are large enough to judge.
	var cam := get_viewport().get_camera_3d()
	var base := Vector3(0.0, 2.0, 0.0)
	var fwd := Vector3.FORWARD
	if cam != null:
		base = cam.global_position
		fwd = -cam.global_transform.basis.z
	var right := fwd.cross(Vector3.UP).normalized()
	var at := base + fwd * rng.randf_range(3.0, 7.0) + right * rng.randf_range(-2.5, 2.5) + Vector3.UP * rng.randf_range(-1.0, 1.0)
	var from := at + right * rng.randf_range(-3.0, 3.0) + fwd * rng.randf_range(1.0, 4.0) + Vector3.UP * rng.randf_range(0.0, 1.5)
	var kind: int = [HitscanResolver.WORLD, HitscanResolver.BODY, HitscanResolver.HEAD][rng.randi_range(0, 2)]
	Tracer.spawn(effects_root, from, at, Palette.player_colour(rng.randi_range(0, 5)), kind, 0.3)
	Burst.spawn_muzzle(effects_root, from, Palette.hud_colour("meter"))


# --- queries -----------------------------------------------------------------------------

func get_local_player() -> Player:
	for p in _players.values():
		if (p as Player).is_local():
			return p
	return null


func get_player(peer_id: int) -> Player:
	return _players.get(peer_id, null)


func all_player_nodes() -> Array:
	return _players.values()


func time_remaining_seconds() -> float:
	if round_end_tick < 0:
		return 0.0
	return maxf(0.0, NetworkTime.seconds_between(NetworkTime.tick, round_end_tick))


func in_warmup() -> bool:
	return round_start_tick >= 0 and NetworkTime.tick < round_start_tick


func remote_render_tick() -> float:
	var sum := 0.0
	var n := 0
	for p in _players.values():
		var pl := p as Player
		if pl._is_remote_on_client() and pl.snapshot_buffer.render_tick() >= 0.0:
			sum += pl.snapshot_buffer.render_tick()
			n += 1
	if n == 0:
		return float(NetworkTime.tick)
	return sum / float(n)


func _targets_for(shooter: Node) -> Array:
	var out := []
	for p in _players.values():
		if p == shooter:
			continue
		var t := HitscanResolver.Target.new()
		t.id = (p as Player).peer_id
		t.node = p
		t.history = (p as Player).hitbox_history
		out.append(t)
	return out


# --- authority: deaths, scoring, round -----------------------------------------------------

func _on_player_died(node: Node, tick: int) -> void:
	var victim := node as Player
	var killer_id := victim.last_hit_by
	var info := victim.last_hit_info
	victim.deaths += 1
	if killer_id != 0 and killer_id != victim.peer_id and _players.has(killer_id):
		var killer: Player = _players[killer_id]
		killer.kills += 1
		NetworkRollback.mutate(killer)
	var enemies := []
	for p in _players.values():
		if p != victim and (p as Player).is_alive():
			enemies.append((p as Player).eye_position())
	var sp := spawn_selector.pick(enemies, get_world_3d().direct_space_state, tick,
		Rng.tick_stream("spawn", tick, victim.peer_id))
	victim.respawn_at(sp["pos"], sp["yaw"], tick, int(arena_cfg.get("spawn_protection_ticks", 90)))
	var key := "%d_%d" % [victim.peer_id, tick]
	if not _kill_sent.has(key):
		_kill_sent[key] = true
		var weapon_slot := info % 10
		var kind := int(info / 10)
		var weapon_id := weapon_defs[weapon_slot].id if weapon_slot < weapon_defs.size() else "?"
		_pending_kills.append([killer_id, victim.peer_id, weapon_id, kind == HitscanResolver.HEAD, tick])


func _notify_shot(shooter: Node, tick: int, origin: Vector3, end_point: Vector3, hit_kind: int) -> void:
	var pl := shooter as Player
	var last: int = _shot_sent.get(pl.peer_id, -1)
	if tick <= last:
		return
	_shot_sent[pl.peer_id] = tick
	var def := pl.weapons.current_def()
	_pending_shots.append([pl.peer_id, origin, end_point, hit_kind, def.id if def != null else "ar"])


func _on_local_shot_fx(origin: Vector3, point: Vector3, hit_kind: int) -> void:
	if Game.headless or not is_inside_tree():
		return
	var start := origin
	if _camera_rig != null and is_instance_valid(_camera_rig) and _camera_rig.viewmodel != null:
		start = _camera_rig.viewmodel.muzzle_world()
	var local := get_local_player()
	var colour := local.colour if local != null else Color.WHITE
	Tracer.spawn(effects_root, start, point, colour, hit_kind)
	Burst.spawn_muzzle(effects_root, start, Palette.hud_colour("meter"))


func _exit_tree() -> void:
	if Events.local_shot_fx.is_connected(_on_local_shot_fx):
		Events.local_shot_fx.disconnect(_on_local_shot_fx)
	if NetworkTime.on_tick.is_connected(_on_tick):
		NetworkTime.on_tick.disconnect(_on_tick)
	if NetworkTime.after_tick_loop.is_connected(_after_tick_loop):
		NetworkTime.after_tick_loop.disconnect(_after_tick_loop)


func _on_tick(_delta: float, tick: int) -> void:
	if not is_inside_tree() or not is_authority() or _finished_sent:
		return
	if round_end_tick > 0 and tick >= round_end_tick:
		_finish_round()


func _after_tick_loop() -> void:
	if not is_inside_tree() or not is_authority():
		return
	for k in _pending_kills:
		_rpc_kill.rpc(k[0], k[1], k[2], k[3], k[4])
	_pending_kills.clear()
	for s in _pending_shots:
		_rpc_shot_fx.rpc(s[0], s[1], s[2], s[3], s[4])
		_apply_shot_fx(s[0], s[1], s[2], s[3], s[4])
	_pending_shots.clear()


func _finish_round() -> void:
	_finished_sent = true
	var result := MinigameResult.new()
	for p in _players.values():
		var pl := p as Player
		result.add(pl.peer_id, pl.kills, pl.display_name)
	result.finalize()
	_rpc_finish.rpc(result.to_dict())


# --- RPCs ---------------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _rpc_round(start_tick: int, end_tick: int) -> void:
	round_start_tick = start_tick
	round_end_tick = end_tick
	Events.round_started.emit(end_tick)
	Log.info("arena", "Round: ticks %d → %d (%.0f s)" % [start_tick, end_tick, NetworkTime.seconds_between(start_tick, end_tick)])


@rpc("authority", "call_local", "reliable")
func _rpc_kill(killer_id: int, victim_id: int, weapon_id: String, headshot: bool, tick: int) -> void:
	kill_log.append({"killer": killer_id, "victim": victim_id, "weapon": weapon_id, "headshot": headshot, "tick": tick})
	Events.kill.emit(killer_id, victim_id, weapon_id, headshot, tick)
	var kn := _name_of(killer_id)
	var vn := _name_of(victim_id)
	Log.info("arena", "KILL %s → %s (%s%s) @%d" % [kn, vn, weapon_id, " HS" if headshot else "", tick])


@rpc("authority", "call_remote", "unreliable")
func _rpc_shot_fx(shooter_id: int, origin: Vector3, end_point: Vector3, hit_kind: int, weapon: String) -> void:
	_apply_shot_fx(shooter_id, origin, end_point, hit_kind, weapon)


## Tracer, impact burst and 3D gunshot for another player's shot (the local player's own shots
## are handled from its predicted fire action).
func _apply_shot_fx(shooter_id: int, origin: Vector3, end_point: Vector3, hit_kind: int, weapon: String) -> void:
	if shooter_id == local_peer_id() or Game.headless or not is_inside_tree():
		return
	var shooter := get_player(shooter_id)
	var colour := shooter.colour if shooter != null else Color.WHITE
	Tracer.spawn(effects_root, origin, end_point, colour, hit_kind)
	Events.remote_shot.emit(weapon, origin)


@rpc("authority", "call_local", "reliable")
func _rpc_finish(data: Dictionary) -> void:
	Events.round_ended.emit()
	finish(MinigameResult.from_dict(data))


func _name_of(id: int) -> String:
	var p := get_player(id)
	if p == null:
		return "world" if id == 0 else "#%d" % id
	return p.display_name
