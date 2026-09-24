extends SceneTree
## Generates board/boards/main.json (BOMBA BAY). Sean (2026-09-24, with an overhead shot of a
## street-grid party board): "make the layout like this... right now it's just a big circle and
## doesn't feel as engaging... you can put decorative stuff about the map in the open spaces where
## there's no place to land on... make the entire map cohesive". The board is a district now:
## one-way walkways laid out like streets round blocks, the blocks holding the base's set-pieces
## (board_dressing.gd builds them from the "zones" written here):
##   the RING ROAD, a rounded plot round everything (a superellipse, clockwise seen from the
##     north: east along the north edge), about 86 spaces so a lap of it is still Sean's 20
##     turns of the d8 (2026-09-23);
##   MAIN STREET across the middle (eastbound) and two AVENUES (the west one southbound, the
##     east one northbound), so every junction offers "straight on or turn" and the six blocks
##     between them (HAB 2, the LANDING PAD and the DEPOT, the FARM, the TANK FARM, the CRATER
##     PARK, the POWER PLANT) have a walkway on every side;
##   the PAD APRON, a rectangular detour off the north edge round the landing pad, and the
##     BOARDWALK, a curve off the south edge round the big crater (item-rich, like the loop
##     board's outside detour).
## Every street is one-way; a fork is a junction with two ways on (never three), and every
## space reaches every other (checked, so the machine and the start are always reachable).
## 3.7 m between spaces, the tile mix, 0.15 m elevation steps and the one safe spot opposite
## the start are the loop board's. Deterministic (seed 11). The machine spots are flagged
## afterwards by tools/mark_spots.gd: the two annexes stand off the east and west rims, the two
## ends of main street ("annexes", the rim angles; the file's "slab" is the rounded plot the view
## builds, so the tool and the view agree).
##   GODOT --headless --path . --script tools/gen_board.gd -- [out]

const SPACING := 3.7          # metres between spaces along a street
const MAX_HOP := 5.6
const MIN_PAIR := 3.0
const A := 54.0               # the ring road's half-width (x)
const B := 43.0               # and half-depth (z)
const N := 3.2                # the superellipse exponent: 2 is an ellipse, higher is squarer
const AVE := 22.0             # the avenues run at x = ±AVE
const APRON_X := 14.0         # the pad apron's legs at x = ±APRON_X, its bottom at z = APRON_Z
const APRON_Z := -26.0
const WALK_X := 13.0          # the boardwalk leaves and rejoins the south edge at x = ±WALK_X
const WALK_C := B - 4.0       # ... on a circle centred (0, WALK_C) of radius WALK_R
const WALK_R := 13.5
const MARGIN_X := 10.0        # the slab past the ring road, sides
const MARGIN_Z := 7.0         # ... and top / bottom (the annexes go where the margin is widest)
const START_X := 30.0         # the start on the south edge (the ring leaves it westward)
const SHIELD_X := -30.0       # the one safe spot on the north edge, opposite

var _rng := RandomNumberGenerator.new()
var _nodes: Array = []        # {id, p: Vector2, next: [ids], kind, type}
var _by_id: Dictionary = {}   # id → index in _nodes
var _index: Dictionary = {}   # position key → id (junctions are shared by position)
var _count: Dictionary = {}   # street letter → spaces made
var _start_id := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "res://board/boards/main.json"
	_rng.seed = 11
	_build_ring()
	_build_streets()
	_assign_types()
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
	var slab := MoonSlab.new()
	slab.rx = A + MARGIN_X
	slab.rz = B + MARGIN_Z
	slab.n = N
	var board := {"id": "main", "display_name": "BOMBA BAY", "start": _start_id,
		"slab": slab.to_dict(), "annexes": [0.0, snappedf(PI, 0.0001)], "zones": _zones(), "spaces": spaces}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(board, "  ") + "\n")
	f.close()
	_report()
	print("wrote %s" % out_path)
	quit(0)


# --- the ring road -------------------------------------------------------------------------------------

## The superellipse's parametric point; t runs clockwise seen from the north (east at 0, the
## south edge at a quarter turn).
func _ring_pt(t: float) -> Vector2:
	var c := cos(t)
	var s := sin(t)
	return Vector2(A * signf(c) * pow(absf(c), 2.0 / N), B * signf(s) * pow(absf(s), 2.0 / N))


## The north edge's z at x, and the south edge's.
func _zn(x: float) -> float:
	return -B * pow(1.0 - pow(absf(x) / A, N), 1.0 / N)


func _zs(x: float) -> float:
	return -_zn(x)


