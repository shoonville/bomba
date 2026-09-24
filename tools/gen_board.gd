extends SceneTree
## Generates board/boards/main.json (BOMBA BAY), the GDScript port of gen_board.py (Sean's
## desktop has no Python): one big loop on a wobbly ellipse sampled every ~3.7 m, with four
## branches (a raised inner bridge, two inner cuts, an outside item-rich detour). Sean
## (2026-09-23): a lap should take about 20 turns of the d8, so the loop is about 88 spaces
## (it was 36) and the branches are short alternates that change a lap by a few steps rather
## than halving it; the tile mix, the wobble, the two elevation waves and the one safe spot
## opposite the start are the originals. Deterministic (seed 11). Machine spots are flagged
## afterwards by tools/mark_spots.gd.
##   GODOT --headless --path . --script tools/gen_board.gd -- [loop_spaces] [out]

const SPACING := 3.7        # metres between loop spaces
const BRANCH_SPACING := 3.9
const CLEAR := 3.1          # a branch point keeps this far from every other space
const MAX_HOP := 5.6

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var want_loop: int = int(args[0]) if args.size() > 0 else 88
	var out_path: String = args[1] if args.size() > 1 else "res://board/boards/main.json"
	_rng.seed = 11
	# The ellipse's radii from the loop length wanted: the original 24 × 18 m gave 36 spaces at
	# 3.7 m; the wobble adds about 2 %, so scale the perimeter estimate to the target.
	var ratio := float(want_loop) / 36.0
	var rx := 24.0 * ratio
	var rz := 18.0 * ratio
	var loop := _sample_loop(rx, rz)
	var L := loop.size()
	print("loop %d spaces on a %.1f × %.1f m ellipse" % [L, rx, rz])
	# Branches as fractions of the loop (the originals were at 3→20, 8→14, 25→32 and 15→19 of
	# 36): a raised bridge cutting the first bend (the long one, a ninth of the loop), an inner
	# cut at the top, an inner cut at the bottom right, an outside detour at the top left (each
	# a fourteenth). An inner cut bows toward the centre, so it runs a step or two shorter than
	# the arc it replaces; the outside detour a step longer; every lap stays near the loop's.
	var span_a := maxi(6, roundi(L / 9.0))
	var span := maxi(5, roundi(L / 14.0))
	var branches := [
		{"name": "A", "i": roundi(L * 0.08), "j": roundi(L * 0.08) + span_a, "side": 1, "y": 1.2},
		{"name": "B", "i": roundi(L * 0.30), "j": roundi(L * 0.30) + span, "side": 1, "y": 0.9},
		{"name": "C", "i": roundi(L * 0.68), "j": roundi(L * 0.68) + span, "side": 1, "y": 0.6},
		{"name": "D", "i": roundi(L * 0.45), "j": roundi(L * 0.45) + span, "side": -1, "y": 0.3},
	]
	var taken: Array = []
	for b in branches:
		var pts := _make_branch(loop, int(b["i"]), int(b["j"]) % L, int(b["side"]), float(b["y"]), taken)
		if pts.is_empty():
			printerr("no bulge works for branch %s" % b["name"])
			quit(2)
			return
		b["pts"] = pts
		taken.append_array(pts)
	var spaces: Array = []
	for i in L:
		var nxt := ["L%d" % ((i + 1) % L)]
		for b in branches:
			if int(b["i"]) == i:
				nxt.append("%s1" % b["name"])
		var typ := "start" if i == 0 else _pick_type(false, "")
		if (i == 1 or i == 2) and typ == "lose":
			typ = "coin"
		if i == L / 2 + 1:
			typ = "shield"   # the one safe spot, opposite the start
		spaces.append(_space("L%d" % i, Vector3(loop[i].x, _elev(i, L), loop[i].y), typ, nxt))
	for b in branches:
		var pts: Array = b["pts"]
		for m in pts.size():
			var nxt := ["%s%d" % [b["name"], m + 2]] if m + 1 < pts.size() else ["L%d" % (int(b["j"]) % L)]
			spaces.append(_space("%s%d" % [b["name"], m + 1], pts[m], _pick_type(true, str(b["name"])), nxt))
	# Geometry check: no two spaces nearer than 3 m, no hop longer than MAX_HOP.
	var byid := {}
	for s in spaces:
		byid[s["id"]] = s
	var min_pair := 1e9
	for a in spaces.size():
		for c in range(a + 1, spaces.size()):
			min_pair = minf(min_pair, _p(spaces[a]).distance_to(_p(spaces[c])))
	var max_hop := 0.0
	for s in spaces:
		for n in s["next"]:
			max_hop = maxf(max_hop, _p(s).distance_to(_p(byid[n])))
	var counts := {}
	var forks := []
	for s in spaces:
		counts[s["type"]] = int(counts.get(s["type"], 0)) + 1
		if (s["next"] as Array).size() > 1:
			forks.append(s["id"])
	print("spaces %d, loop %d, forks %s, branch lengths %s" % [spaces.size(), L, str(forks),
		str(branches.map(func(b): return (b["pts"] as Array).size()))])
	print("min pair %.2f m, hop max %.2f m, types %s" % [min_pair, max_hop, str(counts)])
	if min_pair < 3.0 or max_hop > MAX_HOP:
		printerr("geometry check failed")
		quit(2)
		return
	var board := {"id": "main", "display_name": "BOMBA BAY", "start": "L0", "spaces": spaces}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(board, "  ") + "\n")
	f.close()
	print("wrote %s" % out_path)
	quit(0)


