class_name BoardView
extends Node3D
## The board in 3D (BOARDPLAN.md §5): six-sided floating tiles by space type, planks between
## them, a ring on the goal, pawns hopping space to space, a camera that follows the active
## pawn, floating ticket/item labels. Plays the director's event queue in order.

var director: BoardDirector
var tiles: Dictionary = {}
var pawns: Dictionary = {}
var goal_ring: MeshInstance3D
var goal_beacon: Node3D
var active_pulse: MeshInstance3D
var _spark: MeshInstance3D
var _islands: Array = []   # asteroids: [{node, base_y, phase, spin}]
var _ufo: Node3D
var _planet: Node3D
var _astronaut: Figure
var _dressing: BoardDressing
var _craters: Array = []       # Vector3(x, z, r), for the dressing to keep clear of
var _prop_spots: Array = []    # Vector2 of the five landmark props
var _slab: MoonSlab            # the moon chunk the board stands on (the board file's, or an ellipse round the tiles)
var _district_f: float = 0.0   # how far out the walkways reach, as a fraction of the way to the rim
var _prop_yaws: Array = []     # a heading per landmark prop
var _moon_density: float = 1.0   # slab area over the 65-space board's: feature counts keep their density
var _bounds_centre: Vector3 = Vector3.ZERO
var _bounds_radius: float = 20.0
var _map_blend: float = 0.0
var _anim_t: float = 0.0
var camera: Camera3D
var _env_node: WorldEnvironment
var _env: Environment
var markers: Array = []
var _marker_t: float = 0.0
var _shuttle: Node3D               # the rocket on its pad: the board's one rocket (Sean's drawing, 2026-09-24)
var _shuttle_home: Vector3 = Vector3.ZERO
var _shuttle_flame: MeshInstance3D
var _shuttle_follow: bool = false  # the camera rides along during a flight
var _cam_zoom: float = 1.0         # the camera's distance, scaled: pulled back while the rocket flies
var _free: bool = false            # the free camera (Sean, 2026-09-24: R on your turn, WASD moves it)
var _free_look: Vector3 = Vector3.ZERO
var _free_test_t: float = 0.0      # --free_cam_test: on at 1.5 s, panning north-east from 2 s
var _shuttle_tween: Tween
var _cam_target: Vector3 = Vector3.ZERO
var _cam_look: Vector3 = Vector3.ZERO
var _cam_yaw: float = 0.0          # one heading for the whole board: south of the pawn, looking north (Sean, 2026-09-23)
var _cam_yaw_target: float = 0.0
var _cam_fast: bool = false        # tighter follow while a pawn is moving
var _queue: Array = []
var _playing: bool = false
var _goal_spot: String = ""     # the spot the ring and the lit machine show
var _hop: float = 0.32
var _fork_focus: Array = []
# The laser gun: aim mode (the local player's pawn turns with the mouse and a beam shows the
# reach), the shot flash everyone sees, and the blood it leaves on the board.
var _aiming: bool = false
var _aim: float = 0.0
var _aim_len: float = 9.0
var _aim_peer: int = 0
var _aim_kind: String = "laser"      # what the line is for: the laser's beam or the claw's reach
var _beam: MeshInstance3D
var _beam_dot: MeshInstance3D
var _throw: bool = false             # aiming the bomb: the range ring and the landing reticle
var _throw_range: float = 9.0
var _throw_radius: float = 3.0
var _throw_point: Vector3 = Vector3.ZERO
var _range_ring: MeshInstance3D
var _reticle: Node3D
var _swirl_vp: SubViewport         # the menu's swirl, rendered small for the portals' faces
var _blood_root: Node3D
var _blood_drawn: Dictionary = {}   # blood serial → true
var _blood_mat: Material
var built: bool = false            # the look is complete: build_visuals() ran to its end
var _state_shown: bool = false     # the first state has been applied (goal, focus, blood, shields)
var _shadow: Color
var _moon_rng := RandomNumberGenerator.new()   # one seeded stream across the moon's three chunks


## Dormant through a minigame (2026-09-22): hidden, not processing (its tweens pause with it),
## the camera released and the environment withdrawn, everything else kept, so the return to
## the board costs nothing instead of the 120–150 ms rebuild of 2800 nodes that stalled the wipe
## every round. A hidden WorldEnvironment still applies its environment, and the minigame brings
## its own, so the environment comes off the node while asleep and back on at wake.
func sleep() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	if camera != null:
		camera.current = false
	if _env_node != null:
		_env_node.environment = null


func wake() -> void:
	if _env_node != null and _env != null:
		_env_node.environment = _env
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	if camera != null and not Game.headless:
		camera.current = true


func is_asleep() -> bool:
	return not visible


func setup(p_director: BoardDirector) -> void:
	director = p_director
	_hop = float(director.cfg.get("hop_seconds", 0.32))
	_shadow = Palette.map_colour("board", "shadow_tint")
	director.state_changed.connect(_on_state)
	director.events_received.connect(_on_events)
	_blood_root = Node3D.new()
	_blood_root.name = "Blood"
	add_child(_blood_root)
	_blood_mat = CelMaterial.for_colour(Color.from_hsv(355.0 / 360.0, 0.85, 0.42), _shadow)
	_build_beam()
	camera = Camera3D.new()
	camera.name = "BoardCamera"
	camera.fov = 52.0
	add_child(camera)
	if not Game.headless:
		camera.current = true
		var post := PostStack.new()
		camera.add_child(post)
		post.setup("board")
	_cam_look = Vector3.ZERO
	_cam_target = Vector3.ZERO
	camera.global_position = Vector3(0, 6.2, 6.8)
	camera.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	# The look (sky, tiles, moon, space, dressing, pawns) comes from build_visuals(), one chunk
	# per frame under the held wipe; a state or events that land before it is done wait for it.


## The look, one chunk per rendered frame under the wipe's held cover (Game awaits this, then
## reveals): the sky and sun, the tiles and planks, the markers and the goal, the moon in three
## parts (slab and posts, craters and boulders, the five props), the asteroids, the horizon and
## the UFO, the dressing in four parts, then a pawn per frame. The first build of a match used to
## run whole on the start RPC's frame: 176 ms at 1080p on Sean's desktop (2026-09-23), 2795
## nodes. Every chunk checks the view is still in the tree (a peer can leave mid-build). The
## state, and any events that landed meanwhile, are applied at the end.
func build_visuals() -> void:
	var steps: Array = [
		["environment", _build_environment],
		["tiles", _build_tiles],
		["markers", _build_markers],
		["moon", _build_moon_chunk],
		["craters", _build_moon_craters],
		["props", _build_moon_props.bind(0, 4)],
		["crew", _build_moon_props.bind(4, 5)],   # the first Figure of the match: a frame of its own
		["asteroids", _build_asteroids],
		["horizon", _build_horizon],
	]
	var f0 := Engine.get_process_frames()
	var times := PackedStringArray()
	for step in steps:
		await _next_frame()
		if not is_inside_tree():
			return
		var t := Time.get_ticks_usec()
		(step[1] as Callable).call()
		times.append("%s %d@%d" % [step[0], (Time.get_ticks_usec() - t) / 1000, Engine.get_process_frames()])
	# The detail pass: everything a moon base has around a walkway (board/board_dressing.gd),
	# four parts on four frames.
	await _next_frame()
	if not is_inside_tree():
		return
	_dressing = BoardDressing.new()
	_dressing.name = "Dressing"
	add_child(_dressing)
	# The landmark props as (x, z, radius) for the dressing to keep clear of.
	var landmarks: Array = []
	var prop_r: Array = [4.6, 2.6, 2.2, 2.0, 1.6]
	for i in _prop_spots.size():
		landmarks.append(Vector3(_prop_spots[i].x, _prop_spots[i].y, float(prop_r[mini(i, prop_r.size() - 1)])))
	var dressing_ms: PackedInt32Array = await _dressing.build(self, director.graph, _slab, MOON_TOP, _craters, landmarks, _shadow)
	if not is_inside_tree():
		return
	var placed := []
	for k in _dressing.counts:
		placed.append("%s ×%d" % [k, int(_dressing.counts[k])])
	Log.info("board", "Dressing built: %s" % ", ".join(placed))
	times.append("dressing %s@%d" % ["/".join(Array(dressing_ms).map(func(v): return str(v))), Engine.get_process_frames()])
	# A pawn per frame (a Figure each), before the state is shown.
	var pawn_ms := PackedStringArray()
	if director.state != null:
		for p in director.state.players:
			await _next_frame()
			if not is_inside_tree():
				return
			var t := Time.get_ticks_usec()
			_ensure_pawn(p)
			pawn_ms.append(str((Time.get_ticks_usec() - t) / 1000))
	built = true
	Log.info("perf", "Board look built over %d frames (ms@frame): %s | pawns %s ms, last on %d" % [
		Engine.get_process_frames() - f0, " | ".join(times), "/".join(pawn_ms), Engine.get_process_frames()])
	if director.state != null:
		_on_state(director.state)
	if not _playing and not _queue.is_empty():
		_play_next()


## The next rendered frame, never this one: the start RPC can land before this frame's
## process_frame signal, and one await would then resume in the frame it was issued from.
## Waits on the main loop, not the tree, so a view pulled from the tree mid-build still wakes to
## find that out and stop.
func _next_frame() -> void:
	var f := Engine.get_process_frames()
	await (Engine.get_main_loop() as SceneTree).process_frame
	if Engine.get_process_frames() == f:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://art/shaders/sky_clouds.gdshader")
	mat.set_shader_parameter("sky_top", Palette.map_colour("board", "sky_top"))
	mat.set_shader_parameter("sky_horizon", Palette.map_colour("board", "sky_bottom"))
	mat.set_shader_parameter("cloud_lit", Palette.map_colour("board", "cloud_lit"))
	mat.set_shader_parameter("cloud_shadow", Palette.map_colour("board", "cloud_shadow"))
	mat.set_shader_parameter("ink", Palette.map_colour("board", "line"))
	mat.set_shader_parameter("cloud_coverage", 0.36)
	sky.sky_material = mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Palette.map_colour("board", "counter")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env_node = we
	_env = env
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	sun.light_angular_distance = 0.0
	sun.rotation_degrees = Vector3(-55.0, 28.0, 0.0)
	add_child(sun)


## Hover on LEFT / RIGHT: every tile of the move down that branch lifts and glows, the landing
## tile in the accent colour, until the pointer leaves.
var _highlighted: Array = []   # [{tile, mat}]


func highlight_path(ids: Array) -> void:
	clear_highlight()
	var shadow := Palette.map_colour("board", "shadow_tint")
	for k in ids.size():
		var sid := str(ids[k])
		if not tiles.has(sid):
			continue
		var tile: MeshInstance3D = tiles[sid]
		var base: Color = _tone_for(director.graph.get_space(sid).type)
		var landing := k == ids.size() - 1
		# Landing tile in glowing cream: distinct on every tile colour (the accent is ticket yellow).
		var mat := CelMaterial.for_colour(Palette.hud_colour("paper") if landing else base.lightened(0.3), shadow, 1.4 if landing else 0.9)
		_highlighted.append({"tile": tile, "mat": tile.material_override})
		tile.material_override = mat
		tile.position.y += 0.12 if landing else 0.07
	Log.debug("board", "Hover: path %s glows" % str(ids))


func highlight_space(sid: String) -> void:
	highlight_path([sid])


func clear_highlight() -> void:
	for h in _highlighted:
		var tile: MeshInstance3D = h["tile"]
		if is_instance_valid(tile):
			tile.material_override = h["mat"]
			tile.position.y = director.space_position(tile.get_meta("space_id", "")).y - 0.21 if tile.has_meta("space_id") else tile.position.y
	_highlighted.clear()


