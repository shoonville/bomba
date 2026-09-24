extends SceneTree
## Generates board/boards/main.json (BOMBA BAY) from Sean's drawing (2026-09-24, the second
## board of the day: "I drew where I want the board spaces to be in blue... in black I did an
## arrow pointing to how I want the direction to be. when there's a fork in the road I did two
## arrows... a magenta circle... that's where I want the start to be. the yellow things are the
## spawn points... a rocket and a red circle next to the rocket and a dotted line leading to
## another red circle"). The blue lines are traced here as polylines in the drawing's own pixels
## (a 1500 × 1000 image, 0.115 m per pixel, north up), sampled every 3.7 m, and every junction
## is a shared space. The streets and their one-way directions, from the arrows:
##   TOP: from the start east along the top and down the right side into the rectangle's top edge;
##   START DOWN: from the start south into the westward MID street (a fork at the start);
##   MID: from the F3 junction north up the middle, then west to the F2 fork;
##   F2 LOOP: south-west past the rocket's landing spot and round the big left loop up to M1;
##   F2 CURVE: the short inner curve up to M1 (the fork at F2: loop or curve);
##   M1 to F4, then the LENS: two arcs from F4 to the start (a fork at F4);
##   the RECTANGLE: from F3 south past the rocket pad, east, north and west back to F3 (the fork
##   at F3: up the middle or round the rectangle; the right column merges into its top edge).
## The rocket ("shuttle"): landing on or passing the pad space offers a flight to the landing
## spot on the far side for `price` tickets (board_rules.gd). The yellow domes are the annexes
## (the respawn points, the vending machine's two spots), written as rim angles. The slab is
## the rounded hull of the spaces with a margin (`MoonSlab.from_hull`); the blocks between the
## streets and a few spots in the margin are "zones" the dressing fills. No event spaces (Sean:
## "remove the spot that randomly teleports you"). Deterministic (seed 11). Then run
## tools/mark_spots.gd to flag the machine spots.
##   GODOT --headless --path . --script tools/gen_board.gd -- [out]

const SPACING := 3.7
const MAX_HOP := 5.6
const MIN_PAIR := 3.0
const SCALE := 0.115          # metres per drawing pixel
const ORIGIN := Vector2(701.0, 561.0)   # the drawing pixel that becomes (0, 0)
const MARGIN := 9.0           # the slab past the hull of the spaces
const SHUTTLE_PRICE := 10

# Junctions, in drawing pixels (x right, y down = south).
const START := Vector2(840, 310)
const F4 := Vector2(612, 332)
const M1 := Vector2(490, 392)
const F2 := Vector2(606, 496)
const M2 := Vector2(832, 420)
const RED_L := Vector2(515, 665)   # the rocket's landing spot
const F3 := Vector2(862, 682)
const M3 := Vector2(1130, 666)
const PAD := Vector2(862, 830)     # the rocket pad
const BR := Vector2(1200, 828)
const TR := Vector2(1222, 692)
const SHIELD_AT := Vector2(280, 806)   # the safe spot: the bottom of the big loop, opposite the start
const ANNEX_L := Vector2(375, 335)     # the yellow domes
const ANNEX_R := Vector2(1300, 740)