func _loop_pt(t: float, rx: float, rz: float) -> Vector2:
	var rw := 1.0 + 0.06 * sin(3.0 * t + 0.6)
	return Vector2(rx * cos(t) * rw, rz * sin(t) * (1.0 + 0.10 * cos(2.0 * t)))


## The loop sampled every SPACING metres of arc.
func _sample_loop(rx: float, rz: float) -> Array:
	var loop: Array = []
	var n := 6000
	var prev := _loop_pt(0.0, rx, rz)
	loop.append(prev)
	var acc := 0.0
	for i in range(1, n + 1):
		var t := TAU * i / n
		var p := _loop_pt(t, rx, rz)
		acc += p.distance_to(prev)
		prev = p
		if acc >= SPACING:
			loop.append(p)
			acc = 0.0
	if (loop[-1] as Vector2).distance_to(loop[0]) < 3.0:
		loop.pop_back()
	return loop


## Two waves of elevation round the loop, in 0.15 m steps, 0 to 0.9 m.
func _elev(i: int, L: int) -> float:
	return roundf((0.45 * (1.0 + sin(float(i) * TAU / L * 2.0 + 0.8))) / 0.15) * 0.15


func _bowed(a: Vector2, b: Vector2, nrm: Vector2, bulge: float, f: float) -> Vector2:
	return a + (b - a) * f + nrm * bulge * sin(f * PI)


## Interior points of a path from loop[i] to loop[j], bowed toward (side 1) or away from (side
## -1) the board's centre by the smallest bulge that keeps every point CLEAR metres from every
## loop space and every other branch space, spaced about BRANCH_SPACING along the path.
func _make_branch(loop: Array, i: int, j: int, side: int, y: float, taken: Array) -> Array:
	var a: Vector2 = loop[i]
	var b: Vector2 = loop[j]
	var d := b - a
	var nrm := Vector2(-d.y, d.x) / d.length()
	var mid := (a + b) * 0.5
	if (nrm.dot(-mid)) * side < 0.0:
		nrm = -nrm
	for bi in range(4, 88):
		var bulge := bi * 0.5
		var fine: Array = []
		for f in 301:
			fine.append(_bowed(a, b, nrm, bulge, f / 300.0))
		var seg: Array = []
		var length := 0.0
		for m in 300:
			var sl: float = (fine[m] as Vector2).distance_to(fine[m + 1])
			seg.append(sl)
			length += sl
		var k := maxi(1, roundi(length / BRANCH_SPACING) - 1)
		var step := length / (k + 1)
		var pts: Array = []
		var acc := 0.0
		var want := step
		var m := 0
		while pts.size() < k and m < 300:
			acc += float(seg[m])
			m += 1
			if acc >= want:
				var q: Vector2 = fine[m]
				pts.append(Vector3(q.x, y, q.y))
				want += step
		var ok := pts.size() == k
		if ok:
			for p in pts:
				var pf := Vector2((p as Vector3).x, (p as Vector3).z)
				for q in loop:
					if pf.distance_to(q) < CLEAR:
						ok = false
						break
				if not ok:
					break
				for q in taken:
					if (p as Vector3).distance_to(q) < CLEAR:
						ok = false
						break
				if not ok:
					break
		if ok:
			return pts
	return []


func _pick_type(is_branch: bool, kind: String) -> String:
	var r := _rng.randf()
	if kind == "D":
		return "item" if r < 0.5 else ("coin" if r < 0.8 else "event")
	if is_branch:
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


func _space(id: String, pos: Vector3, typ: String, nxt: Array) -> Dictionary:
	return {"id": id, "position": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)],
		"type": typ, "next": nxt, "goal": false}


func _p(s: Dictionary) -> Vector3:
	var a: Array = s["position"]
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