## The special spaces' emblems, painted on the tile (Sean, 2026-09-24: "the events on the spots
## (item, tickets, damage) they should be painted on the tile"): flat pieces a hair above the
## face, children of the tile so the fork hover lift carries them, still. Two ticket stubs
## fanned for TICKETS, a paper star for an item (the "?" bag was ugly, his word), an ink mine
## on a paper disc for damage, a paper med bag with a green cross for the health spot; the safe
## spot keeps its dome and the start its flag.
func _build_marker(space: BoardGraph.Space, shadow: Color) -> void:
	var tile: Node3D = tiles.get(space.id, null)
	if tile == null:
		return
	var ink := Palette.map_colour("board", "line")
	var ink_mat := CelMaterial.for_colour(Color.from_hsv(ink.h, 0.45, 0.24), shadow)
	var paper_mat := CelMaterial.for_colour(Palette.hud_colour("paper"), shadow)
	var root := Node3D.new()
	root.position = Vector3(0, 0.21, 0)   # the tile's face
	var y := 0.052                        # the paint, over the dressing's inset hex
	match space.type:
		"ticket":
			# A Gundam-style head painted on the currency spot (Sean, 2026-09-24: "i dont like the pink
			# ticket. lets scrap tickets, can you do a gundam style character"): a paper helmet with side
			# vents, a gold V-fin with a red jewel, an ink face band with two green eyes, a red chin.
			var gold := CelMaterial.for_colour(Color.from_hsv(46.0 / 360.0, 0.8, 0.9), shadow, 0.3)
			var red := CelMaterial.for_colour(Palette.hud_colour("danger"), shadow, 0.2)
			var eyes := CelMaterial.for_colour(Palette.map_colour("board", "alien"), shadow, 1.0)
			var grey := CelMaterial.for_colour(Palette.map_colour("board", "metal"), shadow)
			var head := Node3D.new()
			head.position = Vector3(0, y, 0.08)
			root.add_child(head)
			_flat_polygon(head, GUNDAM_HELMET, Vector3.ZERO, 0.4, paper_mat)
			_flat_polygon(head, GUNDAM_FIN, Vector3(0, 0.006, 0), 0.4, gold)
			_prop_cyl(head, 0.035, 0.014, Vector3(0, 0.012, -0.2), red)
			_prop_box(head, Vector3(0.34, 0.012, 0.13), Vector3(0, 0.006, 0.0), ink_mat)
			for ex: float in [-0.09, 0.09]:
				_prop_box(head, Vector3(0.08, 0.012, 0.05), Vector3(ex, 0.012, -0.01), eyes)
				_prop_box(head, Vector3(0.07, 0.012, 0.1), Vector3(ex * 2.6, 0.006, 0.08), grey)
			_flat_point(head, 0.16, 0.13, Vector3(0, 0.012, 0.25), PI * 0.5, red)
		"item":
			# A wrapped present painted from above (Sean: not the star): a paper box, an accent ribbon
			# crossing it, a bow of two loops and a knot in the middle.
			var ribbon := CelMaterial.for_colour(Palette.map_colour("board", "accent"), shadow, 0.3)
			var gift := Node3D.new()
			gift.position = Vector3(0, y, 0)
			gift.rotation.y = 0.35
			root.add_child(gift)
			_prop_box(gift, Vector3(0.62, 0.012, 0.62), Vector3.ZERO, paper_mat)
			_prop_box(gift, Vector3(0.64, 0.014, 0.13), Vector3(0, 0.004, 0), ribbon)
			_prop_box(gift, Vector3(0.13, 0.014, 0.64), Vector3(0, 0.004, 0), ribbon)
			for s: float in [-1.0, 1.0]:
				var loop := MeshInstance3D.new()
				var lm := TorusMesh.new()
				lm.inner_radius = 0.05
				lm.outer_radius = 0.11
				lm.rings = 12
				lm.ring_segments = 4
				loop.mesh = lm
				loop.position = Vector3(s * 0.11, 0.012, -0.06)
				loop.rotation.y = s * 0.6
				loop.scale = Vector3(1.4, 0.12, 0.9)
				loop.material_override = ribbon
				gift.add_child(loop)
			_prop_cyl(gift, 0.045, 0.016, Vector3(0, 0.014, -0.02), ribbon)
		"lose":
			_flat_ngon(root, 0.5, 16, Vector3(0, y, 0), paper_mat, 0.0)
			_flat_ngon(root, 0.23, 12, Vector3(0, y + 0.006, 0), ink_mat, 0.0)
			for k in 8:
				var a := k * TAU / 8.0
				_flat_point(root, 0.13, 0.2, Vector3(cos(a) * 0.3, y + 0.006, sin(a) * 0.3), a, ink_mat)
			_prop_cyl(root, 0.05, 0.012, Vector3(-0.07, y + 0.012, -0.07), paper_mat)   # a glint
		"heal":
			var cross := CelMaterial.for_colour(Color.from_hsv(128.0 / 360.0, 0.72, 0.52), shadow)
			_prop_box(root, Vector3(0.72, 0.012, 0.5), Vector3(0, y, 0.06), paper_mat)   # the bag
			_prop_box(root, Vector3(0.6, 0.012, 0.08), Vector3(0, y, -0.22), paper_mat)   # its top edge
			var handle := MeshInstance3D.new()
			var hm := TorusMesh.new()
			hm.inner_radius = 0.12
			hm.outer_radius = 0.19
			hm.rings = 16
			hm.ring_segments = 4
			handle.mesh = hm
			handle.position = Vector3(0, y, -0.28)
			handle.scale = Vector3(1.0, 0.15, 1.0)
			handle.material_override = paper_mat
			root.add_child(handle)
			_prop_box(root, Vector3(0.36, 0.012, 0.12), Vector3(0, y + 0.006, 0.06), cross)
			_prop_box(root, Vector3(0.12, 0.012, 0.36), Vector3(0, y + 0.006, 0.06), cross)
		"shield":
			var dome := MeshInstance3D.new()
			var dm := SphereMesh.new()
			dm.radius = 0.36
			dm.height = 0.72
			dm.radial_segments = 14
			dm.rings = 7
			dm.is_hemisphere = true
			dome.mesh = dm
			dome.position = Vector3(0, 0.02, 0)
			dome.scale = Vector3(1.0, 0.8, 1.0)
			dome.material_override = CelMaterial.for_colour(Palette.hud_colour("meter"), shadow, 0.5)
			root.add_child(dome)
			var band := MeshInstance3D.new()
			var bm2 := TorusMesh.new()
			bm2.inner_radius = 0.34
			bm2.outer_radius = 0.42
			bm2.rings = 16
			bm2.ring_segments = 6
			band.mesh = bm2
			band.position = Vector3(0, 0.03, 0)
			band.scale = Vector3(1.0, 0.5, 1.0)
			band.material_override = ink_mat
			root.add_child(band)
		"start":
			var pole := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.04
			pm.bottom_radius = 0.04
			pm.height = 1.3
			pole.mesh = pm
			pole.position = Vector3(0.7, 0.65, -0.7)
			pole.material_override = ink_mat
			root.add_child(pole)
			var flag := MeshInstance3D.new()
			var fm := PrismMesh.new()
			fm.size = Vector3(0.5, 0.34, 0.04)
			flag.mesh = fm
			flag.position = Vector3(0.7 + 0.27, 1.13, -0.7)
			flag.rotation.z = -PI * 0.5
			flag.material_override = CelMaterial.for_colour(Palette.map_colour("board", "accent"), shadow, 0.3)
			root.add_child(flag)
		_:
			root.queue_free()
			return
	tile.add_child(root)
	markers.append(root)


## A flat regular polygon lying on the face, for the painted emblems.
func _flat_ngon(parent: Node3D, radius: float, sides: int, pos: Vector3, mat: Material, turn: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.012
	cm.radial_segments = sides
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	mi.rotation.y = turn
	mi.material_override = mat
	parent.add_child(mi)


## A flat triangle lying on the face with its apex pointing along angle `a` (from +x toward +z).
func _flat_point(parent: Node3D, width: float, length: float, pos: Vector3, a: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(width, length, 0.012)
	mi.mesh = pm
	mi.position = pos
	mi.rotation = Vector3(-PI * 0.5, atan2(-cos(a), -sin(a)), 0.0)
	mi.material_override = mat
	parent.add_child(mi)


## The tile whose centre projects nearest the screen point, within `max_px`; "" if none.
func tile_at_screen(pos: Vector2, max_px: float = 70.0) -> String:
	if camera == null:
		return ""
	var best := ""
	var best_d := max_px
	for sid in tiles:
		var world := director.space_position(str(sid))
		if camera.is_position_behind(world):
			continue
		var d := camera.unproject_position(world).distance_to(pos)
		if d < best_d:
			best_d = d
			best = str(sid)
	return best


var _socials: Array = []   # [{node, t, life, base_y, kind}]


## A pin in the pinger's colour bouncing over a space, with their name, for three seconds.
func show_ping(peer_id: int, space_id: String) -> void:
	if Game.headless or not tiles.has(space_id):
		return
	var p := director.state.player(peer_id) if director.state != null else null
	var col := Palette.player_colour(p.colour_index) if p != null else Palette.hud_colour("paper")
	var shadow := Palette.map_colour("board", "shadow_tint")
	var ink := Palette.map_colour("board", "line")
	var root := Node3D.new()
	var base := director.space_position(space_id) + Vector3(0, 1.3, 0)
	root.position = base
	add_child(root)
	var pin := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.34
	cm.bottom_radius = 0.0
	cm.height = 0.7
	cm.radial_segments = 10
	pin.mesh = cm
	pin.material_override = CelMaterial.for_colour(col, shadow, 0.6)
	root.add_child(pin)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.64
	sm.radial_segments = 12
	sm.rings = 6
	ball.mesh = sm
	ball.position.y = 0.55
	ball.material_override = CelMaterial.for_colour(col, shadow, 0.6)
	root.add_child(ball)
	var dot := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.12
	dm.height = 0.24
	dot.mesh = dm
	dot.position = Vector3(0, 0.55, -0.26)
	dot.material_override = CelMaterial.for_colour(Color.from_hsv(ink.h, 0.45, 0.24), shadow)
	root.add_child(dot)
	var label := Label3D.new()
	label.text = (p.display_name if p != null else "?").to_upper()
	label.font_size = 40
	label.pixel_size = 0.006
	label.outline_size = 12
	label.modulate = Palette.hud_colour("paper")
	label.outline_modulate = ink
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.position.y = 1.15
	root.add_child(label)
	_socials.append({"node": root, "t": 0.0, "life": 3.0, "base_y": base.y, "kind": "ping"})
	Log.debug("board", "Ping pin at %s (space %s)" % [str(base), space_id])


## A speech bubble over the player's pawn for a couple of seconds.
func show_emote(peer_id: int, text: String) -> void:
	if Game.headless or not pawns.has(peer_id):
		return
	var pawn: BoardPawn = pawns[peer_id]
	var ink := Palette.map_colour("board", "line")
	var root := Node3D.new()
	root.position = Vector3(0, 2.7, 0)
	pawn.add_child(root)
	var bubble := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.34 * text.length() + 0.5, 0.62)
	bubble.mesh = qm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Palette.hud_colour("paper")
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.material_override = bm
	root.add_child(bubble)
	var label := Label3D.new()
	label.text = text
	label.font_size = 56
	label.pixel_size = 0.006
	label.outline_size = 0
	label.modulate = Color.from_hsv(ink.h, 0.45, 0.24)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.position.z = 0.02
	label.render_priority = 1
	root.add_child(label)
	root.scale = Vector3.ONE * 0.2
	_socials.append({"node": root, "t": 0.0, "life": 2.4, "base_y": 2.7, "kind": "emote"})


# --- the laser gun ------------------------------------------------------------------------------------

## The aiming beam: a thin red bar with a bright dot at its end, unshaded so it reads as light.
## Reused for the shot flash (thicker, fading).
func _build_beam() -> void:
	_beam = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.07, 1.0)
	_beam.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.95, 0.12, 0.1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 3
	_beam.material_override = mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
	_beam_dot = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	sm.radial_segments = 10
	sm.rings = 5
	_beam_dot.mesh = sm
	_beam_dot.material_override = mat
	_beam_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam_dot.visible = false
	add_child(_beam_dot)


func _place_beam(from: Vector3, a: float, length: float, thick: float, alpha: float, col: Color = Color(0.95, 0.12, 0.1)) -> void:
	var dir := Vector3(cos(a), 0.0, sin(a))
	_beam.visible = true
	_beam_dot.visible = true
	_beam.scale = Vector3(thick / 0.07, thick / 0.07, length)
	_beam.global_position = from + dir * length * 0.5
	_beam.look_at(from + dir * length, Vector3.UP)
	_beam_dot.global_position = from + dir * length
	_beam_dot.scale = Vector3.ONE * (thick / 0.07) * 0.8
	(_beam.material_override as StandardMaterial3D).albedo_color = Color(col, alpha)


func _hide_beam() -> void:
	if _beam != null:
		_beam.visible = false
		_beam_dot.visible = false


## The local player draws the laser (or the claw): the pawn turns to follow the mouse and the
## line shows how far it reaches. `length` in metres (the rules' laser_length or claw_length).
func begin_aim(peer_id: int, length: float, kind: String = "laser") -> void:
	_aiming = true
	_aim_peer = peer_id
	_aim_len = length
	_aim_kind = kind
	var pawn: BoardPawn = pawns.get(peer_id, null)
	if pawn != null:
		if kind == "claw":
			pawn.show_claw(true)
		else:
			pawn.show_gun(true)
		_focus(pawn.global_position)


func end_aim() -> void:
	if not _aiming:
		return
	_aiming = false
	var pawn: BoardPawn = pawns.get(_aim_peer, null)
	if pawn != null and not _throw:
		pawn.show_gun(false)
		pawn.show_claw(false)
	_throw = false
	_hide_beam()
	if _range_ring != null:
		_range_ring.visible = false
		_reticle.visible = false


func is_aiming() -> bool:
	return _aiming


func aim_angle() -> float:
	return _aim


## Aim from the mouse: the point under the cursor on the plane at the pawn's chest height, seen
## from the pawn. Keeps the last aim when the cursor is off the plane. `--aim_test=DEG` pins it.
func _update_aim(pawn: BoardPawn) -> void:
	if Game.args.has("aim_test") or Game.args.has("claw_test"):
		_aim = deg_to_rad(float(Game.args.get("aim_test", Game.args.get("claw_test", 0))))
		return
	if camera == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var normal := camera.project_ray_normal(mouse)
	var plane_y := pawn.global_position.y + 1.0
	if absf(normal.y) < 0.001:
		return
	var t := (plane_y - origin.y) / normal.y
	if t <= 0.0:
		return
	var hit := origin + normal * t
	var d := Vector2(hit.x - pawn.global_position.x, hit.z - pawn.global_position.z)
	if d.length() > 0.2:
		_aim = atan2(d.y, d.x)


## The local player aims the bomb: a ring on the ground shows how far it can be thrown, a reticle
## the size of the blast follows the mouse inside it, and the pawn turns to face it.
func begin_throw(peer_id: int, range_m: float, radius_m: float) -> void:
	_aiming = true
	_throw = true
	_aim_peer = peer_id
	_throw_range = range_m
	_throw_radius = radius_m
	var pawn: BoardPawn = pawns.get(peer_id, null)
	if pawn == null:
		return
	_ensure_throw_marks()
	(_range_ring.mesh as TorusMesh).inner_radius = range_m - 0.08
	(_range_ring.mesh as TorusMesh).outer_radius = range_m + 0.08
	var rt := (_reticle.get_child(0) as MeshInstance3D).mesh as TorusMesh
	rt.inner_radius = radius_m - 0.09
	rt.outer_radius = radius_m + 0.09
	_range_ring.visible = true
	_reticle.visible = true
	_range_ring.global_position = pawn.global_position + Vector3(0, 0.05, 0)
	_throw_point = pawn.global_position + Vector3(range_m * 0.6, 0.0, 0.0)
	_focus(pawn.global_position)


func throw_point() -> Vector3:
	return _throw_point


