extends SceneTree
## Flags the vending machine spots on a board file (the spaces flagged "goal"): the two walkway
## spaces nearest the board's two annexes. The annexes stand off the rim where the walkway sits
## farthest from it, at least 110° apart (`AnnexPlan.angles`, the search that placed
## them before they carried the machines); each gets the blank, non-fork, non-start space nearest
## its rim point whose corridor out to the annex is clear of every other space, so the bridge
## crosses nothing. Sean: the machine lives on "those original two spots", never more. Rewrites
## the file in place.
##   GODOT --headless --path . --script tools/mark_spots.gd -- board/boards/main.json

const CORRIDOR_HALF := 2.6   # the annex bridge is 3.2 m wide


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
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for sd in spaces:
		var p: Array = sd["position"]
		var v := Vector2(float(p[0]), float(p[2]))
		pos[str(sd["id"])] = v
		fork[str(sd["id"])] = (sd.get("next", []) as Array).size() > 1
		tiles.append(Vector3(v.x, 0.0, v.y))
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	var centre := (lo + hi) * 0.5
	var rx := (hi.x - lo.x) * 0.5 + 7.0   # the moon slab's radii, as board_view builds them
	var rz := (hi.y - lo.y) * 0.5 + 7.0
	var start := str(d.get("start", ""))
	var chosen := {}
	var report := []
	for a_v in AnnexPlan.angles(tiles, Vector3(centre.x, 0.0, centre.y), rx, rz):
		var a: float = a_v
		var rim := Vector2(centre.x + cos(a) * rx, centre.y + sin(a) * rz)
		var best := ""
		var best_d := 1e9
		for sd in spaces:
			var sid := str(sd["id"])
			if sid == start or bool(fork[sid]) or str(sd.get("type", "blank")) != "blank" or chosen.has(sid):
				continue
			var v: Vector2 = pos[sid]
			# The annex stands straight out from the space (the ellipse's own ray through it) and
			# the bridge runs along that ray; its corridor to the rim must be clear of every other
			# space.
			var t := atan2((v.y - centre.y) / rz, (v.x - centre.x) / rx)
			var out_pt := Vector2(centre.x + cos(t) * rx, centre.y + sin(t) * rz)
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
