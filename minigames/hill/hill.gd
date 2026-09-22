extends FpsMatch
## KING OF THE HILL (MINIGAMES.md §3): a hill that moves between the layout's spots; a tick alone
## inside it scores; two or more inside is contested and scores nobody; hill.win_seconds alone
## wins on the spot, else the clock ends it and hill seconds rank. The host samples the hill once
## per tick from the authoritative states and announces moves and scores; clients only display.
## Rules in HillRules (pure, tested), numbers in tuning/hill.json.

var hill_cfg: Dictionary = {}
var hills: Array = []               # [{pos: Vector3, radius: float, bots: bool}] from the layout
var hill_index: int = -1
var hill_until_tick: int = -1       # the tick it moves
var holder: int = HillRules.EMPTY   # the peer alone inside, EMPTY or CONTESTED
var hill_ticks: Dictionary = {}     # peer → ticks alone inside

var _order: Array = []
var _order_pos: int = 0
var _radius: float = 2.8
var _height: float = 3.0
var _floor_slack: float = 0.3
var _move_ticks: int = 1800
var _win_ticks: int = 3600
var _sync_interval: int = 6
var _last_sync_tick: int = -1000
var _hill_root: Node3D
var _glass_mesh: CylinderMesh
var _ring_mesh: TorusMesh
var _glass_mat: StandardMaterial3D
var _beam_mat: StandardMaterial3D
var _ring_mat: ShaderMaterial
var _flag_mat: ShaderMaterial
var _pennant: Node3D
var _shown_colour: Color = Color.TRANSPARENT
var _last_tick_second: int = -1
var _sway_t: float = 0.0


func _on_setup() -> void:
	hill_cfg = Tuning.table("hill")
	_radius = float(hill_cfg.get("radius_m", 2.8))
	_height = float(hill_cfg.get("height_m", 3.0))
	_floor_slack = float(hill_cfg.get("floor_slack_m", 0.3))
	_move_ticks = maxi(1, int(float(hill_cfg.get("move_every_seconds", 30)) * NetworkTime.tickrate))
	_win_ticks = maxi(1, int(float(hill_cfg.get("win_seconds", 60)) * NetworkTime.tickrate))
	_sync_interval = maxi(1, int(hill_cfg.get("sync_interval_ticks", 6)))
	super()
	hills = layout.get("hills", [])
	if hills.is_empty():
		Log.error("hill", "The layout has no hill spots; the hill stands at the origin")
		hills = [{"pos": Vector3.ZERO, "radius": _radius}]
	for p in players:
		hill_ticks[p.peer_id] = 0
	_build_hill()
	if is_authority():
		var first := int(Game.args.get("hill_index", -1))
		_order = HillRules.make_order(hills.size(), Rng.stream("hill"), -1, first)
		_order_pos = 0
		_rpc_hill.rpc(int(_order[0]), round_start_tick + _move_ticks)


# --- the rules ---------------------------------------------------------------------------

func _score_for(pl: Player) -> int:
	return int(hill_ticks.get(pl.peer_id, 0))


func _score_label(pl: Player) -> String:
	return "%s HILL" % HillRules.format_seconds(_score_for(pl), NetworkTime.tickrate)


func hud_score(pl: Player) -> String:
	return HillRules.format_seconds(_score_for(pl), NetworkTime.tickrate)


func hud_score_header() -> String:
	return "HILL"


func hill_position() -> Vector3:
	if hill_index < 0 or hill_index >= hills.size():
		return Vector3.INF
	return hills[hill_index]["pos"]


## The bots head for the hill, except a spot they cannot climb to (the roofs: no waypoints).
func objective_position() -> Vector3:
	if hill_index < 0 or hill_index >= hills.size() or not bool(hills[hill_index].get("bots", true)):
		return Vector3.INF
	return hills[hill_index]["pos"]


