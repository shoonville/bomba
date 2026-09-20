class_name BoardDressing
extends Node3D
## The detail pass on the board (Sean: "add a bunch of detail... make it look great"): everything
## a moon base has around a walkway, built from primitives in the board palette and placed by
## seeded search in spots clear of the tiles, the craters and the five landmark props. Nothing
## here touches the rules, the tiles' positions or the camera.
##   On the path: an inset on every tile, collars on the posts, a stripe on every plank, cables
##     slung under the planks, a lamp beside every fifth space, a pennant banner over the start.
##   On the ground: hatches, rock clusters with pebbles, dust patches, cracks, rim rock.
##   Around: an annex platform off the rim carrying the habitat domes with tube corridors and
##     the greenhouse; on the slab a solar farm, fuel tanks, cargo stacks, a comms mast,
##     antenna masts, a telescope dome, a drill rig over a crater, oxygen tanks, landing lights
##     around the pad, a welcome sign, a pad sign, an arrow post.
##   Alive: a patrol drone flying the loop, a buggy driving the longest clear stretch of rim,
##     blinking lights, a shooting star now and then, a space station turning on the horizon.
## Deterministic from the board id, so every peer sees the same base.

var _view: Node3D
var _graph: BoardGraph
var _centre: Vector3
var _rx: float
var _rz: float
var _top: float
var _shadow: Color
var _rng := RandomNumberGenerator.new()
var _occupied: Array = []        # Vector3(x, z, radius) of everything placed, craters and landmarks included
var _mats: Dictionary = {}
var _tile_positions: Array = []  # Vector3 per space
var _annex: Vector3 = Vector3.INF   # centre of the annex platform, if built
var _annex_r: float = 8.0

# Alive things
var _blinkers: Array = []        # [{node, period, phase}]
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
# The vending machines: one per machine spot (a space flagged "goal"), on a raised pad past the
# rim, reached by a bridge from the space. space id → {node, sign, beam, knob, globe, tray}
var _machines: Dictionary = {}
var _machine_angles: Array = []
var _active_machine: String = ""
var counts: Dictionary = {}      # what was placed, for the log


func build(view: Node3D, g: BoardGraph, centre: Vector3, rx: float, rz: float, top: float,
		craters: Array, landmarks: Array, shadow: Color) -> void:
	_view = view
	_graph = g
	_centre = centre
	_rx = rx
	_rz = rz
	_top = top
	_shadow = shadow
	_rng.seed = hash(g.id) + 101
	for sid in g.ids():
		_tile_positions.append(g.get_space(sid).position)
	for cr in craters:
		_occupied.append(Vector3(cr.x, cr.y, cr.z + 0.6))
	for sp in landmarks:
		_occupied.append(Vector3(sp.x, sp.y, 4.6))
	_path_details()
	_machine_pads()
	_path_props()
	_build_annexes()
	_plan_road()
	_ground_details()
	_structures(craters, landmarks)
	_signs_and_pennants(landmarks)
	_life()


## The buggy's road: the longest clear stretch of a ring near the rim, chosen after the annexes
## (their bridge mouths are reserved) and before the ground props so they keep off it. Falls
## back to a loop around the base annex.
func _plan_road() -> void:
	var samples: Array = []
	var clear: Array = []
	var n := 96
	for i in n:
		var a := i * TAU / n
		var p := Vector3(_centre.x + cos(a) * _rx * 0.92, _top, _centre.z + sin(a) * _rz * 0.92)
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
		"moon_light": m = CelMaterial.for_colour(Palette.map_colour("board", "moon").lightened(0.12), _shadow)
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
	var dx := (x - _centre.x) / _rx
	var dz := (z - _centre.z) / _rz
	return dx * dx + dz * dz <= f_max * f_max