func _build_ring() -> void:
	var start := Vector2(START_X, _zs(START_X))
	var junctions: Array = [start,
		Vector2(A, 0.0), Vector2(-A, 0.0),
		Vector2(-AVE, _zn(-AVE)), Vector2(AVE, _zn(AVE)), Vector2(-AVE, _zs(-AVE)), Vector2(AVE, _zs(AVE)),
		Vector2(-APRON_X, _zn(-APRON_X)), Vector2(APRON_X, _zn(APRON_X)),
		Vector2(WALK_X, _zs(WALK_X)), Vector2(-WALK_X, _zs(-WALK_X)),
		Vector2(SHIELD_X, _zn(SHIELD_X))]
	# A dense outline with the junctions dropped in at their exact spots, then one arc per
	# stretch between junctions, clockwise from the start, so the ring's ids count round from it.
	var dense: Array = []
	var m := 3600
	for i in m:
		dense.append(_ring_pt(TAU * i / m))
	var jidx: Array = []
	for j in junctions:
		var best := 0
		for i in m:
			if (dense[i] as Vector2).distance_to(j) < (dense[best] as Vector2).distance_to(j):
				best = i
		dense[best] = j
		jidx.append(best)
	var t0: int = jidx[0]
	var order := jidx.duplicate()
	order.sort_custom(func(a, b): return (a - t0 + m) % m < (b - t0 + m) % m)
	for k in order.size():
		var i0: int = order[k]
		var i1: int = order[(k + 1) % order.size()]
		var pts: Array = []
		var i := i0
		while true:
			pts.append(dense[i])
			if i == i1:
				break
			i = (i + 1) % m
		_arc(pts, "R", "ring")
	_start_id = _index[_key(start)]


# --- the streets -----------------------------------------------------------------------------------------

func _build_streets() -> void:
	# Main street, eastbound: it leaves the west edge (a fork there) and joins the east edge.
	_leg(Vector2(-A, 0.0), Vector2(-AVE, 0.0), "M", "main")
	_leg(Vector2(-AVE, 0.0), Vector2(AVE, 0.0), "M", "main")
	_leg(Vector2(AVE, 0.0), Vector2(A, 0.0), "M", "main")
	# The west avenue southbound, the east avenue northbound: with the ring clockwise every
	# junction is a "straight on or turn", and the four small loops round the middle blocks
	# all run clockwise too.
	_leg(Vector2(-AVE, _zn(-AVE)), Vector2(-AVE, 0.0), "W", "avenue")
	_leg(Vector2(-AVE, 0.0), Vector2(-AVE, _zs(-AVE)), "W", "avenue")
	_leg(Vector2(AVE, _zs(AVE)), Vector2(AVE, 0.0), "E", "avenue")
	_leg(Vector2(AVE, 0.0), Vector2(AVE, _zn(AVE)), "E", "avenue")
	# The pad apron: a rectangular detour south of the north edge round the landing pad.
	_leg(Vector2(-APRON_X, _zn(-APRON_X)), Vector2(-APRON_X, APRON_Z), "P", "apron")
	_leg(Vector2(-APRON_X, APRON_Z), Vector2(APRON_X, APRON_Z), "P", "apron")
	_leg(Vector2(APRON_X, APRON_Z), Vector2(APRON_X, _zn(APRON_X)), "P", "apron")
	# The boardwalk: an arc north of the south edge round the big crater, east end to west end
	# (the south edge runs west).
	var pts: Array = []
	var a0 := atan2(_zs(WALK_X) - WALK_C, WALK_X)
	var a1 := PI - a0 - TAU
	var steps := 400
	for i in steps + 1:
		var t := lerpf(a0, a1, float(i) / steps)
		pts.append(Vector2(WALK_R * cos(t), WALK_C + WALK_R * sin(t)))
	pts[0] = Vector2(WALK_X, _zs(WALK_X))
	pts[-1] = Vector2(-WALK_X, _zs(-WALK_X))
	_arc(pts, "B", "walk")


func _leg(a: Vector2, b: Vector2, street: String, kind: String) -> void:
	_arc([a, b], street, kind)


## Spaces every ~SPACING along a polyline, its two ends exact (shared with whatever else ends
## there), linked in order.
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


# --- types and heights --------------------------------------------------------------------------------

func _assign_types() -> void:
	for nd in _nodes:
		nd["type"] = _pick_type(str(nd["kind"]))
	var start := _node(_start_id)
	start["type"] = "start"
	# No damage on the first two spaces out of the start.
	var s1: String = start["next"][0]
	var s2: String = _node(s1)["next"][0]
	for id in [s1, s2]:
		if _node(id)["type"] == "lose":
			_node(id)["type"] = "coin"
	# The safe spot: the ring space at the far side.
	_node(_index[_key(Vector2(SHIELD_X, _zn(SHIELD_X)))])["type"] = "shield"
	# The ring spaces either side of the two main-street junctions stay blank: the machine spots
	# (tools/mark_spots.gd wants a blank space with a clear corridor out to the rim, and the
	# annexes stand off the middle of the west and east rims).
	for jx in [-A, A]:
		for nd in _nodes:
			if str(nd["kind"]) == "ring" and (nd["p"] as Vector2).distance_to(Vector2(jx, 0.0)) < SPACING * 1.4 \
					and (nd["p"] as Vector2).distance_to(Vector2(jx, 0.0)) > 0.1:
				nd["type"] = "blank"