func _ensure_throw_marks() -> void:
	if _range_ring != null:
		return
	_range_ring = MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.rings = 72
	rm.ring_segments = 6
	_range_ring.mesh = rm
	_range_ring.material_override = _flat_mat(Color(Palette.hud_colour("score"), 0.8))
	_range_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_range_ring)
	_reticle = Node3D.new()
	add_child(_reticle)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.rings = 40
	tm.ring_segments = 6
	ring.mesh = tm
	ring.material_override = _flat_mat(Color(Palette.hud_colour("danger"), 0.85))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reticle.add_child(ring)
	var dot := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.22
	dm.bottom_radius = 0.22
	dm.height = 0.04
	dot.mesh = dm
	dot.material_override = _flat_mat(Color(Palette.hud_colour("danger"), 0.9))
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reticle.add_child(dot)


## An unshaded translucent material drawn after the outline quad, which paints over transparent
## geometry drawn before it.
func _flat_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.render_priority = 3
	return m


## The landing point from the mouse: the point under the cursor on the plane at the pawn's feet,
## held within the range. `--throw_test=DEG` pins it at 70 % of the range in that direction.
func _update_throw(pawn: BoardPawn) -> void:
	var base := pawn.global_position
	if Game.args.has("throw_test"):
		var a := deg_to_rad(float(Game.args["throw_test"]))
		_throw_point = base + Vector3(cos(a), 0.0, sin(a)) * _throw_range * 0.7
	elif camera != null:
		var mouse := get_viewport().get_mouse_position()
		var origin := camera.project_ray_origin(mouse)
		var normal := camera.project_ray_normal(mouse)
		if absf(normal.y) > 0.001:
			var t := (base.y - origin.y) / normal.y
			if t > 0.0:
				var hit := origin + normal * t
				var d := Vector2(hit.x - base.x, hit.z - base.z)
				if d.length() > _throw_range:
					d = d.normalized() * _throw_range
				_throw_point = Vector3(base.x + d.x, base.y, base.z + d.y)
	var to := _throw_point - base
	if Vector2(to.x, to.z).length() > 0.2:
		pawn.face_angle(atan2(to.z, to.x))
	_range_ring.global_position = base + Vector3(0, 0.05, 0)
	_reticle.global_position = _throw_point + Vector3(0, 0.06, 0)


## The shot everyone sees: a thick beam that fades over a third of a second.
func _flash_beam(from: Vector3, a: float, length: float) -> void:
	_place_beam(from, a, length, 0.16, 1.0)
	var tw := create_tween()
	tw.tween_method(func(v: float): _place_beam(from, a, length, 0.16 * (0.4 + 0.6 * v), v), 1.0, 0.0, 0.36)
	tw.tween_callback(func(): if not _aiming: _hide_beam())


## Blood: a burst of dark-red blobs flung from the victim, then a splat on the board.
func _blood_burst(at: Vector3) -> void:
	if Game.headless:
		return
	Burst.spawn(self, at + Vector3(0, 1.0, 0), Color.from_hsv(355.0 / 360.0, 0.85, 0.5), 0.9, 0.3, 9)
	for k in 9:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r := randf_range(0.05, 0.11)
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 6
		sm.rings = 3
		mi.mesh = sm
		mi.material_override = _blood_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = at + Vector3(0, randf_range(0.8, 1.3), 0)
		var fling := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * randf_range(0.5, 1.4)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "global_position:x", mi.global_position.x + fling.x, 0.42)
		tw.tween_property(mi, "global_position:z", mi.global_position.z + fling.z, 0.42)
		tw.tween_property(mi, "global_position:y", at.y + 0.04, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_property(mi, "scale", Vector3(1.5, 0.15, 1.5), 0.08)
		tw.chain().tween_interval(1.2)
		tw.chain().tween_callback(mi.queue_free)


## One splat from a state record {n, space, a, r, seed}: flat dark-red discs on the tile,
## drawn once per serial so a rebuilt view and a replayed event agree.
func _draw_blood(entry: Dictionary) -> void:
	var n := int(entry.get("n", 0))
	if _blood_drawn.has(n) or _blood_root == null:
		return
	_blood_drawn[n] = true
	var base := director.space_position(str(entry.get("space", "")))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(entry.get("seed", 0)) * 7919 + n
	var root := Node3D.new()
	root.position = base + Vector3(0, 0.03, 0)
	root.rotation.y = float(entry.get("a", 0.0))
	_blood_root.add_child(root)
	var spread := float(entry.get("r", 0.6))
	for k in 7:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r := rng.randf_range(0.12, 0.34) * (1.4 if k == 0 else 1.0)
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 9
		sm.rings = 4
		mi.mesh = sm
		mi.material_override = _blood_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var off := Vector3.ZERO if k == 0 else Vector3(rng.randf_range(-spread, spread), 0.0, rng.randf_range(-spread, spread)) * 0.8
		mi.position = off + Vector3(0, -r + 0.05, 0)
		mi.scale = Vector3(rng.randf_range(0.9, 1.4), 0.1, rng.randf_range(0.9, 1.4))
		root.add_child(mi)
	for k in 5:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r := rng.randf_range(0.04, 0.08)
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 6
		sm.rings = 3
		mi.mesh = sm
		mi.material_override = _blood_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ang := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(spread * 0.9, spread * 1.6)
		mi.position = Vector3(cos(ang) * dist, -r + 0.05, sin(ang) * dist)
		mi.scale = Vector3(1.0, 0.15, 1.0)
		root.add_child(mi)


## Everything in the state's blood list that is not on the board yet (a rebuilt view, a
## reconnect, or a splat whose event this peer never played).
func _draw_blood_from_state() -> void:
	if director.state == null:
		return
	for entry in director.state.blood:
		_draw_blood(entry)


## The ring and the lit machine move to `spot` together.
func _show_goal(spot: String) -> void:
	_goal_spot = spot
	if goal_ring != null:
		_place_goal(director.space_position(spot))
	if _dressing != null:
		_dressing.set_active_machine(spot)


func _place_goal(pos: Vector3) -> void:
	goal_ring.global_position = pos + Vector3(0, 0.08, 0)
	if goal_beacon != null:
		goal_beacon.global_position = pos + Vector3(0, 2.1, 0)
		goal_beacon.set_meta("base_y", pos.y + 2.1)


func _clear_of_tiles(g: BoardGraph, x: float, z: float, min_d: float) -> bool:
	for sid in g.ids():
		var sp := g.get_space(sid).position
		if Vector2(sp.x - x, sp.z - z).length() < min_d:
			return false
	return true


const MOON_TOP := -1.75


## The block of the board a prop or a structure belongs to, by kind (`BoardGraph.zones`, written
## by tools/gen_board.gd): {} when the board has none.
func _zone(kind: String) -> Dictionary:
	for z in director.graph.zones:
		if str(z.get("kind", "")) == kind:
			return z
	return {}


## A point in a zone: its centre plus an offset turned by its yaw.
func _zone_at(zone: Dictionary, dx: float, dz: float) -> Vector2:
	var c: Array = zone.get("centre", [0.0, 0.0])
	var yaw := float(zone.get("yaw", 0.0))
	var off := Vector2(dx, dz).rotated(-yaw)
	return Vector2(float(c[0]), float(c[1])) + off


## True when (x, z) is at least `pad` outside every block's disc.
func _zone_clear(x: float, z: float, pad: float) -> bool:
	for zone in director.graph.zones:
		var c: Array = zone.get("centre", [0.0, 0.0])
		if Vector2(x - float(c[0]), z - float(c[1])).length() < float(zone.get("r", 0.0)) + pad:
			return false
	return true


## The moon: the board stands on posts over a floating chunk of grey rock. Since 2026-09-24 the
## chunk is the board file's own rounded plot (`BoardGraph.slab`, a superellipse; a file without
## one gets the old ellipse round its tiles): the district's streets run inside it with a margin
## of open moon round them, and its blocks hold the base's set-pieces (the "zones", built by the
## dressing; the five landmark props here take their spots from them). The pink sky stays (Sean:
## outer space, keep the pink).
func _build_moon_chunk() -> void:
	var g := director.graph
	var shadow := _shadow
	var rng := _moon_rng
	rng.seed = hash(g.id) + 23
	var tiles: Array = []
	for sid in g.ids():
		tiles.append(g.get_space(sid).position)
	_slab = g.slab if g.slab != null else MoonSlab.around(tiles, 7.0, 7.0)
	# How far out the walkways reach: the ring road sits at this fraction of the way to the rim;
	# the open moon (the small craters, the buggy's road, the annex bridges) lies past it.
	_district_f = 0.0
	for p in tiles:
		_district_f = maxf(_district_f, _slab.f_of(p.x, p.z))
	# Feature counts were set on the 31 × 25 m slab of the 65-space board; a bigger board keeps
	# the same density (boulders, pebbles per square metre) so it does not read as empty.
	_moon_density = _slab.area() / (PI * 31.0 * 25.0)
	# The five landmark props' spots: the rocket's pad and the parked buggy in the pad block, the
	# dish at the power plant, the probe on the park's lawn, the crew by the flag on the plaza off
	# the start. A board without blocks gets the old search for clear spots.
	var rocket := _zone("rocket")
	var pad := _zone("pad")
	var power := _zone("power")
	var park := _zone("park")
	var plaza := _zone("plaza")
	_prop_spots = []
	_prop_yaws = []
	if not (rocket.is_empty() or pad.is_empty() or power.is_empty() or park.is_empty() or plaza.is_empty()):
		# The rocket on its pad by the pad space, the dish at the power plant, the rover on its
		# own pad, the probe on the park's lawn past the crater, the crew by the flag off the start.
		_prop_spots = [_zone_at(rocket, 0.0, 0.0), _zone_at(power, -3.8, 3.4), _zone_at(pad, 1.2, 0.4),
			_zone_at(park, -4.8, -2.2), _zone_at(plaza, 0.0, 0.0)]
		_prop_yaws = [rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), float(pad.get("yaw", 0.0)) + PI * 0.5,
			rng.randf_range(0.0, TAU), float(plaza.get("yaw", 0.0)) + 0.4]
	var c := _slab.centre
	var moon_mat := CelMaterial.with_print(CelMaterial.for_colour(Palette.map_colour("board", "moon"), shadow), "moon", Palette.map_colour("board", "line"))
	var moon_dark_mat := CelMaterial.for_colour(Palette.map_colour("board", "moon_dark"), shadow)
	var post_mat := CelMaterial.for_colour(Palette.map_colour("board", "counter_dark"), shadow)
	# The chunk: a prism on the slab's outline (40 sides, each pushed in or out a little so the
	# edge reads as rock, not a cut), 2.6 m thick with its foot drawn in; a rocky root tapering
	# nine metres down.
	var slab := MeshInstance3D.new()
	slab.mesh = _prism(_slab.outline(40, 0.015, rng), 2.6, 0.94)
	slab.position = c + Vector3(0, MOON_TOP - 2.6, 0)
	slab.material_override = moon_mat
	add_child(slab)
	var root := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.9
	rm.bottom_radius = 0.22
	rm.height = 1.0
	rm.radial_segments = 11
	root.mesh = rm
	root.scale = Vector3(_slab.rx, 9.0, _slab.rz)
	root.position = c + Vector3(0, MOON_TOP - 2.6 - 4.5, 0)
	root.material_override = moon_dark_mat
	add_child(root)
	# Posts from every tile down to the rock, with a foot.
	for sid in g.ids():
		var sp := g.get_space(sid).position
		var bottom := sp.y - 1.22
		var h := bottom - MOON_TOP + 0.3
		if h > 0.2:
			_prop_cyl(self, 0.3, h, Vector3(sp.x, MOON_TOP + h * 0.5 - 0.1, sp.z), post_mat)
		_prop_cyl(self, 0.75, 0.14, Vector3(sp.x, MOON_TOP + 0.05, sp.z), moon_dark_mat)


## A flat-shaded prism: `outline` at the top (y = height), the same outline scaled by `foot` at
## the base (y = 0), sides between. Fanned from the origin, so the outline must be star-shaped
## about it (a superellipse is). Front faces wind clockwise, as Godot wants, and every face
## carries its own normal (SurfaceTool's generated normals smooth the rim between the top and
## the sides, which shaded the top as a lit blob fading to the shadow band at the edge).
func _prism(outline: PackedVector2Array, height: float, foot: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var n := outline.size()
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		var ta := Vector3(a.x, height, a.y)
		var tb := Vector3(b.x, height, b.y)
		var ba := Vector3(a.x * foot, 0.0, a.y * foot)
		var bb := Vector3(b.x * foot, 0.0, b.y * foot)
		# Top: centre, a, b (clockwise seen from above, x east and z south).
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(0, height, 0))
		st.add_vertex(ta)
		st.add_vertex(tb)
		# Base, seen from below.
		st.set_normal(Vector3.DOWN)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(bb)
		st.add_vertex(ba)
		# The side, its normal outward and a little up (the foot is drawn in).
		st.set_normal((tb - ta).cross(ba - ta).normalized())
		st.add_vertex(ta)
		st.add_vertex(ba)
		st.add_vertex(tb)
		st.add_vertex(tb)
		st.add_vertex(ba)
		st.add_vertex(bb)
	return st.commit()


