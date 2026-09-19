class_name BoardView
extends Node3D
## The board in 3D (BOARDPLAN.md §5): six-sided floating tiles by space type, planks between
## them, a ring on the goal, pawns hopping space to space, a camera that follows the active
## pawn, floating coin/item labels. Plays the director's event queue in order.

var director: BoardDirector
var tiles: Dictionary = {}
var pawns: Dictionary = {}
var goal_ring: MeshInstance3D
var camera: Camera3D
var _cam_target: Vector3 = Vector3.ZERO
var _cam_look: Vector3 = Vector3.ZERO
var _queue: Array = []
var _playing: bool = false
var _hop: float = 0.32
var _fork_focus: Array = []


func setup(p_director: BoardDirector) -> void:
	director = p_director
	_hop = float(director.cfg.get("hop_seconds", 0.32))
	_build_environment()
	_build_tiles()
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
	camera.global_position = Vector3(0, 14, 16)
	camera.look_at(Vector3.ZERO, Vector3.UP)
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


func _tone_for(type: String) -> Color:
	match type:
		"coin": return Palette.player_colour(3)
		"lose": return Palette.hud_colour("danger")
		"item": return Palette.player_colour(5)
		"event": return Palette.player_colour(0)
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
	goal_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.2
	tm.outer_radius = 1.45
	tm.rings = 32
	tm.ring_segments = 8
	goal_ring.mesh = tm
	goal_ring.material_override = CelMaterial.for_colour(Palette.hud_colour("paper"), shadow, 1.0)
	add_child(goal_ring)


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
	for p in state.players:
		_ensure_pawn(p)
	if not _playing:
		_snap_all()
	if goal_ring != null and state.goal != "":
		goal_ring.global_position = director.space_position(state.goal) + Vector3(0, 0.08, 0)
	var ap := state.active_player()
	if ap != null and not _playing:
		_focus(director.space_position(ap.space))


func _snap_all() -> void:
	if director.state == null:
		return
	for p in director.state.players:
		if pawns.has(p.peer_id):
			(pawns[p.peer_id] as BoardPawn).snap_to(_slot_position(p.space, p.peer_id))


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
			wait = 0.6
		"move":
			var pawn: BoardPawn = pawns.get(int(e["peer"]), null)
			var path: Array = e["path"]
			if pawn != null:
				for sid in path:
					if not is_inside_tree():
						_playing = false
						return
					pawn.hop_to(director.space_position(str(sid)), _hop)
					_focus(director.space_position(str(sid)))
					await get_tree().create_timer(_hop).timeout
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
				goal_ring.global_position = director.space_position(str(e["new_goal"])) + Vector3(0, 0.08, 0)
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
				_focus((director.space_position(str(opts[0])) + director.space_position(str(opts[1]))) * 0.5)
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
	l.no_depth_test = true
	add_child(l)
	l.global_position = pawn.global_position + Vector3(0, 2.6, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position:y", l.global_position.y + 1.4, 1.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)


func _focus(point: Vector3) -> void:
	_cam_look = point


func _process(delta: float) -> void:
	if camera == null:
		return
	var desired_pos := _cam_look + Vector3(0.0, 12.0, 13.5)
	camera.global_position = camera.global_position.lerp(desired_pos, 1.0 - pow(0.02, delta))
	_cam_target = _cam_target.lerp(_cam_look, 1.0 - pow(0.02, delta))
	camera.look_at(_cam_target + Vector3(0, 0.8, 0), Vector3.UP)
	if goal_ring != null:
		goal_ring.rotation.y += delta * 0.8