var _rng := RandomNumberGenerator.new()
var _nodes: Array = []
var _by_id: Dictionary = {}
var _index: Dictionary = {}
var _count: Dictionary = {}
var _start_id := ""
var _slab: MoonSlab


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "res://board/boards/main.json"
	_rng.seed = 11
	_build_streets()
	_assign_types()
	var pts: Array = []
	for nd in _nodes:
		pts.append(nd["p"])
	_slab = MoonSlab.from_hull(pts, MARGIN)
	var problems := _check()
	for p in problems:
		printerr(p)
	if not problems.is_empty():
		quit(2)
		return
	var spaces: Array = []
	for nd in _nodes:
		var p: Vector2 = nd["p"]
		spaces.append({"id": nd["id"], "position": [snappedf(p.x, 0.01), snappedf(_elev(p), 0.01), snappedf(p.y, 0.01)],
			"type": nd["type"], "next": nd["next"], "goal": false})
	var board := {"id": "main", "display_name": "BOMBA BAY", "start": _start_id,
		"slab": _slab.to_dict(),
		"annexes": [snappedf(_angle(ANNEX_L), 0.0001), snappedf(_angle(ANNEX_R), 0.0001)],
		"shuttle": {"from": _index[_key(_m(PAD))], "to": _index[_key(_m(RED_L))], "price": SHUTTLE_PRICE},
		"zones": _zones(), "spaces": spaces}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(board, "  ") + "\n")
	f.close()
	_report()
	print("wrote %s" % out_path)
	quit(0)


## Drawing pixels to metres.
func _m(px: Vector2) -> Vector2:
	return (px - ORIGIN) * SCALE


func _angle(px: Vector2) -> float:
	var p := _m(px)
	return atan2(p.y - _slab_centre().y, p.x - _slab_centre().x)


func _slab_centre() -> Vector2:
	return Vector2(_slab.centre.x, _slab.centre.z) if _slab != null else Vector2.ZERO


# --- the streets, traced from the drawing ----------------------------------------------------------

func _build_streets() -> void:
	# The start first, so the first space is S0 and the lens arcs end on it.
	_node_at(_m(START), "S", "main")
	_start_id = _index[_key(_m(START))]
	# TOP: east along the top, down the right column, into the rectangle's top edge at M3.
	_poly([START, Vector2(900, 292), Vector2(1000, 283), Vector2(1060, 290), Vector2(1100, 312), Vector2(1113, 345),
		Vector2(1118, 450), Vector2(1124, 560), M3], "T", "main")
	# START DOWN: south from the start into MID at M2.
	_poly([START, Vector2(846, 350), Vector2(840, 392), M2], "D", "main")
	# MID: from F3 north up the middle, then west through M2 to F2.
	_poly([F3, Vector2(860, 640), Vector2(868, 600), Vector2(885, 578), Vector2(915, 566), Vector2(940, 545),
		Vector2(951, 505), Vector2(950, 462), Vector2(940, 432), Vector2(900, 426), M2], "M", "main")
	_poly([M2, Vector2(760, 424), Vector2(700, 432), Vector2(660, 454), Vector2(630, 478), F2], "M", "main")
	# F2 LOOP: south-west past the rocket's landing spot, round the big loop, up to M1.
	_poly([F2, Vector2(582, 538), Vector2(552, 598), RED_L], "L", "main")
	_poly([RED_L, Vector2(470, 705), Vector2(400, 760), Vector2(330, 800), SHIELD_AT, Vector2(215, 786), Vector2(185, 740),
		Vector2(180, 690), Vector2(200, 620), Vector2(250, 560), Vector2(330, 490), Vector2(420, 430), M1], "L", "main")
	# F2 CURVE: the inner curve up to M1 (item-rich, the short way).
	_poly([F2, Vector2(572, 480), Vector2(532, 452), Vector2(506, 422), M1], "C", "rich")
	# M1 to F4.
	_poly([M1, Vector2(540, 360), Vector2(590, 340), F4], "K", "main")
	# The LENS: two arcs from F4 to the start.
	_poly([F4, Vector2(660, 308), Vector2(720, 296), Vector2(790, 298), START], "A", "rich")
	_poly([F4, Vector2(640, 356), Vector2(700, 362), Vector2(770, 350), Vector2(820, 326), START], "B", "branch")
	# The RECTANGLE: south from F3 to the pad, east along the bottom, north, then west along the
	# top edge through M3 back to F3.
	_poly([F3, Vector2(860, 760), PAD], "P", "branch")
	_poly([PAD, Vector2(950, 838), Vector2(1050, 840), Vector2(1150, 834), BR, Vector2(1218, 780), Vector2(1222, 730), TR], "P", "branch")
	_poly([TR, Vector2(1180, 676), M3], "P", "branch")
	_poly([M3, Vector2(1050, 672), Vector2(960, 677), F3], "P", "branch")


