class_name FpsMatch
extends Minigame
## Shared base for first-person free-for-all minigames: builds a gray-box map from a layout
## table, spawns players from the SDK's player list, drives bots through PlayerContext, runs a
## timed round with instant respawn and spawn protection, and returns a ranked result.
## A minigame folder subclasses this with a manifest (weapons, time limit) and, if it wants,
## overrides _layout(), _palette_map() and _score_for(). Nothing outside the folder changes.

const PLAYER_SCENE := preload("res://fps/player/player.tscn")


class MatchContext:
	extends PlayerContext
	var arena: FpsMatch

	func can_fire_at(tick: int) -> bool:
		return arena.round_start_tick < 0 or tick >= arena.round_start_tick

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

	func objective_position() -> Vector3:
		return arena.objective_position()

	func is_frozen(tick: int) -> bool:
		return arena._is_frozen(tick)

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
var _dead_since: Dictionary = {}  # peer → death tick, only used when _respawns() is false
var _ctx: MatchContext
var _pending_kills: Array = []
var _kill_sent: Dictionary = {}
var _shot_sent: Dictionary = {}
var _pending_shots: Array = []
var _finished_sent: bool = false
var _camera_rig: Node3D
var _spectator: SpectatorRig

# The round's end (Sean, 2026-09-22: "wait a couple seconds before it actually ends... a final
# kill cam like COD"): at the end tick everyone freezes, ROUND OVER and the winner show for
# OVER_HOLD, the final kill replays from the killer's eyes (KillCam) when one is in reach of the
# replay buffers, then the host sends the finish. The host schedules the finish by tick; every
# peer plays the presentation from the same over tick.
const OVER_HOLD := 2.0
const OVER_TAIL := 0.4
var _over_tick: int = -1          # replicated: the tick the round ended on
var _result_dict: Dictionary = {}
var _finish_at_tick: int = -1     # host: when to send the finish
var _final_sent: bool = false
var _over_since: float = -1.0     # wall clock, this peer
var _final_kill: Dictionary = {}  # the kill log's entry {killer, victim, weapon, headshot, tick}, or {}
var _killcam: KillCam
var _killcam_done: bool = false

@onready var players_root: Node3D = $Players
@onready var map_root: Node3D = $Map
@onready var effects_root: Node3D = $Effects


func _on_setup() -> void:
	arena_cfg = Tuning.table("arena")
	move_cfg = MovementConfig.from_dict(Tuning.table("movement"))
	var wt := Tuning.table("weapons")
	var ids: Array = []
	if manifest != null:
		for w in manifest.weapons:
			ids.append(str(w))
	weapon_defs = WeaponDef.load_ids(wt, ids) if not ids.is_empty() else WeaponDef.load_all(wt)
	swap_ticks = int(wt.get("swap_ticks", 20))
	lag_comp_ticks = int(round(Tuning.float_value("net.lag_comp_max_ms", 250.0) / 1000.0 * NetworkTime.tickrate))

	var t0 := Time.get_ticks_usec()
	layout = _layout()
	MapDressing.dress(layout, _palette_map())   # decor only: boxes, spawns and the bot graph untouched
	MapBuilder.build_boxes(map_root, layout, _palette_map())
	spawn_selector.configure(layout["spawns"], arena_cfg, move_cfg.eye_height)
	_ctx = MatchContext.new()
	_ctx.arena = self
	if is_authority() and multiplayer.multiplayer_peer is OfflineMultiplayerPeer and not NetworkTime.is_initial_sync_done():
		# Offline (harness) run: nothing started the clock, and the chunks below wait on it.
		NetworkTime.start()
	var t_map := Time.get_ticks_usec()

	# The simulation, all in this call and in this order: the players' bodies and brains, the tick
	# hooks and the round clock. Their look (figures, viewmodel, decor, sky) comes in
	# build_visuals(), in chunks on later frames under the wipe's held cover; the whole build in
	# one frame used to stall the wipe 90–200 ms. Only the look moves: a player spawned after a
	# tick loop drifted the determinism harness by 0.4 mm on one seat (2026-09-22).
	var sorted := players.duplicate()
	sorted.sort_custom(func(a: MinigamePlayer, b: MinigamePlayer): return a.peer_id < b.peer_id)
	for i in sorted.size():
		_spawn_player(sorted[i], i)
	NetworkTime.on_tick.connect(_on_tick)
	NetworkTime.after_tick_loop.connect(_after_tick_loop)
	Events.local_shot_fx.connect(_on_local_shot_fx)
	var t_players := Time.get_ticks_usec()
	if is_authority():
		var warm := int(float(arena_cfg.get("warmup_seconds", 3)) * NetworkTime.tickrate)
		var secs := int(config.get("round_seconds", 0))
		if secs <= 0 and manifest != null and manifest.time_limit_seconds > 0:
			secs = manifest.time_limit_seconds
		if secs <= 0:
			secs = int(arena_cfg.get("round_seconds", 180))
		var start := NetworkTime.tick + warm
		_rpc_round.rpc(start, start + secs * NetworkTime.tickrate)
	Log.info("arena", "Setup %s: %d players, %d boxes, %d spawns, weapons %s" % [manifest.id if manifest != null else "?", _players.size(), layout["boxes"].size(), layout["spawns"].size(), weapon_defs.map(func(d): return d.id)])
	Log.info("perf", "Match simulation built on frame %d: map %d ms | players %d ms" % [Engine.get_process_frames(), (t_map - t0) / 1000, (t_players - t_map) / 1000])


