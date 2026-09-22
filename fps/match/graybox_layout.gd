class_name GrayboxLayout
extends RefCounted
## The gray-box arena as data: boxes, spawns, bot waypoints. Built to Rust's principles
## (DESIGN.md §5) at ~125 % footprint with added vertical: one central tower everyone orbits,
## two rooftops for the sniper, cover lanes along the edges for the flank.
## Units: metres. Y up. Steps are ≤ 1.2 m so a 1.49 m Halo jump clears them.


static func box(pos: Vector3, size: Vector3, tone: String = "field") -> Dictionary:
	return {"pos": pos, "size": size, "tone": tone}


static func decor_box(pos: Vector3, size: Vector3, tone: String, yaw: float = 0.0) -> Dictionary:
	return {"pos": pos, "size": size, "tone": tone, "yaw": yaw, "shape": "box"}


static func decor_cyl(pos: Vector3, size: Vector3, tone: String) -> Dictionary:
	return {"pos": pos, "size": size, "tone": tone, "shape": "cylinder"}


## A poster on a wall: a paper sheet, a coloured print and a stripe, all thin boxes standing
## 4 cm off the wall. `normal` points away from the wall.
static func poster(out: Array, pos: Vector3, normal: Vector3, w: float, h: float, print_tone: String, stripe_tone: String) -> void:
	var yaw := atan2(normal.x, normal.z)
	var off := normal * 0.04
	out.append(decor_box(pos + off, Vector3(w, h, 0.05), "paper", yaw))
	out.append(decor_box(pos + off * 1.6 + Vector3(0, h * 0.06, 0), Vector3(w * 0.82, h * 0.62, 0.05), print_tone, yaw))
	out.append(decor_box(pos + off * 2.2 - Vector3(0, h * 0.36, 0), Vector3(w * 0.82, h * 0.1, 0.05), stripe_tone, yaw))


## A street lamp: a post and a glowing head.
static func lamp(out: Array, pos: Vector3) -> void:
	out.append(decor_cyl(pos + Vector3(0, 2.6, 0), Vector3(0.22, 5.2, 0.28), "counter_dark"))
	out.append(decor_box(pos + Vector3(0, 5.3, 0), Vector3(0.7, 0.32, 0.7), "counter_dark"))
	out.append(decor_box(pos + Vector3(0, 5.1, 0), Vector3(0.5, 0.08, 0.5), "glow"))