## The moon's second chunk: craters and boulders. The big crater is the park's (the "crater"
## zone, the rig stands over it); the small ones lie in the open moon past the ring road and on
## the park's lawn, never under a tile; boulders anywhere clear of the tiles, the blocks and the
## props. The seeded stream carries on from the first chunk.
func _build_moon_craters() -> void:
	var g := director.graph
	var shadow := _shadow
	var rng := _moon_rng
	var moon_dark_mat := CelMaterial.for_colour(Palette.map_colour("board", "moon_dark"), shadow)
	var crater_mat := CelMaterial.for_colour(Palette.map_colour("board", "crater"), shadow)
	var rock_mat := CelMaterial.for_colour(Palette.map_colour("board", "rock"), shadow)
	var craters: Array = []
	var big := _zone("crater")
	var big_r := float(big.get("r", 4.0))
	if big.is_empty():
		# The drawn board's park holds its crater in the middle of the block.
		big = _zone("park")
		big_r = float(big.get("r", 6.0)) * 0.55
	if not big.is_empty():
		var bc := _zone_at(big, 0.0, 0.0)
		craters.append(Vector3(bc.x, bc.y, big_r))
	# Small craters in the margin past the ring road (a band a few metres wide, so they are
	# small), and two on the park's lawn.
	var park := _zone("park")
	var wanted := craters.size() + roundi(12 * sqrt(_moon_density)) + (2 if not park.is_empty() else 0)
	var tries := 0
	while craters.size() < wanted and tries < 900:
		tries += 1
		var on_lawn := not park.is_empty() and tries % 4 == 0 and craters.size() >= wanted - 2
		var x: float
		var z: float
		var r: float
		if on_lawn:
			var lc := _zone_at(park, 0.0, 0.0)
			var lr := float(park.get("r", 7.0))
			var la := rng.randf_range(0.0, TAU)
			var lf := rng.randf_range(0.3, 0.8) * lr
			x = lc.x + cos(la) * lf
			z = lc.y + sin(la) * lf
			r = rng.randf_range(1.2, 1.8)
		elif _district_f > 0.0 and _district_f < 0.95:
			var pt := _slab.point(rng.randf_range(0.0, TAU), rng.randf_range(_district_f + 0.04, 0.95))
			x = pt.x
			z = pt.y
			r = rng.randf_range(1.0, 1.7)
		else:
			var pt := _slab.point(rng.randf_range(0.0, TAU), sqrt(rng.randf_range(0.04, 0.9)))
			x = pt.x
			z = pt.y
			r = rng.randf_range(1.1, 3.4)
		if not _clear_of_tiles(g, x, z, r + 1.6):
			continue
		if not on_lawn and not _zone_clear(x, z, r + 0.5):
			continue
		var ok := _slab.inside(x, z, 0.96)
		for cr in craters:
			if Vector2(x - cr.x, z - cr.y).length() < r + cr.z + 1.0:
				ok = false
				break
		for sp in _prop_spots:
			if Vector2(x - sp.x, z - sp.y).length() < r + 3.0:
				ok = false
				break
		if not ok:
			continue
		craters.append(Vector3(x, z, r))
	for cr in craters:
		var x: float = cr.x
		var z: float = cr.y
		var r: float = cr.z
		_prop_cyl(self, r * 0.86, 0.08, Vector3(x, MOON_TOP + 0.03, z), crater_mat)
		var rim := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r * 0.86
		tm.outer_radius = r * 1.14
		tm.rings = 24 if r < 3.0 else 40
		tm.ring_segments = 6
		rim.mesh = tm
		rim.position = Vector3(x, MOON_TOP + 0.06, z)
		rim.scale = Vector3(1.0, 0.5, 1.0)
		rim.material_override = moon_dark_mat
		add_child(rim)
	# Boulders: in the open moon and the blocks' leftover corners, a few on the rim so the edge
	# reads as rock.
	var inner_boulders := roundi(20 * _moon_density)
	for k in roundi(28 * _moon_density):
		var a := rng.randf_range(0.0, TAU)
		var f := sqrt(rng.randf_range(0.1, 1.0)) if k < inner_boulders else rng.randf_range(0.97, 1.02)
		var pt := _slab.point(a, f)
		var x := pt.x
		var z := pt.y
		if not _clear_of_tiles(g, x, z, 2.4) or not _zone_clear(x, z, 1.0):
			continue
		var ok := true
		for cr in craters:
			if Vector2(x - cr.x, z - cr.y).length() < cr.z + 1.4:
				ok = false
		for sp in _prop_spots:
			if Vector2(x - sp.x, z - sp.y).length() < 3.6:
				ok = false
		if not ok:
			continue
		var r := rng.randf_range(0.35, 1.3)
		var b := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = r
		bm.height = r * 2.0
		bm.radial_segments = 7
		bm.rings = 4
		b.mesh = bm
		b.position = Vector3(x, MOON_TOP + r * 0.45, z)
		b.scale = Vector3(rng.randf_range(0.8, 1.3), rng.randf_range(0.55, 0.9), rng.randf_range(0.8, 1.3))
		b.rotation.y = rng.randf_range(0.0, TAU)
		b.material_override = rock_mat if k % 3 != 0 else moon_dark_mat
		add_child(b)
	_craters = craters


## The moon's third chunk: the five landmark props (a landing pad with a rocket, a dish on a
## tripod, a buggy, a half-buried probe, a crew member by a flag), each on its block's spot
## (`_build_moon_chunk`) or, on a board without blocks, in a spot searched here clear of the
## tiles, the craters and each other. Props `from` up to `to` are built; the seeded stream runs
## on across the calls in the single build's order.
func _build_moon_props(from: int, to: int) -> void:
	var g := director.graph
	var shadow := _shadow
	var rng := _moon_rng
	var craters := _craters
	var metal_mat := CelMaterial.for_colour(Palette.map_colour("board", "metal"), shadow)
	var paper_mat := CelMaterial.for_colour(Palette.hud_colour("paper"), shadow)
	var accent_mat := CelMaterial.for_colour(Palette.map_colour("board", "accent"), shadow, 0.3)
	var ink_mat := CelMaterial.for_colour(Color.from_hsv(Palette.map_colour("board", "line").h, 0.45, 0.24), shadow)
	var glow_mat := CelMaterial.for_colour(Palette.hud_colour("danger"), shadow, 1.5)
	var alien_mat := CelMaterial.for_colour(Palette.map_colour("board", "alien"), shadow, 1.2)
	var spots: Array = _prop_spots
	var tries := 0
	while from == 0 and spots.size() < 5 and tries < 600:
		tries += 1
		var pt := _slab.point(rng.randf_range(0.0, TAU), rng.randf_range(0.3, 0.88))
		var x := pt.x
		var z := pt.y
		if not _clear_of_tiles(g, x, z, 4.6):
			continue
		var ok := true
		for sp in spots:
			if Vector2(x - sp.x, z - sp.y).length() < 9.0:
				ok = false
				break
		for cr in craters:
			if Vector2(x - cr.x, z - cr.y).length() < cr.z + 3.0:
				ok = false
				break
		if ok:
			spots.append(Vector2(x, z))
			_prop_yaws.append(rng.randf_range(0.0, TAU))
	_prop_spots = spots
	for n in range(from, mini(to, spots.size())):
		var at := Vector3(spots[n].x, MOON_TOP, spots[n].y)
		var prop := Node3D.new()
		prop.position = at
		prop.rotation.y = float(_prop_yaws[n]) if n < _prop_yaws.size() else rng.randf_range(0.0, TAU)
		add_child(prop)
		match n:
			0:   # landing pad with a rocket on its fins
				_prop_cyl(prop, 3.2, 0.16, Vector3(0, 0.08, 0), metal_mat)
				var ring := MeshInstance3D.new()
				var tm2 := TorusMesh.new()
				tm2.inner_radius = 2.6
				tm2.outer_radius = 2.95
				tm2.rings = 32
				tm2.ring_segments = 4
				ring.mesh = tm2
				ring.position.y = 0.18
				ring.scale = Vector3(1.0, 0.3, 1.0)
				ring.material_override = accent_mat
				prop.add_child(ring)
				# The rocket itself on a node of its own, so it can fly (the board's one rocket, Sean's
				# drawing, 2026-09-24); a flame under the bell shows only in flight.
				var rocket := Node3D.new()
				prop.add_child(rocket)
				_shuttle = rocket
				_shuttle_home = at
				var flame := MeshInstance3D.new()
				var flm := CylinderMesh.new()
				flm.top_radius = 0.5
				flm.bottom_radius = 0.06
				flm.height = 1.5
				flm.radial_segments = 10
				flame.mesh = flm
				flame.position = Vector3(0, -0.5, 0)
				flame.material_override = CelMaterial.for_colour(Palette.hud_colour("score"), shadow, 1.6)
				flame.visible = false
				rocket.add_child(flame)
				_shuttle_flame = flame
				# The rocket's foot (Sean: the bottom was "random triangles pasted on it"): the
				# body ends in a wider skirt, an engine bell hangs under it, and three fins are
				# right-triangle plates standing on the pad with their straight edge against the
				# skirt and the body, the slope running out to the tip.
				_prop_cyl(rocket, 0.72, 3.6, Vector3(0, 2.5, 0), paper_mat)     # body, foot at 0.7
				_prop_cyl(rocket, 0.74, 0.5, Vector3(0, 2.0, 0), accent_mat)    # band
				_prop_cyl(rocket, 0.8, 0.36, Vector3(0, 0.88, 0), accent_mat)   # skirt
				var bell := MeshInstance3D.new()
				var bellm := CylinderMesh.new()
				bellm.top_radius = 0.34
				bellm.bottom_radius = 0.58
				bellm.height = 0.46
				bellm.radial_segments = 14
				bell.mesh = bellm
				bell.position.y = 0.47
				bell.material_override = ink_mat
				rocket.add_child(bell)
				_prop_cyl(rocket, 0.3, 0.06, Vector3(0, 0.3, 0), metal_mat)     # the throat
				for fk in 3:
					var fa := fk * TAU / 3.0 + 0.5
					var fin := MeshInstance3D.new()
					var fm := PrismMesh.new()
					fm.size = Vector3(1.0, 1.5, 0.1)
					fm.left_to_right = 0.0   # the apex over the inner edge: a right triangle
					fin.mesh = fm
					fin.position = Vector3(cos(fa) * 1.2, 0.99, sin(fa) * 1.2)
					fin.rotation.y = -fa   # local +x points out from the axis
					fin.material_override = accent_mat
					rocket.add_child(fin)
				var nose := MeshInstance3D.new()
				var nm := CylinderMesh.new()
				nm.top_radius = 0.0
				nm.bottom_radius = 0.72
				nm.height = 1.5
				nm.radial_segments = 14
				nose.mesh = nm
				nose.position.y = 5.05
				nose.material_override = accent_mat
				rocket.add_child(nose)
				var port := MeshInstance3D.new()
				var pm := CylinderMesh.new()
				pm.top_radius = 0.26
				pm.bottom_radius = 0.26
				pm.height = 0.08
				port.mesh = pm
				port.position = Vector3(0, 3.2, -0.72)
				port.rotation.x = PI * 0.5
				port.material_override = CelMaterial.for_colour(Palette.hud_colour("meter"), shadow, 0.6)
				rocket.add_child(port)
			1:   # satellite dish on a tripod
				for lk in 3:
					var leg := MeshInstance3D.new()
					var lm := CylinderMesh.new()
					lm.top_radius = 0.07
					lm.bottom_radius = 0.07
					lm.height = 2.6
					leg.mesh = lm
					leg.position = Vector3(cos(lk * TAU / 3.0) * 0.55, 1.2, sin(lk * TAU / 3.0) * 0.55)
					leg.rotation = Vector3(sin(lk * TAU / 3.0) * 0.32, 0.0, -cos(lk * TAU / 3.0) * 0.32)
					leg.material_override = ink_mat
					prop.add_child(leg)
				var dish := MeshInstance3D.new()
				var dm := CylinderMesh.new()
				dm.top_radius = 1.9
				dm.bottom_radius = 0.3
				dm.height = 0.6
				dm.radial_segments = 16
				dish.mesh = dm
				dish.position = Vector3(0, 2.8, 0)
				dish.rotation.x = -0.7
				dish.material_override = paper_mat
				prop.add_child(dish)
				_prop_cyl(prop, 0.05, 1.6, Vector3(0, 3.3, -0.55), ink_mat)
				_prop_sphere(prop, 0.16, Vector3(0, 4.1, -1.05), glow_mat)
			2:   # the rover parks here; the dressing builds it, one design with the driving one (2026-09-24)
				pass
			3:   # a half-buried probe with antennas and a blinking light
				_prop_sphere(prop, 1.1, Vector3(0, -0.35, 0), metal_mat)
				for ak in 3:
					var ant := MeshInstance3D.new()
					var am := CylinderMesh.new()
					am.top_radius = 0.03
					am.bottom_radius = 0.03
					am.height = 1.8
					ant.mesh = am
					ant.position = Vector3(cos(ak * 2.1) * 0.5, 1.2, sin(ak * 2.1) * 0.5)
					ant.rotation = Vector3(sin(ak * 2.1) * 0.5, 0.0, -cos(ak * 2.1) * 0.5)
					ant.material_override = ink_mat
					prop.add_child(ant)
				_prop_sphere(prop, 0.14, Vector3(0, 0.8, 0), alien_mat)
			_:   # a crew member looking up at the sky, and a planted flag
				_astronaut = Figure.new()
				prop.add_child(_astronaut)
				_astronaut.build(Palette.hud_colour("paper"), "board", 1.62, false)
				_astronaut.position = Vector3(0.3, 0, 0)
				_prop_cyl(prop, 0.05, 2.4, Vector3(-1.2, 1.2, 0), ink_mat)
				_prop_box(prop, Vector3(1.0, 0.6, 0.05), Vector3(-0.7, 2.1, 0), accent_mat)


func _prop_sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 10
	sm.rings = 5
	mi.mesh = sm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


