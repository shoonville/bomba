class_name BoardView
extends Node3D
## The board in 3D (BOARDPLAN.md §5): six-sided floating tiles by space type, planks between
## them, a ring on the goal, pawns hopping space to space, a camera that follows the active
## pawn, floating coin/item labels. Plays the director's event queue in order.

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
var _bounds_centre: Vector3 = Vector3.ZERO
var _bounds_radius: float = 20.0
var _map_blend: float = 0.0
var _anim_t: float = 0.0
var camera: Camera3D
var markers: Array = []
var _marker_t: float = 0.0
var _cam_target: Vector3 = Vector3.ZERO
var _cam_look: Vector3 = Vector3.ZERO
var _cam_yaw: float = 0.0          # camera sits behind the pawn along this heading
var _cam_yaw_target: float = 0.0
var _cam_fast: bool = false        # tighter follow while a pawn is moving
var _queue: Array = []
var _playing: bool = false
var _hop: float = 0.32
var _fork_focus: Array = []


func setup(p_director: BoardDirector) -> void:
	director = p_director
	_hop = float(director.cfg.get("hop_seconds", 0.32))
	var t0 := Time.get_ticks_usec()
	_build_environment()
	var t1 := Time.get_ticks_usec()
	_build_tiles()
	var t2 := Time.get_ticks_usec()
	Log.info("perf", "Board view built: environment %d ms, tiles+markers %d ms" % [(t1 - t0) / 1000, (t2 - t1) / 1000])
	director.state_changed.connect(_on_state)
	director.events_received.connect(_on_events)
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
	if director.state != null:
		_on_state(director.state)


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
		# Landing tile in glowing cream: distinct on every tile colour (the accent is coin yellow).
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


## A marker over every special space so the board reads without a legend: a spinning coin,
## a crate for items, a spiked ball for LOSE, a "?" sign for events, a flag for the start.
func _build_marker(space: BoardGraph.Space, shadow: Color) -> void:
	var ink := Palette.map_colour("board", "line")
	var ink_mat := CelMaterial.for_colour(Color.from_hsv(ink.h, 0.45, 0.24), shadow)
	var root := Node3D.new()
	root.position = space.position + Vector3(0, 0.55, 0)
	match space.type:
		"coin":
			var coin := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.28
			cm.bottom_radius = 0.28
			cm.height = 0.08
			cm.radial_segments = 16
			coin.mesh = cm
			coin.rotation.x = PI * 0.5
			coin.material_override = CelMaterial.for_colour(_tone_for("coin"), shadow, 0.35)
			root.add_child(coin)
			var rim := MeshInstance3D.new()
			var rm := TorusMesh.new()
			rm.inner_radius = 0.26
			rm.outer_radius = 0.31
			rm.rings = 16
			rm.ring_segments = 6
			rim.mesh = rm
			rim.rotation.x = PI * 0.5
			rim.material_override = ink_mat
			root.add_child(rim)
		"item":
			var crate := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.42, 0.42, 0.42)
			crate.mesh = bm
			crate.material_override = CelMaterial.for_colour(_tone_for("item"), shadow, 0.2)
			root.add_child(crate)
			for axis in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
				var strap := MeshInstance3D.new()
				var sb := BoxMesh.new()
				sb.size = Vector3(0.46, 0.46, 0.46) - axis * 0.36
				strap.mesh = sb
				strap.material_override = ink_mat
				root.add_child(strap)
		"lose":
			var ball := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.24
			sm.height = 0.48
			ball.mesh = sm
			ball.material_override = CelMaterial.for_colour(_tone_for("lose"), shadow, 0.2)
			root.add_child(ball)
			for k in 6:
				var spike := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.0
				cm.bottom_radius = 0.07
				cm.height = 0.22
				cm.radial_segments = 6
				spike.mesh = cm
				var dir := [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK][k] as Vector3
				spike.position = dir * 0.3
				if dir.is_equal_approx(Vector3.UP):
					pass
				elif dir.is_equal_approx(Vector3.DOWN):
					spike.rotation.x = PI
				else:
					spike.basis = Basis(Quaternion(Vector3.UP, dir))
				spike.material_override = ink_mat
				root.add_child(spike)
		"event":
			var sign := Label3D.new()
			sign.text = "?"
			sign.font_size = 96
			sign.pixel_size = 0.008
			sign.outline_size = 22
			sign.modulate = Palette.hud_colour("paper")
			sign.outline_modulate = ink
			sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sign.alpha_cut = Label3D.ALPHA_CUT_DISCARD
			sign.position.y = 0.2
			root.add_child(sign)
		"shield":
			var dome := MeshInstance3D.new()
			var dm := SphereMesh.new()
			dm.radius = 0.3
			dm.height = 0.6
			dm.radial_segments = 14
			dm.rings = 7
			dome.mesh = dm
			dome.scale = Vector3(1.0, 0.6, 1.0)
			dome.material_override = CelMaterial.for_colour(Palette.hud_colour("meter"), shadow, 0.5)
			root.add_child(dome)
			var band := MeshInstance3D.new()
			var bm2 := TorusMesh.new()
			bm2.inner_radius = 0.3
			bm2.outer_radius = 0.38
			bm2.rings = 16
			bm2.ring_segments = 6
			band.mesh = bm2
			band.material_override = ink_mat
			root.add_child(band)
		"start":
			var pole := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.04
			pm.bottom_radius = 0.04
			pm.height = 1.3
			pole.mesh = pm
			pole.position = Vector3(0.7, 0.1, -0.7)
			pole.material_override = ink_mat
			root.add_child(pole)
			var flag := MeshInstance3D.new()
			var fm := PrismMesh.new()
			fm.size = Vector3(0.5, 0.34, 0.04)
			flag.mesh = fm
			flag.position = Vector3(0.7 + 0.27, 0.58, -0.7)
			flag.rotation.z = -PI * 0.5
			flag.material_override = CelMaterial.for_colour(Palette.map_colour("board", "accent"), shadow, 0.3)
			root.add_child(flag)
		_:
			root.queue_free()
			return
	add_child(root)
	root.set_meta("base_y", root.position.y)
	markers.append(root)


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


