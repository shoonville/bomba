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
var soak_seconds: float = 0.0
var headless: bool = false
var rounds_left: int = 0

var _menu: Node
var _hud: Node
var _soak_elapsed: float = 0.0
var _quitting: bool = false
var _shot_timer: float = 0.0
var _shot_done: bool = false


func _ready() -> void:
	args = Cli.parse(OS.get_cmdline_user_args())
	headless = DisplayServer.get_name() == "headless"
	if args.has("log"):
		Log.level = int(args["log"])
	if args.has("seed"):
		Rng.set_match_seed(int(args["seed"]))
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

	Session.minigame_start_requested.connect(_on_minigame_start)
	Session.local_name = str(args.get("name", "Player %d" % (OS.get_process_id() % 1000)))

	if args.has("host"):
		_boot_host()
	elif args.has("join"):
		_boot_join()
	else:
		show_menu()


func _boot_host() -> void:
	var port := int(args.get("port", Tuning.int_value("net.default_port")))
	var max_players := Tuning.int_value("arena.max_players", 6)
	var err := Net.host(port, max_players)
	if err != OK:
		Log.error("game", "Could not host on port %d: %s" % [port, error_string(err)])
		_quit_if_headless(1)
		return
	Session.host_session(Session.local_name)
	if args.has("round_seconds"):
		Session.config.round_seconds = int(args["round_seconds"])
	var bots := int(args.get("bots", 0))
	var difficulty := str(args.get("bot_difficulty", Tuning.value("bots.default_difficulty", "normal")))
	for i in bots:
		Session.add_bot(difficulty)
	var expect := int(args.get("expect", 0))
	var minigame_id := str(args.get("minigame", "arena"))
	if args.has("start"):
		if expect > 0:
			Log.info("game", "Waiting for %d human players before starting %s" % [expect, minigame_id])
			Session.registry_changed.connect(func():
				# expect counts joining clients; the host's own seat is not one of them.
				if Session.human_count() - 1 >= expect and active_minigame == null:
					Session.start_minigame(minigame_id)
			)
		else:
			Session.start_minigame(minigame_id)
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
	Net.join_failed.connect(func(reason: String):
		Log.error("game", "Join failed: %s" % reason)
		_quit_if_headless(1)
	)
	if not headless:
		show_menu()


func show_menu() -> void:
	_clear_hud()
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
	if headless or not ResourceLoader.exists(MENU_SCENE):
		return
	_menu = load(MENU_SCENE).instantiate()
	ui_layer.add_child(_menu)


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
	var scene: PackedScene = load(manifest.scene_path)
	if scene == null:
		Log.error("game", "Minigame '%s' scene missing at %s" % [id, manifest.scene_path])
		return
	active_minigame = scene.instantiate() as Minigame
	if active_minigame == null:
		Log.error("game", "Minigame '%s' root is not a Minigame" % id)
		return
	active_minigame.name = "Minigame_" + id
	active_minigame.manifest = manifest
	world.add_child(active_minigame)
	active_minigame.finished.connect(_on_minigame_finished.bind(id))
	active_minigame.setup(players, seed_value, config)
	Events.minigame_started.emit(id)
	if not headless and ResourceLoader.exists(HUD_SCENE):
		_hud = load(HUD_SCENE).instantiate()
		ui_layer.add_child(_hud)
	if not headless and not args.has("screenshot"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Log.info("game", "Minigame %s started with %d players, seed %d" % [id, players.size(), seed_value])


func _on_minigame_finished(result: MinigameResult, id: String) -> void:
	Log.info("game", "Minigame %s finished: %s" % [id, result.summary()])
	Events.minigame_finished.emit(result)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_clear_hud()
	if Session.is_authority():
		Session.report_result(result)
	if not headless and ResourceLoader.exists(RESULTS_SCENE):
		var results: Node = load(RESULTS_SCENE).instantiate()
		ui_layer.add_child(results)
		if results.has_method("show_result"):
			results.show_result(result)
	rounds_left -= 1
	if soak_seconds > 0.0 and rounds_left <= 0:
		# Write the report while the minigame is still in the tree, then quit.
		_finish_soak()
		return
	if active_minigame != null and is_instance_valid(active_minigame):
		# finished is emitted from inside the tick loop; take the minigame out at the end of the
		# frame so the rest of the loop's handlers are not called on nodes outside the tree.
		var old := active_minigame
		(func():
			if is_instance_valid(old):
				if old.get_parent() == world:
					world.remove_child(old)
				old.queue_free()
		).call_deferred()
	active_minigame = null
	if rounds_left > 0 and Session.is_authority():
		Log.info("game", "Rematch in 1 s (%d rounds left)" % rounds_left)
		await get_tree().create_timer(1.0).timeout
		Session.start_minigame(id)


func _clear_hud() -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.queue_free()
	_hud = null


func _process(delta: float) -> void:
	if args.has("screenshot") and (active_minigame != null or args.has("screenshot_any")) and not _shot_done:
		_shot_timer += delta
		if _shot_timer >= float(args.get("screenshot_at", 3.0)):
			_shot_done = true
			_take_screenshot(str(args["screenshot"]))
	if soak_seconds > 0.0 and active_minigame != null:
		_soak_elapsed += delta
		if _soak_elapsed >= soak_seconds:
			Log.info("game", "Soak time reached (%.1fs)" % _soak_elapsed)
			_finish_soak()


func finish_soak() -> void:
	_finish_soak()


func _finish_soak() -> void:
	if _quitting:
		return
	_quitting = true
	soak_seconds = 0.0
	var recorder := get_node_or_null("/root/SoakRecorder")
	if recorder != null and recorder.has_method("write_report"):
		recorder.write_report()
	Log.flush()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)


func _take_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	Log.info("game", "Screenshot %s → %s (%dx%d)" % [error_string(err), path, img.get_width(), img.get_height()])
	if args.has("screenshot_quit"):
		Log.flush()
		get_tree().quit(0)


func _quit_if_headless(code: int) -> void:
	if headless:
		Log.flush()
		get_tree().quit(code)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Net.leave()
		Log.flush()