## A random spot at least `tile_d` from every tile and clear of everything placed, within the
## slab. Returns Vector2.INF when nothing fits in `tries`.
func _spot(tile_d: float, own: float, f_min: float = 0.15, f_max: float = 0.9, tries: int = 300) -> Vector2:
	for i in tries:
		var a := _rng.randf_range(0.0, TAU)
		var f := sqrt(_rng.randf_range(f_min * f_min, f_max * f_max))
		var x := _centre.x + cos(a) * _rx * f
		var z := _centre.z + sin(a) * _rz * f
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
			var stripe := _box(self, Vector3(0.12, 0.02, length * 0.9), Vector3.ZERO, "paper")
			stripe.global_position = mid
			if (q - p).length() > 0.01:
				stripe.look_at(q, Vector3.UP)
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
			var side := Vector2(-dir.y, dir.x)
			var out := Vector2(p.x - _centre.x, p.z - _centre.z).normalized()
			if side.dot(out) < 0.0:
				side = -side
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
		var out := Vector2(p.x - _centre.x, p.z - _centre.z).normalized()
		if side.dot(out) < 0.0:
			side = -side
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
	# Hatches: a plate with a rim and a light, flush with the ground near the walkway.
	for k in 12:
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
	for k in 10:
		var sp := _spot(2.3, 1.7, 0.1, 0.95, 200)
		if sp == Vector2.INF:
			break
		var c := _node(Vector3(sp.x, _top, sp.y), _rng.randf_range(0.0, TAU))
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
	# Loose pebbles anywhere the ground is bare.
	for k in 60:
		var a := _rng.randf_range(0.0, TAU)
		var f := sqrt(_rng.randf_range(0.02, 0.9))
		var x := _centre.x + cos(a) * _rx * f
		var z := _centre.z + sin(a) * _rz * f
		if not _tile_clear(x, z, 1.5):
			continue
		var r := _rng.randf_range(0.07, 0.15)
		var p := _sphere(self, r, Vector3(x, _top + r * 0.5, z), "moon_dark" if k % 2 == 0 else "crater", Vector3(1.3, 0.6, 1.0), false, 6)
		p.rotation.y = _rng.randf_range(0.0, TAU)
	# Dust patches: a shade off the slab, thin, so the flat ground is not one tone.
	for k in 9:
		var a := _rng.randf_range(0.0, TAU)
		var f := sqrt(_rng.randf_range(0.05, 0.85))
		var x := _centre.x + cos(a) * _rx * f
		var z := _centre.z + sin(a) * _rz * f
		if not _tile_clear(x, z, 2.0):
			continue
		var d := _sphere(self, _rng.randf_range(1.6, 3.2), Vector3(x, _top - 0.02, z), "moon_light" if k % 2 == 0 else "moon_dark",
			Vector3(1.0, 0.012, _rng.randf_range(0.6, 1.0)), false, 9)
		d.rotation.y = _rng.randf_range(0.0, TAU)
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Rim edge: chunks of rock along the slab's edge so it reads as a cliff, not a cut.
	for k in 22:
		var a := k * TAU / 22.0 + _rng.randf_range(-0.1, 0.1)
		var x := _centre.x + cos(a) * _rx * _rng.randf_range(0.99, 1.04)
		var z := _centre.z + sin(a) * _rz * _rng.randf_range(0.99, 1.04)
		var r := _rng.randf_range(0.5, 1.4)
		var chunk := _sphere(self, r, Vector3(x, _top - _rng.randf_range(0.2, 1.4), z), "rock" if k % 3 != 0 else "moon_dark",
			Vector3(_rng.randf_range(0.8, 1.4), _rng.randf_range(0.6, 1.1), _rng.randf_range(0.8, 1.4)), false, 7)
		chunk.rotation = Vector3(_rng.randf_range(0, 1), _rng.randf_range(0.0, TAU), 0)
	# Cracks in the surface: thin dark lines in a few places.
	for k in 8:
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