## Outer space around the moon: drifting asteroids (some with a satellite, a beacon, a wreck),
## a ringed planet and a small moon on the horizon, and a UFO doing slow laps of the board.
func _build_asteroids() -> void:
	var g := director.graph
	var shadow := _shadow
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(g.id) + 17
	var rock_mat := CelMaterial.for_colour(Palette.map_colour("board", "rock"), shadow)
	var dark_mat := CelMaterial.for_colour(Palette.map_colour("board", "moon_dark"), shadow)
	var metal_mat := CelMaterial.for_colour(Palette.map_colour("board", "metal"), shadow)
	var accent_mat := CelMaterial.for_colour(Palette.map_colour("board", "accent"), shadow, 0.3)
	var ink_mat := CelMaterial.for_colour(Color.from_hsv(Palette.map_colour("board", "line").h, 0.45, 0.24), shadow)
	var glow_mat := CelMaterial.for_colour(Palette.hud_colour("meter"), shadow, 1.2)
	var alien_mat := CelMaterial.for_colour(Palette.map_colour("board", "alien"), shadow, 1.2)
	var paper_mat := CelMaterial.for_colour(Palette.hud_colour("paper"), shadow)
	var ast_n := roundi(14 * sqrt(_moon_density))   # more asteroids round a bigger board
	for i in ast_n:
		var a := float(i) / ast_n * TAU + rng.randf_range(-0.2, 0.2)
		var r := _bounds_radius * rng.randf_range(1.5, 2.1)
		var pos := _bounds_centre + Vector3(cos(a) * r, rng.randf_range(-9.0, 7.0), sin(a) * r * 0.9)
		var ast := Node3D.new()
		ast.position = pos
		ast.rotation = Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), 0.0)
		add_child(ast)
		var big := i < 8
		var size := rng.randf_range(1.8, 3.4) if big else rng.randf_range(0.6, 1.1)
		var body := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = size
		bm.height = size * 2.0
		bm.radial_segments = 7
		bm.rings = 4
		body.mesh = bm
		body.scale = Vector3(rng.randf_range(0.8, 1.3), rng.randf_range(0.7, 1.0), rng.randf_range(0.8, 1.3))
		body.material_override = rock_mat if i % 3 != 1 else dark_mat
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ast.add_child(body)
		if big:
			_prop_sphere(ast, size * 0.55, Vector3(size * 0.7, size * 0.3, 0), dark_mat)
			_prop_sphere(ast, size * 0.4, Vector3(-size * 0.5, -size * 0.4, size * 0.4), rock_mat)
			var prop := Node3D.new()
			prop.position = Vector3(0, size * 0.85, 0)
			ast.add_child(prop)
			match i % 4:
				0:   # satellite: body, two panels, a dish
					_prop_box(prop, Vector3(0.9, 0.9, 1.2), Vector3(0, 0.6, 0), metal_mat)
					_prop_box(prop, Vector3(3.2, 0.08, 1.0), Vector3(0, 0.6, 0), accent_mat)
					_prop_cyl(prop, 0.5, 0.2, Vector3(0, 1.25, 0), paper_mat)
				1:   # beacon
					_prop_cyl(prop, 0.08, 2.4, Vector3(0, 1.2, 0), ink_mat)
					_prop_sphere(prop, 0.35, Vector3(0, 2.6, 0), alien_mat)
				2:   # wrecked rocket, nose in the rock, its tail with the fins and bell in the air
					var wreck := Node3D.new()
					wreck.position = Vector3(0, 0.9, 0)
					wreck.rotation = Vector3(0.6, 0.0, 0.4)
					prop.add_child(wreck)
					_prop_cyl(wreck, 0.5, 2.6, Vector3.ZERO, paper_mat)
					_prop_cyl(wreck, 0.56, 0.3, Vector3(0, 1.15, 0), accent_mat)   # skirt at the tail
					var wbell := MeshInstance3D.new()
					var wbm := CylinderMesh.new()
					wbm.top_radius = 0.42
					wbm.bottom_radius = 0.24
					wbm.height = 0.36
					wbm.radial_segments = 12
					wbell.mesh = wbm
					wbell.position.y = 1.48
					wbell.material_override = ink_mat
					wreck.add_child(wbell)
					for fk in 3:
						var fa := fk * TAU / 3.0
						var fin := MeshInstance3D.new()
						var fm := PrismMesh.new()
						fm.size = Vector3(0.7, 1.0, 0.08)
						fm.left_to_right = 0.0
						fin.mesh = fm
						fin.position = Vector3(cos(fa) * 0.83, 0.8, sin(fa) * 0.83)
						fin.rotation.y = -fa
						fin.rotation.z = PI   # the tail is up: the straight edge stays against the body, the slope runs down
						fin.material_override = accent_mat
						wreck.add_child(fin)
				_:   # a lamp, because someone lives out here
					_prop_cyl(prop, 0.08, 2.2, Vector3(0, 1.1, 0), ink_mat)
					_prop_box(prop, Vector3(0.6, 0.3, 0.6), Vector3(0, 2.3, 0), ink_mat)
					_prop_box(prop, Vector3(0.44, 0.08, 0.44), Vector3(0, 2.12, 0), glow_mat)
		_islands.append({"node": ast, "base_y": pos.y, "phase": rng.randf_range(0.0, TAU), "spin": rng.randf_range(-0.12, 0.12)})


## Outer space's second chunk: the ringed planet and the small moon on the horizon, and the UFO.
func _build_horizon() -> void:
	var shadow := _shadow
	var metal_mat := CelMaterial.for_colour(Palette.map_colour("board", "metal"), shadow)
	var ink_mat := CelMaterial.for_colour(Color.from_hsv(Palette.map_colour("board", "line").h, 0.45, 0.24), shadow)
	# A ringed planet and a small moon on the horizon (no shadows: they are far).
	var planet := Node3D.new()
	planet.position = _bounds_centre + Vector3(-75.0, 36.0, -105.0)
	add_child(planet)
	var pb := MeshInstance3D.new()
	var pbm := SphereMesh.new()
	pbm.radius = 9.0
	pbm.height = 18.0
	pbm.radial_segments = 24
	pbm.rings = 12
	pb.mesh = pbm
	pb.material_override = CelMaterial.for_colour(Palette.map_colour("board", "planet"), shadow)
	pb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.add_child(pb)
	var band := MeshInstance3D.new()
	var bnm := TorusMesh.new()
	bnm.inner_radius = 8.6
	bnm.outer_radius = 9.15
	bnm.rings = 32
	bnm.ring_segments = 6
	band.mesh = bnm
	band.rotation.x = 0.35
	band.material_override = CelMaterial.for_colour(Palette.map_colour("board", "planet").darkened(0.18), shadow)
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.add_child(band)
	var ring := MeshInstance3D.new()
	var rgm := TorusMesh.new()
	rgm.inner_radius = 12.0
	rgm.outer_radius = 17.0
	rgm.rings = 48
	rgm.ring_segments = 4
	ring.mesh = rgm
	ring.scale = Vector3(1.0, 0.12, 1.0)
	ring.rotation = Vector3(0.45, 0.0, 0.25)
	ring.material_override = CelMaterial.for_colour(Palette.map_colour("board", "planet_ring"), shadow)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.add_child(ring)
	_planet = planet
	var little := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 3.2
	lm.height = 6.4
	lm.radial_segments = 14
	lm.rings = 7
	little.mesh = lm
	little.position = _bounds_centre + Vector3(70.0, 28.0, -85.0)
	little.material_override = CelMaterial.for_colour(Palette.map_colour("board", "moon"), shadow)
	little.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(little)
	# The UFO: a saucer with a glass dome and a ring of lights, doing laps.
	_ufo = Node3D.new()
	add_child(_ufo)
	var saucer := MeshInstance3D.new()
	var scm := CylinderMesh.new()
	scm.top_radius = 1.5
	scm.bottom_radius = 2.4
	scm.height = 0.55
	scm.radial_segments = 18
	saucer.mesh = scm
	saucer.material_override = metal_mat
	_ufo.add_child(saucer)
	var under := MeshInstance3D.new()
	var um := CylinderMesh.new()
	um.top_radius = 2.4
	um.bottom_radius = 0.9
	um.height = 0.5
	um.radial_segments = 18
	under.mesh = um
	under.position.y = -0.52
	under.material_override = ink_mat
	_ufo.add_child(under)
	var dome := MeshInstance3D.new()
	var dmm := SphereMesh.new()
	dmm.radius = 1.05
	dmm.height = 2.1
	dmm.radial_segments = 16
	dmm.rings = 8
	dome.mesh = dmm
	dome.position.y = 0.45
	dome.scale = Vector3(1.0, 0.75, 1.0)
	dome.material_override = CelMaterial.for_colour(Palette.hud_colour("meter"), shadow, 0.5)
	_ufo.add_child(dome)
	for k in 8:
		var lk := MeshInstance3D.new()
		var lkm := SphereMesh.new()
		lkm.radius = 0.16
		lkm.height = 0.32
		lkm.radial_segments = 8
		lkm.rings = 4
		lk.mesh = lkm
		lk.position = Vector3(cos(k * TAU / 8.0) * 2.05, -0.2, sin(k * TAU / 8.0) * 2.05)
		lk.material_override = CelMaterial.for_colour(Palette.hud_colour("score") if k % 2 == 0 else Palette.hud_colour("danger"), shadow, 1.6)
		_ufo.add_child(lk)


func _prop_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _prop_cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 8
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _tone_for(type: String) -> Color:
	match type:
		"ticket": return Palette.player_colour(3)
		"lose": return Palette.hud_colour("danger")
		"item": return Palette.player_colour(5)
		"shield": return Palette.hud_colour("meter")
		"heal": return Palette.map_colour("board", "heal")
		"start": return Palette.map_colour("board", "accent")
	return Palette.map_colour("board", "field")


func _build_tiles() -> void:
	var g := director.graph
	var shadow := Palette.map_colour("board", "shadow_tint")
	var plank_mat := CelMaterial.for_colour(Palette.map_colour("board", "field_dark"), shadow)
	for sid in g.ids():
		var s := g.get_space(sid)
		var tile := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.15
		cm.bottom_radius = 1.0
		cm.height = 0.42
		cm.radial_segments = 6
		tile.mesh = cm
		tile.position = s.position - Vector3(0, 0.21, 0)
		tile.rotation.y = deg_to_rad(30.0)
		tile.material_override = CelMaterial.for_colour(_tone_for(s.type), shadow)
		tile.set_meta("space_id", sid)
		add_child(tile)
		tiles[sid] = tile
		var under := MeshInstance3D.new()
		var um := CylinderMesh.new()
		um.top_radius = 0.95
		um.bottom_radius = 0.55
		um.height = 0.8
		um.radial_segments = 6
		under.mesh = um
		under.position = s.position - Vector3(0, 0.82, 0)
		under.rotation.y = deg_to_rad(30.0)
		under.material_override = CelMaterial.for_colour(Palette.map_colour("board", "counter_dark"), shadow)
		add_child(under)
		for n in s.next:
			var t := g.get_space(n)
			var a := s.position
			var b := t.position
			var mid := (a + b) * 0.5 - Vector3(0, 0.12, 0)
			var plank := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.5, 0.14, maxf(0.2, (b - a).length() - 2.0))
			plank.mesh = bm
			plank.material_override = plank_mat
			add_child(plank)
			plank.global_position = mid
			if (b - a).length() > 0.01:
				plank.look_at(b, Vector3.UP)
	# Board bounds, for the Tab map view, the asteroids and the UFO.
	var lo := Vector3(1e9, 0, 1e9)
	var hi := Vector3(-1e9, 0, -1e9)
	for sid in g.ids():
		var sp := g.get_space(sid).position
		lo.x = minf(lo.x, sp.x)
		lo.z = minf(lo.z, sp.z)
		hi.x = maxf(hi.x, sp.x)
		hi.z = maxf(hi.z, sp.z)
	_bounds_centre = (lo + hi) * 0.5
	_bounds_radius = maxf(hi.x - lo.x, hi.z - lo.z) * 0.5


## The markers over the special spaces, the goal ring, the toy beacon and the active pulse.
func _build_markers() -> void:
	var g := director.graph
	var shadow := _shadow
	for sid in g.ids():
		_build_marker(g.get_space(sid), shadow)
	goal_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.2
	tm.outer_radius = 1.45
	tm.rings = 32
	tm.ring_segments = 8
	goal_ring.mesh = tm
	goal_ring.material_override = CelMaterial.for_colour(Palette.hud_colour("paper"), shadow, 1.0)
	add_child(goal_ring)
	# The toy beacon: a capsule floating over the space the vending machine stands beside, visible
	# from anywhere (the machine itself is on the pad past the rim, lit when it is the live one).
	goal_beacon = Node3D.new()
	var top := MeshInstance3D.new()
	var tsm := SphereMesh.new()
	tsm.radius = 0.42
	tsm.height = 0.84
	tsm.radial_segments = 16
	tsm.rings = 8
	tsm.is_hemisphere = true
	top.mesh = tsm
	top.material_override = CelMaterial.for_colour(Palette.hud_colour("score"), shadow, 0.4)
	goal_beacon.add_child(top)
	var bottom := MeshInstance3D.new()
	bottom.mesh = tsm
	bottom.rotation.x = PI
	bottom.material_override = CelMaterial.for_colour(Palette.hud_colour("paper"), shadow)
	goal_beacon.add_child(bottom)
	var seam := MeshInstance3D.new()
	var ssm := TorusMesh.new()
	ssm.inner_radius = 0.4
	ssm.outer_radius = 0.46
	ssm.rings = 24
	ssm.ring_segments = 6
	seam.mesh = ssm
	seam.material_override = CelMaterial.for_colour(Color.from_hsv(Palette.map_colour("board", "line").h, 0.45, 0.24), shadow)
	goal_beacon.add_child(seam)
	_spark = MeshInstance3D.new()
	var spm := SphereMesh.new()
	spm.radius = 0.11
	spm.height = 0.22
	spm.radial_segments = 8
	spm.rings = 4
	_spark.mesh = spm
	_spark.position = Vector3(0, 0.62, 0)
	_spark.material_override = CelMaterial.for_colour(Palette.hud_colour("score"), shadow, 1.6)
	goal_beacon.add_child(_spark)
	var badge := Label3D.new()
	badge.text = "TOY"
	badge.font_size = 64
	badge.pixel_size = 0.006
	badge.outline_size = 8
	badge.modulate = Palette.hud_colour("paper")
	badge.outline_modulate = Palette.map_colour("board", "line")
	badge.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.position = Vector3(0, -0.72, 0)
	goal_beacon.add_child(badge)
	add_child(goal_beacon)
	# Pulse under whoever's turn it is.
	active_pulse = MeshInstance3D.new()
	var apm := TorusMesh.new()
	apm.inner_radius = 0.7
	apm.outer_radius = 0.82
	apm.rings = 32
	apm.ring_segments = 6
	active_pulse.mesh = apm
	active_pulse.material_override = CelMaterial.for_colour(Palette.map_colour("board", "accent"), shadow, 1.0)
	active_pulse.visible = false
	add_child(active_pulse)


func _ensure_pawn(p: BoardState.PlayerState) -> BoardPawn:
	if pawns.has(p.peer_id):
		return pawns[p.peer_id]
	var pawn := BoardPawn.new()
	pawn.name = "Pawn_%d" % p.peer_id
	add_child(pawn)
	pawn.setup(p.peer_id, Palette.player_colour(p.colour_index), p.display_name)
	pawns[p.peer_id] = pawn
	pawn.snap_to(_slot_position(p.space, p.peer_id))
	_face_travel(pawn, p.space)
	return pawn


