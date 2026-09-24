class_name BoardGraph
extends RefCounted
## A board as data (BOARDPLAN.md §3): spaces with positions, types and forward links. Loaded
## from board/boards/<id>.json. Pure: pathing and goal placement are plain functions.


class Space:
	var id: String = ""
	var position: Vector3 = Vector3.ZERO
	var type: String = "blank"
	var next: PackedStringArray = []
	var goal: bool = false


var id: String = ""
var display_name: String = ""
var start_id: String = ""
var spaces: Dictionary = {}
var slab: MoonSlab = null      # the moon chunk the board stands on (board files since 2026-09-24)
var zones: Array = []          # the blocks between the streets: {kind, centre [x, z], r, yaw}, for the look
var annex_angles: Array = []   # where the two annexes stand off the rim, when the board says
var shuttle_from := ""         # the rocket pad, when the board has a rocket (2026-09-24, Sean's drawing)
var shuttle_to := ""           # ... and the spot it lands on
var shuttle_price := 10        # the fare, in tickets
var _prev: Dictionary = {}


## Every board shipped in board/boards/, by id (file name), sorted.
static func available_ids() -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://board/boards")
	if dir == null:
		return ["first"]
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


static func load_file(path: String) -> BoardGraph:
	var d := TuningLoader.load_file(path)
	if d.is_empty():
		return null
	return from_dict(d)


static func from_dict(d: Dictionary) -> BoardGraph:
	var g := BoardGraph.new()
	g.id = str(d.get("id", "board"))
	g.display_name = str(d.get("display_name", g.id.to_upper()))
	g.start_id = str(d.get("start", "0"))
	g.slab = MoonSlab.from_dict(d.get("slab", {}))
	for zd in d.get("zones", []):
		g.zones.append(zd)
	for a in d.get("annexes", []):
		g.annex_angles.append(float(a))
	var sh: Dictionary = d.get("shuttle", {})
	g.shuttle_from = str(sh.get("from", ""))
	g.shuttle_to = str(sh.get("to", ""))
	g.shuttle_price = int(sh.get("price", 10))
	for sd in d.get("spaces", []):
		var s := Space.new()
		s.id = str(sd.get("id", ""))
		var p: Array = sd.get("position", [0, 0, 0])
		s.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		s.type = str(sd.get("type", "blank"))
		for n in sd.get("next", []):
			s.next.append(str(n))
		s.goal = bool(sd.get("goal", false))
		g.spaces[s.id] = s
	for sid in g.spaces:
		for n in (g.spaces[sid] as Space).next:
			if not g._prev.has(n):
				g._prev[n] = PackedStringArray()
			g._prev[n].append(sid)
	return g


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not spaces.has(start_id):
		errors.append("start space '%s' missing" % start_id)
	for sid in spaces:
		var s: Space = spaces[sid]
		if s.next.is_empty():
			errors.append("space '%s' has no next" % sid)
		for n in s.next:
			if not spaces.has(n):
				errors.append("space '%s' links to missing '%s'" % [sid, n])
	if goal_candidates().is_empty():
		errors.append("no goal candidates")
	if shuttle_from != "" and not (spaces.has(shuttle_from) and spaces.has(shuttle_to)):
		errors.append("the rocket runs from '%s' to '%s', and one is missing" % [shuttle_from, shuttle_to])
	return errors


func ids() -> Array:
	var out := spaces.keys()
	out.sort_custom(func(a, b): return int(a) < int(b) if a.is_valid_int() and b.is_valid_int() else a < b)
	return out


func get_space(space_id: String) -> Space:
	return spaces.get(space_id, null)


func next_of(space_id: String) -> PackedStringArray:
	var s := get_space(space_id)
	return s.next if s != null else PackedStringArray()


func prev_of(space_id: String) -> PackedStringArray:
	return _prev.get(space_id, PackedStringArray())


func is_fork(space_id: String) -> bool:
	return next_of(space_id).size() > 1


func goal_candidates() -> PackedStringArray:
	var out := PackedStringArray()
	for sid in ids():
		if (spaces[sid] as Space).goal:
			out.append(sid)
	return out


## Hops along forward links, or -1 if unreachable.
func distance(from: String, to: String) -> int:
	if from == to:
		return 0
	var dist := {from: 0}
	var queue := [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for n in next_of(cur):
			if not dist.has(n):
				dist[n] = int(dist[cur]) + 1
				if n == to:
					return int(dist[n])
				queue.append(n)
	return -1


## Walk n spaces backwards along the first predecessor (knockback). Returns the path walked.
func step_back(space_id: String, n: int) -> PackedStringArray:
	var path := PackedStringArray()
	var cur := space_id
	for i in n:
		var p := prev_of(cur)
		if p.is_empty():
			break
		cur = p[0]
		path.append(cur)
	return path


## Where the vending machine goes next: the candidate (a space flagged "goal" in the board file)
## farthest from where the players are on average, measured in hops from each player and
## averaged; a candidate within 3 hops of anyone is skipped while another exists, so a spot far
## from the average is never next door to one player. Ties are broken by the seeded generator,
## so every peer that shares the seed picks the same one. `exclude` is the spot just bought from.
const MACHINE_MIN_HOPS := 3

func machine_spot(from_ids: Array, rng: RandomNumberGenerator, exclude: String = "") -> String:
	var cands := goal_candidates()
	var order := []
	for c in cands:
		order.append(c)
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var best := ""
	var best_mean := -1.0
	var best_fair := false
	for c in order:
		if c == exclude and order.size() > 1:
			continue
		var total := 0.0
		var nearest := 1 << 30
		for f in from_ids:
			var d := distance(str(f), c)
			if d < 0:
				d = 1 << 20
			total += d
			nearest = mini(nearest, d)
		var mean := total / maxf(1.0, from_ids.size())
		var fair := nearest >= MACHINE_MIN_HOPS
		if (fair and not best_fair) or (fair == best_fair and mean > best_mean):
			best = c
			best_mean = mean
			best_fair = fair
	if best == "" and not cands.is_empty():
		best = cands[0]
	return best


var _mean_step: float = -1.0


## The mean distance between linked spaces, in metres: the board's "one space" for anything
## measured in spaces (the laser's reach), so the numbers in tuning hold on any board.
func mean_step() -> float:
	if _mean_step < 0.0:
		var total := 0.0
		var n := 0
		for sid in spaces:
			var s: Space = spaces[sid]
			for nx in s.next:
				var t := get_space(str(nx))
				if t != null:
					total += s.position.distance_to(t.position)
					n += 1
		_mean_step = total / n if n > 0 else 3.0
	return _mean_step