static func build() -> Dictionary:
	var W := 48.0
	var D := 40.0
	var boxes: Array = []
	# Floor and perimeter
	boxes.append(box(Vector3(0, -0.5, 0), Vector3(W, 1, D), "floor"))
	boxes.append(box(Vector3(0, 3.0, -D / 2 - 0.5), Vector3(W + 2, 6, 1), "counter"))
	boxes.append(box(Vector3(0, 3.0, D / 2 + 0.5), Vector3(W + 2, 6, 1), "counter"))
	boxes.append(box(Vector3(-W / 2 - 0.5, 3.0, 0), Vector3(1, 6, D + 2), "counter_dark"))
	boxes.append(box(Vector3(W / 2 + 0.5, 3.0, 0), Vector3(1, 6, D + 2), "counter_dark"))

	# Central tower (Sean: it looked unfinished and unconnected, and the top must be reachable
	# by stairs): three decks stepping in (9, 7, 5 m), four pillars, and three flights of four
	# 0.75 m steps (a hop each, well under the 1.49 m jump) winding up it: the ground to deck 1
	# on the south, deck 1 to deck 2 along the north edge, deck 2 to deck 3 along the east edge.
	# Each flight sits in the 1 m ring one deck leaves round the next.
	boxes.append(box(Vector3(0, 2.75, 0), Vector3(9, 0.5, 9), "field_dark"))
	boxes.append(box(Vector3(0, 5.75, 0), Vector3(7, 0.5, 7), "field_dark"))
	boxes.append(box(Vector3(0, 8.75, 0), Vector3(5, 0.5, 5), "accent"))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			boxes.append(box(Vector3(sx * 3.0, 4.5, sz * 3.0), Vector3(0.6, 9, 0.6), "counter_dark"))
	_stairs(boxes, Vector3(0, 0, 7.65), Vector3(0, 0, -1), 2.4, 0.0, "field")            # ground → deck 1
	_stairs(boxes, Vector3(-1.95, 0, -4.0), Vector3(1, 0, 0), 1.0, 3.0, "field_dark")   # deck 1 → deck 2
	_stairs(boxes, Vector3(3.0, 0, 1.95), Vector3(0, 0, -1), 1.0, 6.0, "field_dark")    # deck 2 → deck 3

	# Two buildings (rooftops = sniper perches), opposite corners, with crate stairs
	for s: float in [-1.0, 1.0]:
		var bx: float = s * 16.0
		var bz: float = s * -12.0
		boxes.append(box(Vector3(bx, 2.0, bz), Vector3(9, 4, 8), "field"))
		boxes.append(box(Vector3(bx - s * 6.5, 0.6, bz + 2.0), Vector3(1.6, 1.2, 1.6), "field_dark"))
		boxes.append(box(Vector3(bx - s * 6.5, 1.8, bz + 0.2), Vector3(1.6, 1.2, 1.6), "field_dark"))
		boxes.append(box(Vector3(bx - s * 6.5, 3.0, bz - 1.6), Vector3(1.6, 1.2, 1.6), "field_dark"))
		# Low parapet on the roof for cover
		boxes.append(box(Vector3(bx, 4.4, bz + s * 3.8), Vector3(9, 0.8, 0.4), "field_dark"))

	# Cover lanes: long low walls east/west of the tower, mid-height walls north/south
	boxes.append(box(Vector3(-10, 1.25, 0), Vector3(0.6, 2.5, 10), "counter"))
	boxes.append(box(Vector3(10, 1.25, 0), Vector3(0.6, 2.5, 10), "counter"))
	boxes.append(box(Vector3(0, 0.9, -13), Vector3(12, 1.8, 0.6), "counter"))
	boxes.append(box(Vector3(0, 0.9, 13), Vector3(12, 1.8, 0.6), "counter"))

	# Scattered crates: jump-height hops and sightline breakers
	var crates := [
		Vector3(-18, 0.6, 10), Vector3(-16.6, 0.6, 10), Vector3(-17.3, 1.8, 10),
		Vector3(18, 0.6, -6), Vector3(19.2, 0.6, -6), Vector3(18.6, 1.8, -6),
		Vector3(-6, 0.6, -16), Vector3(6, 0.6, 16), Vector3(14, 0.6, 8), Vector3(-14, 0.6, -8),
		Vector3(-3, 0.6, 12), Vector3(3, 0.6, -12),
	]
	for i in crates.size():
		# A few crates carry the accent; most are the counter colour so the accent stays small.
		boxes.append(box(crates[i], Vector3(1.2, 1.2, 1.2), "accent" if i % 4 == 2 else "counter"))

	# A catwalk along the east wall at 3.6 m with step access at both ends
	boxes.append(box(Vector3(21.5, 3.4, 0), Vector3(3, 0.4, 24), "field_dark"))
	boxes.append(box(Vector3(21.5, 0.6, 13.5), Vector3(3, 1.2, 1.5), "field"))
	boxes.append(box(Vector3(21.5, 1.8, 12.5), Vector3(3, 1.2, 1.0), "field"))
	boxes.append(box(Vector3(21.5, 2.8, 11.7), Vector3(3, 1.2, 0.8), "field"))
	boxes.append(box(Vector3(21.5, 0.6, -13.5), Vector3(3, 1.2, 1.5), "field"))
	boxes.append(box(Vector3(21.5, 1.8, -12.5), Vector3(3, 1.2, 1.0), "field"))
	boxes.append(box(Vector3(21.5, 2.8, -11.7), Vector3(3, 1.2, 0.8), "field"))

	# Spawn points: {pos, yaw} — yaw faces the centre. Ground level, edges, one on each roof.
	# The SW and NE corners are buildings, so those spawns sit in the corridors past them.
	var spawns: Array = []
	var spawn_positions := [
		Vector3(-16, 0, 18), Vector3(20, 0, 16), Vector3(-20, 0, -16), Vector3(16, 0, -18),
		Vector3(0, 0, 17), Vector3(0, 0, -17), Vector3(-21, 0, 0), Vector3(21.5, 3.6, 0),
		Vector3(16, 4.0, -12), Vector3(-16, 4.0, 12),
	]
	for p in spawn_positions:
		var to_centre: Vector3 = Vector3(0, 0, 0) - p
		spawns.append({"pos": p, "yaw": atan2(-to_centre.x, -to_centre.z)})

	# Bot waypoints and edges. Every edge is a clear straight line at chest height (a unit test
	# checks each one against the boxes): the mid walls are rounded by their end points, the
	# two buildings by the corridors past them.
	var wp := [
		Vector3(0, 0, 9),        # 0 south of tower steps
		Vector3(0, 3.0, 0),      # 1 deck 1
		Vector3(0, 6.0, 0),      # 2 deck 2
		Vector3(-14, 0, 0),      # 3 west lane
		Vector3(14, 0, 0),       # 4 east lane
		Vector3(0, 0, -9),       # 5 north of tower
		Vector3(-16, 0, 18),     # 6 south corridor below the SW building
		Vector3(20, 0, 16),      # 7 SE corner
		Vector3(-20, 0, -16),    # 8 NW corner
		Vector3(16, 0, -18),     # 9 north corridor above the NE building
		Vector3(0, 0, 17),       # 10 south edge
		Vector3(0, 0, -17),      # 11 north edge
		Vector3(21.5, 3.6, 0),   # 12 catwalk middle
		Vector3(21.5, 0, 16),    # 13 catwalk south foot
		Vector3(21.5, 0, -16),   # 14 catwalk north foot
		Vector3(-8, 0, 8),       # 15 SW inner
		Vector3(8, 0, 8),        # 16 SE inner
		Vector3(-8, 0, -8),      # 17 NW inner
		Vector3(8, 0, -8),       # 18 NE inner
		Vector3(-7.5, 0, 13),    # 19 south wall, west end
		Vector3(7.5, 0, 13),     # 20 south wall, east end
		Vector3(-7.5, 0, -13),   # 21 north wall, west end
		Vector3(7.5, 0, -13),    # 22 north wall, east end
		Vector3(-22, 0, 2),      # 23 west edge, north of the SW building
		Vector3(0, 9.0, 0),      # 24 deck 3, the top of the tower
	]
	var edges := [
		[0, 1], [1, 2], [2, 24], [0, 15], [0, 16], [0, 19], [0, 20], [19, 10], [20, 10], [19, 15], [20, 16],
		[5, 17], [5, 18], [5, 21], [5, 22], [21, 11], [22, 11], [21, 17], [22, 18],
		[15, 3], [17, 3], [16, 4], [18, 4], [15, 17], [16, 18],
		[3, 23], [23, 8], [17, 8], [8, 11], [3, 8],
		[16, 7], [7, 10], [7, 13], [13, 12], [12, 14], [14, 9], [9, 11], [4, 7], [6, 10],
	]
	# Dressing (no collision): posters on the perimeter walls, lamps at the edges, road paint
	# down the lanes, hazard stripes on the tower's first deck. Accents stay small (STYLE §8).
	var decor: Array = []
	poster(decor, Vector3(-12, 3.2, -D / 2), Vector3(0, 0, 1), 3.0, 3.6, "poster_a", "accent")
	poster(decor, Vector3(9, 3.0, -D / 2), Vector3(0, 0, 1), 2.4, 3.0, "poster_b", "poster_a")
	poster(decor, Vector3(14, 3.2, D / 2), Vector3(0, 0, -1), 3.0, 3.6, "poster_b", "accent")
	poster(decor, Vector3(-8, 3.0, D / 2), Vector3(0, 0, -1), 2.4, 3.0, "poster_a", "poster_b")
	poster(decor, Vector3(-W / 2, 3.2, 6), Vector3(1, 0, 0), 3.0, 3.6, "accent", "poster_a")
	poster(decor, Vector3(W / 2, 3.2, -6), Vector3(-1, 0, 0), 3.0, 3.6, "poster_a", "poster_b")
	for lp in [Vector3(-22.5, 0, 6), Vector3(-22.5, 0, -6), Vector3(-6, 0, 18.5), Vector3(8, 0, -18.5), Vector3(12, 0, 18.5)]:
		lamp(decor, lp)
	for z in [-16.0, 16.0]:
		decor.append(decor_box(Vector3(0, 0.015, z), Vector3(30, 0.03, 0.25), "paper"))
	for x in [-19.0, 19.0]:
		decor.append(decor_box(Vector3(x, 0.015, 0), Vector3(0.25, 0.03, 24), "paper"))
	for i in 5:
		decor.append(decor_box(Vector3(-2.8 + i * 1.4, 3.02, 3.4), Vector3(0.7, 0.05, 0.2), "accent" if i % 2 == 0 else "paper"))
	# Railings (decor, no collision) so the tower reads as built: along the outer side of each
	# flight, both sides of the wide ground flight, and round the top deck except where the
	# stairs arrive.
	_stair_rail(decor, Vector3(0, 0, 7.65), Vector3(0, 0, -1), Vector3(1.25, 0, 0), 0.0)
	_stair_rail(decor, Vector3(0, 0, 7.65), Vector3(0, 0, -1), Vector3(-1.25, 0, 0), 0.0)
	_stair_rail(decor, Vector3(-1.95, 0, -4.0), Vector3(1, 0, 0), Vector3(0, 0, -0.52), 3.0)
	_stair_rail(decor, Vector3(3.0, 0, 1.95), Vector3(0, 0, -1), Vector3(0.52, 0, 0), 6.0)
	_rail(decor, Vector3(-2.5, 9.0, -2.5), Vector3(2.5, 9.0, -2.5))
	_rail(decor, Vector3(-2.5, 9.0, 2.5), Vector3(2.5, 9.0, 2.5))
	_rail(decor, Vector3(-2.5, 9.0, -2.5), Vector3(-2.5, 9.0, 2.5))
	_rail(decor, Vector3(2.5, 9.0, -0.3), Vector3(2.5, 9.0, 2.5))
	_rail(decor, Vector3(2.5, 9.0, -2.5), Vector3(2.5, 9.0, -1.2))
	# KING OF THE HILL spots (MINIGAMES.md §3): the tower top, both roofs, the catwalk, the south
	# and north lanes, the west and east lanes; a radius per spot so the hill fits its deck. The
	# roofs have no waypoints (the bots cannot climb the crates on purpose), so they are marked
	# bots=false and the bots roam while the hill is up there.
	var hills := [
		{"pos": Vector3(0, 9.0, 0), "radius": 2.3, "bots": true},
		{"pos": Vector3(-16, 4.0, 12), "radius": 3.0, "bots": false},
		{"pos": Vector3(16, 4.0, -12), "radius": 3.0, "bots": false},
		{"pos": Vector3(0, 0, 10.2), "radius": 2.6, "bots": true},
		{"pos": Vector3(0, 0, -10.2), "radius": 2.6, "bots": true},
		{"pos": Vector3(21.5, 3.6, 0), "radius": 2.2, "bots": true},
		{"pos": Vector3(-14, 0, 0), "radius": 2.8, "bots": true},
		{"pos": Vector3(14, 0, 0), "radius": 2.8, "bots": true},
	]
	return {"boxes": boxes, "spawns": spawns, "waypoints": wp, "edges": edges, "size": Vector2(W, D), "decor": decor, "hills": hills}