func hud_status() -> Array:
	if hill_index < 0 or in_warmup():
		return []
	var lp := get_local_player()
	var paper := Palette.hud_colour("paper")
	var top := "HILL OPEN"
	var col := Color(paper, 0.85)
	if holder == HillRules.CONTESTED:
		top = "CONTESTED"
		col = Palette.hud_colour("danger")
	elif holder != HillRules.EMPTY:
		if lp != null and holder == lp.peer_id:
			top = "YOU ARE KING"
			col = Palette.hud_colour("score")
		else:
			top = "%s IS KING" % _name_of(holder).to_upper()
			var hp := get_player(holder)
			col = hp.colour.lightened(0.3) if hp != null else paper
	var lines: Array = [{"text": top, "colour": col, "size": 30}]
	var best_id := 0
	var best := -1
	for id in hill_ticks:
		if int(hill_ticks[id]) > best:
			best = int(hill_ticks[id])
			best_id = int(id)
	var mine := _score_for(lp) if lp != null else 0
	var lead := "YOU LEAD"
	if lp == null or best_id != lp.peer_id:
		lead = "%s %s" % [_name_of(best_id).to_upper(), HillRules.format_seconds(best, NetworkTime.tickrate)]
	var moves := ceili(maxf(0.0, NetworkTime.seconds_between(NetworkTime.tick, hill_until_tick)))
	lines.append({"text": "YOU %s   ·   LEAD %s   ·   MOVES IN %d" % [HillRules.format_seconds(mine, NetworkTime.tickrate), lead, moves],
		"colour": Color(paper, 0.8), "size": 18})
	return lines


# --- authority ---------------------------------------------------------------------------

func _on_tick(delta: float, tick: int) -> void:
	if is_inside_tree() and is_authority() and not _finished_sent and hill_index >= 0 \
			and round_start_tick >= 0 and tick >= round_start_tick:
		_sample_hill(tick)
	super(delta, tick)


## One sample per tick from the states applied for it: the living players inside the hill.
func _sample_hill(tick: int) -> void:
	if tick >= hill_until_tick:
		_advance_hill(tick)
	var hill: Vector3 = hills[hill_index]["pos"]
	var r := float(hills[hill_index].get("radius", _radius))
	var inside: Array = []
	for p in _players.values():
		var pl := p as Player
		if pl.is_alive() and HillRules.inside(pl.global_position, hill, r, _height, _floor_slack):
			inside.append(pl.peer_id)
	holder = HillRules.holder(inside)
	if holder != HillRules.EMPTY and holder != HillRules.CONTESTED:
		hill_ticks[holder] = int(hill_ticks.get(holder, 0)) + 1
		if int(hill_ticks[holder]) >= _win_ticks:
			Log.info("hill", "%s held the hill for %d s: wins at tick %d" % [_name_of(holder), _win_ticks / NetworkTime.tickrate, tick])
			_rpc_hill_sync.rpc(holder, hill_ticks)
			_finish_round()
			return
	if tick - _last_sync_tick >= _sync_interval:
		_last_sync_tick = tick
		_rpc_hill_sync.rpc(holder, hill_ticks)


func _advance_hill(tick: int) -> void:
	_order_pos += 1
	if _order_pos >= _order.size():
		_order = HillRules.make_order(hills.size(), Rng.stream("hill"), hill_index)
		_order_pos = 0
	_rpc_hill.rpc(int(_order[_order_pos]), tick + _move_ticks)


# --- RPCs ---------------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _rpc_hill(index: int, until_tick: int) -> void:
	var moved := hill_index >= 0 and index != hill_index
	hill_index = clampi(index, 0, hills.size() - 1)
	hill_until_tick = until_tick
	holder = HillRules.EMPTY
	_place_hill(moved)
	Log.info("hill", "Hill %d at %s until tick %d%s" % [hill_index, hills[hill_index]["pos"], until_tick, " (moved)" if moved else ""])
	Events.hill_moved.emit(hill_index)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_hill_sync(p_holder: int, ticks: Dictionary) -> void:
	holder = p_holder
	for k in ticks:
		hill_ticks[int(k)] = int(ticks[k])


# --- seen ---------------------------------------------------------------------------------

