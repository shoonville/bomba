class_name BoardDressing
extends Node3D
## The detail pass on the board (Sean: "add a bunch of detail... make it look great"): everything
## a moon base has around a walkway, built from primitives in the board palette and placed by
## seeded search in spots clear of the tiles, the craters and the five landmark props. Nothing
## here touches the rules, the tiles' positions or the camera.
##   On the path: an inset on every tile, collars on the posts, a stripe on every plank, cables
##     slung under the planks, a lamp beside every fifth space, a pennant banner over the start.
##   On the ground: hatches, rock clusters with pebbles, dust patches, cracks, rim rock.
##   Around: two annexes off the rim, the machine spots, each with a bridge from its space and a
##     vending machine facing it: the habitat domes with tube corridors and the greenhouse on
##     one, fuel tanks, a solar array and the telescope dome on the other; on the slab a solar
##     farm, cargo stacks, a comms mast,
##     antenna masts, a telescope dome, a drill rig over a crater, oxygen tanks, landing lights
##     around the pad, a pad sign, an arrow post.
##   Alive: a patrol drone flying the loop, a buggy driving the longest clear stretch of rim,
##     blinking lights, a shooting star now and then, a space station turning on the horizon.
## Deterministic from the board id, so every peer sees the same base.

var _view: Node3D
var _graph: BoardGraph
var _slab: MoonSlab            # the moon chunk's outline: the board file's rounded plot
var _centre: Vector3
var _top: float
var _shadow: Color
var _density: float = 1.0        # slab area over the 65-space board's, for the prop counts
var _rng := RandomNumberGenerator.new()
var _occupied: Array = []        # Vector3(x, z, radius) of everything placed, craters and landmarks included
var _mats: Dictionary = {}
var _tile_positions: Array = []  # Vector3 per space
var _annex: Vector3 = Vector3.INF   # centre of the annex platform, if built
var _annex_r: float = 8.0

# Alive things
var _blinkers: Array = []        # [{node, period, phase}]
var _bobbers: Array = []         # [{node, base_y, period}]: the balloon, the pilot, gently up and down
var _spinners: Array = []        # [{node, rate}]: the station's radar dish, turning
var _drone: Node3D
var _drone_path: Array = []      # Vector3 waypoints above the loop
var _drone_t: float = 0.0
var _drone_rotors: Array = []
var _buggy: Node3D
var _buggy_wheels: Array = []
var _buggy_road: Array = []      # Vector3 samples of the longest clear rim arc, or empty
var _road_loop: bool = false     # a closed ring (drive round) rather than an arc (drive back and forth)
var _buggy_t: float = 0.0
var _buggy_len: float = 1.0
var _star: Node3D
var _star_from: Vector3
var _star_to: Vector3
var _star_t: float = 99.0
var _star_next: float = 9.0
var _station: Node3D
var _freighter: Node3D
var _anim_t: float = 0.0
# The vending machines: one per machine spot (a space flagged "goal"), on the annex off the rim
# that a bridge joins to the space. space id → {node, sign, beam, knob, globe, tray}
var _machines: Dictionary = {}
var _active_machine: String = ""
var counts: Dictionary = {}      # what was placed, for the log


## Built in five parts on five frames (the view awaits this under the held wipe; whole, it was
## 41 ms of the first board build's 176 ms frame at 1080p, 2026-09-23): the path, the annexes,
## the props and the ground, the structures and the signs, the living things. Returns the
## milliseconds each part took. A part checks the node is still in the tree first (a peer can
## leave mid-build), and the order and the seeded stream are the single build's, so the base is
## the same on every peer.
func build(view: Node3D, g: BoardGraph, slab: MoonSlab, top: float, craters: Array, landmarks: Array,
		shadow: Color) -> PackedInt32Array:
	_view = view
	_graph = g
	_slab = slab
	_centre = slab.centre
	_top = top
	_shadow = shadow
	# The counts below were set on the 31 × 25 m slab of the 65-space board; a bigger board keeps
	# the same density of hatches, rocks, dust and cracks (per area) and of structures (per rim).
	_density = slab.area() / (PI * 31.0 * 25.0)
	_rng.seed = hash(g.id) + 101
	for sid in g.ids():
		_tile_positions.append(g.get_space(sid).position)
	for cr in craters:
		_occupied.append(Vector3(cr.x, cr.y, cr.z + 0.6))
	for sp in landmarks:   # (x, z, radius)
		_occupied.append(Vector3(sp.x, sp.y, sp.z))
	var times := PackedInt32Array()
	var t := Time.get_ticks_usec()
	_path_details()
	times.append((Time.get_ticks_usec() - t) / 1000)
	await _next_frame()
	if not is_inside_tree():
		return times
	t = Time.get_ticks_usec()
	_build_annexes()
	times.append((Time.get_ticks_usec() - t) / 1000)
	await _next_frame()
	if not is_inside_tree():
		return times
	t = Time.get_ticks_usec()
	_blocks(craters, landmarks)
	times.append((Time.get_ticks_usec() - t) / 1000)
	await _next_frame()
	if not is_inside_tree():
		return times
	t = Time.get_ticks_usec()
	_path_props()
	_plan_road()
	_ground_details()
	times.append((Time.get_ticks_usec() - t) / 1000)
	await _next_frame()
	if not is_inside_tree():
		return times
	t = Time.get_ticks_usec()
	_antennas()
	_signs_and_pennants(landmarks)
	times.append((Time.get_ticks_usec() - t) / 1000)
	await _next_frame()
	if not is_inside_tree():
		return times
	t = Time.get_ticks_usec()
	_life()
	times.append((Time.get_ticks_usec() - t) / 1000)
	return times


## The next rendered frame, never this one (the rule from FpsMatch._next_frame); waits on the
## main loop, not the tree, so a node pulled from the tree mid-build still wakes to stop.
func _next_frame() -> void:
	var f := Engine.get_process_frames()
	await (Engine.get_main_loop() as SceneTree).process_frame
	if Engine.get_process_frames() == f:
		await (Engine.get_main_loop() as SceneTree).process_frame


## The buggy's road: the longest clear stretch of a ring near the rim (on the district, the strip
## of open moon between the ring road and the rim, which the annex bridges cut into two arcs),
## chosen after the annexes (their bridge mouths are reserved) and before the ground props so
## they keep off it. Falls back to a loop around the base annex.
func _plan_road() -> void:
	var samples: Array = []
	var clear: Array = []
	var n := 96
	for i in n:
		var a := i * TAU / n
		var q := _slab.point(a, 0.955)
		var p := Vector3(q.x, _top, q.y)
		samples.append(p)
		clear.append(_tile_clear(p.x, p.z, 2.3) and _prop_clear(p.x, p.z, 1.0))
	var best_start := -1
	var best_len := 0
	for i in n:
		if not clear[i]:
			continue
		var run := 0
		while run < n and clear[(i + run) % n]:
			run += 1
		if run > best_len:
			best_len = run
			best_start = i
	if best_len >= 12:
		for k in best_len:
			_buggy_road.append(samples[(best_start + k) % n])
		_road_loop = best_len >= n
		for p in _buggy_road:
			_occupied.append(Vector3(p.x, p.z, 1.4))


# --- materials and meshes ---------------------------------------------------------------------------

func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"paper": m = CelMaterial.for_colour(Palette.hud_colour("paper"), _shadow)
		"ink": m = CelMaterial.for_colour(Color.from_hsv(Palette.map_colour("board", "line").h, 0.45, 0.24), _shadow)
		"glow_cyan": m = CelMaterial.for_colour(Palette.hud_colour("meter"), _shadow, 1.2)
		"glow_red": m = CelMaterial.for_colour(Palette.hud_colour("danger"), _shadow, 1.5)
		"glow_yellow": m = CelMaterial.for_colour(Palette.hud_colour("score"), _shadow, 1.4)
		"glow_green": m = CelMaterial.for_colour(Palette.map_colour("board", "alien"), _shadow, 1.2)
		"glass": m = CelMaterial.for_colour(Palette.hud_colour("meter"), _shadow, 0.45)
		"accent_lit": m = CelMaterial.for_colour(Palette.map_colour("board", "accent"), _shadow, 0.3)
		"moon": m = CelMaterial.with_print(CelMaterial.for_colour(Palette.map_colour("board", "moon"), _shadow), "moon", Palette.map_colour("board", "line"))
		"moon_light": m = CelMaterial.for_colour(Palette.map_colour("board", "moon").lightened(0.12), _shadow)
		"pavement": m = CelMaterial.for_colour(Palette.map_colour("board", "moon").darkened(0.1), _shadow)
		_:
			if key.begins_with("player"):
				m = CelMaterial.for_colour(Palette.player_colour(int(key.substr(6))), _shadow, 0.15)
			else:
				m = CelMaterial.for_colour(Palette.map_colour("board", key), _shadow)
	_mats[key] = m
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: String, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = _mat(mat)
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r_top: float, r_bottom: float, h: float, pos: Vector3, mat: String,
		rot: Vector3 = Vector3.ZERO, segments: int = 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = h
	cm.radial_segments = segments
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = _mat(mat)
	parent.add_child(mi)
	return mi