## The look, one chunk per rendered frame under the wipe's held cover (Game awaits this, then
## reveals): a figure per frame, the camera rig and viewmodel, the decor in quarters, the sky and
## sun last. Every chunk checks the match is still in the tree (a peer can leave mid-build).
func build_visuals() -> void:
	var times: Array = []
	var frames: Array = []
	var t := Time.get_ticks_usec()
	var sorted: Array = _players.values()
	sorted.sort_custom(func(a: Player, b: Player): return a.peer_id < b.peer_id)
	for p in sorted:
		await _next_frame()
		if not is_inside_tree():
			return
		_add_visual(p)
		frames.append(Engine.get_process_frames())
		times.append((Time.get_ticks_usec() - t) / 1000)
		t = Time.get_ticks_usec()
	await _next_frame()
	if not is_inside_tree():
		return
	_attach_camera()
	var t_cam := (Time.get_ticks_usec() - t) / 1000
	t = Time.get_ticks_usec()
	await _next_frame()
	if not is_inside_tree():
		return
	if _camera_rig != null and _camera_rig.has_method("add_viewmodel"):
		_camera_rig.add_viewmodel()
	var t_vm := (Time.get_ticks_usec() - t) / 1000
	t = Time.get_ticks_usec()
	var decor_count: int = layout.get("decor", []).size()
	var decor_times: Array = []
	for k in 4:
		await _next_frame()
		if not is_inside_tree():
			return
		MapBuilder.build_decor(map_root, layout, _palette_map(), decor_count * k / 4, decor_count * (k + 1) / 4)
		decor_times.append((Time.get_ticks_usec() - t) / 1000)
		t = Time.get_ticks_usec()
	await _next_frame()
	if not is_inside_tree():
		return
	_build_environment()
	var t_env := (Time.get_ticks_usec() - t) / 1000
	Log.info("perf", "Match look built over %d frames (figures on frames %s, last on %d): figures %s ms | camera %d ms | viewmodel %d ms | decor %s ms (%d pieces) | environment %d ms" % [
		sorted.size() + 7, str(frames), Engine.get_process_frames(), str(times), t_cam, t_vm, str(decor_times), decor_count, t_env])


## The next rendered frame, never this one: the start RPC can land before this frame's
## process_frame signal, and one await would then resume in the same frame it was issued from
## (measured: the first figure landing on the setup frame, 55 ms together).
func _next_frame() -> void:
	var f := Engine.get_process_frames()
	await get_tree().process_frame
	if Engine.get_process_frames() == f:
		await get_tree().process_frame