## The moon: the board stands on posts over a floating chunk of grey rock with craters and
## boulders, a landing pad with a rocket, a satellite dish, a buggy, a half-buried probe and a
## crew member looking at the sky. The pink sky stays (Sean: outer space, keep the pink).
func _build_moon(g: BoardGraph, shadow: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(g.id) + 23
	var lo := Vector3(1e9, 0, 1e9)
	var hi := Vector3(-1e9, 0, -1e9)
	for sid in g.ids():
		var sp := g.get_space(sid).position
		lo.x = minf(lo.x, sp.x); lo.z = minf(lo.z, sp.z)
		hi.x = maxf(hi.x, sp.x); hi.z = maxf(hi.z, sp.z)
	var c := (lo + hi) * 0.5
	var rx := (hi.x - lo.x) * 0.5 + 7.0
	var rz := (hi.z - lo.z) * 0.5 + 7.0
	var moon_mat := CelMaterial.for_colour(Palette.map_colour("board", "moon"), shadow)
	var moon_dark_mat := CelMaterial.for_colour(Palette.map_colour("board", "moon_dark"), shadow)
	var crater_mat := CelMaterial.for_colour(Palette.map_colour("board", "crater"), shadow)
	var rock_mat := CelMaterial.for_colour(Palette.map_colour("board", "rock"), shadow)
	var post_mat := CelMaterial.for_colour(Palette.map_colour("board", "counter_dark"), shadow)
	var metal_mat := CelMaterial.for_colour(Palette.map_colour("board", "metal"), shadow)
	var paper_mat := CelMaterial.for_colour(Palette.hud_colour("paper"), shadow)
	var accent_mat := CelMaterial.for_colour(Palette.map_colour("board", "accent"), shadow, 0.3)
	var ink_mat := CelMaterial.for_colour(Color.from_hsv(Palette.map_colour("board", "line").h, 0.45, 0.24), shadow)
	var glow_mat := CelMaterial.for_colour(Palette.hud_colour("danger"), shadow, 1.5)
	var alien_mat := CelMaterial.for_colour(Palette.map_colour("board", "alien"), shadow, 1.2)
	# The chunk: a 13-sided slab, a rocky root tapering nine metres down.
	var slab := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 1.0
	sm.bottom_radius = 0.94
	sm.height = 2.6
	sm.radial_segments = 13
	slab.mesh = sm
	slab.scale = Vector3(rx, 1.0, rz)
	slab.position = c + Vector3(0, MOON_TOP - 1.3, 0)
	slab.material_override = moon_mat
	add_child(slab)
	var root := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.9
	rm.bottom_radius = 0.22
	rm.height = 1.0
	rm.radial_segments = 11
	root.mesh = rm
	root.scale = Vector3(rx, 9.0, rz)
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
	# Craters: a darker floor and a raised rim, never under a tile.
	var craters: Array = []
	var tries := 0
	while craters.size() < 16 and tries < 400:
		tries += 1
		var a := rng.randf_range(0.0, TAU)
		var f := sqrt(rng.randf_range(0.04, 0.9))
		var x := c.x + cos(a) * rx * f
		var z := c.z + sin(a) * rz * f
		var r := rng.randf_range(1.1, 3.4)
		if not _clear_of_tiles(g, x, z, r + 1.6):
			continue
		var ok := true
		for cr in craters:
			if Vector2(x - cr.x, z - cr.y).length() < r + cr.z + 1.0:
				ok = false
				break
		if not ok:
			continue
		craters.append(Vector3(x, z, r))
		_prop_cyl(self, r * 0.86, 0.08, Vector3(x, MOON_TOP + 0.03, z), crater_mat)
		var rim := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r * 0.86
		tm.outer_radius = r * 1.14
		tm.rings = 24
		tm.ring_segments = 6
		rim.mesh = tm
		rim.position = Vector3(x, MOON_TOP + 0.06, z)
		rim.scale = Vector3(1.0, 0.5, 1.0)
		rim.material_override = moon_dark_mat
		add_child(rim)
	# Boulders, a few on the rim so the edge reads as rock.
	for k in 28:
		var a := rng.randf_range(0.0, TAU)
		var f := sqrt(rng.randf_range(0.1, 1.0)) if k < 20 else rng.randf_range(0.97, 1.02)
		var x := c.x + cos(a) * rx * f
		var z := c.z + sin(a) * rz * f
		if not _clear_of_tiles(g, x, z, 2.4):
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
	# Props, each in a spot clear of the tiles and of each other.
	var spots: Array = []
	tries = 0
	while spots.size() < 5 and tries < 600:
		tries += 1
		var a := rng.randf_range(0.0, TAU)
		var f := rng.randf_range(0.3, 0.88)
		var x := c.x + cos(a) * rx * f
		var z := c.z + sin(a) * rz * f
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
	for n in spots.size():
		var at := Vector3(spots[n].x, MOON_TOP, spots[n].y)
		var prop := Node3D.new()
		prop.position = at
		prop.rotation.y = rng.randf_range(0.0, TAU)
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
				for fk in 3:
					var fin := MeshInstance3D.new()
					var fm := PrismMesh.new()
					fm.size = Vector3(1.4, 1.6, 0.12)
					fin.mesh = fm
					fin.position = Vector3(cos(fk * TAU / 3.0) * 0.95, 0.95, sin(fk * TAU / 3.0) * 0.95)
					fin.rotation.y = -fk * TAU / 3.0 + PI * 0.5
					fin.rotation.z = -PI * 0.5
					fin.material_override = accent_mat
					prop.add_child(fin)
				_prop_cyl(prop, 0.5, 0.5, Vector3(0, 0.45, 0), ink_mat)
				_prop_cyl(prop, 0.72, 3.6, Vector3(0, 2.5, 0), paper_mat)
				_prop_cyl(prop, 0.74, 0.5, Vector3(0, 2.0, 0), accent_mat)
				var nose := MeshInstance3D.new()
				var nm := CylinderMesh.new()
				nm.top_radius = 0.0
				nm.bottom_radius = 0.72
				nm.height = 1.5
				nm.radial_segments = 14
				nose.mesh = nm
				nose.position.y = 5.05
				nose.material_override = accent_mat
				prop.add_child(nose)
				var port := MeshInstance3D.new()
				var pm := CylinderMesh.new()
				pm.top_radius = 0.26
				pm.bottom_radius = 0.26
				pm.height = 0.08
				port.mesh = pm
				port.position = Vector3(0, 3.2, -0.72)
				port.rotation.x = PI * 0.5
				port.material_override = CelMaterial.for_colour(Palette.hud_colour("meter"), shadow, 0.6)
				prop.add_child(port)
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
			2:   # moon buggy
				_prop_box(prop, Vector3(2.4, 0.5, 1.4), Vector3(0, 0.8, 0), metal_mat)
				_prop_box(prop, Vector3(0.9, 0.6, 1.1), Vector3(-0.5, 1.3, 0), accent_mat)
				for wx: float in [-0.85, 0.85]:
					for wz: float in [-0.85, 0.85]:
						var wheel := MeshInstance3D.new()
						var wm := CylinderMesh.new()
						wm.top_radius = 0.45
						wm.bottom_radius = 0.45
						wm.height = 0.3
						wm.radial_segments = 10
						wheel.mesh = wm
						wheel.position = Vector3(wx, 0.45, wz)
						wheel.rotation.x = PI * 0.5
						wheel.material_override = ink_mat
						prop.add_child(wheel)
				_prop_cyl(prop, 0.04, 1.8, Vector3(0.9, 1.9, 0.5), ink_mat)
				_prop_sphere(prop, 0.1, Vector3(0.9, 2.8, 0.5), glow_mat)
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
func _build_space(g: BoardGraph, shadow: Color) -> void:
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
	for i in 14:
		var a := float(i) / 14.0 * TAU + rng.randf_range(-0.2, 0.2)
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
				2:   # wrecked rocket, nose in the rock
					var wreck := MeshInstance3D.new()
					var wm := CylinderMesh.new()
					wm.top_radius = 0.5
					wm.bottom_radius = 0.5
					wm.height = 2.6
					wreck.mesh = wm
					wreck.position = Vector3(0, 0.9, 0)
					wreck.rotation = Vector3(0.6, 0.0, 0.4)
					wreck.material_override = paper_mat
					prop.add_child(wreck)
					_prop_box(prop, Vector3(1.2, 0.9, 0.1), Vector3(0.5, 2.0, 0.3), accent_mat)
				_:   # a lamp, because someone lives out here
					_prop_cyl(prop, 0.08, 2.2, Vector3(0, 1.1, 0), ink_mat)
					_prop_box(prop, Vector3(0.6, 0.3, 0.6), Vector3(0, 2.3, 0), ink_mat)
					_prop_box(prop, Vector3(0.44, 0.08, 0.44), Vector3(0, 2.12, 0), glow_mat)
		_islands.append({"node": ast, "base_y": pos.y, "phase": rng.randf_range(0.0, TAU), "spin": rng.randf_range(-0.12, 0.12)})
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
		"coin": return Palette.player_colour(3)
		"lose": return Palette.hud_colour("danger")
		"item": return Palette.player_colour(5)
		"event": return Palette.player_colour(0)
		"shield": return Palette.hud_colour("meter")
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
	# The Bomba beacon: a bomb with a lit fuse floating over the goal, visible from anywhere.
	goal_beacon = Node3D.new()
	var bomb := MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.42
	bsm.height = 0.84
	bsm.radial_segments = 16
	bsm.rings = 8
	bomb.mesh = bsm
	bomb.material_override = CelMaterial.for_colour(Color.from_hsv(Palette.map_colour("board", "line").h, 0.45, 0.2), shadow)
	goal_beacon.add_child(bomb)
	var cap := MeshInstance3D.new()
	var cpm := CylinderMesh.new()
	cpm.top_radius = 0.12
	cpm.bottom_radius = 0.14
	cpm.height = 0.14
	cap.mesh = cpm
	cap.position = Vector3(0, 0.44, 0)
	cap.material_override = CelMaterial.for_colour(Palette.map_colour("board", "counter"), shadow)
	goal_beacon.add_child(cap)
	var fuse := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.03
	fm.bottom_radius = 0.03
	fm.height = 0.34
	fuse.mesh = fm
	fuse.position = Vector3(0.08, 0.64, 0)
	fuse.rotation.z = -0.5
	fuse.material_override = CelMaterial.for_colour(Palette.hud_colour("paper"), shadow)
	goal_beacon.add_child(fuse)
	_spark = MeshInstance3D.new()
	var spm := SphereMesh.new()
	spm.radius = 0.11
	spm.height = 0.22
	spm.radial_segments = 8
	spm.rings = 4
	_spark.mesh = spm
	_spark.position = Vector3(0.17, 0.79, 0)
	_spark.material_override = CelMaterial.for_colour(Palette.hud_colour("score"), shadow, 1.6)
	goal_beacon.add_child(_spark)
	var badge := Label3D.new()
	badge.text = "◆"
	badge.font_size = 96
	badge.pixel_size = 0.006
	badge.outline_size = 0
	badge.modulate = Palette.hud_colour("score")
	badge.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	badge.position = Vector3(0, 0.0, -0.43)
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
	# Board bounds, for the Tab map view and the islands.
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
	_build_moon(g, shadow)
	_build_space(g, shadow)


func _ensure_pawn(p: BoardState.PlayerState) -> BoardPawn:
	if pawns.has(p.peer_id):
		return pawns[p.peer_id]
	var pawn := BoardPawn.new()
	pawn.name = "Pawn_%d" % p.peer_id
	add_child(pawn)
	pawn.setup(p.peer_id, Palette.player_colour(p.colour_index), p.display_name)
	pawns[p.peer_id] = pawn
	pawn.snap_to(_slot_position(p.space, p.peer_id))
	return pawn


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
	var first := pawns.is_empty()
	for p in state.players:
		_ensure_pawn(p)
	# Existing pawns are moved by the events that follow this state. Snapping them here showed
	# every pawn at its destination for a frame before the hop (Sean's note 2); the queue's
	# end-of-events snap reconciles instead.
	if goal_ring != null and state.goal != "" and (first or not _playing):
		_place_goal(director.space_position(state.goal))
	var ap := state.active_player()
	if ap != null and first:
		_focus(director.space_position(ap.space))


func _snap_all() -> void:
	if director.state == null:
		return
	for p in director.state.players:
		if pawns.has(p.peer_id):
			(pawns[p.peer_id] as BoardPawn).snap_to(_slot_position(p.space, p.peer_id))


## True while the view is still playing events (hops, dice, cards); the HUD holds its buttons
## until the pawn has actually arrived where the state says it is.
func is_animating() -> bool:
	return _playing or not _queue.is_empty()


func _on_events(events: Array) -> void:
	_queue.append_array(events)
	if not _playing:
		_play_next()


func _play_next() -> void:
	if _queue.is_empty():
		_playing = false
		_snap_all()
		return
	_playing = true
	var e: Dictionary = _queue.pop_front()
	var wait := 0.05
	match str(e.get("kind", "")):
		"turn":
			var p := director.state.player(int(e["peer"])) if director.state != null else null
			if p != null:
				_focus(director.space_position(p.space))
			wait = 0.3
		"roll":
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
				var to := base + right * 1.5 - forward * 0.6 + Vector3.UP * BoardDice.INRADIUS
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
					_heading_from(pawn.global_position, to)
					pawn.hop_to(to, _hop)
					_focus(to)
					await get_tree().create_timer(_hop).timeout
				_cam_fast = false
				if not Game.headless:
					Burst.spawn(self, pawn.global_position + Vector3(0, 0.2, 0), pawn.colour, 0.45, 0.18, 7)
			wait = 0.1
		"coins":
			_float_label(int(e["peer"]), ("+%d" if int(e["delta"]) >= 0 else "%d") % int(e["delta"]),
				Palette.player_colour(3) if int(e["delta"]) >= 0 else Palette.hud_colour("danger"))
			Audio.play("coin" if int(e["delta"]) >= 0 else "hurt", -6.0)
			wait = 0.5
		"item":
			_float_label(int(e["peer"]), "+" + str(e["item"]).to_upper(), Palette.player_colour(5))
			Audio.play("ui_click", -2.0)
			wait = 0.5
		"item_used":
			_float_label(int(e["peer"]), str(e["item"]).to_upper() + "!", Palette.hud_colour("danger"))
			Audio.play("dice", 0.0)
			wait = 0.5
		"goal":
			var pawn: BoardPawn = pawns.get(int(e["peer"]), null)
			if pawn != null and not Game.headless:
				Burst.spawn(self, pawn.global_position + Vector3(0, 1.0, 0), Palette.hud_colour("score"), 1.2, 0.5, 10)
			_float_label(int(e["peer"]), "BOMBA!", Palette.hud_colour("score"))
			Audio.play("kill", 0.0)
			if goal_ring != null:
				_place_goal(director.space_position(str(e["new_goal"])))
			wait = 1.0
		"shield":
			var pawn: BoardPawn = pawns.get(int(e["peer"]), null)
			if pawn != null:
				if not Game.headless:
					Burst.spawn(self, pawn.global_position + Vector3(0, 0.8, 0), Palette.player_colour(5), 1.1, 0.45, 12)
				_focus(pawn.global_position)
			_float_label(int(e["peer"]), "SHIELDED!", Palette.player_colour(5))
			Audio.play("land", 0.0)
			wait = 0.8
		"teleport":
			var pawn: BoardPawn = pawns.get(int(e["peer"]), null)
			if pawn != null:
				if not Game.headless:
					Burst.spawn(self, pawn.global_position + Vector3(0, 0.6, 0), Palette.player_colour(0), 0.8, 0.3, 8)
				pawn.snap_to(director.space_position(str(e["to"])))
				_focus(pawn.global_position)
				Audio.play("respawn", -4.0)
			wait = 0.8
		"choose":
			var opts: Array = e["options"]
			_fork_focus = opts
			if opts.size() >= 2:
				# Stand behind the fork looking down the middle of the two paths, so LEFT and
				# RIGHT are on the left and right of the screen.
				var pawn: BoardPawn = pawns.get(int(e["peer"]), null)
				var mid := (director.space_position(str(opts[0])) + director.space_position(str(opts[1]))) * 0.5
				if pawn != null:
					_heading_from(pawn.global_position, mid)
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
	tw.chain().tween_callback(l.queue_free)


func _focus(point: Vector3) -> void:
	_cam_look = point


## Put the camera behind a pawn travelling from `from` to `to` (flat), so it looks along the path.
func _heading_from(from: Vector3, to: Vector3) -> void:
	var travel := to - from
	travel.y = 0.0
	if travel.length() > 0.2:
		_cam_yaw_target = atan2(-travel.x, -travel.z)


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
	var desired_pos := _cam_look + Vector3(sin(_cam_yaw) * 6.8, 6.2, cos(_cam_yaw) * 6.8)
	var look := _cam_look
	if Game.args.has("board_overview"):
		# Harness: the whole board from above, for layout screenshots.
		desired_pos = Vector3(0.0, 64.0, 46.0)
		_cam_look = Vector3.ZERO
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
	var k := 1.0 - pow(0.004 if (_cam_fast or _map_blend > 0.0) else 0.02, delta)
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
	_marker_t += delta
	for i in markers.size():
		var n := markers[i] as Node3D
		if n != null and is_instance_valid(n):
			n.rotation.y = _marker_t * 1.1 + float(i)
			n.position.y = float(n.get_meta("base_y", n.position.y)) + sin(_marker_t * 2.2 + float(i)) * 0.06