## The vending machine spots: every space flagged "goal" gets a raised pad past the rim, a level
## bridge to it from the space, and a machine on the pad in front of a small dome hut. Only the
## active machine is lit; the others stand dark until the machine moves to them.
func _machine_pads() -> void:
	for sid in _graph.goal_candidates():
		var p: Vector3 = _graph.get_space(sid).position
		var out := Vector2(p.x - _centre.x, p.z - _centre.z).normalized()
		var a := atan2(out.y, out.x)
		_machine_angles.append(a)
		var rim := Vector2(_centre.x + cos(a) * _rx, _centre.z + sin(a) * _rz)
		var pc := rim + out * 5.0
		var pad := Vector3(pc.x, _top, pc.y)
		var deck_y := p.y - 0.2   # the pad's deck at tile level, so the bridge is flat
		var o3 := Vector3(out.x, 0, out.y)
		var yaw := atan2(out.x, out.y)   # a node's -Z then faces the bridge
		_occupied.append(Vector3(pc.x, pc.y, 4.6))
		_occupied.append(Vector3(rim.x, rim.y, 2.4))
		# The chunk: a raised 8-sided deck on a rock root, rim chunks round it.
		var h := deck_y - (_top - 1.3)
		_cyl(self, 3.4, 3.1, h, Vector3(pad.x, _top - 1.3 + h * 0.5, pad.z), "moon", Vector3(0, a, 0), 8)
		_cyl(self, 3.6, 3.6, 0.24, Vector3(pad.x, deck_y - 0.12, pad.z), "metal", Vector3(0, a, 0), 8)
		_cyl(self, 3.0, 0.6, 7.0, Vector3(pad.x, _top - 2.6 - 3.5, pad.z), "moon_dark", Vector3(0, a + 0.4, 0), 8)
		for k in 7:
			var ca := k * TAU / 7.0 + 0.3
			var r := _rng.randf_range(0.4, 0.9)
			_sphere(self, r, Vector3(pad.x + cos(ca) * 3.4, deck_y - _rng.randf_range(0.6, 1.6), pad.z + sin(ca) * 3.4),
				"rock" if k % 3 != 0 else "moon_dark", Vector3(1.2, 0.7, 1.1), false, 7)
		# The bridge: a level walkway from the space's outer edge to the pad, plated, with rails
		# and a lamp at the pad end.
		var from := p + o3 * 1.25 + Vector3(0, -0.12, 0)
		var to := pad + Vector3(0, deck_y - _top, 0) - o3 * 3.2
		var mid := (from + to) * 0.5
		var length := (to - from).length()
		# The bridge's corridor is off limits to props, signs and landmarks (a crate and the welcome
		# sign were standing in its rails): a chain of 1.4 m circles from the space to the pad.
		var corridor := maxi(2, int(length) + 2)
		for k in corridor:
			var c := (from - o3 * 0.6).lerp(to, float(k) / float(corridor - 1))
			_occupied.append(Vector3(c.x, c.z, 1.4))
		_box(self, Vector3(1.7, 0.16, length), mid, "metal", Vector3(0, yaw, 0))
		var plates := maxi(1, int(length / 1.0))
		for k in plates:
			var t := (k + 0.5) / plates
			_box(self, Vector3(1.6, 0.03, 0.12), from.lerp(to, t) + Vector3(0, 0.1, 0), "counter_dark", Vector3(0, yaw, 0))
		for side: float in [-1.0, 1.0]:
			var rail_off := Vector3(-out.y, 0, out.x) * side * 0.8
			_box(self, Vector3(0.08, 0.08, length), mid + rail_off + Vector3(0, 0.9, 0), "counter_dark", Vector3(0, yaw, 0))
			var posts := maxi(2, int(length / 1.5) + 1)
			for k in posts:
				var t := (k + 0.5) / posts
				_box(self, Vector3(0.07, 0.9, 0.07), from.lerp(to, t) + rail_off + Vector3(0, 0.45, 0), "counter_dark")
		var lamp := _node(to + Vector3(-out.y, 0, out.x) * 1.1)
		_cyl(lamp, 0.06, 0.08, 2.0, Vector3(0, 1.0, 0), "counter_dark")
		_box(lamp, Vector3(0.3, 0.26, 0.3), Vector3(0, 2.1, 0), "glass")
		_box(lamp, Vector3(0.36, 0.06, 0.36), Vector3(0, 2.26, 0), "counter_dark")
		# The dome hut behind the machine, its door toward it.
		var hut := _node(pad + Vector3(0, deck_y - _top, 0) + o3 * 1.5, yaw)
		_cyl(hut, 1.55, 1.6, 0.4, Vector3(0, 0.2, 0), "metal", Vector3.ZERO, 14)
		_sphere(hut, 1.5, Vector3(0, 0.4, 0), "paper", Vector3.ONE, true, 14)
		_torus(hut, 1.48, 1.6, Vector3(0, 0.4, 0), "counter_dark", Vector3.ZERO, Vector3(1, 0.45, 1))
		_box(hut, Vector3(0.9, 1.3, 0.3), Vector3(0, 0.85, -1.4), "counter_dark")
		_box(hut, Vector3(0.6, 1.0, 0.1), Vector3(0, 0.8, -1.52), "metal")
		_cyl(hut, 0.3, 0.34, 0.2, Vector3(0, 1.95, 0), "counter_dark", Vector3.ZERO, 8)
		for w in 3:
			var wa := w * TAU / 3.0 + 1.6
			var win := _cyl(hut, 0.22, 0.22, 0.08, Vector3(cos(wa) * 1.35, 0.95, sin(wa) * 1.35), "glass", Vector3.ZERO, 8)
			win.look_at(hut.to_global(Vector3(0, 0.95, 0)), Vector3.UP)
			win.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		# The machine itself, in front of the hut, facing the bridge.
		var m := _node(pad + Vector3(0, deck_y - _top, 0) - o3 * 0.9, yaw)
		_box(m, Vector3(1.3, 2.0, 1.0), Vector3(0, 1.0, 0), "metal")
		_box(m, Vector3(1.34, 0.1, 1.04), Vector3(0, 0.05, 0), "counter_dark")
		_box(m, Vector3(1.34, 0.1, 1.04), Vector3(0, 2.0, 0), "counter_dark")
		for sx: float in [-0.67, 0.67]:
			_box(m, Vector3(0.04, 1.6, 0.8), Vector3(sx, 1.05, 0), "accent_lit")
		_box(m, Vector3(1.1, 0.9, 0.04), Vector3(0, 1.45, -0.51), "ink")   # the front panel
		_box(m, Vector3(0.16, 0.05, 0.06), Vector3(0.38, 1.7, -0.53), "glow_yellow")   # coin slot
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
		_machines[sid] = {"node": m, "sign": sign, "beam": beam, "knob": knob, "globe": globe,
			"tray": m.position + Vector3(0, 0.6, 0) - o3 * 0.6}
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


