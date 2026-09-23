extends Node
## Bootstrap and game flow. Autoload `Game`.
##
## Reads the command line, brings up hosting or joining, and moves between menu, minigame and
## results. The minigame SDK is the only thing it knows about a minigame.

const MENU_SCENE := "res://ui/menu/main_menu.tscn"
const RESULTS_SCENE := "res://ui/results/results.tscn"
const HUD_SCENE := "res://ui/hud/hud.tscn"

var args: Dictionary = {}
var world: Node3D
var ui_layer: CanvasLayer
var active_minigame: Minigame
var board: BoardDirector
var soak_seconds: float = 0.0
var headless: bool = false
var rounds_left: int = 0

var wipe: Wipe
var _menu: Node
var _hud: Node
var _pause: PauseMenu
var _soak_elapsed: float = 0.0
var _quitting: bool = false
var _shot_timer: float = 0.0
var _shot_done: bool = false
var _shot_armed: bool = false
var _shot_event_seen: int = 0
var _last_frame_ms: int = 0
var _hitch_ms: int = 150   # a frame over this is logged with what it did (--hitch_ms=N lowers it for a diagnosis)
var _perf_pipes_start: PackedInt64Array = PackedInt64Array()   # pipeline counts when --perf sampling began
var _last_vmem: int = 0
var _last_nodes: int = 0
var _last_resources: int = 0
var _last_pipes := PackedInt64Array([0, 0, 0, 0, 0])
var _held: Array[Resource] = []
var quality: AutoQuality
var _perf_gpu: PackedFloat32Array = []
var _perf_cpu: PackedFloat32Array = []
var _perf_frame: PackedFloat32Array = []
var _perf_process: PackedFloat32Array = []   # --perf: the main thread's process phase per frame, ms
var _perf_physics: PackedFloat32Array = []   # --perf: the frame's longest physics step, ms
const STRIDE := 6                             # --motion_log columns per frame
var _motion: PackedFloat64Array = []         # --motion_log: per frame t_us, camera x, camera z, tick, fraction, gap_ms


static func _mean(v: PackedFloat32Array) -> float:
	if v.is_empty():
		return 0.0
	var s := 0.0
	for x in v:
		s += x
	return s / v.size()


static func _p95(v: PackedFloat32Array) -> float:
	if v.is_empty():
		return 0.0
	var s := v.duplicate()
	s.sort()
	return s[int(0.95 * (s.size() - 1))]


static func _max(v: PackedFloat32Array) -> float:
	var m := 0.0
	for x in v:
		m = maxf(m, x)
	return m


static func _median(v: PackedFloat32Array) -> float:
	if v.is_empty():
		return 0.0
	var s := v.duplicate()
	s.sort()
	return s[s.size() / 2]


func _ready() -> void:
	args = Cli.parse(OS.get_cmdline_user_args())
	_hitch_ms = int(args.get("hitch_ms", 150))
	if args.has("screenshot_event"):
		Events.kill.connect(_arm_screenshot_on_kill)
		Events.round_ended.connect(_arm_screenshot_on_round_end)
	headless = DisplayServer.get_name() == "headless"
	if args.has("log"):
		Log.level = int(args["log"])
	if args.has("netfox_debug"):
		NetfoxLogger.log_level = NetfoxLogger.LOG_DEBUG
		NetfoxLogger.module_log_level.clear()
	if args.has("seed"):
		Rng.set_match_seed(int(args["seed"]))
	apply_render_scale()
	apply_window_settings()
	if not headless:
		# Per-frame render times for --perf and the hitch log (two GPU timestamps a frame).
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if args.has("soak"):
		soak_seconds = float(args["soak"])
	rounds_left = int(args.get("rounds", 1))
	if args.has("soak") or args.has("soak_ticks") or args.has("report"):
		var rec := SoakRecorder.new()
		rec.name = "SoakRecorder"
		rec.label = str(args.get("report", "soak_%d" % OS.get_process_id()))
		rec.soak_ticks = int(args.get("soak_ticks", 0))
		rec.report_dir = str(args.get("report_dir", ProjectSettings.globalize_path("res://reports")))
		get_tree().root.add_child.call_deferred(rec)
	Log.info("game", "BOMBA %s | Godot %s | args %s | headless=%s" % [
		ProjectSettings.get_setting("application/config/version"),
		Engine.get_version_info()["string"], JSON.stringify(args), headless])