## The figure and name tag other players see (the look; the body was spawned in setup).
func _add_visual(p: Player) -> void:
	var vis := PlayerVisual.new()
	p.visual.add_child(vis)
	vis.setup(p, move_cfg)


## Hooks for minigame folders.
func _layout() -> Dictionary:
	return GrayboxLayout.build()


func _palette_map() -> String:
	return "arena"


func _score_for(pl: Player) -> int:
	return kills_for(pl.peer_id)


## Kills and deaths as the kill feed saw them (one message per life). Scoring and the HUD read
## the log, which is identical on every peer; the body's counters are kept in step with it (they
## were rollback state until 2026-09-22, and a partial resimulation of a kill tick lost them).
func kills_for(peer: int) -> int:
	var n := 0
	for k in kill_log:
		if int(k["killer"]) == peer and int(k["victim"]) != peer:
			n += 1
	return n


func deaths_for(peer: int) -> int:
	var n := 0
	for k in kill_log:
		if int(k["victim"]) == peer:
			n += 1
	return n


## What the results screen prints for this player instead of the score; "" prints the score.
func _score_label(_pl: Player) -> String:
	return ""


## False for one-life minigames: the dead stay down and the round ends when one player is left.
func _respawns() -> bool:
	return true


## Text the HUD puts in the centre for the local player instead of its own "DOWN"; "" for none.
func centre_text() -> String:
	return ""


## Lines the HUD prints at the top centre, each {text, colour, size}; [] for none.
func hud_status() -> Array:
	return []


## The big number top-right and this player's scoreboard cell; the column's header.
func hud_score(pl: Player) -> String:
	return "%d" % kills_for(pl.peer_id)


func hud_score_header() -> String:
	return "K"


## The rank score, for the scoreboard's order.
func score_value(pl: Player) -> int:
	return _score_for(pl)


## Where the bots go when nobody is in sight; INF for no objective.
func objective_position() -> Vector3:
	return Vector3.INF


func warmup_seconds_left() -> float:
	if not in_warmup():
		return 0.0
	return NetworkTime.seconds_between(NetworkTime.tick, round_start_tick)


## Who an eliminated local player watches; "" when not spectating.
func spectating_name() -> String:
	return _spectator.target_name() if _spectator != null and is_instance_valid(_spectator) else ""


func _next_living(current: Player, step: int) -> Player:
	var living: Array = []
	for id in _players.keys():
		var pl: Player = _players[id]
		if pl.is_alive() and not pl.is_local():
			living.append(pl)
	if living.is_empty():
		return null
	living.sort_custom(func(a, b): return a.peer_id < b.peer_id)
	var i := living.find(current)
	if i < 0:
		return living[0]
	return living[posmod(i + step, living.size())]


## Eliminated in a one-life round: hand the view to a chase camera behind a living player.
func _update_spectator() -> void:
	if _respawns() or Game.headless or _camera_rig == null:
		return
	var local := get_local_player()
	if local == null or local.is_alive():
		return
	if _finished_sent:
		return
	if _spectator == null or not is_instance_valid(_spectator):
		var first := _next_living(null, 1)
		if first == null:
			return
		_spectator = SpectatorRig.new()
		_spectator.name = "Spectator"
		add_child(_spectator)
		_spectator.setup(_next_living, first, _ctx.world_mask())
		Log.info("arena", "Spectating %s" % first.display_name)
	if Input.is_action_just_pressed("fire") and not Game.is_paused():
		_spectator.cycle(1)
	for p in _players.values():
		var pl := p as Player
		for child in pl.visual.get_children():
			if child is PlayerVisual:
				child.hide_tag = pl == _spectator.target