## A polyline in drawing pixels: spaces every ~SPACING along it, both ends exact.
func _poly(px: Array, street: String, kind: String) -> void:
	var pts: Array = []
	for p in px:
		pts.append(_m(p))
	_arc(pts, street, kind)


func _arc(pts: Array, street: String, kind: String) -> void:
	var length := 0.0
	for i in range(1, pts.size()):
		length += (pts[i] as Vector2).distance_to(pts[i - 1])
	var n := maxi(1, roundi(length / SPACING))
	var step := length / n
	var prev := _node_at(pts[0], street, kind)
	var acc := 0.0
	var want := step
	var made := 1
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var seg := a.distance_to(b)
		while made < n and acc + seg >= want - 1e-6:
			var q := a.lerp(b, (want - acc) / seg)
			var id := _node_at(q, street, kind)
			_link(prev, id)
			prev = id
			made += 1
			want += step
		acc += seg
	_link(prev, _node_at(pts[-1], street, kind))


func _key(p: Vector2) -> String:
	return "%.1f|%.1f" % [p.x, p.y]


func _node_at(p: Vector2, street: String, kind: String) -> String:
	var key := _key(p)
	if _index.has(key):
		return _index[key]
	var c := int(_count.get(street, 0))
	_count[street] = c + 1
	var id := "%s%d" % [street, c]
	_index[key] = id
	_by_id[id] = _nodes.size()
	_nodes.append({"id": id, "p": p, "next": [], "kind": kind, "type": "blank"})
	return id


func _link(a: String, b: String) -> void:
	if a == b:
		return
	var nxt: Array = _nodes[_by_id[a]]["next"]
	if not nxt.has(b):
		nxt.append(b)


func _node(id: String) -> Dictionary:
	return _nodes[_by_id[id]]


func _pos(id: String) -> Vector2:
	return _node(id)["p"]


func _nearest(px: Vector2) -> String:
	var target := _m(px)
	var best := ""
	var best_d := 1e9
	for nd in _nodes:
		var d := (nd["p"] as Vector2).distance_to(target)
		if d < best_d:
			best_d = d
			best = nd["id"]
	return best


# --- types and heights --------------------------------------------------------------------------------

func _assign_types() -> void:
	for nd in _nodes:
		nd["type"] = _pick_type(str(nd["kind"]))
	var start := _node(_start_id)
	start["type"] = "start"
	# No damage on the first two spaces out of the start, either way.
	for first in start["next"]:
		var s2: String = _node(first)["next"][0]
		for id in [first, s2]:
			if _node(id)["type"] == "lose":
				_node(id)["type"] = "ticket"
	# The one safe spot, at the bottom of the big loop.
	_node(_nearest(SHIELD_AT))["type"] = "shield"
	# The rocket pad and its landing spot are plain spaces (the flight is the effect).
	_node(_index[_key(_m(PAD))])["type"] = "blank"
	_node(_index[_key(_m(RED_L))])["type"] = "blank"
	# Blanks near each annex so the machine spots have candidates (tools/mark_spots.gd wants
	# a blank, non-junction space with a clear corridor out to the rim).
	for dome in [ANNEX_L, ANNEX_R]:
		var near: Array = []
		for nd in _nodes:
			near.append([(nd["p"] as Vector2).distance_to(_m(dome)), nd["id"]])
		near.sort_custom(func(a, b): return a[0] < b[0])
		for k in 4:
			var nd := _node(near[k][1])
			if str(nd["type"]) != "start" and str(nd["type"]) != "shield":
				nd["type"] = "blank"