func boot(root: Node) -> void:
	world = Node3D.new()
	world.name = "World"
	root.add_child(world)
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	root.add_child(ui_layer)
	if not headless:
		var wipe_layer := CanvasLayer.new()
		wipe_layer.name = "WipeLayer"
		wipe_layer.layer = 10
		root.add_child(wipe_layer)
		wipe = Wipe.new()
		wipe_layer.add_child(wipe)
	Net.left.connect(_on_net_left)

	Session.minigame_start_requested.connect(_on_minigame_start)
	Session.board_start_requested.connect(_on_board_start)
	Session.local_name = str(args.get("name", Settings.player_name if Settings.player_name != "" else "Player %d" % (OS.get_process_id() % 1000)))

	if not headless and not args.has("no_warmup"):
		# Load every scene, script and shader a match needs now, and keep them referenced so the
		# switch into a minigame finds them in the cache: the first load of the FPS script graph
		# cost 106 ms, the HUD 31 ms, on the switch frame on Sean's desktop.
		_preload_resources()
		# Create the GPU pipelines and the shadow atlas now, behind the boot colour, instead of
		# on the first frame of the first match (a 300–800 ms stall on Sean's desktop).
		var warm := PipelineWarmup.new()
		warm.name = "PipelineWarmup"
		world.add_child(warm)
		await warm.run(ui_layer)

	if args.has("host_online"):
		_boot_host_online()
	elif args.has("join_code"):
		_boot_join_code()
	elif args.has("host"):
		_boot_host()
	elif args.has("join"):
		_boot_join()
	else:
		show_menu()


func _boot_host_online() -> void:
	var err: Error = await Net.host_online(Tuning.int_value("arena.max_players", 6))
	if err != OK:
		_quit_if_headless(1)
		return
	_after_host_ready()


func _boot_join_code() -> void:
	var err: Error = await Net.join_code(str(args["join_code"]), args.has("relay"))
	if err != OK:
		_quit_if_headless(1)
		return
	Session.join_session(Session.local_name)
	if not headless:
		show_menu()


func _boot_host() -> void:
	var port := int(args.get("port", Tuning.int_value("net.default_port")))
	var max_players := Tuning.int_value("arena.max_players", 6)
	var err := Net.host(port, max_players)
	if err != OK:
		Log.error("game", "Could not host on port %d: %s" % [port, error_string(err)])
		_quit_if_headless(1)
		return
	_after_host_ready()


func _after_host_ready() -> void:
	Session.host_session(Session.local_name)
	if args.has("round_seconds"):
		Session.config.round_seconds = int(args["round_seconds"])
	var bots := int(args.get("bots", 0))
	var difficulty := str(args.get("bot_difficulty", Tuning.value("bots.default_difficulty", "normal")))
	for i in bots:
		Session.add_bot(difficulty)
	var expect := int(args.get("expect", 0))
	var minigame_id := str(args.get("minigame", "arena"))
	var start_match := func():
		if args.has("board"):
			Session.start_board(str(args.get("board_id", Tuning.value("board.default_board", "main"))))
		else:
			Session.start_minigame(minigame_id)
	if args.has("start"):
		if expect > 0:
			Log.info("game", "Waiting for %d human players before starting" % expect)
			Session.registry_changed.connect(func():
				# expect counts joining clients; the host's own seat is not one of them.
				if Session.human_count() - 1 >= expect and active_minigame == null and board == null:
					start_match.call()
			)
		else:
			start_match.call()
	elif not headless:
		show_menu()