func _sphere(parent: Node3D, r: float, pos: Vector3, mat: String, scale: Vector3 = Vector3.ONE,
		hemisphere: bool = false, segments: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = segments
	sm.rings = maxi(4, segments / 2)
	sm.is_hemisphere = hemisphere
	mi.mesh = sm
	mi.position = pos
	mi.scale = scale
	mi.material_override = _mat(mat)
	parent.add_child(mi)
	return mi


func _torus(parent: Node3D, inner: float, outer: float, pos: Vector3, mat: String,
		rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 24
	tm.ring_segments = 6
	mi.mesh = tm
	mi.position = pos
	mi.rotation = rot
	mi.scale = scale
	mi.material_override = _mat(mat)
	parent.add_child(mi)
	return mi


## A segment between two points: a thin cylinder, for cables, strings and struts.
func _strut(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: String, segments: int = 6) -> MeshInstance3D:
	var mi := _cyl(parent, r, r, maxf(0.01, (b - a).length()), (a + b) * 0.5, mat, Vector3.ZERO, segments)
	if (b - a).length() > 0.001:
		mi.look_at(parent.to_global(b) if parent != self else b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	return mi


func _label(parent: Node3D, text: String, pos: Vector3, px: int, colour: Color, yaw: float, outline: int = 10) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = px
	l.pixel_size = 0.006
	l.outline_size = outline
	l.modulate = colour
	l.outline_modulate = Palette.map_colour("board", "line")
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.double_sided = false   # a sign read from behind would mirror; its back panel shows instead
	l.position = pos
	l.rotation.y = yaw
	parent.add_child(l)
	return l


func _node(pos: Vector3, yaw: float = 0.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	add_child(n)
	return n


func _count(what: String) -> void:
	counts[what] = int(counts.get(what, 0)) + 1


# --- placement ------------------------------------------------------------------------------------------

func _tile_clear(x: float, z: float, d: float) -> bool:
	for p in _tile_positions:
		if Vector2(p.x - x, p.z - z).length() < d:
			return false
	return true


func _prop_clear(x: float, z: float, own: float) -> bool:
	for o in _occupied:
		if Vector2(o.x - x, o.y - z).length() < o.z + own:
			return false
	return true


func _inside(x: float, z: float, f_max: float) -> bool:
	return _slab.inside(x, z, f_max)


## A random spot at least `tile_d` from every tile and clear of everything placed, within the
## slab. Returns Vector2.INF when nothing fits in `tries`.
func _spot(tile_d: float, own: float, f_min: float = 0.15, f_max: float = 0.9, tries: int = 300) -> Vector2:
	for i in tries:
		var a := _rng.randf_range(0.0, TAU)
		var f := sqrt(_rng.randf_range(f_min * f_min, f_max * f_max))
		var q := _slab.point(a, f)
		var x := q.x
		var z := q.y
		if _tile_clear(x, z, tile_d) and _prop_clear(x, z, own):
			_occupied.append(Vector3(x, z, own))
			return Vector2(x, z)
	return Vector2.INF


## A random spot in a ring around a point, same rules.
func _spot_near(cx: float, cz: float, r_min: float, r_max: float, tile_d: float, own: float, tries: int = 200) -> Vector2:
	for i in tries:
		var a := _rng.randf_range(0.0, TAU)
		var r := _rng.randf_range(r_min, r_max)
		var x := cx + cos(a) * r
		var z := cz + sin(a) * r
		if _inside(x, z, 0.97) and _tile_clear(x, z, tile_d) and _prop_clear(x, z, own):
			_occupied.append(Vector3(x, z, own))
			return Vector2(x, z)
	return Vector2.INF


# --- on the path --------------------------------------------------------------------------------------

func _path_details() -> void:
	var g := _graph
	var ids := g.ids()
	for i in ids.size():
		var s := g.get_space(ids[i])
		var p := s.position
		# An inset hex on the tile face, a step lighter, so the tiles read as game pieces.
		var tone: Color = _view._tone_for(s.type) if _view.has_method("_tone_for") else Palette.map_colour("board", "field")
		var inset := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.82
		cm.bottom_radius = 0.82
		cm.height = 0.04
		cm.radial_segments = 6
		inset.mesh = cm
		inset.position = p + Vector3(0, 0.02, 0)
		inset.rotation.y = deg_to_rad(30.0)
		inset.material_override = CelMaterial.for_colour(Color(tone).lightened(0.16), _shadow)
		add_child(inset)
		# Collars on the post: one under the tile's cone, one at the foot.
		var post_top := p.y - 1.22
		_torus(self, 0.3, 0.42, Vector3(p.x, post_top - 0.1, p.z), "metal", Vector3.ZERO, Vector3(1, 0.5, 1))
		_torus(self, 0.3, 0.44, Vector3(p.x, _top + 0.42, p.z), "metal", Vector3.ZERO, Vector3(1, 0.5, 1))
		for n in s.next:
			var q := g.get_space(n).position
			# A stripe down the middle of the plank ahead.
			var mid := (p + q) * 0.5 - Vector3(0, 0.045, 0)
			var length := maxf(0.2, (q - p).length() - 2.0)
			# The street under the walkway: a paved band on the moon from post to post, so the
			# walkways read as streets and the blocks between them as blocks (2026-09-24).
			var band := _box(self, Vector3(3.0, 0.02, (q - p).length() + 1.6), Vector3.ZERO, "pavement")
			band.global_position = Vector3(mid.x, _top + 0.012, mid.z)
			if (q - p).length() > 0.01:
				band.look_at(Vector3(q.x, _top + 0.012, q.z), Vector3.UP)
			band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var stripe := _box(self, Vector3(0.12, 0.02, length * 0.9), Vector3.ZERO, "paper")
			stripe.global_position = mid
			if (q - p).length() > 0.01:
				stripe.look_at(q, Vector3.UP)
			# A chevron at the stripe's far end: every street is one-way (2026-09-24), and the
			# reference board draws an arrow on every link.
			var head := MeshInstance3D.new()
			var hm := PrismMesh.new()
			hm.size = Vector3(0.46, 0.4, 0.02)
			head.mesh = hm
			head.material_override = _mat("paper")
			add_child(head)
			head.global_position = mid + (q - p).normalized() * (length * 0.45 + 0.24)
			if (q - p).length() > 0.01:
				head.look_at(q, Vector3.UP)
				head.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
			# Two cables slung under the plank between the posts, sagging in the middle.
			var a := Vector3(p.x, post_top - 0.25, p.z)
			var b := Vector3(q.x, q.y - 1.22 - 0.25, q.z)
			var sag := (a + b) * 0.5 - Vector3(0, 0.55, 0)
			for cable in 2:
				var off := Vector3(0, -0.12 * cable, 0)
				var c1 := _strut(self, a + off, sag + off, 0.03, "ink", 5)
				c1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var c2 := _strut(self, sag + off, b + off, 0.03, "ink", 5)
				c2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# A lamp beside every fifth space, on the side away from the centre.
		if i % 5 == 2 and not s.next.is_empty():
			var q := g.get_space(s.next[0]).position
			var dir := Vector2(q.x - p.x, q.z - p.z).normalized()
			var side := Vector2(-dir.y, dir.x)   # the right-hand side of travel, like a street's lamps
			var lp := Vector2(p.x, p.z) + side * 2.3
			if _tile_clear(lp.x, lp.y, 1.9) and _prop_clear(lp.x, lp.y, 0.6) and _inside(lp.x, lp.y, 0.97):
				_occupied.append(Vector3(lp.x, lp.y, 0.6))
				var lamp := _node(Vector3(lp.x, _top, lp.y))
				_cyl(lamp, 0.09, 0.13, 3.0, Vector3(0, 1.5, 0), "counter_dark")
				_cyl(lamp, 0.24, 0.24, 0.1, Vector3(0, 0.05, 0), "metal")
				_box(lamp, Vector3(0.44, 0.34, 0.44), Vector3(0, 3.15, 0), "glass")
				_box(lamp, Vector3(0.52, 0.08, 0.52), Vector3(0, 3.36, 0), "counter_dark")
				_box(lamp, Vector3(0.52, 0.06, 0.52), Vector3(0, 2.97, 0), "counter_dark")
				_count("lamp")


## Small props beside the walkway every fourth space, cycling through five kinds, alternating
## the outer and inner side, so the close camera always has something next to the path.
func _path_props() -> void:
	var g := _graph
	var ids := g.ids()
	for i in ids.size():
		if i % 4 != 0:
			continue
		var s := g.get_space(ids[i])
		if s.next.is_empty():
			continue
		var p := s.position
		var q := g.get_space(s.next[0]).position
		var dir := Vector2(q.x - p.x, q.z - p.z).normalized()
		var side := Vector2(-dir.y, dir.x)
		if (i / 4) % 2 == 1:
			side = -side
		var pp := Vector2(p.x, p.z) + side * 2.4
		if not (_tile_clear(pp.x, pp.y, 1.9) and _prop_clear(pp.x, pp.y, 0.7) and _inside(pp.x, pp.y, 0.96)):
			continue
		_occupied.append(Vector3(pp.x, pp.y, 0.7))
		var n := _node(Vector3(pp.x, _top, pp.y), _rng.randf_range(0.0, TAU))
		match (i / 4) % 5:
			0:   # two traffic cones with white bands
				for cx: float in [-0.35, 0.35]:
					_cyl(n, 0.03, 0.22, 0.6, Vector3(cx, 0.3, 0), "accent_lit", Vector3.ZERO, 8)
					_box(n, Vector3(0.5, 0.04, 0.5), Vector3(cx, 0.02, 0), "ink")
					_torus(n, 0.1, 0.16, Vector3(cx, 0.36, 0), "paper", Vector3.ZERO, Vector3(1, 0.4, 1))
				_count("cones")
			1:   # a bin with a lid and a glowing slot
				_cyl(n, 0.3, 0.28, 0.8, Vector3(0, 0.4, 0), "counter_dark", Vector3.ZERO, 10)
				_cyl(n, 0.34, 0.34, 0.08, Vector3(0, 0.84, 0), "metal", Vector3.ZERO, 10)
				_box(n, Vector3(0.3, 0.06, 0.04), Vector3(0, 0.66, 0.29), "glow_cyan")
				_count("bin")
			2:   # an info kiosk: a post, a screen, a little dish
				_cyl(n, 0.06, 0.08, 1.7, Vector3(0, 0.85, 0), "counter_dark")
				_box(n, Vector3(0.7, 0.5, 0.08), Vector3(0, 1.5, 0), "ink")
				_box(n, Vector3(0.6, 0.4, 0.04), Vector3(0, 1.5, 0.04), "glass")
				_cyl(n, 0.2, 0.05, 0.1, Vector3(0.1, 1.95, 0), "paper", Vector3(-0.6, 0, 0), 8)
				_count("kiosk")
			3:   # a cable spool on its side
				_cyl(n, 0.5, 0.5, 0.08, Vector3(-0.3, 0.5, 0), "paper", Vector3(0, 0, PI * 0.5), 12)
				_cyl(n, 0.5, 0.5, 0.08, Vector3(0.3, 0.5, 0), "paper", Vector3(0, 0, PI * 0.5), 12)
				_cyl(n, 0.3, 0.3, 0.56, Vector3(0, 0.5, 0), "counter_dark", Vector3(0, 0, PI * 0.5), 10)
				_box(n, Vector3(0.9, 0.06, 0.06), Vector3(0, 0.45, 0.3), "ink")
				_count("spool")
			_:   # a lone crate with a strap
				_box(n, Vector3(0.9, 0.9, 0.9), Vector3(0, 0.45, 0), "field_dark" if i % 8 == 0 else "accent_lit")
				_box(n, Vector3(0.94, 0.14, 0.94), Vector3(0, 0.45, 0), "counter_dark")
				_count("crate")


# --- on the ground ------------------------------------------------------------------------------------

func _ground_details() -> void:
	# Hatches: a plate with a rim and a light, flush with the ground (a dozen or so: at the
	# loop board's density they were 56 white squares across the district's map).
	for k in roundi(5 * sqrt(_density)):
		var sp := _spot(2.1, 1.0, 0.1, 0.92, 200)
		if sp == Vector2.INF:
			break
		var h := _node(Vector3(sp.x, _top, sp.y), _rng.randf_range(0.0, TAU))
		if k % 3 == 0:
			_cyl(h, 0.95, 0.95, 0.08, Vector3(0, 0.04, 0), "metal", Vector3.ZERO, 12)
			_torus(h, 0.86, 1.0, Vector3(0, 0.08, 0), "counter_dark", Vector3.ZERO, Vector3(1, 0.5, 1))
			_box(h, Vector3(0.5, 0.06, 0.1), Vector3(0, 0.11, 0), "ink")
		else:
			_box(h, Vector3(1.6, 0.08, 1.6), Vector3(0, 0.04, 0), "metal")
			_box(h, Vector3(1.7, 0.03, 0.12), Vector3(0, 0.09, 0.79), "counter_dark")
			_box(h, Vector3(1.7, 0.03, 0.12), Vector3(0, 0.09, -0.79), "counter_dark")
			_box(h, Vector3(0.12, 0.03, 1.7), Vector3(0.79, 0.09, 0), "counter_dark")
			_box(h, Vector3(0.12, 0.03, 1.7), Vector3(-0.79, 0.09, 0), "counter_dark")
			_box(h, Vector3(0.18, 0.05, 0.18), Vector3(0.55, 0.1, 0.55), "glow_yellow" if k % 2 == 0 else "glow_cyan")
		_count("hatch")
	# Rock clusters: a few boulders of different sizes and a scatter of pebbles.
	for k in roundi(10 * _density):
		var sp := _spot(2.3, 1.7, 0.1, 0.95, 200)
		if sp == Vector2.INF:
			break
		_rock_cluster(Vector3(sp.x, _top, sp.y))
	# Loose pebbles anywhere the ground is bare.
	for k in roundi(60 * _density):
		var a := _rng.randf_range(0.0, TAU)
		var f := sqrt(_rng.randf_range(0.02, 0.9))
		var q := _slab.point(a, f)
		var x := q.x
		var z := q.y
		if not _tile_clear(x, z, 1.5):
			continue
		var r := _rng.randf_range(0.07, 0.15)
		var p := _sphere(self, r, Vector3(x, _top + r * 0.5, z), "moon_dark" if k % 2 == 0 else "crater", Vector3(1.3, 0.6, 1.0), false, 6)
		p.rotation.y = _rng.randf_range(0.0, TAU)
	# Dust patches: a shade off the slab, thin, so the flat ground is not one tone.
	for k in roundi(9 * _density):
		var a := _rng.randf_range(0.0, TAU)
		var f := sqrt(_rng.randf_range(0.05, 0.85))
		var q := _slab.point(a, f)
		var x := q.x
		var z := q.y
		if not _tile_clear(x, z, 2.0):
			continue
		var d := _sphere(self, _rng.randf_range(1.6, 3.2), Vector3(x, _top - 0.02, z), "moon_light" if k % 2 == 0 else "moon_dark",
			Vector3(1.0, 0.012, _rng.randf_range(0.6, 1.0)), false, 9)
		d.rotation.y = _rng.randf_range(0.0, TAU)
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Rim edge: chunks of rock along the slab's edge so it reads as a cliff, not a cut.
	for k in roundi(22 * sqrt(_density)):
		var a := k * TAU / 22.0 + _rng.randf_range(-0.1, 0.1)
		var q := _slab.point(a, _rng.randf_range(0.99, 1.04))
		var x := q.x
		var z := q.y
		var r := _rng.randf_range(0.5, 1.4)
		var chunk := _sphere(self, r, Vector3(x, _top - _rng.randf_range(0.2, 1.4), z), "rock" if k % 3 != 0 else "moon_dark",
			Vector3(_rng.randf_range(0.8, 1.4), _rng.randf_range(0.6, 1.1), _rng.randf_range(0.8, 1.4)), false, 7)
		chunk.rotation = Vector3(_rng.randf_range(0, 1), _rng.randf_range(0.0, TAU), 0)
	# Cracks in the surface: thin dark lines in a few places.
	for k in roundi(8 * _density):
		var sp := _spot(2.2, 1.4, 0.1, 0.9, 150)
		if sp == Vector2.INF:
			break
		var cn := _node(Vector3(sp.x, _top + 0.005, sp.y), _rng.randf_range(0.0, TAU))
		var segs := 3 + _rng.randi() % 3
		var at := Vector3.ZERO
		var heading := 0.0
		for s in segs:
			var len := _rng.randf_range(0.7, 1.4)
			var seg := _box(cn, Vector3(0.08, 0.02, len), at + Vector3(sin(heading), 0, cos(heading)) * len * 0.5, "crater", Vector3(0, heading, 0))
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			at += Vector3(sin(heading), 0, cos(heading)) * len
			heading += _rng.randf_range(-0.9, 0.9)


# --- the annex: a second, smaller chunk off the rim, joined by a bridge ------------------------------

## The vending machine on an annex, facing the bridge (a node's -Z looks down the bridge when
## `dir` is the annex's outward direction): a ticket slot, a knob, a tray, a glass globe of capsules,
## a TOYS marquee and a light beam that only the live one shows.
func _machine(sid: String, at: Vector3, dir: Vector2) -> void:
	var yaw := atan2(dir.x, dir.y)
	var m := _node(at, yaw)
	_box(m, Vector3(1.3, 2.0, 1.0), Vector3(0, 1.0, 0), "metal")
	_box(m, Vector3(1.34, 0.1, 1.04), Vector3(0, 0.05, 0), "counter_dark")
	_box(m, Vector3(1.34, 0.1, 1.04), Vector3(0, 2.0, 0), "counter_dark")
	for sx: float in [-0.67, 0.67]:
		_box(m, Vector3(0.04, 1.6, 0.8), Vector3(sx, 1.05, 0), "accent_lit")
	_box(m, Vector3(1.1, 0.9, 0.04), Vector3(0, 1.45, -0.51), "ink")   # the front panel
	_box(m, Vector3(0.16, 0.05, 0.06), Vector3(0.38, 1.7, -0.53), "glow_yellow")   # ticket slot
	_label(m, "¥", Vector3(0.38, 1.85, -0.54), 40, Palette.hud_colour("paper"), PI, 0)
	var knob := Node3D.new()
	knob.position = Vector3(-0.28, 1.3, -0.52)
	m.add_child(knob)
	_cyl(knob, 0.17, 0.17, 0.12, Vector3.ZERO, "accent_lit", Vector3(PI * 0.5, 0, 0), 12)
	_box(knob, Vector3(0.28, 0.05, 0.06), Vector3(0, 0, -0.06), "ink")
	_box(m, Vector3(0.8, 0.36, 0.3), Vector3(0, 0.5, -0.45), "counter_dark")   # the tray
	_box(m, Vector3(0.6, 0.22, 0.1), Vector3(0, 0.5, -0.56), "ink")
	var globe := _node(m.position + Vector3(0, 2.62, 0), yaw)
	_cyl(m, 0.5, 0.55, 0.16, Vector3(0, 2.08, 0), "counter_dark", Vector3.ZERO, 12)
	# The globe is real glass (the one translucent material on the board, like the sniper's
	# lens): the capsules inside are the whole point of a capsule machine.
	var glass := _sphere(globe, 0.62, Vector3.ZERO, "glass", Vector3.ONE, false, 16)
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tint := Palette.hud_colour("meter")
	gm.albedo_color = Color(tint.r, tint.g, tint.b, 0.28)
	gm.metallic = 0.6
	gm.roughness = 0.15
	gm.cull_mode = BaseMaterial3D.CULL_BACK
	gm.render_priority = 4
	glass.material_override = gm
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in 7:
		var ca := c * 2.4
		var cr := 0.28 + 0.1 * (c % 3)
		var cap := _sphere(globe, 0.12, Vector3(cos(ca) * cr * 0.9, -0.3 + 0.13 * (c % 4), sin(ca) * cr * 0.9), "player%d" % (c % 6), Vector3.ONE, false, 8)
		cap.scale = Vector3(1, 0.8, 1)
	_cyl(globe, 0.16, 0.16, 0.2, Vector3(0, 0.65, 0), "counter_dark", Vector3.ZERO, 8)
	var sign := _box(m, Vector3(1.5, 0.4, 0.34), Vector3(0, 3.55, 0), "counter_dark")
	_label(m, "TOYS", Vector3(0, 3.6, -0.18), 56, Palette.hud_colour("paper"), PI, 0)
	var beam := _cyl(m, 0.2, 0.3, 14.0, Vector3(0, 3.8 + 7.0, 0), "glass", Vector3.ZERO, 8)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visible = false
	_occupied.append(Vector3(at.x, at.z, 1.6))
	_machines[sid] = {"node": m, "sign": sign, "beam": beam, "knob": knob, "globe": globe,
		"tray": m.position + Vector3(0, 0.6, 0) - Vector3(dir.x, 0, dir.y) * 0.6}
	_count("vending machine")


## Light the machine the players can buy from; the rest stand dark.
func set_active_machine(space_id: String) -> void:
	_active_machine = space_id
	for sid in _machines:
		var mach: Dictionary = _machines[sid]
		var on: bool = str(sid) == space_id
		(mach["sign"] as MeshInstance3D).material_override = _mat("glow_yellow" if on else "counter_dark")
		(mach["beam"] as Node3D).visible = on


## A purchase at the machine on `spot` (the one lit before the state moved on): its knob turns and
## a capsule in the buyer's colour pops out of the tray and arcs to the pawn.
func vend(spot: String, to: Vector3, colour: Color) -> void:
	var key := spot if _machines.has(spot) else _active_machine
	if not _machines.has(key):
		return
	var mach: Dictionary = _machines[key]
	var knob: Node3D = mach["knob"]
	var tw := create_tween()
	tw.tween_property(knob, "rotation:z", knob.rotation.z + PI, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var capsule := Node3D.new()
	add_child(capsule)
	var top := _sphere(capsule, 0.24, Vector3.ZERO, "paper", Vector3.ONE, true, 10)
	top.material_override = CelMaterial.for_colour(colour, _shadow, 0.3)
	var bottom := _sphere(capsule, 0.24, Vector3.ZERO, "paper", Vector3(1, -1, 1), true, 10)
	bottom.rotation.x = PI
	var from: Vector3 = mach["tray"]
	capsule.position = from
	var flight := create_tween()
	flight.tween_method(func(t: float):
		var pos := from.lerp(to + Vector3(0, 1.2, 0), t)
		pos.y += sin(t * PI) * 2.5
		capsule.position = pos
		capsule.rotation.y = t * TAU * 2.0, 0.0, 1.0, 0.9).set_delay(0.35).set_trans(Tween.TRANS_SINE)
	flight.tween_callback(capsule.queue_free)


## The two annexes off the rim carry the vending machines (Sean: "those original two spots",
## never more). Each stands straight out from a machine spot, the spaces flagged "goal" in the
## board file: `tools/mark_spots.gd` flags the space nearest each angle where the walkway sits
## farthest from the rim (`AnnexPlan.angles`, the search that placed the annexes before they
## carried anything), and the same search pairs them here so the habitat domes stay on the first
## and the works on the second. A level plated bridge joins the space to the chunk; the machine
## stands on the chunk facing the bridge with the decor behind it. A board with more machine
## spots gets a bare chunk for each extra one.
func _build_annexes() -> void:
	var spots: Array = []
	for sid in _graph.goal_candidates():
		spots.append(str(sid))
	if spots.is_empty():
		return
	var plan: Array = []   # [angle, space id] per annex, the searched angles first
	for a in AnnexPlan.angles(_tile_positions, _slab, _graph.annex_angles):
		var rim := _slab.rim(a)
		var best := ""
		var best_d := 1e9
		for sid in spots:
			var p: Vector3 = _graph.get_space(sid).position
			var d := Vector2(p.x - rim.x, p.z - rim.y).length()
			if d < best_d:
				best_d = d
				best = sid
		if best != "":
			# The annex stands straight out from its space (a level, straight bridge): the step from
			# the searched angle to the space's own ray is a few degrees.
			var bp: Vector3 = _graph.get_space(best).position
			plan.append([_slab.angle_of(bp.x, bp.z), best])
			spots.erase(best)
	for sid in spots:
		var p: Vector3 = _graph.get_space(sid).position
		plan.append([_slab.angle_of(p.x, p.z), sid])
	var k := 0
	for entry in plan:
		var a: float = entry[0]
		var sid: String = entry[1]
		var p: Vector3 = _graph.get_space(sid).position
		var radius := 8.0 if k == 0 else 7.5
		var base := _annex_platform(a, radius, p)
		var centre: Vector3 = base["centre"]
		var dir: Vector2 = base["dir"]   # along the bridge, outward
		var d3 := Vector3(dir.x, 0, dir.y)
		var s3 := Vector3(-dir.y, 0, dir.x)
		_machine(sid, centre - d3 * (radius - 3.6), dir)
		if k == 0:
			_annex = centre
			_annex_r = radius
			_habitat(centre + d3 * 1.8, a + PI)
			_greenhouse(centre + s3 * 4.6 + d3 * 1.6, a + PI * 0.5)
			_cargo(centre - s3 * 5.2 + d3 * 2.4, a, 4)
		elif k == 1:
			_fuel_tanks(centre + d3 * 1.8, a + PI * 0.5)
			_solar_array(centre + s3 * 4.2 - d3 * 0.6, a, 2)
			_telescope(centre - s3 * 4.4 + d3 * 0.2, a + 0.6)
			var an := _node(centre + d3 * 5.6 + s3 * 2.5)
			_cyl(an, 0.3, 0.3, 0.3, Vector3(0, 0.15, 0), "metal")
			_cyl(an, 0.04, 0.06, 3.4, Vector3(0, 2.0, 0), "ink")
			var b := _sphere(an, 0.12, Vector3(0, 3.8, 0), "glow_cyan", Vector3.ONE, false, 8)
			_blinkers.append({"node": b, "period": 1.6, "phase": 0.4})
		k += 1


## A chunk off the rim at angle `a`, its deck at the tile height of `from_space`, joined to that
## space by a level plated bridge with rails, lamps at both ends and posts to the ground where it
## runs over the slab. Returns its centre and the bridge's outward direction; reserves the bridge
## and the rim mouth so the road, props and landmarks keep off.
func _annex_platform(a: float, radius: float, from_space: Vector3) -> Dictionary:
	var rim_pt := _slab.rim(a)
	var out := (rim_pt - Vector2(_centre.x, _centre.z)).normalized()
	var c2 := rim_pt + out * (radius + 3.0)
	var deck_y := from_space.y - 0.2
	var centre := Vector3(c2.x, deck_y, c2.y)
	var dir := (c2 - Vector2(from_space.x, from_space.z)).normalized()
	var d3 := Vector3(dir.x, 0, dir.y)
	_occupied.append(Vector3(rim_pt.x, rim_pt.y, 3.2))
	var h := deck_y - (_top - 2.6)
	var slab := _cyl(self, radius, radius * 0.94, h, centre + Vector3(0, -h * 0.5, 0), "moon", Vector3.ZERO, 9)
	slab.rotation.y = a
	var root := _cyl(self, radius * 0.9, radius * 0.2, 8.0, centre + Vector3(0, -h - 4.0, 0), "moon_dark", Vector3.ZERO, 9)
	root.rotation.y = a + 0.3
	for k in 10:
		var ca := k * TAU / 10.0
		var r := _rng.randf_range(0.5, 1.2)
		var chunk := _sphere(self, r, centre + Vector3(cos(ca) * radius, -_rng.randf_range(0.3, 1.2), sin(ca) * radius), "rock" if k % 3 != 0 else "moon_dark",
			Vector3(_rng.randf_range(0.8, 1.3), _rng.randf_range(0.6, 1.0), _rng.randf_range(0.8, 1.3)), false, 7)
		chunk.rotation.y = _rng.randf_range(0.0, TAU)
	# Pebbles and a dust patch on the annex too.
	for k in 8:
		var pa := _rng.randf_range(0.0, TAU)
		var pr := _rng.randf_range(0.0, radius * 0.9)
		var r := _rng.randf_range(0.07, 0.14)
		_sphere(self, r, centre + Vector3(cos(pa) * pr, r * 0.5, sin(pa) * pr), "moon_dark" if k % 2 == 0 else "crater", Vector3(1.3, 0.6, 1.0), false, 6)
	# The bridge: a plated walkway from the space's outer edge to the chunk, level at tile height,
	# with rails and lamps at both ends. Its corridor is off limits to props, signs and landmarks.
	var from := from_space + d3 * 1.25 + Vector3(0, -0.12, 0)
	var to := centre - d3 * (radius - 1.0) + Vector3(0, 0.1, 0)
	var mid := (from + to) * 0.5
	var length := (to - from).length()
	var yaw := atan2(dir.x, dir.y)
	var corridor := maxi(2, int(length) + 2)
	for k in corridor:
		var c := (from - d3 * 0.6).lerp(to, float(k) / float(corridor - 1))
		_occupied.append(Vector3(c.x, c.z, 2.2))
	_box(self, Vector3(3.2, 0.2, length), mid, "metal", Vector3(0, yaw, 0))
	for side: float in [-1.0, 1.0]:
		var rail_off := Vector3(-dir.y, 0, dir.x) * side * 1.5
		_box(self, Vector3(0.1, 0.1, length), mid + rail_off + Vector3(0, 1.0, 0), "counter_dark", Vector3(0, yaw, 0))
		var posts := int(length / 1.6) + 1
		for k in posts:
			var t := (k + 0.5) / posts
			_box(self, Vector3(0.08, 1.0, 0.08), from.lerp(to, t) + rail_off + Vector3(0, 0.5, 0), "counter_dark")
		for endp in [from, to]:
			var lamp := _node(endp + rail_off)
			_cyl(lamp, 0.06, 0.08, 2.2, Vector3(0, 1.1, 0), "counter_dark")
			_box(lamp, Vector3(0.3, 0.26, 0.3), Vector3(0, 2.3, 0), "glass")
			_box(lamp, Vector3(0.36, 0.06, 0.36), Vector3(0, 2.46, 0), "counter_dark")
	var plates := maxi(1, int(length / 1.2))
	for k in plates:
		var t := (k + 0.5) / plates
		_box(self, Vector3(3.0, 0.03, 0.14), from.lerp(to, t) + Vector3(0, 0.12, 0), "counter_dark", Vector3(0, yaw, 0))
	# Posts to the ground under the stretch over the slab; the rest hangs over the drop.
	var supports := maxi(1, int(length / 2.4))
	for k in supports:
		var sp := from.lerp(to, (k + 0.5) / supports)
		var hgt := sp.y - 0.1 - _top
		if hgt > 0.3 and _inside(sp.x, sp.z, 0.985):
			_cyl(self, 0.1, 0.14, hgt, Vector3(sp.x, _top + hgt * 0.5, sp.z), "counter_dark", Vector3.ZERO, 8)
	_count("annex")
	return {"centre": centre, "dir": dir}


func _fuel_tanks(at: Vector3, yaw: float) -> void:
	var tn := _node(at, yaw)
	for i in 3:
		var z := i * 1.7 - 1.7
		for cx: float in [-1.1, 1.1]:
			_box(tn, Vector3(0.5, 0.5, 1.2), Vector3(cx, 0.25, z), "counter_dark")
		_cyl(tn, 0.65, 0.65, 3.4, Vector3(0, 0.95, z), "paper", Vector3(0, 0, PI * 0.5), 12)
		_sphere(tn, 0.65, Vector3(1.7, 0.95, z), "paper", Vector3(0.5, 1, 1), false, 10)
		_sphere(tn, 0.65, Vector3(-1.7, 0.95, z), "paper", Vector3(0.5, 1, 1), false, 10)
		for hx: float in [-0.9, 0.9]:
			_torus(tn, 0.64, 0.72, Vector3(hx, 0.95, z), "counter_dark", Vector3(0, 0, PI * 0.5))
		_box(tn, Vector3(0.5, 0.36, 1.32), Vector3(0.0, 0.95, z), "accent_lit")
		_torus(tn, 0.14, 0.2, Vector3(0.0, 1.65, z), "ink", Vector3(PI * 0.5, 0, 0))
	# A pipe manifold along the tanks and a pump box.
	_cyl(tn, 0.09, 0.09, 5.4, Vector3(2.3, 0.5, 0), "counter_dark", Vector3(PI * 0.5, 0, 0), 8)
	_box(tn, Vector3(0.9, 0.9, 0.9), Vector3(2.3, 0.45, 2.9), "metal")
	_box(tn, Vector3(0.3, 0.2, 0.1), Vector3(2.3, 0.7, 3.36), "glow_red")
	_count("fuel tanks")


func _solar_array(at: Vector3, yaw: float, rows: int) -> void:
	var fnode := _node(at, yaw)
	for row in rows:
		for col in 3:
			var pp := Vector3(col * 1.9 - 1.9, 0, row * 2.4 - (rows - 1) * 1.2)
			_cyl(fnode, 0.07, 0.09, 0.9, pp + Vector3(0, 0.45, 0), "counter_dark")
			_box(fnode, Vector3(1.7, 0.06, 1.1), pp + Vector3(0, 1.0, 0), "field_dark", Vector3(-0.55, 0, 0))
			_box(fnode, Vector3(1.6, 0.02, 0.06), pp + Vector3(0, 1.03, 0), "metal", Vector3(-0.55, 0, 0))
	_box(fnode, Vector3(0.6, 0.7, 0.4), Vector3(3.0, 0.35, 0), "metal")
	_box(fnode, Vector3(0.2, 0.2, 0.08), Vector3(3.0, 0.5, 0.22), "glow_green")
	_count("solar array")


func _telescope(at: Vector3, yaw: float) -> void:
	var tn := _node(at, yaw)
	_cyl(tn, 1.7, 1.8, 1.4, Vector3(0, 0.7, 0), "metal", Vector3.ZERO, 14)
	_sphere(tn, 1.7, Vector3(0, 1.4, 0), "paper", Vector3.ONE, true, 14)
	_box(tn, Vector3(0.5, 1.8, 1.8), Vector3(0, 2.3, 0.4), "counter_dark", Vector3(-0.6, 0, 0))
	_cyl(tn, 0.22, 0.28, 2.2, Vector3(0, 2.6, 0.9), "ink", Vector3(-0.9, 0, 0), 10)
	_box(tn, Vector3(0.9, 1.6, 0.4), Vector3(1.4, 0.8, 0.9), "counter_dark")
	_box(tn, Vector3(0.5, 0.9, 0.12), Vector3(1.4, 0.8, 1.11), "metal")
	_count("telescope")


func _habitat(at: Vector3, yaw: float, label: String = "HAB 1") -> void:
	var h := _node(at, yaw)
	var domes := [Vector3(0, 0, 0), Vector3(4.0, 0, 1.4), Vector3(1.2, 0, -3.6)]
	var radii := [2.3, 1.7, 1.5]
	for i in domes.size():
		var d: Vector3 = domes[i]
		var r: float = radii[i]
		_cyl(h, r * 1.05, r * 1.1, 0.5, d + Vector3(0, 0.25, 0), "metal", Vector3.ZERO, 16)
		_sphere(h, r, d + Vector3(0, 0.5, 0), "paper", Vector3.ONE, true, 16)
		_torus(h, r * 0.98, r * 1.1, d + Vector3(0, 0.5, 0), "counter_dark", Vector3.ZERO, Vector3(1, 0.45, 1))
		# Seams up the dome, a cap on top and a ring of small lights round the base.
		for seam in 4:
			var sa := seam * PI / 4.0
			var band := _torus(h, r * 0.99, r * 1.02, d + Vector3(0, 0.5, 0), "metal", Vector3(0, sa, PI * 0.5), Vector3(1, 1, 1))
			band.scale = Vector3(1.0, 1.0, 1.0)
		_cyl(h, r * 0.22, r * 0.26, 0.24, d + Vector3(0, 0.5 + r - 0.02, 0), "counter_dark", Vector3.ZERO, 10)
		_cyl(h, r * 0.16, r * 0.16, 0.14, d + Vector3(0, 0.5 + r + 0.16, 0), "metal", Vector3.ZERO, 8)
		for lt in 6:
			var la := lt * TAU / 6.0 + 0.2
			_sphere(h, 0.09, d + Vector3(cos(la) * r * 1.06, 0.62, sin(la) * r * 1.06), "glow_cyan" if lt % 2 == 0 else "glow_yellow", Vector3.ONE, false, 6)
		var nwin := 5 if i == 0 else 3
		for w in nwin:
			var a := w * TAU / nwin + 0.4
			var wp := d + Vector3(cos(a) * r * 0.9, 0.5 + r * 0.4, sin(a) * r * 0.9)
			var win := _cyl(h, 0.26, 0.26, 0.1, wp, "glass", Vector3.ZERO, 10)
			win.look_at(h.to_global(d + Vector3(0, 0.5 + r * 0.4, 0)), Vector3.UP)
			win.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		if i > 0:
			var from: Vector3 = domes[0]
			var to: Vector3 = d
			var mid := (from + to) * 0.5 + Vector3(0, 1.0, 0)
			var tube := _cyl(h, 0.6, 0.6, (to - from).length() - r - radii[0] + 1.4, mid, "metal", Vector3.ZERO, 10)
			tube.look_at(h.to_global(to + Vector3(0, 1.0, 0)), Vector3.UP)
			tube.rotate_object_local(Vector3.RIGHT, PI * 0.5)
			for k in 2:
				var ring := _torus(h, 0.58, 0.72, mid + (to - from).normalized() * (k - 0.5) * 1.6, "counter_dark")
				ring.look_at(h.to_global(to + Vector3(0, 1.0, 0)), Vector3.UP)
				ring.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	# Airlock on the big dome, facing the bridge.
	_box(h, Vector3(0.5, 1.8, 1.3), Vector3(2.3, 1.2, -0.3), "counter_dark")
	_box(h, Vector3(0.2, 1.4, 0.9), Vector3(2.58, 1.1, -0.3), "metal")
	_box(h, Vector3(0.12, 0.3, 0.3), Vector3(2.7, 1.4, -0.3), "glow_yellow")
	_label(h, label, Vector3(2.72, 2.55, -0.3), 48, Palette.hud_colour("paper"), PI * 0.5)
	# Antenna with a blinking red light, and a dish on the small dome.
	_cyl(h, 0.05, 0.07, 2.6, Vector3(0, 2.8 + 1.3, 0), "ink")
	var blink := _sphere(h, 0.16, Vector3(0, 5.5, 0), "glow_red", Vector3.ONE, false, 8)
	_blinkers.append({"node": blink, "period": 1.3, "phase": 0.0})
	var dish := _cyl(h, 0.7, 0.12, 0.3, Vector3(1.2, 2.5, -3.6), "paper", Vector3(-0.9, 0.0, 0.0), 12)
	dish.rotation.y = 0.6
	# Oxygen tanks by the airlock.
	var on := _node(at + Vector3(sin(yaw) * 3.6, 0, cos(yaw) * 3.6), yaw)
	_oxygen(on, 0)
	_count("habitat")


func _greenhouse(at: Vector3, yaw: float) -> void:
	var gn := _node(at, yaw)
	_box(gn, Vector3(3.6, 0.3, 2.4), Vector3(0, 0.15, 0), "metal")
	for i in 6:
		var px := (i % 3) * 1.1 - 1.1
		var pz := (i / 3) * 1.1 - 0.55
		_cyl(gn, 0.22, 0.26, 0.4, Vector3(px, 0.5, pz), "counter_dark")
		_sphere(gn, 0.34, Vector3(px, 0.95, pz), "glow_green", Vector3(1, 0.8, 1), false, 8)
	_box(gn, Vector3(3.7, 1.7, 2.5), Vector3(0, 1.15, 0), "glass")
	for ex: float in [-1.85, 1.85]:
		_box(gn, Vector3(0.1, 1.8, 2.6), Vector3(ex, 1.2, 0), "counter_dark")
	_box(gn, Vector3(3.8, 0.1, 0.1), Vector3(0, 2.05, 0), "counter_dark")
	_cyl(gn, 0.45, 0.45, 1.6, Vector3(2.6, 0.8, 0.6), "paper")
	_count("greenhouse")


func _cargo(at: Vector3, yaw: float, n: int) -> void:
	var cs := _node(at, yaw)
	var tones := ["metal", "field_dark", "accent_lit", "counter"]
	for i in n:
		var lvl := i / 2
		var off := Vector3((i % 2) * 1.5 - 0.75, 0.4 + lvl * 0.82, _rng.randf_range(-0.2, 0.2))
		var y := _rng.randf_range(-0.2, 0.2)
		_box(cs, Vector3(1.4, 0.8, 0.8), off, tones[i % tones.size()], Vector3(0, y, 0))
		_box(cs, Vector3(1.44, 0.14, 0.84), off, "counter_dark", Vector3(0, y, 0))
	_count("cargo stack")


func _oxygen(on: Node3D, k: int) -> void:
	_box(on, Vector3(1.3, 0.12, 0.7), Vector3(0, 0.06, 0), "counter_dark")
	for tx: float in [-0.32, 0.32]:
		_cyl(on, 0.24, 0.24, 1.3, Vector3(tx, 0.77, 0), "glass" if k == 1 else "paper", Vector3.ZERO, 10)
		_sphere(on, 0.24, Vector3(tx, 1.42, 0), "paper", Vector3(1, 0.6, 1), false, 8)
		_cyl(on, 0.06, 0.06, 0.2, Vector3(tx, 1.62, 0), "ink")
	_box(on, Vector3(0.9, 0.16, 0.16), Vector3(0, 1.1, 0.3), "accent_lit")
	_count("oxygen tanks")


# --- the blocks: a set-piece in every open space between the streets ------------------------------

## A point in a block: its centre plus an offset turned by its yaw.
func _at(c: Vector3, yaw: float, dx: float, dz: float) -> Vector3:
	return c + Vector3(dx, 0.0, dz).rotated(Vector3.UP, yaw)


## The district's blocks (`BoardGraph.zones`, tools/gen_board.gd): each a disc the walkways keep
## clear of, holding one part of the base, so the open spaces between the streets read as a
## place (Sean, 2026-09-24: "decorative stuff about the map in the open spaces... make the
## entire map cohesive"). The view's five landmark props already stand on theirs (the rocket's
## pad, the dish, the buggy, the probe, the crew); everything else in a block is built here, and
## the disc is then off limits to the random fillers. A board without blocks gets the old
## scatter (`_scatter`).
func _blocks(craters: Array, landmarks: Array) -> void:
	if _graph.zones.is_empty():
		_scatter(craters, landmarks)
		return
	for zone in _graph.zones:
		var c2: Array = zone.get("centre", [0.0, 0.0])
		var c := Vector3(float(c2[0]), _top, float(c2[1]))
		var r := float(zone.get("r", 6.0))
		var yaw := float(zone.get("yaw", 0.0))
		match str(zone.get("kind", "")):
			"hab": _block_hab(c, r, yaw)
			"pad": _block_pad(c, r, yaw)
			"depot": _block_depot(c, r, yaw)
			"farm": _block_farm(c, r, yaw)
			"tanks": _block_tanks(c, r, yaw)
			"park": _block_park(c, r, yaw)
			"crater": _block_crater(c, r, yaw)
			"power": _block_power(c, r, yaw)
			"plaza": _block_plaza(c, r, yaw)
			"rocket": _block_rocket(c, r, yaw)
			"solar": _block_solar(c, r, yaw)
			"lander": _block_lander(c, r, yaw)
			"ufo": _block_ufo(c, r, yaw)
			"balloon": _block_balloon(c, r, yaw)
			"radio": _block_radio(c, r, yaw)
			"station": _block_station(c, r, yaw)
			"satellite": _block_satellite(c, r, yaw)
			"arch": _block_arch(c, r, yaw)
			"telescope": _block_telescope(c, r, yaw)
			"control": _block_control(c, r, yaw)
			"rocket_pad": _block_rocket_pad(c, r, yaw)
			"rocket_cradle": _block_rocket_cradle(c, r, yaw)
		_occupied.append(Vector3(c.x, c.z, r + 0.8))
		_count("block")


## HAB 2: a habitat cluster like the west annex's, the comms tower and spare oxygen.
func _block_hab(c: Vector3, r: float, yaw: float) -> void:
	_habitat(_at(c, yaw, 0.6, 0.8), yaw + 0.3, "HAB 2")
	_comms_mast(_at(c, yaw, -5.8, -4.6))
	_oxygen(_node(_at(c, yaw, 5.6, 4.2), yaw + 0.5), 1)


## The rover's pad: landing lights round it (the rover is the view's), drums and a toolbox.
func _block_pad(c: Vector3, r: float, yaw: float) -> void:
	var lit := 0
	for i in 12:
		var a := i * TAU / 12.0
		var lp := Vector2(c.x, c.z) + Vector2(cos(a), sin(a)) * 3.8
		if _tile_clear(lp.x, lp.y, 1.6) and _inside(lp.x, lp.y, 0.97):
			_cyl(self, 0.1, 0.12, 0.26, Vector3(lp.x, _top + 0.13, lp.y), "counter_dark")
			_sphere(self, 0.1, Vector3(lp.x, _top + 0.3, lp.y), "glow_yellow" if i % 2 == 0 else "glow_red", Vector3.ONE, false, 8)
			lit += 1
	if lit > 0:
		_count("landing lights")
	var dn := _node(_at(c, yaw, -4.2, 1.6), yaw + 0.3)
	for k in 2:
		_cyl(dn, 0.32, 0.32, 0.9, Vector3(k * 0.75 - 0.37, 0.45, 0), "accent_lit" if k == 0 else "paper", Vector3.ZERO, 10)
		_torus(dn, 0.3, 0.34, Vector3(k * 0.75 - 0.37, 0.7, 0), "counter_dark", Vector3.ZERO, Vector3(1, 0.5, 1))
	_box(dn, Vector3(0.7, 0.35, 0.4), Vector3(0.2, 0.18, 0.8), "counter_dark")
	_box(dn, Vector3(0.74, 0.06, 0.44), Vector3(0.2, 0.37, 0.8), "metal")
	_count("drums")
	# The rover, parked (the view keeps its spot as a landmark).
	_rover(self, _at(c, yaw, 1.2, 0.4), yaw + PI * 0.5, [])


## The fuel bowser: a tank on a cart with a hose run out.
func _bowser(at: Vector3, yaw: float) -> void:
	var bw := _node(at, yaw)
	_box(bw, Vector3(1.8, 0.3, 1.0), Vector3(0, 0.45, 0), "counter_dark")
	_cyl(bw, 0.5, 0.5, 2.0, Vector3(0, 1.0, 0), "paper", Vector3(0, 0, PI * 0.5), 12)
	_torus(bw, 0.5, 0.58, Vector3(0.6, 1.0, 0), "accent_lit", Vector3(0, 0, PI * 0.5))
	_torus(bw, 0.5, 0.58, Vector3(-0.6, 1.0, 0), "accent_lit", Vector3(0, 0, PI * 0.5))
	for wx: float in [-0.7, 0.7]:
		for wz: float in [-0.55, 0.55]:
			_cyl(bw, 0.28, 0.28, 0.24, Vector3(wx, 0.28, wz), "ink", Vector3(PI * 0.5, 0, 0), 10)
	_box(bw, Vector3(0.3, 0.3, 0.3), Vector3(1.0, 1.65, 0), "metal")
	_strut(bw, Vector3(1.0, 1.5, 0), Vector3(3.4, 0.15, 0.5), 0.05, "ink", 6)
	_count("fuel bowser")


## The depot: a maintenance hangar, cargo stacks, cable spools and a crane with a crate on its hook.
func _block_depot(c: Vector3, r: float, yaw: float) -> void:
	# The hangar: a quonset hut (a cylinder on its side, half sunk), end plates, a door with a
	# lit strip, ribs along it.
	var hg := _node(_at(c, yaw, -1.5, -3.2), yaw)
	_cyl(hg, 2.6, 2.6, 7.0, Vector3.ZERO, "metal", Vector3(0, 0, PI * 0.5), 14)
	for ex: float in [-3.52, 3.52]:
		_cyl(hg, 2.66, 2.66, 0.14, Vector3(ex, 0.0, 0), "counter_dark", Vector3(0, 0, PI * 0.5), 14)
	_box(hg, Vector3(0.14, 2.2, 2.4), Vector3(3.6, 1.1, 0), "ink")
	_box(hg, Vector3(0.1, 0.16, 2.6), Vector3(3.62, 2.35, 0), "glow_yellow")
	_label(hg, "MAINT", Vector3(3.68, 2.95, 0), 40, Palette.hud_colour("paper"), PI * 0.5)
	for k in 4:
		_torus(hg, 2.6, 2.72, Vector3(-2.4 + k * 1.6, 0, 0), "counter_dark", Vector3(0, 0, PI * 0.5))
	_count("hangar")
	_cargo(_at(c, yaw, 3.8, 2.6), yaw + 0.3, 6)
	_cargo(_at(c, yaw, -4.6, 3.4), yaw - 0.4, 4)
	for k in 2:
		var sn := _node(_at(c, yaw, 0.6 + k * 1.6, 5.2), yaw + k * 0.7)
		_cyl(sn, 0.5, 0.5, 0.08, Vector3(-0.3, 0.5, 0), "paper", Vector3(0, 0, PI * 0.5), 12)
		_cyl(sn, 0.5, 0.5, 0.08, Vector3(0.3, 0.5, 0), "paper", Vector3(0, 0, PI * 0.5), 12)
		_cyl(sn, 0.3, 0.3, 0.56, Vector3(0, 0.5, 0), "counter_dark", Vector3(0, 0, PI * 0.5), 10)
	# The crane: a mast, a boom with a counterweight, a cable and a crate on the hook.
	var cr := _node(_at(c, yaw, 5.6, -2.6), yaw + 0.9)
	_cyl(cr, 0.7, 0.8, 0.5, Vector3(0, 0.25, 0), "counter_dark", Vector3.ZERO, 10)
	_cyl(cr, 0.16, 0.2, 6.5, Vector3(0, 3.5, 0), "metal")
	_box(cr, Vector3(5.0, 0.3, 0.3), Vector3(2.2, 6.6, 0), "accent_lit")
	_box(cr, Vector3(1.4, 0.3, 0.3), Vector3(-1.0, 6.6, 0), "accent_lit")
	_box(cr, Vector3(0.6, 0.8, 0.6), Vector3(-1.4, 6.3, 0), "counter_dark")
	_strut(cr, Vector3(0, 6.5, 0), Vector3(4.4, 6.8, 0), 0.03, "ink", 5)
	_strut(cr, Vector3(4.4, 6.45, 0), Vector3(4.4, 3.3, 0), 0.03, "ink", 5)
	_box(cr, Vector3(1.2, 0.8, 0.8), Vector3(4.4, 2.8, 0), "field_dark")
	_box(cr, Vector3(1.24, 0.14, 0.84), Vector3(4.4, 2.8, 0), "counter_dark")
	var b := _sphere(cr, 0.12, Vector3(0, 7.0, 0), "glow_red", Vector3.ONE, false, 8)
	_blinkers.append({"node": b, "period": 1.1, "phase": 0.6})
	_count("crane")


## The farm: greenhouses in two rows with pavers between, a water tank on legs, the pump.
func _block_farm(c: Vector3, r: float, yaw: float) -> void:
	for row in 2:
		for col in 3:
			_greenhouse(_at(c, yaw, col * 4.8 - 4.8, row * 3.8 - 1.0), yaw)
	for k in 7:
		_box(self, Vector3(1.0, 0.04, 0.9), _at(c, yaw, k * 1.6 - 4.8, 0.9) + Vector3(0, 0.02, 0), "metal", Vector3(0, yaw, 0))
	var wt := _node(_at(c, yaw, 0.0, -5.4), yaw)
	for lk in 4:
		var la := lk * TAU / 4.0 + PI * 0.25
		_cyl(wt, 0.08, 0.1, 2.2, Vector3(cos(la) * 1.0, 1.1, sin(la) * 1.0), "counter_dark")
	_cyl(wt, 1.3, 1.3, 2.2, Vector3(0, 3.2, 0), "paper", Vector3.ZERO, 14)
	_cyl(wt, 1.34, 1.34, 0.2, Vector3(0, 2.2, 0), "counter_dark", Vector3.ZERO, 14)
	_cyl(wt, 1.34, 1.34, 0.2, Vector3(0, 4.2, 0), "counter_dark", Vector3.ZERO, 14)
	_box(wt, Vector3(2.7, 0.3, 0.4), Vector3(0, 3.2, 1.35), "accent_lit")
	_cyl(wt, 0.05, 0.05, 4.0, Vector3(1.1, 2.0, 0.6), "ink")
	_cyl(wt, 0.05, 0.05, 4.0, Vector3(1.1, 2.0, 1.0), "ink")
	for k in 6:
		_box(wt, Vector3(0.04, 0.04, 0.4), Vector3(1.1, 0.5 + k * 0.6, 0.8), "ink")
	_box(wt, Vector3(0.8, 0.8, 0.8), Vector3(-1.8, 0.4, 0.4), "metal")
	_box(wt, Vector3(0.2, 0.2, 0.08), Vector3(-1.8, 0.6, 0.82), "glow_green")
	_count("water tank")


## The tank farm: two spheres on legs, a row of horizontal tanks, a pipe run, spare oxygen.
func _block_tanks(c: Vector3, r: float, yaw: float) -> void:
	for k in 2:
		var tn := _node(_at(c, yaw, -3.6, k * 5.4 - 2.7), yaw)
		for lk in 4:
			var la := lk * TAU / 4.0
			_cyl(tn, 0.12, 0.14, 2.0, Vector3(cos(la) * 1.5, 1.0, sin(la) * 1.5), "counter_dark", Vector3(sin(la) * 0.25, 0, -cos(la) * 0.25))
		_sphere(tn, 2.1, Vector3(0, 3.2, 0), "paper", Vector3.ONE, false, 16)
		_torus(tn, 2.05, 2.16, Vector3(0, 3.2, 0), "accent_lit" if k == 0 else "counter_dark", Vector3.ZERO, Vector3(1, 0.6, 1))
		_cyl(tn, 0.4, 0.4, 0.4, Vector3(0, 5.4, 0), "counter_dark", Vector3.ZERO, 10)
		_cyl(tn, 0.05, 0.05, 5.0, Vector3(1.9, 2.5, 0.5), "ink")
		_cyl(tn, 0.05, 0.05, 5.0, Vector3(1.9, 2.5, 0.9), "ink")
		_label(tn, "LOX" if k == 0 else "LH2", Vector3(0, 3.0, -2.14), 48, Palette.map_colour("board", "line"), PI, 0)
	_fuel_tanks(_at(c, yaw, 3.4, 0.0), yaw + PI * 0.5)
	var pr := _node(_at(c, yaw, 0.0, 0.0), yaw)
	_cyl(pr, 0.12, 0.12, 6.0, Vector3(-0.2, 0.7, 0), "counter_dark", Vector3(0, 0, PI * 0.5), 8)
	for k in 3:
		_box(pr, Vector3(0.2, 0.6, 0.3), Vector3(k * 2.4 - 2.6, 0.3, 0), "metal")
	_oxygen(_node(_at(c, yaw, -1.2, 5.6), yaw + 0.8), 0)
	_count("tank farm")


## The crater park: the drill rig over the crater in the middle of the block (the view digs it,
## at 0.55 of the block's radius), boulders on its rim, rock clusters and dust round it and the
## half-buried probe (the view's) at the block's edge.
func _block_park(c: Vector3, r: float, yaw: float) -> void:
	var cr := r * 0.55
	_drill_rig(c, cr, yaw)
	_occupied.append(Vector3(c.x, c.z, cr + 1.2))
	for k in 4:
		var a := yaw + k * 1.3 + 0.4
		var bp := c + Vector3(cos(a) * (cr + 1.5), 0, sin(a) * (cr + 1.5))
		if _tile_clear(bp.x, bp.z, 2.0):
			var rk := _sphere(self, _rng.randf_range(0.5, 0.95), bp + Vector3(0, 0.3, 0), "rock" if k % 2 == 0 else "moon_dark",
				Vector3(_rng.randf_range(0.9, 1.3), _rng.randf_range(0.6, 0.9), _rng.randf_range(0.9, 1.3)), false, 7)
			rk.rotation.y = _rng.randf_range(0.0, TAU)
	for k in 4:
		var sp := _spot_near(c.x, c.z, cr + 2.4, r - 1.0, 2.3, 1.4, 200)
		if sp == Vector2.INF:
			break
		_rock_cluster(Vector3(sp.x, _top, sp.y))
	for k in 2:
		var sp := _spot_near(c.x, c.z, 1.0, r - 1.0, 2.0, 0.4, 100)
		if sp != Vector2.INF:
			var d := _sphere(self, _rng.randf_range(1.6, 2.6), Vector3(sp.x, _top - 0.02, sp.y), "moon_light" if k == 0 else "moon_dark",
				Vector3(1.0, 0.012, _rng.randf_range(0.6, 1.0)), false, 9)
			d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_count("park lawn")


## The big crater (the view digs it): the drill rig over it, boulders on its far rim, two
## benches on the near one looking in.
func _block_crater(c: Vector3, r: float, yaw: float) -> void:
	_drill_rig(c, r, yaw)
	for k in 4:
		var a := PI * 0.5 + k * 0.55 - 0.8
		var bp := c + Vector3(cos(a) * (r + 1.6), 0, sin(a) * (r + 1.6))
		if _tile_clear(bp.x, bp.z, 2.0):
			var rk := _sphere(self, _rng.randf_range(0.6, 1.1), bp + Vector3(0, 0.35, 0), "rock" if k % 2 == 0 else "moon_dark",
				Vector3(_rng.randf_range(0.9, 1.3), _rng.randf_range(0.6, 0.9), _rng.randf_range(0.9, 1.3)), false, 7)
			rk.rotation.y = _rng.randf_range(0.0, TAU)
	for k in 2:
		var bp := c + Vector3(k * 8.0 - 4.0, 0, -(r + 2.4))
		if _tile_clear(bp.x, bp.z, 1.9):
			_bench(bp, 0.0)
	_count("crater park")


## The power plant: a solar field, the reactor with its cooling towers, a substation; the dish
## (the view's) at the block's corner.
func _block_power(c: Vector3, r: float, yaw: float) -> void:
	_solar_array(_at(c, yaw, -3.4, -3.0), yaw, 3 if r >= 7.5 else 2)
	var rn := _node(_at(c, yaw, 4.2, -2.4), yaw)
	_cyl(rn, 2.2, 2.4, 3.2, Vector3(0, 1.6, 0), "metal", Vector3.ZERO, 16)
	_cyl(rn, 2.3, 2.3, 0.3, Vector3(0, 3.3, 0), "counter_dark", Vector3.ZERO, 16)
	_sphere(rn, 1.9, Vector3(0, 3.4, 0), "paper", Vector3(1, 0.6, 1), true, 16)
	_torus(rn, 2.25, 2.45, Vector3(0, 1.0, 0), "glow_cyan", Vector3.ZERO, Vector3(1, 0.5, 1))
	_box(rn, Vector3(0.5, 1.6, 1.2), Vector3(-2.3, 0.8, 0.4), "counter_dark")
	_box(rn, Vector3(0.12, 0.3, 0.3), Vector3(-2.58, 1.3, 0.4), "glow_yellow")
	for k in 2:
		var ct := Vector3(1.6, 0, 3.6 + k * 2.6)
		_cyl(rn, 0.9, 1.3, 4.6, ct + Vector3(0, 2.3, 0), "paper", Vector3.ZERO, 14)
		_cyl(rn, 0.95, 0.95, 0.2, ct + Vector3(0, 4.7, 0), "counter_dark", Vector3.ZERO, 14)
		_torus(rn, 1.28, 1.4, ct + Vector3(0, 0.5, 0), "counter_dark", Vector3.ZERO, Vector3(1, 0.5, 1))
	_cyl(rn, 0.14, 0.14, 3.6, Vector3(1.6, 0.9, 2.0), "counter_dark", Vector3(PI * 0.5, 0, 0), 8)
	var sb := _node(_at(c, yaw, 4.6, 4.8), yaw + 0.2)
	_box(sb, Vector3(1.6, 1.2, 1.0), Vector3(0, 0.6, 0), "metal")
	for k in 3:
		_cyl(sb, 0.08, 0.1, 0.6, Vector3(k * 0.5 - 0.5, 1.5, 0), "paper", Vector3.ZERO, 8)
	_box(sb, Vector3(0.3, 0.2, 0.06), Vector3(0.5, 0.7, 0.53), "glow_red")
	for k in 8:
		var fa := k * TAU / 8.0
		_cyl(sb, 0.04, 0.04, 1.0, Vector3(cos(fa) * 1.8, 0.5, sin(fa) * 1.8), "ink", Vector3.ZERO, 5)
	_count("reactor")


## The plaza off the start: benches either side of the crew and the flag (the view's), facing
## the walkway.
func _block_plaza(c: Vector3, r: float, yaw: float) -> void:
	for k in 2:
		_bench(_at(c, yaw, k * 5.6 - 2.8, 0.0), yaw + PI)
	_count("plaza")


func _bench(at: Vector3, yaw: float) -> void:
	var bn := _node(at, yaw)
	_box(bn, Vector3(1.6, 0.08, 0.5), Vector3(0, 0.5, 0), "paper")
	_box(bn, Vector3(1.6, 0.4, 0.08), Vector3(0, 0.78, -0.24), "paper")
	for bx: float in [-0.65, 0.65]:
		_box(bn, Vector3(0.1, 0.5, 0.5), Vector3(bx, 0.25, 0), "counter_dark")
	_occupied.append(Vector3(at.x, at.z, 1.0))


## Comms mast: a lattice tower with a small dish and a blinking light.
func _comms_mast(at: Vector3) -> void:
	var mn := _node(at)
	for i in 3:
		var a := i * TAU / 3.0
		_cyl(mn, 0.05, 0.07, 7.0, Vector3(cos(a) * 0.45, 3.5, sin(a) * 0.45), "ink", Vector3(sin(a) * 0.05, 0, -cos(a) * 0.05))
	for lvl in 5:
		_box(mn, Vector3(1.0, 0.06, 1.0), Vector3(0, 1.2 + lvl * 1.35, 0), "counter_dark")
	_cyl(mn, 0.06, 0.06, 1.6, Vector3(0, 7.7, 0), "ink")
	_cyl(mn, 0.75, 0.15, 0.3, Vector3(0.7, 4.5, 0), "paper", Vector3(0, 0, -1.1), 12)
	var b := _sphere(mn, 0.18, Vector3(0, 8.55, 0), "glow_red", Vector3.ONE, false, 8)
	_blinkers.append({"node": b, "period": 0.9, "phase": 0.3})
	_occupied.append(Vector3(at.x, at.z, 1.6))
	_count("comms mast")


## A drill rig straddling a crater of radius `r`.
func _drill_rig(at: Vector3, r: float, yaw: float) -> void:
	var rig := _node(at, yaw)
	var s := r * 0.9
	for i in 4:
		var a := i * TAU / 4.0 + PI * 0.25
		_cyl(rig, 0.08, 0.1, 5.0, Vector3(cos(a) * s * 0.55, 2.4, sin(a) * s * 0.55), "counter_dark",
			Vector3(sin(a) * 0.2, 0, -cos(a) * 0.2))
	_box(rig, Vector3(s * 0.9, 0.16, s * 0.9), Vector3(0, 4.7, 0), "counter_dark")
	_box(rig, Vector3(s * 0.7, 0.12, s * 0.7), Vector3(0, 2.6, 0), "counter_dark")
	_cyl(rig, 0.16, 0.16, 5.2, Vector3(0, 2.4, 0), "metal")
	_box(rig, Vector3(1.2, 0.8, 0.8), Vector3(0, 5.2, 0), "accent_lit")
	var b := _sphere(rig, 0.14, Vector3(0, 5.75, 0), "glow_yellow", Vector3.ONE, false, 8)
	_blinkers.append({"node": b, "period": 1.7, "phase": 0.5})
	_count("drill rig")


## A few boulders of different sizes and a scatter of pebbles.
func _rock_cluster(at: Vector3) -> void:
	var c := _node(at, _rng.randf_range(0.0, TAU))
	var n := 2 + _rng.randi() % 3
	for j in n:
		var r := _rng.randf_range(0.28, 0.75)
		var off := Vector3(_rng.randf_range(-1.0, 1.0), 0, _rng.randf_range(-1.0, 1.0))
		var rock := _sphere(c, r, off + Vector3(0, r * 0.4, 0), "rock" if j % 2 == 0 else "moon_dark",
			Vector3(_rng.randf_range(0.8, 1.3), _rng.randf_range(0.5, 0.85), _rng.randf_range(0.8, 1.3)), false, 7)
		rock.rotation.y = _rng.randf_range(0.0, TAU)
	for j in 4 + _rng.randi() % 4:
		var r := _rng.randf_range(0.08, 0.16)
		var off := Vector3(_rng.randf_range(-1.6, 1.6), r * 0.5, _rng.randf_range(-1.6, 1.6))
		_sphere(c, r, off, "crater", Vector3(1.2, 0.7, 1.0), false, 6)
	_count("rock cluster")


## Antenna masts: short whips with a light, two of them, wherever they fit.
func _antennas() -> void:
	for k in 2:
		var sp := _spot(2.2, 0.8, 0.15, 0.95, 200)
		if sp == Vector2.INF:
			break
		var an := _node(Vector3(sp.x, _top, sp.y))
		_cyl(an, 0.3, 0.3, 0.3, Vector3(0, 0.15, 0), "metal")
		_cyl(an, 0.04, 0.06, 3.4, Vector3(0, 2.0, 0), "ink")
		var b := _sphere(an, 0.12, Vector3(0, 3.8, 0), "glow_green" if k == 0 else "glow_cyan", Vector3.ONE, false, 8)
		_blinkers.append({"node": b, "period": 2.1 + k, "phase": 0.7 * k})
		_count("antenna")


## The scatter a board without blocks gets: solar arrays, cargo stacks, a comms mast, a drill
## rig over its biggest crater, oxygen, landing lights round the pad.
func _scatter(craters: Array, landmarks: Array) -> void:
	for k in roundi(2 * sqrt(_density)):
		var farm := _spot(3.4, 2.4, 0.15, 0.94, 500)
		if farm != Vector2.INF:
			_solar_array(Vector3(farm.x, _top, farm.y), _rng.randf_range(0.0, TAU), 1)
	for k in roundi(3 * sqrt(_density)):
		var sp := _spot(2.7, 1.6, 0.15, 0.92, 300)
		if sp == Vector2.INF:
			break
		_cargo(Vector3(sp.x, _top, sp.y), _rng.randf_range(0.0, TAU), 3 + _rng.randi() % 3)
	var mast := _spot(2.8, 1.6, 0.2, 0.9, 300)
	if mast != Vector2.INF:
		_comms_mast(Vector3(mast.x, _top, mast.y))
	var best: Vector3 = Vector3.INF
	for cr in craters:
		if cr.z >= 1.8 and _tile_clear(cr.x, cr.y, cr.z + 2.2) and (best == Vector3.INF or cr.z > best.z):
			best = cr
	if best != Vector3.INF:
		_drill_rig(Vector3(best.x, _top, best.y), best.z, _rng.randf_range(0.0, TAU))
	for k in 2:
		var sp := _spot(2.0, 0.9, 0.15, 0.95, 200)
		if sp == Vector2.INF:
			break
		_oxygen(_node(Vector3(sp.x, _top, sp.y), _rng.randf_range(0.0, TAU)), k)
	if landmarks.size() > 0:
		var pad := Vector2(landmarks[0].x, landmarks[0].y)
		var lit := 0
		for i in 12:
			var a := i * TAU / 12.0
			var lp := pad + Vector2(cos(a), sin(a)) * 3.8
			if _tile_clear(lp.x, lp.y, 1.6) and _inside(lp.x, lp.y, 0.97):
				_cyl(self, 0.1, 0.12, 0.26, Vector3(lp.x, _top + 0.13, lp.y), "counter_dark")
				_sphere(self, 0.1, Vector3(lp.x, _top + 0.3, lp.y), "glow_yellow" if i % 2 == 0 else "glow_red", Vector3.ONE, false, 8)
				lit += 1
		if lit > 0:
			_count("landing lights")


# --- signs and pennants ------------------------------------------------------------------------------

func _signs_and_pennants(landmarks: Array) -> void:
	var g := _graph
	var start: BoardGraph.Space = g.get_space(g.start_id)
	var sp0: Vector3 = start.position
	var nxt: Vector3 = g.get_space(start.next[0]).position if not start.next.is_empty() else sp0 + Vector3(0, 0, 1)
	var dir := Vector2(nxt.x - sp0.x, nxt.z - sp0.z).normalized()
	var side := Vector2(-dir.y, dir.x)
	# The start line (the welcome sign that stood here is gone, Sean: "dont like it"): two posts
	# beside the start tile and a sagging string of pennants over it,
	# high enough to clear a hopping pawn.
	var pa := Vector2(sp0.x, sp0.z) + side * 2.3
	var pb := Vector2(sp0.x, sp0.z) - side * 2.3
	var others_clear := true
	for p in _tile_positions:
		if p.distance_to(sp0) < 0.01:
			continue
		if Vector2(p.x - pa.x, p.z - pa.y).length() < 1.7 or Vector2(p.x - pb.x, p.z - pb.y).length() < 1.7:
			others_clear = false
	if others_clear and _inside(pa.x, pa.y, 0.99) and _inside(pb.x, pb.y, 0.99):
		_occupied.append(Vector3(pa.x, pa.y, 0.5))
		_occupied.append(Vector3(pb.x, pb.y, 0.5))
		var top_y := sp0.y + 3.9
		for pt in [pa, pb]:
			_cyl(self, 0.07, 0.09, top_y - _top, Vector3(pt.x, (_top + top_y) * 0.5, pt.y), "ink")
			_sphere(self, 0.14, Vector3(pt.x, top_y + 0.05, pt.y), "accent_lit", Vector3.ONE, false, 8)
		var n := 9
		for i in n:
			var t := (i + 0.5) / n
			var x := lerpf(pa.x, pb.x, t)
			var z := lerpf(pa.y, pb.y, t)
			var y := top_y - sin(t * PI) * 0.35
			var flag := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(0.34, 0.46, 0.03)
			flag.mesh = pm
			flag.position = Vector3(x, y - 0.23, z)
			flag.rotation = Vector3(PI, atan2(pb.x - pa.x, pb.y - pa.y) + PI * 0.5, 0)
			flag.material_override = _mat("player%d" % (i % 6))
			add_child(flag)
		for i in 6:
			var t0 := float(i) / 6.0
			var t1 := float(i + 1) / 6.0
			var a := Vector3(lerpf(pa.x, pb.x, t0), top_y - sin(t0 * PI) * 0.35, lerpf(pa.y, pb.y, t0))
			var b := Vector3(lerpf(pa.x, pb.x, t1), top_y - sin(t1 * PI) * 0.35, lerpf(pa.y, pb.y, t1))
			_strut(self, a, b, 0.02, "ink", 5)
		_count("start banner")
	# PAD 1 by the landing pad, and an arrow post somewhere on the loop.
	if landmarks.size() > 0:
		var pad := Vector2(landmarks[0].x, landmarks[0].y)
		var at := _spot_near(pad.x, pad.y, 4.6, 6.5, 1.9, 0.6, 300)
		if at != Vector2.INF:
			var yaw := atan2(-(pad.x - at.x), -(pad.y - at.y)) + PI
			var pn := _node(Vector3(at.x, _top, at.y), yaw)
			_cyl(pn, 0.06, 0.08, 2.2, Vector3(0, 1.1, 0), "ink")
			_box(pn, Vector3(1.3, 0.5, 0.08), Vector3(0, 2.0, 0), "paper")
			_label(pn, "PAD 1", Vector3(0, 2.06, 0.06), 44, Palette.map_colour("board", "line"), 0.0, 0)
			_box(pn, Vector3(1.3, 0.08, 0.08), Vector3(0, 1.72, 0), "accent_lit")
			_count("pad sign")
	var ids := _graph.ids()
	var mid: Vector3 = _graph.get_space(ids[ids.size() / 2]).position
	var ap := _spot_near(mid.x, mid.z, 2.4, 4.0, 2.0, 0.6, 300)
	if ap != Vector2.INF:
		var pn := _node(Vector3(ap.x, _top, ap.y), _rng.randf_range(0.0, TAU))
		_cyl(pn, 0.06, 0.08, 2.4, Vector3(0, 1.2, 0), "ink")
		var tones := ["accent_lit", "paper", "glow_cyan"]
		for i in 3:
			var arrow := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(0.9, 0.3, 0.06)
			arrow.mesh = pm
			arrow.position = Vector3(0.3, 2.3 - i * 0.36, 0)
			arrow.rotation = Vector3(0, 0, -PI * 0.5 + (0.6 if i == 1 else 0.0))
			arrow.material_override = _mat(tones[i])
			pn.add_child(arrow)
		_count("arrow post")


# --- alive ----------------------------------------------------------------------------------------------

func _life() -> void:
	# Patrol drone: follows the main loop 4 m above the tiles.
	var g := _graph
	var sid: String = g.start_id
	var seen := {}
	for step in 240:
		if seen.has(sid):
			break
		seen[sid] = true
		var s := g.get_space(sid)
		_drone_path.append(s.position + Vector3(0, 4.2, 0))
		if s.next.is_empty():
			break
		sid = s.next[0]
	if _drone_path.size() >= 3:
		_drone = Node3D.new()
		add_child(_drone)
		_box(_drone, Vector3(0.5, 0.22, 0.5), Vector3.ZERO, "metal")
		_box(_drone, Vector3(0.3, 0.12, 0.3), Vector3(0, -0.16, 0), "counter_dark")
		_sphere(_drone, 0.09, Vector3(0, -0.24, 0), "glow_red", Vector3.ONE, false, 8)
		for i in 4:
			var a := i * TAU / 4.0 + PI * 0.25
			var arm := Vector3(cos(a) * 0.5, 0.05, sin(a) * 0.5)
			_cyl(_drone, 0.03, 0.03, 0.6, arm * 0.5, "ink", Vector3(0, -a, PI * 0.5), 6)
			var rotor := _cyl(_drone, 0.28, 0.28, 0.02, arm + Vector3(0, 0.1, 0), "accent_lit", Vector3.ZERO, 8)
			_drone_rotors.append(rotor)
		_drone.position = _drone_path[0]
		_count("patrol drone")
	# A buggy driving the road planned earlier: back and forth along a rim arc, or round the annex.
	if _buggy_road.is_empty() and _annex != Vector3.INF:
		for i in 40:
			var a := i * TAU / 40.0
			_buggy_road.append(_annex + Vector3(cos(a) * (_annex_r - 1.1), 0, sin(a) * (_annex_r - 1.1)))
		_road_loop = true
	if not _buggy_road.is_empty():
		_buggy_len = 0.0
		var last := _buggy_road.size() if _road_loop else _buggy_road.size() - 1
		for k in range(1, last + 1):
			_buggy_len += (_buggy_road[k % _buggy_road.size()] - _buggy_road[k - 1]).length()
		_buggy = _rover(self, _buggy_road[0], 0.0, _buggy_wheels)
		# Tyre tracks along the road.
		var segs := _buggy_road.size() if _road_loop else _buggy_road.size() - 1
		for k in range(1, segs + 1):
			var a: Vector3 = _buggy_road[k - 1]
			var bb: Vector3 = _buggy_road[k % _buggy_road.size()]
			var d := (bb - a).normalized()
			var side := Vector3(-d.z, 0, d.x)
			for s: float in [-0.8, 0.8]:
				var tr := _box(self, Vector3(0.14, 0.02, (bb - a).length()), (a + bb) * 0.5 + side * s + Vector3(0, 0.01, 0), "moon_dark")
				tr.look_at(bb + side * s, Vector3.UP)
				tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_count("driving buggy")
	# Shooting star: built once, shown on its runs.
	_star = Node3D.new()
	_star.visible = false
	add_child(_star)
	_sphere(_star, 0.5, Vector3.ZERO, "glow_yellow", Vector3.ONE, false, 8)
	_cyl(_star, 0.05, 0.45, 6.0, Vector3(0, 0, 3.0), "paper", Vector3(PI * 0.5, 0, 0), 8)
	_star_next = _rng.randf_range(6.0, 12.0)
	# A space station on the horizon, turning: a ring with spokes, a hub, solar wings, lights.
	_station = Node3D.new()
	_station.position = _centre + Vector3(70.0, 30.0, 60.0)
	add_child(_station)
	var ring := _torus(_station, 5.2, 6.6, Vector3.ZERO, "moon_dark", Vector3(PI * 0.5 + 0.35, 0, 0))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 4:
		var a := i * TAU / 4.0
		var sp := _box(_station, Vector3(0.5, 0.5, 5.6), Vector3(cos(a) * 3.0, sin(a) * 3.0 * sin(0.35), sin(a) * 3.0 * cos(0.35)), "moon_dark", Vector3(0.35 * 0, a, 0))
		sp.look_at(_station.to_global(Vector3(cos(a) * 6.0, sin(a) * 6.0 * sin(0.35), sin(a) * 6.0 * cos(0.35))), Vector3.UP)
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hub := _cyl(_station, 1.6, 1.6, 2.4, Vector3.ZERO, "metal", Vector3(PI * 0.5 + 0.35, 0, 0), 12)
	hub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for s: float in [-1.0, 1.0]:
		var wing := _box(_station, Vector3(9.0, 0.12, 3.0), Vector3(s * 7.0, 0, 0), "field_dark")
		wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sl := _sphere(_station, 0.4, Vector3(0, 1.8, 0), "glow_red", Vector3.ONE, false, 8)
	_blinkers.append({"node": sl, "period": 2.0, "phase": 0.0})
	_count("space station")
	# A freighter crossing the far sky on a slow lap: a long hull, a cabin, cargo pods, thrusters.
	_freighter = Node3D.new()
	add_child(_freighter)
	var hull := _box(_freighter, Vector3(14.0, 1.6, 2.0), Vector3.ZERO, "metal")
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(_freighter, Vector3(2.4, 2.2, 2.4), Vector3(6.2, 1.0, 0), "counter_dark").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(_freighter, Vector3(1.2, 0.5, 1.6), Vector3(6.9, 1.9, 0), "glass").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in 4:
		_box(_freighter, Vector3(2.2, 1.6, 2.6), Vector3(-5.0 + k * 2.7, 1.4, 0), "accent_lit" if k % 2 == 0 else "paper").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for s: float in [-1.0, 1.0]:
		_cyl(_freighter, 0.7, 0.9, 1.6, Vector3(-7.4, 0, s * 0.8), "counter_dark", Vector3(0, 0, PI * 0.5), 10).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sphere(_freighter, 0.6, Vector3(-8.3, 0, s * 0.8), "glow_cyan", Vector3(0.4, 1, 1), false, 8).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fl := _sphere(_freighter, 0.3, Vector3(7.0, -0.9, 0), "glow_red", Vector3.ONE, false, 8)
	_blinkers.append({"node": fl, "period": 1.5, "phase": 0.5})
	_count("freighter")


func _process(delta: float) -> void:
	_anim_t += delta
	for bl in _blinkers:
		var n: Node3D = bl["node"]
		var period: float = bl["period"]
		n.visible = fmod(_anim_t + float(bl["phase"]) * period, period) < period * 0.18
	for bb in _bobbers:
		var bn: Node3D = bb["node"]
		bn.position.y = float(bb["base_y"]) + sin(_anim_t * TAU / float(bb["period"])) * 0.12
	for sp in _spinners:
		(sp["node"] as Node3D).rotation.y += delta * float(sp["rate"])
	if _drone != null and _drone_path.size() >= 2:
		_drone_t += delta * 3.4
		var n := _drone_path.size()
		var i := int(floor(_drone_t / 4.0)) % n
		var f := fmod(_drone_t / 4.0, 1.0)
		var a: Vector3 = _drone_path[i]
		var b: Vector3 = _drone_path[(i + 1) % n]
		var c: Vector3 = _drone_path[(i + 2) % n]
		var pos := a.lerp(b, f) + Vector3(0, sin(_anim_t * 2.3) * 0.25, 0)
		var ahead := b.lerp(c, f)
		_drone.position = pos
		if (ahead - pos).length() > 0.05:
			_drone.look_at(Vector3(ahead.x, pos.y, ahead.z), Vector3.UP)
		_drone.rotation.x = -0.18
		for r in _drone_rotors:
			(r as Node3D).rotation.y += delta * 30.0
	if _buggy != null and _buggy_road.size() >= 2:
		_buggy_t += delta * 2.0
		# Round a loop, or back and forth along an arc (a triangle wave over its length).
		var forward := true
		var d := fmod(_buggy_t, _buggy_len)
		if not _road_loop:
			var cycle := fmod(_buggy_t, _buggy_len * 2.0)
			forward = cycle < _buggy_len
			d = cycle if forward else _buggy_len * 2.0 - cycle
		var count := _buggy_road.size() if _road_loop else _buggy_road.size() - 1
		var i := 1
		while i <= count:
			var a: Vector3 = _buggy_road[i - 1]
			var b: Vector3 = _buggy_road[i % _buggy_road.size()]
			var seg := (b - a).length()
			if d <= seg or i == count:
				var pos := a.lerp(b, clampf(d / maxf(seg, 0.001), 0.0, 1.0))
				_buggy.position = pos
				var face := b if forward else a
				if (face - pos).length() > 0.01:
					_buggy.look_at(face, Vector3.UP)
					_buggy.rotation.y += PI * 0.5
				break
			d -= seg
			i += 1
		for w in _buggy_wheels:
			(w as Node3D).rotation.y += delta * (4.8 if forward else -4.8)
	if _station != null:
		_station.rotation.y += delta * 0.05
	if _machines.has(_active_machine):
		var globe: Node3D = _machines[_active_machine]["globe"]
		globe.rotation.y += delta * 0.6   # the capsules turn in the lit machine's globe
	if _freighter != null:
		# A 110 s lap far out, low over the horizon, nose forward.
		var lap := _anim_t * TAU / 110.0 + 2.0
		var r := 95.0
		var pos := _centre + Vector3(cos(lap) * r, 22.0 + sin(_anim_t * 0.2) * 2.0, sin(lap) * r * 0.8)
		_freighter.position = pos
		var ahead := _centre + Vector3(cos(lap + 0.02) * r, 22.0, sin(lap + 0.02) * r * 0.8)
		_freighter.look_at(Vector3(ahead.x, pos.y, ahead.z), Vector3.UP)
		_freighter.rotate_object_local(Vector3.UP, -PI * 0.5)
	# The shooting star: a streak across the far sky every so often.
	_star_next -= delta
	if _star != null and _star_next <= 0.0 and _star_t >= 99.0:
		var a := _rng.randf_range(0.0, TAU)
		_star_from = _centre + Vector3(cos(a) * 110.0, _rng.randf_range(38.0, 60.0), sin(a) * 110.0)
		_star_to = _centre + Vector3(cos(a + 1.1) * 110.0, _rng.randf_range(18.0, 34.0), sin(a + 1.1) * 110.0)
		_star_t = 0.0
		_star.visible = true
		_star.position = _star_from
		_star.look_at(_star_from + (_star_from - _star_to), Vector3.UP)
	if _star_t < 99.0:
		_star_t += delta / 1.9
		if _star_t >= 1.0:
			_star_t = 99.0
			_star.visible = false
			_star_next = _rng.randf_range(14.0, 26.0)
		else:
			_star.position = _star_from.lerp(_star_to, _star_t)


## The rocket's pad (the rocket is the view's, on its own node so it can fly): landing lights
## round it, the fuel bowser, and a launch gantry with its swing arm out to the rocket.
func _block_rocket(c: Vector3, r: float, yaw: float) -> void:
	var lit := 0
	for i in 12:
		var a := i * TAU / 12.0
		var lp := Vector2(c.x, c.z) + Vector2(cos(a), sin(a)) * 3.9
		if _tile_clear(lp.x, lp.y, 1.6) and _inside(lp.x, lp.y, 0.97):
			_cyl(self, 0.1, 0.12, 0.26, Vector3(lp.x, _top + 0.13, lp.y), "counter_dark")
			_sphere(self, 0.1, Vector3(lp.x, _top + 0.3, lp.y), "glow_yellow" if i % 2 == 0 else "glow_red", Vector3.ONE, false, 8)
			lit += 1
	if lit > 0:
		_count("landing lights")
	_bowser(_at(c, yaw, -4.4, 1.4), yaw + 0.4)
	var gt := _node(_at(c, yaw, 3.0, -2.4), yaw)
	for i in 4:
		var a := i * TAU / 4.0 + PI * 0.25
		_cyl(gt, 0.05, 0.07, 7.0, Vector3(cos(a) * 0.5, 3.5, sin(a) * 0.5), "counter_dark")
	for lvl in 5:
		_box(gt, Vector3(1.1, 0.06, 1.1), Vector3(0, 1.2 + lvl * 1.4, 0), "metal")
	_box(gt, Vector3(3.2, 0.12, 0.5), Vector3(-1.25, 5.4, 1.0), "accent_lit", Vector3(0, atan2(-2.4, -3.0), 0))
	_box(gt, Vector3(0.6, 0.9, 0.6), Vector3(0, 7.3, 0), "counter_dark")
	var b := _sphere(gt, 0.14, Vector3(0, 7.95, 0), "glow_red", Vector3.ONE, false, 8)
	_blinkers.append({"node": b, "period": 1.3, "phase": 0.2})
	_count("gantry")


## A single row of solar panels, for the slivers between streets.
func _block_solar(c: Vector3, r: float, yaw: float) -> void:
	_solar_array(c, yaw, 1)


## A lunar lander parked in the margin: a gold descent stage on four splayed legs with round
## pads, a silver cabin with a hatch and windows, a little dish, a planted flag.
func _block_lander(c: Vector3, r: float, yaw: float) -> void:
	var ln := _node(c, yaw)
	_cyl(ln, 1.3, 1.3, 0.9, Vector3(0, 1.1, 0), "accent_lit", Vector3.ZERO, 8)
	_cyl(ln, 0.55, 0.8, 0.5, Vector3(0, 0.45, 0), "counter_dark", Vector3.ZERO, 10)   # the engine bell
	for k in 4:
		var a := k * TAU / 4.0 + PI * 0.25
		var foot := Vector3(cos(a) * 2.0, 0.0, sin(a) * 2.0)
		_strut(ln, Vector3(cos(a) * 1.1, 0.9, sin(a) * 1.1), foot + Vector3(0, 0.1, 0), 0.06, "metal", 6)
		_strut(ln, Vector3(cos(a) * 1.1, 1.45, sin(a) * 1.1), foot + Vector3(0, 0.1, 0), 0.04, "counter_dark", 5)
		_cyl(ln, 0.4, 0.4, 0.1, foot + Vector3(0, 0.05, 0), "metal", Vector3.ZERO, 10)
	_box(ln, Vector3(1.5, 1.1, 1.4), Vector3(0, 2.1, 0), "metal")
	_box(ln, Vector3(0.5, 0.6, 0.06), Vector3(0, 2.0, 0.72), "ink")
	for wx: float in [-0.45, 0.45]:
		_box(ln, Vector3(0.3, 0.3, 0.06), Vector3(wx, 2.45, 0.72), "glass")
	_cyl(ln, 0.03, 0.03, 1.4, Vector3(0.5, 3.35, -0.3), "ink")
	_cyl(ln, 0.35, 0.08, 0.2, Vector3(0.5, 4.05, -0.3), "paper", Vector3(-0.5, 0, 0), 10)
	_cyl(ln, 0.03, 0.03, 1.6, Vector3(2.7, 0.8, 0.6), "ink")
	_box(ln, Vector3(0.6, 0.4, 0.03), Vector3(3.0, 1.4, 0.6), "accent_lit")
	_count("lander")


## A saucer parked in the margin on three legs, its ramp down and its pilot beside it: a green
## blob with big eyes and two antennae, bobbing.
func _block_ufo(c: Vector3, r: float, yaw: float) -> void:
	var un := _node(c, yaw)
	_cyl(un, 1.5, 2.3, 0.5, Vector3(0, 1.45, 0), "metal", Vector3.ZERO, 18)
	_cyl(un, 2.3, 1.0, 0.5, Vector3(0, 0.95, 0), "ink", Vector3.ZERO, 18)
	_sphere(un, 1.0, Vector3(0, 1.7, 0), "glass", Vector3(1, 0.75, 1), true, 16)
	for k in 8:
		var a := k * TAU / 8.0
		var lt := _sphere(un, 0.14, Vector3(cos(a) * 2.05, 1.22, sin(a) * 2.05), "glow_yellow" if k % 2 == 0 else "glow_cyan", Vector3.ONE, false, 8)
		if k % 4 == 1:
			_blinkers.append({"node": lt, "period": 1.7, "phase": 0.25 * k})
	for k in 3:
		var a := k * TAU / 3.0 + PI * 0.5
		_strut(un, Vector3(cos(a) * 1.6, 1.0, sin(a) * 1.6), Vector3(cos(a) * 2.2, 0.1, sin(a) * 2.2), 0.06, "counter_dark", 6)
		_cyl(un, 0.3, 0.3, 0.1, Vector3(cos(a) * 2.2, 0.05, sin(a) * 2.2), "metal", Vector3.ZERO, 8)
	_box(un, Vector3(0.9, 0.06, 2.6), Vector3(0, 0.5, 2.3), "metal", Vector3(0.38, 0, 0))
	_alien(un, Vector3(1.5, 0, 2.7))
	_count("saucer")


func _alien(parent: Node3D, at: Vector3) -> void:
	var al := Node3D.new()
	al.position = at
	al.rotation.y = 0.5
	parent.add_child(al)
	_sphere(al, 0.34, Vector3(0, 0.52, 0), "glow_green", Vector3(1.0, 1.15, 1.0), false, 12)
	for ex: float in [-0.14, 0.14]:
		_sphere(al, 0.1, Vector3(ex, 0.66, 0.26), "paper", Vector3.ONE, false, 8)
		_sphere(al, 0.045, Vector3(ex, 0.67, 0.34), "ink", Vector3.ONE, false, 6)
		_strut(al, Vector3(ex * 1.2, 0.8, 0), Vector3(ex * 2.4, 1.2, 0.05), 0.02, "ink", 4)
		_sphere(al, 0.05, Vector3(ex * 2.4, 1.22, 0.05), "glow_green", Vector3.ONE, false, 6)
		_cyl(al, 0.11, 0.11, 0.06, Vector3(ex * 1.1, 0.03, 0.08), "ink", Vector3.ZERO, 8)
	_bobbers.append({"node": al, "base_y": at.y, "period": 2.6})
	_count("pilot")


## A tethered science balloon in the margin: an anchor block and winch, the tether up to a fat
## balloon with a paper band and an instrument box under it, bobbing on its line.
func _block_balloon(c: Vector3, r: float, yaw: float) -> void:
	var bn := _node(c, yaw)
	_box(bn, Vector3(1.0, 0.3, 1.0), Vector3(0, 0.15, 0), "counter_dark")
	_cyl(bn, 0.4, 0.5, 0.5, Vector3(0, 0.5, 0), "metal", Vector3.ZERO, 10)
	_strut(bn, Vector3(0, 0.7, 0), Vector3(0, 5.6, 0), 0.02, "ink", 4)
	var balloon := Node3D.new()
	balloon.position = Vector3(0, 7.5, 0)
	bn.add_child(balloon)
	_sphere(balloon, 1.4, Vector3.ZERO, "accent_lit", Vector3(1, 1.15, 1), false, 16)
	_torus(balloon, 1.38, 1.46, Vector3(0, -0.2, 0), "paper", Vector3.ZERO, Vector3(1, 0.4, 1))
	_strut(balloon, Vector3(0, -1.55, 0), Vector3(0, -1.9, 0), 0.02, "ink", 4)
	_box(balloon, Vector3(0.5, 0.4, 0.5), Vector3(0, -2.1, 0), "metal")
	var b := _sphere(balloon, 0.1, Vector3(0, -2.38, 0), "glow_red", Vector3.ONE, false, 8)
	_blinkers.append({"node": b, "period": 2.2, "phase": 0.6})
	_bobbers.append({"node": balloon, "base_y": 7.5, "period": 4.2})
	_count("balloon")


## The rover, one design for the parked one and the driving one (Sean, 2026-09-24, asked whether
## the rover was the same as before: there were two; this is the driving buggy's): a metal body,
## a cab, a panel on the back, an antenna with a blinking light, four wheels with hubs. Returns
## the node; the wheels go on `wheels` for whoever turns them.
func _rover(parent: Node3D, at: Vector3, yaw: float, wheels: Array) -> Node3D:
	var rv := Node3D.new()
	rv.position = at
	rv.rotation.y = yaw
	parent.add_child(rv)
	_box(rv, Vector3(2.2, 0.4, 1.3), Vector3(0, 0.75, 0), "metal")
	_box(rv, Vector3(0.8, 0.55, 1.0), Vector3(-0.45, 1.2, 0), "counter")
	_box(rv, Vector3(0.7, 0.4, 0.06), Vector3(-0.02, 1.2, 0), "glass")   # the cab's window
	_box(rv, Vector3(0.6, 0.06, 0.9), Vector3(0.55, 0.98, 0), "field_dark")
	_cyl(rv, 0.03, 0.03, 1.5, Vector3(0.8, 1.75, 0.45), "ink")
	var b := _sphere(rv, 0.1, Vector3(0.8, 2.55, 0.45), "glow_cyan", Vector3.ONE, false, 8)
	_blinkers.append({"node": b, "period": 1.0, "phase": 0.2})
	_cyl(rv, 0.2, 0.06, 0.12, Vector3(-0.7, 1.55, -0.3), "paper", Vector3(-0.7, 0, 0), 8)   # a little dish
	for wx: float in [-0.8, 0.8]:
		for wz: float in [-0.8, 0.8]:
			var wheel := _cyl(rv, 0.42, 0.42, 0.3, Vector3(wx, 0.42, wz), "ink", Vector3(PI * 0.5, 0, 0), 10)
			wheels.append(wheel)
			_cyl(rv, 0.2, 0.2, 0.32, Vector3(wx, 0.42, wz), "metal", Vector3(PI * 0.5, 0, 0), 8)
	return rv


## A small radio tower (Sean: "a space themed small radio tower"): a tapering lattice mast with
## cross braces, three ring antennas up it, a big dish and a small one on a platform, guy lines
## to anchor blocks, a cabin at the foot, a red light on top and a cyan one half way.
func _block_radio(c: Vector3, r: float, yaw: float) -> void:
	var rt := _node(c, yaw)
	var h := 8.5
	for i in 4:
		var a := i * TAU / 4.0 + PI * 0.25
		var foot := Vector3(cos(a) * 0.9, 0.0, sin(a) * 0.9)
		var top := Vector3(cos(a) * 0.25, h, sin(a) * 0.25)
		_strut(rt, foot, top, 0.05, "counter_dark", 6)
	for lvl in 6:
		var t := (lvl + 1) / 7.0
		var w := lerpf(1.8, 0.5, t)
		_box(rt, Vector3(w, 0.05, w), Vector3(0, t * h, 0), "metal")
		if lvl % 2 == 0:
			_strut(rt, Vector3(-w * 0.5, t * h, w * 0.5), Vector3(w * 0.45, (lvl + 2) / 7.0 * h, -w * 0.45), 0.03, "counter_dark", 5)
	for k in 3:
		_torus(rt, 0.45 + k * 0.1, 0.5 + k * 0.1, Vector3(0, h * (0.55 + k * 0.12), 0), "accent_lit", Vector3.ZERO, Vector3(1, 0.4, 1))
	_box(rt, Vector3(1.4, 0.08, 1.4), Vector3(0, h * 0.45, 0), "metal")   # the platform
	var big := _cyl(rt, 0.95, 0.15, 0.32, Vector3(0.7, h * 0.45 + 0.6, 0), "paper", Vector3(0, 0, -1.0), 14)
	big.rotation.y = 0.4
	_cyl(rt, 0.05, 0.05, 0.9, Vector3(0.7, h * 0.45 + 0.3, 0), "ink")
	var small := _cyl(rt, 0.4, 0.08, 0.16, Vector3(-0.6, h * 0.45 + 0.45, -0.3), "paper", Vector3(-0.8, 0, 0), 10)
	small.rotation.y = -0.6
	_cyl(rt, 0.04, 0.05, 1.8, Vector3(0, h + 0.9, 0), "ink")
	var top_light := _sphere(rt, 0.16, Vector3(0, h + 1.85, 0), "glow_red", Vector3.ONE, false, 8)
	_blinkers.append({"node": top_light, "period": 1.2, "phase": 0.1})
	var mid_light := _sphere(rt, 0.11, Vector3(0.35, h * 0.72, 0.35), "glow_cyan", Vector3.ONE, false, 8)
	_blinkers.append({"node": mid_light, "period": 2.4, "phase": 0.6})
	for k in 3:
		var a := k * TAU / 3.0 + 0.5
		var anchor := Vector3(cos(a) * 2.6, 0.0, sin(a) * 2.6)
		_box(rt, Vector3(0.4, 0.3, 0.4), anchor + Vector3(0, 0.15, 0), "counter_dark")
		var line := _strut(rt, anchor + Vector3(0, 0.3, 0), Vector3(cos(a) * 0.3, h * 0.8, sin(a) * 0.3), 0.015, "ink", 4)
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cab := _node(_at(c, yaw, 1.9, 1.2), yaw + 0.3)
	_box(cab, Vector3(1.4, 1.1, 1.1), Vector3(0, 0.55, 0), "metal")
	_box(cab, Vector3(0.5, 0.7, 0.06), Vector3(0, 0.45, 0.56), "ink")
	_box(cab, Vector3(0.14, 0.12, 0.05), Vector3(0.4, 0.9, 0.57), "glow_yellow")
	_count("radio tower")


## The space station (Sean: "a space station in the bottom middle part of the map, to take up
## space, spend a lot of time to make it look detailed"): a plated apron; a hub on a plinth with
## a band, windows all round, a glass cupola and a mast; a ring corridor on four spokes with
## windows; four modules on the ring's diagonals, one the docking module with a hatch and an
## airlock light, one a lab with a LAB 1 sign; two solar wings on a boom through the hub, framed;
## a radar dish turning on a stand; a fuel tank on a pipe; landing lights round the apron.
func _block_station(c: Vector3, r: float, yaw: float) -> void:
	var st := _node(c, yaw)
	_cyl(st, 6.9, 7.0, 0.08, Vector3(0, 0.04, 0), "metal", Vector3.ZERO, 24)
	_torus(st, 6.6, 7.0, Vector3(0, 0.08, 0), "counter_dark", Vector3.ZERO, Vector3(1, 0.25, 1))
	for k in 4:
		var a := k * TAU / 4.0
		_box(st, Vector3(0.12, 0.02, 5.8), Vector3(cos(a) * 3.8, 0.09, sin(a) * 3.8), "paper", Vector3(0, -a, 0))
	# The hub.
	_cyl(st, 2.6, 2.8, 0.5, Vector3(0, 0.25, 0), "counter_dark", Vector3.ZERO, 16)
	_cyl(st, 2.2, 2.3, 3.0, Vector3(0, 2.0, 0), "metal", Vector3.ZERO, 16)
	for k in 8:
		var a := k * TAU / 8.0 + 0.2
		var win := _cyl(st, 0.26, 0.26, 0.1, Vector3(cos(a) * 2.22, 2.4, sin(a) * 2.22), "glass", Vector3.ZERO, 10)
		win.look_at(st.to_global(Vector3(0, 2.4, 0)), Vector3.UP)
		win.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_torus(st, 2.2, 2.38, Vector3(0, 3.35, 0), "accent_lit", Vector3.ZERO, Vector3(1, 0.5, 1))
	_torus(st, 2.2, 2.38, Vector3(0, 0.75, 0), "accent_lit", Vector3.ZERO, Vector3(1, 0.5, 1))
	_cyl(st, 2.0, 2.25, 0.3, Vector3(0, 3.65, 0), "counter_dark", Vector3.ZERO, 16)
	_sphere(st, 1.3, Vector3(0, 3.8, 0), "glass", Vector3(1.0, 0.7, 1.0), true, 16)
	for k in 6:
		var a := k * TAU / 6.0
		_strut(st, Vector3(cos(a) * 1.28, 3.8, sin(a) * 1.28), Vector3(0, 4.7, 0), 0.03, "counter_dark", 5)
	_cyl(st, 0.3, 0.35, 0.3, Vector3(0, 4.85, 0), "metal", Vector3.ZERO, 10)
	_cyl(st, 0.04, 0.05, 3.0, Vector3(0, 6.5, 0), "ink")
	var top := _sphere(st, 0.16, Vector3(0, 8.05, 0), "glow_red", Vector3.ONE, false, 8)
	_blinkers.append({"node": top, "period": 1.4, "phase": 0.0})
	_box(st, Vector3(0.5, 1.8, 1.3), Vector3(0, 1.2, -2.35), "counter_dark", Vector3(0, PI * 0.5, 0))   # the airlock, north
	_box(st, Vector3(0.9, 1.4, 0.2), Vector3(0, 1.1, -2.55), "metal")
	_box(st, Vector3(0.3, 0.3, 0.12), Vector3(0, 2.3, -2.6), "glow_yellow")
	_label(st, "LAB 1", Vector3(0, 2.95, -2.34), 48, Palette.hud_colour("paper"), PI)
	# The ring corridor on four spokes.
	var ring := _torus(st, 4.45, 5.95, Vector3(0, 1.6, 0), "metal")
	ring.mesh.rings = 48
	ring.mesh.ring_segments = 10
	for k in 4:
		var a := k * TAU / 4.0 + PI * 0.5
		_cyl(st, 0.5, 0.5, 3.2, Vector3(cos(a) * 3.7, 1.6, sin(a) * 3.7), "metal", Vector3(0, PI - a, PI * 0.5), 10)
		_torus(st, 0.5, 0.62, Vector3(cos(a) * 2.4, 1.6, sin(a) * 2.4), "counter_dark", Vector3(0, -a, PI * 0.5))
	for k in 12:
		var a := k * TAU / 12.0 + 0.13
		var win := _cyl(st, 0.2, 0.2, 0.1, Vector3(cos(a) * 5.95, 1.72, sin(a) * 5.95), "glass", Vector3.ZERO, 8)
		win.look_at(st.to_global(Vector3(0, 1.72, 0)), Vector3.UP)
		win.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	# Four modules on the ring's diagonals, tangent to it.
	for k in 4:
		var a := k * TAU / 4.0 + PI * 0.25
		var at := Vector3(cos(a) * 5.2, 1.6, sin(a) * 5.2)
		var tangent := a + PI * 0.5
		var mod := _cyl(st, 1.0, 1.0, 3.6, at, "paper" if k % 2 == 0 else "metal", Vector3(0, PI - tangent, PI * 0.5), 12)
		for e: float in [-1.85, 1.85]:
			_cyl(st, 1.04, 1.04, 0.14, at + Vector3(cos(tangent) * e, 0, sin(tangent) * e), "counter_dark", Vector3(0, PI - tangent, PI * 0.5), 12)
		for w in 3:
			var off := (w - 1) * 1.1
			var wp := at + Vector3(cos(tangent) * off, 0.35, sin(tangent) * off) + Vector3(cos(a), 0, sin(a)) * 0.95
			var win := _cyl(st, 0.2, 0.2, 0.1, wp, "glass", Vector3.ZERO, 8)
			win.look_at(st.to_global(at + Vector3(cos(tangent) * off, 0.35, sin(tangent) * off)), Vector3.UP)
			win.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		if k == 1:
			# The docking module: a hatch ring on its outer end and an airlock light.
			var end := at + Vector3(cos(tangent), 0, sin(tangent)) * 1.95
			_torus(st, 0.5, 0.75, end, "ink", Vector3(0, -tangent, PI * 0.5))
			_cyl(st, 0.45, 0.45, 0.2, end, "counter_dark", Vector3(0, PI - tangent, PI * 0.5), 10)
			var al := _sphere(st, 0.12, end + Vector3(0, 0.95, 0), "glow_green", Vector3.ONE, false, 8)
			_blinkers.append({"node": al, "period": 1.9, "phase": 0.4})
		if k == 3:
			_box(st, Vector3(1.6, 0.3, 0.3), at + Vector3(0, 1.15, 0), "accent_lit", Vector3(0, -tangent, 0))
	# Solar wings on a boom through the hub.
	_cyl(st, 0.12, 0.12, 15.0, Vector3(0, 3.1, 0), "counter_dark", Vector3(0, 0, PI * 0.5), 8)
	for s: float in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.position = Vector3(s * 5.9, 3.1, 0)
		wing.rotation.x = 0.35
		st.add_child(wing)
		_box(wing, Vector3(6.4, 0.08, 2.6), Vector3.ZERO, "field_dark")
		for e: float in [-1.3, 1.3]:
			_box(wing, Vector3(6.5, 0.12, 0.08), Vector3(0, 0, e), "metal")
		for k in 3:
			_box(wing, Vector3(0.06, 0.1, 2.6), Vector3(k * 2.1 - 2.1, 0, 0), "metal")
		var tip := _sphere(wing, 0.1, Vector3(s * 3.3, 0.1, 0), "glow_red" if s < 0 else "glow_cyan", Vector3.ONE, false, 8)
		_blinkers.append({"node": tip, "period": 1.6, "phase": 0.5 if s < 0 else 0.0})
	# A radar dish turning on a stand, past the ring.
	var rd := _node(_at(c, yaw, 0.0, 7.6), yaw)
	_cyl(rd, 0.5, 0.6, 0.3, Vector3(0, 0.15, 0), "counter_dark", Vector3.ZERO, 10)
	_cyl(rd, 0.1, 0.12, 1.6, Vector3(0, 1.1, 0), "metal")
	var head := Node3D.new()
	head.position = Vector3(0, 1.9, 0)
	rd.add_child(head)
	_cyl(head, 1.1, 0.15, 0.35, Vector3(0, 0.3, 0), "paper", Vector3(-0.8, 0, 0), 14)
	_cyl(head, 0.04, 0.04, 1.0, Vector3(0, 0.55, 0.4), "ink", Vector3(-0.8, 0, 0))
	_sphere(head, 0.08, Vector3(0, 0.95, 0.7), "glow_red", Vector3.ONE, false, 6)
	_spinners.append({"node": head, "rate": 0.5})
	# A fuel tank on a pipe.
	var tk := _node(_at(c, yaw, 6.2, -4.6), yaw + 0.4)
	_cyl(tk, 0.7, 0.7, 2.6, Vector3(0, 0.9, 0), "paper", Vector3(0, 0, PI * 0.5), 12)
	_sphere(tk, 0.7, Vector3(1.3, 0.9, 0), "paper", Vector3(0.4, 1, 1), false, 10)
	_sphere(tk, 0.7, Vector3(-1.3, 0.9, 0), "paper", Vector3(0.4, 1, 1), false, 10)
	for hx: float in [-0.7, 0.7]:
		_box(tk, Vector3(0.4, 0.5, 1.5), Vector3(hx, 0.25, 0), "counter_dark")
	_torus(tk, 0.68, 0.76, Vector3(0, 0.9, 0), "accent_lit", Vector3(0, 0, PI * 0.5))
	_cyl(tk, 0.08, 0.08, 4.4, Vector3(-2.0, 0.4, 0.9), "counter_dark", Vector3(0, 0.5, PI * 0.5), 8)
	_torus(tk, 0.12, 0.2, Vector3(-0.3, 1.75, 0), "ink", Vector3(PI * 0.5, 0, 0))
	# Landing lights round the apron.
	for i in 10:
		var a := i * TAU / 10.0
		var lp := c + Vector3(cos(a) * 7.6, 0, sin(a) * 7.6)
		if _tile_clear(lp.x, lp.z, 1.6) and _inside(lp.x, lp.z, 0.98):
			_cyl(self, 0.1, 0.12, 0.26, Vector3(lp.x, _top + 0.13, lp.z), "counter_dark")
			_sphere(self, 0.1, Vector3(lp.x, _top + 0.3, lp.z), "glow_yellow" if i % 2 == 0 else "glow_cyan", Vector3.ONE, false, 8)
	_count("space station")


## A crashed satellite in the margin: the body nose-down in the ground, one panel bent up, a dish
## askew, a scorch mark and some debris.
func _block_satellite(c: Vector3, r: float, yaw: float) -> void:
	var sn := _node(c, yaw)
	var scorch := _sphere(sn, 2.4, Vector3(0.2, -0.02, 0.1), "crater", Vector3(1.0, 0.012, 0.8), false, 12)
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := _box(sn, Vector3(1.0, 1.0, 1.4), Vector3(0, 0.45, 0), "metal", Vector3(0.6, 0.3, 0.4))
	body.position.y = 0.35
	_box(sn, Vector3(3.0, 0.08, 1.0), Vector3(1.4, 1.3, 0.2), "field_dark", Vector3(0.2, 0.3, 0.9))
	_box(sn, Vector3(1.4, 0.08, 1.0), Vector3(-1.2, 0.2, -0.3), "field_dark", Vector3(0.1, -0.4, 0.15))
	var dish := _cyl(sn, 0.55, 0.1, 0.24, Vector3(-0.4, 1.0, 0.9), "paper", Vector3(1.2, 0.3, 0.4), 10)
	dish.rotation.y = 0.8
	_cyl(sn, 0.03, 0.03, 1.2, Vector3(0.3, 1.2, -0.6), "ink", Vector3(0.5, 0, 0.6))
	for k in 5:
		var a := k * 1.3
		var d := _cyl(sn, 0.0, 0.12, 0.2, Vector3(cos(a) * (1.4 + k * 0.2), 0.1, sin(a) * (1.4 + k * 0.2)), "counter_dark", Vector3(0.9, a, 0.4), 6)
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var b := _sphere(sn, 0.08, Vector3(0.25, 1.05, 0.15), "glow_red", Vector3.ONE, false, 6)
	_blinkers.append({"node": b, "period": 2.8, "phase": 0.0})
	_count("crashed satellite")


## A rock arch in the margin: two boulders with a slab across, pebbles round them.
func _block_arch(c: Vector3, r: float, yaw: float) -> void:
	var an := _node(c, yaw)
	for s: float in [-1.0, 1.0]:
		var rock := _sphere(an, 1.3, Vector3(s * 1.9, 0.6, 0), "rock", Vector3(1.0, 1.25, 0.9), false, 8)
		rock.rotation.y = s * 0.5
	var slab := _sphere(an, 1.2, Vector3(0, 2.15, 0), "moon_dark", Vector3(2.3, 0.45, 0.8), false, 8)
	slab.rotation.z = 0.06
	for k in 7:
		var a := k * 0.9
		var rr := _rng.randf_range(0.1, 0.2)
		_sphere(an, rr, Vector3(cos(a) * 2.6, rr * 0.5, sin(a) * 1.4), "crater" if k % 2 == 0 else "moon_dark", Vector3(1.3, 0.6, 1.0), false, 6)
	_count("rock arch")


## A telescope dome in the margin with a couple of instrument boxes.
func _block_telescope(c: Vector3, r: float, yaw: float) -> void:
	_telescope(c, yaw)
	var ib := _node(_at(c, yaw, -2.4, 1.0), yaw - 0.4)
	_box(ib, Vector3(0.8, 0.6, 0.6), Vector3(0, 0.3, 0), "metal")
	_cyl(ib, 0.03, 0.03, 1.4, Vector3(0.2, 1.3, 0), "ink")
	_box(ib, Vector3(0.2, 0.14, 0.06), Vector3(0, 0.45, 0.31), "glow_green")


## Mission control, near the centre (Sean, 2026-09-24: "add another structure near the center,
## like a space themed building, add detail"): two storeys on a plinth, a window band round the
## ground floor, the upper floor set back with a wide front window and a railed roof, stairs up
## the side, an airlock with a CONTROL sign, a big dish on a mount, two masts with lights, a radar
## bar turning, floodlight masts at the front corners and a flag.
func _block_control(c: Vector3, r: float, yaw: float) -> void:
	var b := _node(c, yaw)
	_box(b, Vector3(6.6, 0.3, 4.6), Vector3(0, 0.15, 0), "counter_dark")
	_box(b, Vector3(6.0, 2.6, 4.0), Vector3(0, 1.6, 0), "metal")
	for k in 2:
		var z := (k * 2 - 1) * 2.01
		_box(b, Vector3(4.4, 0.7, 0.06), Vector3(-0.4, 1.9, z), "glass")
		var x := (k * 2 - 1) * 3.01
		_box(b, Vector3(0.06, 0.7, 3.0), Vector3(x, 1.9, 0), "glass")
	_box(b, Vector3(6.2, 0.16, 4.2), Vector3(0, 2.98, 0), "counter_dark")
	_box(b, Vector3(4.0, 2.2, 2.8), Vector3(-0.6, 4.1, -0.3), "paper")
	_box(b, Vector3(3.4, 1.1, 0.08), Vector3(-0.6, 4.3, 1.11), "glass")
	_box(b, Vector3(4.2, 0.14, 3.0), Vector3(-0.6, 5.28, -0.3), "counter_dark")
	for s: float in [-1.0, 1.0]:
		_box(b, Vector3(4.2, 0.05, 0.05), Vector3(-0.6, 5.78, -0.3 + s * 1.5), "ink")
		for k in 5:
			_box(b, Vector3(0.05, 0.45, 0.05), Vector3(-2.6 + k * 1.0, 5.57, -0.3 + s * 1.5), "ink")
	for k in 7:
		_box(b, Vector3(0.9, 0.08, 0.4), Vector3(2.55, 0.5 + k * 0.4, 1.5 - k * 0.42), "metal")
	_box(b, Vector3(0.06, 1.0, 3.0), Vector3(3.02, 2.6, 0.2), "ink")   # the stair rail
	_box(b, Vector3(1.2, 2.0, 0.5), Vector3(1.9, 1.15, 2.2), "counter_dark")
	_box(b, Vector3(0.7, 1.4, 0.1), Vector3(1.9, 1.0, 2.5), "metal")
	_box(b, Vector3(0.2, 0.2, 0.1), Vector3(1.9, 2.0, 2.5), "glow_yellow")
	_label(b, "CONTROL", Vector3(1.9, 2.5, 2.47), 40, Palette.hud_colour("paper"), 0.0)
	_cyl(b, 0.14, 0.18, 0.9, Vector3(1.9, 3.5, -0.9), "counter_dark")
	var dish := _cyl(b, 1.3, 0.2, 0.4, Vector3(1.9, 4.25, -0.9), "paper", Vector3(-0.9, 0.3, 0), 14)
	dish.rotation.y = 0.3
	_cyl(b, 0.04, 0.04, 1.2, Vector3(1.9, 4.7, -0.45), "ink", Vector3(-0.9, 0, 0))
	for s: float in [-1.0, 1.0]:
		_cyl(b, 0.04, 0.05, 2.6, Vector3(-0.6 + s * 1.7, 6.6, -0.3 + s * 0.8), "ink")
		var lt := _sphere(b, 0.12, Vector3(-0.6 + s * 1.7, 7.95, -0.3 + s * 0.8), "glow_red" if s < 0 else "glow_cyan", Vector3.ONE, false, 8)
		_blinkers.append({"node": lt, "period": 1.5 if s < 0 else 2.3, "phase": 0.3})
	var radar := Node3D.new()
	radar.position = Vector3(-0.6, 5.35, -0.3)
	b.add_child(radar)
	_cyl(radar, 0.08, 0.1, 0.5, Vector3(0, 0.25, 0), "metal")
	_box(radar, Vector3(1.6, 0.35, 0.06), Vector3(0, 0.6, 0), "paper")
	_spinners.append({"node": radar, "rate": 1.2})
	for s: float in [-1.0, 1.0]:
		var mast := _node(_at(c, yaw, s * 3.7, 2.7), yaw)
		_cyl(mast, 0.05, 0.07, 3.4, Vector3(0, 1.7, 0), "counter_dark")
		_box(mast, Vector3(0.4, 0.25, 0.3), Vector3(0, 3.45, -0.1), "ink", Vector3(-0.6, 0, 0))
		_box(mast, Vector3(0.3, 0.1, 0.05), Vector3(0, 3.42, 0.08), "glow_yellow", Vector3(-0.6, 0, 0))
	_cyl(b, 0.03, 0.03, 3.2, Vector3(-3.5, 1.6, 2.6), "ink")
	_box(b, Vector3(0.6, 0.4, 0.03), Vector3(-3.2, 2.9, 2.6), "accent_lit")
	_count("mission control")


## The rocket as decoration (Sean: "a couple more rockets around the map, they will just be
## decoration"), the taxi's shape at a scale: a cream body with a band and a skirt, an engine bell
## and throat, three fins, a nose, a porthole. `lying` lays it on its side along the node's x.
func _rocket_prop(parent: Node3D, at: Vector3, yaw: float, s: float, lying: bool) -> Node3D:
	var rk := Node3D.new()
	rk.position = at
	rk.rotation.y = yaw
	parent.add_child(rk)
	var body := Node3D.new()
	body.scale = Vector3.ONE * s
	if lying:
		body.rotation.z = -PI * 0.5
		body.position = Vector3(-2.0 * s, 0.98 * s, 0)
	rk.add_child(body)
	_cyl(body, 0.72, 0.72, 3.6, Vector3(0, 2.5, 0), "paper", Vector3.ZERO, 14)
	_cyl(body, 0.74, 0.74, 0.5, Vector3(0, 2.0, 0), "accent_lit", Vector3.ZERO, 14)
	_cyl(body, 0.8, 0.8, 0.36, Vector3(0, 0.88, 0), "accent_lit", Vector3.ZERO, 14)
	_cyl(body, 0.34, 0.58, 0.46, Vector3(0, 0.47, 0), "ink", Vector3.ZERO, 14)
	_cyl(body, 0.3, 0.3, 0.06, Vector3(0, 0.3, 0), "metal", Vector3.ZERO, 8)
	for fk in 3:
		var fa := fk * TAU / 3.0 + 0.5
		var fin := MeshInstance3D.new()
		var fm := PrismMesh.new()
		fm.size = Vector3(1.0, 1.5, 0.1)
		fm.left_to_right = 0.0
		fin.mesh = fm
		fin.position = Vector3(cos(fa) * 1.2, 0.99, sin(fa) * 1.2)
		fin.rotation.y = -fa
		fin.material_override = _mat("accent_lit")
		body.add_child(fin)
	_cyl(body, 0.0, 0.72, 1.5, Vector3(0, 5.05, 0), "accent_lit", Vector3.ZERO, 14)
	_cyl(body, 0.26, 0.26, 0.08, Vector3(0, 3.2, -0.72), "glass", Vector3(PI * 0.5, 0, 0), 10)
	return rk


## A rocket standing on a small pad in the margin, lights round it.
func _block_rocket_pad(c: Vector3, r: float, yaw: float) -> void:
	var pn := _node(c, yaw)
	_cyl(pn, 2.1, 2.1, 0.14, Vector3(0, 0.07, 0), "metal", Vector3.ZERO, 16)
	_torus(pn, 1.7, 1.95, Vector3(0, 0.15, 0), "accent_lit", Vector3.ZERO, Vector3(1, 0.3, 1))
	_rocket_prop(pn, Vector3.ZERO, 0.0, 0.8, false)
	for i in 6:
		var a := i * TAU / 6.0
		_cyl(pn, 0.1, 0.12, 0.26, Vector3(cos(a) * 2.5, 0.13, sin(a) * 2.5), "counter_dark")
		_sphere(pn, 0.1, Vector3(cos(a) * 2.5, 0.3, sin(a) * 2.5), "glow_yellow" if i % 2 == 0 else "glow_red", Vector3.ONE, false, 8)
	_count("rocket, standing")


## A rocket on its side on a service cradle, a ladder against it, a toolbox and a hose.
func _block_rocket_cradle(c: Vector3, r: float, yaw: float) -> void:
	var cn := _node(c, yaw)
	for x: float in [-1.2, 1.6]:
		_box(cn, Vector3(0.5, 0.9, 1.9), Vector3(x, 0.45, 0), "counter_dark")
		_box(cn, Vector3(0.6, 0.12, 2.1), Vector3(x, 0.06, 0), "metal")
	_rocket_prop(cn, Vector3(0.0, 0.0, 0.0), 0.0, 0.75, true)
	for k in 4:
		_box(cn, Vector3(0.6, 0.04, 0.04), Vector3(0.3, 0.35 + k * 0.35, 0.95 + k * 0.12), "ink")
	for s: float in [-0.3, 0.3]:
		_cyl(cn, 0.03, 0.03, 1.8, Vector3(0.3 + s, 0.9, 1.15), "ink", Vector3(0.45, 0, 0))
	_box(cn, Vector3(0.7, 0.35, 0.4), Vector3(-2.6, 0.18, 1.2), "counter_dark")
	_box(cn, Vector3(0.74, 0.06, 0.44), Vector3(-2.6, 0.37, 1.2), "metal")
	var hose := _strut(cn, Vector3(-2.3, 0.4, 1.0), Vector3(-1.4, 0.75, 0.1), 0.05, "ink", 6)
	hose.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_count("rocket, on a cradle")