func _pick_type(kind: String) -> String:
	var r := _rng.randf()
	match kind:
		"walk":   # the item-rich detour
			return "item" if r < 0.5 else ("coin" if r < 0.8 else "event")
		"avenue", "apron":
			return "lose" if r < 0.28 else ("coin" if r < 0.6 else ("item" if r < 0.8 else "blank"))
	if r < 0.40:
		return "coin"
	if r < 0.64:
		return "blank"
	if r < 0.76:
		return "item"
	if r < 0.88:
		return "lose"
	return "event"


## Gentle ground swell across the district in 0.15 m steps, 0 to 0.9 m, so the streets rise and
## dip (the loop board had two waves round its loop).
func _elev(p: Vector2) -> float:
	return snappedf(0.45 * (1.0 + sin(p.x / 19.0 + 0.8) * cos(p.y / 15.0 + 0.3)), 0.15)


# --- the blocks: what the dressing builds in the open spaces --------------------------------------

func _zone(kind: String, x: float, z: float, r: float, yaw: float) -> Dictionary:
	return {"kind": kind, "centre": [snappedf(x, 0.01), snappedf(z, 0.01)], "r": r, "yaw": snappedf(yaw, 0.01)}


## One set-piece per block, as a disc the walkways keep clear of (centre, radius, a yaw): the
## dressing places the block's structures inside it and the random ground fillers outside.
func _zones() -> Array:
	var z_start := _zs(START_X)
	var rim_z := (B + MARGIN_Z) * pow(1.0 - pow(START_X / (A + MARGIN_X), N), 1.0 / N)
	return [
		_zone("hab", -35.0, -16.0, 8.0, 0.35),                       # HAB 2: domes, the comms mast
		_zone("pad", 0.0, (APRON_Z + _zn(0.0)) * 0.5, 4.5, 0.0),      # the landing pad inside the apron
		_zone("depot", 0.0, (APRON_Z + 0.0) * 0.5, 8.0, 0.2),         # hangar, cargo, the crane
		_zone("farm", 35.0, -16.0, 8.0, 0.0),                        # greenhouses in rows, the water tank
		_zone("tanks", -35.0, 16.0, 8.0, -0.4),                      # the tank farm
		_zone("park", 0.0, 12.0, 7.0, 0.0),                          # the upper lawn: the probe, rocks
		_zone("crater", 0.0, (WALK_C - WALK_R + z_start) * 0.5 + 0.8, 4.0, 0.6),   # the big crater, the rig
		_zone("power", 35.0, 16.0, 8.0, 0.15),                       # solar field, the reactor, the dish
		_zone("plaza", START_X, (z_start + rim_z) * 0.5 + 0.3, 1.6, 0.0),   # the crew by the flag, off the start
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
	# Strongly connected: everything from the start, the start from everything.
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
	var kinds := {}
	var forks := []
	for nd in _nodes:
		counts[nd["type"]] = int(counts.get(nd["type"], 0)) + 1
		kinds[nd["kind"]] = int(kinds.get(nd["kind"], 0)) + 1
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
	print("spaces %d by street %s, forks %d %s" % [_nodes.size(), str(kinds), forks.size(), str(forks)])
	print("min pair %.2f m, hop max %.2f m, types %s" % [min_pair, max_hop, str(counts)])
	# Laps: every simple route from the start back to the start, in steps.
	var laps: Array = []
	_walk(_start_id, 0, {}, laps)
	laps.sort()
	var mean := 0.0
	for l in laps:
		mean += float(l)
	mean /= maxf(1.0, laps.size())
	print("laps from the start back to it: %d routes, %d–%d steps, mean %.1f (%.1f–%.1f turns of the d8, mean %.1f); the ring road %d" % [
		laps.size(), laps[0], laps[-1], mean, laps[0] / 4.5, laps[-1] / 4.5, mean / 4.5, int(_count.get("R", 0))])


func _walk(at: String, depth: int, seen: Dictionary, laps: Array) -> void:
	for n in _node(at)["next"]:
		if n == _start_id:
			laps.append(depth + 1)
		elif not seen.has(n):
			seen[n] = true
			_walk(n, depth + 1, seen, laps)
			seen.erase(n)