func _boot_join() -> void:
	var target := str(args["join"])
	var address := target
	var port := Tuning.int_value("net.default_port")
	if target.contains(":"):
		address = target.get_slice(":", 0)
		port = int(target.get_slice(":", 1))
	var profile := str(args.get("conditioner", "lan"))
	var err := Net.join(address, port, profile)
	if err != OK:
		Log.error("game", "Could not join %s:%d: %s" % [address, port, error_string(err)])
		_quit_if_headless(1)
		return
	Session.join_session(Session.local_name)
	Session.rejected.connect(func(reason: String):
		Log.error("game", "No seat: %s" % reason)
		Net.leave()
		_quit_if_headless(2)
	)
	Net.join_failed.connect(func(reason: String):
		Log.error("game", "Join failed: %s" % reason)
		_quit_if_headless(1)
	)
	if not headless:
		show_menu()


## Run a callback under a wipe (host-side scene switches). Immediate when there is no screen.
func transition(callback: Callable) -> void:
	if wipe == null:
		callback.call()
		return
	wipe.run(callback)


func _on_net_left() -> void:
	if board != null:
		_end_board()
		_clear_hud()
		show_menu()
		if wipe != null:
			wipe.slam()
		return
	if active_minigame != null and is_instance_valid(active_minigame):
		Log.warn("game", "Connection lost during a minigame; back to the menu")
		if headless:
			# A headless client has no menu to go back to. Finish the soak (report written) or
			# quit; a soak client whose host finished first used to sit here for minutes.
			if soak_seconds > 0.0:
				_finish_soak()
			else:
				_quit_if_headless(2)
			return
		_close_pause()
		world.remove_child(active_minigame)
		active_minigame.queue_free()
		active_minigame = null
		Session.players.clear()
		show_menu()
		if wipe != null:
			wipe.slam()


func _unhandled_input(event: InputEvent) -> void:
	if headless:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F11:
		Settings.window_mode = "windowed" if Settings.window_mode == "fullscreen" else "fullscreen"
		Settings.save()
		apply_window_settings(true)
		return
	if active_minigame == null and board == null:
		return
	if event.is_action_pressed("pause"):
		if _pause == null:
			_open_pause()
		else:
			_close_pause()
		get_viewport().set_input_as_handled()


## The 3D render scale from settings (or --render_scale=N for the harness). Above 1 the frame
## is supersampled, which is what keeps the ink lines clean; 1 or below for weak GPUs.
func apply_render_scale() -> void:
	if headless:
		return
	var pinned := args.has("render_scale")
	var scale := clampf(float(args.get("render_scale", Settings.render_scale)), 0.5, 2.0)
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().scaling_3d_scale = scale
	if quality == null:
		quality = AutoQuality.new()
		quality.name = "AutoQuality"
		add_child(quality)
	quality.enabled = not pinned
	if args.has("gpu_budget_ms"):
		quality.budget_ms = float(args["gpu_budget_ms"])
	quality.set_cap(scale)
	Log.info("perf", "Render scale %.2f %s" % [scale, "(pinned)" if pinned else "cap, auto quality on (GPU budget %.1f ms)" % quality.budget_ms])


## Window mode and vsync from settings, or --window=fullscreen|windowed and --vsync=0|1 for the
## harness. At boot a window Godot's own --fullscreen already made is left alone unless the
## setting says fullscreen; from the panel (or F11) the setting always wins.
func apply_window_settings(from_panel: bool = false) -> void:
	if headless:
		return
	var mode := str(args.get("window", Settings.window_mode))
	var want := DisplayServer.WINDOW_MODE_WINDOWED
	if mode == "fullscreen":
		want = DisplayServer.WINDOW_MODE_FULLSCREEN
	elif mode == "exclusive":   # harness: exclusive fullscreen (Windows), no compositor between the game and the screen
		want = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	var have := DisplayServer.window_get_mode()
	if have != want and (from_panel or mode != "windowed" or args.has("window")):
		DisplayServer.window_set_mode(want)
	var vs := int(args.get("vsync", 1 if Settings.vsync else 0)) != 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vs else DisplayServer.VSYNC_DISABLED)
	Log.info("perf", "Window %s, vsync %s" % [mode, "on" if vs else "off"])


## --ads_progress=0..1 pins the scope-in animation for screenshots (presentation only).
func ads_progress_override(actual: float) -> float:
	if args.has("ads_progress"):
		return clampf(float(args["ads_progress"]), 0.0, 1.0)
	return actual


func is_paused() -> bool:
	return _pause != null and is_instance_valid(_pause)