func alive_count() -> int:
	var n := 0
	for p in _players.values():
		if (p as Player).is_alive():
			n += 1
	return n


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://art/shaders/sky_clouds.gdshader")
	sky_mat.set_shader_parameter("sky_top", Palette.map_colour(_palette_map(), "sky_top"))
	sky_mat.set_shader_parameter("sky_horizon", Palette.map_colour(_palette_map(), "sky_bottom"))
	sky_mat.set_shader_parameter("cloud_lit", Palette.map_colour(_palette_map(), "cloud_lit"))
	sky_mat.set_shader_parameter("cloud_shadow", Palette.map_colour(_palette_map(), "cloud_shadow"))
	sky_mat.set_shader_parameter("ink", Palette.map_colour(_palette_map(), "line"))
	sky_mat.set_shader_parameter("cloud_coverage", Tuning.float_value("palette.maps.%s.cloud_coverage" % _palette_map(), 0.44))
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Palette.map_colour(_palette_map(), "counter")
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
	if not mp.is_bot and mp.peer_id == local_peer_id() and Game.args.has("spawn_index"):
		sp = spawns[clampi(int(Game.args["spawn_index"]), 0, spawns.size() - 1)]   # harness: a chosen vantage for a frame
	p.position = sp["pos"]
	p.yaw = float(sp["yaw"])
	p.rotation = Vector3(0.0, float(sp["yaw"]), 0.0)
	players_root.add_child(p)
	p.configure(mp, _ctx, move_cfg, weapon_defs, swap_ticks, int(arena_cfg.get("health", 100)))
	p.input.set_look(float(sp["yaw"]), 0.0)
	_players[mp.peer_id] = p
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
		# A layout may carry its own vantage ("showcase": {pos, look}); the default suits the
		# 48 × 40 m arena and sits outside a smaller map's walls.
		var show: Dictionary = layout.get("showcase", {})
		cam.global_position = show.get("pos", Vector3(-14.0, 11.0, 24.0))
		cam.look_at(show.get("look", Vector3(1.0, 2.5, -2.0)), Vector3.UP)
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


var _figure_test: Array = []


## --figure_test: three figures in front of the showcase camera (walking, aiming, down) so the
## humanoid can be judged from a screenshot without hunting bots.
func _update_figure_test(delta: float) -> void:
	if not Game.args.has("figure_test") or Game.headless:
		return
	if _figure_test.is_empty():
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		# Park the showcase camera 4.5 m from three figures on the south spawn lane.
		var base := Vector3(14.0, 0.0, 2.5)
		cam.global_position = base + Vector3(0.0, 1.7, 4.6)
		cam.look_at(base + Vector3(0.0, 1.0, 0.0), Vector3.UP)
		for i in 3:
			var f := Figure.new()
			add_child(f)
			f.build(Palette.player_colour(i), _palette_map(), 1.62, i == 1)
			f.global_position = base + Vector3((float(i) - 1.0) * 1.7, 0.0, 0.0)
			f.rotation.y = PI if i != 2 else PI * 0.5   # face the camera (+Z), the third side-on
			_figure_test.append(f)
	(_figure_test[0] as Figure).animate(4.0, true, 0.0, true, delta)
	(_figure_test[1] as Figure).animate(0.0, true, 0.1, true, delta)
	(_figure_test[2] as Figure).animate(0.0, true, 0.0, false, delta)


func _process(delta: float) -> void:
	_update_round_over(delta)
	_update_spectator()
	_update_figure_test(delta)
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
		if p == shooter or not (p as Player).is_alive():
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
	if not _respawns():
		# The body stays down, so this fires every tick from now on; count it at its death tick only.
		var since: int = _dead_since.get(victim.peer_id, -1)
		if since >= 0 and since < tick:
			return
		_dead_since[victim.peer_id] = tick
	var killer_id := victim.last_hit_by
	var info := victim.last_hit_info
	var life := victim.respawn_count  # before the respawn below bumps it
	if _respawns():
		var enemies := []
		for p in _players.values():
			if p != victim and (p as Player).is_alive():
				enemies.append((p as Player).eye_position())
		var sp := spawn_selector.pick(enemies, get_world_3d().direct_space_state, tick,
			Rng.tick_stream("spawn", tick, victim.peer_id))
		victim.respawn_at(sp["pos"], sp["yaw"], tick, int(arena_cfg.get("spawn_protection_ticks", 90)))
	# One kill message per life: a rollback can report the same death again a tick later (the
	# victim's tick runs after the shooter's), which doubled kills in the feed and in SNIPERS.
	var key := "%d_%d" % [victim.peer_id, life]
	if not _kill_sent.has(key):
		_kill_sent[key] = true
		# The counters are plain, not rollback state: a partial resimulation of this tick (the shooter
		# re-run because its fire action marks it mutated, the victim not) re-recorded both from their
		# pre-death states and lost the kill. Counted once per life: here on the host, in _rpc_kill on
		# the clients, so every peer's counters match the feed.
		victim.deaths += 1
		if killer_id != 0 and killer_id != victim.peer_id and _players.has(killer_id):
			(_players[killer_id] as Player).kills += 1
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