## Two annex platforms off the rim, where the tiles sit farthest from it and at least 110° apart,
## and clear of the machine pads: the base (habitat, greenhouse, cargo) and the works (fuel tanks,
## solar array, telescope).
func _build_annexes() -> void:
	var clearance: Array = []
	for i in 36:
		var a := i * TAU / 36.0
		var rim := Vector2(_centre.x + cos(a) * _rx, _centre.z + sin(a) * _rz)
		var d := 1e9
		for p in _tile_positions:
			d = minf(d, Vector2(p.x - rim.x, p.z - rim.y).length())
		# An annex (8 m) at rim + 11 m spans about 13° of arc, a machine pad about 7°: keep 22° clear.
		for ma in _machine_angles:
			if absf(wrapf(a - float(ma), -PI, PI)) < deg_to_rad(22.0):
				d = -1.0
		clearance.append(d)
	var best_a := 0.0
	var best_d := -1.0
	for i in 36:
		if clearance[i] > best_d:
			best_d = clearance[i]
			best_a = i * TAU / 36.0
	if best_d < 0.0:
		return   # every angle is a machine's: no annexes on this board
	var second_a := best_a + PI
	var second_d := -1.0
	for i in 36:
		var a := i * TAU / 36.0
		var apart := absf(wrapf(a - best_a, -PI, PI))
		if apart >= deg_to_rad(90.0) and clearance[i] > second_d:
			second_d = clearance[i]
			second_a = a
	var base := _annex_platform(best_a, 8.0)
	_annex = base["centre"]
	_annex_r = 8.0
	var dir: Vector2 = base["dir"]
	var side := Vector2(-dir.y, dir.x)
	_habitat(_annex, best_a + PI)
	_greenhouse(_annex + Vector3(side.x, 0, side.y) * 4.6 + Vector3(dir.x, 0, dir.y) * 1.0, best_a + PI * 0.5)
	_cargo(_annex - Vector3(side.x, 0, side.y) * 5.2 + Vector3(dir.x, 0, dir.y) * 2.0, best_a, 4)
	if second_d < 0.0:
		return   # room for one annex only
	var works := _annex_platform(second_a, 7.5)
	var wc: Vector3 = works["centre"]
	var wd: Vector2 = works["dir"]
	var ws := Vector2(-wd.y, wd.x)
	_fuel_tanks(wc + Vector3(wd.x, 0, wd.y) * 1.2, second_a + PI * 0.5)
	_solar_array(wc + Vector3(ws.x, 0, ws.y) * 4.2 - Vector3(wd.x, 0, wd.y) * 1.6, second_a, 2)
	_telescope(wc - Vector3(ws.x, 0, ws.y) * 4.4 - Vector3(wd.x, 0, wd.y) * 1.2, second_a + 0.6)
	var an := _node(wc + Vector3(wd.x, 0, wd.y) * 5.6 + Vector3(ws.x, 0, ws.y) * 2.5)
	_cyl(an, 0.3, 0.3, 0.3, Vector3(0, 0.15, 0), "metal")
	_cyl(an, 0.04, 0.06, 3.4, Vector3(0, 2.0, 0), "ink")
	var b := _sphere(an, 0.12, Vector3(0, 3.8, 0), "glow_cyan", Vector3.ONE, false, 8)
	_blinkers.append({"node": b, "period": 1.6, "phase": 0.4})