func _open_pause() -> void:
	_pause = PauseMenu.new()
	ui_layer.add_child(_pause)
	_pause.resumed.connect(_close_pause)
	_pause.left.connect(func():
		_close_pause()
		transition(func():
			Net.leave()
			if active_minigame != null and is_instance_valid(active_minigame):
				world.remove_child(active_minigame)
				active_minigame.queue_free()
			active_minigame = null
			_end_board()
			Session.players.clear()
			show_menu()
		)
	)
	_set_local_input(false)


func _close_pause() -> void:
	if _pause != null and is_instance_valid(_pause):
		_pause.queue_free()
	_pause = null
	if active_minigame != null and board == null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_set_local_input(true)


func _set_local_input(on: bool) -> void:
	if active_minigame != null and active_minigame.has_method("get_local_player"):
		var lp = active_minigame.get_local_player()
		if lp != null and lp.input.brain == null:
			lp.input.enabled = on


func show_menu() -> void:
	_clear_hud()
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
	if headless or not ResourceLoader.exists(MENU_SCENE):
		return
	_menu = load(MENU_SCENE).instantiate()
	ui_layer.add_child(_menu)


func _on_board_start(board_id: String, seed_value: int, players_data: Array, _config: Dictionary) -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
	_end_board()
	board = BoardDirector.new()
	board.name = "BoardDirector"
	add_child(board)
	board.match_finished.connect(_on_board_finished)
	board.events_received.connect(_arm_screenshot_on)
	board.start(players_data, seed_value, board_id)
	if not headless and ResourceLoader.exists("res://ui/board/board_hud.tscn"):
		_hud = load("res://ui/board/board_hud.tscn").instantiate()
		ui_layer.add_child(_hud)
		if _hud.has_method("attach"):
			_hud.attach(board)
	if wipe != null:
		wipe.slam()


func _end_board() -> void:
	if board != null and is_instance_valid(board):
		remove_child(board)
		board.queue_free()
	board = null


func _on_board_finished(final_state: BoardState) -> void:
	Log.info("game", "Board match finished: %s" % ", ".join(final_state.standings().map(func(p): return "%s %d toys %d coins" % [p.display_name, p.toys, p.coins])))
	var result := MinigameResult.new()
	result.minigame_id = "board"
	for p in final_state.standings():
		result.add(p.peer_id, p.toys * 1000 + p.coins, p.display_name)
	result.finalize()
	for r in result.rankings:
		var p := final_state.player(int(r["peer_id"]))
		if p != null:
			r["label"] = "%d %s   ·   %d COINS" % [p.toys, "TOY" if p.toys == 1 else "TOYS", p.coins]
	_clear_hud()
	_end_board()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not headless and ResourceLoader.exists(RESULTS_SCENE):
		var results: Node = load(RESULTS_SCENE).instantiate()
		ui_layer.add_child(results)
		if results.has_method("show_result"):
			results.show_result(result)
		if wipe != null:
			wipe.slam()
	rounds_left -= 1
	if rounds_left > 0 and Session.is_authority():
		# Harness: --rounds=N plays N board matches back to back (the lobby → board → lobby loop).
		Log.info("game", "Board rematch in 1 s (%d left)" % rounds_left)
		await get_tree().create_timer(1.0).timeout
		Session.start_board(final_state.board_id)
		return
	if soak_seconds > 0.0:
		_finish_soak()