func _exit_tree() -> void:
	if Events.local_shot_fx.is_connected(_on_local_shot_fx):
		Events.local_shot_fx.disconnect(_on_local_shot_fx)
	if NetworkTime.on_tick.is_connected(_on_tick):
		NetworkTime.on_tick.disconnect(_on_tick)
	if NetworkTime.after_tick_loop.is_connected(_after_tick_loop):
		NetworkTime.after_tick_loop.disconnect(_after_tick_loop)


func _on_tick(_delta: float, tick: int) -> void:
	if not is_inside_tree() or not is_authority():
		return
	if _finished_sent:
		if _finish_at_tick >= 0 and tick >= _finish_at_tick and not _final_sent:
			_final_sent = true
			_rpc_finish.rpc(_result_dict)
		return
	if round_end_tick > 0 and tick >= round_end_tick:
		_finish_round()
	elif not _respawns() and round_start_tick >= 0 and tick > round_start_tick and _players.size() > 1 \
			and alive_count() <= 1 and not _deaths_pending():
		Log.info("arena", "Last one standing at tick %d" % tick)
		_finish_round()


## A hit that drops a player to 0 lands in the shooter's tick; the victim's own tick (where the
## death is counted and the kill queued) can be one loop later. Do not end a round in between.
func _deaths_pending() -> bool:
	for p in _players.values():
		var pl := p as Player
		if not pl.is_alive() and not _dead_since.has(pl.peer_id):
			return true
	return false


func _flush_kills() -> void:
	for k in _pending_kills:
		_rpc_kill.rpc(k[0], k[1], k[2], k[3], k[4])
	_pending_kills.clear()


func _after_tick_loop() -> void:
	if not is_inside_tree() or not is_authority():
		return
	_flush_kills()
	for s in _pending_shots:
		_rpc_shot_fx.rpc(s[0], s[1], s[2], s[3], s[4])
		_apply_shot_fx(s[0], s[1], s[2], s[3], s[4])
	_pending_shots.clear()


func _finish_round() -> void:
	_finished_sent = true
	_flush_kills()  # a kill on the final tick must be in the log before scoring reads it
	for p in _players.values():
		var pl := p as Player
		if pl.kills != kills_for(pl.peer_id) or pl.deaths != deaths_for(pl.peer_id):
			Log.warn("arena", "%s: state says %d kills %d deaths, the kill log says %d and %d" % [pl.display_name, pl.kills, pl.deaths, kills_for(pl.peer_id), deaths_for(pl.peer_id)])
	var result := MinigameResult.new()
	for p in _players.values():
		var pl := p as Player
		result.add(pl.peer_id, _score_for(pl), pl.display_name, _score_label(pl))
	result.finalize()
	_result_dict = result.to_dict()
	# The hold before the finish: none in a headless run (the harness), else ROUND OVER and, when a
	# kill is within the replay buffers, the kill cam.
	var hold := 0.0
	if not Game.headless:
		hold = OVER_HOLD + OVER_TAIL + (KillCam.SECONDS if not _final_kill_candidate().is_empty() else 0.0)
	_finish_at_tick = NetworkTime.tick + int(hold * NetworkTime.tickrate)
	_rpc_round_over.rpc(_result_dict, NetworkTime.tick)