## A smaller chunk off the rim at angle `a`, joined to it by a plated bridge with rails. Returns
## its centre and the outward direction; reserves the bridge mouth so the road and props keep off.
func _annex_platform(a: float, radius: float) -> Dictionary:
	var dir := Vector2(cos(a) * _rx, sin(a) * _rz).normalized()
	var rim_pt := Vector2(_centre.x + cos(a) * _rx, _centre.z + sin(a) * _rz)
	var c2 := rim_pt + dir * (radius + 3.0)
	var centre := Vector3(c2.x, _top, c2.y)
	_occupied.append(Vector3(rim_pt.x, rim_pt.y, 3.2))
	var slab := _cyl(self, radius, radius * 0.94, 2.6, centre + Vector3(0, -1.3, 0), "moon", Vector3.ZERO, 9)
	slab.rotation.y = a
	var root := _cyl(self, radius * 0.9, radius * 0.2, 8.0, centre + Vector3(0, -2.6 - 4.0, 0), "moon_dark", Vector3.ZERO, 9)
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
	# The bridge: a plated walkway from rim to rim with rails and lamps at both ends.
	var from := Vector3(rim_pt.x, _top + 0.1, rim_pt.y) - Vector3(dir.x, 0, dir.y) * 1.2
	var to := centre - Vector3(dir.x, 0, dir.y) * (radius - 1.0) + Vector3(0, 0.1, 0)
	var mid := (from + to) * 0.5
	var length := (to - from).length()
	var yaw := atan2(dir.x, dir.y)
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