func _on_minigame_start(id: String, seed_value: int, players_data: Array, config: Dictionary) -> void:
	var manifest := MinigameRegistry.get_manifest(id)
	if manifest == null:
		Log.error("game", "Unknown minigame '%s'" % id)
		return
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
	for child in world.get_children():
		# Remove first: a queued-free node keeps its name until the end of the frame, and a
		# duplicate name would be auto-renamed differently on each peer, breaking RPC paths.
		world.remove_child(child)
		child.queue_free()
	var players: Array[MinigamePlayer] = []
	for d in players_data:
		var p := MinigamePlayer.from_dict(d)
		p.colour = Palette.player_colour(p.colour_index)
		players.append(p)
	var t0 := Time.get_ticks_usec()
	var scene: PackedScene = load(manifest.scene_path)
	if scene == null:
		Log.error("game", "Minigame '%s' scene missing at %s" % [id, manifest.scene_path])
		return
	var t1 := Time.get_ticks_usec()
	active_minigame = scene.instantiate() as Minigame
	if active_minigame == null:
		Log.error("game", "Minigame '%s' root is not a Minigame" % id)
		return
	active_minigame.name = "Minigame_" + id
	active_minigame.manifest = manifest
	world.add_child(active_minigame)
	active_minigame.finished.connect(_on_minigame_finished.bind(id))
	var t2 := Time.get_ticks_usec()
	active_minigame.setup(players, seed_value, config)
	var t3 := Time.get_ticks_usec()
	Events.minigame_started.emit(id)
	Audio.music("music_match")
	if wipe != null:
		wipe.slam()
	_clear_hud()
	if not headless and ResourceLoader.exists(HUD_SCENE):
		_hud = load(HUD_SCENE).instantiate()
		ui_layer.add_child(_hud)
	var t4 := Time.get_ticks_usec()
	if not headless and not args.has("screenshot"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Log.info("game", "Minigame %s started with %d players, seed %d" % [id, players.size(), seed_value])
	Log.info("perf", "Minigame build: scene load %d ms, instantiate+add %d ms, setup %d ms, hud %d ms" % [
		(t1 - t0) / 1000, (t2 - t1) / 1000, (t3 - t2) / 1000, (t4 - t3) / 1000])


func _on_minigame_finished(result: MinigameResult, id: String) -> void:
	Log.info("game", "Minigame %s finished: %s" % [id, result.summary()])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_close_pause()
	_clear_hud()
	if board != null and is_instance_valid(board):
		# Part of a board match: hand the ranking back to the board, no results screen.
		_retire_minigame()
		# HUD first: the director broadcasts the reward events synchronously from this emit.
		if not headless and ResourceLoader.exists("res://ui/board/board_hud.tscn"):
			_hud = load("res://ui/board/board_hud.tscn").instantiate()
			ui_layer.add_child(_hud)
			if _hud.has_method("attach"):
				_hud.attach(board)
		Events.minigame_finished.emit(result)
		if wipe != null:
			wipe.slam()
		return
	Events.minigame_finished.emit(result)
	if Session.is_authority():
		Session.report_result(result)
	if not headless and ResourceLoader.exists(RESULTS_SCENE):
		var results: Node = load(RESULTS_SCENE).instantiate()
		ui_layer.add_child(results)
		if results.has_method("show_result"):
			results.show_result(result)
		if wipe != null:
			wipe.slam()
	rounds_left -= 1
	if soak_seconds > 0.0 and rounds_left <= 0:
		# Write the report while the minigame is still in the tree, then quit.
		_finish_soak()
		return
	_retire_minigame()
	if rounds_left > 0 and Session.is_authority():
		Log.info("game", "Rematch in 1 s (%d rounds left)" % rounds_left)
		await get_tree().create_timer(1.0).timeout
		Session.start_minigame(id)


## Take the finished minigame down after a short grace so packets still in flight (one RTT of
## client inputs) find their nodes, and never from inside the tick loop.
func _retire_minigame() -> void:
	var old := active_minigame
	active_minigame = null
	if old == null or not is_instance_valid(old):
		return
	get_tree().create_timer(0.6).timeout.connect(func():
		if is_instance_valid(old):
			if old.get_parent() == world:
				world.remove_child(old)
			old.queue_free()
	)


func _clear_hud() -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.queue_free()
	_hud = null


func _process(delta: float) -> void:
	# Wall clock between frames: Godot caps the delta it hands _process at a few physics steps
	# (max_physics_steps_per_frame), so a 2 s freeze arrives here as ~0.13 s and would hide.
	var now := Time.get_ticks_msec()
	var gap := now - _last_frame_ms
	_last_frame_ms = now
	var vmem := 0 if headless else int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED))
	if gap > _hitch_ms and not headless and _last_frame_ms > 0:
		# A frame this long is a freeze the player felt. Name where we were and what that frame
		# did: GPU memory change (a jump is an allocation), script and physics time, nodes and
		# resources created, pipelines compiled by source ("draw" ones are compile stalls). On
		# Sean's desktop this told apart the 635 MB first-frame allocation (free), pipeline
		# creation (none, ubershaders) and the script loading and scene build that was the cost.
		var where := "menu"
		if active_minigame != null:
			where = "minigame:%s" % (active_minigame.manifest.id if active_minigame.manifest != null else "?")
		elif board != null:
			where = "board"
		if wipe != null and wipe.phase != "idle":
			where += " wipe:%s %.2f" % [wipe.phase, wipe.progress]
		var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var resources := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
		var pipes := _pipeline_counts()
		Log.info("perf", "Frame hitch %d ms (%s) vram %d MB (%+d MB) objects %d | process %.0f ms physics %.0f ms | netfox loop %.1f ms rollback %.1f ms (%d ticks) | nodes %d (%+d) resources %d (%+d) | pipelines canvas %+d mesh %+d surface %+d draw %+d spec %+d" % [
			gap, where, vmem / 1048576, (vmem - _last_vmem) / 1048576,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			NetworkPerformance.get_network_loop_duration_ms(), NetworkPerformance.get_rollback_loop_duration_ms(),
			NetworkPerformance.get_rollback_ticks(),
			nodes, nodes - _last_nodes, resources, resources - _last_resources,
			pipes[0] - _last_pipes[0], pipes[1] - _last_pipes[1], pipes[2] - _last_pipes[2],
			pipes[3] - _last_pipes[3], pipes[4] - _last_pipes[4]])
	_last_vmem = vmem
	_last_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_last_resources = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	if not headless:
		_last_pipes = _pipeline_counts()
	if args.has("open_pause") and active_minigame != null and _pause == null and not headless and _shot_timer > 1.5:
		_open_pause()
	if args.has("screenshot") and (active_minigame != null or board != null or args.has("screenshot_any")) and not _shot_done and (not args.has("screenshot_event") or _shot_armed):
		_shot_timer += delta
		if _shot_timer >= float(args.get("screenshot_at", 3.0)):
			_shot_done = true
			_take_screenshot(str(args["screenshot"]))
	if soak_seconds > 0.0 and (active_minigame != null or board != null):
		_soak_elapsed += delta
		if args.has("perf") and not headless and _soak_elapsed > 2.0:
			# --perf: sample the renderer's own CPU and GPU time per frame (the previous frame's)
			# and the wall-clock frame time, after a 2 s settle; summarised at soak end.
			var rid := get_viewport().get_viewport_rid()
			if _perf_gpu.is_empty():
				_perf_pipes_start = _pipeline_counts()
			_perf_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			_perf_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
			_perf_frame.append(float(gap))
			_perf_process.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			_perf_physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			if args.has("motion_log"):
				var cam := get_viewport().get_camera_3d()
				if cam != null:
					_motion.append_array(PackedFloat64Array([float(Time.get_ticks_usec()), cam.global_position.x, cam.global_position.z, float(NetworkTime.tick), Engine.get_physics_interpolation_fraction(), float(gap)]))
		if _soak_elapsed >= soak_seconds:
			Log.info("game", "Soak time reached (%.1fs)" % _soak_elapsed)
			_finish_soak()