## A glass cylinder on a ring, a pole with a pennant, a beam up so the hill can be found over the
## walls. The ring, the pennant and the glass take the holder's colour (STYLE.md: flat, inked).
func _build_hill() -> void:
	if Game.headless:
		return
	_hill_root = Node3D.new()
	_hill_root.name = "Hill"
	_hill_root.visible = false
	add_child(_hill_root)
	var score := Palette.hud_colour("score")
	var glass := MeshInstance3D.new()
	_glass_mesh = CylinderMesh.new()
	_glass_mesh.top_radius = _radius
	_glass_mesh.bottom_radius = _radius
	_glass_mesh.height = _height
	_glass_mesh.radial_segments = 28
	glass.mesh = _glass_mesh
	glass.position.y = _height * 0.5
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glass_mat.albedo_color = Color(score, 0.3)
	_glass_mat.render_priority = 2   # after the outline quad, which overwrites transparent geometry drawn before it
	glass.material_override = _glass_mat
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hill_root.add_child(glass)
	var ring := MeshInstance3D.new()
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = _radius - 0.14
	_ring_mesh.outer_radius = _radius + 0.14
	_ring_mesh.rings = 40
	_ring_mesh.ring_segments = 8
	ring.mesh = _ring_mesh
	ring.position.y = 0.08
	_ring_mat = CelMaterial.for_colour(score, Palette.map_colour(_palette_map(), "shadow_tint"), 0.35)
	ring.material_override = _ring_mat
	_hill_root.add_child(ring)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.05
	pm.bottom_radius = 0.06
	pm.height = 3.4
	pole.mesh = pm
	pole.position.y = 1.7
	pole.material_override = CelMaterial.for_tone(_palette_map(), "counter_dark")
	_hill_root.add_child(pole)
	_pennant = Node3D.new()
	_pennant.position.y = 3.05
	_hill_root.add_child(_pennant)
	var flag := MeshInstance3D.new()
	var fm := PrismMesh.new()
	fm.size = Vector3(0.56, 0.95, 0.04)
	fm.left_to_right = 0.0
	flag.mesh = fm
	flag.rotation.z = -PI * 0.5
	flag.position = Vector3(0.5, 0.0, 0.0)
	_flag_mat = CelMaterial.for_colour(score, Palette.map_colour(_palette_map(), "shadow_tint"), 0.2)
	flag.material_override = _flag_mat
	_pennant.add_child(flag)
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.3
	bm.bottom_radius = 0.5
	bm.height = 18.0
	bm.radial_segments = 8
	beam.mesh = bm
	beam.position.y = 9.0 + _height
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.albedo_color = Color(score, 0.55)
	_beam_mat.render_priority = 3
	beam.material_override = _beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hill_root.add_child(beam)


func _place_hill(moved: bool) -> void:
	if _hill_root == null or not is_instance_valid(_hill_root):
		return
	var pos: Vector3 = hills[hill_index]["pos"]
	var r := float(hills[hill_index].get("radius", _radius))
	_glass_mesh.top_radius = r
	_glass_mesh.bottom_radius = r
	_ring_mesh.inner_radius = r - 0.14
	_ring_mesh.outer_radius = r + 0.14
	_hill_root.global_position = pos
	_hill_root.visible = true
	_hill_root.scale = Vector3(0.2, 1.0, 0.2)
	var tw := _hill_root.create_tween()
	tw.tween_property(_hill_root, "scale", Vector3.ONE, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	if moved and effects_root != null:
		Burst.spawn(effects_root, pos + Vector3.UP * 1.2, Palette.hud_colour("score"), 1.6, 0.3, 10, false)


func _process(delta: float) -> void:
	super(delta)
	if _hill_root == null or not is_instance_valid(_hill_root) or not _hill_root.visible:
		return
	var col := Palette.hud_colour("score")
	if holder == HillRules.CONTESTED:
		col = Palette.hud_colour("danger")
	elif holder != HillRules.EMPTY:
		var hp := get_player(holder)
		if hp != null:
			col = hp.colour
	if col != _shown_colour:
		_shown_colour = col
		_glass_mat.albedo_color = Color(col, 0.3)
		_beam_mat.albedo_color = Color(col, 0.55)
		for m in [_ring_mat, _flag_mat]:
			m.set_shader_parameter("albedo", Palette.under_ceiling(col))
			m.set_shader_parameter("emission_color", col)
	_sway_t += delta
	_pennant.rotation.y = sin(_sway_t * 2.1) * 0.35
	# One soft tick per second you hold the hill.
	var lp := get_local_player()
	if lp != null and holder == lp.peer_id:
		var sec := _score_for(lp) / maxi(1, NetworkTime.tickrate)
		if sec != _last_tick_second:
			_last_tick_second = sec
			Events.hill_tick.emit()