func _habitat(at: Vector3, yaw: float) -> void:
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
	_label(h, "HAB 1", Vector3(2.72, 2.55, -0.3), 48, Palette.hud_colour("paper"), PI * 0.5)
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


# --- structures on the slab -------------------------------------------------------------------------

func _structures(craters: Array, landmarks: Array) -> void:
	# Single-row solar arrays on the slab, where they fit.
	for k in 2:
		var farm := _spot(3.4, 2.4, 0.15, 0.94, 500)
		if farm != Vector2.INF:
			_solar_array(Vector3(farm.x, _top, farm.y), _rng.randf_range(0.0, TAU), 1)
	# Cargo stacks on the slab.
	for k in 3:
		var sp := _spot(2.7, 1.6, 0.15, 0.92, 300)
		if sp == Vector2.INF:
			break
		_cargo(Vector3(sp.x, _top, sp.y), _rng.randf_range(0.0, TAU), 3 + _rng.randi() % 3)
	# Comms mast: a lattice tower with a small dish and a blinking light.
	var mast := _spot(2.8, 1.6, 0.2, 0.9, 300)
	if mast != Vector2.INF:
		var mn := _node(Vector3(mast.x, _top, mast.y))
		for i in 3:
			var a := i * TAU / 3.0
			_cyl(mn, 0.05, 0.07, 7.0, Vector3(cos(a) * 0.45, 3.5, sin(a) * 0.45), "ink", Vector3(sin(a) * 0.05, 0, -cos(a) * 0.05))
		for lvl in 5:
			_box(mn, Vector3(1.0, 0.06, 1.0), Vector3(0, 1.2 + lvl * 1.35, 0), "counter_dark")
		_cyl(mn, 0.06, 0.06, 1.6, Vector3(0, 7.7, 0), "ink")
		_cyl(mn, 0.75, 0.15, 0.3, Vector3(0.7, 4.5, 0), "paper", Vector3(0, 0, -1.1), 12)
		var b := _sphere(mn, 0.18, Vector3(0, 8.55, 0), "glow_red", Vector3.ONE, false, 8)
		_blinkers.append({"node": b, "period": 0.9, "phase": 0.3})
		_count("comms mast")
	# Antenna masts: short whips with a light, two of them.
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
	# Drill rig over the largest crater away from the tiles.
	var best: Vector3 = Vector3.INF
	for cr in craters:
		if cr.z >= 1.8 and _tile_clear(cr.x, cr.y, cr.z + 2.2) and (best == Vector3.INF or cr.z > best.z):
			best = cr
	if best != Vector3.INF:
		var rig := _node(Vector3(best.x, _top, best.y), _rng.randf_range(0.0, TAU))
		var s := best.z * 0.9
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
	# Oxygen tank pairs on a stand.
	for k in 2:
		var sp := _spot(2.0, 0.9, 0.15, 0.95, 200)
		if sp == Vector2.INF:
			break
		_oxygen(_node(Vector3(sp.x, _top, sp.y), _rng.randf_range(0.0, TAU)), k)
	# Landing lights around the pad (landmark 0): low, just outside its ring.
	if landmarks.size() > 0:
		var pad: Vector2 = landmarks[0]
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
	# The welcome sign beside the start, facing it.
	var placed_sign := false
	for s: float in [1.0, -1.0]:
		var at := Vector2(sp0.x, sp0.z) + side * s * 3.8
		if _tile_clear(at.x, at.y, 2.3) and _prop_clear(at.x, at.y, 1.8) and _inside(at.x, at.y, 0.98):
			_occupied.append(Vector3(at.x, at.y, 1.8))
			var yaw := atan2(-(at.x - sp0.x), -(at.y - sp0.z))
			var sn := _node(Vector3(at.x, _top, at.y), yaw)
			for px: float in [-1.5, 1.5]:
				_cyl(sn, 0.09, 0.11, 2.8, Vector3(px, 1.4, 0), "counter_dark")
			_box(sn, Vector3(3.6, 1.3, 0.12), Vector3(0, 2.9, 0), "paper")
			_box(sn, Vector3(3.66, 1.36, 0.1), Vector3(0, 2.9, -0.09), "counter_dark")   # its back
			_box(sn, Vector3(3.7, 0.16, 0.16), Vector3(0, 3.6, 0), "accent_lit")
			_box(sn, Vector3(3.7, 0.16, 0.16), Vector3(0, 2.2, 0), "accent_lit")
			_label(sn, "BOMBA BAY", Vector3(0, 3.05, 0.08), 96, Palette.map_colour("board", "line"), 0.0, 0)
			_label(sn, "WELCOME · MIND THE GAP", Vector3(0, 2.55, 0.08), 34, Palette.map_colour("board", "counter_dark"), 0.0, 0)
			var b := _sphere(sn, 0.12, Vector3(1.5, 2.95, 0), "glow_yellow", Vector3.ONE, false, 8)
			_blinkers.append({"node": b, "period": 0.6, "phase": 0.0})
			var b2 := _sphere(sn, 0.12, Vector3(-1.5, 2.95, 0), "glow_yellow", Vector3.ONE, false, 8)
			_blinkers.append({"node": b2, "period": 0.6, "phase": 0.3})
			_count("welcome sign")
			placed_sign = true
			break
	if not placed_sign:
		var alt := _spot_near(sp0.x, sp0.z, 3.5, 7.0, 2.3, 1.8, 300)
		if alt != Vector2.INF:
			var yaw := atan2(-(alt.x - sp0.x), -(alt.y - sp0.z))
			var sn := _node(Vector3(alt.x, _top, alt.y), yaw)
			for px: float in [-1.5, 1.5]:
				_cyl(sn, 0.09, 0.11, 2.8, Vector3(px, 1.4, 0), "counter_dark")
			_box(sn, Vector3(3.6, 1.3, 0.12), Vector3(0, 2.9, 0), "paper")
			_label(sn, "BOMBA BAY", Vector3(0, 3.05, 0.08), 96, Palette.map_colour("board", "line"), 0.0, 0)
			_count("welcome sign")
	# The start line: two posts beside the start tile and a sagging string of pennants over it,
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
		var pad: Vector2 = landmarks[0]
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
	for step in 90:
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
		_buggy = Node3D.new()
		add_child(_buggy)
		_box(_buggy, Vector3(2.2, 0.4, 1.3), Vector3(0, 0.75, 0), "metal")
		_box(_buggy, Vector3(0.8, 0.55, 1.0), Vector3(-0.45, 1.2, 0), "counter")
		_box(_buggy, Vector3(0.6, 0.06, 0.9), Vector3(0.55, 0.98, 0), "field_dark")
		_cyl(_buggy, 0.03, 0.03, 1.5, Vector3(0.8, 1.75, 0.45), "ink")
		var b := _sphere(_buggy, 0.1, Vector3(0.8, 2.55, 0.45), "glow_cyan", Vector3.ONE, false, 8)
		_blinkers.append({"node": b, "period": 1.0, "phase": 0.2})
		for wx: float in [-0.8, 0.8]:
			for wz: float in [-0.8, 0.8]:
				var wheel := _cyl(_buggy, 0.42, 0.42, 0.3, Vector3(wx, 0.42, wz), "ink", Vector3(PI * 0.5, 0, 0), 10)
				_buggy_wheels.append(wheel)
				_cyl(_buggy, 0.2, 0.2, 0.32, Vector3(wx, 0.42, wz), "metal", Vector3(PI * 0.5, 0, 0), 8)
		_buggy.position = _buggy_road[0]
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
	if _star_next <= 0.0 and _star_t >= 99.0:
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