## Load and hold the scenes and shaders every scene switch would otherwise load on its frame.
func _preload_resources() -> void:
	var t0 := Time.get_ticks_msec()
	var paths: Array[String] = [MENU_SCENE, HUD_SCENE, RESULTS_SCENE, "res://ui/board/board_hud.tscn",
		"res://fps/player/player.tscn", CelMaterial.SHADER_PATH, CelMaterial.VIEWMODEL_SHADER_PATH,
		PostStack.SHADER_PATH, "res://art/shaders/sky_clouds.gdshader", "res://art/shaders/swirl.gdshader"]
	for id in MinigameRegistry.ids():
		var m := MinigameRegistry.get_manifest(str(id))
		if m != null:
			paths.append(m.scene_path)
	for p in paths:
		if ResourceLoader.exists(p):
			var r := load(p)
			if r != null:
				_held.append(r)
	Log.info("perf", "Preloaded %d scenes and shaders in %d ms" % [_held.size(), Time.get_ticks_msec() - t0])


## Pipeline compilations so far by source (canvas, mesh load, surface, draw call, specialization):
## the "draw" ones are the stalls, a pipeline built on the frame that first needed it.
func _pipeline_counts() -> PackedInt64Array:
	return PackedInt64Array([
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION)])


func finish_soak() -> void:
	_finish_soak()


