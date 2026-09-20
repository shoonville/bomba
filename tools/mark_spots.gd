extends SceneTree
## Marks the vending machine spots on a board file (the spaces flagged "goal"): in each of K
## equal sectors around the board's centre, the blank, non-fork space standing farthest out
## whose corridor outward to the rim is clear of every other space (the bridge must not cross
## the walkway); a sector with no such space gets none. Rewrites the file in place.
##   GODOT --headless --path . --script tools/mark_spots.gd -- board/boards/main.json 6
## BOMBA BAY: six sectors give its five spots (L2, L9, L20, L23, L31); one sector has no clear space.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "board/boards/main.json"
	var k: int = int(args[1]) if args.size() > 1 else 6
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
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for sd in spaces:
		var p: Array = sd["position"]
		var v := Vector2(float(p[0]), float(p[2]))
		pos[str(sd["id"])] = v
		fork[str(sd["id"])] = (sd.get("next", []) as Array).size() > 1
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	var centre := (lo + hi) * 0.5
	var rx := (hi.x - lo.x) * 0.5 + 7.0   # the moon slab's radii, as board_view builds them
	var rz := (hi.y - lo.y) * 0.5 + 7.0
	var start := str(d.get("start", ""))
	var chosen := {}
	for sector in k:
		var best := ""
		var best_score := -1e9
		for sd in spaces:
			var sid := str(sd["id"])
			if sid == start or bool(fork[sid]) or str(sd.get("type", "blank")) != "blank":
				continue
			var v: Vector2 = pos[sid]
			var a := atan2(v.y - centre.y, v.x - centre.x)
			if int(floor((a + PI) / (TAU / k))) % k != sector:
				continue
			var out := (v - centre).normalized()
			var radial := Vector2((v.x - centre.x) / rx, (v.y - centre.y) / rz).length()
			# Corridor outward: nothing within 2.4 m of the line from the space to the rim, or the
			# bridge would cross another space.
			var half := 2.4
			var clear := true
			var rim_d := (Vector2(cos(a) * rx, sin(a) * rz)).length() - (v - centre).length()
			var t := 1.6
			while t < rim_d + 1.0:
				var q := v + out * t
				for other in pos:
					if other != sid and (pos[other] as Vector2).distance_to(q) < half:
						clear = false
				t += 1.0
			if not clear:
				continue
			var score := radial
			if score > best_score:
				best_score = score
				best = sid
		if best != "":
			chosen[best] = true
	for sd in spaces:
		sd["goal"] = chosen.has(str(sd["id"]))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "  ") + "\n")
	f.close()
	var ids := chosen.keys()
	ids.sort()
	print("marked %d machine spots on %s: %s" % [ids.size(), path, ", ".join(ids)])
	quit(0)