## Face the way the walkway runs from `space_id` (its first next space). A fresh pawn stood
## facing north whatever its walkway did (Sean, 2026-09-23: "when the game starts they are
## facing the wrong way"); the hops turn it the same way once it moves.
func _face_travel(pawn: BoardPawn, space_id: String) -> void:
	if director == null or director.graph == null:
		return
	var nx := director.graph.next_of(space_id)
	if nx.is_empty():
		return
	var d := director.space_position(str(nx[0])) - pawn.global_position
	if Vector2(d.x, d.z).length() > 0.2:
		pawn.face_angle(atan2(d.z, d.x))


## World point just over a pawn's cap, where the HUD hangs its name tag; INF when unknown.
func pawn_tag_anchor(peer_id: int) -> Vector3:
	var pawn: BoardPawn = pawns.get(peer_id, null)
	if pawn == null or not is_instance_valid(pawn):
		return Vector3.INF
	return pawn.global_position + Vector3(0, 2.15, 0)


## Pawns sharing a space stand in a small circle.
func _slot_position(space_id: String, peer_id: int) -> Vector3:
	var base := director.space_position(space_id)
	var others := []
	if director.state != null:
		for q in director.state.players:
			if q.space == space_id:
				others.append(q.peer_id)
	if others.size() <= 1:
		return base
	var idx := others.find(peer_id)
	var a := float(idx) / float(others.size()) * TAU
	return base + Vector3(cos(a), 0.0, sin(a)) * 0.55


func _on_state(state: BoardState) -> void:
	if not built:
		return   # applied by build_visuals() once the look is there; the director keeps the state
	var first := not _state_shown
	_state_shown = true
	for p in state.players:
		_ensure_pawn(p)
	# Existing pawns are moved by the events that follow this state. Snapping them here showed
	# every pawn at its destination for a frame before the hop (Sean's note 2); the queue's
	# end-of-events snap reconciles instead.
	# The goal moves with the toy event that follows this state (the state lands first, and the
	# machine that sold must stay lit until the capsule has landed); the first state and the end of
	# a playback place it from the state.
	if goal_ring != null and state.goal != "" and first:
		_show_goal(state.goal)
	var ap := state.active_player()
	if ap != null and first:
		_focus(director.space_position(ap.space))
	if first:
		_draw_blood_from_state()
		_sync_shields()
	# Low HP bleeds until a respawn refills it.
	var low := int(director.cfg.get("bleed_below_hp", 10))
	for p in state.players:
		var pawn: BoardPawn = pawns.get(p.peer_id, null)
		if pawn != null:
			pawn.set_bleeding(p.hp <= low)


func _snap_all() -> void:
	if director.state == null:
		return
	for p in director.state.players:
		if pawns.has(p.peer_id):
			(pawns[p.peer_id] as BoardPawn).snap_to(_slot_position(p.space, p.peer_id))


## True while the view is still playing events (hops, dice, cards); the HUD holds its buttons
## until the pawn has actually arrived where the state says it is.
func is_animating() -> bool:
	return not built or _playing or not _queue.is_empty()


func _on_events(events: Array) -> void:
	_queue.append_array(events)
	if not _playing and built:
		_play_next()   # events that land mid-build wait; build_visuals() starts them