func _finish_soak() -> void:
	if _quitting:
		return
	_quitting = true
	if not headless:
		Log.info("perf", "FPS at soak end: %d (window %dx%d, render scale %.2f)" % [Engine.get_frames_per_second(),
			get_viewport().size.x, get_viewport().size.y, get_viewport().scaling_3d_scale])
		if not _perf_gpu.is_empty():
			var vp := get_viewport()
			Log.info("perf", "PERF window %dx%d scale %.2f (3D %dx%d) msaa %d shadow %d | frames %d | gpu ms mean %.2f p95 %.2f max %.2f | render cpu ms mean %.2f p95 %.2f | frame ms mean %.2f p95 %.2f" % [
				vp.size.x, vp.size.y, vp.scaling_3d_scale, int(vp.size.x * vp.scaling_3d_scale), int(vp.size.y * vp.scaling_3d_scale),
				int(vp.msaa_3d), int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 0)),
				_perf_gpu.size(), _mean(_perf_gpu), _p95(_perf_gpu), _max(_perf_gpu),
				_mean(_perf_cpu), _p95(_perf_cpu), _mean(_perf_frame), _p95(_perf_frame)])
			# Frame pacing: a frame over 1.5× the median is a skipped refresh the player feels;
			# count them, and the pipelines compiled while playing (a draw-time compile is a stall).
			var med := _median(_perf_frame)
			var over15 := 0
			var over2 := 0
			for f in _perf_frame:
				if f > med * 2.0:
					over2 += 1
				if f > med * 1.5:
					over15 += 1
			var pipes := _pipeline_counts()
			Log.info("perf", "PACING frames %d | median %.2f ms | over 1.5x median %d (%.1f %%) | over 2x %d | longest %.0f ms | pipelines compiled while playing: mesh %d surface %d draw %d spec %d" % [
				_perf_frame.size(), med, over15, 100.0 * over15 / maxf(1.0, _perf_frame.size()), over2, _max(_perf_frame),
				pipes[1] - _perf_pipes_start[1], pipes[2] - _perf_pipes_start[2], pipes[3] - _perf_pipes_start[3], pipes[4] - _perf_pipes_start[4]])
			Log.info("perf", "WORST PER SECOND (engine maxima) frame ms mean %.2f p95 %.2f max %.2f | physics step ms mean %.2f p95 %.2f max %.2f" % [
				_mean(_perf_process), _p95(_perf_process), _max(_perf_process),
				_mean(_perf_physics), _p95(_perf_physics), _max(_perf_physics)])
			if args.has("motion_log"):
				Log.info("perf", _motion_summary())
	soak_seconds = 0.0
	var recorder := get_node_or_null("/root/SoakRecorder")
	if recorder != null and recorder.has_method("write_report"):
		recorder.write_report()
	Log.flush()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)


## --screenshot_event=<board event kind>: start the screenshot timer when that board event is
## shown (e.g. "minigame" for the intro card, "reward" for the reward card) instead of at load;
## "out" arms when the local player is killed (FPS).
func _arm_screenshot_on_kill(_killer: int, victim: int, _weapon: String, _headshot: bool, _tick: int) -> void:
	if _shot_armed or str(args.get("screenshot_event", "")) != "out":
		return
	if victim == multiplayer.get_unique_id():
		_shot_armed = true
		_shot_timer = 0.0


func _arm_screenshot_on_round_end() -> void:
	if not _shot_armed and str(args.get("screenshot_event", "")) == "results":
		_shot_armed = true
		_shot_timer = 0.0