## The last kill of the log when the replay buffers still hold its lead-up; {} otherwise.
func _final_kill_candidate() -> Dictionary:
	if kill_log.is_empty():
		return {}
	var k: Dictionary = kill_log.back()
	var kill_tick := int(k["tick"])
	if NetworkTime.tick - kill_tick > Player.REPLAY_TICKS - KillCam.BEFORE_TICKS - 20:
		return {}
	var killer := int(k["killer"])
	var victim := int(k["victim"])
	if get_player(killer) == null or get_player(victim) == null or killer == victim:
		return {}
	return k


func _is_frozen(tick: int) -> bool:
	return _over_tick >= 0 and tick >= _over_tick


## The HUD's centre during the end: {phase: "over"|"killcam", title, subtitle}; {} in play.
func overlay_state() -> Dictionary:
	if _over_since < 0.0:
		return {}
	if _killcam != null and is_instance_valid(_killcam):
		var k := _final_kill
		return {"phase": "killcam", "title": "FINAL KILL",
			"subtitle": "%s  ▸  %s%s" % [_name_of(int(k["killer"])), _name_of(int(k["victim"])), "   ·   HEADSHOT" if bool(k["headshot"]) else ""]}
	var winner := ""
	var rankings: Array = _result_dict.get("rankings", [])
	if not rankings.is_empty():
		winner = str(rankings[0].get("display_name", ""))
	return {"phase": "over", "title": "ROUND OVER", "subtitle": ("WINNER   " + winner) if winner != "" else ""}


func _update_round_over(_delta: float) -> void:
	if _over_since < 0.0 or Game.headless:
		return
	var t := Time.get_ticks_msec() / 1000.0 - _over_since
	if _killcam == null and not _killcam_done and t >= OVER_HOLD and not _final_kill.is_empty():
		_start_killcam()
	if _killcam != null and is_instance_valid(_killcam) and _killcam.finished:
		_end_killcam()


func _start_killcam() -> void:
	var killer := get_player(int(_final_kill["killer"]))
	var victim := get_player(int(_final_kill["victim"]))
	if killer == null or victim == null:
		_killcam_done = true
		return
	_killcam = KillCam.new()
	_killcam.name = "KillCam"
	add_child(_killcam)
	_killcam.setup(self, killer, victim, int(_final_kill["tick"]), str(_final_kill["weapon"]), bool(_final_kill["headshot"]), move_cfg.eye_height)


func _end_killcam() -> void:
	_killcam_done = true
	if _killcam != null and is_instance_valid(_killcam):
		_killcam.end()
		_killcam.queue_free()
	_killcam = null
	# The view goes back to whoever had it: the spectator rig, else the player's own camera.
	if _spectator != null and is_instance_valid(_spectator) and _spectator.camera != null:
		_spectator.camera.current = true
	elif _camera_rig != null and is_instance_valid(_camera_rig) and _camera_rig.camera != null:
		_camera_rig.camera.current = true


@rpc("authority", "call_local", "reliable")
func _rpc_round_over(result: Dictionary, over_tick: int) -> void:
	_over_tick = over_tick
	_result_dict = result
	_final_kill = _final_kill_candidate()
	_over_since = Time.get_ticks_msec() / 1000.0
	Events.round_ended.emit()


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
	if not is_authority():
		# The host counted at the death tick; clients keep the same counters from the message.
		var v := get_player(victim_id)
		if v != null:
			v.deaths += 1
		var k := get_player(killer_id)
		if k != null and killer_id != victim_id:
			k.kills += 1
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
	if _over_since < 0.0:
		Events.round_ended.emit()   # a finish with no round-over first (never, but the HUD would wait)
	if _killcam != null and is_instance_valid(_killcam):
		_end_killcam()
	finish(MinigameResult.from_dict(data))


func _name_of(id: int) -> String:
	var p := get_player(id)
	if p == null:
		return "world" if id == 0 else "#%d" % id
	return p.display_name
