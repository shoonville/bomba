class_name MapDressing
extends RefCounted
## Dresses a gray-box layout without touching its play. Everything here is decor (meshes, no
## collision) appended to layout["decor"] and built by MapBuilder like the posters and lamps;
## the boxes, spawns and bot graph are read, never changed, so the layout tests still hold.
## Deterministic from the layout's size, so every peer builds the same city.
##   - a skyline outside the walls: two bands of blocks tall enough to show over the 6 m wall
##     from anywhere inside, a few landmarks, lit windows on the near band
##   - façades: window rows and a cornice on the perimeter walls, windows and roof units on
##     every free-standing building, straps on the crates, a beacon on the tallest deck
##   - floor zones: a plaza slab under the centre, sidewalks along the walls, drain grates
##   - props against the walls: barrels in the corners, a dumpster, pipes with junction boxes,
##     two billboards on the wall tops
## Colours are palette tones of the map (skyline, skyline_far, window are new keys), so LAST
## STAND's dusk pit gets the same city in its own light.


static func dress(layout: Dictionary, map_id: String) -> void:
	var size: Vector2 = layout.get("size", Vector2(48, 40))
	var w := size.x
	var d := size.y
	var decor: Array = layout.get("decor", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d:%d" % [map_id, int(w), int(d)])
	var occupied := _wall_exclusions(decor, w, d)
	_perimeter(decor, w, d, occupied)
	_buildings(decor, layout["boxes"], w, d)
	_crates(decor, layout["boxes"])
	_beacon(decor, layout["boxes"])
	_floor(decor, w, d, rng)
	_props(decor, w, d, occupied, rng)
	_skyline(decor, w, d, rng)
	layout["decor"] = decor


# --- helpers -------------------------------------------------------------------------------------

static func _box(out: Array, pos: Vector3, size: Vector3, tone: String, yaw: float = 0.0, shadow: bool = true) -> void:
	out.append({"pos": pos, "size": size, "tone": tone, "yaw": yaw, "shape": "box", "shadow": shadow})


static func _cyl(out: Array, pos: Vector3, size: Vector3, tone: String, shadow: bool = true) -> void:
	out.append({"pos": pos, "size": size, "tone": tone, "shape": "cylinder", "shadow": shadow})


## Along-wall intervals already taken by posters (paper sheets standing on a wall face), keyed
## by wall: "n", "s", "e", "w". Windows and doors keep clear of them.
static func _wall_exclusions(decor: Array, w: float, d: float) -> Dictionary:
	var out := {"n": [], "s": [], "e": [], "w": []}
	for dcr in decor:
		if str(dcr.get("tone", "")) != "paper" or str(dcr.get("shape", "box")) != "box":
			continue
		var p: Vector3 = dcr["pos"]
		var s: Vector3 = dcr["size"]
		if s.y < 1.0:
			continue   # road paint, not a sheet
		var half := s.x * 0.5 + 0.7
		if absf(p.z + d * 0.5) < 0.3:
			out["n"].append(Vector2(p.x - half, p.x + half))
		elif absf(p.z - d * 0.5) < 0.3:
			out["s"].append(Vector2(p.x - half, p.x + half))
		elif absf(p.x + w * 0.5) < 0.3:
			out["w"].append(Vector2(p.z - half, p.z + half))
		elif absf(p.x - w * 0.5) < 0.3:
			out["e"].append(Vector2(p.z - half, p.z + half))
	return out


static func _free(intervals: Array, t: float, half: float) -> bool:
	for iv in intervals:
		if t + half > float(iv.x) and t - half < float(iv.y):
			return false
	return true


# --- the perimeter walls: windows, doors, a cornice and a plinth ------------------------------------

static func _perimeter(out: Array, w: float, d: float, occupied: Dictionary) -> void:
	# Each wall: its inside face plane, the axis along it, the normal pointing into the arena.
	var walls := [
		{"key": "n", "normal": Vector3(0, 0, 1), "along": Vector3(1, 0, 0), "face": Vector3(0, 0, -d * 0.5), "len": w},
		{"key": "s", "normal": Vector3(0, 0, -1), "along": Vector3(1, 0, 0), "face": Vector3(0, 0, d * 0.5), "len": w},
		{"key": "w", "normal": Vector3(1, 0, 0), "along": Vector3(0, 0, 1), "face": Vector3(-w * 0.5, 0, 0), "len": d},
		{"key": "e", "normal": Vector3(-1, 0, 0), "along": Vector3(0, 0, 1), "face": Vector3(w * 0.5, 0, 0), "len": d},
	]
	for wall in walls:
		var n: Vector3 = wall["normal"]
		var a: Vector3 = wall["along"]
		var face: Vector3 = wall["face"]
		var length: float = wall["len"]
		var yaw := atan2(n.x, n.z)
		var taken: Array = occupied[wall["key"]]
		# Cornice along the top and a plinth along the foot, the whole length.
		_box(out, face + n * 0.14 + Vector3(0, 5.86, 0), Vector3(length, 0.28, 0.28) if a.x != 0.0 else Vector3(0.28, 0.28, length), "paper", 0.0, false)
		_box(out, face + n * 0.05 + Vector3(0, 0.3, 0), Vector3(length, 0.6, 0.1) if a.x != 0.0 else Vector3(0.1, 0.6, length), "counter_dark", 0.0, false)
		# Windows: two rows on a 2.4 m pitch, doors every fourth slot on the lower row.
		var slots := int(floorf((length - 3.0) / 2.4))
		var start := -(slots - 1) * 1.2
		for i in slots:
			var t := start + i * 2.4
			if not _free(taken, t, 0.75):
				continue
			var base := face + a * t
			if i % 4 == 2:
				_box(out, base + n * 0.02 + Vector3(0, 1.25, 0), Vector3(1.3, 2.5, 0.04), "window", yaw, false)
				_box(out, base + n * 0.04 + Vector3(0, 2.5, 0), Vector3(1.5, 0.12, 0.06), "paper", yaw, false)
			else:
				_box(out, base + n * 0.02 + Vector3(0, 2.7, 0), Vector3(1.0, 1.3, 0.04), "window", yaw, false)
				_box(out, base + n * 0.04 + Vector3(0, 2.02, 0), Vector3(1.2, 0.1, 0.06), "paper", yaw, false)
			_box(out, base + n * 0.02 + Vector3(0, 4.5, 0), Vector3(1.0, 1.1, 0.04), "window", yaw, false)
			_box(out, base + n * 0.04 + Vector3(0, 3.92, 0), Vector3(1.2, 0.1, 0.06), "paper", yaw, false)


# --- free-standing buildings: windows on every face, a roof unit -----------------------------------

static func _buildings(out: Array, boxes: Array, w: float, d: float) -> void:
	for b in boxes:
		var s: Vector3 = b["size"]
		var p: Vector3 = b["pos"]
		if s.y < 3.5 or s.x < 5.0 or s.z < 5.0 or s.x > w - 4.0:
			continue   # not a building: floor, walls, decks, crates, pillars
		var top := p.y + s.y * 0.5
		var faces := [
			[Vector3(0, 0, 1), Vector3(1, 0, 0), s.x], [Vector3(0, 0, -1), Vector3(1, 0, 0), s.x],
			[Vector3(1, 0, 0), Vector3(0, 0, 1), s.z], [Vector3(-1, 0, 0), Vector3(0, 0, 1), s.z],
		]
		for f in faces:
			var n: Vector3 = f[0]
			var a: Vector3 = f[1]
			var length: float = f[2]
			var yaw := atan2(n.x, n.z)
			var face := p + n * (absf(n.x) * s.x + absf(n.z) * s.z) * 0.5
			var slots := int(floorf((length - 1.6) / 2.0))
			var start := -(slots - 1) * 1.0
			# `base` carries the building's centre height already, so the offsets are from the
			# centre: windows 2 m above the bottom, sills at 1.37 m. (They were placed from the
			# top instead and stood 2 m over the roof: Sean's floating panels.)
			for i in slots:
				var base := face + a * (start + i * 2.0)
				_box(out, base + n * 0.02 + Vector3(0, 2.0 - s.y * 0.5, 0), Vector3(0.9, 1.2, 0.04), "window", yaw, false)
				_box(out, base + n * 0.04 + Vector3(0, 1.37 - s.y * 0.5, 0), Vector3(1.1, 0.1, 0.06), "paper", yaw, false)
		# Roof: an air unit with a fan disc and a vent pipe, off the parapet side, standing on
		# the roof (absolute heights: `top` is the roof).
		_box(out, Vector3(p.x - s.x * 0.22, top + 0.45, p.z + s.z * 0.1), Vector3(1.4, 0.9, 1.1), "counter_dark")
		_cyl(out, Vector3(p.x - s.x * 0.22, top + 0.92, p.z + s.z * 0.1), Vector3(0.9, 0.06, 0.9), "glow", false)
		_cyl(out, Vector3(p.x + s.x * 0.25, top + 0.7, p.z - s.z * 0.15), Vector3(0.36, 1.4, 0.36), "counter_dark")
		_cyl(out, Vector3(p.x + s.x * 0.25, top + 1.45, p.z - s.z * 0.15), Vector3(0.6, 0.12, 0.6), "counter_dark")


# --- crates: a strap band so a cube reads as a crate ----------------------------------------------

static func _crates(out: Array, boxes: Array) -> void:
	for b in boxes:
		var s: Vector3 = b["size"]
		if absf(s.y - 1.2) > 0.01 or s.x < 1.1 or s.x > 1.7 or absf(s.x - s.z) > 0.01:
			continue
		_box(out, b["pos"], Vector3(s.x + 0.04, 0.14, s.z + 0.04), "counter_dark", 0.0, false)


# --- a beacon on the highest deck ----------------------------------------------------------------

static func _beacon(out: Array, boxes: Array) -> void:
	var best: Dictionary = {}
	var best_top := -1.0
	for b in boxes:
		var s: Vector3 = b["size"]
		if s.y > 1.0 or s.x < 3.0:
			continue   # decks are thin and wide
		var top: float = b["pos"].y + s.y * 0.5
		if top > best_top:
			best_top = top
			best = b
	if best.is_empty():
		return
	var p: Vector3 = best["pos"]
	var s: Vector3 = best["size"]
	var foot := Vector3(p.x - s.x * 0.5 + 0.5, best_top, p.z - s.z * 0.5 + 0.5)
	_cyl(out, foot + Vector3(0, 1.6, 0), Vector3(0.14, 3.2, 0.18), "counter_dark")
	_box(out, foot + Vector3(0, 3.35, 0), Vector3(0.36, 0.36, 0.36), "glow", 0.0, false)
	_cyl(out, foot + Vector3(0, 0.08, 0), Vector3(0.7, 0.16, 0.7), "counter_dark")


# --- the floor: a plaza, sidewalks, grates ----------------------------------------------------------

static func _floor(out: Array, w: float, d: float, rng: RandomNumberGenerator) -> void:
	var pw := minf(w, d) * 0.42
	_box(out, Vector3(0, 0.012, 0), Vector3(pw, 0.024, pw), "field", 0.0, false)
	_box(out, Vector3(0, 0.02, 0), Vector3(pw - 1.2, 0.024, pw - 1.2), "floor", 0.0, false)
	var sw := 2.0
	_box(out, Vector3(0, 0.012, -d * 0.5 + sw * 0.5), Vector3(w, 0.024, sw), "field_dark", 0.0, false)
	_box(out, Vector3(0, 0.012, d * 0.5 - sw * 0.5), Vector3(w, 0.024, sw), "field_dark", 0.0, false)
	_box(out, Vector3(-w * 0.5 + sw * 0.5, 0.012, 0), Vector3(sw, 0.024, d), "field_dark", 0.0, false)
	_box(out, Vector3(w * 0.5 - sw * 0.5, 0.012, 0), Vector3(sw, 0.024, d), "field_dark", 0.0, false)
	for i in 4:
		var gp := Vector3(rng.randf_range(-w * 0.34, w * 0.34), 0.016, rng.randf_range(-d * 0.34, d * 0.34))
		if gp.length() < pw * 0.6:
			gp = gp.normalized() * pw * 0.6
		_cyl(out, gp, Vector3(0.9, 0.03, 0.9), "counter_dark", false)
		_cyl(out, gp + Vector3(0, 0.005, 0), Vector3(0.6, 0.03, 0.6), "window", false)


# --- props against the walls ----------------------------------------------------------------------

static func _props(out: Array, w: float, d: float, occupied: Dictionary, rng: RandomNumberGenerator) -> void:
	# Barrels tucked into the four corners, two or three each.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var corner := Vector3(sx * (w * 0.5 - 0.6), 0, sz * (d * 0.5 - 0.6))
			var n := 2 + (rng.randi() % 2)
			for i in n:
				var off := Vector3(-sx * (0.0 if i == 0 else 0.62 * i), 0, -sz * (0.62 if i == 0 else 0.0))
				var tone := "accent" if (i == 1 and sx > 0.0 and sz < 0.0) else "counter"
				_cyl(out, corner + off + Vector3(0, 0.45, 0), Vector3(0.58, 0.9, 0.58), tone)
				_cyl(out, corner + off + Vector3(0, 0.3, 0), Vector3(0.62, 0.06, 0.62), "counter_dark")
				_cyl(out, corner + off + Vector3(0, 0.62, 0), Vector3(0.62, 0.06, 0.62), "counter_dark")
	# A dumpster against the east wall, where the catwalk feet are not.
	var dz := 6.0
	if not _free(occupied["e"], dz, 1.3):
		dz = -6.0
	_box(out, Vector3(w * 0.5 - 1.05, 0.55, dz), Vector3(1.3, 1.1, 2.2), "counter")
	_box(out, Vector3(w * 0.5 - 1.05, 1.14, dz), Vector3(1.4, 0.1, 2.3), "counter_dark")
	_box(out, Vector3(w * 0.5 - 0.25, 0.15, dz), Vector3(0.3, 0.3, 2.0), "counter_dark")
	# Pipes along the north and south walls at 4.6 m with junction boxes and a drop at each end.
	for sz: float in [-1.0, 1.0]:
		var z := sz * (d * 0.5 - 0.22)
		var run := w * 0.62
		_cyl(out, Vector3(0, 4.6, z), Vector3(0.18, run, 0.18), "counter_dark", false)
		# MapBuilder builds cylinders upright; rolled a quarter turn this one runs along the wall.
		out.back()["roll"] = PI * 0.5
		for sx: float in [-1.0, 1.0]:
			_cyl(out, Vector3(sx * run * 0.5, 2.3, z), Vector3(0.18, 4.6, 0.18), "counter_dark", false)
			_box(out, Vector3(sx * run * 0.28, 4.6, z), Vector3(0.6, 0.5, 0.42), "counter_dark", 0.0, false)
	# Two billboards standing on the wall tops (east of centre on the south wall, west on the
	# north one, so neither stands in the showcase camera's line to the tower).
	for sz: float in [-1.0, 1.0]:
		var x := sz * w * 0.18
		var z := sz * (d * 0.5 + 0.5)
		for px: float in [-2.6, 2.6]:
			_cyl(out, Vector3(x + px, 7.0, z), Vector3(0.2, 2.0, 0.2), "counter_dark", false)
		_box(out, Vector3(x, 9.3, z), Vector3(6.4, 3.2, 0.14), "paper", 0.0, false)
		_box(out, Vector3(x, 9.3, z + sz * 0.12), Vector3(6.5, 3.3, 0.12), "counter_dark", 0.0, false)   # its back, seen from a roof
		_box(out, Vector3(x, 9.4, z - sz * 0.1), Vector3(5.6, 2.2, 0.06), "poster_b" if sz > 0.0 else "poster_a", 0.0, false)
		_box(out, Vector3(x, 8.35, z - sz * 0.14), Vector3(5.6, 0.36, 0.06), "accent", 0.0, false)


# --- the skyline outside the walls ------------------------------------------------------------------

static func _skyline(out: Array, w: float, d: float, rng: RandomNumberGenerator) -> void:
	# Two bands around the arena. From an eye at 1.6 m, 10 m inside a 6 m wall, a block 12 m past
	# the wall has to be over 11 m tall to show, one 35 m past it over 21 m: the bands are sized
	# so that every block shows from somewhere on the floor and the tall ones from anywhere.
	var bands := [
		{"gap": 5.0, "depth": 12.0, "hmin": 10.0, "hmax": 18.0, "tone": "skyline", "n": 7, "lit": true},
		{"gap": 22.0, "depth": 24.0, "hmin": 18.0, "hmax": 40.0, "tone": "skyline_far", "n": 6, "lit": false},
	]
	for band in bands:
		var gap: float = band["gap"]
		var depth: float = band["depth"]
		var n: int = band["n"]
		var tone: String = band["tone"]
		var sides := [
			[Vector3(0, 0, -1), Vector3(1, 0, 0), w, d * 0.5], [Vector3(0, 0, 1), Vector3(1, 0, 0), w, d * 0.5],
			[Vector3(-1, 0, 0), Vector3(0, 0, 1), d, w * 0.5], [Vector3(1, 0, 0), Vector3(0, 0, 1), d, w * 0.5],
		]
		for side in sides:
			var outward: Vector3 = side[0]
			var along: Vector3 = side[1]
			var length: float = side[2]
			var half: float = side[3]
			for i in n:
				var t := -length * 0.55 + (i + rng.randf_range(0.2, 0.8)) * (length * 1.1 / n)
				var dist := half + gap + rng.randf_range(0.0, depth)
				var bw := rng.randf_range(4.0, 10.0)
				var bd := rng.randf_range(4.0, 9.0)
				var bh := rng.randf_range(float(band["hmin"]), float(band["hmax"]))
				var centre := outward * dist + along * t
				var size := Vector3(bw, bh, bd) if along.x != 0.0 else Vector3(bd, bh, bw)
				_box(out, centre + Vector3(0, bh * 0.5, 0), size, tone, 0.0, false)
				# A shorter neighbour on one side, so the silhouette steps instead of repeating.
				if rng.randf() < 0.6:
					var nh := bh * rng.randf_range(0.45, 0.8)
					var nw := rng.randf_range(3.0, 6.0)
					var nc := centre + along * (bw * 0.5 + nw * 0.5) * (1.0 if rng.randf() < 0.5 else -1.0)
					_box(out, nc + Vector3(0, nh * 0.5, 0), Vector3(nw, nh, bd) if along.x != 0.0 else Vector3(bd, nh, nw), tone, 0.0, false)
				if bool(band["lit"]):
					# Lit window strips on the face toward the arena, high enough to show over the wall.
					var face := centre - outward * ((bd if along.x != 0.0 else bw) * 0.5 + 0.03)
					var rows := 1 + (rng.randi() % 3)
					for r in rows:
						var y := bh - 1.6 - r * 2.4
						if y < 8.0:
							break
						var sw := rng.randf_range(1.6, bw * 0.6)
						var strip := Vector3(sw, 0.5, 0.06) if along.x != 0.0 else Vector3(0.06, 0.5, sw)
						_box(out, face + along * rng.randf_range(-bw * 0.2, bw * 0.2) + Vector3(0, y, 0), strip, "glow", 0.0, false)
				elif rng.randf() < 0.5:
					# Far band: a water tank or an antenna on the roof.
					var roof := centre + Vector3(0, bh, 0)
					if rng.randf() < 0.5:
						_cyl(out, roof + Vector3(0, 1.4, 0), Vector3(2.6, 2.8, 2.6), tone, false)
					else:
						_cyl(out, roof + Vector3(0, 3.0, 0), Vector3(0.3, 6.0, 0.4), tone, false)
	# Landmarks: a tower crane past one corner, a radio mast past the opposite one.
	var cx := w * 0.5 + 16.0
	var cz := -d * 0.5 - 14.0
	_box(out, Vector3(cx, 15.0, cz), Vector3(1.6, 30.0, 1.6), "skyline", 0.0, false)
	_box(out, Vector3(cx - 9.0, 30.4, cz), Vector3(22.0, 0.8, 0.8), "skyline", 0.0, false)
	_box(out, Vector3(cx - 16.0, 26.0, cz), Vector3(0.3, 8.0, 0.3), "skyline", 0.0, false)
	_box(out, Vector3(cx - 16.0, 21.6, cz), Vector3(1.4, 1.0, 1.4), "accent", 0.0, false)
	_box(out, Vector3(cx + 3.0, 30.0, cz), Vector3(3.0, 1.6, 1.6), "skyline", 0.0, false)
	var mx := -w * 0.5 - 20.0
	var mz := d * 0.5 + 18.0
	_cyl(out, Vector3(mx, 17.0, mz), Vector3(0.5, 34.0, 1.6), "skyline_far", false)
	for i in 3:
		_cyl(out, Vector3(mx, 24.0 + i * 4.0, mz), Vector3(2.4 - i * 0.5, 0.16, 2.4 - i * 0.5), "skyline_far", false)
	_box(out, Vector3(mx, 34.4, mz), Vector3(0.5, 0.5, 0.5), "glow", 0.0, false)