func _pick_type(kind: String) -> String:
	var r := _rng.randf()
	match kind:
		"rich":
			return "item" if r < 0.45 else ("ticket" if r < 0.8 else "blank")
		"branch":
			return "lose" if r < 0.28 else ("ticket" if r < 0.6 else ("item" if r < 0.8 else "blank"))
	if r < 0.44:
		return "ticket"
	if r < 0.7:
		return "blank"
	if r < 0.84:
		return "item"
	return "lose"


## Gentle ground swell in 0.15 m steps, 0 to 0.9 m, so the streets rise and dip.
func _elev(p: Vector2) -> float:
	return snappedf(0.45 * (1.0 + sin(p.x / 19.0 + 0.8) * cos(p.y / 15.0 + 0.3)), 0.15)


# --- the blocks and the margin spots: what the dressing builds -------------------------------------

func _zone(kind: String, px: Vector2, r: float, yaw: float) -> Dictionary:
	var p := _m(px)
	return {"kind": kind, "centre": [snappedf(p.x, 0.01), snappedf(p.y, 0.01)], "r": r, "yaw": snappedf(yaw, 0.01)}


func _margin_zone(kind: String, deg: float, f: float, r: float, yaw: float) -> Dictionary:
	var p := _slab.point(deg_to_rad(deg), f)
	return {"kind": kind, "centre": [snappedf(p.x, 0.01), snappedf(p.y, 0.01)], "r": r, "yaw": snappedf(yaw, 0.01)}


## One set-piece per open space (a disc the walkways keep clear of: centre, radius, a yaw), and a
## few cute things out in the margin between the streets and the rim.
func _zones() -> Array:
	var start_m := _m(START)
	var plaza := Vector2(start_m.x, start_m.y - 7.6)
	return [
		_zone("hab", Vector2(330, 640), 8.0, 0.4),          # inside the big loop: HAB 2, the comms tower
		_zone("farm", Vector2(690, 555), 8.0, -0.2),        # the bay: greenhouses in rows
		_zone("park", Vector2(640, 700), 6.0, 0.6),         # the bay's crater with the rig
		_zone("rocket", Vector2(768, 768), 4.6, 0.0),       # the rocket on its pad, by the pad space
		_zone("pad", Vector2(1000, 400), 6.0, 0.3),         # inside the top loop: the rover's pad and lights
		_zone("depot", Vector2(1040, 585), 7.0, 0.2),       # ... and the hangar, cargo, the crane
		_zone("power", Vector2(1040, 758), 6.5, 0.0),       # inside the rectangle: the reactor, solar
		_zone("solar", Vector2(690, 396), 2.4, 0.15),       # the sliver under the lens: a solar row
		{"kind": "plaza", "centre": [snappedf(plaza.x, 0.01), snappedf(plaza.y, 0.01)], "r": 1.6, "yaw": 0.0},
		_margin_zone("lander", -28.0, 0.93, 2.4, 0.5),      # north-east margin: the lander
		_margin_zone("ufo", 138.0, 0.93, 3.0, 0.0),         # south-west margin: a parked saucer and its pilot
		_margin_zone("balloon", -112.0, 0.93, 1.6, 0.0),    # north margin: the tethered balloon
	]


# --- checks and the report ---------------------------------------------------------------------------