## A flight of four 0.75 m steps: `start` is the centre of the lowest step (y ignored), `dir` the
## horizontal direction of climb, `width` across the run, `base_y` the level it starts from.
## Each step is a solid block from that level up, so the flight has no underside to see.
static func _stairs(boxes: Array, start: Vector3, dir: Vector3, width: float, base_y: float, tone: String) -> void:
	for k in 4:
		var h := 0.75 * (k + 1)
		var c := start + dir * (0.9 * k)
		var size := Vector3(width, h, 0.9) if absf(dir.z) > 0.5 else Vector3(0.9, h, width)
		boxes.append(box(Vector3(c.x, base_y + h * 0.5, c.z), size, tone))


## A stepped handrail beside a flight: a post at every step's outer corner and a rail segment
## over each step, on the `side` of the run.
static func _stair_rail(decor: Array, start: Vector3, dir: Vector3, side: Vector3, base_y: float) -> void:
	for k in 4:
		var top := base_y + 0.75 * (k + 1)
		var c := start + dir * (0.9 * k) + side
		decor.append(decor_box(Vector3(c.x, top + 0.5, c.z), Vector3(0.08, 1.0, 0.08), "counter_dark"))
		var seg := Vector3(0.08, 0.06, 0.9) if absf(dir.z) > 0.5 else Vector3(0.9, 0.06, 0.08)
		decor.append(decor_box(Vector3(c.x, top + 0.97, c.z), seg, "counter_dark"))


## A level rail between two points on a deck edge, posts every 1.25 m.
static func _rail(decor: Array, a: Vector3, b: Vector3) -> void:
	var span := b - a
	var length := span.length()
	if length < 0.1:
		return
	var mid := (a + b) * 0.5
	var along_x := absf(span.x) > absf(span.z)
	decor.append(decor_box(mid + Vector3(0, 0.97, 0), Vector3(length, 0.06, 0.08) if along_x else Vector3(0.08, 0.06, length), "counter_dark"))
	var posts := maxi(2, int(length / 1.25) + 1)
	for k in posts:
		var p := a + span * (float(k) / float(posts - 1))
		decor.append(decor_box(p + Vector3(0, 0.5, 0), Vector3(0.08, 1.0, 0.08), "counter_dark"))