func _arm_screenshot_on(events: Array) -> void:
	if _shot_armed or not args.has("screenshot_event"):
		return
	var want := str(args["screenshot_event"])
	for e in events:
		var kind := str(e.get("kind", ""))
		var hit := kind == want
		if want == "reward":
			hit = kind == "coins" and e.has("rank")
		elif want == "myturn":
			hit = kind == "turn" and int(e.get("peer", 0)) == multiplayer.get_unique_id()
		elif want == "mychoose":
			hit = kind == "choose" and int(e.get("peer", 0)) == multiplayer.get_unique_id()
		if hit:
			# --screenshot_event_index=N arms on the Nth matching event (1 = the first).
			_shot_event_seen += 1
			if _shot_event_seen < int(args.get("screenshot_event_index", 1)):
				continue
			_shot_armed = true
			_shot_timer = 0.0
			return


func _take_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	Log.info("game", "Screenshot %s → %s (%dx%d)" % [error_string(err), path, img.get_width(), img.get_height()])
	if args.has("screenshot_quit"):
		Log.flush()
		get_tree().quit(0)


## Harness runs (headless, or windowed with --screenshot / --soak) quit on a boot failure. A
## windowed harness run that could not host used to sit at the menu forever, holding the shell
## that launched it (a --screenshot run stuck behind a port held by another instance).
func _quit_if_headless(code: int) -> void:
	if headless or args.has("screenshot") or args.has("soak") or args.has("soak_ticks"):
		Log.flush()
		get_tree().quit(code)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Net.leave()
		Log.flush()


## --motion_log (with --perf and --soak): how evenly the camera advances from frame to frame while
## it moves. With vsync every frame is shown one refresh apart, so a 60 Hz tick shown at a higher
## refresh should turn every frame into a step of the same size; a frame with no step while its
## neighbours step, or a double step, is judder the eye sees even when no frame is dropped. The
## step is compared raw, never divided by the wall clock between samples: that clock wobbles by
## ±1.6 ms with where the physics tick lands in the frame while the steps stay identical
## (measured 2026-09-22: 35.8 mm every frame at 165 Hz). Only steady straight motion is counted.
func _motion_summary() -> String:
	var n := _motion.size() / STRIDE
	if str(args.get("motion_log", "")) not in ["", "true"]:
		var f := FileAccess.open(str(args["motion_log"]), FileAccess.WRITE)
		if f != null:
			f.store_line("t_us,x,z,tick,fraction,gap_ms")
			for i in n:
				f.store_line("%.0f,%.5f,%.5f,%.0f,%.4f,%.0f" % [_motion[i * STRIDE], _motion[i * STRIDE + 1], _motion[i * STRIDE + 2], _motion[i * STRIDE + 3], _motion[i * STRIDE + 4], _motion[i * STRIDE + 5]])
			f.close()
	if n < 3:
		return "MOTION no samples"
	var steps := PackedFloat32Array()   # metres moved between consecutive frames
	var dirs: Array[Vector2] = []
	for i in range(1, n):
		var d := Vector2(_motion[i * STRIDE + 1] - _motion[(i - 1) * STRIDE + 1], _motion[i * STRIDE + 2] - _motion[(i - 1) * STRIDE + 2])
		steps.append(d.length())
		dirs.append(d.normalized() if d.length() > 1e-6 else Vector2.ZERO)
	var changes := PackedFloat32Array()
	var steady := 0
	var stalls := 0
	var doubles := 0
	for i in range(1, steps.size() - 1):
		var a := steps[i - 1]
		var b := steps[i]
		var c := steps[i + 1]
		if a < 0.003 or c < 0.003 or dirs[i - 1].dot(dirs[i + 1]) < 0.98:
			continue
		steady += 1
		var ref := (a + c) * 0.5
		changes.append(absf(b - ref) / ref * 100.0)
		if b < ref * 0.25:
			stalls += 1
		elif b > ref * 1.75:
			doubles += 1
	if steady == 0:
		return "MOTION frames %d, none moving steadily" % n
	return "MOTION frames %d steady %d | frame step vs its neighbours: mean %.1f %% p95 %.1f %% | stalled frames %d (%.2f %%) double steps %d (%.2f %%)" % [
		n, steady, _mean(changes), _p95(changes), stalls, 100.0 * stalls / steady, doubles, 100.0 * doubles / steady]