func _check() -> PackedStringArray:
	var out := PackedStringArray()
	for nd in _nodes:
		var nxt: Array = nd["next"]
		if nxt.is_empty():
			out.append("%s has no way on" % nd["id"])
		if nxt.size() > 2:
			out.append("%s has %d ways on (a fork offers two)" % [nd["id"], nxt.size()])
	var fwd := _reach(_start_id, false)
	var back := _reach(_start_id, true)
	for nd in _nodes:
		if not fwd.has(nd["id"]):
			out.append("%s is unreachable from the start" % nd["id"])
		if not back.has(nd["id"]):
			out.append("%s never gets back to the start" % nd["id"])
	var min_pair := 1e9
	var worst := ""
	for a in _nodes.size():
		for b in range(a + 1, _nodes.size()):
			var d := (_nodes[a]["p"] as Vector2).distance_to(_nodes[b]["p"])
			if d < min_pair:
				min_pair = d
				worst = "%s-%s" % [_nodes[a]["id"], _nodes[b]["id"]]
	var max_hop := 0.0
	for nd in _nodes:
		for n in nd["next"]:
			max_hop = maxf(max_hop, (nd["p"] as Vector2).distance_to(_pos(n)))
	if min_pair < MIN_PAIR:
		out.append("spaces %s only %.2f m apart" % [worst, min_pair])
	if max_hop > MAX_HOP:
		out.append("a hop of %.2f m" % max_hop)
	for z in _zones():
		var c: Array = z["centre"]
		var r := float(z["r"])
		for nd in _nodes:
			var d := (nd["p"] as Vector2).distance_to(Vector2(float(c[0]), float(c[1])))
			if d < r + 1.6:
				out.append("zone %s (r %.1f) is %.1f m from space %s" % [z["kind"], r, d, nd["id"]])
				break
		if not _slab.inside(float(c[0]), float(c[1]), 0.97):
			out.append("zone %s is off the slab" % z["kind"])
	return out


func _reach(from: String, backwards: bool) -> Dictionary:
	var prev := {}
	if backwards:
		for nd in _nodes:
			for n in nd["next"]:
				if not prev.has(n):
					prev[n] = []
				(prev[n] as Array).append(nd["id"])
	var seen := {from: true}
	var queue := [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		var edges: Array = prev.get(cur, []) if backwards else _node(cur)["next"]
		for n in edges:
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


func _report() -> void:
	var counts := {}
	var forks := []
	for nd in _nodes:
		counts[nd["type"]] = int(counts.get(nd["type"], 0)) + 1
		if (nd["next"] as Array).size() > 1:
			forks.append(nd["id"])
	var min_pair := 1e9
	for a in _nodes.size():
		for b in range(a + 1, _nodes.size()):
			min_pair = minf(min_pair, (_nodes[a]["p"] as Vector2).distance_to(_nodes[b]["p"]))
	var max_hop := 0.0
	for nd in _nodes:
		for n in nd["next"]:
			max_hop = maxf(max_hop, (nd["p"] as Vector2).distance_to(_pos(n)))
	print("spaces %d by street %s, forks %d %s" % [_nodes.size(), str(_count), forks.size(), str(forks)])
	print("min pair %.2f m, hop max %.2f m, types %s" % [min_pair, max_hop, str(counts)])
	print("slab centre (%.1f, %.1f), extent ±%.1f × ±%.1f m; shuttle %s → %s; annexes at %d° and %d°" % [
		_slab.centre.x, _slab.centre.z, _slab.rx, _slab.rz, _index[_key(_m(PAD))], _index[_key(_m(RED_L))],
		roundi(rad_to_deg(_angle(ANNEX_L))), roundi(rad_to_deg(_angle(ANNEX_R)))])
	var laps: Array = []
	_walk(_start_id, 0, {}, laps)
	laps.sort()
	var mean := 0.0
	for l in laps:
		mean += float(l)
	mean /= maxf(1.0, laps.size())
	print("laps from the start back to it: %d routes, %d–%d steps, mean %.1f (%.1f–%.1f turns of the d8, mean %.1f)" % [
		laps.size(), laps[0], laps[-1], mean, laps[0] / 4.5, laps[-1] / 4.5, mean / 4.5])


func _walk(at: String, depth: int, seen: Dictionary, laps: Array) -> void:
	for n in _node(at)["next"]:
		if n == _start_id:
			laps.append(depth + 1)
		elif not seen.has(n):
			seen[n] = true
			_walk(n, depth + 1, seen, laps)
			seen.erase(n)