func _play_next() -> void:
	if _queue.is_empty():
		_playing = false
		_snap_all()
		# A goal the events did not move (a reconnect, a state without a toy) is placed now.
		if director.state != null and director.state.goal != "" and director.state.goal != _goal_spot:
			_show_goal(director.state.goal)
		_draw_blood_from_state()
		_sync_shields()
		return
	_playing = true
	var e: Dictionary = _queue.pop_front()
	var wait := 0.05
	match str(e.get("kind", "")):
		"turn":
			var p := director.state.player(int(e["peer"])) if director.state != null else null
			if p != null:
				_focus(director.space_position(p.space))
			Events.board_turn_shown.emit(int(e["peer"]))
			wait = 0.3
		"roll":
			set_free_cam(false)   # the roll brings the camera home
			var pawn: BoardPawn = pawns.get(int(e["peer"]), null)
			var v := int(e["value"])
			var raw := int(e.get("roll", v))
			if pawn != null and not Game.headless:
				var base := pawn.global_position
				var dice := BoardDice.new()
				dice.name = "Dice"
				add_child(dice)
				dice.setup(Palette.hud_colour("score"), Palette.map_colour("board", "line"), Palette.map_colour("board", "shadow_tint"))
				var rng := RandomNumberGenerator.new()
				rng.seed = (director.state.turn_serial if director.state != null else 0) * 7919 + v
				# Beside the pawn, to the camera's right, the number reading upright from the camera.
				var right := Vector3(cos(_cam_yaw), 0.0, -sin(_cam_yaw))
				var forward := -Vector3(sin(_cam_yaw), 0.0, cos(_cam_yaw))
				var spot := base + right * 1.5 - forward * 0.6
				var to := spot + Vector3.UP * BoardDice.INRADIUS
				# On the moon's ground beside the tile, not floating at tile height (Sean, 2026-09-22),
				# when the spot is on the slab and clear of a crater; else (an annex, the rim) at the
				# tile's height as before.
				var on_ground := _slab != null and _slab.inside(spot.x, spot.z, 0.96)
				for cr in _craters:
					if Vector2(spot.x - cr.x, spot.z - cr.y).length() < cr.z + 0.6:
						on_ground = false
				Log.debug("board", "dice ground: f %.2f on_ground %s" % [_slab.f_of(spot.x, spot.z) if _slab != null else 9.9, on_ground])
				if on_ground:
					to.y = _slab.centre.y + MOON_TOP + BoardDice.INRADIUS
				dice.roll(base + Vector3(0.3, 2.8, 0.2), to, raw, rng, forward)
				dice.landed.connect(func(_val: int):
					Audio.play("land", -9.0)
					Events.board_dice_landed.emit(v)
				)
				_focus(base)
				Audio.play("dice", -2.0)
				wait = BoardDice.T_AIR + BoardDice.T_SETTLE + 0.5
			else:
				Events.board_dice_landed.emit(v)
				wait = 0.6
		"move":
			var pawn: BoardPawn = pawns.get(int(e["peer"]), null)
			var path: Array = e["path"]
			if pawn != null:
				_cam_fast = true
				for sid in path:
					if not is_inside_tree():
						_playing = false
						return
					var to := director.space_position(str(sid))
					pawn.hop_to(to, _hop)
					_focus(to)
					await get_tree().create_timer(_hop).timeout
				_cam_fast = false
				if not Game.headless:
					Burst.spawn(self, pawn.global_position + Vector3(0, 0.2, 0), pawn.colour, 0.45, 0.18, 7)
			wait = 0.1
		"tickets":
			_float_label(int(e["peer"]), ("+%d" if int(e["delta"]) >= 0 else "%d") % int(e["delta"]),
				Palette.player_colour(3) if int(e["delta"]) >= 0 else Palette.hud_colour("danger"))
			Audio.play("ticket" if int(e["delta"]) >= 0 else "hurt", -6.0)
			wait = 0.5
		"heal":
			_float_label(int(e["peer"]), "+%d HP" % int(e["delta"]), Palette.map_colour("board", "heal"))
			Audio.play("heal", -6.0)
			wait = 0.5
		"item":
			# The HUD pops the item's icon over the pawn's head (Sean: an icon, not the name); a
			# minigame reward shows when the winner's turn comes instead (the results card is up now).
			Events.board_item_picked.emit(int(e["peer"]), str(e["item"]), bool(e.get("reward", false)))
			if str(e["item"]) == "shield":
				var sp: BoardPawn = pawns.get(int(e["peer"]), null)
				if sp != null:
					sp.set_shield(true)
			Audio.play("ui_click", -2.0)
			wait = 0.5 if not bool(e.get("reward", false)) else 0.1
		"item_used":
			_float_label(int(e["peer"]), str(e["item"]).to_upper() + "!", Palette.hud_colour("danger"))
			Audio.play("dice", 0.0)
			wait = 0.15 if str(e["item"]) in ["laser", "bomb", "claw", "portal"] else 0.5
		"laser":
			# The shooter turns to the aim and draws, the beam flashes down the line, and every
			# player in it flinches, bleeds and loses HP; a downed one comes back at the annex.
			var shooter: BoardPawn = pawns.get(int(e["peer"]), null)
			var a := float(e["aim"])
			var length := float(e["length"])
			var hits: Array = e.get("hits", [])
			var deaths := 0
			if shooter != null:
				shooter.face_angle(a)
				shooter.show_gun(true)
				_focus(shooter.global_position)
				await get_tree().create_timer(0.3).timeout
				if not is_inside_tree():
					_playing = false
					return
				if not Game.headless:
					_flash_beam(shooter.gun_tip(), a, length)
				Audio.play("laser", -2.0)
				for h in hits:
					var victim: BoardPawn = pawns.get(int(h["peer"]), null)
					if victim == null:
						continue
					if bool(h.get("shielded", false)):
						continue   # the shield event that follows shows it
					victim.flinch()
					victim.hit_bleed()
					_blood_burst(victim.global_position)
					if h.has("blood"):
						_draw_blood(h["blood"])
					_float_label(victim.peer_id, "-%d" % int(h["damage"]), Palette.hud_colour("danger"))
					Audio.play("splat", -4.0)
					if bool(h.get("dead", false)):
						deaths += 1
				if deaths > 0:
					await get_tree().create_timer(0.7).timeout
					if not is_inside_tree():
						_playing = false
						return
					for h in hits:
						if not bool(h.get("dead", false)):
							continue
						var victim: BoardPawn = pawns.get(int(h["peer"]), null)
						if victim == null:
							continue
						_float_label(victim.peer_id, "DOWN!", Palette.hud_colour("danger"))
						if not Game.headless:
							Burst.spawn(self, victim.global_position + Vector3(0, 0.6, 0), Palette.player_colour(0), 0.8, 0.3, 8)
						victim.snap_to(director.space_position(str(h["respawn"])))
						victim.set_bleeding(false)
						Audio.play("respawn", -4.0)
						if int(h.get("tickets", 0)) > 0:
							_float_label(shooter.peer_id, "+%d" % int(h["tickets"]), Palette.player_colour(3))
				get_tree().create_timer(1.0).timeout.connect(func():
					if is_instance_valid(shooter) and not _aiming:
						shooter.show_gun(false))
			wait = 0.9 + 0.5 * deaths
		"bomb":
			# The thrower turns, winds up and throws; the bomb arcs to the landing point and goes off;
			# everyone in the blast flinches, bleeds, loses HP and is shoved back along the walkway;
			# a downed one comes back at the annex.
			var thrower: BoardPawn = pawns.get(int(e["peer"]), null)
			var at_arr: Array = e["at"]
			var at := Vector3(float(at_arr[0]), float(at_arr[1]), float(at_arr[2]))
			var radius := float(e["radius"])
			var hits: Array = e.get("hits", [])
			var deaths := 0
			if thrower != null:
				var d := at - thrower.global_position
				if Vector2(d.x, d.z).length() > 0.2:
					thrower.face_angle(atan2(d.z, d.x))
				thrower.throw()
				_focus(thrower.global_position.lerp(at, 0.5))
				Audio.play("bomb_throw", -6.0)
				await get_tree().create_timer(0.28).timeout
				if not is_inside_tree():
					_playing = false
					return
				if not Game.headless:
					await _fly_bomb(thrower.hand_position(), at, 0.62)
				else:
					await get_tree().create_timer(0.62).timeout
				if not is_inside_tree():
					_playing = false
					return
				if not Game.headless:
					_blast(at, radius)
				Audio.play("bomb_blast", 0.0)
				var longest := 0
				for h in hits:
					var victim: BoardPawn = pawns.get(int(h["peer"]), null)
					if victim == null or bool(h.get("shielded", false)):
						continue   # the shield event that follows shows it
					victim.flinch()
					victim.hit_bleed()
					_blood_burst(victim.global_position)
					if h.has("blood"):
						_draw_blood(h["blood"])
					_float_label(victim.peer_id, "-%d" % int(h["damage"]), Palette.hud_colour("danger"))
					if bool(h.get("dead", false)):
						deaths += 1
					var knock: Array = h.get("knock", [])
					if not knock.is_empty():
						longest = maxi(longest, knock.size())
						_knock_back(victim, knock)
				if longest > 0:
					await get_tree().create_timer(_hop * 0.8 * longest + 0.1).timeout
					if not is_inside_tree():
						_playing = false
						return
				if deaths > 0:
					await get_tree().create_timer(0.5).timeout
					if not is_inside_tree():
						_playing = false
						return
					for h in hits:
						if not bool(h.get("dead", false)):
							continue
						var victim: BoardPawn = pawns.get(int(h["peer"]), null)
						if victim == null:
							continue
						_float_label(victim.peer_id, "DOWN!", Palette.hud_colour("danger"))
						if not Game.headless:
							Burst.spawn(self, victim.global_position + Vector3(0, 0.6, 0), Palette.player_colour(0), 0.8, 0.3, 8)
						victim.snap_to(director.space_position(str(h["respawn"])))
						victim.set_bleeding(false)
						Audio.play("respawn", -4.0)
						if int(h.get("tickets", 0)) > 0 and victim != thrower:
							_float_label(thrower.peer_id, "+%d" % int(h["tickets"]), Palette.player_colour(3))
			wait = 0.6 + 0.4 * deaths
		"portal":
			# A portal opens a step ahead of the user, who skates in and steps out of a second one
			# beside the mark, shoves them through it, and takes their space while they come out
			# of the first portal where the user stood (Sean's description, in that order).
			var user: BoardPawn = pawns.get(int(e["peer"]), null)
			var mark: BoardPawn = pawns.get(int(e["target"]), null)
			var from_pos := director.space_position(str(e["from"]))
			var to_pos := director.space_position(str(e["to"]))
			if user != null and mark != null and not Game.headless:
				var dir := mark.global_position - user.global_position
				dir.y = 0.0
				dir = dir.normalized() if dir.length() > 0.05 else Vector3.RIGHT
				var p1 := user.global_position + dir * 1.4
				var p2 := mark.global_position - dir * 1.4
				user.face_angle(atan2(dir.z, dir.x))
				var ring1 := _open_portal(p1, dir)
				Audio.play("portal", -4.0)
				_focus(p1)
				await get_tree().create_timer(0.35).timeout
				if not is_inside_tree():
					_playing = false
					return
				user.hop_to(p1, 0.3)
				await get_tree().create_timer(0.3).timeout
				await _vanish(user, true)
				var ring2 := _open_portal(p2, dir)
				Audio.play("portal", -4.0)
				_focus(mark.global_position)
				await get_tree().create_timer(0.3).timeout
				if not is_inside_tree():
					_playing = false
					return
				user.snap_to(p2)
				user.face_angle(atan2(dir.z, dir.x))
				await _vanish(user, false)
				await get_tree().create_timer(0.15).timeout
				user.hop_to(p2 + dir * 0.6, 0.15)
				await get_tree().create_timer(0.15).timeout
				mark.flinch()
				Audio.play("swap", -6.0)
				mark.hop_to(p2, 0.3, false)
				await get_tree().create_timer(0.3).timeout
				await _vanish(mark, true)
				_close_portal(ring2)
				if not is_inside_tree():
					_playing = false
					return
				mark.snap_to(from_pos)
				await _vanish(mark, false)
				_close_portal(ring1)
				user.hop_to(to_pos, 0.25)
				await get_tree().create_timer(0.25).timeout
				_focus(to_pos)
				Audio.play("respawn", -8.0)
			else:
				if user != null:
					user.snap_to(to_pos)
				if mark != null:
					mark.snap_to(from_pos)
			wait = 0.4
		"claw":
			# The claw: the thief turns to the aim, the arm comes up, the claw flies out on its cable
			# along the line to the first player in it (or to the end of its reach and back empty),
			# who flinches; it retracts with the item, whose icon pops over the thief's head.
			var thief: BoardPawn = pawns.get(int(e["peer"]), null)
			var mark: BoardPawn = pawns.get(int(e.get("target", 0)), null)
			var a := float(e["aim"])
			var length := float(e["length"])
			if thief != null:
				thief.face_angle(a)
				thief.show_claw(true)
				var end := thief.global_position + Vector3(cos(a), 0.0, sin(a)) * length + Vector3(0, 1.05, 0)
				if mark != null:
					end = mark.global_position + Vector3(0, 1.05, 0)
				_focus((thief.global_position + end) * 0.5)
				await get_tree().create_timer(0.3).timeout
				if not is_inside_tree():
					_playing = false
					return
				Audio.play("claw", -4.0)
				var fly := 0.2 + 0.02 * thief.global_position.distance_to(end)
				if not Game.headless:
					await thief.claw_to(end, fly)
				else:
					await get_tree().create_timer(fly).timeout
				if mark != null:
					mark.flinch()
					if not Game.headless:
						Burst.spawn(self, end, mark.colour, 0.5, 0.2, 7)
				else:
					_float_label(thief.peer_id, "NOTHING!", Palette.hud_colour("paper"))
				if not Game.headless:
					await thief.claw_back(0.32)
				else:
					await get_tree().create_timer(0.32).timeout
				thief.show_claw(false)
				if mark == null or bool(e.get("shielded", false)):
					pass   # the shield event that follows shows it
				elif str(e["item"]) != "":
					Events.board_item_picked.emit(thief.peer_id, str(e["item"]), false)
					_float_label(mark.peer_id, "-%s" % str(e["item"]).to_upper(), Palette.hud_colour("danger"))
					Audio.play("ticket", -6.0)
				elif int(e.get("tickets", 0)) > 0:
					_float_label(mark.peer_id, "-%d" % int(e["tickets"]), Palette.hud_colour("danger"))
					_float_label(thief.peer_id, "+%d" % int(e["tickets"]), Palette.player_colour(3))
					Audio.play("ticket", -6.0)
			wait = 0.5
		"toy":
			var pawn: BoardPawn = pawns.get(int(e["peer"]), null)
			var col := Palette.hud_colour("score")
			var buyer := director.state.player(int(e["peer"])) if director.state != null else null
			if buyer != null:
				col = Palette.player_colour(buyer.colour_index)
			if pawn != null and not Game.headless:
				Burst.spawn(self, pawn.global_position + Vector3(0, 1.0, 0), Palette.hud_colour("score"), 1.2, 0.5, 10)
			_float_label(int(e["peer"]), "TOY!", Palette.hud_colour("score"))
			Audio.play("kill", 0.0)
			if _dressing != null and pawn != null:
				_dressing.vend(str(e.get("spot", "")), pawn.global_position, col)
			# The machine that sold stays lit until the capsule has landed, then the goal moves.
			var new_spot := str(e["new_spot"])
			get_tree().create_timer(1.25).timeout.connect(func() -> void:
				if is_inside_tree():
					_show_goal(new_spot))
			wait = 1.3
		"shield":
			var pawn: BoardPawn = pawns.get(int(e["peer"]), null)
			if pawn != null:
				pawn.set_shield(false)
				if not Game.headless:
					Burst.spawn(self, pawn.global_position + Vector3(0, 0.8, 0), Palette.player_colour(5), 1.1, 0.45, 12)
				_focus(pawn.global_position)
			_float_label(int(e["peer"]), "SHIELDED!", Palette.player_colour(5))
			Audio.play("land", 0.0)
			wait = 0.8
		"shuttle":
			# The rocket ride (Sean, 2026-09-24): the rider walks to the rocket and climbs in, it
			# lifts off with a flame and arcs over the base with the camera riding along, sets down
			# beside the landing spot, the rider steps out onto it, and the rocket flies itself home
			# for the next fare.
			var rider: BoardPawn = pawns.get(int(e["peer"]), null)
			if rider != null and _shuttle != null:
				if _shuttle_tween != null and _shuttle_tween.is_valid():
					_shuttle_tween.kill()
				_shuttle_flame.visible = false
				_shuttle.transform = Transform3D.IDENTITY
				var from := director.space_position(str(e["from"]))
				var to := director.space_position(str(e["to"]))
				_float_label(rider.peer_id, "-%d" % int(e["price"]), Palette.hud_colour("danger"))
				var foot := _shuttle_home + (from - _shuttle_home).normalized() * 1.5
				foot.y = from.y
				_cam_fast = true
				rider.hop_to(foot, 0.5)
				_focus(_shuttle_home + Vector3(0, 1.0, 0))
				await get_tree().create_timer(0.55).timeout
				if not is_inside_tree():
					_playing = false
					return
				await _vanish(rider, true)
				Audio.play("rocket", -4.0)
				_shuttle_flame.visible = true
				_shuttle_follow = true
				var land := Vector3(to.x, _slab.centre.y + MOON_TOP, to.z)
				var inward := (Vector3(_slab.centre.x, 0, _slab.centre.z) - Vector3(to.x, 0, to.z)).normalized()
				land += inward * 2.6
				var home := _shuttle_home
				var tw := create_tween()
				tw.tween_method(func(t: float): _fly(home, land, t), 0.0, 1.0, 3.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				await tw.finished
				if not is_inside_tree():
					_playing = false
					return
				_shuttle_follow = false
				_shuttle_flame.visible = false
				_cam_fast = false
				rider.snap_to(to)
				await _vanish(rider, false)
				if not is_inside_tree():
					_playing = false
					return
				if not Game.headless:
					Burst.spawn(self, rider.global_position + Vector3(0, 0.2, 0), rider.colour, 0.45, 0.18, 7)
				Audio.play("land", -6.0)
				_focus(to)
				_shuttle_return(land, home)
			wait = 0.4
		"choose":
			var opts: Array = e["options"]
			_fork_focus = opts
			if bool(e.get("shuttle", false)) and _shuttle != null and opts.size() >= 2:
				# The rocket's offer: the pad and the rocket in one look.
				_fork_focus = []
				_focus((director.space_position(str(opts[0])) + _shuttle_home) * 0.5 + Vector3(0, 0.6, 0))
				wait = 0.1
			elif opts.size() >= 2:
				# Stand behind the fork looking down the middle of the two paths, so LEFT and
				# RIGHT are on the left and right of the screen.
				var pawn: BoardPawn = pawns.get(int(e["peer"]), null)
				var mid := (director.space_position(str(opts[0])) + director.space_position(str(opts[1]))) * 0.5
				_focus(mid)
			wait = 0.2
		"minigame":
			wait = 0.3
		"finished":
			wait = 0.3
	if not is_inside_tree():
		_playing = false
		return
	await get_tree().create_timer(wait).timeout
	if not is_inside_tree():
		_playing = false
		return
	_play_next()


## The thrown bomb: a dark sphere with a cap and a spark, along a parabola from the hand to the
## landing point, tumbling; gone when it lands.
func _fly_bomb(from: Vector3, to: Vector3, seconds: float) -> void:
	var shadow := Palette.map_colour("board", "shadow_tint")
	var bomb := Node3D.new()
	add_child(bomb)
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.24
	sm.height = 0.48
	sm.radial_segments = 12
	sm.rings = 6
	body.mesh = sm
	body.material_override = CelMaterial.for_colour(Color.from_hsv(0.62, 0.35, 0.16), shadow)
	bomb.add_child(body)
	var cap := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(0.12, 0.08, 0.12)
	cap.mesh = cb
	cap.position.y = 0.26
	cap.material_override = CelMaterial.for_colour(Palette.hud_colour("paper"), shadow)
	bomb.add_child(cap)
	var spark := MeshInstance3D.new()
	var ss := SphereMesh.new()
	ss.radius = 0.07
	ss.height = 0.14
	ss.radial_segments = 6
	ss.rings = 3
	spark.mesh = ss
	spark.position = Vector3(0.08, 0.4, 0.0)
	spark.material_override = CelMaterial.for_colour(Palette.hud_colour("score"), shadow, 1.6)
	bomb.add_child(spark)
	bomb.global_position = from
	var tw := create_tween()
	tw.tween_method(_bomb_arc.bind(bomb, from, to), 0.0, 1.0, seconds)
	await tw.finished
	if is_instance_valid(bomb):
		bomb.queue_free()


func _bomb_arc(t: float, bomb: Node3D, from: Vector3, to: Vector3) -> void:
	if not is_instance_valid(bomb):
		return
	var p := from.lerp(to, t)
	p.y += 2.4 * 4.0 * t * (1.0 - t)
	bomb.global_position = p
	bomb.rotation.z = t * TAU * 1.5


## The blast: two bursts and a ring racing out to the blast's radius.
func _blast(at: Vector3, radius: float) -> void:
	Burst.spawn(self, at + Vector3(0, 0.5, 0), Palette.hud_colour("danger"), radius * 0.55, 0.42, 12)
	Burst.spawn(self, at + Vector3(0, 0.9, 0), Palette.hud_colour("score"), radius * 0.3, 0.25, 8)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.2
	tm.outer_radius = 0.42
	tm.rings = 48
	tm.ring_segments = 6
	ring.mesh = tm
	var m := _flat_mat(Color(Palette.hud_colour("danger"), 0.9))
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = at + Vector3(0, 0.08, 0)
	ring.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * (radius / 0.31), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.34)
	tw.chain().tween_callback(ring.queue_free)


## A shove backwards along the walkway, one space at a time, still facing the blast.
func _knock_back(victim: BoardPawn, knock: Array) -> void:
	for sid in knock:
		if not is_inside_tree() or not is_instance_valid(victim):
			return
		victim.hop_to(director.space_position(str(sid)), _hop * 0.8, false)
		await get_tree().create_timer(_hop * 0.8).timeout


## The menu's marbled swirl (Sean: "the exact vibe", untouched), rendered small into a viewport
## once, for the inside of every portal.
func _swirl_texture() -> Texture2D:
	if _swirl_vp == null:
		_swirl_vp = SubViewport.new()
		_swirl_vp.size = Vector2i(256, 384)
		_swirl_vp.disable_3d = true
		_swirl_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(_swirl_vp)
		var bg := UiStyle.swirl_background()
		bg.size = Vector2(256, 384)
		_swirl_vp.add_child(bg)
	return _swirl_vp.get_texture()


## A standing portal facing `dir` (Sean: a rectangle, with the main menu's swirl inside): a
## framed doorway a pawn fits through, the swirl moving on its face, opening with a pop.
func _open_portal(pos: Vector3, dir: Vector3) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	var w := 1.5
	var h := 2.3
	var t := 0.12
	node.global_position = pos + Vector3(0, h * 0.5 + 0.02, 0)
	if Vector2(dir.x, dir.z).length() > 0.01:
		node.look_at(node.global_position + Vector3(dir.x, 0.0, dir.z), Vector3.UP)
	var col := Palette.player_colour(5)
	var shadow := Palette.map_colour("board", "shadow_tint")
	var frame := CelMaterial.for_colour(col, shadow, 1.2)
	var stud := CelMaterial.for_colour(Palette.hud_colour("paper"), shadow, 0.6)
	_prop_box(node, Vector3(w + t, t, t), Vector3(0, h * 0.5, 0), frame)
	_prop_box(node, Vector3(w + t, t, t), Vector3(0, -h * 0.5, 0), frame)
	_prop_box(node, Vector3(t, h, t), Vector3(-w * 0.5, 0, 0), frame)
	_prop_box(node, Vector3(t, h, t), Vector3(w * 0.5, 0, 0), frame)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			_prop_box(node, Vector3(t * 1.6, t * 1.6, t * 1.3), Vector3(sx * w * 0.5, sy * h * 0.5, 0), stud)
	var face := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w - t * 0.5, h - t * 0.5)
	face.mesh = qm
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fmat.albedo_texture = _swirl_texture()
	fmat.render_priority = 2
	face.material_override = fmat
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(face)
	node.scale = Vector3.ONE * 0.05
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Burst.spawn(self, node.global_position, col, 0.9, 0.3, 9)
	return node


