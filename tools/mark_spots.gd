extends SceneTree
## Flags the vending machine spots on a board file (the spaces flagged "goal"): the two walkway
## spaces nearest the board's two annexes. The annexes stand off the rim where the walkway sits
## farthest from it, at least 110° apart (`AnnexPlan.angles`, the search that placed
## them before they carried the machines); each gets the blank, non-fork, non-merge, non-start
## space nearest its rim point whose corridor out to the annex is clear of every other space, so
## the bridge crosses nothing. Sean: the machine lives on "those original two spots", never more.
## The slab is the board file's own (`MoonSlab`, written by tools/gen_board.gd) so the tool sees
## the rim the view builds; a file without one gets the old ellipse round the tiles. Rewrites the
## file in place.
##   GODOT --headless --path . --script tools/mark_spots.gd -- board/boards/main.json

const CORRIDOR_HALF := 2.6   # the annex bridge is 3.2 m wide
const MIN_HOPS_FROM_START := 8   # no annex on the start's doorstep, either way round


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "board/boards/main.json"
	if not path.is_absolute_path() and not path.begins_with("res://"):
		path = "res://" + path
	var d: Dictionary = TuningLoader.load_file(path)
	if d.is_empty():
		printerr("cannot read %s" % path)
		quit(2)
		return
	var spaces: Array = d["spaces"]
	var pos := {}
	var fork := {}
	var tiles: Array = []
	for sd in spaces:
		var p: Array = sd["position"]
		var v := Vector2(float(p[0]), float(p[2]))
		pos[str(sd["id"])] = v
		fork[str(sd["id"])] = (sd.get("next", []) as Array).size() > 1
		tiles.append(Vector3(v.x, 0.0, v.y))
	var slab: MoonSlab = MoonSlab.from_dict(d.get("slab", {}))
	if slab == null:
		slab = MoonSlab.around(tiles, 7.0, 7.0)
	var start := str(d.get("start", ""))
	# Hops from the start forwards and backwards along the paths, so the annexes stay off the
	# start's doorstep; and how many ways lead into each space (a merge is no place for a bridge).
	var fwd := {}
	var back := {}
	for sd in spaces:
		var sid := str(sd["id"])
		fwd[sid] = Array(sd.get("next", [])).map(func(n): return str(n))
		for n in fwd[sid]:
			if not back.has(n):
				back[n] = []
			(back[n] as Array).append(sid)
	var hops_out := _hops(start, fwd)
	var hops_in := _hops(start, back)
	var chosen := {}
	var report := []
	var preset: Array = []
	for a in d.get("annexes", []):
		preset.append(float(a))
	for a_v in AnnexPlan.angles(tiles, slab, preset):
		var a: float = a_v
		var rim := slab.rim(a)
		var best := ""
		var best_d := 1e9
		for sd in spaces:
			var sid := str(sd["id"])
			if sid == start or bool(fork[sid]) or str(sd.get("type", "blank")) != "blank" or chosen.has(sid):
				continue
			if (back.get(sid, []) as Array).size() > 1:
				continue
			if mini(int(hops_out.get(sid, 999)), int(hops_in.get(sid, 999))) < MIN_HOPS_FROM_START:
				continue
			var v: Vector2 = pos[sid]
			# The annex stands straight out from the space (the slab's own ray through it) and
			# the bridge runs along that ray; its corridor to the rim must be clear of every other
			# space.
			var out_pt := slab.rim(slab.angle_of(v.x, v.y))
			var dir := (out_pt - v).normalized()
			var span := v.distance_to(out_pt) + 1.0
			var clear := true
			var s := 1.6
			while s < span:
				var q := v + dir * s
				for other in pos:
					if other != sid and (pos[other] as Vector2).distance_to(q) < CORRIDOR_HALF:
						clear = false
				s += 1.0
			if not clear:
				continue
			var dd := v.distance_to(rim)
			if dd < best_d:
				best_d = dd
				best = sid
		if best != "":
			chosen[best] = true
			report.append("%s (annex at %d°, %.1f m from its rim point)" % [best, roundi(rad_to_deg(a)), best_d])
	for sd in spaces:
		sd["goal"] = chosen.has(str(sd["id"]))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "  ") + "\n")
	f.close()
	print("marked %d machine spots on %s: %s" % [chosen.size(), path, ", ".join(report)])
	quit(0)


## Breadth-first hop counts from `from` over `edges` (id → [ids]).
func _hops(from: String, edges: Dictionary) -> Dictionary:
	var dist := {from: 0}
	var queue := [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for n in edges.get(cur, []):
			if not dist.has(n):
				dist[n] = int(dist[cur]) + 1
				queue.append(n)
	return dist