func _close_portal(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector3.ONE * 0.05, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(node.queue_free)


## A pawn shrinks into a portal (`out`) or grows back out of one.
func _vanish(pawn: BoardPawn, out: bool) -> void:
	if out:
		pawn.scale = Vector3.ONE
	else:
		pawn.scale = Vector3.ONE * 0.02
	var tw := pawn.create_tween()
	tw.tween_property(pawn, "scale", Vector3.ONE * (0.02 if out else 1.0), 0.16).set_trans(Tween.TRANS_QUAD)
	await tw.finished


## Every pawn's aura agrees with the state's shields (the first state, and the end of a playback:
## the events between animate the changes).
func _sync_shields() -> void:
	if director.state == null:
		return
	for p in director.state.players:
		var pawn: BoardPawn = pawns.get(p.peer_id, null)
		if pawn != null:
			pawn.set_shield(p.items.has("shield"))


func _float_label(peer_id: int, text: String, colour: Color) -> void:
	var pawn: BoardPawn = pawns.get(peer_id, null)
	if pawn == null or Game.headless:
		return
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.008
	l.outline_size = 16
	l.modulate = colour
	l.outline_modulate = Palette.map_colour("board", "line")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.no_depth_test = false
	add_child(l)
	l.global_position = pawn.global_position + Vector3(0, 2.6, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position:y", l.global_position.y + 1.4, 1.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.4)
	tw.tween_property(l, "outline_modulate:a", 0.0, 1.0).set_delay(0.4)   # or the ink shows through the fade
	tw.chain().tween_callback(l.queue_free)


func _focus(point: Vector3) -> void:
	_cam_look = point


## Look at a player's pawn: the HUD's target mode sends the camera to whoever is targeted.
func focus_peer(peer_id: int) -> void:
	var pawn: BoardPawn = pawns.get(peer_id, null)
	if pawn != null:
		_focus(pawn.global_position)


static func _rotate_toward_angle(from: float, to: float, max_step: float) -> float:
	var d := wrapf(to - from, -PI, PI)
	return from + clampf(d, -max_step, max_step)


func _process(delta: float) -> void:
	if camera == null:
		return
	# Close on whoever's turn it is, Pummel Party style: about 9 m out, 42° down, sitting
	# behind the pawn along its heading so the spaces ahead fill the frame. The heading eases
	# at most ~100°/s so corners swing, never snap.
	_cam_yaw = _rotate_toward_angle(_cam_yaw, _cam_yaw_target, delta * 1.8)
	if _aiming:
		var pawn: BoardPawn = pawns.get(_aim_peer, null)
		if pawn != null and _throw:
			_update_throw(pawn)
		elif pawn != null:
			_update_aim(pawn)
			pawn.face_angle(_aim)
			if _aim_kind == "claw":
				_place_beam(pawn.hand_position(), _aim, _aim_len, 0.05, 0.8, Palette.hud_colour("paper"))
			else:
				_place_beam(pawn.gun_tip(), _aim, _aim_len, 0.07, 0.9)
	# The free camera: only on the local player's turn before the roll; WASD slides the look point
	# over the map at 16 m/s, never off the slab; the camera sits a little further back.
	if _free and not (director.state != null and director.is_local_turn() and director.state.phase == BoardState.PHASE_TURNS):
		_free = false
	if Game.args.has("free_cam_test") and director.state != null and director.is_local_turn():
		_free_test_t += delta
		if _free_test_t >= 1.5 and not _free:
			set_free_cam(true)
		if _free_test_t >= 2.0:
			Input.action_press("move_back")
			Input.action_press("move_left")
	if _free:
		var dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if dir.length() > 0.0 and not Game.is_paused():
			var next := _free_look + Vector3(dir.x, 0.0, dir.y) * 16.0 * delta
			if _slab == null or _slab.inside(next.x, next.z, 0.95):
				_free_look = next
		_cam_look = _free_look
	_cam_zoom = move_toward(_cam_zoom, 2.6 if _shuttle_follow else (1.6 if _free else 1.0), delta * 1.6)
	var desired_pos := _cam_look + Vector3(sin(_cam_yaw) * 6.8, 6.2, cos(_cam_yaw) * 6.8) * _cam_zoom
	var look := _cam_look
	if Game.args.has("board_overview"):
		# Harness: the whole board from above, for layout screenshots (2.8 × and 2.0 × the
		# bounds radius: the (0, 64, 46) that framed the 65-space board).
		desired_pos = _bounds_centre + Vector3(0.0, 2.8 * _bounds_radius, 2.0 * _bounds_radius)
		_cam_look = _bounds_centre
		look = _cam_look
	if Game.args.has("board_cam"):
		# Harness: --board_cam=x,y,z:tx,ty,tz puts the camera anywhere, looking at a point.
		var parts := str(Game.args["board_cam"]).split(":")
		if parts.size() == 2:
			var a := parts[0].split(",")
			var b := parts[1].split(",")
			if a.size() == 3 and b.size() == 3:
				desired_pos = Vector3(float(a[0]), float(a[1]), float(a[2]))
				_cam_look = Vector3(float(b[0]), float(b[1]), float(b[2]))
				look = _cam_look
	# Hold Tab (the scoreboard action) for the whole board; blends in and out over ~0.6 s.
	var want_map := (Input.is_action_pressed("scoreboard") and not Game.is_paused()) or Game.args.has("board_map")
	_map_blend = move_toward(_map_blend, 1.0 if want_map else 0.0, delta * 1.8)
	if _map_blend > 0.0:
		var e := smoothstep(0.0, 1.0, _map_blend)
		var map_pos := _bounds_centre + Vector3(0.0, _bounds_radius * 1.5 + 10.0, _bounds_radius * 0.95)
		desired_pos = desired_pos.lerp(map_pos, e)
		look = look.lerp(_bounds_centre, e)
	var k := 1.0 - pow(0.004 if (_cam_fast or _map_blend > 0.0 or _free) else 0.02, delta)
	camera.global_position = camera.global_position.lerp(desired_pos, k)
	_cam_target = _cam_target.lerp(look, k)
	camera.look_at(_cam_target + Vector3(0, 1.0, 0), Vector3.UP)
	# Board life: the beacon turns and bobs with a flickering spark, islands drift, the active
	# pawn's ring pulses.
	_anim_t += delta
	if goal_beacon != null:
		goal_beacon.rotation.y += delta * 0.7
		goal_beacon.global_position.y = float(goal_beacon.get_meta("base_y", goal_beacon.global_position.y)) + sin(_anim_t * 1.6) * 0.12
	if _spark != null:
		var f := 0.75 + 0.45 * absf(sin(_anim_t * 9.0)) * (0.6 + 0.4 * sin(_anim_t * 23.0))
		_spark.scale = Vector3.ONE * f
	for isl in _islands:
		var n: Node3D = isl["node"]
		n.position.y = float(isl["base_y"]) + sin(_anim_t * 0.35 + float(isl["phase"])) * 0.5
		n.rotation.y += delta * float(isl.get("spin", 0.0))
	if _ufo != null:
		var lap := _anim_t * TAU / 48.0
		var rr := _bounds_radius * 1.22
		_ufo.position = _bounds_centre + Vector3(cos(lap) * rr, 9.0 + sin(_anim_t * 0.9) * 0.6, sin(lap) * rr * 0.85)
		_ufo.rotation = Vector3(0.0, _anim_t * 1.4, 0.1 * sin(_anim_t * 0.9))
	if _planet != null:
		_planet.rotation.y += delta * 0.03
	if _astronaut != null:
		_astronaut.animate(0.0, true, 0.45 + 0.1 * sin(_anim_t * 0.7), true, delta)
	for i in range(_socials.size() - 1, -1, -1):
		var so: Dictionary = _socials[i]
		var n: Node3D = so["node"]
		if not is_instance_valid(n):
			_socials.remove_at(i)
			continue
		so["t"] = float(so["t"]) + delta
		var t: float = so["t"]
		if t >= float(so["life"]):
			n.queue_free()
			_socials.remove_at(i)
			continue
		if str(so["kind"]) == "ping":
			n.position.y = float(so["base_y"]) + absf(sin(t * 5.0)) * 0.45 * maxf(0.0, 1.0 - t / 3.0)
			n.rotation.y += delta * 2.5
		else:
			var pop := minf(1.0, t / 0.15)
			var out := clampf((float(so["life"]) - t) / 0.2, 0.0, 1.0)
			n.scale = Vector3.ONE * (0.2 + 0.8 * pop) * out
			n.position.y = float(so["base_y"]) + pop * 0.15
	if active_pulse != null and director.state != null:
		var ap := director.state.active_player()
		var pawn: BoardPawn = pawns.get(ap.peer_id, null) if ap != null else null
		var show := pawn != null and director.state.phase in [BoardState.PHASE_TURNS, BoardState.PHASE_CHOOSING]
		active_pulse.visible = show
		if show:
			active_pulse.global_position = pawn.global_position + Vector3(0, 0.05, 0)
			var pulse := 1.0 + 0.18 * (0.5 + 0.5 * sin(_anim_t * 4.0))
			active_pulse.scale = Vector3(pulse, 1.0, pulse)
	if goal_ring != null:
		goal_ring.rotation.y += delta * 0.8
	# The rocket in flight: the camera rides along and the flame flickers (the markers on the
	# tiles sit still since 2026-09-24).
	_marker_t += delta
	if _shuttle_follow and _shuttle != null:
		_cam_look = _shuttle.global_position
	if _shuttle_flame != null and _shuttle_flame.visible:
		_shuttle_flame.scale = Vector3(1.0 + 0.15 * sin(_marker_t * 31.0), 1.0 + 0.3 * absf(sin(_marker_t * 23.0)), 1.0 + 0.15 * cos(_marker_t * 27.0))


## The rocket's flight: a lob 14 m high between two ground points, the nose leaning into the
## travel through the middle of the arc, upright at both ends.
func _fly(from: Vector3, to: Vector3, t: float) -> void:
	if _shuttle == null:
		return
	var pos := from.lerp(to, t) + Vector3.UP * sin(t * PI) * 14.0
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var basis := Basis.IDENTITY
	if d.length() > 0.01:
		basis = Basis(Vector3.UP.cross(d.normalized()).normalized(), 0.45 * sin(t * PI))
	_shuttle.global_transform = Transform3D(basis, pos)


## After a ride the rocket flies itself home, empty, in the background.
func _shuttle_return(from: Vector3, home: Vector3) -> void:
	if _shuttle == null:
		return
	_shuttle_tween = create_tween()
	_shuttle_tween.tween_interval(1.2)
	_shuttle_tween.tween_callback(func(): _shuttle_flame.visible = true)
	_shuttle_tween.tween_method(func(t: float): _fly(from, home, t), 0.0, 1.0, 3.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_shuttle_tween.tween_callback(func():
		_shuttle_flame.visible = false
		_shuttle.transform = Transform3D.IDENTITY)


## A maple leaf, y up, a unit tall: three big lobes, two small ones and a stem.
const MAPLE_LEAF := [Vector2(0.0, 1.0), Vector2(0.12, 0.7), Vector2(0.35, 0.78), Vector2(0.28, 0.5),
	Vector2(0.6, 0.62), Vector2(0.5, 0.35), Vector2(0.92, 0.45), Vector2(0.8, 0.2), Vector2(0.95, -0.05),
	Vector2(0.55, -0.02), Vector2(0.62, -0.32), Vector2(0.35, -0.2), Vector2(0.1, -0.45), Vector2(0.06, -0.45),
	Vector2(0.06, -0.95), Vector2(-0.06, -0.95), Vector2(-0.06, -0.45), Vector2(-0.1, -0.45), Vector2(-0.35, -0.2),
	Vector2(-0.62, -0.32), Vector2(-0.55, -0.02), Vector2(-0.95, -0.05), Vector2(-0.8, 0.2), Vector2(-0.92, 0.45),
	Vector2(-0.5, 0.35), Vector2(-0.6, 0.62), Vector2(-0.28, 0.5), Vector2(-0.35, 0.78), Vector2(-0.12, 0.7)]


## A flat polygon lying on the face (y up in `pts` becomes north, -z), triangulated, both windings
## so it shows whichever way the triangulation turns.
func _flat_polygon(parent: Node3D, points: Array, pos: Vector3, s: float, mat: Material) -> void:
	var pts := PackedVector2Array(points)
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	st.set_normal(Vector3.UP)
	for t in range(0, idx.size(), 3):
		var a := pts[idx[t]]
		var b := pts[idx[t + 1]]
		var c := pts[idx[t + 2]]
		for tri in [[a, b, c], [a, c, b]]:
			for p in tri:
				st.add_vertex(Vector3((p as Vector2).x * s, 0.0, -(p as Vector2).y * s))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


## A mecha helmet, y up, from the brow to the chin: a domed top, side flares, ear vents, a chin.
const GUNDAM_HELMET := [Vector2(0.0, 0.75), Vector2(0.32, 0.7), Vector2(0.5, 0.45), Vector2(0.55, 0.1), Vector2(0.45, -0.1),
	Vector2(0.62, -0.25), Vector2(0.5, -0.55), Vector2(0.25, -0.75), Vector2(0.1, -0.9), Vector2(-0.1, -0.9),
	Vector2(-0.25, -0.75), Vector2(-0.5, -0.55), Vector2(-0.62, -0.25), Vector2(-0.45, -0.1), Vector2(-0.55, 0.1),
	Vector2(-0.5, 0.45), Vector2(-0.32, 0.7)]

## The V-fin over the brow.
const GUNDAM_FIN := [Vector2(-0.68, 1.2), Vector2(-0.54, 1.26), Vector2(-0.06, 0.66), Vector2(0.06, 0.66), Vector2(0.54, 1.26),
	Vector2(0.68, 1.2), Vector2(0.1, 0.5), Vector2(-0.1, 0.5)]


## The free camera (Sean, 2026-09-24: "when it's our turn, we can press R to toggle free cam
## mode, and use WASD to move the camera around the map"): the look point leaves the pawn and
## slides under the keys; off again with R, with the roll, or when the turn is no longer yours.
func free_cam() -> bool:
	return _free


func set_free_cam(on: bool) -> void:
	if on and not _free:
		_free_look = _cam_look
	_free = on


func toggle_free_cam() -> void:
	set_free_cam(not _free)
